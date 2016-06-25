//
//  SEPersistenceService.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import "SEPersistenceService.h"

#include <libkern/OSAtomic.h>
#import <CoreData/CoreData.h>

#import "SETools.h"
#import "SEConstants.h"
#import "NSArray+SEJSONExtensions.h"

#define PERSISTENCE_VERIFY_DATA_LOADED do { if ((_parent == nil && _dataLoadedFlag == 0) || (_parent != nil && ![_parent isInitialized])) THROW_INCONSISTENCY(nil); } while(0)

static inline BOOL PERSISTENCE_SHOULD_SAVE(SEPersistenceServiceSaveOptions options)
{
    return options == SEPersistenceServiceSaveAndPersist || options == SEPersistenceServiceSaveCurrentOnly;
}

static inline BOOL PERSISTENCE_SHOULD_SAVE_AND_PERSIST(SEPersistenceServiceImpl *parent, SEPersistenceServiceSaveOptions options)
{
    return (parent != nil && options == SEPersistenceServiceSaveAndPersist);
}

NSInteger const SEPersistenceServiceBlockOperationError = 2000;

@implementation SEPersistenceServiceImpl
{
    SEPersistenceServiceImpl *_parent;
    NSManagedObjectContext *_objectContext;
    volatile uint32_t _dataLoadedFlag;
}

- (instancetype)init
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithDataModel:(NSManagedObjectModel *)dataModel storePath:(NSString *)storePath
{
    self = [super init];
    if (self)
    {
        _dataLoadedFlag = 0;
        
        [self initializeCoreDataWithModel:dataModel storePath:storePath];
    }
    return self;
}

- (instancetype)initWithDataModelName:(NSString *)dataModelName storePath:(NSString *)storePath
{
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:dataModelName withExtension:@"momd"];
    NSManagedObjectModel *objectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    if (objectModel == nil) THROW_INVALID_PARAM(dataModelName, @{ NSLocalizedDescriptionKey: @"Could not initialize data model" });

    return [self initWithDataModel:objectModel storePath:storePath];
}

- (instancetype)initWithParentPersistenceService:(SEPersistenceServiceImpl *)parentPersistence concurrencyType:(NSManagedObjectContextConcurrencyType)concurrencyType
{
    if (parentPersistence == nil) THROW_INVALID_PARAM(parentPersistence, nil);
    
    self = [super init];
    if (self)
    {
        _parent = parentPersistence;
        _objectContext = [parentPersistence createChildContextWithConcurrencyType:concurrencyType verifyLoaded:NO];
    }
    return self;
}

- (void)initializeCoreDataWithModel:(NSManagedObjectModel *)objectModel storePath:(NSString *)storePath
{
    NSPersistentStoreCoordinator *storeCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:objectModel];
    NSManagedObjectContext *objectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [objectContext setPersistentStoreCoordinator:storeCoordinator];
    _objectContext = objectContext;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        NSURL *storeURL = [NSURL fileURLWithPath:storePath];
        
        NSDictionary *storeOptions = @{ NSMigratePersistentStoresAutomaticallyOption : @YES, NSInferMappingModelAutomaticallyOption : @YES };

        NSError *error = nil;
        NSPersistentStoreCoordinator *storeCoordinator = [_objectContext persistentStoreCoordinator];
        NSPersistentStore *store = [storeCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:storeOptions error:&error];
        if (store == nil)
        {
            NSString *reason = [NSString stringWithFormat:@"Error initializing PSC: %@\n%@", [error localizedDescription], [error userInfo]];
            THROW_INVALID_PARAMS(@{ NSLocalizedDescriptionKey: reason });
        }
        
        OSMemoryBarrier();
        _dataLoadedFlag = 1;
    });
}

#pragma mark - Service Interface - State

- (BOOL)isInitialized
{
    if (_parent != nil) return [_parent isInitialized];
    return _dataLoadedFlag != 0;
}

#pragma mark - Service Interface - Child Context

- (NSManagedObjectContext *)createChildContextWithConcurrencyType:(NSManagedObjectContextConcurrencyType)concurrencyType verifyLoaded:(BOOL)verifyLoaded
{
    if (verifyLoaded) PERSISTENCE_VERIFY_DATA_LOADED;
    NSManagedObjectContext *childContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:concurrencyType];
    [childContext setParentContext:_objectContext];
    return childContext;
}

- (id<SEPersistenceService>)createChildPersistenceServiceWithMainQueueConcurrency
{
    return [[SEPersistenceServiceImpl alloc] initWithParentPersistenceService:self concurrencyType:NSMainQueueConcurrencyType];
}

- (id<SEPersistenceService>)createChildPersistenceServiceWithPrivateQueueConcurrency
{
    return [[SEPersistenceServiceImpl alloc] initWithParentPersistenceService:self concurrencyType:NSPrivateQueueConcurrencyType];
}

- (NSManagedObjectContext *)createChildContextWithMainQueueConcurrency
{
    return [self createChildContextWithConcurrencyType:NSMainQueueConcurrencyType verifyLoaded:YES];
}

- (NSManagedObjectContext *)createChildContextWithPrivateQueueConcurrency
{
    return [self createChildContextWithConcurrencyType:NSPrivateQueueConcurrencyType verifyLoaded:YES];
}

#pragma mark - Service Interface - Creation of Individual Objects

