//
//  SENetworkReachabilityTracker.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import "SENetworkReachabilityTracker.h"
#import "SETools.h"

// Remove the header to disable the notifications.
@import SystemConfiguration;

#ifdef _SYSTEMCONFIGURATION_H
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>

#ifdef _SYSTEMCONFIGURATION_H
static inline void SENetworkReachabilityTrackerStopTracking(SCNetworkReachabilityRef reachability)
{
    if (reachability != NULL)
    {
        SCNetworkReachabilitySetCallback(reachability, NULL, NULL);
        CFRelease(reachability);
    }
}
#endif

@interface SENetworkReachabilityTracker ()
- (void)onUpdateReachabilityFlags: (SCNetworkReachabilityFlags) flags;
@end

/**
 Detects if a URL host is in fact an IP address
 As AFNetworking implementation suggests, IP addresses need special treatment, so detect if URL is based off IP address
 */
static BOOL IsURLHostIpAddress(NSString * const host)
{
    if (host)
    {
        const char *hostString = [host UTF8String];
        struct sockaddr_in sockAddrIP4;
        struct sockaddr_in6 sockAddrIP6;
        return (inet_pton(AF_INET, hostString, &sockAddrIP4) == 1 || inet_pton(AF_INET6, hostString, &sockAddrIP6) == 1);
    }
    return NO;
}

void NetworkReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info)
{
    SENetworkReachabilityTracker *tracker = (__bridge SENetworkReachabilityTracker *)info;
    [tracker onUpdateReachabilityFlags:flags];
}

#endif

@implementation SENetworkReachabilityTracker
{
    __weak id<SENetworkReachabilityTrackerDelegate> _delegate;
    dispatch_queue_t _dispatchQueue;
    volatile SENetworkReachabilityStatus _status;
#ifdef _SYSTEMCONFIGURATION_H
    SCNetworkReachabilityRef _networkReachabiilty;
#endif
}

+ (BOOL)isReachabilityAvailable
{
#ifdef _SYSTEMCONFIGURATION_H
    return YES;
#else
    return NO;
#endif
}

- (instancetype)init
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithURL:(NSURL *)url delegate:(id<SENetworkReachabilityTrackerDelegate>)delegate dispatchQueue:(dispatch_queue_t)dispatchQueue
{
    if (url == nil) THROW_INVALID_PARAM(url, nil);
    self = [super init];
    if (self)
    {
        _delegate = delegate;
        _dispatchQueue = dispatchQueue ?: dispatch_get_main_queue();
        _host = url.host;
        
#ifdef _SYSTEMCONFIGURATION_H
        _status = SENetworkReachabilityStatusUnknown;
        [self startTracking];
#else
        _status = NetworkReachabilityStatusUnavailable;
#endif
    }
    return self;
}

- (void)dealloc
{
#ifdef _SYSTEMCONFIGURATION_H
    SENetworkReachabilityTrackerStopTracking(_networkReachabiilty);
#endif
}

- (SENetworkReachabilityStatus)reachability
{
    return _status;
}

#ifndef _SYSTEMCONFIGURATION_H
- (void) startTracking
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (void) stopTracking
{
    THROW_NOT_IMPLEMENTED(nil);
}

#else

- (void) startTracking
{
    [self stopTracking];
    _networkReachabiilty = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [_host UTF8String]);
    if (_networkReachabiilty == NULL)
    {
        _status = SENetworkReachabilityStatusUnavailable;
        return;
    }
    
    SCNetworkReachabilityContext context = { .version = 0, .info = (__bridge void *)self, .retain = NULL, .release = NULL, .copyDescription = NULL };
    if (!SCNetworkReachabilitySetCallback(_networkReachabiilty, NetworkReachabilityCallback, &context))
    {
        CFRelease(_networkReachabiilty);
        _networkReachabiilty = NULL;
    }
    else
    {
        if (!SCNetworkReachabilitySetDispatchQueue(_networkReachabiilty, _dispatchQueue))
        {
            [self stopTracking];
        }
        else
        {
            if (IsURLHostIpAddress(_host))
            {
                SCNetworkReachabilityFlags flags;
                if (SCNetworkReachabilityGetFlags(_networkReachabiilty, &flags))
                {
                    [self onUpdateReachabilityFlags:flags];
                }
            }
        }
    }
}

- (void) stopTracking
{
    SENetworkReachabilityTrackerStopTracking(_networkReachabiilty);
    _networkReachabiilty = NULL;
}

- (void)onUpdateReachabilityFlags: (SCNetworkReachabilityFlags) flags
{
    SENetworkReachabilityStatus oldStatus = _status;
    BOOL isReachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
    BOOL isLocal = ((flags & kSCNetworkReachabilityFlagsIsLocalAddress) != 0);
    BOOL needsConnection = ((flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0);
    BOOL canConnectionAutomatically = (((flags & kSCNetworkReachabilityFlagsConnectionOnDemand ) != 0) || ((flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0));
    BOOL canConnectWithoutUserInteraction = (canConnectionAutomatically && (flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0);
    BOOL isNetworkReachable = (isReachable && (!needsConnection || canConnectWithoutUserInteraction));
    
    SENetworkReachabilityStatus newStatus;
    if (!isNetworkReachable)
    {
        newStatus = SENetworkReachabilityStatusNotReachable;
    }
    else if (isLocal)
    {
        newStatus = SENetworkReachabilityStatusReachableLocal;
    }
#if	TARGET_OS_IPHONE
    else if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0)
    {
        newStatus = SENetworkReachabilityStatusReachableViaWWAN;
    }
#endif
    else
    {
        newStatus = SENetworkReachabilityStatusReachableViaWiFi;
    }
    
    if (newStatus != oldStatus)
    {
        NSString *keyPath = NSStringFromSelector(@selector(reachability));
        [self willChangeValueForKey:keyPath];
        _status = newStatus;
        [self didChangeValueForKey:keyPath];
        
        dispatch_async(_dispatchQueue, ^{
            [_delegate networkReachabilityTracker:self didUpdateStatus:_status];
        });
    }
}

#endif

- (NSString *)description
{
    NSString *availabilityString = nil;
    switch (_status)
    {
        case SENetworkReachabilityStatusUnknown:
            availabilityString = NSLocalizedString(@"unknown", @"reachability unknown");
            break;
        case SENetworkReachabilityStatusUnavailable:
            availabilityString = NSLocalizedString(@"status unavailable", @"reachability unavailable");
            break;
        case SENetworkReachabilityStatusNotReachable:
            availabilityString = NSLocalizedString(@"not reachable", @"not reachable");
            break;
        case SENetworkReachabilityStatusReachableLocal:
            availabilityString = NSLocalizedString(@"local address", @"local address");
            break;
        case SENetworkReachabilityStatusReachableViaWWAN:
            availabilityString = NSLocalizedString(@"reachable via WWAN", @"reachabile via WWAN");
            break;
        case SENetworkReachabilityStatusReachableViaWiFi:
            availabilityString = NSLocalizedString(@"reachable via WiFi", @"reachable via WiFi");
            break;
            
        default:
            availabilityString = NSLocalizedString(@"unknown", @"reachability unknown");
            break;
    }
    return [NSString stringWithFormat:@"Reachability [%@]: %@", _host, availabilityString];
}

@end
