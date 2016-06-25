//
//  NSDictionary+SEJSONExtensions.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <Foundation/Foundation.h>

@interface NSDictionary (SEJSONExtensions)
/** safely takes a value for key, checking it for `null` */
- (nullable id) safeObjectForKey: (nonnull id) key;
/** safely takes a value for key, checking it is of string type */
- (nullable NSString *) safeStringForKey: (nonnull id) key;
/** safely takes a value for key, checking it is of numeric type */
- (nullable NSNumber *) safeNumberForKey: (nonnull id) key;
/** safely takes a Unix timestamp value for key, checking it is of proper type and value */
- (nullable NSDate *) safeTimestampForKey: (nonnull id) key;
/** safely takes a an array for key, checking it is of proper type and its contens are of a certain class */
- (nullable NSArray *) safeArrayOfType: (nonnull __unsafe_unretained Class) cls forKey: (nonnull id) key;
@end

@interface NSMutableDictionary (JSONExtensions)
/** safely sets a value for key, if the value being set is nil it is discarded */
- (void) safeSetObject: (nullable id) object forKey: (nonnull id<NSCopying>) key;
/** safely sets a value for key, if the value being set is nil, null value is used */
- (void) nullableSetObject: (nullable id) object forKey: (nonnull id<NSCopying>) key;
@end