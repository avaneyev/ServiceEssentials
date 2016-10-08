//
//  SEDataRequestServiceSecurityHelper.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//
// -----------------------------------------------------------------------------
// Contains modified parts from AFNetworking v.2.6.3
// AFNetworking repository: https://github.com/AFNetworking/AFNetworking
// AFNetworking is distributed under MIT License:
// Copyright (c) 2011–2015 Alamofire Software Foundation (http://alamofire.org/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
// -----------------------------------------------------------------------------


#import <ServiceEssentials/SEDataRequestServiceSecurityHelper.h>

#import <ServiceEssentials/SEDataRequestService.h>

// Declarations for some helper functions
#if !defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
static NSData *SecKeyGetData(SecKeyRef key);
#endif
static BOOL SecKeyIsEqualToKey(SecKeyRef key1, SecKeyRef key2);

@implementation SEDataRequestServiceSecurityHelper

#pragma mark - Security

+ (BOOL)validateTrustDefault:(SecTrustRef)serverTrust error:(NSError *__autoreleasing *)error
{
    SecTrustResultType result;
    OSStatus status = SecTrustEvaluate(serverTrust, &result);
    
    BOOL returnValue = (status == errSecSuccess) && ((result == kSecTrustResultProceed) || (result == kSecTrustResultUnspecified));
    
    if (!returnValue && error != nil) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceTrustFailure userInfo:@{NSLocalizedDescriptionKey: @"Default Validation: Trust chain evaluation failed."}];
    return returnValue;
}

+ (BOOL)validateTrustDefaultAcceptRecoverable:(SecTrustRef)serverTrust error:(NSError *__autoreleasing *)error
{
    SecTrustResultType result;
    OSStatus status = SecTrustEvaluate(serverTrust, &result);
    
    BOOL returnValue = (status == errSecSuccess) && ((result == kSecTrustResultProceed) || (result == kSecTrustResultUnspecified) || (result == kSecTrustResultRecoverableTrustFailure));
    
    if (!returnValue && error != nil) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceTrustFailure userInfo:@{NSLocalizedDescriptionKey: @"Validate accepting recoverable fault: Trust chain evaluation failed."}];
    return returnValue;
}

/** Validates the server trust using pinned certificates */
+ (BOOL) validateTrustUsingCertificates: (SecTrustRef) serverTrust error:(NSError * __autoreleasing *) error
{
    NSArray *trustChain = [self buildTrustChainFromTrust:serverTrust useCertificate:YES error:error];
    if (trustChain)
    {
        NSArray *pinnedCertificates = [self pinnedCertificates];
        if (pinnedCertificates.count == 0)
        {
            if (error) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceTrustFailure userInfo:@{NSLocalizedDescriptionKey: @"There has to be at least one certificate file in the application bundle."}];
            return NO;
        }
        
        for (id serverCertificateData in trustChain)
        {
            if ([pinnedCertificates containsObject:serverCertificateData])
            {
                return YES;
            }
        }
    }
    if (error) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceTrustFailure userInfo:@{NSLocalizedDescriptionKey: @"There was no matching pinned certificate in the application bundle."}];
    
    return NO;
}

+ (BOOL) validateTrustUsingPublicKeys: (SecTrustRef) serverTrust error:(NSError * __autoreleasing *) error
{
    NSArray *trustChain = [self buildTrustChainFromTrust:serverTrust useCertificate:NO error:error];
    if (trustChain)
    {
        NSArray *pinnedPublicKeys = [self pinnedPublicKeys];
        if (pinnedPublicKeys.count == 0)
        {
            if (error) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceTrustFailure userInfo:@{NSLocalizedDescriptionKey: @"There has to be at least one key file in the application bundle."}];
            return NO;
        }
        
        for (id publicKey in trustChain)
        {
            for (id pinnedPublicKey in pinnedPublicKeys)
            {
                if (SecKeyIsEqualToKey((__bridge SecKeyRef)publicKey, (__bridge SecKeyRef)pinnedPublicKey))
                {
                    return YES;
                }
            }
        }
    }
    
    if (error) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceTrustFailure userInfo:@{NSLocalizedDescriptionKey: @"There was no matching pinned certificate in the application bundle."}];
    
    return NO;
}


/**
 This function constructs a trust chain of certificates based on server trust
 @param serverTrust server trust (received with a response)
 @param useCertificate a boolean indicating wether to use a certificate or just a key
 */
