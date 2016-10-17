//
//  SEDefaultDataSerializer.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <Foundation/Foundation.h>

@interface SEDataSerializer : NSObject

/**
 Determines if a serializer supports additional parameters provided by the request preparation delegate.
 Default implemetation returns `NO`. Subclasses may return `YES` if they are prepared to handle additional parameters
 merged to the object being serialized.
 */
@property (nonatomic, readonly) BOOL supportsAdditionalParameters;

/**
 Determines if `Content-Type` header should contain charset when using this serializer
 */
@property (nonatomic, readonly) BOOL shouldAppendCharsetToContentType;

/** Serialize the object to data
 @param object object to be serialized
 @param mimeType data type hint, seializers could use it to extract charset and other encoding parameters
 @param error a pointer where error will be returned if serialization fails
 @return serialized data or @a nil if serialization fails
 */
- (NSData *) serializeObject: (id) object mimeType: (NSString *) mimeType error: (NSError * __autoreleasing *) error;

/** Deserialize the data to an object
 @param data data to be deserialized
 @param mimeType data type hint, seializers could use it to extract charset and other encoding parameters
 @param error a pointer where error will be returned if serialization fails
 @return deserialized object or @a nil if deserialization fails
 */
- (id) deserializeData: (NSData *) data mimeType: (NSString *) mimeType error: (NSError * __autoreleasing *) error;

/** Helper function to extract charset from MIME type */
+ (NSStringEncoding) charsetFromMIMEType: (NSString *) mimeType;
/** Helper function to detect MIME type based on file extension */
+ (NSString *) mimeTypeForFileExtension: (NSString *) extension;

@end
