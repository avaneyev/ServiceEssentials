//
//  SEDataRequestServiceSecurityHelper.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

@import Foundation;

@interface SEDataRequestServiceSecurityHelper : NSObject
+ (BOOL) validateTrustDefault: (SecTrustRef) serverTrust error:(NSError * __autoreleasing *) error;
+ (BOOL) validateTrustUsingCertificates: (SecTrustRef) serverTrust error:(NSError * __autoreleasing *) error;
+ (BOOL) validateTrustUsingPublicKeys: (SecTrustRef) serverTrust error:(NSError * __autoreleasing *) error;

/** this function will accept self-signed certificates, so use with caution */
+ (BOOL) validateTrustDefaultAcceptRecoverable: (SecTrustRef) serverTrust error:(NSError * __autoreleasing *) error;
@end
