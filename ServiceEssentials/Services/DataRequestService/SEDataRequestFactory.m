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

@implementation SEDataRequestFactory
{
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

- (instancetype)initWithSecure:(BOOL)secure userAgent:(NSString *)userAgent requestPreparationDelegate:(id<SEDataRequestPreparationDelegate>)requestDelegate
{
    self = [super init];
    if (self)
    {
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
{
    return nil;
}

- (NSURLRequest *)createRequestWithBuilder:(SEInternalDataRequestBuilder *)builder asUpload:(BOOL)asUpload
{
    return nil;
}

@end
