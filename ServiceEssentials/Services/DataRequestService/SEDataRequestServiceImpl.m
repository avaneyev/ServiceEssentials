//
//  SEDataRequestServiceImpl.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import "SEDataRequestServiceImpl.h"

#include <objc/runtime.h>
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
@import UIKit;
#endif

#import "SEDataRequestServicePrivate.h"
#import "SETools.h"
#import "NSString+SEExtensions.h"
#import "SEEnvironmentService.h"
#import "SEInternalDataRequest.h"

#import "SEDataSerializer.h"
#import "SEJSONDataSerializer.h"
#import "SEPlainTextSerializer.h"
#import "SEWebFormSerializer.h"
#import "SEDataRequestServiceSecurityHelper.h"
#import "SENetworkReachabilityTracker.h"
#import "SEInternalDataRequestBuilder.h"
#import "SEMultipartRequestContentStream.h"

// Macro for graceful handling of an error while building data requests
#define HANDLE_BUILD_REQUEST_ERROR_GRACEFUL(message) do { if (error != nil) { *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceRequestSubmissuionFailure userInfo:@{NSLocalizedDescriptionKey: message}]; } \
SELog(@"%@", message); \
return nil; } while(0)

// Macro for generic handling of an error while building data requests (graceful in Release, crash in Debug)
#ifdef DEBUG
#define HANDLE_BUILD_REQUEST_ERROR(message) do { THROW_INVALID_PARAM(body, @{ NSLocalizedDescriptionKey: message }); } while(0)
#else
#define HANDLE_BUILD_REQUEST_ERROR(message) HANDLE_BUILD_REQUEST_ERROR_GRACEFUL(message)
#endif

const NSStringEncoding SEDataRequestServiceStringEncoding = NSUTF8StringEncoding;

NSString * const SEDataRequestServiceContentTypeJSON = @"application/json";
NSString * const SEDataRequestServiceContentTypeURLEncode = @"application/x-www-form-urlencoded";
NSString * const SEDataRequestServiceContentTypePlainText = @"text/plain";
NSString * const SEDataRequestServiceContentTypeTextHTML = @"text/html";
NSString * const SEDataRequestServiceContentTypeOctetStream = @"application/octet-stream";

NSString * const SEDataRequestServiceChangedReachabilityNotification = @"SEDataRequestServiceChangedReachabilityNotification";
NSString * const SEDataRequestServiceChangedReachabilityStatusKey = @"reachabilityStatus";

static NSInteger const SEDataRequestServiceErrorStart = 1000;
NSInteger const SEDataRequestServiceSerializationFailure = SEDataRequestServiceErrorStart;
NSInteger const SEDataRequestServiceTrustFailure = SEDataRequestServiceErrorStart + 1;
NSInteger const SEDataRequestServiceRequestCancelled = SEDataRequestServiceErrorStart + 2;
NSInteger const SEDataRequestServiceRequestSubmissuionFailure = SEDataRequestServiceErrorStart + 3;
NSInteger const SEDataRequestServiceRequestBuilderFailure = SEDataRequestServiceErrorStart + 4;

NSString * _Nonnull const SEDataRequestServiceErrorDeserializedContentKey = @"ErrorDeserializedContentKey";

static NSString * _Nonnull const SEDataRequestServiceBackgroundTaskId = @"com.service-essentials.DataRequestServiceService.background";


@interface SEDataRequestServiceImpl () <NSURLSessionDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate, SEDataRequestServicePrivate, SENetworkReachabilityTrackerDelegate>
@end

@implementation SEDataRequestServiceImpl
{
    id<SEEnvironmentService> _environmentService;
    NSURLSession *_session;
    NSOperationQueue *_queue;
    NSURL *_baseURL;
    SENetworkReachabilityTracker *_reachabilityTracker;
    SEDataRequestCertificatePinningType _pinningType;
    
    NSMutableDictionary<id<SECancellableToken>, SEInternalDataRequest *> *_internalRequestsByKey;
    NSMutableDictionary<NSNumber *, SEInternalDataRequest *> *_internalRequestsByTask;
    NSLock *_lock;
    
    NSDictionary *_dataSerializers;
    SEDataSerializer *_defaultSerializer;
    
    NSString *_userAgent;
    NSString *_authorizationHeader;
    
    BOOL _applicationBackgroundDefault;
    
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
    UIBackgroundTaskIdentifier _backgroundTaskId;
#endif
}

