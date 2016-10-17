//
//  SEDataRequestFactory.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <ServiceEssentials/SEDataRequestFactory.h>

#include <pthread.h>

#import <ServiceEssentials/SEDataRequestServicePrivate.h>
#import <ServiceEssentials/SEDataSerializer.h>
#import <ServiceEssentials/SEJSONDataSerializer.h>
#import <ServiceEssentials/SEInternalDataRequestBuilder.h>
#import <ServiceEssentials/SEMultipartRequestContentStream.h>
#import <ServiceEssentials/SETools.h>
#import <ServiceEssentials/SEWebFormSerializer.h>

#define CHECK_IF_SECURE do { if (!_isSecure) THROW_NOT_IMPLEMENTED((@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ is not implemented for non-secure request factory", NSStringFromSelector(_cmd)] })); } while(0)

// Always returns nil, it's a shortcut to make a one-liner statement that creates an error and returns no data.
static inline id SEDataRequestAssignErrorFromMessage(NSString *message, NSError * __autoreleasing *error)
{
    if (error != nil)
    {
        *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceRequestSubmissuionFailure userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    SELog(@"%@", message);
    return nil;
}

static inline id SEDataRequestAssignSerializationError(NSError *error, NSError * __autoreleasing *errorOut)
{
    if (errorOut != nil)
    {
        *errorOut = error;
    }
    SELog(@"Failed to serialize request data: %@", error);
    return nil;
}

static inline NSURL *SEDataRequestValidateAndCreateURL(NSURL *baseURL, NSString *path)
{
    NSURL *url = [NSURL URLWithString:path relativeToURL:baseURL];
    if (![url.scheme isEqualToString:baseURL.scheme] || ![url.host isEqualToString:baseURL.host])
    {
        THROW_INVALID_PARAM(path, @{ NSLocalizedDescriptionKey: @"Path is not really a path, it modifies host or scheme and cannot be accepted." });
    }
    return url;
}

static inline NSURL *SEDataRequestMakeURL(NSURL *baseURL, NSString *path, NSDictionary *parameters)
{
    NSString *urEncodedParameters = [SEWebFormSerializer webFormEncodedStringFromDictionary:parameters withEncoding:NSUTF8StringEncoding];
    NSString *appendString = ([path rangeOfString:@"?"].location == NSNotFound) ? @"?" : @"&";
    return SEDataRequestValidateAndCreateURL(baseURL, [NSString stringWithFormat:@"%@%@%@", path, appendString, urEncodedParameters]);
}

static inline NSDictionary *SEDataRequestDictionaryWithAdditionalParameters(NSDictionary *parameters, id service, id<SEDataRequestPreparationDelegate> requestDelegate, NSString *method, NSString *path)
{
    NSDictionary *additionalParameters = [requestDelegate dataRequestService:service additionalParametersForRequestMethod:method path:path];
    if (additionalParameters != nil && additionalParameters.count > 0)
    {
        if (parameters == nil)
        {
            parameters = additionalParameters;
        }
        else
        {
            // delegate-provided parameters are applied on top
            NSMutableDictionary *temp = [[NSMutableDictionary alloc] initWithDictionary:parameters];
            [temp addEntriesFromDictionary:additionalParameters];
            parameters = temp;
        }
    }
    return parameters;
}

static inline BOOL SEDataRequestMethodURLEncodesBody(NSString *method)
{
    return !([method isEqualToString:SEDataRequestMethodGET] || [method isEqualToString:SEDataRequestMethodHEAD] || [method isEqualToString:SEDataRequestMethodDELETE]);
}

// Macro for generic handling of an error while building data requests (graceful in Release, crash in Debug)
#ifdef DEBUG
#define HANDLE_BUILD_REQUEST_ERROR(message) do { THROW_INVALID_PARAM(body, @{ NSLocalizedDescriptionKey: message }); } while(0)
#else
#define HANDLE_BUILD_REQUEST_ERROR(message) do { return SEDataRequestAssignErrorFromMessage(message, error); } while(0)
#endif

@implementation SEDataRequestFactory
{
    __weak id<SEDataRequestServicePrivate> _service;
    BOOL _isSecure;
    NSString *_userAgent;
    NSString *_authorizationHeader;
    pthread_mutex_t _authorizationHeaderLock;
    id<SEDataRequestPreparationDelegate> _requestDelegate;
}

@synthesize userAgent = _userAgent;

- (instancetype)init
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithService:(id<SEDataRequestServicePrivate>)service secure:(BOOL)secure userAgent:(NSString *)userAgent requestPreparationDelegate:(id<SEDataRequestPreparationDelegate>)requestDelegate
{
    if (service == nil) THROW_INVALID_PARAM(service, nil);
    if (!secure && requestDelegate != nil) THROW_INVALID_PARAMS(nil);

    self = [super init];
    if (self)
    {
        _service = service;
        _requestDelegate = requestDelegate;
        _userAgent = [userAgent copy];
        
        _isSecure = secure;
        if (secure)
        {
            pthread_mutex_init(&_authorizationHeaderLock, NULL);
        }
    }
    return self;
}

- (void)dealloc
{
    if (_isSecure)
    {
        pthread_mutex_destroy(&_authorizationHeaderLock);
    }
}

#pragma mark - Properties

- (NSString *)authorizationHeader
{
    CHECK_IF_SECURE;
    
    NSString *value;
    
    pthread_mutex_lock(&_authorizationHeaderLock);
    value = _authorizationHeader;
    pthread_mutex_unlock(&_authorizationHeaderLock);

    return value;
}

- (void)setAuthorizationHeader:(NSString *)authorizationHeader
{
    CHECK_IF_SECURE;

    pthread_mutex_lock(&_authorizationHeaderLock);
    if (authorizationHeader != _authorizationHeader)
    {
        _authorizationHeader = [authorizationHeader copy];
    }
    pthread_mutex_unlock(&_authorizationHeaderLock);
}

#pragma mark - Interface methods

- (NSURLRequest *)createRequestWithMethod:(NSString *)method
                                  baseURL:(NSURL *)baseURL
                                     path:(NSString *)path
                                     body:(id)body
                                 mimeType:(NSString *)mimeType
                                    error:(NSError * _Nullable __autoreleasing *)error
{
    CHECK_IF_SECURE;
    
    // since service is weak-referenced, retain it for the duration of request making and pass around
    id service = _service;
    if (service == nil) return nil;

    return [self buildRequestWithService:service
                                  method:method
                                 baseURL:baseURL
                                    path:path
                                    body:body
                                mimeType:mimeType
                                 headers:nil
                       acceptContentType:SEDataRequestAcceptContentTypeJSON
                                   error:error];
}

- (NSURLRequest *)createDownloadRequestWithBaseURL:(NSURL *)baseURL
                                              path:(NSString *)path
                                              body:(id)body
                                             error:(NSError * _Nullable __autoreleasing *)error
{
    CHECK_IF_SECURE;
    
    // since service is weak-referenced, retain it for the duration of request making and pass around
    id service = _service;
    if (service == nil) return nil;
    
    return [self buildRequestWithService:service
                                  method:SEDataRequestMethodGET
                                 baseURL:baseURL
                                    path:path
                                    body:body
                                mimeType:nil
                                 headers:nil
                       acceptContentType:SEDataRequestAcceptContentTypeData
                                   error:error];
}

- (NSURLRequest *)createRequestWithBuilder:(SEInternalDataRequestBuilder *)builder
                                   baseURL:(NSURL *)baseURL
                                     error:(NSError * _Nullable __autoreleasing *)error
{
    CHECK_IF_SECURE;
    
    // since service is weak-referenced, retain it for the duration of request making and pass around
    id service = _service;
    if (service == nil) return nil;
    
    return [self buildRequestWithService:service
                                  method:builder.method
                                 baseURL:baseURL
                                    path:builder.path
                                    body:builder.bodyParameters
                                mimeType:builder.contentEncoding
                                 headers:builder.headers
                       acceptContentType:builder.acceptContentType
                                   error:error];
}

- (NSURLRequest *)createMultipartRequestWithBuilder:(SEInternalDataRequestBuilder *)builder
                                            baseURL:(NSURL *)baseURL
                                           boundary:(NSString *)boundary
                                              error:(NSError * _Nullable __autoreleasing *)error
{
    CHECK_IF_SECURE;
    
    // since service is weak-referenced, retain it for the duration of request making and pass around
    id<SEDataRequestServicePrivate> service = _service;
    if (service == nil) return nil;

    NSMutableURLRequest *request = [self buildRequestWithService:service
                                                          method:builder.method
                                                         baseURL:baseURL
                                                            path:builder.path
                                                            body:nil
                                                        mimeType:nil
                                                         headers:builder.headers
                                               acceptContentType:builder.acceptContentType
                                                           error:error];

    // Setting content-type and content-length in the very end to ensure they are consistent with the request.
    NSString *mimeType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request setValue:mimeType forHTTPHeaderField:@"Content-Type"];
    
    unsigned long long contentLength = [SEMultipartRequestContentStream contentLengthForParts:builder.contentParts boundary:boundary stringEncoding:[service stringEncoding]];
    [request setValue:[NSString stringWithFormat:@"%llu", contentLength] forHTTPHeaderField:@"Content-Length"];

    return request;
}