- (void)createObjectOfType:(Class)type obtainPermanentId:(BOOL)obtainPermanentId initializer:(void (^)(__kindof NSManagedObject * _Nonnull))initializer saveOptions:(SEPersistenceServiceSaveOptions)saveOptions success:(void (^)())success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (type == nil || ![type isSubclassOfClass:[NSManagedObject class]]) THROW_INVALID_PARAM(type, nil);
    if (initializer == nil) THROW_INVALID_PARAM(initializer, nil);
    if ((success != nil || failure != nil) && completionQueue == nil) THROW_INVALID_PARAM(completionQueue, nil);
#endif
    
    NSString *entityName = [SEPersistenceServiceImpl entityNameForClass:type];
    BOOL shouldSave = PERSISTENCE_SHOULD_SAVE(saveOptions);
    BOOL shouldSaveToParent = PERSISTENCE_SHOULD_SAVE_AND_PERSIST(_parent, saveOptions);
    [_objectContext performBlock:^{
        NSError *error = nil;
        if ([self internalCreateAndSaveEntityWithClass:type name:entityName obtainPermanentId:obtainPermanentId initializer:initializer shouldSave:shouldSave error:&error])
        {
            if (shouldSaveToParent)
            {
                [_parent saveAllWithOptions:saveOptions success:success failure:failure completionQueue:completionQueue];
            }
            else
            {
                if (success != nil) dispatch_async(completionQueue, success);
            }
        }
        else
        {
            if (failure != nil) dispatch_async(completionQueue, ^{ failure(error); });
        }
    }];
}

- (BOOL)createAndWaitObjectOfType:(Class)type obtainPermanentId:(BOOL)obtainPermanentId initializer:(void (^)(__kindof NSManagedObject * _Nonnull))initializer saveOptions:(SEPersistenceServiceSaveOptions)saveOptions error:(NSError *__autoreleasing  _Nullable *)error
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (type == nil || ![type isSubclassOfClass:[NSManagedObject class]]) THROW_INVALID_PARAM(type, nil);
    if (initializer == nil) THROW_INVALID_PARAM(initializer, nil);
#endif
    
    NSString *entityName = [SEPersistenceServiceImpl entityNameForClass:type];
    __block BOOL result = NO;
    __block NSError *innerError = nil;
    BOOL shouldSave = PERSISTENCE_SHOULD_SAVE(saveOptions);
    [_objectContext performBlockAndWait:^{
        result = [self internalCreateAndSaveEntityWithClass:type name:entityName obtainPermanentId:obtainPermanentId initializer:initializer shouldSave:shouldSave error:&innerError];
    }];
    
    if (result)
    {
        if (PERSISTENCE_SHOULD_SAVE_AND_PERSIST(_parent, saveOptions))
        {
            result = [_parent saveAllAndWaitWithOptions:saveOptions error:error];
        }
    }
    else
    {
        if (error != nil) *error = innerError;
    }
    return result;
}

- (BOOL) internalCreateAndSaveEntityWithClass:(Class) type name:(NSString *)entityName obtainPermanentId:(BOOL)obtainPermanentId initializer:(void (^)(id _Nonnull))initializer shouldSave:(BOOL)shouldSave error:(NSError * __autoreleasing *)error
{
    NSEntityDescription *entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:_objectContext];
    NSManagedObject *model = [[type alloc] initWithEntity:entity insertIntoManagedObjectContext:_objectContext];
    
    if (obtainPermanentId)
    {
        BOOL obtained = [_objectContext obtainPermanentIDsForObjects:@[ model ] error:error];
        if (!obtained) return NO;
    }
    
    initializer(model);
    
    if (shouldSave) return [_objectContext save:error];
    
    if (error != nil) *error = nil;
    return YES;
}

#pragma mark - Creation Through Bulk Transform

- (void)createObjectsOfType:(Class)type byTransformingObjects:(NSArray *)objects withTransform:(BOOL (^)(id _Nonnull, __kindof NSManagedObject * _Nonnull))transform saveOptions:(SEPersistenceServiceSaveOptions)saveOptions success:(void (^)())success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (type == nil || ![type isSubclassOfClass:[NSManagedObject class]]) THROW_INVALID_PARAM(type, nil);
    if (objects == nil || objects.count == 0) THROW_INVALID_PARAM(objects, nil);
    if (transform == nil) THROW_INVALID_PARAM(transform, nil);
    if ((success != nil || failure != nil) && completionQueue == nil) THROW_INVALID_PARAM(completionQueue, nil);
#endif
    
    NSString *entityName = [SEPersistenceServiceImpl entityNameForClass:type];
    BOOL shouldSave = PERSISTENCE_SHOULD_SAVE(saveOptions);
    BOOL shouldSaveToParent = PERSISTENCE_SHOULD_SAVE_AND_PERSIST(_parent, saveOptions);
    [_objectContext performBlock:^{
        NSError *error = nil;
        if ([self internalCreateAndSaveEntitiesWithClass:type name:entityName objects:objects transform:transform shouldSave:shouldSave error:&error])
        {
            if (shouldSaveToParent)
            {
                [_parent saveAllWithOptions:saveOptions success:success failure:failure completionQueue:completionQueue];
            }
            else
            {
                if (success != nil) dispatch_async(completionQueue, success);
            }
        }
        else
        {
            if (failure != nil) dispatch_async(completionQueue, ^{ failure(error); });
        }
    }];
}

- (BOOL)createAndWaitObjectsOfType:(Class)type byTransformingObjects:(NSArray *)objects withTransform:(BOOL (^)(id __nonnull source, __kindof NSManagedObject * __nonnull target))transform saveOptions:(SEPersistenceServiceSaveOptions)saveOptions error:(NSError *__autoreleasing  _Nullable *)error
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (type == nil || ![type isSubclassOfClass:[NSManagedObject class]]) THROW_INVALID_PARAM(type, nil);
    if (objects == nil || objects.count == 0) THROW_INVALID_PARAM(objects, nil);
    if (transform == nil) THROW_INVALID_PARAM(transform, nil);
