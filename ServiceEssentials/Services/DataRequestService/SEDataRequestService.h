//
//  SEDataRequestService.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#ifndef ServiceEssentials_DataRequestService_h
#define ServiceEssentials_DataRequestService_h

@import Foundation;

#import "SEConstants.h"
#import "SECancellableToken.h"
#import "SEDataRequestJSONDeserializable.h"

extern NSString * _Nonnull const SEDataRequestServiceChangedReachabilityNotification;
extern NSString * _Nonnull const SEDataRequestServiceChangedReachabilityStatusKey;

extern NSInteger const SEDataRequestServiceSerializationFailure;
extern NSInteger const SEDataRequestServiceTrustFailure;
extern NSInteger const SEDataRequestServiceRequestCancelled;
extern NSInteger const SEDataRequestServiceRequestSubmissuionFailure;
extern NSInteger const SEDataRequestServiceRequestBuilderFailure;

extern NSString * _Nonnull const SEDataRequestServiceErrorDeserializedContentKey;

extern NSString * _Nonnull const SEDataRequestServiceContentTypeJSON;
extern NSString * _Nonnull const SEDataRequestServiceContentTypeURLEncode;
extern NSString * _Nonnull const SEDataRequestServiceContentTypePlainText;
extern NSString * _Nonnull const SEDataRequestServiceContentTypeOctetStream;
extern NSString * _Nonnull const SEDataRequestServiceContentTypeTextHTML;

typedef enum
{
    // no pinning
    SEDataRequestCertificatePinningTypeNone = 0,
    // pin by public key
    SEDataRequestCertificatePinningTypePublicKey = 1,
    // pin by certificate
    SEDataRequestCertificatePinningTypeCertificate = 2
#ifdef ALLOWS_TEST_ENVIRONMENTS
    ,
    // accept recoverable failures, such as self-signed certificates.
    // WARNING: while this is useful for testing, this value should not be used in production.
    SEDataRequestCertificatePinningTypeNoneAcceptRecoverableFailure = 4
#endif
} SEDataRequestCertificatePinningType;

typedef enum
{
    SENetworkReachabilityStatusUnknown = 0,
    SENetworkReachabilityStatusUnavailable = 1,
    SENetworkReachabilityStatusReachableLocal = 2,
    SENetworkReachabilityStatusNotReachable = 3,
    SENetworkReachabilityStatusReachableViaWiFi = 4,
    SENetworkReachabilityStatusReachableViaWWAN = 5
} SENetworkReachabilityStatus;

typedef enum
{
    SEDataRequestQOSDefault = QOS_CLASS_UNSPECIFIED,
    SEDataRequestQOSPriorityBackground = QOS_CLASS_BACKGROUND,
    SEDataRequestQOSPriorityLow = QOS_CLASS_UTILITY,
    SEDataRequestQOSPriorityNormal = QOS_CLASS_DEFAULT,
    SEDataRequestQOSPriorityHigh = QOS_CLASS_USER_INITIATED,
    SEDataRequestQOSPriorityInteractive = QOS_CLASS_USER_INTERACTIVE
} SEDataRequestQualityOfService;

@protocol SEDataRequestCustomizer <NSObject>
/** 
 Finalizes the requests and submits it. This method must be invoked in the end of the building to make the request. 
 @param asUpload determines if a request is submitted as upload or as a regular data task.
 @discussion Upload requests can be used in the background. Upload requests are only supported for methods that have body 
 (PUT and POST).
 */
- (nonnull id<SECancellableToken>) submitAsUpload: (BOOL) asUpload;
/** Convenience shorthand method for `submitAsUpload:`. Will determine how to submit based on parameters. */
- (nonnull id<SECancellableToken>) submit;

/** 
 Set request quality of service. If the value is not set or set to SEDataRequestQOSDefault,
 requests are performed with default priority - that is, default request priority 
 and parsing on a service's internal queue.
 */
- (void) setQualityOfService:(SEDataRequestQualityOfService)qualityOfService;

/** Set class to deserialize the data to. Will deserialize from JSON, mutually exclusive with raw data. */
- (void) setDeserializeClass: (nonnull Class) class;
/** Sets accept header to data, mutually exclusive with deserializing to class */
- (void) setAcceptRawData;
/** Set content encoding for data being sent */
- (void) setContentEncoding: (nonnull NSString *) encoding;
/** Sets an HTTP header for the request. Can be called multiple times. */
- (void) setHTTPHeader: (nonnull NSString *) header forkey: (nonnull NSString *) key;
/** Sets expected HTTP codes (as an index set). Defaults to 2xx. */
- (void) setExpectedHTTPCodes: (nonnull NSIndexSet *) expectedCodes;

/** Set the request body parameters. Cannot be combined with multipart. */
- (void) setBodyParameters: (nonnull NSDictionary<NSString *, id> *) parameters;

