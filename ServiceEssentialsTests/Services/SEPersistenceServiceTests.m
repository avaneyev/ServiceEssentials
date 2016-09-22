//
//  SEPersistenceServiceTests.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "SEPersistenceService.h"

@interface SEPersistenceServiceTests : XCTestCase

@end

@interface SEPersistenceServiceTestModel : NSManagedObject
@property (nonatomic, readwrite, strong, nullable) NSNumber *identifierAttribute;
@property (nonatomic, readwrite, strong, nullable) NSString *firstAttribute;
@property (nonatomic, readwrite, strong, nullable) NSNumber *secondAttribute;
@end

@implementation SEPersistenceServiceTestModel
@dynamic identifierAttribute;
@dynamic firstAttribute;
@dynamic secondAttribute;
@end

@implementation SEPersistenceServiceTests
{
    NSString *_persistentStorePath;
    NSManagedObjectModel *_objectModel;
}

- (void)setUp
{
    [super setUp];
    _objectModel = nil;
    
    // Set up the core data stack programmatically
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    NSString *storePath = [documentsDirectory stringByAppendingPathComponent:@"SEPersistenceTest"];
    _persistentStorePath = storePath;

    // first, clear out the store directory
    [SEPersistenceServiceTests clearOutDirectoryContents:storePath createDirectoryIfNeeded:YES];
    
    // then, create a programmatic data model
    
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];

    NSEntityDescription *entity = [[NSEntityDescription alloc] init];
    [entity setName:@"PersistenceServiceTestModel"];
    [entity setManagedObjectClassName:NSStringFromClass([SEPersistenceServiceTestModel class])];
    
    NSMutableArray *properties = [NSMutableArray array];
    
    NSAttributeDescription *identifierAttribute = [[NSAttributeDescription alloc] init];
    [identifierAttribute setName:@"identifierAttribute"];
    [identifierAttribute setAttributeType:NSInteger64AttributeType];
    [identifierAttribute setOptional:NO];
    [identifierAttribute setIndexed:YES];
    [properties addObject:identifierAttribute];

    NSAttributeDescription *firstAttribute = [[NSAttributeDescription alloc] init];
    [firstAttribute setName:@"firstAttribute"];
    [firstAttribute setAttributeType:NSStringAttributeType];
    [firstAttribute setOptional:NO];
    [firstAttribute setIndexed:YES];
    [properties addObject:firstAttribute];

    NSAttributeDescription *secondAttribute = [[NSAttributeDescription alloc] init];
    [secondAttribute setName:@"secondAttribute"];
    [secondAttribute setAttributeType:NSInteger64AttributeType];
    [secondAttribute setOptional:YES];
    [secondAttribute setIndexed:NO];
    [properties addObject:secondAttribute];
    
    [entity setProperties:properties];
    [model setEntities:@[ entity ]];
    _objectModel = model;
    
    XCTAssertNotNil(_objectModel);
}

- (void)tearDown
{
    [SEPersistenceServiceTests clearOutDirectoryContents:_persistentStorePath createDirectoryIfNeeded:NO];

    [super tearDown];
}

