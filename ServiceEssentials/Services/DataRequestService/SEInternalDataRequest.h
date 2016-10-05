//
//  SEInternalDataRequest.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

@import Foundation;
#import "SEDataRequestService.h"

@protocol SEDataRequestServicePrivate;
@protocol SECancellableToken;
@class SEMultipartRequestContentPart;

@interface SEInternalMultipartContents : NSObject
- (instancetype) initWithMultipartContents: (NSArray<SEMultipartRequestContentPart *> *) multipartContents boundary:(NSString *)boundary;
@property (nonatomic, readonly, strong) NSArray<SEMultipartRequestContentPart *> *multipartContents;
@property (nonatomic, readonly, strong) NSString *boundary;
@end

@interface SEInternalDownloadRequestParameters : NSObject
- (instancetype) initWithSaveAsURL: (NSURL *) saveAsURL downloadProgressCallback:(void(^)(int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpected))progress;
@property (nonatomic, readonly, strong) NSURL *saveAsURL;
@property (nonatomic, readonly, strong) void(^progress)(int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpected);
@end

@interface SEInternalDataRequest : NSObject

- (instancetype) initWithSessionTask:(NSURLSessionTask *)task
                      requestService:(id<SEDataRequestServicePrivate>)requestService
                    qualityOfService:(SEDataRequestQualityOfService)qualityOfService
                   responseDataClass:(Class)dataClass
                   expectedHTTPCodes:(NSIndexSet *)expectedCodes
                   multipartContents:(SEInternalMultipartContents *)multipartContents
                  downloadParameters:(SEInternalDownloadRequestParameters *)downloadParameters
                             success:(void(^)(id, NSURLResponse *))success
                             failure:(void (^)(NSError *))failure
                     completionQueue:(dispatch_queue_t)completionQueue;

@property (nonatomic, readonly, retain) id<SECancellableToken> token;
@property (nonatomic, readonly, retain) NSURLSessionTask *task;
@property (nonatomic, readonly, assign) SEDataRequestQualityOfService qualityOfService;

@property (nonatomic, readonly, assign) BOOL isCompleted;

- (void) cancelAndNotifyComplete:(BOOL)notifyComplete;
- (void) completeWithError: (NSError *) error;
- (void) receivedData: (NSData *) data;
- (BOOL) receivedURLResponse: (NSURLResponse *) response;
- (void) downloadRequestDidWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite;
- (void) downloadRequestDidFinishDownloadingToURL:(NSURL *)location;

- (NSInputStream *) createStream;

@end