/** Request can be sent while application is in the background */
- (void) setCanSendInBackground:(BOOL)canSendInBackground;

/** Append a data part for multipart request */
- (BOOL) appendPartWithData: (nonnull NSData *) data name: (nonnull NSString *) name fileName:(nullable NSString *) fileName mimeType: (nullable NSString *) mimeType error: (NSError * __autoreleasing _Nullable * _Nullable) error;
/** Append a data part for multipart request */
- (BOOL) appendPartWithData: (nonnull NSData *) data name: (nonnull NSString *) name mimeType: (nonnull NSString *) mimeType error: (NSError * __autoreleasing _Nullable * _Nullable) error;
/** Append a data part with JSON data. Convenience method for `appendPartWithData:name:mimeType:error` */
- (BOOL) appendPartWithJSON: (nonnull NSDictionary<NSString *, id> *)json name: (nonnull NSString *) name error: (NSError * __autoreleasing _Nullable * _Nullable) error;
/** Append file as a data part for multipart request */
- (BOOL) appendPartWithFileURL: (nonnull NSURL *) fileUrl name: (nonnull NSString *) name error: (NSError * __autoreleasing _Nullable * _Nullable) error;
@end

@protocol SEDataRequestBuilder <NSObject>
- (nonnull id<SEDataRequestCustomizer>) POST: (nonnull NSString *)path success: (nonnull void(^)(id _Nullable data, NSURLResponse * _Nonnull response)) success failure: (nullable void (^)(NSError * _Nonnull error)) failure completionQueue: (nullable dispatch_queue_t) completionQueue;
- (nonnull id<SEDataRequestCustomizer>) PUT: (nonnull NSString *)path success: (nonnull void(^)(id _Nullable data, NSURLResponse * _Nonnull response)) success failure: (nullable void (^)(NSError * _Nonnull error)) failure completionQueue: (nullable dispatch_queue_t) completionQueue;
@end


/**
 Data Request Service is designed to help make secure service requests with a designated host.
 All requests are bases off common URL (typically <protocol://host/[path]>, for example "https://api.mycompany.com/api/data"
 Data requests share the environment, security policy and authorization settings.
 @warning trying to cheat and provide full URL as path so that request goes to a different host or scheme will cause an exception.
 @discussion The use case for Data Request Service is as follows: connecting with own APIs to exchange information including sensible details. Requests may contain authorization details. Secure connection and certificate pinning will be enforced.
 
 Some requests don't return any response for a valid reason.
 For exmaple, HTTP 204 No Data is one of those reasons (may be in response to PUT request)
 So a successful response may contain no data and there is nothing to deserialize

 */
@protocol SEDataRequestService <NSObject>

/**
 Returns <code>YES</code> if host is reachable and <code>NO</code> if not. Simplified representation of the reachability status which may take into account user's preference to only connect over WiFi
 */
- (BOOL) isReachable;

/** 
 Returns current reachability status. 
 If reachability is unavailable, returns <code>NetworkReachabilityStatusUnavailable</code>
 */
- (SENetworkReachabilityStatus) reachabilityStatus;

/**
 Sets authorization header as a form of authentication to use with subsequent requests
 @param authorizationHeader header value to set
 */
- (void) setAuthorizationHeader:(nonnull NSString *) authorizationHeader;

/**
 Clears authorization data (header, cookies if any, etc.)
 */
- (void) clearAuthorization;

/**
 Creates, starts and returns a new GET request
 @param path specifies a relative path to the API
 @param parameters specifies request query parameters if any
 @param success callback invoked on success, JSON object (whatever it is) is passed along
 @param failure callback invoked on failure
 @param completionQueue queue used to invoke a completion callback
 @return request token
 */
- (nonnull id<SECancellableToken>) GET: (nonnull NSString *)path parameters: (nullable NSDictionary <NSString *, id> *)parameters success: (nonnull void(^)(id _Nullable data, NSURLResponse * _Nonnull response)) success failure: (nullable void (^)(NSError * _Nonnull error)) failure completionQueue: (nullable dispatch_queue_t) completionQueue;

/**
 Creates, starts and returns a new GET request with deserialization class
 @param path specifies a relative path to the API
 @param parameters specifies request query parameters if any
 @param class specifies the class to deserialize JSON object to
 @param success callback invoked on success, deserialized object is passed along
 @param failure callback invoked on failure
 @param completionQueue queue used to invoke a completion callback
 @return request token
 */
- (nonnull id<SECancellableToken>) GET: (nonnull NSString *)path parameters: (nullable NSDictionary <NSString *, id> *)parameters deserializeToClass: (nullable Class) class success: (nonnull void(^)(id _Nullable data, NSURLResponse * _Nonnull response)) success failure: (nullable void (^)(NSError * _Nonnull error)) failure completionQueue: (nullable dispatch_queue_t) completionQueue;