#endif
    
    NSString *entityName = [SEPersistenceServiceImpl entityNameForClass:type];
    __block BOOL result = NO;
    __block NSError *innerError = nil;
    BOOL shouldSave = PERSISTENCE_SHOULD_SAVE(saveOptions);
    [_objectContext performBlockAndWait:^{
        result = [self internalCreateAndSaveEntitiesWithClass:type name:entityName objects:objects transform:transform shouldSave:shouldSave error:&innerError];
    }];
    
    if (result)
    {
        if (PERSISTENCE_SHOULD_SAVE_AND_PERSIST(_parent, saveOptions))
        {
            result = [_parent saveAllAndWaitWithOptions:saveOptions error:error];
        }
    }
    else
    {
        if (error != nil) *error = innerError;
    }
    return result;
}

- (BOOL) internalCreateAndSaveEntitiesWithClass:(Class)type name:(NSString *)entityName objects:(NSArray *)objects transform:(nonnull BOOL (^)(id __nonnull source, __kindof NSManagedObject * __nonnull target))transform shouldSave:(BOOL)shouldSave error:(NSError * __autoreleasing *)error
{
    NSEntityDescription *entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:_objectContext];
    
    BOOL success = YES;
    @try
    {
        for (id object in objects)
        {
            NSManagedObject *model = [[type alloc] initWithEntity:entity insertIntoManagedObjectContext:_objectContext];
            success = transform(object, model);
            if (!success) break;
        }
    }
    @catch (NSException *exception)
    {
        success = NO;
        if (error != nil)
        {
            NSString *reason = [NSString stringWithFormat:@"Failed executing fetch processor: %@", exception];
            *error = [NSError errorWithDomain:SEErrorDomain code:SEPersistenceServiceBlockOperationError userInfo:@{ NSLocalizedDescriptionKey: reason }];
        }

    }

    if (!success)
    {
        [_objectContext rollback];
        return NO;
    }
    
    if (shouldSave) return [_objectContext save:error];
    
    if (error != nil) *error = nil;
    return YES;
}


#pragma mark - Service Interface - Save

- (void)saveAllWithOptions:(SEPersistenceServiceSaveOptions)saveOptions success:(void (^)())success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    PERSISTENCE_VERIFY_DATA_LOADED;
    
    BOOL shouldSaveToParent = PERSISTENCE_SHOULD_SAVE_AND_PERSIST(_parent, saveOptions);
    [_objectContext performBlock:^{
        if (!_objectContext.hasChanges)
        {
            if (success != nil) dispatch_async(completionQueue, success);
        }
        else
        {
            NSError *error = nil;
            BOOL result = [_objectContext save:&error];
            if (result)
            {
                if (shouldSaveToParent)
                {
                    [_parent saveAllWithOptions:saveOptions success:success failure:failure completionQueue:completionQueue];
                }
                else
                {
                    if (success != nil) dispatch_async(completionQueue, success);
                }
            }
            else
            {
                if (failure != nil) dispatch_async(completionQueue, ^{ failure(error); });
            }
        }
    }];
}

- (BOOL)saveAllAndWaitWithOptions:(SEPersistenceServiceSaveOptions)saveOptions error:(NSError *__autoreleasing  _Nullable *)error
{
    PERSISTENCE_VERIFY_DATA_LOADED;
    __block BOOL result = NO;
    __block NSError *innerError = nil;
    [_objectContext performBlockAndWait:^{
        if (!_objectContext.hasChanges) result = YES;
        else
        {
            result = [_objectContext save:&innerError];
        }
    }];
    
    if (result)
    {
        if (PERSISTENCE_SHOULD_SAVE_AND_PERSIST(_parent, saveOptions))
        {
            result = [_parent saveAllAndWaitWithOptions:saveOptions error:error];
        }
    }
    else
    {
        if (error != nil) *error = innerError;
    }
    return result;
}

#pragma mark - Service Interface - Fetch Read-only

- (void)fetchReadOnlyObjectsOfType:(Class)type fetchParameters:(SEFetchParameters *)fetchParameters fetchedObjectProcessor:(void (^)(NSArray<__kindof NSManagedObject *> * _Nonnull))fetchedProcessor success:(void (^)())success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (type == nil || ![type isSubclassOfClass:[NSManagedObject class]]) THROW_INVALID_PARAM(type, nil);
    if (fetchedProcessor == nil) THROW_INVALID_PARAM(fetchedProcessor, nil);
#endif

    NSString *entityName = [SEPersistenceServiceImpl entityNameForClass:type];
    
    [_objectContext performBlock:^{
        NSError *error = nil;
        BOOL result = [self internalFetchReadOnlyAndProcessWithName:entityName fetchParameters:fetchParameters fetchedObjectProcessor:fetchedProcessor error:&error];
        if (result)
        {
            if (success != nil) dispatch_async(completionQueue, success);
        }
        else
        {
            if (failure != nil) dispatch_async(completionQueue, ^{ failure(error); });
        }
    }];
}

- (BOOL)fetchReadOnlyAndWaitObjectsOfType:(Class)type fetchParameters:(SEFetchParameters *)fetchParameters fetchedObjectProcessor:(void (^)(NSArray<__kindof NSManagedObject *> * _Nonnull))fetchedProcessor error:(NSError *__autoreleasing  _Nullable *)error
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (type == nil || ![type isSubclassOfClass:[NSManagedObject class]]) THROW_INVALID_PARAM(type, nil);
    if (fetchedProcessor == nil) THROW_INVALID_PARAM(fetchedProcessor, nil);
