//
//  NSArray+SEJSONExtensions.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <Foundation/Foundation.h>

@interface NSArray (SEJSONExtensions)
- (BOOL) verifyAllObjectsOfClass: (nonnull __unsafe_unretained Class) cls;
- (nullable NSArray *)parseJSONObjectsWithIndividualParser:(nonnull id _Nullable(^)(NSDictionary * _Nonnull objectJson))parser;
@end
