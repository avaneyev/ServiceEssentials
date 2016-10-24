//
//  SECancellableTokenImpl.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <Foundation/Foundation.h>

#import <ServiceEssentials/SECancellableToken.h>

@interface SECancellableTokenImpl : NSObject<SECancellableToken>

- (instancetype)initWithService:(id<SECancellableItemService>)service;
- (void)cancel;

@end
