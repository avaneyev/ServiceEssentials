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
#import "SETools.h"

static inline void SEDataRequestVerifyQOS(SEDataRequestQualityOfService qualityOfService)
{
    if (   qualityOfService != SEDataRequestQOSDefault
        && qualityOfService != SEDataRequestQOSPriorityBackground
        && qualityOfService != SEDataRequestQOSPriorityLow
        && qualityOfService != SEDataRequestQOSPriorityNormal
        && qualityOfService != SEDataRequestQOSPriorityHigh
        && qualityOfService != SEDataRequestQOSPriorityInteractive)
    {
        THROW_INVALID_PARAM(qualityOfService, @{ NSLocalizedDescriptionKey: @"Unrecognized quality of service (QOS) value." });
    }
}

static inline float SEDataRequestServiceTaskPriorityForQOS(const SEDataRequestQualityOfService qos)
{
    switch (qos) {
        case SEDataRequestQOSPriorityLow:
        case SEDataRequestQOSPriorityBackground:
            return NSURLSessionTaskPriorityLow;
        case SEDataRequestQOSPriorityHigh:
        case SEDataRequestQOSPriorityInteractive:
            return NSURLSessionTaskPriorityHigh;
        case SEDataRequestQOSDefault:
        case SEDataRequestQOSPriorityNormal:
        default:
            return NSURLSessionTaskPriorityDefault;
    }
}

static inline NSQualityOfService SEDataRequestQualityOfServiceForQOS(const SEDataRequestQualityOfService qos)
{
    if (qos == SEDataRequestQOSDefault) return NSQualityOfServiceDefault;
    return (NSQualityOfService)qos;
}

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
