//
//  SEInternalDataRequest.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import "SEInternalDataRequest.h"

#include <objc/runtime.h>
#include <libkern/OSAtomic.h>

#import "SETools.h"
#import "SEDataRequestService.h"
#import "SEDataRequestServicePrivate.h"
#import "SEDataSerializer.h"
#import "SECancellableTokenImpl.h"
#import "SEMultipartRequestContentStream.h"

#define COMPLETED_REQUEST_BIT       0 // signals that request has been completed
#define CANCELLED_REQUEST_BIT       1 // signals that request has been cancelled, this bit will also be set by completed callback

static inline dispatch_queue_t SEDataRequestQueueForQOS(SEDataRequestQualityOfService qos, dispatch_queue_t privateQueue)
{
#ifdef DEBUG
    if (privateQueue == nil) THROW_INVALID_PARAM(privateQueue, nil);
#endif
    if (qos == SEDataRequestQOSDefault) return privateQueue;
    
    dispatch_queue_t result = dispatch_get_global_queue(qos, 0);
    if (result == nil) THROW_INVALID_PARAM(qos, nil);
    return result;
}

static inline void SEDataRequestSendCompletionToService(id<SEDataRequestServicePrivate> service, SEInternalDataRequest *request)
{
    if (service)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            [service completeInternalRequest:request];
        });
    }
}

@implementation SEInternalDataRequest
{
    __weak id<SEDataRequestServicePrivate> _requestService;
    __unsafe_unretained Class _dataClass;
    NSIndexSet *_expectedHTTPCodes;
    SEInternalMultipartContents *_multipartContents;
    SEInternalDownloadRequestParameters *_downloadRequestParameters;
    void (^_success)(id data, NSURLResponse *response);
    void (^_failure)(NSError *error);
    dispatch_queue_t _completionQueue;
    volatile uint32_t _completed;
    
    NSMutableData *_data;
    NSURLResponse *_response;
}

- (instancetype)initWithSessionTask:(NSURLSessionTask *)task requestService:(id<SEDataRequestServicePrivate>)requestService qualityOfService:(SEDataRequestQualityOfService)qualityOfService responseDataClass:(__unsafe_unretained Class)dataClass expectedHTTPCodes:(NSIndexSet *)expectedCodes multipartContents:(SEInternalMultipartContents *)multipartContents downloadParameters:(SEInternalDownloadRequestParameters *)downloadParameters success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    self = [super init];
    if (self)
    {
        _requestService = requestService;
        
        _expectedHTTPCodes = expectedCodes ?: [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 100)];
        _task = task;
        _qualityOfService = qualityOfService;
        _dataClass = dataClass;
        _multipartContents = multipartContents;
        _downloadRequestParameters = downloadParameters;
        _success = success;
        _failure = failure;
        _completionQueue = completionQueue;
        
        _token = [[SECancellableTokenImpl alloc] initWithService:requestService];
    }
    return self;
}

- (void)dealloc
{
    // If the taks was not completed but is deallocated - clean its inner guts and send 'cancelled' error
    bool wasCompleted = OSAtomicTestAndSet(COMPLETED_REQUEST_BIT, &_completed);
    if (!wasCompleted)
    {
        [_task cancel];
        
        // cannot do anything that causes a retain of self, need to be very careful
        // cannot make a block that uses self
        // cannot make an async block because self will be gone
        // better to avoid any calls to self at all
        // call the service method synchronously

        void (^failureBlock)(NSError *) = _failure;
        NSError *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceRequestCancelled userInfo:nil];
        if (failureBlock)
        {
            dispatch_async(_completionQueue, ^{
                failureBlock(error);
            });
        }

        
#ifdef DEBUG
        if (_requestService) {
            NSLog(@"ERROR: the service is not deallocated and request is not complete, this should never happen!");
        }
#endif
        
        __unsafe_unretained typeof (self) unretainedSelf = self;
        [_requestService completeInternalRequest:unretainedSelf];
    }
}

- (BOOL)isCompleted
{
    // since 'cancelled' flag can only be set after 'completed' flag, this condition is valid
    return _completed != 0;
}

- (void)cancel
{
    // always set 'completed' first, then 'cancelled'
    bool wasCompleted = OSAtomicTestAndSet(COMPLETED_REQUEST_BIT, &_completed);
    if (!wasCompleted)
    {
        OSAtomicTestAndSet(CANCELLED_REQUEST_BIT, &_completed);
        [_task cancel];
        SEDataRequestSendCompletionToService(_requestService, self);
    }
}