+ (void)clearOutDirectoryContents:(NSString *)directory createDirectoryIfNeeded:(BOOL)createDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    BOOL isDirectory = NO;
    NSError *error = nil;
    if (![fileManager fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory)
    {
        if (createDirectory) [fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
    }
    else
    {
        NSArray *contents = [fileManager contentsOfDirectoryAtPath:directory error:&error];
        if (contents != nil)
        {
            for (NSString *fileName in contents)
            {
                NSString *file = [directory stringByAppendingPathComponent:fileName];
                [fileManager removeItemAtPath:file error:&error];
            }
        }
    }
}

- (SEPersistenceServiceImpl *)createInitializedService
{
    NSDate *dateStart = [NSDate date];
    NSTimeInterval timeElapsed;

    NSString *storeFilePath = [_persistentStorePath stringByAppendingPathComponent:@"test_file.sqlite"];
    BOOL initialized = NO;
    
    SEPersistenceServiceImpl *persistenceService = [[SEPersistenceServiceImpl alloc] initWithDataModel:_objectModel storePath:storeFilePath];
    
    do
    {
        [NSThread sleepForTimeInterval:0.01];
        initialized = [persistenceService isInitialized];
        timeElapsed = -[dateStart timeIntervalSinceNow];
    } while (!initialized && (timeElapsed < 5));
    
    XCTAssert(initialized, @"Must initialize persistence!");

    if (!initialized) return nil;
    
    return persistenceService;
}

#pragma mark - Actual tests - Creation & Fetch

- (void)testInitializationSucceeds
{
    SEPersistenceServiceImpl *persistenceService = [self createInitializedService];
    
    XCTAssertNotNil(persistenceService, @"Must initialize persistence!");
}

- (void)testCreateObjectProducesAnObjectSynchronously
{
    NSNumber *const IdentifierValue = @(10);
    SEPersistenceServiceImpl *persistenceService = [self createInitializedService];
    
    NSError *error = nil;
    BOOL result = [persistenceService createAndWaitObjectOfType:[SEPersistenceServiceTestModel class] obtainPermanentId:NO initializer:^(SEPersistenceServiceTestModel *  _Nonnull instance) {
        instance.identifierAttribute = IdentifierValue;
        instance.firstAttribute = @"Value";
        instance.secondAttribute = @(2);
    } saveOptions:SEPersistenceServiceSaveCurrentOnly error:&error];
    
    XCTAssertTrue(result, @"Creation should succeed");
    XCTAssertNil(error, @"Error should be nil");
    
    // now check that the object is there
    __block volatile NSUInteger count = 0;
    __block volatile NSNumber *identifier = nil;
    result = [persistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil  fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
        SEPersistenceServiceTestModel *model = objects.firstObject;
        identifier = model.identifierAttribute;
    } error:&error];
    
    XCTAssertTrue(result, @"Fetch should succeed");
    XCTAssertNil(error, @"Error should be nil");
    XCTAssert(1 == count, @"Object count");
    XCTAssertEqualObjects(IdentifierValue, identifier);
}

- (void)testCreateObjectProducesAnObjectAsync
{
    NSNumber *const IdentifierValue = @(789);
    SEPersistenceServiceImpl *persistenceService = [self createInitializedService];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    __block volatile BOOL success = NO;
    __block volatile NSError *outError = nil;
    __block volatile NSNumber *identifier = nil;
    __block volatile NSUInteger count = 0;
    [persistenceService createObjectOfType:[SEPersistenceServiceTestModel class] obtainPermanentId:NO initializer:^(SEPersistenceServiceTestModel * _Nonnull instance) {
        instance.identifierAttribute = IdentifierValue;
        instance.firstAttribute = @"Value";
        instance.secondAttribute = @(2);
    } saveOptions:SEPersistenceServiceSaveCurrentOnly success:^{
        [persistenceService fetchReadOnlyObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
            count = objects.count;
            SEPersistenceServiceTestModel *model = objects.firstObject;
            identifier = model.identifierAttribute;
        } success:^{
            success = YES;
            dispatch_semaphore_signal(semaphore);
        } failure:^(NSError * _Nonnull error) {
            success = NO;
            outError = error;
            dispatch_semaphore_signal(semaphore);
        } completionQueue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)];
    } failure:^(NSError * _Nonnull error) {
        success = NO;
        outError = error;
        dispatch_semaphore_signal(semaphore);
    } completionQueue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)];
    
    long result = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC));
    
    XCTAssertEqual(0, result);
    XCTAssertTrue(success);
    XCTAssertNil(outError);
    XCTAssert(1 == count);
    XCTAssertEqualObjects(IdentifierValue, identifier);
}

- (void)testCreateBulkObjectsSynchronously
{
    NSArray *newObjectIds = @[ @10, @20, @30 ];
    
    SEPersistenceServiceImpl *persistenceService = [self createInitializedService];
    
    NSError *error = nil;
    BOOL result = [persistenceService createAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] byTransformingObjects:newObjectIds withTransform:^BOOL(NSNumber * _Nonnull source, SEPersistenceServiceTestModel * _Nonnull target) {
        target.identifierAttribute = source;
        target.firstAttribute = @"Value";
        target.secondAttribute = @(2);
        return YES;
    } saveOptions:SEPersistenceServiceSaveCurrentOnly error:&error];
    
    XCTAssertTrue(result, @"Creation should succeed");
    XCTAssertNil(error, @"Error should be nil");
    
    // now check that the object is there
    __block volatile NSUInteger count = 0;
    
    NSMutableSet *identifiers = [[NSMutableSet alloc] init];
    result = [persistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil  fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
        for (SEPersistenceServiceTestModel *model in objects) [identifiers addObject:model.identifierAttribute];
    } error:&error];
    
    XCTAssertTrue(result, @"Fetch should succeed");
    XCTAssertNil(error, @"Error should be nil");
    XCTAssert(3 == count, @"Object count");
    XCTAssertTrue([identifiers isEqualToSet:[NSSet setWithArray:newObjectIds]]);
}