- (instancetype)initWithEnvironmentService:(id<SEEnvironmentService>)environmentService sessionConfiguration:(NSURLSessionConfiguration *)configuration pinningType:(SEDataRequestCertificatePinningType)certificatePinningType applicationBackgroundDefault:(BOOL)backgroundDefault
{
    if (environmentService == nil) THROW_INVALID_PARAMS(nil);
    
    self = [super init];
    if (self)
    {
        _environmentService = environmentService;
        if (configuration == nil) configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        
        _queue = [[NSOperationQueue alloc] init];
        _queue.maxConcurrentOperationCount = 5;
        _queue.qualityOfService = NSQualityOfServiceBackground;
        _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:_queue];
        _baseURL = [environmentService environmentBaseURL];
        _pinningType = certificatePinningType;
        _applicationBackgroundDefault = backgroundDefault;
        
        _internalRequestsByKey = [[NSMutableDictionary alloc] initWithCapacity:1];
        _internalRequestsByTask = [[NSMutableDictionary alloc] initWithCapacity:1];
        _lock = [[NSLock alloc] init];
        
        _defaultSerializer = [SEDataSerializer new];
        SEDataSerializer *plainTextDeserializer = [SEPlainTextSerializer new];

        _dataSerializers = @{
                             SEDataRequestServiceContentTypeJSON        : [SEJSONDataSerializer new],
                             SEDataRequestServiceContentTypePlainText   : plainTextDeserializer,
                             SEDataRequestServiceContentTypeTextHTML    : plainTextDeserializer,
                             SEDataRequestServiceContentTypeURLEncode   : [SEWebFormSerializer new],
                             SEDataRequestServiceContentTypeOctetStream : _defaultSerializer
                             };
        
        _userAgent = [SEDataRequestServiceImpl userAgentValue];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onUpdateEnvironment:) name:SEEnvironmentChangedNotification object:environmentService];

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
        _backgroundTaskId = UIBackgroundTaskInvalid;
        NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
        [defaultCenter addObserver:self selector:@selector(onDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [defaultCenter addObserver:self selector:@selector(onWillResumeActive:) name:UIApplicationWillEnterForegroundNotification object:nil];
        [defaultCenter addObserver:self selector:@selector(onWillTerminateApplication:) name:UIApplicationWillTerminateNotification object:nil];
#endif
        
        // track connectivity/reachability
        if ([SENetworkReachabilityTracker isReachabilityAvailable])
        {
            _reachabilityTracker = [[SENetworkReachabilityTracker alloc] initWithURL:_baseURL delegate:self dispatchQueue:dispatch_get_main_queue()];
        }
    }
    return self;
}

- (instancetype)initWithEnvironmentService:(id<SEEnvironmentService>)environmentService sessionConfiguration:(NSURLSessionConfiguration *)configuration
{
    return [self initWithEnvironmentService:environmentService sessionConfiguration:configuration pinningType:SEDataRequestCertificatePinningTypeCertificate applicationBackgroundDefault:NO];
}

- (void)dealloc
{
    [_session invalidateAndCancel];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void) onWillTerminateApplication: (NSNotification *) notification
{
    [_session invalidateAndCancel];
    _session = nil;
}

- (void) onDidEnterBackground: (NSNotification *)notification
{
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
    [self checkNeedsFinishRequestsInBackground];
#endif
}

- (void) onWillResumeActive: (NSNotification *)notification
{
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
    [self checkNeedsFinishBackgroundTask];
#endif
}

- (void) onUpdateEnvironment: (NSNotification *) notification
{
    NSURL *newUrl = [_environmentService environmentBaseURL];
    @try
    {
        [_lock lock];
        if (![newUrl isEqual:_baseURL])
        {
            _baseURL = [_environmentService environmentBaseURL];
            
            // TODO: implement the rest of environment switch if needed (cancel requests and so on)
        }
    }
    @finally
    {
        [_lock unlock];
    }
}

#pragma mark - Interface

- (BOOL)isReachable
{
    SENetworkReachabilityStatus status = [self reachabilityStatus];
    return status == SENetworkReachabilityStatusReachableLocal || status == SENetworkReachabilityStatusReachableViaWiFi || status == SENetworkReachabilityStatusReachableViaWWAN;
}

- (SENetworkReachabilityStatus)reachabilityStatus
{
    if (_reachabilityTracker != nil) return _reachabilityTracker.reachability;
    return SENetworkReachabilityStatusUnavailable;
}

- (void)setAuthorizationHeader:(NSString *)authorizationHeader
{
#ifdef DEBUG
    if (authorizationHeader == nil) THROW_INVALID_PARAM(authorizationHeader, nil);
#endif
    
    if (authorizationHeader != _authorizationHeader)
    {
        _authorizationHeader = authorizationHeader;
    }
}

- (void)clearAuthorization
{
    _authorizationHeader = nil;
}

