//
//  SEDataRequestServiceImpl.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <ServiceEssentials/SEDataRequestServiceImpl.h>
#import <ServiceEssentials/SEDataRequestServicePrivate.h>

#include <pthread.h>
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
@import UIKit;
#endif

#import "NSString+SEExtensions.h"
#import "SETools.h"
#import "SEDataRequestFactory.h"
#import "SEDataRequestServiceSecurityHelper.h"
#import "SEDataRequestServiceUserAgent.h"
#import "SEDataSerializer.h"
#import "SEEnvironmentService.h"
#import "SEInternalDataRequest.h"
#import "SEInternalDataRequestBuilder.h"
#import "SEJSONDataSerializer.h"
#import "SEMultipartRequestContentStream.h"
#import "SENetworkReachabilityTracker.h"
#import "SEPlainTextSerializer.h"
#import "SEWebFormSerializer.h"

// Pair of macros to enter and leave the critical section
#define ENTER_CRITICAL_SECTION(service)           \
@try                                              \
{                                                 \
    pthread_mutex_lock(&(service->_requestLock));

#define LEAVE_CRITICAL_SECTION(service)             \
}                                                   \
@finally                                            \
{                                                   \
    pthread_mutex_unlock(&(service->_requestLock)); \
}


// Macro for generic handling of an error while building data requests (graceful in Release, crash in Debug)
#ifdef DEBUG
#define HANDLE_BUILD_REQUEST_ERROR(message) do { THROW_INVALID_PARAM(body, @{ NSLocalizedDescriptionKey: message }); } while(0)
#else
#define HANDLE_BUILD_REQUEST_ERROR(message) do { return SEDataRequestServiceGracefulHandleError(message, error); } while(0)
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

static NSString * _Nonnull const SEDataRequestServiceBackgroundTaskId = @"com.service-essentials.DataRequestService.background";

NSString * _Nonnull const SEDataRequestMethodGET = @"GET";
NSString * _Nonnull const SEDataRequestMethodPOST = @"POST";
NSString * _Nonnull const SEDataRequestMethodPUT = @"PUT";
NSString * _Nonnull const SEDataRequestMethodDELETE = @"DELETE";
NSString * _Nonnull const SEDataRequestMethodHEAD = @"HEAD";

@interface SEDataRequestServiceImpl () <NSURLSessionDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate, SEDataRequestServicePrivate, SENetworkReachabilityTrackerDelegate>
@end

@implementation SEDataRequestServiceImpl
{
    NSURLSession *_session;
    NSOperationQueue *_queue;
    SENetworkReachabilityTracker *_reachabilityTracker;
    
    NSMutableDictionary<id<SECancellableToken>, SEInternalDataRequest *> *_internalRequestsByKey;
    NSMutableDictionary<NSNumber *, SEInternalDataRequest *> *_internalRequestsByTask;
    pthread_mutex_t _requestLock;
    
    // Will create the factory for safe requests immediately, but create unsafe counterpart lazy
    // since it may or may or may not be needed.
    SEDataRequestFactory *_secureRequestFactory;
    dispatch_once_t _unsafeRequestFactoryOnceToken;
    SEDataRequestFactory *_unsafeRequestFactory;
    
    id<SEEnvironmentService> _environmentService;
    pthread_mutex_t _baseURLLock;
    NSURL *_baseURL;
    SEDataRequestCertificatePinningType _pinningType;

    NSDictionary<NSString *, __kindof SEDataSerializer *> *_dataSerializers;
    SEDataSerializer *_defaultSerializer;
        
    BOOL _applicationBackgroundDefault;
    
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
    UIBackgroundTaskIdentifier _backgroundTaskId;
#endif
}