- (void)testCreateBulkFetchBulkObjectsSynchronously
{
    NSArray *newObjectIds = @[ @10, @20, @30 ];
    
    SEPersistenceServiceImpl *persistenceService = [self createInitializedService];
    
    NSError *error = nil;
    BOOL result = [persistenceService createAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] byTransformingObjects:newObjectIds withTransform:^BOOL(NSNumber * _Nonnull source, SEPersistenceServiceTestModel * _Nonnull target) {
        target.identifierAttribute = source;
        target.firstAttribute = @"Value";
        target.secondAttribute = @(2);
        return YES;
    } saveOptions:SEPersistenceServiceSaveCurrentOnly error:&error];
    
    XCTAssertTrue(result, @"Creation should succeed");
    XCTAssertNil(error, @"Error should be nil");
    
    NSArray *identifiers = [persistenceService fetchAndWaitTransformObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil transform:^id _Nonnull(__kindof SEPersistenceServiceTestModel * _Nonnull source) {
        return source.identifierAttribute;
    } error:&error];
    
    XCTAssertTrue(result, @"Fetch should succeed");
    XCTAssertNil(error, @"Error should be nil");
    XCTAssertEqual(3, identifiers.count, @"Object count");
    XCTAssertTrue([[NSSet setWithArray:identifiers] isEqualToSet:[NSSet setWithArray:newObjectIds]]);
}

- (void)testCreateBulkFetchBulkAsynchronously
{
    NSArray *newObjectIds = @[ @50, @61, @77 ];
    SEPersistenceServiceImpl *persistenceService = [self createInitializedService];
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    __block volatile BOOL success = NO;
    __block volatile NSError *outError = nil;
    __block volatile NSArray *outIdentifiers = nil;
    
    [persistenceService createObjectsOfType:[SEPersistenceServiceTestModel class] byTransformingObjects:newObjectIds withTransform:^BOOL(NSNumber * _Nonnull source, SEPersistenceServiceTestModel * _Nonnull target) {
        target.identifierAttribute = source;
        target.firstAttribute = @"Value";
        target.secondAttribute = source;
        return YES;
    } saveOptions:SEPersistenceServiceSaveCurrentOnly success:^{
        [persistenceService fetchTransformObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil transform:^id _Nonnull(SEPersistenceServiceTestModel * _Nonnull source) {
            return source.identifierAttribute;
        } success:^(NSArray * _Nonnull results) {
            outIdentifiers = results;
            success = YES;
            dispatch_semaphore_signal(semaphore);
        } failure:^(NSError * _Nonnull error) {
            success = NO;
            outError = error;
            dispatch_semaphore_signal(semaphore);
        } completionQueue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)];
    } failure:^(NSError * _Nonnull error) {
        success = NO;
        outError = error;
        dispatch_semaphore_signal(semaphore);
    } completionQueue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)];
    
    long result = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC));
    
    XCTAssertEqual(0, result);
    XCTAssertTrue(success);
    XCTAssertNil(outError);
    XCTAssertNotNil(outIdentifiers);
    XCTAssertEqual(3, outIdentifiers.count);
    XCTAssertEqualObjects([NSSet setWithArray:newObjectIds], [NSSet setWithArray:(NSArray *)outIdentifiers]);
}

#pragma mark - Actual Tests - Deletion