#endif
    
    NSString *entityName = [SEPersistenceServiceImpl entityNameForClass:type];
    __block BOOL result = YES;
    __block NSError *innerError = nil;
    [_objectContext performBlockAndWait:^{
        result = [self internalFetchReadOnlyAndProcessWithName:entityName fetchParameters:fetchParameters fetchedObjectProcessor:fetchedProcessor error:&innerError];
    }];
    
    if (!result)
    {
        if (error != nil) *error = innerError;
    }
    return result;
}

- (void)fetchReadOnlyObjectsByIds:(NSArray<NSManagedObjectID *> *)objectIds fetchedObjectProcessor:(void (^)(NSArray<__kindof NSManagedObject *> * _Nonnull))fetchedProcessor success:(void (^)())success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (objectIds == nil || objectIds.count == 0 || ![objectIds verifyAllObjectsOfClass:[NSManagedObjectID class]]) THROW_INVALID_PARAM(objectIds, nil);
    if (fetchedProcessor == nil) THROW_INVALID_PARAM(fetchedProcessor, nil);
#endif

    [_objectContext performBlock:^{
        NSError *error = nil;
        BOOL result = [self internalFetchReadOnlyObjectsByIds:objectIds fetchedObjectProcessor:fetchedProcessor error:&error];
        if (result)
        {
            if (success != nil) dispatch_async(completionQueue, success);
        }
        else
        {
            if (failure != nil) dispatch_async(completionQueue, ^{ failure(error); });
        }
    }];
}

- (BOOL)fetchReadOnlyAndWaitObjectsByIds:(NSArray<NSManagedObjectID *> *)objectIds fetchedObjectProcessor:(void (^)(NSArray<__kindof NSManagedObject *> * _Nonnull))fetchedProcessor error:(NSError *__autoreleasing  _Nullable *)error
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (objectIds == nil || objectIds.count == 0 || ![objectIds verifyAllObjectsOfClass:[NSManagedObjectID class]]) THROW_INVALID_PARAM(objectIds, nil);
    if (fetchedProcessor == nil) THROW_INVALID_PARAM(fetchedProcessor, nil);
#endif
    
    __block BOOL result = YES;
    __block NSError *innerError = nil;
    [_objectContext performBlockAndWait:^{
        result = [self internalFetchReadOnlyObjectsByIds:objectIds fetchedObjectProcessor:fetchedProcessor error:&innerError];
    }];
    
    if (!result)
    {
        if (error != nil) *error = innerError;
    }
    return result;
}

- (void)fetchTransformObjectsOfType:(Class)type fetchParameters:(SEFetchParameters *)fetchParameters transform:(id  _Nonnull (^)(__kindof NSManagedObject * _Nonnull))transform success:(void (^)(NSArray * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (type == nil || ![type isSubclassOfClass:[NSManagedObject class]]) THROW_INVALID_PARAM(type, nil);
    if (transform == nil) THROW_INVALID_PARAM(transform, nil);
    if (success == nil) THROW_INVALID_PARAM(success, nil);
#endif
    
    NSString *entityName = [SEPersistenceServiceImpl entityNameForClass:type];
    
    [_objectContext performBlock:^{
        NSError *error = nil;
        NSArray *results = [self internalFetchTransformObjectsWithName:entityName fetchParameters:fetchParameters transform:transform error:&error];
        if (results)
        {
            if (success != nil) dispatch_async(completionQueue, ^{ success(results); });
        }
        else
        {
            if (failure != nil) dispatch_async(completionQueue, ^{ failure(error); });
        }
    }];

}

- (NSArray *)fetchAndWaitTransformObjectsOfType:(Class)type fetchParameters:(SEFetchParameters *)fetchParameters transform:(id  _Nonnull (^)(__kindof NSManagedObject * _Nonnull))transform error:(NSError *__autoreleasing  _Nullable *)error
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (type == nil || ![type isSubclassOfClass:[NSManagedObject class]]) THROW_INVALID_PARAM(type, nil);
    if (transform == nil) THROW_INVALID_PARAM(transform, nil);
#endif
    
    NSString *entityName = [SEPersistenceServiceImpl entityNameForClass:type];
    __block NSArray *results = nil;
    __block NSError *innerError = nil;
    [_objectContext performBlockAndWait:^{
        results = [self internalFetchTransformObjectsWithName:entityName fetchParameters:fetchParameters transform:transform error:&innerError];
    }];
    
    if (results == nil)
    {
        if (error != nil) *error = innerError;
    }
    return results;
}

- (NSFetchRequest *)createFetchRequestForEntityName:(NSString *)entityName fetchParameters:(SEFetchParameters *)fetchParameters includesValues:(BOOL)includesValues
{
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:_objectContext];
    fetchRequest.entity = entity;
    fetchRequest.includesPropertyValues = includesValues;
    
    if (fetchParameters != nil)
    {
        if (fetchParameters.predicate != nil) [fetchRequest setPredicate:fetchParameters.predicate];
        if (fetchParameters.sort != nil && fetchParameters.sort.count > 0) [fetchRequest setSortDescriptors:fetchParameters.sort];
        if (fetchParameters.fetchLimit > 0) fetchRequest.fetchLimit = fetchParameters.fetchLimit;
    }
    
    return fetchRequest;
}