- (void)completeWithError:(NSError *)error
{
    if (_completed) return;
    
    if (error)
    {
        [self failedWithError:error];
        return;
    }
    
    error = [self checkURLResponseIsValid:_response];
    // If there was an error, it will contain deserialized data if deserialization was possible and there was data.
    if (error != nil)
    {
        [self failedWithError:error];
        return;
    }
    
    id result = nil;
    
    // Some requests don't return any response for a valid reason.
    // For exmaple, HTTP 204 No Data is one of those reasons (may be in response to PUT request)
    // So a successful response may contain no data and there is nothing to deserialize
    if (_data != nil && _data.length > 0)
    {
        SEDataSerializer *serializer = [_requestService serializerForMIMEType:_response.MIMEType];
        if (serializer == nil)
        {
            error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:nil];
        }
        else
        {
            result = [serializer deserializeData:_data mimeType:_response.MIMEType error:&error];
        }
    
#ifdef DEBUG
        // double-ensure
        if (_dataClass != nil && ![SEDataRequestServiceImpl canDeserializeToClass:_dataClass])
        {
            error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:@{ NSLocalizedDescriptionKey: @"FAILURE: incorrect class for deserialization" }];
        }
#endif
        if (error == nil && _dataClass != nil)
        {
            if ([result isKindOfClass:[NSDictionary class]])
            {
                result = [_dataClass deserializeFromJSON: result];
                if (result == nil) error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:nil];
            }
            else if ([result isKindOfClass:[NSArray class]])
            {
                result = [SEInternalDataRequest deserializeArray:result toClass:_dataClass error:&error];
            }
            else
            {
                error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:@{ NSLocalizedDescriptionKey: @"Incompatible data type for deserialization." }];
            }
        }
    }

    if (error != nil)
    {
        [self failedWithError:error];
        return;
    }
    
    [self finalizeCompleteRequestSuccessfulWithResult:result];
}

- (void)receivedData:(NSData *)data
{
    // No need for locking since the sequence of events is such that data is accumulated in chunks and only then task is completed
    if (_data == nil) _data  = [[NSMutableData alloc] initWithData:data];
    else [_data appendData:data];
}

- (BOOL)receivedURLResponse:(NSURLResponse *)response
{
    // No need for locking since it is the only place where request will be written, and it is only read after the task is complete so it's safe
    
    // when completed, don't proceed receiving data
    if (_completed) return NO;

    // Still receive data since even a faulty response may contain valuable body
    _response = response;
    return YES;
}

- (NSInputStream *)createStream
{
    if (_completed) return nil;
    if (_multipartContents == nil) return nil;
    return [[SEMultipartRequestContentStream alloc] initWithParts:_multipartContents.multipartContents boundary:_multipartContents.boundary stringEncoding:[_requestService stringEncoding]];
}

- (void)downloadRequestDidFinishDownloadingToURL:(NSURL *)location
{
    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (_completed)
    {
        if(![fileManager removeItemAtURL:location error:&error])
        {
            [self failedWithError:error];
        }
        else
        {
            bool wasCompleted = OSAtomicTestAndSet(COMPLETED_REQUEST_BIT, &_completed);
            if (!wasCompleted) SEDataRequestSendCompletionToService(_requestService, self);
        }
    }
    else
    {
        // 1. Save the file to URL provided
        // 2. Invoke a completion callback
        if ([fileManager moveItemAtURL:location toURL:_downloadRequestParameters.saveAsURL error:&error])
        {
            [self finalizeCompleteRequestSuccessfulWithResult:nil];
        }
        else
        {
            [self failedWithError:error];
        }
    }
}

- (void)downloadRequestDidWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    if (_completed) return;
    
    void (^progress)(int64_t, int64_t, int64_t) = _downloadRequestParameters.progress;
    if (progress != nil)
    {
        dispatch_async(_completionQueue, ^{
            if (!_completed) progress(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
        });
    }
}

#pragma mark - Priavte stuff

- (NSError *) checkURLResponseIsValid: (NSURLResponse *) response
{
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)_response;
    NSInteger responseCode = httpResponse.statusCode;
    if ([_expectedHTTPCodes containsIndex:responseCode])
    {
        return nil;
    }
    else
    {
        // not an expected response code
        NSString *textDescription = [SEInternalDataRequest errorMessageForHTTPCode:responseCode];
        NSString *description;
        if (textDescription != nil) description = [NSString stringWithFormat:@"Request failed: %@", textDescription];
        else description = [NSString stringWithFormat:@"Response code %i is not within expected bounds (%@)", (int) responseCode, _expectedHTTPCodes];
        
        id internalData = nil;
        NSError *deserializationError = nil;
        if (_data.length > 0)
        {
            SEDataSerializer *serializer = [_requestService explicitSerializerForMIMEType:response.MIMEType];
            if (serializer != nil)
            {
                internalData = [serializer deserializeData:_data mimeType:response.MIMEType error:&deserializationError];
            }
        }
        
        NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] initWithCapacity:2];
        [userInfo setObject:description forKey:NSLocalizedDescriptionKey];
        if (deserializationError != nil) [userInfo setObject:deserializationError forKey:NSUnderlyingErrorKey];
        if (internalData != nil) [userInfo setObject:internalData forKey:SEDataRequestServiceErrorDeserializedContentKey];
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:responseCode userInfo:[userInfo copy]];
        return error;
    }
}

