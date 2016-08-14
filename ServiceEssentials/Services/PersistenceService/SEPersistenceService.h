//
//  SEPersistenceService.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <Foundation/Foundation.h>
#import "SEFetchParameters.h"

@class NSManagedObjectContext;
@class NSManagedObjectModel;
@class NSManagedObject;
@class NSManagedObjectID;

typedef enum
{
    SEPersistenceServiceDontSave,
    SEPersistenceServiceSaveCurrentOnly,
    SEPersistenceServiceSaveAndPersist
} SEPersistenceServiceSaveOptions;

extern NSString * const SEPersistenceServiceInitializationCompleteNotification;

extern NSInteger const SEPersistenceServiceBlockOperationError;

@protocol SEPersistenceService <NSObject>
- (BOOL)isInitialized;

#pragma mark - Create

- (void)createObjectOfType:(nonnull Class)type obtainPermanentId:(BOOL)obtainPermanentId initializer:(nonnull void(^)(__kindof NSManagedObject * __nonnull instance))initializer saveOptions:(SEPersistenceServiceSaveOptions)saveOptions success:(nullable void (^)())success failure:(nullable void(^)(NSError * __nonnull error))failure completionQueue:(nullable dispatch_queue_t)completionQueue;
- (BOOL)createAndWaitObjectOfType:(nonnull Class)type obtainPermanentId:(BOOL)obtainPermanentId initializer:(nonnull void(^)(__kindof NSManagedObject * __nonnull instance))initializer saveOptions:(SEPersistenceServiceSaveOptions)saveOptions error:(NSError * __nullable __autoreleasing * __nullable)error;

- (void)createObjectsOfType:(nonnull Class)type byTransformingObjects:(nonnull NSArray *)objects withTransform:(nonnull BOOL (^)(id __nonnull source, __kindof NSManagedObject * __nonnull target))transform saveOptions:(SEPersistenceServiceSaveOptions)saveOptions success:(nullable void (^)())success failure:(nullable void(^)(NSError * __nonnull error))failure completionQueue:(nullable dispatch_queue_t)completionQueue;
- (BOOL)createAndWaitObjectsOfType:(nonnull Class)type byTransformingObjects:(nonnull NSArray *)objects withTransform:(nonnull BOOL (^)(id __nonnull source, __kindof NSManagedObject * __nonnull target))transform saveOptions:(SEPersistenceServiceSaveOptions)saveOptions error:(NSError * __nullable __autoreleasing * __nullable)error;

#pragma mark - Fetch - Read-Only

- (void)fetchReadOnlyObjectsOfType:(nonnull Class)type fetchParameters:(nullable SEFetchParameters *)fetchParameters fetchedObjectProcessor:(nonnull void (^)(NSArray<__kindof NSManagedObject *> *__nonnull objects))fetchedProcessor success:(nullable void (^)())success failure:(nullable void(^)(NSError * __nonnull error))failure completionQueue:(nullable dispatch_queue_t)completionQueue;
- (BOOL)fetchReadOnlyAndWaitObjectsOfType:(nonnull Class)type fetchParameters:(nullable SEFetchParameters *)fetchParameters fetchedObjectProcessor:(nonnull void (^)(NSArray<__kindof NSManagedObject *> *__nonnull objects))fetchedProcessor error:(NSError * __nullable __autoreleasing * __nullable)error;

- (void)fetchReadOnlyObjectsByIds:(nonnull NSArray<NSManagedObjectID *> *)objectIds fetchedObjectProcessor:(nonnull void (^)(NSArray<__kindof NSManagedObject *> *__nonnull objects))fetchedProcessor success:(nullable void (^)())success failure:(nullable void(^)(NSError * __nonnull error))failure completionQueue:(nullable dispatch_queue_t)completionQueue;
- (BOOL)fetchReadOnlyAndWaitObjectsByIds:(nonnull NSArray<NSManagedObjectID *> *)objectIds fetchedObjectProcessor:(nonnull void (^)(NSArray<__kindof NSManagedObject *> *__nonnull objects))fetchedProcessor error:(NSError * __nullable __autoreleasing * __nullable)error;

- (void)fetchTransformObjectsOfType:(nonnull Class)type fetchParameters:(nullable SEFetchParameters *)fetchParameters transform:(nonnull id __nonnull (^)(__kindof NSManagedObject *__nonnull source))transform success:(nonnull void (^)(NSArray *__nonnull results))success failure:(nullable void(^)(NSError * __nonnull error))failure completionQueue:(nullable dispatch_queue_t)completionQueue;

