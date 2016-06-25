//
//  SEMultipartRequestContentStream.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <Foundation/Foundation.h>

@class SEMultipartRequestContentPart;

@interface SEMultipartRequestContentStream : NSInputStream

- (nonnull instancetype) initWithParts: (nonnull NSArray<SEMultipartRequestContentPart *> *) parts boundary: (nonnull NSString *) boundary stringEncoding: (NSStringEncoding) stringEncoding;

/* Content-Length header needs to have a value upfront, before the entire stream is calculated, so this value has to be precise based on parts, boundary and encoding */
+ (unsigned long long) contentLengthForParts: (nonnull NSArray<SEMultipartRequestContentPart *> *) parts boundary: (nonnull NSString *) boundary stringEncoding: (NSStringEncoding) stringEncoding;

@end