- (instancetype)initWithEnvironmentService:(id<SEEnvironmentService>)environmentService
                      sessionConfiguration:(NSURLSessionConfiguration *)configuration
                          qualityOfService:(SEDataRequestQualityOfService) qualityOfService
                               pinningType:(SEDataRequestCertificatePinningType)certificatePinningType
              applicationBackgroundDefault:(BOOL)backgroundDefault
                               serializers:(NSDictionary<NSString *,__kindof SEDataSerializer *> *)serializers
                requestPreparationDelegate:(id<SEDataRequestPreparationDelegate>)requestDelegate
{
    if (environmentService == nil) THROW_INVALID_PARAM(environmentService, nil);
    if (serializers)
    {
        for (NSString *key in serializers)
        {
            if (![key isKindOfClass:[NSString class]] || ![[serializers objectForKey:key] isKindOfClass:[SEDataSerializer class]])
            {
                THROW_INVALID_PARAM(serializers, nil);
            }
        }
    }
    
    SEDataRequestVerifyQOS(qualityOfService);
    
    self = [super init];
    if (self)
    {
        _environmentService = environmentService;
        if (configuration == nil) configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        
        _queue = [[NSOperationQueue alloc] init];
        _queue.maxConcurrentOperationCount = 5;
        _queue.qualityOfService = SEDataRequestQualityOfServiceForQOS(qualityOfService);
        _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:_queue];
        _baseURL = [environmentService environmentBaseURL];
        _pinningType = certificatePinningType;
        _applicationBackgroundDefault = backgroundDefault;
        
        _internalRequestsByKey = [[NSMutableDictionary alloc] initWithCapacity:1];
        _internalRequestsByTask = [[NSMutableDictionary alloc] initWithCapacity:1];
        pthread_mutex_init(&_requestLock, NULL);
                
        _defaultSerializer = [SEDataSerializer new];
        
        if (serializers != nil)
        {
            _dataSerializers = [serializers copy];
        }
        else
        {
            SEDataSerializer *plainTextDeserializer = [SEPlainTextSerializer new];

            _dataSerializers = @{
                                 SEDataRequestServiceContentTypeJSON        : [SEJSONDataSerializer new],
                                 SEDataRequestServiceContentTypePlainText   : plainTextDeserializer,
                                 SEDataRequestServiceContentTypeTextHTML    : plainTextDeserializer,
                                 SEDataRequestServiceContentTypeURLEncode   : [SEWebFormSerializer new],
                                 SEDataRequestServiceContentTypeOctetStream : _defaultSerializer
                                 };
        }
        
        NSString *userAgent = SEDataRequestServiceUserAgent();
        _secureRequestFactory = [[SEDataRequestFactory alloc] initWithService:self secure:YES userAgent:userAgent  requestPreparationDelegate:requestDelegate];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onUpdateEnvironment:) name:SEEnvironmentChangedNotification object:environmentService];

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
        _backgroundTaskId = UIBackgroundTaskInvalid;
        NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
        [defaultCenter addObserver:self selector:@selector(onDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [defaultCenter addObserver:self selector:@selector(onWillResumeActive:) name:UIApplicationWillEnterForegroundNotification object:nil];
        [defaultCenter addObserver:self selector:@selector(onWillTerminateApplication:) name:UIApplicationWillTerminateNotification object:nil];
#endif
        
        // track connectivity/reachability
        [self createReachabilityTrackerIfAvailableForURL:_baseURL];
    }
    return self;
}

- (instancetype)initWithEnvironmentService:(id<SEEnvironmentService>)environmentService sessionConfiguration:(NSURLSessionConfiguration *)configuration
{
    return [self initWithEnvironmentService:environmentService sessionConfiguration:configuration qualityOfService:SEDataRequestQOSDefault pinningType:SEDataRequestCertificatePinningTypeCertificate applicationBackgroundDefault:NO serializers:nil requestPreparationDelegate:nil];
}

- (instancetype)initWithEnvironmentService:(id<SEEnvironmentService>)environmentService sessionConfiguration:(NSURLSessionConfiguration *)configuration pinningType:(SEDataRequestCertificatePinningType)certificatePinningType applicationBackgroundDefault:(BOOL)backgroundDefault
{
    return [self initWithEnvironmentService:environmentService sessionConfiguration:configuration qualityOfService:SEDataRequestQOSDefault pinningType:certificatePinningType applicationBackgroundDefault:backgroundDefault serializers:nil requestPreparationDelegate:nil];
}