- (nullable NSArray *)fetchAndWaitTransformObjectsOfType:(nonnull Class)type fetchParameters:(nullable SEFetchParameters *)fetchParameters transform:(nonnull id __nonnull (^)(__kindof NSManagedObject *__nonnull source))transform error:(NSError * __nullable __autoreleasing * __nullable)error;

#pragma mark - Fetch - Read-Write

- (void)fetchObjectsOfType:(nonnull Class)type fetchParameters:(nullable SEFetchParameters *)fetchParameters fetchedObjectProcessor:(nonnull SEPersistenceServiceSaveOptions (^)(NSArray<__kindof NSManagedObject *> *__nonnull objects))fetchedProcessor success:(nullable void (^)())success failure:(nullable void(^)(NSError * __nonnull error))failure completionQueue:(nullable dispatch_queue_t)completionQueue;
- (BOOL)fetchAndWaitObjectsOfType:(nonnull Class)type fetchParameters:(nullable SEFetchParameters *)fetchParameters fetchedObjectProcessor:(nonnull SEPersistenceServiceSaveOptions (^)(NSArray<__kindof NSManagedObject *> *__nonnull objects))fetchedProcessor error:(NSError * __nullable __autoreleasing * __nullable)error;

- (void)fetchObjectsByIds:(nonnull NSArray<NSManagedObjectID *> *)objectIds fetchedObjectProcessor:(nonnull SEPersistenceServiceSaveOptions (^)(NSArray<__kindof NSManagedObject *> *__nonnull objects))fetchedProcessor success:(nullable void (^)())success failure:(nullable void(^)(NSError * __nonnull error))failure completionQueue:(nullable dispatch_queue_t)completionQueue;
- (BOOL)fetchAndWaitObjectsByIds:(nonnull NSArray<NSManagedObjectID *> *)objectIds fetchedObjectProcessor:(nonnull SEPersistenceServiceSaveOptions (^)(NSArray<__kindof NSManagedObject *> *__nonnull objects))fetchedProcessor error:(NSError * __nullable __autoreleasing * __nullable)error;

#pragma mark - Delete

- (void)deleteObjectsOfType:(nonnull Class)type fetchParameters:(nullable SEFetchParameters *)fetchParameters saveOptions:(SEPersistenceServiceSaveOptions)saveOptions success:(nullable void (^)())success failure:(nullable void(^)(NSError * __nonnull error))failure completionQueue:(nullable dispatch_queue_t)completionQueue;
- (BOOL)deleteObjectsAndWaitOfType:(nonnull Class)type fetchParameters:(nullable SEFetchParameters *)fetchParameters saveOptions:(SEPersistenceServiceSaveOptions)saveOptions error:(NSError * __nullable __autoreleasing * __nullable)error;

- (void)deleteObjectsByIds:(nonnull NSArray<NSManagedObjectID *> *)objectIds saveOptions:(SEPersistenceServiceSaveOptions)saveOptions success:(nullable void (^)())success failure:(nullable void(^)(NSError * __nonnull error))failure completionQueue:(nullable dispatch_queue_t)completionQueue;
- (BOOL)deleteObjectsAndWaitByIds:(nonnull NSArray<NSManagedObjectID *> *)objectIds saveOptions:(SEPersistenceServiceSaveOptions)saveOptions error:(NSError * __nullable __autoreleasing * __nullable)error;

#pragma mark - Save

- (void)saveAllWithOptions:(SEPersistenceServiceSaveOptions)saveOptions success:(nullable void (^)())success failure:(nullable void(^)(NSError * __nonnull error))failure completionQueue:(nullable dispatch_queue_t)completionQueue;
- (BOOL)saveAllAndWaitWithOptions: (SEPersistenceServiceSaveOptions)saveOptions error:(NSError * __nullable __autoreleasing * __nullable)error;

#pragma mark - Rollback

- (void)rollbackWithCompletion:(nullable void (^)())completion completionQueue:(nullable dispatch_queue_t)completionQueue;
- (void)rollbackAndWait;

#pragma mark - Child contexts/persistence services

- (nonnull id<SEPersistenceService>)createChildPersistenceServiceWithMainQueueConcurrency;
- (nonnull id<SEPersistenceService>)createChildPersistenceServiceWithPrivateQueueConcurrency;

- (nonnull NSManagedObjectContext *)createChildContextWithMainQueueConcurrency;
- (nonnull NSManagedObjectContext *)createChildContextWithPrivateQueueConcurrency;
@end

@interface SEPersistenceServiceImpl : NSObject<SEPersistenceService>
- (nonnull instancetype)initWithDataModel:(nonnull NSManagedObjectModel *)dataModel storePath:(nonnull NSString *)storePath;
- (nonnull instancetype)initWithDataModelName:(nonnull NSString *)dataModelName storePath:(nonnull NSString *)storePath;
@end
