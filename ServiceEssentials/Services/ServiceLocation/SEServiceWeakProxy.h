//
//  SEServiceWeakProxy.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <Foundation/Foundation.h>

@interface SEServiceWeakProxy : NSProxy

- (nonnull instancetype) initWithTarget: (nonnull id) target protocol: (nonnull Protocol *) protocol;

@property (nonatomic, readonly, assign) BOOL isValid;

@end