+ (NSArray *) buildTrustChainFromTrust: (SecTrustRef) serverTrust useCertificate: (BOOL) useCertificate error: (NSError * __autoreleasing *) error
{
    NSError *innerError = nil;
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    SecTrustEvaluate(serverTrust, NULL);
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:certificateCount];
    
    for (CFIndex i = 0; i < certificateCount; i++)
    {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);
        
        if (useCertificate)
        {
            [trustChain addObject:(__bridge_transfer NSData *)SecCertificateCopyData(certificate)];
        }
        else
        {
            CFArrayRef certificates = CFArrayCreate(NULL, (const void **)&certificate, 1, NULL);
            SecTrustRef trust = NULL;
            
            OSStatus status = SecTrustCreateWithCertificates(certificates, policy, &trust);
            if (status != errSecSuccess)
            {
                innerError = [self createErrorFromOSStatus:status function:@"SecTrustCreateWithCertificates"];
            }
            else if (trust)
            {
                SecTrustResultType result;
                status = SecTrustEvaluate(trust, &result);
                if (status == errSecSuccess)
                {
                    if (   (result == kSecTrustResultUnspecified)
                        || (result == kSecTrustResultProceed)
                        || (result == kSecTrustResultRecoverableTrustFailure))
                    {
                        [trustChain addObject:(__bridge_transfer id)SecTrustCopyPublicKey(trust)];
                    }
                }
                else
                {
                    innerError = [self createErrorFromOSStatus:status function:@"SecTrustEvaluate"];
                }
                
                CFRelease(trust);
            }
            
            CFRelease(certificates);
            if (innerError) break;
        }
    }
    
    CFRelease(policy);
    
    if (innerError)
    {
        if (error) *error = innerError;
        return nil;
    }
    return [NSArray arrayWithArray:trustChain];
}

+ (NSError *) createErrorFromOSStatus: (OSStatus) statusCode function: (NSString *) function
{
    NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ failed with code %d", function, (int)statusCode]};
    return [NSError errorWithDomain:SEErrorDomain code:statusCode userInfo:userInfo];
}


/**
 @a pinnedCertificates function is just an exact copy of the AFNetworking function with the same name
 */
+ (NSArray *)pinnedCertificates
{
    static NSArray *_pinnedCertificates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle mainBundle];
        NSArray *paths = [bundle pathsForResourcesOfType:@"cer" inDirectory:@"."];
        
        NSMutableArray *certificates = [NSMutableArray arrayWithCapacity:[paths count]];
        for (NSString *path in paths) {
            NSData *certificateData = [NSData dataWithContentsOfFile:path];
            [certificates addObject:certificateData];
        }
        
        _pinnedCertificates = [[NSArray alloc] initWithArray:certificates];
    });
    
    return _pinnedCertificates;
}

/**
 @a pinnedPublicKeys function is just an exact copy of the AFNetworking function with the same name
 */
+ (NSArray *)pinnedPublicKeys
{
    static NSArray *_pinnedPublicKeys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *pinnedCertificates = [self pinnedCertificates];
        NSMutableArray *publicKeys = [NSMutableArray arrayWithCapacity:[pinnedCertificates count]];
        
        for (NSData *data in pinnedCertificates)
        {
            SecCertificateRef allowedCertificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)data);
            NSParameterAssert(allowedCertificate);
            
            CFArrayRef certificates = CFArrayCreate(NULL, (const void **)&allowedCertificate, 1, NULL);
            
            SecPolicyRef policy = SecPolicyCreateBasicX509();
            SecTrustRef allowedTrust = NULL;
            OSStatus status = SecTrustCreateWithCertificates(certificates, policy, &allowedTrust);
            NSAssert(status == errSecSuccess, @"SecTrustCreateWithCertificates error: %ld", (long int)status);
            if (status == errSecSuccess && allowedTrust)
            {
                SecTrustResultType result = 0;
                status = SecTrustEvaluate(allowedTrust, &result);
                NSAssert(status == errSecSuccess, @"SecTrustEvaluate error: %ld", (long int)status);
                if (status == errSecSuccess)
                {
                    SecKeyRef allowedPublicKey = SecTrustCopyPublicKey(allowedTrust);
                    NSParameterAssert(allowedPublicKey);
                    if (allowedPublicKey)
                    {
                        [publicKeys addObject:(__bridge_transfer id)allowedPublicKey];
                    }
                }
                
                CFRelease(allowedTrust);
            }
            
            CFRelease(policy);
            CFRelease(certificates);
            CFRelease(allowedCertificate);
        }
        
        _pinnedPublicKeys = [[NSArray alloc] initWithArray:publicKeys];
    });
    
    return _pinnedPublicKeys;
}

@end

/** The two functions below are just copies of AFNetworking implementation */
#if !defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
static NSData *SecKeyGetData(SecKeyRef key)
{
    CFDataRef data = NULL;
    
#if defined(NS_BLOCK_ASSERTIONS)
    SecItemExport(key, kSecFormatUnknown, kSecItemPemArmour, NULL, &data);
#else
    OSStatus status = SecItemExport(key, kSecFormatUnknown, kSecItemPemArmour, NULL, &data);
    NSCAssert(status == errSecSuccess, @"SecItemExport error: %ld", (long int)status);
#endif
    
    NSCParameterAssert(data);
    
    return (__bridge_transfer NSData *)data;
}
#endif

static BOOL SecKeyIsEqualToKey(SecKeyRef key1, SecKeyRef key2)
{
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
    return [(__bridge id)key1 isEqual:(__bridge id)key2];
#else
    return [SecKeyGetData(key1) isEqual:AFSecKeyGetData(key2)];
#endif
}