//
//  SEDataRequestServiceImpl.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import "SEDataRequestService.h"

@protocol SEEnvironmentService;

@interface SEDataRequestServiceImpl : NSObject<SEDataRequestService, SEUnsafeURLRequestService>

/** 
 Initializes a data request service with session configuration
 @param environmentService environment service that provides current environment
 @param configuration session configuration
 @discussion This initializer assumes no certificate validation exceptions
 */
- (nonnull instancetype) initWithEnvironmentService: (nonnull id<SEEnvironmentService>) environmentService sessionConfiguration: (nullable NSURLSessionConfiguration *) configuration;

/**
 Initializes a data request service with session configuration and a list of hosts which may have invalid (including self-signed) certificates
 @param environmentService environment service that provides current environment
 @param configuration session configuration
 @param pinningType a type of certificate pinning
 @param backgroundDefault determines whether requests can be sent in the background by default
 @discussion It is highly recommended to use pinned certificates to be able to establish truly trusted connection
 */
- (nonnull instancetype) initWithEnvironmentService: (nonnull id<SEEnvironmentService>) environmentService sessionConfiguration: (nullable NSURLSessionConfiguration *) configuration pinningType: (SEDataRequestCertificatePinningType) certificatePinningType applicationBackgroundDefault: (BOOL) backgroundDefault;

@end
