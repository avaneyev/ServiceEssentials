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
@class SEDataSerializer;

@interface SEDataRequestServiceImpl : NSObject<SEDataRequestService, SEUnsafeURLRequestService>

/** 
 Initializes a data request service with session configuration
 @param environmentService environment service that provides current environment
 @param configuration session configuration
 @discussion This initializer assumes no certificate validation exceptions
 */
- (nonnull instancetype) initWithEnvironmentService: (nonnull id<SEEnvironmentService>) environmentService sessionConfiguration: (nullable NSURLSessionConfiguration *) configuration;
/**
 Initializes a data request service with session configuration, pinning type and background handling option.
 @param environmentService environment service that provides current environment
 @param configuration session configuration
 @param pinningType a type of certificate pinning
 @param backgroundDefault determines whether requests can be sent in the background by default.
 This is not an equivalent to the background session. Instead, it just allows to finish outstanding requests
 when the application goes to the background as opposed to cancelling them immediately.
 @discussion This initializer assumes default set of data serializers, which cover typical types like JSON and plain text.
 */
- (nonnull instancetype) initWithEnvironmentService: (nonnull id<SEEnvironmentService>) environmentService sessionConfiguration: (nullable NSURLSessionConfiguration *) configuration pinningType: (SEDataRequestCertificatePinningType) certificatePinningType applicationBackgroundDefault: (BOOL) backgroundDefault;

/**
 Initializes a data request service with session configuration and a list of hosts which may have invalid (including self-signed) certificates
 @param environmentService environment service that provides current environment
 @param configuration session configuration
 @param qualityOfService quality of service that determines the priority of a queue processing data requests
 @param pinningType a type of certificate pinning
 @param backgroundDefault determines whether requests can be sent in the background by default. 
    This is not an equivalent to the background session. Instead, it just allows to finish outstanding requests 
    when the application goes to the background as opposed to cancelling them immediately.
 @param serializers a dictionary mapping MIME types to corresponding serializers. 
    One serializer can be used for multiple MIME types.
    Serializers must be thread-safe and re-entrant, and preferrably stateless.
    If a serializer is not defined for a MIME type, a default will be used, which just uses response data as a reasult.
 @discussion It is highly recommended to use pinned certificates to be able to establish truly trusted connection.
 */
- (nonnull instancetype) initWithEnvironmentService: (nonnull id<SEEnvironmentService>) environmentService
                               sessionConfiguration: (nullable NSURLSessionConfiguration *) configuration
                                   qualityOfService:(SEDataRequestQualityOfService)qualityOfService
                                        pinningType: (SEDataRequestCertificatePinningType) certificatePinningType
                       applicationBackgroundDefault: (BOOL) backgroundDefault
                                        serializers:(nullable NSDictionary<NSString *, __kindof SEDataSerializer *> *)serializers;

@end