- (SEPersistenceServiceImpl *)arrangeDataForDeletionWithFirstId:(NSNumber *)firstId secondId:(NSNumber *)secondId
{
    SEPersistenceServiceImpl *persistenceService = [self createInitializedService];
    
    NSError *error = nil;
    BOOL result = [persistenceService createAndWaitObjectOfType:[SEPersistenceServiceTestModel class] obtainPermanentId:NO initializer:^(SEPersistenceServiceTestModel *  _Nonnull instance) {
        instance.identifierAttribute = firstId;
        instance.firstAttribute = @"Value";
        instance.secondAttribute = @(2);
    } saveOptions:SEPersistenceServiceSaveCurrentOnly error:&error];
    XCTAssertTrue(result);
    
    result = [persistenceService createAndWaitObjectOfType:[SEPersistenceServiceTestModel class] obtainPermanentId:NO initializer:^(SEPersistenceServiceTestModel *  _Nonnull instance) {
        instance.identifierAttribute = secondId;
        instance.firstAttribute = @"Other Value";
        instance.secondAttribute = nil;
    } saveOptions:SEPersistenceServiceSaveCurrentOnly error:&error];
    XCTAssertTrue(result);
    
    __block NSUInteger count = 0;
    result = [persistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertEqual(2, count);

    return persistenceService;
}

- (void)testDeleteObjectSynchronous
{
    NSNumber *const IdentifierValue = @(777);
    NSNumber *const OtherIdentifierValue = @(889);

    // first, arrange a couple of objects
    SEPersistenceServiceImpl *persistenceService = [self arrangeDataForDeletionWithFirstId:IdentifierValue secondId:OtherIdentifierValue];
    
    // now, delete one
    NSError *error = nil;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K = %@", @"identifierAttribute", IdentifierValue];
    SEFetchParameters *parameters = [SEFetchParameters fetchParametersWithPredicate:predicate];
    BOOL result = [persistenceService deleteObjectsAndWaitOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters saveOptions:SEPersistenceServiceSaveAndPersist error:&error];
    
    XCTAssertTrue(result);
    XCTAssertNil(error);
    
    __block NSUInteger count = 0;
    __block NSNumber *identifier = nil;
    result = [persistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
        SEPersistenceServiceTestModel *model = objects.firstObject;
        identifier = model.identifierAttribute;
    } error:&error];
    XCTAssertEqual(1, count);
    XCTAssertEqualObjects(OtherIdentifierValue, identifier);
}

- (void)testDeleteObjectAsync
{
    NSNumber *const IdentifierValue = @(345);
    NSNumber *const OtherIdentifierValue = @(123);
    
    // first, arrange a couple of objects
    SEPersistenceServiceImpl *persistenceService = [self arrangeDataForDeletionWithFirstId:IdentifierValue secondId:OtherIdentifierValue];
    
    // now, delete one
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block volatile BOOL success = NO;
    __block volatile NSError *outError = nil;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K = %@", @"identifierAttribute", IdentifierValue];
    SEFetchParameters *parameters = [SEFetchParameters fetchParametersWithPredicate:predicate];
    [persistenceService deleteObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters saveOptions:SEPersistenceServiceSaveAndPersist success:^{
        success = YES;
        dispatch_semaphore_signal(semaphore);
    } failure:^(NSError * _Nonnull error) {
        success = NO;
        outError = error;
        dispatch_semaphore_signal(semaphore);
    } completionQueue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)];
    
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC));
    XCTAssertTrue(success);
    XCTAssertNil(outError);
    
    __block NSUInteger count = 0;
    __block NSNumber *identifier = nil;
    BOOL result = [persistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
        SEPersistenceServiceTestModel *model = objects.firstObject;
        identifier = model.identifierAttribute;
    } error:&outError];
    XCTAssertTrue(result);
    XCTAssertEqual(1, count);
    XCTAssertEqualObjects(OtherIdentifierValue, identifier);
}

#pragma mark - Actual Tests - Fetch and Update