static inline void SEDataRequestServiceKillAllTasksAndCleanup(__unsafe_unretained SEDataRequestServiceImpl *service, BOOL clearData)
{
    // This function is not pretty but it eliminates copy-pasting cleanup logic between dealloc and
    // other places where object may be invalidated without having to create a method, because
    // sending messages to `self` in `dealloc` is strongly discouraged.
    
    NSURLSession *session = nil;
    ENTER_CRITICAL_SECTION(service)
        for (SEInternalDataRequest *request in service->_internalRequestsByKey.allValues)
        {
            [request cancelAndNotifyComplete:NO];
        }
        
        session = service->_session;

        if (clearData)
        {
            [service->_internalRequestsByKey removeAllObjects];
            [service->_internalRequestsByTask removeAllObjects];
            service->_session = nil;
        }
    LEAVE_CRITICAL_SECTION(service)

    [session invalidateAndCancel];
    pthread_mutex_destroy(&(service->_requestLock));
}

- (void)dealloc
{
    // Pointer to `self` is still valid, but need to avoid anything that can retain it.
    // Can do short cleanup (without cleaning up the requests maps and such).
    __unsafe_unretained typeof (self) unsafeInstance = self;
    SEDataRequestServiceKillAllTasksAndCleanup(unsafeInstance, NO);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void) onWillTerminateApplication: (NSNotification *) notification
{
    SEDataRequestServiceKillAllTasksAndCleanup(self, YES);
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
        pthread_mutex_lock(&_baseURLLock);
        if (![newUrl isEqual:_baseURL])
        {
            _baseURL = [_environmentService environmentBaseURL];
            [self createReachabilityTrackerIfAvailableForURL:_baseURL];
            
            // TODO: implement the rest of environment switch if needed (cancel requests and so on)
        }
    }
    @finally
    {
        pthread_mutex_unlock(&_baseURLLock);
    }
}

- (NSURL *)safeBaseURL
{
    NSURL *baseURL = nil;
    @try
    {
        pthread_mutex_lock(&_baseURLLock);

        baseURL = [_baseURL copy];
    }
    @finally
    {
        pthread_mutex_unlock(&_baseURLLock);
    }
    
    return baseURL;
}