- (BOOL)internalFetchReadOnlyAndProcessWithName:(NSString *)entityName fetchParameters:(SEFetchParameters *)fetchParameters  fetchedObjectProcessor:(void (^)(NSArray * _Nonnull))fetchedProcessor error:(NSError *__autoreleasing  _Nullable *)error
{
    NSFetchRequest *fetchRequest = [self createFetchRequestForEntityName:entityName fetchParameters:fetchParameters includesValues:YES];
    NSArray *fetchedObjects = [_objectContext executeFetchRequest:fetchRequest error:error];
    if (fetchedObjects == nil) return NO;
    
    BOOL result = YES;
    BOOL hadChanges = _objectContext.hasChanges;
    
    @try
    {
        fetchedProcessor(fetchedObjects);
    }
    @catch (NSException *exception)
    {
        result = NO;
        if (error != nil)
        {
            NSString *reason = [NSString stringWithFormat:@"Failed executing fetch processor: %@", exception];
            *error = [NSError errorWithDomain:SEErrorDomain code:SEPersistenceServiceBlockOperationError userInfo:@{ NSLocalizedDescriptionKey: reason }];
        }
    }
    
    // Maybe cannot prevent all changes but at least an obvious case. Also exclude a scenario when there were changes before.
    if (!hadChanges && _objectContext.hasChanges)
    {
#ifdef DEBUG
        THROW_INCONSISTENCY(@{ NSLocalizedDescriptionKey: @"Read-only fetch modified objects!!" });
#endif
        [_objectContext rollback];
        result = NO;
        if (error != nil) *error = [NSError errorWithDomain:SEErrorDomain code:SEPersistenceServiceBlockOperationError userInfo:@{ NSLocalizedDescriptionKey: @"Read-only fetch modified objects!!" }];
    }
    return result;
}

- (BOOL)internalFetchReadOnlyObjectsByIds:(NSArray<NSManagedObjectID *> *)objectIds fetchedObjectProcessor:(void (^)(NSArray * _Nonnull))fetchedProcessor error:(NSError *__autoreleasing  _Nullable *)error
{
    BOOL hadChanges = _objectContext.hasChanges;
    BOOL result = YES;
    NSError *innerError = nil;
    NSMutableArray *resultingObjects = [[NSMutableArray alloc] initWithCapacity:objectIds.count];
    for (NSManagedObjectID *objectId in objectIds)
    {
        NSManagedObject *object = [_objectContext existingObjectWithID:objectId error:&innerError];
        if (object == nil)
        {
            result = NO;
            break;
        }
        [resultingObjects addObject:object];
    }
    
    @try
    {
        fetchedProcessor(resultingObjects);
    }
    @catch (NSException *exception)
    {
        result = NO;
        if (error != nil)
        {
            NSString *reason = [NSString stringWithFormat:@"Failed executing fetch processor: %@", exception];
            *error = [NSError errorWithDomain:SEErrorDomain code:SEPersistenceServiceBlockOperationError userInfo:@{ NSLocalizedDescriptionKey: reason }];
        }
    }
    
    if (!hadChanges && _objectContext.hasChanges)
    {
#ifdef DEBUG
        THROW_INCONSISTENCY(@{ NSLocalizedDescriptionKey: @"Read-only fetch modified objects!!" });
#endif
        [_objectContext rollback];
        result = NO;
        innerError = [NSError errorWithDomain:SEErrorDomain code:SEPersistenceServiceBlockOperationError userInfo:@{ NSLocalizedDescriptionKey: @"Read-only fetch modified objects!!" }];
    }

    if (!result)
    {
        if (error != nil) *error = innerError;
    }
    
    return result;
}

- (NSArray *)internalFetchTransformObjectsWithName:(NSString *)entityName fetchParameters:(SEFetchParameters *)fetchParameters transform:(id  _Nonnull (^)(__kindof NSManagedObject * _Nonnull))transform error:(NSError *__autoreleasing  _Nullable *)error
{
    NSFetchRequest *fetchRequest = [self createFetchRequestForEntityName:entityName fetchParameters:fetchParameters includesValues:YES];
    NSArray *fetchedObjects = [_objectContext executeFetchRequest:fetchRequest error:error];
    if (fetchedObjects == nil) return nil;
    
    BOOL hadChanges = _objectContext.hasChanges;
    NSMutableArray *results = [[NSMutableArray alloc] initWithCapacity:fetchedObjects.count];
    NSError *innerError = nil;
    
    @try
    {
        for (NSManagedObject *source in fetchedObjects)
        {
            id transformedObject = transform(source);
            if (transformedObject == nil)
            {
                innerError = [NSError errorWithDomain:SEErrorDomain code:SEPersistenceServiceBlockOperationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed transforming an object" }];
                break;
            }
            
            [results addObject:transformedObject];
        }
    }
    @catch (NSException *exception)
    {
        NSString *reason = [NSString stringWithFormat:@"Failed executing fetch processor: %@", exception];
        innerError = [NSError errorWithDomain:SEErrorDomain code:SEPersistenceServiceBlockOperationError userInfo:@{ NSLocalizedDescriptionKey: reason }];
    }
    
    // Maybe cannot prevent all changes but at least an obvious case. Also exclude a scenario when there were changes before.
    if (!hadChanges && _objectContext.hasChanges)
    {
#ifdef DEBUG
        THROW_INCONSISTENCY(@{ NSLocalizedDescriptionKey: @"Read-only fetch modified objects!!" });
#endif
        [_objectContext rollback];
        innerError = [NSError errorWithDomain:SEErrorDomain code:SEPersistenceServiceBlockOperationError userInfo:@{ NSLocalizedDescriptionKey: @"Read-only fetch modified objects!!" }];
    }
    
    if (innerError != nil)
    {
        if (error != nil) *error = innerError;
        return nil;
    }

    return [results copy];
}

#pragma mark - Fetch - Generic

- (void)fetchObjectsOfType:(Class)type fetchParameters:(SEFetchParameters *)fetchParameters fetchedObjectProcessor:(SEPersistenceServiceSaveOptions (^)(NSArray<__kindof NSManagedObject *> * _Nonnull))fetchedProcessor success:(void (^)())success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (type == nil || ![type isSubclassOfClass:[NSManagedObject class]]) THROW_INVALID_PARAM(type, nil);
    if (fetchedProcessor == nil) THROW_INVALID_PARAM(fetchedProcessor, nil);
#endif

    NSString *entityName = [SEPersistenceServiceImpl entityNameForClass:type];

    [_objectContext performBlock:^{
        NSError *error = nil;
        SEPersistenceServiceSaveOptions saveOptions = SEPersistenceServiceDontSave;
        BOOL result = [self internalFetchAndProcessWithName:entityName fetchParameters:fetchParameters fetchedObjectProcessor:fetchedProcessor error:&error saveOptionsOut:&saveOptions];
        if (result)
        {
            if (PERSISTENCE_SHOULD_SAVE_AND_PERSIST(_parent,saveOptions))
            {
                [_parent saveAllWithOptions:saveOptions success:success failure:failure completionQueue:completionQueue];
            }
            else
            {
                if (success != nil) dispatch_async(completionQueue, success);
            }
        }
        else
        {
            if (failure != nil) dispatch_async(completionQueue, ^{ failure(error); });
        }
    }];
}