- (void) finalizeCompleteRequestSuccessfulWithResult:(id)result
{
    bool wasCompleted = OSAtomicTestAndSet(COMPLETED_REQUEST_BIT, &_completed);
    if (wasCompleted) return;
    
    SEDataRequestSendCompletionToService(_requestService, self);
    
    NSURLResponse *response = _response;
    void (^completion)(id, NSURLResponse *) = _success;
    if (completion)
    {
        dispatch_async(_completionQueue, ^{
            // need to check for cancellation right before here
            if (!OSAtomicTestAndSet(CANCELLED_REQUEST_BIT, &_completed))
                completion(result, response);
        });
    }
}

- (void) failedWithError: (NSError *) error
{
    bool wasCompleted = OSAtomicTestAndSet(COMPLETED_REQUEST_BIT, &_completed);
    if (!wasCompleted) // not cancelled and not completed
    {
        [self sendFailureAndComplete:error checkBeforeCallback:YES];
    }
}

- (void) sendFailureAndComplete: (NSError *) error checkBeforeCallback: (BOOL) checkBeforeCallback
{
    // send completion first so that data service can perform the cleanup, then send the callback
    SEDataRequestSendCompletionToService(_requestService, self);
    
    void (^failureBlock)(NSError *) = _failure;
    if (failureBlock)
    {
        dispatch_async(_completionQueue, ^{
            // need to check for cancellation right before here
            if (!checkBeforeCallback || !OSAtomicTestAndSet(CANCELLED_REQUEST_BIT, &_completed))
                failureBlock(error);
        });
    }
}

#pragma mark - Error mapping

+ (NSString *) errorMessageForHTTPCode: (NSInteger) httpCode
{
    switch (httpCode)
    {
        case 400: return @"Bad Request";
        case 401: return @"Unauthorized";
        case 402: return @"Payment Required";
        case 403: return @"Forbidden";
        case 404: return @"Not Found";
        case 405: return @"Method Not Allowed";
        case 406: return @"Not Acceptable";
        case 407: return @"Proxy Authentication Required";
        case 408: return @"Request Timeout";
        case 409: return @"Conflict";
        case 410: return @"Gone";
        case 411: return @"Length Required";
        case 412: return @"Precondition Failed";
        case 413: return @"Request Entity Too Large";
        case 414: return @"Request-URI Too Long";
        case 415: return @"Unsupported Media Type";
        case 416: return @"Requested Range Not Satisfiable";
        case 417: return @"Expectation Failed";

        case 500: return @"Internal Server Error";
        case 501: return @"Not Implemented";
        case 502: return @"Bad Gateway";
        case 503: return @"Service Unavailable";
        case 504: return @"Gateway Timeout";
        case 505: return @"HTTP Version Not Supported";
    }

    return nil;
}

#pragma mark - Helpful functions

+ (NSArray *) deserializeArray: (NSArray *) array toClass: (Class) dataClass error: (NSError * __autoreleasing *) error
{
    NSError *innerError = nil;
    NSMutableArray *resultingArray = [[NSMutableArray alloc] initWithCapacity:array.count];
    for (NSDictionary *object in array)
    {
        if ([object isKindOfClass:[NSDictionary class]])
        {
            id parsedObject = [dataClass deserializeFromJSON: object];
            if (parsedObject == nil)
            {
                innerError = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:nil];
                break;
            }
            else
            {
                [resultingArray addObject:parsedObject];
            }
        }
    }
    
    if (innerError == nil) return [resultingArray copy];

    if (error != nil) *error = innerError;
    return nil;
}

@end

@implementation SEInternalMultipartContents
- (instancetype)init
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithMultipartContents:(NSArray<SEMultipartRequestContentPart *> *)multipartContents boundary:(NSString *)boundary
{
#ifdef DEBUG
    if (multipartContents == nil) THROW_INVALID_PARAM(multipartContents, nil);
    if (boundary == nil) THROW_INVALID_PARAM(boundary, nil);
#endif
    self = [super init];
    if (self)
    {
        _multipartContents = multipartContents;
        _boundary = boundary;
    }
    return self;
}
@end

@implementation SEInternalDownloadRequestParameters
- (instancetype)init
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithSaveAsURL:(NSURL *)saveAsURL downloadProgressCallback:(void (^)(int64_t, int64_t, int64_t))progress
{
#ifdef DEBUG
    if (saveAsURL == nil || ![saveAsURL isFileURL]) THROW_INVALID_PARAM(saveAsURL, nil);
#endif
    self = [super init];
    if (self)
    {
        _saveAsURL = saveAsURL;
        _progress = progress;
    }
    return self;
}
@end
