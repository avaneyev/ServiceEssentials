//
//  SEDataRequestFactory.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <Foundation/Foundation.h>
#import "SEDataRequestService.h"

@class SEInternalDataRequestBuilder;

@interface SEDataRequestFactory : NSObject

- (nonnull instancetype)initWithSecure:(BOOL)secure userAgent:(nonnull NSString *)userAgent requestPreparationDelegate:(nullable id<SEDataRequestPreparationDelegate>)requestDelegate;

@property (nonatomic, readonly, strong, nonnull) NSString *userAgent;
@property (nonatomic, strong, nullable) NSString *authorizationHeader;

- (nonnull NSURLRequest *)createRequestWithMethod:(nonnull NSString *)method;
- (nonnull NSURLRequest *)createRequestWithBuilder:(nonnull SEInternalDataRequestBuilder *)builder asUpload:(BOOL)asUpload;

@end