- (void)testFetchAndUpdateSync
{
    NSNumber *const IdentifierValue = @(765);
    NSNumber *const NewIdentifierValue = @(999);

    SEPersistenceServiceImpl *persistenceService = [self createInitializedService];
    
    NSError *error = nil;
    BOOL result = [persistenceService createAndWaitObjectOfType:[SEPersistenceServiceTestModel class] obtainPermanentId:NO initializer:^(SEPersistenceServiceTestModel *  _Nonnull instance) {
        instance.identifierAttribute = IdentifierValue;
        instance.firstAttribute = @"Value";
        instance.secondAttribute = @(2);
    } saveOptions:SEPersistenceServiceSaveCurrentOnly error:&error];
    XCTAssertTrue(result);

    __block NSUInteger count = 0;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K = %@", @"identifierAttribute", IdentifierValue];
    SEFetchParameters *parameters = [SEFetchParameters fetchParametersWithPredicate:predicate];
    result = [persistenceService fetchAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^SEPersistenceServiceSaveOptions(NSArray * _Nonnull objects) {
        count = objects.count;
        for (SEPersistenceServiceTestModel *model in objects)
        {
            model.identifierAttribute = NewIdentifierValue;
            model.firstAttribute = @"New Value";
            model.secondAttribute = @(3);
        }
        return SEPersistenceServiceSaveCurrentOnly;
    } error:&error];
    XCTAssertEqual(1, count);
    XCTAssertTrue(result);
    
    result = [persistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssertEqual(0, count);
    
    predicate = [NSPredicate predicateWithFormat:@"%K = %@", @"identifierAttribute", NewIdentifierValue];
    parameters = [SEFetchParameters fetchParametersWithPredicate:predicate];
    result = [persistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssertEqual(1, count);
}

- (void)testFetchByObjectIdsSync
{
    SEPersistenceServiceImpl *persistenceService = [self createInitializedService];
    
    __block NSArray *objectIds = nil;
    NSError *error = nil;

    BOOL result = [persistenceService createAndWaitObjectOfType:[SEPersistenceServiceTestModel class] obtainPermanentId:NO initializer:^(SEPersistenceServiceTestModel *  _Nonnull instance) {
        instance.identifierAttribute = @(5566);
        instance.firstAttribute = @"Value";
        instance.secondAttribute = @(2);
    } saveOptions:SEPersistenceServiceSaveCurrentOnly error:&error];

    result = [persistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil fetchedObjectProcessor:^(NSArray<__kindof NSManagedObject *> * _Nonnull objects) {
        NSMutableArray *ids = [NSMutableArray new];
        for (NSManagedObject *object in objects)
        {
            NSManagedObjectID *objectId = object.objectID;
            if (!objectId.temporaryID) [ids addObject:objectId];
        }
        objectIds = [ids copy];
    } error:&error];
    
    XCTAssert(result);
    XCTAssertEqual(1, objectIds.count);
    
    __block NSUInteger count = 0;
    __block BOOL noFault = YES;
    result = [persistenceService fetchReadOnlyAndWaitObjectsByIds:objectIds fetchedObjectProcessor:^(NSArray<__kindof NSManagedObject *> * _Nonnull objects) {
        count = objects.count;
        for (NSManagedObject *object in objects)
        {
            if (object.isFault) noFault = NO;
        }
    } error:&error];
    
    XCTAssert(result);
    XCTAssert(noFault);
    XCTAssertEqual(1, count);
}

#pragma mark - Actual Tests - Hierarchical

- (void)testCreatesOnChildContextOnlyDontPropagateToParent
{
    SEPersistenceServiceImpl *parentPersistenceService = [self createInitializedService];
    id<SEPersistenceService> childPersistenceService = [parentPersistenceService createChildPersistenceServiceWithPrivateQueueConcurrency];
    
    NSError *error = nil;
    BOOL result = [childPersistenceService createAndWaitObjectOfType:[SEPersistenceServiceTestModel class] obtainPermanentId:NO initializer:^(SEPersistenceServiceTestModel * _Nonnull instance) {
        instance.identifierAttribute = @(5);
        instance.firstAttribute = @"first";
    } saveOptions:SEPersistenceServiceDontSave error:&error];
    
    XCTAssertTrue(result);
    
    __block NSUInteger count = 0;
    result = [childPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssertEqual(1, count);

    result = [parentPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssertEqual(0, count);
}

- (void)testCreatesOnChildAndLocalSavesPropagatesOneStepUp
{
    SEPersistenceServiceImpl *parentPersistenceService = [self createInitializedService];
    id<SEPersistenceService> childPersistenceService = [parentPersistenceService createChildPersistenceServiceWithPrivateQueueConcurrency];
    id<SEPersistenceService> superChildPersistenceService = [childPersistenceService createChildPersistenceServiceWithPrivateQueueConcurrency];
    
    NSError *error = nil;
    BOOL result = [superChildPersistenceService createAndWaitObjectOfType:[SEPersistenceServiceTestModel class] obtainPermanentId:NO initializer:^(SEPersistenceServiceTestModel * _Nonnull instance) {
        instance.identifierAttribute = @(5);
        instance.firstAttribute = @"first";
    } saveOptions:SEPersistenceServiceSaveCurrentOnly error:&error];
    
    XCTAssertTrue(result);
    
    __block NSUInteger count = 0;
    result = [childPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssertEqual(1, count);
    
    result = [parentPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssertEqual(0, count);
}

- (void)testCreatesOnChildAndPersistentSavePropagatesAllTheWay
{
    SEPersistenceServiceImpl *parentPersistenceService = [self createInitializedService];
    id<SEPersistenceService> childPersistenceService = [parentPersistenceService createChildPersistenceServiceWithPrivateQueueConcurrency];
    id<SEPersistenceService> superChildPersistenceService = [childPersistenceService createChildPersistenceServiceWithPrivateQueueConcurrency];
    
    NSError *error = nil;
    BOOL result = [superChildPersistenceService createAndWaitObjectOfType:[SEPersistenceServiceTestModel class] obtainPermanentId:NO initializer:^(SEPersistenceServiceTestModel * _Nonnull instance) {
        instance.identifierAttribute = @(5);
        instance.firstAttribute = @"first";
    } saveOptions:SEPersistenceServiceSaveAndPersist error:&error];
    
    XCTAssertTrue(result);
    
    __block NSUInteger count = 0;
    result = [childPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssertEqual(1, count);
    
    result = [parentPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:nil fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssertEqual(1, count);
}

- (void)testHierarchicalFetchAndUpdateOneStepSync
{
    NSNumber *const IdentifierValue = @(333);
    NSNumber *const NewIdentifierValue = @(444);
    
    SEPersistenceServiceImpl *parentPersistenceService = [self createInitializedService];
    id<SEPersistenceService> childPersistenceService = [parentPersistenceService createChildPersistenceServiceWithPrivateQueueConcurrency];
    id<SEPersistenceService> superChildPersistenceService = [childPersistenceService createChildPersistenceServiceWithPrivateQueueConcurrency];
    
    NSError *error = nil;
    BOOL result = [superChildPersistenceService createAndWaitObjectOfType:[SEPersistenceServiceTestModel class] obtainPermanentId:NO initializer:^(SEPersistenceServiceTestModel *  _Nonnull instance) {
        instance.identifierAttribute = IdentifierValue;
        instance.firstAttribute = @"Value";
        instance.secondAttribute = @(2);
    } saveOptions:SEPersistenceServiceSaveCurrentOnly error:&error];
    XCTAssertTrue(result);
    
    __block NSUInteger count = 0;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K = %@", @"identifierAttribute", IdentifierValue];
    SEFetchParameters *parameters = [SEFetchParameters fetchParametersWithPredicate:predicate];
    result = [childPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssertEqual(1, count);
    
    result = [parentPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssertEqual(0, count);

    // now make an update and save in current context
    result = [superChildPersistenceService fetchAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^SEPersistenceServiceSaveOptions(NSArray * _Nonnull objects) {
        count = objects.count;
        for (SEPersistenceServiceTestModel *model in objects)
        {
            model.identifierAttribute = NewIdentifierValue;
            model.firstAttribute = @"New Value";
            model.secondAttribute = @(3);
        }
        return SEPersistenceServiceSaveCurrentOnly;
    } error:&error];
    XCTAssertEqual(1, count);
    XCTAssertTrue(result);
    
    result = [childPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssertEqual(0, count);
    
    result = [parentPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssertEqual(0, count);

    predicate = [NSPredicate predicateWithFormat:@"%K = %@", @"identifierAttribute", NewIdentifierValue];
    parameters = [SEFetchParameters fetchParametersWithPredicate:predicate];
    result = [childPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssertEqual(1, count);
    
    result = [parentPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssertEqual(0, count);
}

- (void)testHierarchicalFetchAndUpdateAllTheWaySync
{
    NSNumber *const IdentifierValue = @(889);
    NSNumber *const NewIdentifierValue = @(890);
    
    SEPersistenceServiceImpl *parentPersistenceService = [self createInitializedService];
    id<SEPersistenceService> childPersistenceService = [parentPersistenceService createChildPersistenceServiceWithPrivateQueueConcurrency];
    id<SEPersistenceService> superChildPersistenceService = [childPersistenceService createChildPersistenceServiceWithPrivateQueueConcurrency];
    
    NSError *error = nil;
    BOOL result = [superChildPersistenceService createAndWaitObjectOfType:[SEPersistenceServiceTestModel class] obtainPermanentId:NO initializer:^(SEPersistenceServiceTestModel *  _Nonnull instance) {
        instance.identifierAttribute = IdentifierValue;
        instance.firstAttribute = @"Value";
        instance.secondAttribute = @(2);
    } saveOptions:SEPersistenceServiceSaveCurrentOnly error:&error];
    XCTAssertTrue(result);
    
    __block volatile NSUInteger count = 0;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K = %@", @"identifierAttribute", IdentifierValue];
    SEFetchParameters *parameters = [SEFetchParameters fetchParametersWithPredicate:predicate];
    result = [childPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssert(1 == count);
    
    result = [parentPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssert(0 == count);
    
    // Now make an update and save all the way
    result = [superChildPersistenceService fetchAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^SEPersistenceServiceSaveOptions(NSArray * _Nonnull objects) {
        count = objects.count;
        for (SEPersistenceServiceTestModel *model in objects)
        {
            model.identifierAttribute = NewIdentifierValue;
            model.firstAttribute = @"New Value";
            model.secondAttribute = @(3);
        }
        return SEPersistenceServiceSaveAndPersist;
    } error:&error];
    XCTAssert(1 == count);
    XCTAssertTrue(result);
    
    result = [childPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssert(0 == count);
    
    result = [parentPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssert(0 == count);
    
    predicate = [NSPredicate predicateWithFormat:@"%K = %@", @"identifierAttribute", NewIdentifierValue];
    parameters = [SEFetchParameters fetchParametersWithPredicate:predicate];
    result = [childPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssert(1 == count);
    
    result = [parentPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssert(1 == count);
}

- (void)testHierarchicalFetchAndUpdateAllTheWayAsync
{
    NSNumber *const IdentifierValue = @(123);
    NSNumber *const NewIdentifierValue = @(134);
    
    SEPersistenceServiceImpl *parentPersistenceService = [self createInitializedService];
    id<SEPersistenceService> childPersistenceService = [parentPersistenceService createChildPersistenceServiceWithPrivateQueueConcurrency];
    id<SEPersistenceService> superChildPersistenceService = [childPersistenceService createChildPersistenceServiceWithPrivateQueueConcurrency];
    
    NSError *error = nil;
    BOOL result = [superChildPersistenceService createAndWaitObjectOfType:[SEPersistenceServiceTestModel class] obtainPermanentId:NO initializer:^(SEPersistenceServiceTestModel *  _Nonnull instance) {
        instance.identifierAttribute = IdentifierValue;
        instance.firstAttribute = @"Value";
        instance.secondAttribute = @(2);
    } saveOptions:SEPersistenceServiceSaveCurrentOnly error:&error];
    XCTAssertTrue(result);
    
    // Now make an update and save all the way
    __block volatile BOOL success = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    __block volatile NSUInteger count = 0;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K = %@", @"identifierAttribute", IdentifierValue];
    SEFetchParameters *parameters = [SEFetchParameters fetchParametersWithPredicate:predicate];
    [superChildPersistenceService fetchObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^SEPersistenceServiceSaveOptions(NSArray * _Nonnull objects) {
        count = objects.count;
        for (SEPersistenceServiceTestModel *model in objects)
        {
            model.identifierAttribute = NewIdentifierValue;
            model.firstAttribute = @"New Value";
            model.secondAttribute = @(3);
        }
        return SEPersistenceServiceSaveAndPersist;
    } success:^{
        success = YES;
        dispatch_semaphore_signal(semaphore);
    } failure:^(NSError * _Nonnull error) {
        success = NO;
        dispatch_semaphore_signal(semaphore);
    } completionQueue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)];

    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC));
    XCTAssert(1 == count);
    XCTAssertTrue(success);
    
    result = [childPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssert(0 == count);
    
    result = [parentPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssert(0 == count);
    
    predicate = [NSPredicate predicateWithFormat:@"%K = %@", @"identifierAttribute", NewIdentifierValue];
    parameters = [SEFetchParameters fetchParametersWithPredicate:predicate];
    result = [childPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssert(1 == count);
    
    result = [parentPersistenceService fetchReadOnlyAndWaitObjectsOfType:[SEPersistenceServiceTestModel class] fetchParameters:parameters fetchedObjectProcessor:^void(NSArray * _Nonnull objects) {
        count = objects.count;
    } error:&error];
    XCTAssertTrue(result);
    XCTAssert(1 == count);
}


@end