- (NSURLRequest *)createUnsafeRequestWithMethod:(NSString *)method
                                            URL:(NSURL *)url
                                     parameters:(NSDictionary<NSString *, id> *)parameters
                                       mimeType:(NSString *)mimeType
                                          error:(NSError * _Nullable __autoreleasing *)error
{
    if (_isSecure) THROW_NOT_IMPLEMENTED((@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ is not implemented for secure request factory", NSStringFromSelector(_cmd)] }));
    
    if (url == nil || [url isFileURL]) THROW_INVALID_PARAM(url, @{ NSLocalizedDescriptionKey: @"Invalid URL"} );
 
    NSData *data = nil;
    NSString *contentType = nil;
    NSStringEncoding encoding = [_service stringEncoding];
    if (parameters != nil)
    {
        if (SEDataRequestMethodURLEncodesBody(method))
        {
            url = SEURLByAppendingQueryParameters(url, parameters, encoding);
        }
        else
        {
            NSString *charset = (__bridge NSString *)CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(encoding));
            data = [self buildRequestDataWithService:_service method:method path:nil body:parameters mimeType:mimeType charset:charset contentTypeOut:&contentType error:error];
            
            if (data == nil) return nil;
        }
    }

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setHTTPMethod:method];
    [request setURL:url];
    
    NSString *userAgent = _userAgent;
    if (userAgent) [request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    
    if (data)
    {
        [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
        [request setHTTPBody:data];
    }
    
    return request;
}

#pragma mark - Internal building functions

- (NSMutableURLRequest *)buildRequestWithService:(id)service method:(NSString *)method baseURL:(NSURL *)baseURL path:(NSString *)path body:(id)body mimeType:(NSString *)mimeType headers:(NSDictionary<NSString *, NSString *> *)headers acceptContentType:(SEDataRequestAcceptContentType)acceptType error:(NSError * __autoreleasing *)error
{
    // compose the URL
    BOOL needsBody = NO;
    NSURL *fullUrl = [self buildURLWithService:service path:path baseURL:baseURL forMethod:method body:body needsBodyData:&needsBody error:error];

    if (fullUrl == nil)
    {
        NSString *message = [NSString stringWithFormat:@"Not a valid request URL combination of path [%@], base [%@] and parameters [%@]", path, baseURL, needsBody ? @"n/a" : body];
        HANDLE_BUILD_REQUEST_ERROR(message);
    }

    // if necessary - create the request body
    NSString *charset = (__bridge NSString *)CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding([_service stringEncoding]));
    NSString *contentType = nil;
    NSData *data = nil;

    if (needsBody && (body != nil))
    {
        data = [self buildRequestDataWithService:service method:method path:path body:body mimeType:mimeType charset:charset contentTypeOut:&contentType error:error];
        if (data == nil) return nil;
    }

    // assign everything to a request
    return [self createRequestWithService:service method:method path:path url:fullUrl data:data contentType:contentType headers:headers acceptContentType:acceptType charset:charset];
}

- (NSMutableURLRequest *)createRequestWithService:(id)service method:(NSString *)method path:(NSString *)path url:(NSURL *)url data:(NSData *)data contentType:(NSString *)contentType headers:(NSDictionary<NSString *, NSString *> *)headers acceptContentType:(SEDataRequestAcceptContentType)acceptType charset:(NSString *)charset
{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setHTTPMethod:method];
    [request setURL:url];

    if (_userAgent) [request setValue:_userAgent forHTTPHeaderField:@"User-Agent"];

    if (acceptType == SEDataRequestAcceptContentTypeJSON)
    {
        NSString *acceptHeader = [NSString stringWithFormat:@"application/json; charset=%@", charset];
        [request setValue:acceptHeader forHTTPHeaderField:@"Accept"];
    }
    
    SEAssignHeadersToURLRequest(request, headers);

    if (_isSecure)
    {
        [self applyGlobalAndDelegateSettingsForAuthorizedRequest:request withService:service method:method path:path];
    }

    if (data)
    {
        [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
        [request setHTTPBody:data];
    }

    return request;
}

- (NSURL *)buildURLWithService:(id)service path:(NSString *)path baseURL:(NSURL *)baseURL forMethod:(NSString *)method body:(id)body needsBodyData:(BOOL *)needsBody error: (NSError * __autoreleasing *) error
{
    *needsBody = SEDataRequestMethodURLEncodesBody(method);
    if (*needsBody)
    {
        return SEDataRequestValidateAndCreateURL(baseURL, path);
    }

    if (body != nil && ![body isKindOfClass:[NSDictionary class]])
    {
        NSString *message = [NSString stringWithFormat:@"Not a valid body type for %@ request: %@", method, [body class]];
        HANDLE_BUILD_REQUEST_ERROR(message);
    }
    else
    {
        NSDictionary *parameters = body;
        if (_isSecure && _requestDelegate)
        {
            parameters = SEDataRequestDictionaryWithAdditionalParameters(parameters, service, _requestDelegate, method, path);
        }
        
        if (parameters == nil || parameters.count == 0) return SEDataRequestValidateAndCreateURL(baseURL, path);
        return SEDataRequestMakeURL(baseURL, path, parameters);
    }
}

- (NSData *)buildRequestDataWithService:(id)service method:(NSString *)method path:(NSString *)path body:(id)body mimeType:(NSString *)mimeType charset:(NSString *)charset contentTypeOut:(NSString * __autoreleasing *)contentTypeOut error: (NSError * __autoreleasing *) error
{
    if (contentTypeOut == nil) THROW_INVALID_PARAM(contentTypeOut, nil);

    NSData *data = nil;
    NSString *contentType = nil;
    BOOL isDictionary = [body isKindOfClass:[NSDictionary class]];

    if (mimeType != nil)
    {
        NSError *serializationError = nil;
        SEDataSerializer *serializer = [_service explicitSerializerForMIMEType:mimeType];
        if (serializer == nil)
        {
            NSString *message = [NSString stringWithFormat:@"Serializer not found for type %@", mimeType];
            return SEDataRequestAssignErrorFromMessage(message, error);
        }
        
        if (_isSecure && _requestDelegate && isDictionary && serializer.supportsAdditionalParameters)
        {
            body = SEDataRequestDictionaryWithAdditionalParameters(body, service, _requestDelegate, method, path);
        }
        
        data = [serializer serializeObject:body mimeType:mimeType error:&serializationError];
        if (serializationError != nil)
        {
            return SEDataRequestAssignSerializationError(serializationError, error);
        }
        contentType = serializer.shouldAppendCharsetToContentType ? [NSString stringWithFormat:@"%@; charset=%@", mimeType, charset] : mimeType;
    }
    else if ([body isKindOfClass:[NSString class]])
    {
        NSString *text = body;
        data = [text dataUsingEncoding:[_service stringEncoding]];
        contentType = [NSString stringWithFormat:@"text/plain; charset=%@", charset];
    }
    else if (isDictionary || [body isKindOfClass:[NSArray class]] || [body isKindOfClass:[NSNumber class]])
    {
        if (_isSecure && _requestDelegate && isDictionary)
        {
            body = SEDataRequestDictionaryWithAdditionalParameters(body, service, _requestDelegate, method, path);
        }
        NSError *jsonError = nil;
        data = [SEJSONDataSerializer serializeObject:body error:error];

        if (jsonError != nil)
        {
            return SEDataRequestAssignSerializationError(jsonError, error);
        }

        contentType = [NSString stringWithFormat:@"application/json; charset=%@", charset];
    }
    else
    {
        NSString *message = [NSString stringWithFormat:@"Not a valid request data type: %@", [body class]];
        return SEDataRequestAssignErrorFromMessage(message, error);
    }

    *contentTypeOut = contentType;
    return data;
}

- (void)applyGlobalAndDelegateSettingsForAuthorizedRequest:(NSMutableURLRequest *)request withService:(id)service method:(NSString *)method path:(NSString *)path
{
    NSAssert(_isSecure, @"Global settings only apply to secure requests");
    
    if (_requestDelegate != nil)
    {
        NSDictionary<NSString *, NSString *> *headers = [_requestDelegate dataRequestService:service additionalHeadersForRequestMethod:method path:path];
        SEAssignHeadersToURLRequest(request, headers);
    }

    NSString *authorizationHeader = self.authorizationHeader;
    if (authorizationHeader != nil) [request setValue:authorizationHeader forHTTPHeaderField:@"Authorization"];
}

@end