- (void)createReachabilityTrackerIfAvailableForURL:(NSURL *)url
{
    if ([SENetworkReachabilityTracker isReachabilityAvailable])
    {
        _reachabilityTracker = [[SENetworkReachabilityTracker alloc] initWithURL:url delegate:self dispatchQueue:dispatch_get_main_queue()];
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

    _secureRequestFactory.authorizationHeader = authorizationHeader;
}

- (void)clearAuthorization
{
    _secureRequestFactory.authorizationHeader = nil;
}

- (id<SECancellableToken>)GET:(NSString *)path parameters:(NSDictionary <NSString *, id> *)parameters success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    return [self GET:path parameters:parameters deserializeToClass:nil success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>)GET:(NSString *)path parameters:(NSDictionary<NSString *,id> *)parameters deserializeToClass:(Class)class success:(void (^)(id _Nonnull, NSURLResponse * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    return [self buildAndSubmitSimpleRequestWithMethod:SEDataRequestMethodGET path:path parameters:parameters mimeType:nil deserializationClass:class success:success failure:failure completionQueue:completionQueue];
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
    
    return [self buildAndSubmitSimpleRequestWithMethod:SEDataRequestMethodPOST path:path parameters:parameters mimeType:encoding deserializationClass:class success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>)PUT:(NSString *)path parameters:(NSDictionary<NSString *,id> *)parameters success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    return [self buildAndSubmitSimpleRequestWithMethod:SEDataRequestMethodPUT path:path parameters:parameters mimeType:nil deserializationClass:nil success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>)download:(NSString *)path parameters:(NSDictionary<NSString *,id> *)parameters saveAs:(NSURL *)saveAsURL success:(void (^)(id _Nullable, NSURLResponse * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure progress:(void (^)(int64_t, int64_t, int64_t))progress completionQueue:(dispatch_queue_t)completionQueue
{
    if (path == nil) THROW_INVALID_PARAM(url, @{ NSLocalizedDescriptionKey: @"Invalid URL"} );
    if (saveAsURL == nil || ![saveAsURL isFileURL]) THROW_INVALID_PARAM(saveAsURL, @{ NSLocalizedDescriptionKey: @"Invalid URL to save a file" });

    NSError *error = nil;
    NSURLRequest *request = [_secureRequestFactory createDownloadRequestWithBaseURL:[self safeBaseURL] path:path body:parameters error:&error];
    
    if (request == nil)
    {
        if (failure != nil)
        {
            if (error == nil) error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceRequestSubmissuionFailure userInfo:@{ NSLocalizedDescriptionKey: @"Invalid URL" }];
            dispatch_async(completionQueue, ^{ failure(error); });
        }
        return nil;
    }
    else
    {
        return [self createDownloadRequestWithURLRequest:request qos:SEDataRequestQOSDefault saveFileAs:saveAsURL expectedHTTPCodes:nil success:success failure:failure progress:progress completionQueue:completionQueue];
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
        
        NSURL *baseURL = [self safeBaseURL];
        SEDataRequestCertificatePinningType pinningType = _pinningType;
        if (![challenge.protectionSpace.host isEqualToString:baseURL.host]) pinningType = SEDataRequestCertificatePinningTypeNone;
        
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

- (SEDataRequestFactory *)lazyUnsafeFactory
{
    dispatch_once(&_unsafeRequestFactoryOnceToken, ^{
        _unsafeRequestFactory = [[SEDataRequestFactory alloc] initWithService:self secure:NO userAgent:_secureRequestFactory.userAgent requestPreparationDelegate:nil];
    });
    return _unsafeRequestFactory;
}


- (id<SECancellableToken>)URLGET:(NSURL *)url parameters:(NSDictionary<NSString *,id> *)parameters success:(void (^)(id _Nonnull, NSURLResponse * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    NSError *error = nil;
    NSURLRequest *request = [[self lazyUnsafeFactory] createUnsafeRequestWithMethod:SEDataRequestMethodGET URL:url parameters:parameters mimeType:nil error:&error];
    if (request == nil)
    {
        if (failure != nil)
        {
            dispatch_async(completionQueue, ^{ failure(error); });
        }
        return nil;
    }

    return [self createDataRequestWithURLRequest:request qos:SEDataRequestQOSDefault dataClass:nil expectedHTTPCodes:nil success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>)URLDownload:(NSURL *)url parameters:(NSDictionary<NSString *,id> *)parameters saveAs:(NSURL *)saveAsURL success:(void (^)(id _Nullable, NSURLResponse * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure progress:(void (^)(int64_t, int64_t, int64_t))progress completionQueue:(dispatch_queue_t)completionQueue
{
    if (saveAsURL == nil || ![saveAsURL isFileURL]) THROW_INVALID_PARAM(saveAsURL, @{ NSLocalizedDescriptionKey: @"Invalid URL to save a file" });
    
    NSError *error = nil;
    NSURLRequest *request = [[self lazyUnsafeFactory] createUnsafeRequestWithMethod:SEDataRequestMethodGET URL:url parameters:parameters mimeType:nil error:&error];
    if (request == nil)
    {
        if (failure != nil)
        {
            dispatch_async(completionQueue, ^{ failure(error); });
        }
        return nil;
    }
    
    return [self createDownloadRequestWithURLRequest:request qos:SEDataRequestQOSPriorityLow saveFileAs:saveAsURL expectedHTTPCodes:nil success:success failure:failure progress:progress completionQueue:completionQueue];
}

#pragma mark - Private interface

- (NSStringEncoding)stringEncoding
{
    return SEDataRequestServiceStringEncoding;
}

- (void)cancelItemForToken:(id<SECancellableToken>)token
{
    SEInternalDataRequest *request = nil;
    ENTER_CRITICAL_SECTION(self)
        request = [_internalRequestsByKey objectForKey:token];
    LEAVE_CRITICAL_SECTION(self);
    
    if (request) [request cancelAndNotifyComplete:YES];
}

- (void)completeInternalRequest:(SEInternalDataRequest *)request
{
    ENTER_CRITICAL_SECTION(self)
        [_internalRequestsByKey removeObjectForKey:request.token];
        NSURLSessionTask *task = request.task;
        if (task != nil) [_internalRequestsByTask removeObjectForKey:@(task.taskIdentifier)];
        
        if (_internalRequestsByKey.count == 0) [self completeBackgroundTaskIfNeeded];
    LEAVE_CRITICAL_SECTION(self);
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
    NSURLRequest *request;
    if (requestBuilder.contentParts == nil)
    {
        // regular, non-multipart request
        request = [_secureRequestFactory createRequestWithBuilder:requestBuilder baseURL:[self safeBaseURL] error:&error];
        
        if (request != nil)
        {            
            if (asUpload)
            {
                return [self createDataRequestWithURLRequest:request qos:requestBuilder.qualityOfService dataClass:requestBuilder.deserializeClass expectedHTTPCodes:requestBuilder.expectedHTTPCodes success:requestBuilder.success failure:requestBuilder.failure completionQueue:requestBuilder.completionQueue];
            }
            else
            {
                return [self createUploadRequestWithURLRequest:request qos:requestBuilder.qualityOfService data:request.HTTPBody dataClass:requestBuilder.deserializeClass expectedHTTPCodes:requestBuilder.expectedHTTPCodes success:requestBuilder.success failure:requestBuilder.failure completionQueue:requestBuilder.completionQueue];
            }
        }
    }
    else
    {
        // multipart request
        NSString *boundary = [NSString randomStringOfLength:10];
        request = [_secureRequestFactory createMultipartRequestWithBuilder:requestBuilder baseURL:[self safeBaseURL] boundary:boundary error:&error];
        
        if (request != nil)
        {
            return [self createStreamedUploadRequestWithURLRequest:request qos:requestBuilder.qualityOfService dataClass:requestBuilder.deserializeClass expectedHTTPCodes:requestBuilder.expectedHTTPCodes multipartContents:requestBuilder.contentParts boundary:boundary success:requestBuilder.success failure:requestBuilder.failure completionQueue:requestBuilder.completionQueue];
        }
    }
    
    if (error != nil && requestBuilder.failure != nil)
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

static inline SEInternalDataRequest *SEDataRequestServiceInterlockedGetRequest(SEDataRequestServiceImpl *service, NSURLSessionTask *task)
{
    SEInternalDataRequest *dataRequest = nil;
    ENTER_CRITICAL_SECTION(service)
        dataRequest = [service->_internalRequestsByTask objectForKey:@(task.taskIdentifier)];
    LEAVE_CRITICAL_SECTION(service)
    return dataRequest;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    SEInternalDataRequest *dataRequest = SEDataRequestServiceInterlockedGetRequest(self, task);
    if (dataRequest) [dataRequest completeWithError:error];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    SEInternalDataRequest *dataRequest = SEDataRequestServiceInterlockedGetRequest(self, dataTask);
    
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
    SEInternalDataRequest *dataRequest = SEDataRequestServiceInterlockedGetRequest(self, dataTask);
    
    if ((dataRequest != nil) && !dataRequest.isCompleted) [dataRequest receivedData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task needNewBodyStream:(void (^)(NSInputStream * _Nullable))completionHandler
{
    SEInternalDataRequest *dataRequest = SEDataRequestServiceInterlockedGetRequest(self, task);
    
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
    SEInternalDataRequest *dataRequest = SEDataRequestServiceInterlockedGetRequest(self, downloadTask);
    
    if ((dataRequest != nil) && !dataRequest.isCompleted)
    {
        [dataRequest downloadRequestDidFinishDownloadingToURL:location];
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    SEInternalDataRequest *dataRequest = SEDataRequestServiceInterlockedGetRequest(self, downloadTask);
    
    if ((dataRequest != nil) && !dataRequest.isCompleted)
    {
        [dataRequest downloadRequestDidWriteData:bytesWritten totalBytesWritten:totalBytesWritten totalBytesExpectedToWrite:totalBytesExpectedToWrite];
    }
}

#pragma mark - request building

- (id<SECancellableToken>)buildAndSubmitSimpleRequestWithMethod:(NSString *)method path:(NSString *)path parameters:(NSDictionary *)parameters mimeType:(NSString *)mimeType deserializationClass:(Class)class success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    if (class != nil && !SEVerifyClassForDeserialization(class, failure, completionQueue))
    {
        return nil;
    }
    
    NSError *error = nil;
    NSURLRequest *urlRequest = [_secureRequestFactory createRequestWithMethod:method baseURL:[self safeBaseURL] path:path body:parameters mimeType:mimeType error:&error];
    
    if (urlRequest != nil)
    {
        return [self createDataRequestWithURLRequest:urlRequest qos:SEDataRequestQOSDefault dataClass:class expectedHTTPCodes:nil success:success failure:failure completionQueue:completionQueue];
    }
    else
    {
        if (failure) dispatch_async(completionQueue, ^{ failure(error); });
        return nil;
    }
}

/** Creates and submits standard data task */
- (id<SECancellableToken>) createDataRequestWithURLRequest: (NSURLRequest *) urlRequest qos: (SEDataRequestQualityOfService) qos dataClass:(Class) dataClass expectedHTTPCodes:(NSIndexSet *)expectedCodes success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    NSURLSessionDataTask *dataTask = [_session dataTaskWithRequest:urlRequest];
    return [self createInternalRequestWithTask:dataTask qos:qos dataClass:dataClass expectedHTTPCodes:expectedCodes multipartContents:nil downloadParameters:nil success:success failure:failure completionQueue:completionQueue];
}

/** Creates and submits upload data task with provided data */
- (id<SECancellableToken>) createUploadRequestWithURLRequest: (NSURLRequest *) urlRequest qos: (SEDataRequestQualityOfService) qos data:(NSData *) data dataClass: (Class) dataClass expectedHTTPCodes:(NSIndexSet *) expectedCodes success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    NSURLSessionDataTask *dataTask = [_session uploadTaskWithRequest:urlRequest fromData:data];
    return [self createInternalRequestWithTask:dataTask qos:qos dataClass:dataClass expectedHTTPCodes:expectedCodes multipartContents:nil downloadParameters:nil success:success failure:failure completionQueue:completionQueue];
}

/** Creates and submits upload data task with a file */
- (id<SECancellableToken>) createUploadRequestWithURLRequest: (NSURLRequest *) urlRequest qos: (SEDataRequestQualityOfService) qos file:(NSURL *) dataFile dataClass:(Class) dataClass expectedHTTPCodes: (NSIndexSet *) expectedCodes success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    NSURLSessionDataTask *dataTask = [_session uploadTaskWithRequest:urlRequest fromFile:dataFile];
    return [self createInternalRequestWithTask:dataTask qos:qos dataClass:dataClass expectedHTTPCodes:expectedCodes multipartContents:nil downloadParameters:nil success:success failure:failure completionQueue:completionQueue];
}

/** Creates and submits streamed uploda data task - will have to provide the stream as well. Will use for some of the multipart submissions. */
- (id<SECancellableToken>) createStreamedUploadRequestWithURLRequest: (NSURLRequest *) urlRequest qos:(SEDataRequestQualityOfService)qos dataClass:(Class) dataClass expectedHTTPCodes:(NSIndexSet *)expectedCodes multipartContents:(NSArray *)multipartContents boundary:(NSString *)boundary success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    NSURLSessionUploadTask *dataTask = [_session uploadTaskWithStreamedRequest:urlRequest];
    SEInternalMultipartContents *multipartParameters = (multipartContents == nil || boundary == nil) ? nil : [[SEInternalMultipartContents alloc] initWithMultipartContents:multipartContents boundary:boundary];
    return [self createInternalRequestWithTask:dataTask qos:qos dataClass:dataClass expectedHTTPCodes:expectedCodes multipartContents:multipartParameters downloadParameters:nil success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>) createDownloadRequestWithURLRequest: (NSURLRequest *) urlRequest qos:(SEDataRequestQualityOfService)qos saveFileAs: (NSURL *) saveAs expectedHTTPCodes:(NSIndexSet *)expectedCodes success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure progress:(void (^)(int64_t, int64_t, int64_t))progress completionQueue:(dispatch_queue_t)completionQueue
{
    NSURLSessionDownloadTask *downloadTask = [_session downloadTaskWithRequest:urlRequest];
    SEInternalDownloadRequestParameters *downloadRequestParameters = [[SEInternalDownloadRequestParameters alloc] initWithSaveAsURL:saveAs downloadProgressCallback:progress];
    return [self createInternalRequestWithTask:downloadTask qos:qos dataClass:nil expectedHTTPCodes:nil multipartContents:nil downloadParameters:downloadRequestParameters success:success failure:failure completionQueue:completionQueue];
}

- (id<SECancellableToken>) createInternalRequestWithTask: (NSURLSessionTask *) dataTask qos:(SEDataRequestQualityOfService)qos dataClass:(Class) dataClass expectedHTTPCodes:(NSIndexSet *)expectedCodes multipartContents:(SEInternalMultipartContents *)multipartContents downloadParameters:(SEInternalDownloadRequestParameters *)downloadParameters success:(void (^)(id, NSURLResponse *))success failure:(void (^)(NSError *))failure completionQueue:(dispatch_queue_t)completionQueue
{
    dataTask.priority = SEDataRequestServiceTaskPriorityForQOS(qos);
    SEInternalDataRequest *internalRequest = [[SEInternalDataRequest alloc] initWithSessionTask:dataTask requestService:self qualityOfService:qos responseDataClass:dataClass expectedHTTPCodes:expectedCodes multipartContents:multipartContents downloadParameters:downloadParameters success:success failure:failure completionQueue:completionQueue];
    
    ENTER_CRITICAL_SECTION(self)
        [_internalRequestsByKey setObject:internalRequest forKey:internalRequest.token];
        [_internalRequestsByTask setObject:internalRequest forKey:@(dataTask.taskIdentifier)];
    LEAVE_CRITICAL_SECTION(self)
    
    [dataTask resume];
    
    return internalRequest.token;
}


#pragma mark - Reachability Tracking Delegation

- (void)networkReachabilityTracker:(SENetworkReachabilityTracker *)tracker didUpdateStatus:(SENetworkReachabilityStatus)status
{
    SELog(@"Reachability changed: %@", tracker);
    [[NSNotificationCenter defaultCenter] postNotificationName:SEDataRequestServiceChangedReachabilityNotification object:self userInfo:@{ SEDataRequestServiceChangedReachabilityStatusKey: @(status) }];
}


#pragma mark - Handle being in background - if there are outstanding tasks, attempt to complete

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
- (void) checkNeedsFinishRequestsInBackground
{
    if (_applicationBackgroundDefault) return;
    
    ENTER_CRITICAL_SECTION(self)
        if (_internalRequestsByKey.count > 0)
        {
            _backgroundTaskId = [[UIApplication sharedApplication] beginBackgroundTaskWithName:SEDataRequestServiceBackgroundTaskId expirationHandler:^{
                [self expireBackgroundWaitForCompletion];
            }];
        }
    LEAVE_CRITICAL_SECTION(self)
}

- (void) checkNeedsFinishBackgroundTask
{
    if (_applicationBackgroundDefault) return;
    
    ENTER_CRITICAL_SECTION(self)
        [self completeBackgroundTaskIfNeeded];
    LEAVE_CRITICAL_SECTION(self)
}

- (void) expireBackgroundWaitForCompletion
{
    NSArray *incompleteTasks = nil;
    ENTER_CRITICAL_SECTION(self)
        if (_internalRequestsByKey.count > 0)
        {
            incompleteTasks = [_internalRequestsByKey allValues];
        }
    LEAVE_CRITICAL_SECTION(self)
    
    if (incompleteTasks != nil)
    {
        for (SEInternalDataRequest *task in incompleteTasks) [task cancelAndNotifyComplete:YES];
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

@end
