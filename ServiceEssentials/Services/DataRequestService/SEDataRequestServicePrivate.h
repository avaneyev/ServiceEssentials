//
//  SEDataRequestServicePrivate.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import "SECancellableToken.h"

#ifndef ServiceEssentials_DataRequestServicePrivate_h
#define ServiceEssentials_DataRequestServicePrivate_h

typedef enum {
    SEDataRequestAcceptContentTypeData,
    SEDataRequestAcceptContentTypeJSON
} SEDataRequestAcceptContentType;

#endif // ServiceEssentials_DataRequestServicePrivate_h

#import "SEDataRequestServiceImpl.h"

@protocol SECancellableToken;
@class SEInternalDataRequest;
@class SEDataSerializer;
@class SEInternalDataRequestBuilder;

@protocol SEDataRequestServicePrivate <NSObject, SECancellableItemService>
/** Called when a data request is complete. Removes the request from internal data structures */
- (void) completeInternalRequest: (nonnull SEInternalDataRequest *) request;
/** Returns a serializer for a specified MIME type. Returns default serializer when explicit serializer was not found */
- (nullable SEDataSerializer *) serializerForMIMEType: (nonnull NSString *) mimeType;
/** Returns a serializer for a specified MIME type. Returns `nil` when explicit serializer was not found */
- (nullable SEDataSerializer *) explicitSerializerForMIMEType: (nonnull NSString *) mimeType;

/** Submits a request with parameters specified by the builder. */
- (nullable id<SECancellableToken>)submitRequestWithBuilder: (nonnull SEInternalDataRequestBuilder *) requestBuilder asUpload: (BOOL) asUpload;

- (NSStringEncoding) stringEncoding;
@end

@interface SEDataRequestServiceImpl (Private)
/** Checks if a class supports deserialization */
+ (BOOL) canDeserializeToClass: (nonnull Class) class;
+ (nullable NSURL *)appendQueryStringToURL:(nonnull NSURL *)url query:(nonnull NSString *)query;
+ (nullable NSURL *)appendQueryStringToURL:(nonnull NSURL *)url queryParameters:(nonnull NSDictionary<NSString *, id> *)query encoding:(NSStringEncoding)encoding;
@end