/**
 Creates, starts and returns a new POST request
 @param path specifies a relative path to the API
 @param parameters specifies request query parameters if any
 @param success callback invoked on success, JSON object (whatever it is) is passed along
 @param failure callback invoked on failure
 @param completionQueue queue used to invoke a completion callback
 @return request token
 */
- (nonnull id<SECancellableToken>) POST: (nonnull NSString *)path parameters: (nullable NSDictionary <NSString *, id> *)parameters success: (nonnull void(^)(id _Nullable data, NSURLResponse * _Nonnull response)) success failure: (nullable void (^)(NSError * _Nonnull error)) failure completionQueue: (nullable dispatch_queue_t) completionQueue;

/**
 Creates, starts and returns a new POST request
 @param path specifies a relative path to the API
 @param parameters specifies request query parameters if any
 @param encoding specifies content encoding to override (default is JSON). if a serializer cannot be found, exception will be thrown.
 @param success callback invoked on success, JSON object (whatever it is) is passed along
 @param failure callback invoked on failure
 @param completionQueue queue used to invoke a completion callback
 @return request token
 */
- (nonnull id<SECancellableToken>) POST: (nonnull NSString *)path parameters: (nullable NSDictionary <NSString *, id> *)parameters contentEncoding: (nullable NSString *) encoding success: (nonnull void(^)(id _Nullable data, NSURLResponse * _Nonnull response)) success failure: (nullable void (^)(NSError * _Nonnull error)) failure completionQueue: (nullable dispatch_queue_t) completionQueue;

/**
 Creates, starts and returns a new POST request
 @param path specifies a relative path to the API
 @param parameters specifies request query parameters if any
 @param encoding specifies content encoding to override (default is JSON). if a serializer cannot be found, exception will be thrown.
 @param class specifies the class to deserialize JSON object to
 @param success callback invoked on success, JSON object (whatever it is) is passed along
 @param failure callback invoked on failure
 @param completionQueue queue used to invoke a completion callback
 @return request token
 */
- (nonnull id<SECancellableToken>) POST: (nonnull NSString *)path parameters: (nullable NSDictionary <NSString *, id> *)parameters contentEncoding: (nullable NSString *) encoding deserializeToClass: (nullable Class) class success: (nonnull void(^)(id _Nullable data, NSURLResponse * _Nonnull response)) success failure: (nullable void (^)(NSError * _Nonnull error)) failure completionQueue: (nullable dispatch_queue_t) completionQueue;

/**
 Creates, starts and returns a new PUT request
 @param path specifies a relative path to the API
 @param parameters specifies request query parameters if any
 @param success callback invoked on success, JSON object (whatever it is) is passed along
 @param failure callback invoked on failure
 @param completionQueue queue used to invoke a completion callback
 @return request token
 */
- (nonnull id<SECancellableToken>) PUT: (nonnull NSString *)path parameters: (nullable NSDictionary <NSString *, id> *)parameters success: (nonnull void(^)(id _Nullable data, NSURLResponse * _Nonnull response)) success failure: (nullable void (^)(NSError * _Nonnull error)) failure completionQueue: (nullable dispatch_queue_t) completionQueue;

/**
 Creates, starts and returns a new DOWNLOAD request
 @param path specifies a URL to a relative path to the downloadable content
 @param parameters specifies optional request query parameters. if parameters are provided, they will be appended to URL query.
 @param saveAsURL URL of a file to store downloaded contents
 @param success callback invoked on success, does not pass any data since it's in the file
 @param failure callback invoked on failure
 @param progress optional progress callback invoked on download progress
 @param completionQueue queue used to invoke a completion callback
 @return request token
 @discussion Success block will never receive any data, since data is saved as a file. It is provided for callback uniformity.
 */
- (nonnull id<SECancellableToken>) download:(nonnull NSString *)path parameters: (nullable NSDictionary <NSString *, id> *)parameters saveAs:(nonnull NSURL *)saveAsURL success: (nonnull void(^)(id _Nullable data, NSURLResponse * _Nonnull response)) success failure: (nullable void (^)(NSError * _Nonnull error)) failure progress:(nullable void(^)(int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpected))progress completionQueue: (nullable dispatch_queue_t) completionQueue;

/**
 Creates a data request builder which can then be provided with all necessary parameters, such as method, data, callbacks and so on.
 */
- (nonnull id<SEDataRequestBuilder>) createRequestBuilder;

/**
 A function to use when a client needs to validate a challenge according to common policies.
 It may be helpful for the stream, for example, to coordinate the common security policy and certificate/key pinning
 */
