//
//  SEDataRequestFactory.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import "SEDataRequestFactory.h"

#include <pthread.h>

#import "SETools.h"
#import "SEDataRequestServicePrivate.h"
#import "SEDataSerializer.h"
#import "SEWebFormSerializer.h"

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

    return [self buildRequestWithMethod:method baseURL:baseURL path:path body:body mimeType:mimeType acceptContentType:SEDataRequestAcceptContentTypeJSON error:error];
}

- (NSURLRequest *)createRequestWithBuilder:(SEInternalDataRequestBuilder *)builder
                                   baseURL:(NSURL *)baseURL
                                  asUpload:(BOOL)asUpload
                                     error:(NSError * _Nullable __autoreleasing *)error
{
    CHECK_IF_SECURE;

    return nil;
}

#pragma mark - Internal building functions

- (NSMutableURLRequest *)buildRequestWithMethod:(NSString *)method baseURL:(NSURL *)baseURL path:(NSString *)path body:(id)body mimeType:(NSString *)mimeType acceptContentType:(SEDataRequestAcceptContentType)acceptType error:(NSError * __autoreleasing *)error
{
    // compose the URL
    BOOL needsBody = NO;
    NSURL *fullUrl = [self buildURLWithPath:path baseURL:baseURL forMethod:method body:body needsBodyData:&needsBody error:error];

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
        data = [self buildRequestDataWithBody:body mimeType:mimeType charset:charset contentTypeOut:&contentType error:error];
        if (data == nil) return nil;
    }

    // assign everything to a request
    return [self createRequestWithMethod:method url:fullUrl data:data contentType:contentType acceptContentType:acceptType charset:charset];
}

- (NSMutableURLRequest *)createRequestWithMethod:(NSString *)method url:(NSURL *)url data:(NSData *)data contentType:(NSString *)contentType acceptContentType:(SEDataRequestAcceptContentType)acceptType charset:(NSString *)charset
{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setHTTPMethod:method];
    [request setURL:url];

    if (_userAgent) [request setValue:_userAgent forHTTPHeaderField:@"User-Agent"];

    if (_isSecure)
    {
        [self applyGlobalAndDelegateSettingsForAuthorizedRequest:request];
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

- (NSURL *)buildURLWithPath:(NSString *)path baseURL:(NSURL *)baseURL forMethod:(NSString *)method body:(id)body needsBodyData:(BOOL *)needsBody error: (NSError * __autoreleasing *) error
{
    *needsBody = !([method isEqualToString:SEDataRequestMethodGET] || [method isEqualToString:SEDataRequestMethodHEAD] || [method isEqualToString:SEDataRequestMethodDELETE]);
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
            id requestService = _service;
            if (requestService == nil) THROW_INCONSISTENCY(nil);
            NSDictionary *additionalParameters = [_requestDelegate dataRequestService:requestService additionalParametersForRequestMethod:method path:path];
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
        }
        
        if (parameters == nil || parameters.count == 0) return SEDataRequestValidateAndCreateURL(baseURL, path);
        return SEDataRequestMakeURL(baseURL, path, parameters);
    }
}

- (NSData *)buildRequestDataWithBody:(id)body mimeType:(NSString *)mimeType charset:(NSString *)charset contentTypeOut:(NSString * __autoreleasing *)contentTypeOut error: (NSError * __autoreleasing *) error
{
    if (contentTypeOut == nil) THROW_INVALID_PARAM(contentTypeOut, nil);

    NSData *data = nil;
    NSString *contentType = nil;

    if (mimeType != nil)
    {
        NSError *serializationError = nil;
        SEDataSerializer *serializer = [_service explicitSerializerForMIMEType:mimeType];
        if (serializer == nil)
        {
            NSString *message = [NSString stringWithFormat:@"Serializer not found for type %@", mimeType];
            return SEDataRequestAssignErrorFromMessage(message, error);
        }
        data = [serializer serializeObject:body mimeType:mimeType error:&serializationError];
        if (serializationError != nil)
        {
            return SEDataRequestAssignSerializationError(serializationError, error);
        }
        contentType = [NSString stringWithFormat:@"%@; charset=%@", mimeType, charset];
    }
    else if ([body isKindOfClass:[NSString class]])
    {
        NSString *text = body;
        data = [text dataUsingEncoding:[_service stringEncoding]];
        contentType = [NSString stringWithFormat:@"text/plain; charset=%@", charset];
    }
    else if ([body isKindOfClass:[NSArray class]] || [body isKindOfClass:[NSDictionary class]] || [body isKindOfClass:[NSNumber class]])
    {
        NSError *jsonError = nil;
        data = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];

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

- (void)applyGlobalAndDelegateSettingsForAuthorizedRequest:(NSMutableURLRequest *)request
{
    NSAssert(_isSecure, @"Global settings only apply to secure requests");
//    NSAssert([request.URL.host isEqualToString:_baseURL.host], @"Only applies to requests sent to authorized host");

    // TODO: add request preparation delegate stuff here.

    NSString *authorizationHeader = self.authorizationHeader;
    if (authorizationHeader != nil) [request setValue:authorizationHeader forHTTPHeaderField:@"Authorization"];
}



@end