- (id<SECancellableToken>)GET:(NSString *)path parameters:(NSDictionary <NSString *, id> *)parameters success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    return [self GET:path parameters:parameters deserializeToClass:nil success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>)GET:(NSString *)path parameters:(NSDictionary<NSString *,id> *)parameters deserializeToClass:(Class)class success:(void (^)(id _Nonnull, NSURLResponse * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    if (class != nil && ![SEDataRequestServiceImpl verifyDeserializationClass:class failure:failure completionQueue:completionQueue])
    {
        return nil;
    }
    
    return [self buildAndSubmitSimpleRequestWithMethod:@"GET" path:path parameters:parameters mimeType:nil deserializationClass:class success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>)POST:(NSString *)path parameters:(NSDictionary <NSString *, id> *)parameters success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    return [self POST:path parameters:parameters contentEncoding:nil deserializeToClass:nil success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>)POST:(NSString *)path parameters:(NSDictionary<NSString *,id> *)parameters contentEncoding:(NSString *)encoding success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    return [self POST:path parameters:parameters contentEncoding:encoding deserializeToClass:nil success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>)POST:(NSString *)path parameters:(NSDictionary<NSString *,id> *)parameters contentEncoding:(NSString *)encoding deserializeToClass:(Class)class success:(void (^)(id _Nonnull, NSURLResponse * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
#ifdef DEBUG
    if (encoding != nil)
    {
        SEDataSerializer *bodySerializer = [_dataSerializers objectForKey:encoding];
        if (bodySerializer == nil) THROW_INVALID_PARAM(encoding, @{ NSLocalizedDescriptionKey: @"Serializer not found for content type" });
    }
#endif
    
    if (class != nil && ![SEDataRequestServiceImpl verifyDeserializationClass:class failure:failure completionQueue:completionQueue])
    {
        return nil;
    }
    
    return [self buildAndSubmitSimpleRequestWithMethod:@"POST" path:path parameters:parameters mimeType:encoding deserializationClass:class success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>)PUT:(NSString *)path parameters:(NSDictionary<NSString *,id> *)parameters success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    return [self buildAndSubmitSimpleRequestWithMethod:@"PUT" path:path parameters:parameters mimeType:nil deserializationClass:nil success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>)download:(NSString *)path parameters:(NSDictionary<NSString *,id> *)parameters saveAs:(NSURL *)saveAsURL success:(void (^)(id _Nullable, NSURLResponse * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure progress:(void (^)(int64_t, int64_t, int64_t))progress completionQueue:(dispatch_queue_t)completionQueue
{
    if (path == nil) THROW_INVALID_PARAM(url, @{ NSLocalizedDescriptionKey: @"Invalid URL"} );
    if (saveAsURL == nil || ![saveAsURL isFileURL]) THROW_INVALID_PARAM(saveAsURL, @{ NSLocalizedDescriptionKey: @"Invalid URL to save a file" });

    BOOL needsBody = NO;
    NSError *error = nil;
    NSURL *url = [self buildURLWithPath:path forMethod:@"GET" body:parameters needsBodyData:&needsBody error:&error];
    
    if (url == nil)
    {
#ifdef DEBUG
        HANDLE_BUILD_REQUEST_ERROR(error.localizedDescription);
#endif
        if (failure != nil)
        {
            if (error == nil) error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceRequestSubmissuionFailure userInfo:@{ NSLocalizedDescriptionKey: @"Invalid URL" }];
            dispatch_async(completionQueue, ^{ failure(error); });
        }
        return nil;
    }
    else
    {
        NSMutableURLRequest *request = [self createRequestWithMethod:@"GET" authorized:YES url:url data:nil contentType:nil acceptContentType:SEDataRequestAcceptContentTypeData charset:nil];
        
        return [self createDownloadRequestWithURLRequest:request saveFileAs:saveAsURL expectedHTTPCodes:nil success:success failure:failure progress:progress completionQueue:completionQueue];
    }
}

- (id<SEDataRequestBuilder>)createRequestBuilder
{
    return [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:self];
}

- (BOOL)validateSecurityChallenge:(NSURLAuthenticationChallenge *)challenge
{
    BOOL accept = NO;
    if([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
    {
        SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
        NSError *error = nil;
        
        SEDataRequestCertificatePinningType pinningType = _pinningType;
        if (![challenge.protectionSpace.host isEqualToString:_baseURL.host]) pinningType = SEDataRequestCertificatePinningTypeNone;
        
        switch (pinningType)
        {
            case SEDataRequestCertificatePinningTypeNone:
                accept = [SEDataRequestServiceSecurityHelper validateTrustDefault:serverTrust error:&error];
                break;
            case SEDataRequestCertificatePinningTypeCertificate:
                accept = [SEDataRequestServiceSecurityHelper validateTrustUsingCertificates:serverTrust error:&error];
                break;
            case SEDataRequestCertificatePinningTypePublicKey:
                accept = [SEDataRequestServiceSecurityHelper validateTrustUsingPublicKeys:serverTrust error:&error];
                break;
#ifdef ALLOWS_TEST_ENVIRONMENTS
            case SEDataRequestCertificatePinningTypeNoneAcceptRecoverableFailure:
                accept = [SEDataRequestServiceSecurityHelper validateTrustDefaultAcceptRecoverable:serverTrust error:&error];
                break;
#endif
                
            default:
                accept = NO;
                break;
        }
        
        if (error != nil) SELog(@"Security challenge error: %@", error);
    }
    return accept;
}

#pragma mark - Unsafe URL Request service interface

- (id<SECancellableToken>)URLGET:(NSURL *)url parameters:(NSDictionary<NSString *,id> *)parameters success:(void (^)(id _Nonnull, NSURLResponse * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    if (url == nil || [url isFileURL]) THROW_INVALID_PARAM(url, @{ NSLocalizedDescriptionKey: @"Invalid URL"} );
    
    if (parameters != nil) url = [SEDataRequestServiceImpl appendQueryStringToURL:url queryParameters:parameters encoding:[self stringEncoding]];
    
    NSMutableURLRequest *request = [self createRequestWithMethod:@"GET" authorized:NO url:url data:nil contentType:nil acceptContentType:SEDataRequestAcceptContentTypeData charset:nil];

    return [self createDataRequestWithURLRequest:request dataClass:nil expectedHTTPCodes:nil success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>)URLDownload:(NSURL *)url parameters:(NSDictionary<NSString *,id> *)parameters saveAs:(NSURL *)saveAsURL success:(void (^)(id _Nullable, NSURLResponse * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure progress:(void (^)(int64_t, int64_t, int64_t))progress completionQueue:(dispatch_queue_t)completionQueue
{
    if (url == nil || [url isFileURL]) THROW_INVALID_PARAM(url, @{ NSLocalizedDescriptionKey: @"Invalid URL"} );
    if (saveAsURL == nil || ![saveAsURL isFileURL]) THROW_INVALID_PARAM(saveAsURL, @{ NSLocalizedDescriptionKey: @"Invalid URL to save a file" });

    if (parameters != nil) url = [SEDataRequestServiceImpl appendQueryStringToURL:url queryParameters:parameters encoding:[self stringEncoding]];
    
    NSMutableURLRequest *request = [self createRequestWithMethod:@"GET" authorized:NO url:url data:nil contentType:nil acceptContentType:SEDataRequestAcceptContentTypeData charset:nil];

    return [self createDownloadRequestWithURLRequest:request saveFileAs:saveAsURL expectedHTTPCodes:nil success:success failure:failure progress:progress completionQueue:completionQueue];
}

#pragma mark - Private interface

- (NSStringEncoding)stringEncoding
{
    return SEDataRequestServiceStringEncoding;
}

- (void)cancelItemForToken:(id<SECancellableToken>)token
{
    SEInternalDataRequest *request = nil;
    @try
    {
        [_lock lock];
        request = [_internalRequestsByKey objectForKey:token];
    }
    @finally
    {
        [_lock unlock];
    }
    
    if (request) [request cancel];
}

- (void) completeInternalRequest:(SEInternalDataRequest *)request
{
    @try
    {
        [_lock lock];
        [_internalRequestsByKey removeObjectForKey:request.token];
        NSURLSessionTask *task = request.task;
        if (task != nil) [_internalRequestsByTask removeObjectForKey:@(task.taskIdentifier)];
        
        if (_internalRequestsByKey.count == 0) [self completeBackgroundTaskIfNeeded];
    }
    @finally
    {
        [_lock unlock];
    }
}

- (SEDataSerializer *)explicitSerializerForMIMEType:(NSString *)mimeType
{
    NSRange rangeOfSeparator = [mimeType rangeOfString:@";"];
    NSString *trueType = (rangeOfSeparator.location == NSNotFound) ? trueType = mimeType : [mimeType substringToIndex:rangeOfSeparator.location];
    // for now just an explicit check. may need a type/subtype check, for example for different encodings of text
    SEDataSerializer *serializer = [_dataSerializers objectForKey:trueType];
    if (serializer != nil) return serializer;
    return nil;
}

- (SEDataSerializer *)serializerForMIMEType:(NSString *)mimeType
{
    SEDataSerializer *serializer = [self explicitSerializerForMIMEType:mimeType];
    if (serializer != nil) return serializer;
    return _defaultSerializer;
}

- (id<SECancellableToken>)submitRequestWithBuilder:(SEInternalDataRequestBuilder *)requestBuilder asUpload:(BOOL)asUpload
{
    NSError *error = nil;
    NSMutableURLRequest *baseRequest;
    if (requestBuilder.contentParts == nil)
    {
        // regular, non-multipart request
        baseRequest = [self buildRequestWithMethod:requestBuilder.method path:requestBuilder.path body:requestBuilder.bodyParameters mimeType:requestBuilder.contentEncoding acceptContentType:requestBuilder.acceptContentType error:&error];
        
        if (baseRequest != nil)
        {
            [SEDataRequestServiceImpl assignHeaders:requestBuilder.headers toURLRequest:baseRequest];
            
            if (asUpload)
            {
                return [self createDataRequestWithURLRequest:baseRequest dataClass:requestBuilder.deserializeClass expectedHTTPCodes:requestBuilder.expectedHTTPCodes success:requestBuilder.success failure:requestBuilder.failure completionQueue:requestBuilder.completionQueue];
            }
            else
            {
                return [self createUploadRequestWithURLRequest:baseRequest data:baseRequest.HTTPBody dataClass:requestBuilder.deserializeClass expectedHTTPCodes:requestBuilder.expectedHTTPCodes success:requestBuilder.success failure:requestBuilder.failure completionQueue:requestBuilder.completionQueue];
            }
        }
    }
    else
    {
        // multipart request
        baseRequest = [self createRequestWithMethod:requestBuilder.method authorized:YES url:[self validateAndCreateURLWithPath:requestBuilder.path] data:nil contentType:nil acceptContentType:SEDataRequestAcceptContentTypeData charset:nil];

        NSString *boundary = [SEDataRequestServiceImpl generateRandomBoundaryString];
        NSString *mimeType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
        [baseRequest setValue:mimeType forHTTPHeaderField:@"Content-Type"];
        
        [SEDataRequestServiceImpl assignHeaders:requestBuilder.headers toURLRequest:baseRequest];

        unsigned long long contentLength = [SEMultipartRequestContentStream contentLengthForParts:requestBuilder.contentParts boundary:boundary stringEncoding:SEDataRequestServiceStringEncoding];
            [baseRequest setValue:[NSString stringWithFormat:@"%llu", contentLength] forHTTPHeaderField:@"Content-Length"];
            
        return [self createStreamedUploadRequestWithURLRequest:baseRequest dataClass:requestBuilder.deserializeClass expectedHTTPCodes:requestBuilder.expectedHTTPCodes multipartContents:requestBuilder.contentParts boundary:boundary success:requestBuilder.success failure:requestBuilder.failure completionQueue:requestBuilder.completionQueue];
    }
    
    if (error && requestBuilder.failure != nil)
    {
        dispatch_async(requestBuilder.completionQueue, ^{ requestBuilder.failure(error); });
    }
    return nil;
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler
{
    // validation will take host into account and check if it's the 'safe' host or not, and will apply policy correspondingly.
    BOOL accept = [self validateSecurityChallenge:challenge];
    if (accept)
    {
        SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
        NSURLCredential *credential = [NSURLCredential credentialForTrust:serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    }
    else
    {
        SELog(@"WARNING: discarding an invalid certificate from host: %@", challenge.protectionSpace.host);
        
        completionHandler(NSURLSessionAuthChallengeRejectProtectionSpace, nil);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    SEInternalDataRequest *dataRequest = nil;
    @try
    {
        [_lock lock];
        dataRequest = [_internalRequestsByTask objectForKey:@(task.taskIdentifier)];
    }
    @finally
    {
        [_lock unlock];
    }
 
    if (dataRequest) [dataRequest completeWithError:error];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    SEInternalDataRequest *dataRequest = nil;
    @try
    {
        [_lock lock];
        dataRequest = [_internalRequestsByTask objectForKey:@(dataTask.taskIdentifier)];
    }
    @finally
    {
        [_lock unlock];
    }
    
    if ((dataRequest == nil) || (dataRequest.isCompleted))
    {
        completionHandler(NSURLSessionResponseCancel);
    }
    else
    {
        if([dataRequest receivedURLResponse:response])
            completionHandler(NSURLSessionResponseAllow);
        else
            completionHandler(NSURLSessionResponseCancel);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    SEInternalDataRequest *dataRequest = nil;
    @try
    {
        [_lock lock];
        dataRequest = [_internalRequestsByTask objectForKey:@(dataTask.taskIdentifier)];
    }
    @finally
    {
        [_lock unlock];
    }
    
    if ((dataRequest != nil) && !dataRequest.isCompleted) [dataRequest receivedData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task needNewBodyStream:(void (^)(NSInputStream * _Nullable))completionHandler
{
    SEInternalDataRequest *dataRequest = nil;
    @try
    {
        [_lock lock];
        dataRequest = [_internalRequestsByTask objectForKey:@(task.taskIdentifier)];
    }
    @finally
    {
        [_lock unlock];
    }
    
    if ((dataRequest != nil) && !dataRequest.isCompleted)
    {
        completionHandler([dataRequest createStream]);
    }
    else
    {
        completionHandler(nil);
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location
{
    SEInternalDataRequest *dataRequest = nil;
    @try
    {
        [_lock lock];
        dataRequest = [_internalRequestsByTask objectForKey:@(downloadTask.taskIdentifier)];
    }
    @finally
    {
        [_lock unlock];
    }
    
    if ((dataRequest != nil) && !dataRequest.isCompleted)
    {
        [dataRequest downloadRequestDidFinishDownloadingToURL:location];
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    SEInternalDataRequest *dataRequest = nil;
    @try
    {
        [_lock lock];
        dataRequest = [_internalRequestsByTask objectForKey:@(downloadTask.taskIdentifier)];
    }
    @finally
    {
        [_lock unlock];
    }
    
    if ((dataRequest != nil) && !dataRequest.isCompleted)
    {
        [dataRequest downloadRequestDidWriteData:bytesWritten totalBytesWritten:totalBytesWritten totalBytesExpectedToWrite:totalBytesExpectedToWrite];
    }
}

#pragma mark - request building

- (id<SECancellableToken>) buildAndSubmitSimpleRequestWithMethod:(NSString *)method path:(NSString *)path parameters:(NSDictionary *)parameters mimeType:(NSString *)mimeType deserializationClass:(Class)class success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    NSError *error = nil;
    NSURLRequest *urlRequest = [self buildRequestWithMethod:method path:path body:parameters mimeType:mimeType acceptContentType:SEDataRequestAcceptContentTypeJSON error:&error];
    
    if (urlRequest != nil)
    {
        return [self createDataRequestWithURLRequest:urlRequest dataClass:class expectedHTTPCodes:nil success:success failure:failure completionQueue:completionQueue];
    }
    else
    {
        if (failure) dispatch_async(completionQueue, ^{ failure(error); });
        return nil;
    }
}

/** Creates and submits standard data task */
- (id<SECancellableToken>) createDataRequestWithURLRequest: (NSURLRequest *) urlRequest dataClass:(Class) dataClass expectedHTTPCodes:(NSIndexSet *)expectedCodes success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    NSURLSessionDataTask *dataTask = [_session dataTaskWithRequest:urlRequest];
    return [self createInternalRequestWithTask:dataTask dataClass:dataClass expectedHTTPCodes:expectedCodes multipartContents:nil downloadParameters:nil success:success failure:failure completionQueue:completionQueue];
}

/** Creates and submits upload data task with provided data */
- (id<SECancellableToken>) createUploadRequestWithURLRequest: (NSURLRequest *) urlRequest data:(NSData *) data dataClass:(Class) dataClass expectedHTTPCodes:(NSIndexSet *)expectedCodes success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    NSURLSessionDataTask *dataTask = [_session uploadTaskWithRequest:urlRequest fromData:data];
    return [self createInternalRequestWithTask:dataTask dataClass:dataClass expectedHTTPCodes:expectedCodes multipartContents:nil downloadParameters:nil success:success failure:failure completionQueue:completionQueue];
}

/** Creates and submits upload data task with a file */
- (id<SECancellableToken>) createUploadRequestWithURLRequest: (NSURLRequest *) urlRequest file:(NSURL *) dataFile dataClass:(Class) dataClass expectedHTTPCodes:(NSIndexSet *)expectedCodes success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    NSURLSessionDataTask *dataTask = [_session uploadTaskWithRequest:urlRequest fromFile:dataFile];
    return [self createInternalRequestWithTask:dataTask dataClass:dataClass expectedHTTPCodes:expectedCodes multipartContents:nil downloadParameters:nil success:success failure:failure completionQueue:completionQueue];
}

/** Creates and submits streamed uploda data task - will have to provide the stream as well. Will use for some of the multipart submissions. */
- (id<SECancellableToken>) createStreamedUploadRequestWithURLRequest: (NSURLRequest *) urlRequest dataClass:(Class) dataClass expectedHTTPCodes:(NSIndexSet *)expectedCodes multipartContents:(NSArray *)multipartContents boundary:(NSString *)boundary success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    NSURLSessionUploadTask *dataTask = [_session uploadTaskWithStreamedRequest:urlRequest];
    SEInternalMultipartContents *multipartParameters = (multipartContents == nil || boundary == nil) ? nil : [[SEInternalMultipartContents alloc] initWithMultipartContents:multipartContents boundary:boundary];
    return [self createInternalRequestWithTask:dataTask dataClass:dataClass expectedHTTPCodes:expectedCodes multipartContents:multipartParameters downloadParameters:nil success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>) createDownloadRequestWithURLRequest: (NSURLRequest *) urlRequest saveFileAs: (NSURL *) saveAs expectedHTTPCodes:(NSIndexSet *)expectedCodes success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure progress:(void (^)(int64_t, int64_t, int64_t))progress completionQueue:(dispatch_queue_t)completionQueue
{
    NSURLSessionDownloadTask *downloadTask = [_session downloadTaskWithRequest:urlRequest];
    SEInternalDownloadRequestParameters *downloadRequestParameters = [[SEInternalDownloadRequestParameters alloc] initWithSaveAsURL:saveAs downloadProgressCallback:progress];
    return [self createInternalRequestWithTask:downloadTask dataClass:nil expectedHTTPCodes:nil multipartContents:nil downloadParameters:downloadRequestParameters success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>) createInternalRequestWithTask: (NSURLSessionTask *) dataTask dataClass:(Class) dataClass expectedHTTPCodes:(NSIndexSet *)expectedCodes multipartContents:(SEInternalMultipartContents *)multipartContents downloadParameters:(SEInternalDownloadRequestParameters *)downloadParameters success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    SEInternalDataRequest *internalRequest = [[SEInternalDataRequest alloc] initWithSessionTask:dataTask requestService:self responseDataClass:dataClass expectedHTTPCodes:expectedCodes multipartContents:multipartContents downloadParameters:downloadParameters success:success failure:failure completionQueue:completionQueue];
    
    @try
    {
        [_lock lock];
        [_internalRequestsByKey setObject:internalRequest forKey:internalRequest.token];
        [_internalRequestsByTask setObject:internalRequest forKey:@(dataTask.taskIdentifier)];
    }
    @catch (NSException *e)
    {
        SELog(@"Failed obtaining a lock with error %@", e);
        return nil;
    }
    @finally
    {
        [_lock unlock];
    }
    
    [dataTask resume];
    
    return internalRequest.token;
}

- (NSURL *) buildURLWithPath:(NSString *)path forMethod:(NSString *)method body:(id)body needsBodyData:(BOOL *)needsBody error: (NSError * __autoreleasing *) error
{
    NSURL *fullUrl;
    *needsBody = NO;
    if ([method isEqualToString:@"GET"] || [method isEqualToString:@"HEAD"] || [method isEqualToString:@"DELETE"])
    {
        if (body != nil)
        {
            if ([body isKindOfClass:[NSDictionary class]]) fullUrl = [self makeURLWithPath:path parameters:body];
            else
            {
                NSString *message = [NSString stringWithFormat:@"Not a valid body type for %@ request: %@", method, [body class]];
                HANDLE_BUILD_REQUEST_ERROR(message);
            }
        }
        else
        {
            fullUrl = [self validateAndCreateURLWithPath:path];
        }
    }
    else
    {
        fullUrl = [self validateAndCreateURLWithPath:path];
        *needsBody = YES;
    }
    return fullUrl;
}

- (NSData *) buildRequestDataWithBody:(id)body mimeType:(NSString *)mimeType charset:(NSString *)charset contentTypeOut:(NSString * __autoreleasing *)contentTypeOut error: (NSError * __autoreleasing *) error
{
    if (contentTypeOut == nil) THROW_INVALID_PARAM(contentTypeOut, nil);
    
    NSData *data = nil;
    NSString *contentType = nil;

    if (mimeType != nil)
    {
        NSError *serializationError = nil;
        SEDataSerializer *serializer = [_dataSerializers objectForKey:mimeType];
        if (serializer == nil)
        {
            NSString *message = [NSString stringWithFormat:@"Serializer not found for type %@", mimeType];
            HANDLE_BUILD_REQUEST_ERROR_GRACEFUL(message);
        }
        data = [serializer serializeObject:body mimeType:mimeType error:&serializationError];
        if (serializationError != nil)
        {
            if (error) *error = serializationError;
            SELog("Failed to serialize request data: %@", serializationError);
            return nil;
        }
        contentType = [NSString stringWithFormat:@"%@; charset=%@", mimeType, charset];
    }
    else if ([body isKindOfClass:[NSString class]])
    {
        NSString *text = body;
        data = [text dataUsingEncoding:SEDataRequestServiceStringEncoding];
        contentType = [NSString stringWithFormat:@"text/plain; charset=%@", charset];
    }
    else if ([body isKindOfClass:[NSArray class]] || [body isKindOfClass:[NSDictionary class]] || [body isKindOfClass:[NSNumber class]])
    {
        NSError *jsonError = nil;
        data = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
        
        if (jsonError != nil)
        {
            if (error) *error = jsonError;
            SELog("Failed to serialize request data: %@", jsonError);
            return nil;
        }
        
        contentType = [NSString stringWithFormat:@"application/json; charset=%@", charset];
    }
    else
    {
        NSString *message = [NSString stringWithFormat:@"Not a valid request data type: %@", [body class]];
        HANDLE_BUILD_REQUEST_ERROR_GRACEFUL(message);
    }

    *contentTypeOut = contentType;
    return data;
}

- (NSMutableURLRequest *) createRequestWithMethod:(NSString *)method authorized:(BOOL)authorized url:(NSURL *)url data:(NSData *)data contentType:(NSString *)contentType acceptContentType: (SEDataRequestAcceptContentType) acceptType charset:(NSString *)charset
{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setHTTPMethod:method];
    [request setURL:url];
    
    
    if (_userAgent) [request setValue:_userAgent forHTTPHeaderField:@"User-Agent"];

    if (authorized)
    {
        if (_authorizationHeader != nil) [request setValue:_authorizationHeader forHTTPHeaderField:@"Authorization"];
    }

    if (acceptType == SEDataRequestAcceptContentTypeJSON)
    {
        NSString *acceptHeader = [NSString stringWithFormat:@"application/json; charset=%@", charset];
        [request setValue:acceptHeader forHTTPHeaderField:@"Accept"];
    }
    
    if (data)
    {
        [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
        [request setHTTPBody:data];
    }
    
    return request;
}

- (NSMutableURLRequest *) buildRequestWithMethod: (NSString *) method path: (NSString *) path body: (id) body mimeType: (NSString *) mimeType acceptContentType: (SEDataRequestAcceptContentType) acceptType error: (NSError * __autoreleasing *) error
{
    // compose the URL
    BOOL needsBody = NO;
    NSURL *fullUrl = [self buildURLWithPath:path forMethod:method body:body needsBodyData:&needsBody error:error];
    
    if (fullUrl == nil)
    {
        NSString *message = [NSString stringWithFormat:@"Not a valid request URL combination of path [%@], base [%@] and parameters [%@]", path, _baseURL, needsBody ? @"n/a" : body];
        HANDLE_BUILD_REQUEST_ERROR(message);
    }
    
    // if necessary - create the request body
    NSString *charset = (__bridge NSString *)CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(SEDataRequestServiceStringEncoding));
    NSString *contentType = nil;
    NSData *data = nil;

    if (needsBody && (body != nil))
    {
        data = [self buildRequestDataWithBody:body mimeType:mimeType charset:charset contentTypeOut:&contentType error:error];
        if (data == nil) return nil;
    }
    
    // assign everything to a request
    return [self createRequestWithMethod:method authorized:YES url:fullUrl data:data contentType:contentType acceptContentType:acceptType charset:charset];
}

+ (void) assignHeaders:(NSDictionary *)headers toURLRequest:(NSMutableURLRequest *)request
{
    if (headers != nil)
    {
        NSDictionary *existingHeaders = request.allHTTPHeaderFields;
        for (NSString *header in headers)
        {
            if (![existingHeaders objectForKey:header])
            {
#ifdef DEBUG
                NSDictionary *info = @{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Attempting to override existing header %@", header] };
                THROW_INVALID_PARAM(headers, info);
#else
                continue;
#endif
            }
            [request setValue:[headers objectForKey:header] forHTTPHeaderField:header];
        }
    }
}

- (NSURL *)makeURLWithPath: (NSString *) path parameters: (NSDictionary *) parameters
{
    NSString *urEncodedParameters = [SEWebFormSerializer webFormEncodedStringFromDictionary:parameters withEncoding:NSUTF8StringEncoding];
    NSString *appendString = ([path rangeOfString:@"?"].location == NSNotFound) ? @"?" : @"&";
    return [self validateAndCreateURLWithPath:[NSString stringWithFormat:@"%@%@%@", path, appendString, urEncodedParameters]];
}

- (NSURL *)validateAndCreateURLWithPath:(NSString *)path
{
    NSURL *url = [NSURL URLWithString:path relativeToURL:_baseURL];
    if (![url.scheme isEqualToString:_baseURL.scheme] || ![url.host isEqualToString:_baseURL.host])
    {
        THROW_INVALID_PARAM(path, @{ NSLocalizedDescriptionKey: @"Path is not really a path, it modifies host or scheme and cannot be accepted." });
    }
    return url;
}

#pragma mark - Headers and other Auxillary Stuff

+ (NSString *) userAgentValue
{
    // User-Agent Header; see http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.43

    NSString *userAgent = nil;
    NSDictionary *applicationDictionary = [[NSBundle mainBundle] infoDictionary];
    
    NSString *appName = [applicationDictionary objectForKey:(__bridge NSString *)kCFBundleExecutableKey];
    if (appName == nil) appName = [applicationDictionary objectForKey:(__bridge NSString *)kCFBundleIdentifierKey];
    
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
    id appVersion = (__bridge id)CFBundleGetValueForInfoDictionaryKey(CFBundleGetMainBundle(), kCFBundleVersionKey);
    if (appVersion == nil) appVersion = [applicationDictionary objectForKey:(__bridge NSString *)kCFBundleVersionKey];
    
    UIDevice *device = [UIDevice currentDevice];
    CGFloat scale = ([[UIScreen mainScreen] respondsToSelector:@selector(scale)] ? [[UIScreen mainScreen] scale] : 1.0f);
    
    userAgent = [NSString stringWithFormat:@"%@/%@ (%@; iOS %@; Scale/%0.2f)", appName, appVersion, [device model], [device systemVersion], scale];
#elif defined(__MAC_OS_X_VERSION_MIN_REQUIRED)
    id appVersion = [applicationDictionary objectForKey:@"CFBundleShortVersionString"];
    if (appVersion == nil) appVersion = [applicationDictionary objectForKey:(__bridge NSString *)kCFBundleVersionKey];

    userAgent = [NSString stringWithFormat:@"%@/%@ (Mac OS X %@)", appName, appVersion, [[NSProcessInfo processInfo] operatingSystemVersionString]];
#endif

    return userAgent;
}

#pragma mark - Reachability Tracking Delegation

- (void)networkReachabilityTracker:(SENetworkReachabilityTracker *)tracker didUpdateStatus:(SENetworkReachabilityStatus)status
{
    SELog(@"Reachability changed: %@", tracker);
    [[NSNotificationCenter defaultCenter] postNotificationName:SEDataRequestServiceChangedReachabilityNotification object:self userInfo:@{ SEDataRequestServiceChangedReachabilityStatusKey: @(status) }];
}

#pragma mark - Conformity to deserialization

+ (BOOL) canDeserializeToClass: (Class) class
{
    BOOL conforms = NO;
    while (true)
    {
        conforms = class_conformsToProtocol(class, @protocol(SEDataRequestJSONDeserializable));
#ifdef DEBUG
        conforms &= class_getClassMethod(class, @selector(deserializeFromJSON:)) != NULL;
#endif
        if (conforms) break;

        class = class_getSuperclass(class);
        if (class == nil || class == [NSObject class]) break;
    }
    return conforms;
}

+ (BOOL) verifyDeserializationClass: (Class) class failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t) completionQueue
{
    if (![self canDeserializeToClass:class])
    {
        NSString *reason = [NSString stringWithFormat:@"Class %@ is not compatible for deserialization.", class];
#ifdef DEBUG
        THROW_INVALID_PARAM(class, (@{ NSLocalizedDescriptionKey: reason }));
#else
        if (failure != nil) {
            dispatch_async(completionQueue, ^{
                failure([NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:@{ NSLocalizedDescriptionKey: reason }]);
            });
        }
        return NO;
#endif
    }
    
    return YES;
}

#pragma mark - Handle being in background - if there are outstanding tasks, attempt to complete

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
- (void) checkNeedsFinishRequestsInBackground
{
    if (_applicationBackgroundDefault) return;
    
    @try
    {
        [_lock lock];
        
        if (_internalRequestsByKey.count > 0)
        {
            _backgroundTaskId = [[UIApplication sharedApplication] beginBackgroundTaskWithName:SEDataRequestServiceBackgroundTaskId expirationHandler:^{
                [self expireBackgroundWaitForCompletion];
            }];
        }
    }
    @finally
    {
        [_lock unlock];
    }
}

- (void) checkNeedsFinishBackgroundTask
{
    if (_applicationBackgroundDefault) return;
    
    @try
    {
        [_lock lock];
        
        [self completeBackgroundTaskIfNeeded];
    }
    @finally
    {
        [_lock unlock];
    }

}

- (void) expireBackgroundWaitForCompletion
{
    NSArray *incompleteTasks = nil;
    @try
    {
        [_lock lock];
        
        if (_internalRequestsByKey.count > 0)
        {
            incompleteTasks = [_internalRequestsByKey allValues];
        }
    }
    @finally
    {
        [_lock unlock];
    }
    
    if (incompleteTasks != nil)
    {
        for (SEInternalDataRequest *task in incompleteTasks) [task cancel];
    }
}

#endif

- (void) completeBackgroundTaskIfNeeded
{
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
    
    // It is running in a lock already
    if (_backgroundTaskId != UIBackgroundTaskInvalid)
    {
        [[UIApplication sharedApplication] endBackgroundTask:_backgroundTaskId];
        _backgroundTaskId = UIBackgroundTaskInvalid;
    }
#endif
}

#pragma mark - Utilities

+ (NSString *) generateRandomBoundaryString
{
    return [NSString randomStringOfLength:10];
}

+ (NSURL *)appendQueryStringToURL:(NSURL *)url query:(NSString *)query
{
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:YES];
    NSString *existingQuery = components.query;
    if (existingQuery == nil || existingQuery.length == 0)
    {
        components.query = query;
    }
    else
    {
        components.query = [NSString stringWithFormat:@"%@&%@", existingQuery, query];
    }
    return components.URL;
}

+ (NSURL *)appendQueryStringToURL:(NSURL *)url queryParameters:(NSDictionary<NSString *, id> *)query encoding:(NSStringEncoding)encoding
{
    return [self appendQueryStringToURL:url query:[SEWebFormSerializer webFormEncodedStringFromDictionary:query withEncoding:encoding]];
}


@end
