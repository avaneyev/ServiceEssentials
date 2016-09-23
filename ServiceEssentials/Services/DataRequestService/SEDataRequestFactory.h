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
#import "SEDataRequestServicePrivate.h"

@class SEInternalDataRequestBuilder;

@interface SEDataRequestFactory : NSObject

- (nonnull instancetype)initWithService:(nonnull id<SEDataRequestServicePrivate>)service secure:(BOOL)secure userAgent:(nonnull NSString *)userAgent requestPreparationDelegate:(nullable id<SEDataRequestPreparationDelegate>)requestDelegate;

@property (nonatomic, readonly, strong, nonnull) NSString *userAgent;
@property (nonatomic, strong, nullable) NSString *authorizationHeader;

- (nonnull NSURLRequest *)createRequestWithMethod:(nonnull NSString *)method
                                          baseURL:(nonnull NSURL *)baseURL
                                             path:(nullable NSString *)path
                                             body:(nullable id)body
                                         mimeType:(nullable NSString *)mimeType
                                            error:(NSError * __autoreleasing _Nullable * _Nullable)error;

- (nonnull NSURLRequest *)createRequestWithBuilder:(nonnull SEInternalDataRequestBuilder *)builder
                                           baseURL:(nonnull NSURL *)baseURL
                                          asUpload:(BOOL)asUpload
                                             error:(NSError * __autoreleasing _Nullable * _Nullable)error;

@end
