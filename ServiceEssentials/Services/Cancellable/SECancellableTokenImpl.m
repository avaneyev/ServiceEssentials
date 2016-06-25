//
//  SECancellableTokenImpl.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import "SECancellableTokenImpl.h"

@implementation SECancellableTokenImpl
{
    __weak id<SECancellableItemService> _service;
}

- (instancetype)initWithService:(id<SECancellableItemService>)service
{
    self = [super init];
    if (self)
    {
        _service = service;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (void)cancel
{
    [_service cancelItemForToken:self];
}

@end
