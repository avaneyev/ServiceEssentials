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

// Always returns nil, it's a shortcut to make a one-liner statement that creates an error and returns no data.
static inline id SEDataRequestServiceGracefulHandleError(NSString *message, NSError * __autoreleasing *error)
{
    if (error != nil)
    {
        *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceRequestSubmissuionFailure userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    SELog(@"%@", message);
    return nil;
}

static inline id SEDataRequestHandleSerializationError(NSError *error, NSError * __autoreleasing *errorOut)
{
    if (errorOut != nil)
    {
        *errorOut = error;
    }
    SELog(@"Failed to serialize request data: %@", error);
    return nil;
}


// Macro for generic handling of an error while building data requests (graceful in Release, crash in Debug)
#ifdef DEBUG
#define HANDLE_BUILD_REQUEST_ERROR(message) do { THROW_INVALID_PARAM(body, @{ NSLocalizedDescriptionKey: message }); } while(0)
#else
#define HANDLE_BUILD_REQUEST_ERROR(message) do { return SEDataRequestServiceGracefulHandleError(message, error); } while(0)
#endif

@implementation SEDataRequestFactory
{
    __weak id<SEDataRequestServicePrivate> _service;
    BOOL _isSecure;
    NSString *_userAgent;
    NSString *_authorizationHeader;
    pthread_mutex_t _authorizationHeaderLock;
}

@synthesize userAgent = _userAgent;

- (instancetype)init
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithService:(id<SEDataRequestServicePrivate>)service secure:(BOOL)secure userAgent:(NSString *)userAgent requestPreparationDelegate:(id<SEDataRequestPreparationDelegate>)requestDelegate
{
    if (service == nil) THROW_INVALID_PARAM(service, nil);

    self = [super init];
    if (self)
    {
        _service = service;
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
    NSString *value;
    
    pthread_mutex_lock(&_authorizationHeaderLock);
    value = _authorizationHeader;
    pthread_mutex_unlock(&_authorizationHeaderLock);

    return value;
}

- (void)setAuthorizationHeader:(NSString *)authorizationHeader
{
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
    return [self buildRequestWithMethod:method baseURL:baseURL path:path body:body mimeType:mimeType acceptContentType:SEDataRequestAcceptContentTypeJSON error:error];
}

- (NSURLRequest *)createRequestWithBuilder:(SEInternalDataRequestBuilder *)builder
                                   baseURL:(NSURL *)baseURL
                                  asUpload:(BOOL)asUpload
                                     error:(NSError * _Nullable __autoreleasing *)error
{
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
    NSURL *fullUrl;
    *needsBody = NO;
    if ([method isEqualToString:SEDataRequestMethodGET] || [method isEqualToString:SEDataRequestMethodHEAD] || [method isEqualToString:SEDataRequestMethodDELETE])
    {
        if (body != nil)
        {
            if ([body isKindOfClass:[NSDictionary class]])
            {
                fullUrl = [self makeURLWithPath:path baseURL:baseURL parameters:body];
            }
            else
            {
                NSString *message = [NSString stringWithFormat:@"Not a valid body type for %@ request: %@", method, [body class]];
                HANDLE_BUILD_REQUEST_ERROR(message);
            }
        }
        else
        {
            fullUrl = [self validateAndCreateURLWithPath:path baseURL:baseURL];
        }
    }
    else
    {
        fullUrl = [self validateAndCreateURLWithPath:path baseURL:baseURL];
        *needsBody = YES;
    }
    return fullUrl;
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
            return SEDataRequestServiceGracefulHandleError(message, error);
        }
        data = [serializer serializeObject:body mimeType:mimeType error:&serializationError];
        if (serializationError != nil)
        {
            return SEDataRequestHandleSerializationError(serializationError, error);
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
            return SEDataRequestHandleSerializationError(jsonError, error);
        }

        contentType = [NSString stringWithFormat:@"application/json; charset=%@", charset];
    }
    else
    {
        NSString *message = [NSString stringWithFormat:@"Not a valid request data type: %@", [body class]];
        return SEDataRequestServiceGracefulHandleError(message, error);
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

- (NSURL *)makeURLWithPath:(NSString *)path baseURL:(NSURL *)baseURL parameters:(NSDictionary *)parameters
{
    NSString *urEncodedParameters = [SEWebFormSerializer webFormEncodedStringFromDictionary:parameters withEncoding:NSUTF8StringEncoding];
    NSString *appendString = ([path rangeOfString:@"?"].location == NSNotFound) ? @"?" : @"&";
    return [self validateAndCreateURLWithPath:[NSString stringWithFormat:@"%@%@%@", path, appendString, urEncodedParameters] baseURL:baseURL];
}

- (NSURL *)validateAndCreateURLWithPath:(NSString *)path baseURL:(NSURL *)baseURL
{
    NSURL *url = [NSURL URLWithString:path relativeToURL:baseURL];
    if (![url.scheme isEqualToString:baseURL.scheme] || ![url.host isEqualToString:baseURL.host])
    {
        THROW_INVALID_PARAM(path, @{ NSLocalizedDescriptionKey: @"Path is not really a path, it modifies host or scheme and cannot be accepted." });
    }
    return url;
}



@end
