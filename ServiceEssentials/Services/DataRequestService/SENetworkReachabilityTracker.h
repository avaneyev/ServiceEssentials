//
//  SENetworkReachabilityTracker.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <ServiceEssentials/SEDataRequestService.h>

@class SENetworkReachabilityTracker;

@protocol SENetworkReachabilityTrackerDelegate <NSObject>
- (void) networkReachabilityTracker: (SENetworkReachabilityTracker * _Nonnull)tracker didUpdateStatus: (SENetworkReachabilityStatus) status;
@end

@interface SENetworkReachabilityTracker : NSObject

+ (BOOL) isReachabilityAvailable;

- (nonnull instancetype)initWithURL: (NSURL * _Nonnull) url delegate: (id<SENetworkReachabilityTrackerDelegate> _Nonnull) delegate dispatchQueue: (dispatch_queue_t _Nonnull) dispatchQueue;

@property (nonatomic, readonly, assign) SENetworkReachabilityStatus reachability;
@property (nonatomic, readonly, retain, nonnull) NSString *host;

- (void) startTracking;
- (void) stopTracking;

@end
