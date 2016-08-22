//
//  SEDataRequestServiceUserAgent.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#ifndef SEDataRequestServiceUserAgent_h
#define SEDataRequestServiceUserAgent_h


static inline NSString * _Nonnull SEDataRequestServiceUserAgent()
{
    // User-Agent Header; see http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.43
    
    NSString *userAgent = nil;
    NSDictionary *applicationDictionary = [[NSBundle mainBundle] infoDictionary];
    
    NSString *appName = [applicationDictionary objectForKey:(__bridge NSString *)kCFBundleExecutableKey];
    if (appName == nil) appName = [applicationDictionary objectForKey:(__bridge NSString *)kCFBundleIdentifierKey];
    
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
    id appVersion = (__bridge id)CFBundleGetValueForInfoDictionaryKey(CFBundleGetMainBundle(), kCFBundleVersionKey);
    if (appVersion == nil) appVersion = [applicationDictionary objectForKey:(__bridge NSString *)kCFBundleVersionKey];
    
    UIDevice *device = [UIDevice currentDevice];
    CGFloat scale = ([[UIScreen mainScreen] respondsToSelector:@selector(scale)] ? [[UIScreen mainScreen] scale] : 1.0f);
    
    userAgent = [NSString stringWithFormat:@"%@/%@ (%@; iOS %@; Scale/%0.2f)", appName, appVersion, [device model], [device systemVersion], scale];
#elif defined(__MAC_OS_X_VERSION_MIN_REQUIRED)
    id appVersion = [applicationDictionary objectForKey:@"CFBundleShortVersionString"];
    if (appVersion == nil) appVersion = [applicationDictionary objectForKey:(__bridge NSString *)kCFBundleVersionKey];
    
    userAgent = [NSString stringWithFormat:@"%@/%@ (Mac OS X %@)", appName, appVersion, [[NSProcessInfo processInfo] operatingSystemVersionString]];
#endif
    
    return userAgent;
}


#endif /* SEDataRequestServiceUserAgent_h */
