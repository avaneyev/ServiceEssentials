//
//  SEEnvironmentService.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <Foundation/Foundation.h>

static NSString * _Nonnull const SEEnvironmentChangedNotification = @"SEEnvironmentChangedNotification";

@protocol SEEnvironmentService <NSObject>
- (nonnull NSString *) currentEnvironment;
- (nonnull NSURL *) environmentBaseURL;
@end
