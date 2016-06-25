//
//  SEMultipartRequestContentPart.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

@import Foundation;

@interface SEMultipartRequestContentPart : NSObject

- (nonnull instancetype) initWithData: (nonnull NSData *) data name: (nonnull NSString *) name fileName: (nullable NSString *) fileName mimeType: (nonnull NSString *) mimeType;
- (nonnull instancetype) initWithFileURL: (nonnull NSURL *) fileUrl length:(unsigned long long) length name: (nonnull NSString *) name fileName: (nullable NSString *) fileName mimeType:(nonnull NSString *) mimeType;

@property (nonatomic, readonly, strong, nonnull) NSString *name;
@property (nonatomic, readonly, strong, nullable) NSData *data;
@property (nonatomic, readonly, strong, nullable) NSString *fileName;
@property (nonatomic, readonly, strong, nullable) NSURL *fileURL;
@property (nonatomic, readonly, assign) unsigned long long contentSize;

@property (nonatomic, readonly, strong, nullable, getter=headers) NSDictionary<NSString *, NSString *> *headers;
@end
