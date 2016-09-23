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

#include <objc/runtime.h>

#import "SEDataRequestServiceImpl.h"
#import "SETools.h"
#import "SEWebFormSerializer.h"

extern NSString * _Nonnull const SEDataRequestMethodGET;
extern NSString * _Nonnull const SEDataRequestMethodPOST;
extern NSString * _Nonnull const SEDataRequestMethodPUT;
extern NSString * _Nonnull const SEDataRequestMethodDELETE;
extern NSString * _Nonnull const SEDataRequestMethodHEAD;

@protocol SECancellableToken;
@class SEInternalDataRequest;
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

/* Utilities */

// Verify Quality of Service value
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

// Translate QoS to Task Priority
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

// Translate service-specific QoS value to task's QoS
static inline NSQualityOfService SEDataRequestQualityOfServiceForQOS(const SEDataRequestQualityOfService qos)
{
    if (qos == SEDataRequestQOSDefault) return NSQualityOfServiceDefault;
    return (NSQualityOfService)qos;
}

// Helper function to validate and assign headers to URL request
static inline void SEAssignHeadersToURLRequest(NSMutableURLRequest * _Nonnull request, NSDictionary * _Nullable headers)
{
    if (headers != nil)
    {
        NSDictionary *existingHeaders = request.allHTTPHeaderFields;
        for (NSString *header in headers)
        {
            if ([existingHeaders objectForKey:header])
            {
#ifdef DEBUG
                NSDictionary *info = @{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Attempting to override existing header %@", header] };
                THROW_INVALID_PARAM(headers, info);
#else
                continue;
#endif
            }
            [request setValue:[headers objectForKey:header] forHTTPHeaderField:header];
        }
    }
}

// Checks if a class can be used for type-safe deserialization
static inline BOOL SECanDeserializeToClass(Class _Nonnull klass)
{
    BOOL conforms = NO;
    while (true)
    {
        conforms = class_conformsToProtocol(klass, @protocol(SEDataRequestJSONDeserializable));
#ifdef DEBUG
        conforms &= class_getClassMethod(klass, @selector(deserializeFromJSON:)) != NULL;
#endif
        if (conforms) break;
        
        klass = class_getSuperclass(klass);
        if (klass == nil || klass == [NSObject class]) break;
    }
    return conforms;
}

typedef void (^ SEFailureBlock)(NSError * _Nonnull error);

static inline BOOL SEVerifyClassForDeserialization(Class _Nonnull klass, SEFailureBlock _Nonnull failure, dispatch_queue_t _Nullable completionQueue)
{
    if (!SECanDeserializeToClass(klass))
    {
        NSString *reason = [NSString stringWithFormat:@"Class %@ is does not support deserialization.", klass];
#ifdef DEBUG
        THROW_INVALID_PARAM(klass, (@{ NSLocalizedDescriptionKey: reason }));
#else
        if (failure != nil) {
            dispatch_async(completionQueue, ^{
                failure([NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:@{ NSLocalizedDescriptionKey: reason }]);
            });
        }
        return NO;
#endif
    }
    
    return YES;
}


static inline NSURL * _Nonnull SEURLByAppendingQuery(NSURL * _Nonnull url, NSString * _Nonnull query)
{
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:YES];
    NSString *existingQuery = components.query;
    if (existingQuery == nil || existingQuery.length == 0)
    {
        components.query = query;
    }
    else
    {
        components.query = [NSString stringWithFormat:@"%@&%@", existingQuery, query];
    }
    return components.URL;
}

static inline NSURL * _Nonnull SEURLByAppendingQueryParameters(NSURL * _Nonnull url, NSDictionary<NSString *, id> * _Nonnull query, NSStringEncoding encoding)
{
    return SEURLByAppendingQuery(url, [SEWebFormSerializer webFormEncodedStringFromDictionary:query withEncoding:encoding]);
}

#endif // ServiceEssentials_DataRequestServicePrivate_h