- (BOOL) validateSecurityChallenge: (nonnull NSURLAuthenticationChallenge *) challenge;
@end

/**
 Unsafe URL Request Service is a Data Request Service counterpart which has a slightly different use case.
 While Data Request Service allows a wide variety of request types, it restricts requests to a certain host. Unsafe URL Request service removes that limitation, allowing requests to other hosts by providing full URLs, but handles the requests differently and limits available types of requests.
 Security information (tokens, cookies) will not be passed with these requests.
 @discussion the use case for this service is to request information that resides outside of main API and is not user-sensitive. For example, avatar images, third-party images, CDN content and so on.
 */
@protocol SEUnsafeURLRequestService <NSObject>
/**
 Creates, starts and returns a new GET request
 @param url specifies a URL to request data from
 @param parameters specifies optional request query parameters. if parameters are provided, they will be appended to URL query.
 @param success callback invoked on success, JSON object (whatever it is) is passed along
 @param failure callback invoked on failure
 @param completionQueue queue used to invoke a completion callback
 @return request token
 */
- (nonnull id<SECancellableToken>) URLGET: (nonnull NSURL *)url parameters: (nullable NSDictionary <NSString *, id> *)parameters success: (nonnull void(^)(id _Nullable data, NSURLResponse * _Nonnull response)) success failure: (nullable void (^)(NSError * _Nonnull error)) failure completionQueue: (nullable dispatch_queue_t) completionQueue;

/**
 Creates, starts and returns a new DOWNLOAD request
 @param url specifies a URL to request data from
 @param parameters specifies optional request query parameters. if parameters are provided, they will be appended to URL query.
 @param saveAsURL URL of a file to store downloaded contents
 @param success callback invoked on success, does not pass any data since it's in the file
 @param failure callback invoked on failure
 @param progress optional progress callback invoked on download progress
 @param completionQueue queue used to invoke a completion callback
 @return request token
 @discussion Success block will never receive any data, since data is saved as a file. It is provided for callback uniformity.
 */
- (nonnull id<SECancellableToken>) URLDownload: (nonnull NSURL *)url parameters: (nullable NSDictionary <NSString *, id> *)parameters saveAs:(nonnull NSURL *)saveAsURL success: (nonnull void(^)(id _Nullable data, NSURLResponse * _Nonnull response)) success failure: (nullable void (^)(NSError * _Nonnull error)) failure progress:(nullable void(^)(int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpected))progress completionQueue: (nullable dispatch_queue_t) completionQueue;

@end

/**
 Preparation delegate is an optional object that is queried during request preparation
 and can provide additional headers and/or query parameters.
 
 WARNING: data request service will keep a strong reference to the delegate.
 That is done to avoid accidental deallocations and hard to find bugs where requests 
 don't match the expectation.
 If na application needs to make the reference weak, it may use a weak proxy,
 like `SEServiceWeakProxy` or similar.
 
 Delegate is not queried for unsafe requests, since those are considered fully composed 
 to only get/download a URL.
 
 The order in which headers and query parameters are applied is from more special to more generic:
 - First, URL query parameters and headers provided to the builder are applied.
 - Next, headers and parameters (if any) provided by the delegate are applied.
 - Finally, generic service-level parameters and headers (such as those set through setSecurityHeader:) are applied.
 The motivation is to provide consistency and avoid hard to find bugs caused by random collisions.
 Generic policy cannot be overridden and supercedes specific settings.
 
 The delegate mothods can be used to add tracking, dynamic authorization and lots of other things 
 in a uniform way rather than having to add them for each request.
 */
@protocol SEDataRequestPreparationDelegate <NSObject>

/**
 Queries a delegate for additional headers that should be added to a request with URL and method.
 @param dataRequestService data request service sending a request.
 @param method request method, such as `POST` or `GET`.`
 @param url URL being requested.
 @return a dictionary of headers (name-value pairs) that should be added to the request.
 */
- (NSDictionary<NSString *, NSString *>)dataRequestService:(nonnull id<SEDataRequestService>)dataRequestService additionalHeadersForRequestMethod:(nonnull NSString *)method URL:(nonnull NSURL *)url;

/**
 Queries a delegate for additional parameters that should be added to a request with URL and method.
 For GET and HEAD requests, additional parameters will be appended as part of the query.
 For POST, they will be a part of the body if it's JSON, otherwise they will be a part of the query.
 @param dataRequestService data request service sending a request.
 @param method request method, such as `POST` or `GET`.`
 @param url URL being requested.
 @return a dictionary of headers (name-value pairs) that should be added to the request.
 */
- (NSDictionary<NSString *, id>)dataRequestService:(nonnull id<SEDataRequestService>)dataRequestService additionalParametersForRequestMethod:(nonnull NSString *)method URL:(nonnull NSURL *)url;

@end

#endif