- (BOOL)fetchAndWaitObjectsOfType:(Class)type fetchParameters:(SEFetchParameters *)fetchParameters fetchedObjectProcessor:(SEPersistenceServiceSaveOptions (^)(NSArray<__kindof NSManagedObject *> * _Nonnull))fetchedProcessor error:(NSError *__autoreleasing  _Nullable *)error
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (type == nil || ![type isSubclassOfClass:[NSManagedObject class]]) THROW_INVALID_PARAM(type, nil);
    if (fetchedProcessor == nil) THROW_INVALID_PARAM(fetchedProcessor, nil);
#endif

    NSString *entityName = [SEPersistenceServiceImpl entityNameForClass:type];
    __block BOOL result = YES;
    __block NSError *innerError = nil;
    __block SEPersistenceServiceSaveOptions saveOptions = SEPersistenceServiceDontSave;
    [_objectContext performBlockAndWait:^{
        result = [self internalFetchAndProcessWithName:entityName fetchParameters:fetchParameters fetchedObjectProcessor:fetchedProcessor error:&innerError saveOptionsOut:&saveOptions];
    }];

    if (result)
    {
        if (PERSISTENCE_SHOULD_SAVE_AND_PERSIST(_parent, saveOptions))
        {
            result = [_parent saveAllAndWaitWithOptions:saveOptions error:error];
        }
    }
    else
    {
        if (error != nil) *error = innerError;
    }
    return result;
}

- (void)fetchObjectsByIds:(NSArray<NSManagedObjectID *> *)objectIds fetchedObjectProcessor:(SEPersistenceServiceSaveOptions (^)(NSArray<__kindof NSManagedObject *> * _Nonnull))fetchedProcessor success:(void (^)())success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (objectIds == nil || objectIds.count == 0 || ![objectIds verifyAllObjectsOfClass:[NSManagedObjectID class]]) THROW_INVALID_PARAM(objectIds, nil);
    if (fetchedProcessor == nil) THROW_INVALID_PARAM(fetchedProcessor, nil);
#endif

    [_objectContext performBlock:^{
        NSError *error = nil;
        SEPersistenceServiceSaveOptions saveOptions = SEPersistenceServiceDontSave;
        BOOL result = [self internalFetchAndProcessObjectsByIds:objectIds fetchedObjectProcessor:fetchedProcessor error:&error saveOptionsOut:&saveOptions];
        if (result)
        {
            if (PERSISTENCE_SHOULD_SAVE_AND_PERSIST(_parent, saveOptions))
            {
                [_parent saveAllWithOptions:saveOptions success:success failure:failure completionQueue:completionQueue];
            }
            else
            {
                if (success != nil) dispatch_async(completionQueue, success);
            }
        }
        else
        {
            if (failure != nil) dispatch_async(completionQueue, ^{ failure(error); });
        }
    }];

}

- (BOOL)fetchAndWaitObjectsByIds:(NSArray<NSManagedObjectID *> *)objectIds fetchedObjectProcessor:(SEPersistenceServiceSaveOptions (^)(NSArray<__kindof NSManagedObject *> * _Nonnull))fetchedProcessor error:(NSError *__autoreleasing  _Nullable *)error
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (objectIds == nil || objectIds.count == 0 || ![objectIds verifyAllObjectsOfClass:[NSManagedObjectID class]]) THROW_INVALID_PARAM(objectIds, nil);
    if (fetchedProcessor == nil) THROW_INVALID_PARAM(fetchedProcessor, nil);
#endif

    __block BOOL result = YES;
    __block NSError *innerError = nil;
    __block SEPersistenceServiceSaveOptions saveOptions = SEPersistenceServiceDontSave;
    [_objectContext performBlockAndWait:^{
        result = [self internalFetchAndProcessObjectsByIds:objectIds fetchedObjectProcessor:fetchedProcessor error:&innerError saveOptionsOut:&saveOptions];
    }];
    
    if (result)
    {
        if (PERSISTENCE_SHOULD_SAVE_AND_PERSIST(_parent, saveOptions))
        {
            result = [_parent saveAllAndWaitWithOptions:saveOptions error:error];
        }
    }
    else
    {
        if (error != nil) *error = innerError;
    }
    return result;
}

