//
//  SEInternalDataRequestBuilder.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <ServiceEssentials/SEDataRequestService.h>
#import "SEDataRequestServicePrivate.h"

@class SEMultipartRequestContentPart;

@interface SEInternalDataRequestBuilder : NSObject<SEDataRequestBuilder, SEDataRequestCustomizer>
- (nonnull instancetype) initWithDataRequestService: (nonnull id<SEDataRequestServicePrivate>) dataRequestService;

@property (nonatomic, readonly, strong, nullable) NSString *method;
@property (nonatomic, readonly, strong, nullable) NSString *path;
@property (nonatomic, readonly, strong, nullable) void (^success)(id _Nonnull, NSURLResponse * _Nonnull);
@property (nonatomic, readonly, strong, nullable) void (^failure)(NSError * _Nonnull);
@property (nonatomic, readonly, strong, nullable) dispatch_queue_t completionQueue;

@property (nonatomic, readonly, assign) SEDataRequestQualityOfService qualityOfService;

@property (nonatomic, readonly, assign, nullable) Class deserializeClass;
@property (nonatomic, readonly, strong, nullable) NSString *contentEncoding;
@property (nonatomic, readonly, assign) SEDataRequestAcceptContentType acceptContentType;
@property (nonatomic, readonly, strong, nullable) NSDictionary<NSString *, NSString *> *headers;
@property (nonatomic, readonly, strong, nullable) NSIndexSet *expectedHTTPCodes;
@property (nonatomic, readonly, strong, nullable) NSDictionary<NSString *, id> *bodyParameters;
@property (nonatomic, readonly, strong, nullable) NSArray<SEMultipartRequestContentPart *> *contentParts;
@property (nonatomic, readonly, strong, nullable) NSNumber *canSendInBackground;

@end
