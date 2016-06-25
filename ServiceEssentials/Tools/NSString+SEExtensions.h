//
//  NSString+SEExtensions.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <Foundation/Foundation.h>

@interface NSString (SEExtentsions)

- (BOOL) isEmptyOrWhitespace;

+ (NSString *) randomStringOfLength:(NSUInteger)length;

@end