- (BOOL)internalFetchAndProcessWithName:(NSString *)entityName fetchParameters:(SEFetchParameters *)fetchParameters fetchedObjectProcessor:(SEPersistenceServiceSaveOptions (^)(NSArray * _Nonnull))fetchedProcessor error:(NSError *__autoreleasing  _Nullable *)error saveOptionsOut:(SEPersistenceServiceSaveOptions *)saveOptionsOut
{
#ifdef DEBUG
    if (saveOptionsOut == nil) THROW_INVALID_PARAM(saveOptionsOut, nil);
#endif
    
    NSFetchRequest *fetchRequest = [self createFetchRequestForEntityName:entityName fetchParameters:fetchParameters includesValues:YES];
    NSArray *fetchedObjects = [_objectContext executeFetchRequest:fetchRequest error:error];
    if (fetchedObjects == nil) return NO;

    BOOL result = YES;
    BOOL save = NO;
    
    @try
    {
        SEPersistenceServiceSaveOptions saveOptions = fetchedProcessor(fetchedObjects);
        save = PERSISTENCE_SHOULD_SAVE(saveOptions);
        *saveOptionsOut = saveOptions;
    }
    @catch (NSException *exception)
    {
        result = NO;
        if (error != nil)
        {
            NSString *reason = [NSString stringWithFormat:@"Failed executing fetch processor: %@", exception];
            *error = [NSError errorWithDomain:SEErrorDomain code:SEPersistenceServiceBlockOperationError userInfo:@{ NSLocalizedDescriptionKey: reason }];
        }
    }
    
    if (save && _objectContext.hasChanges)
    {
        result = [_objectContext save:error];
    }
    return result;
}

- (BOOL)internalFetchAndProcessObjectsByIds:(NSArray<NSManagedObjectID *> *)objectIds fetchedObjectProcessor:(SEPersistenceServiceSaveOptions (^)(NSArray * _Nonnull))fetchedProcessor error:(NSError *__autoreleasing  _Nullable *)error saveOptionsOut:(SEPersistenceServiceSaveOptions *)saveOptionsOut
{
#ifdef DEBUG
    if (saveOptionsOut == nil) THROW_INVALID_PARAM(saveOptionsOut, nil);
#endif
    
    BOOL result = YES;
    NSError *innerError = nil;
    NSMutableArray *resultingObjects = [[NSMutableArray alloc] initWithCapacity:objectIds.count];
    for (NSManagedObjectID *objectId in objectIds)
    {
        NSManagedObject *object = [_objectContext existingObjectWithID:objectId error:&innerError];
        if (object == nil)
        {
            result = NO;
            break;
        }
        [resultingObjects addObject:object];
    }
    
    BOOL save = NO;
    @try
    {
        SEPersistenceServiceSaveOptions saveOptions = fetchedProcessor(resultingObjects);
        save = PERSISTENCE_SHOULD_SAVE(saveOptions);
        *saveOptionsOut = saveOptions;
    }
    @catch (NSException *exception)
    {
        result = NO;
        
        NSString *reason = [NSString stringWithFormat:@"Failed executing fetch processor: %@", exception];
        innerError = [NSError errorWithDomain:SEErrorDomain code:SEPersistenceServiceBlockOperationError userInfo:@{ NSLocalizedDescriptionKey: reason }];
    }
    
    if (result)
    {
        if (save && _objectContext.hasChanges)
        {
            result = [_objectContext save:&innerError];
        }
    }
    else
    {
        if (error != nil) *error = innerError;
    }
    return result;
}


#pragma mark - Service Interface - Delete

- (void)deleteObjectsOfType:(Class)type fetchParameters:(SEFetchParameters *)fetchParameters saveOptions:(SEPersistenceServiceSaveOptions)saveOptions success:(void (^)())success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (type == nil || ![type isSubclassOfClass:[NSManagedObject class]]) THROW_INVALID_PARAM(type, nil);
#endif

    BOOL shouldSave = PERSISTENCE_SHOULD_SAVE(saveOptions);
    BOOL shouldSaveToParent = PERSISTENCE_SHOULD_SAVE_AND_PERSIST(_parent, saveOptions);
    NSString *entityName = [SEPersistenceServiceImpl entityNameForClass:type];
    [_objectContext performBlock:^{
        NSError *error = nil;
        BOOL result = [self internalDeleteObjectsWithName:entityName fetchParameters:fetchParameters shouldSave:shouldSave error:&error];
        if (result)
        {
            if (shouldSaveToParent)
            {
                [_parent saveAllWithOptions:saveOptions success:success failure:failure completionQueue:completionQueue];
            }
            else
            {
                if (success != nil) dispatch_async(completionQueue, success);
            }
        }
        else
        {
            if (failure != nil) dispatch_async(completionQueue, ^{ failure(error); });
        }

    }];
}

- (BOOL)deleteObjectsAndWaitOfType:(Class)type fetchParameters:(SEFetchParameters *)fetchParameters saveOptions:(SEPersistenceServiceSaveOptions)saveOptions error:(NSError *__autoreleasing  _Nullable *)error
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (type == nil || ![type isSubclassOfClass:[NSManagedObject class]]) THROW_INVALID_PARAM(type, nil);
#endif

    BOOL shouldSave = PERSISTENCE_SHOULD_SAVE(saveOptions);
    NSString *entityName = [SEPersistenceServiceImpl entityNameForClass:type];
    __block BOOL result = YES;
    __block NSError *innerError = nil;

    [_objectContext performBlockAndWait:^{
        result = [self internalDeleteObjectsWithName:entityName fetchParameters:fetchParameters shouldSave:shouldSave error:&innerError];
    }];
    
    if (result)
    {
        if (PERSISTENCE_SHOULD_SAVE_AND_PERSIST(_parent, saveOptions))
        {
            result = [_parent saveAllAndWaitWithOptions:saveOptions error:error];
        }
    }
    else
    {
        if (error != nil) *error = innerError;
    }
    return result;
}

- (void)deleteObjectsByIds:(NSArray<NSManagedObjectID *> *)objectIds saveOptions:(SEPersistenceServiceSaveOptions)saveOptions success:(void (^)())success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    PERSISTENCE_VERIFY_DATA_LOADED;
#ifdef DEBUG
    if (objectIds == nil || objectIds.count == 0 || ![objectIds verifyAllObjectsOfClass:[NSManagedObjectID class]]) THROW_INVALID_PARAM(objectIds, nil);
#endif
    
    BOOL shouldSave = PERSISTENCE_SHOULD_SAVE(saveOptions);
    BOOL shouldSaveToParent = PERSISTENCE_SHOULD_SAVE_AND_PERSIST(_parent, saveOptions);
    [_objectContext performBlock:^{
        NSError *error = nil;
        BOOL result = [self internalDeleteObjectsByIds:objectIds shouldSave:shouldSave error:&error];
        if (result)
        {
            if (shouldSaveToParent)
            {
                [_parent saveAllWithOptions:saveOptions success:success failure:failure completionQueue:completionQueue];
            }
            else
            {
                if (success != nil) dispatch_async(completionQueue, success);
            }
        }
        else
        {
            if (failure != nil) dispatch_async(completionQueue, ^{ failure(error); });
        }
        
    }];
}

- (BOOL)deleteObjectsAndWaitByIds:(NSArray<NSManagedObjectID *> *)objectIds saveOptions:(SEPersistenceServiceSaveOptions)saveOptions error:(NSError *__autoreleasing  _Nullable *)error
{
#ifdef DEBUG
    if (objectIds == nil || objectIds.count == 0 || ![objectIds verifyAllObjectsOfClass:[NSManagedObjectID class]]) THROW_INVALID_PARAM(objectIds, nil);
#endif
 
    BOOL shouldSave = PERSISTENCE_SHOULD_SAVE(saveOptions);
    __block BOOL result = YES;
    __block NSError *innerError = nil;
    
    [_objectContext performBlockAndWait:^{
        result = [self internalDeleteObjectsByIds:objectIds shouldSave:shouldSave error:&innerError];
    }];
    
    if (result)
    {
        if (PERSISTENCE_SHOULD_SAVE_AND_PERSIST(_parent, saveOptions))
        {
            result = [_parent saveAllAndWaitWithOptions:saveOptions error:error];
        }
    }
    else
    {
        if (error != nil) *error = innerError;
    }
    return result;
}

- (BOOL)internalDeleteObjectsWithName:(NSString *)entityName fetchParameters:(SEFetchParameters *)fetchParameters shouldSave:(BOOL)shouldSave error:(NSError *__autoreleasing  _Nullable *)error
{
    NSFetchRequest *fetchRequest = [self createFetchRequestForEntityName:entityName fetchParameters:fetchParameters includesValues:NO];
    fetchRequest.returnsObjectsAsFaults = YES;
    
    NSArray *fetchedObjects = [_objectContext executeFetchRequest:fetchRequest error:error];
    if (fetchedObjects == nil) return NO;

    for (NSManagedObject *object in fetchedObjects)
    {
        [_objectContext deleteObject:object];
    }
    
    if (!shouldSave) return YES;
    
    return [_objectContext save:error];
}

- (BOOL)internalDeleteObjectsByIds:(NSArray<NSManagedObjectID *> *)objectIds shouldSave:(BOOL)shouldSave error:(NSError *__autoreleasing  _Nullable *)error
{
    NSError *innerError = nil;
    BOOL result = YES;
    // first find all objects to reduce the chance that some will be deleted before an error
    NSMutableArray *actualObjects = [[NSMutableArray alloc] initWithCapacity:objectIds.count];
    for (NSManagedObjectID *objectId in objectIds)
    {
        NSManagedObject *object = [_objectContext existingObjectWithID:objectId error:&innerError];
        if (object != nil) [actualObjects addObject:object];
        else
        {
            result = NO;
            break;
        }
    }
    
    if (!result)
    {
        if (error != nil) *error = innerError;
        return NO;
    }
    
    for (NSManagedObject *foundObject in actualObjects)
    {
        [_objectContext deleteObject:foundObject];
    }
    
    if (!shouldSave) return YES;
    
    return [_objectContext save:error];
}


#pragma mark - Service Interface - Rollback

- (void)rollbackWithCompletion:(void (^)())completion completionQueue:(dispatch_queue_t)completionQueue
{
    PERSISTENCE_VERIFY_DATA_LOADED;
    [_objectContext performBlock:^{
        [_objectContext rollback];
        if (completion != nil) dispatch_async(completionQueue, ^{ completion(); });
    }];
}

- (void)rollbackAndWait
{
    PERSISTENCE_VERIFY_DATA_LOADED;
    [_objectContext performBlockAndWait:^{
        [_objectContext rollback];
    }];
}

#pragma mark - Naming

+ (NSString *)entityNameForClass:(Class)type
{
    id klass = type;
    if ([klass respondsToSelector:@selector(entityName)])
    {
        return [klass entityName];
    }
    else
    {
        return NSStringFromClass(type);
    }
}

@end
