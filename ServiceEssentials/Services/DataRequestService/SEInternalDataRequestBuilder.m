//
//  SEInternalDataRequestBuilder.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import "SEInternalDataRequestBuilder.h"

#import "SETools.h"
#import "SEMultipartRequestContentPart.h"
#import "SEDataSerializer.h"

#define INVALID_BUILDER_PARAM(param) THROW_INVALID_PARAM(param, nil);

@implementation SEInternalDataRequestBuilder
{
    __weak id<SEDataRequestServicePrivate> _dataRequestService;
    
    NSMutableDictionary *_additionalHeaders;
    NSMutableArray *_contentParts;
}

- (instancetype)init
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithDataRequestService:(id<SEDataRequestServicePrivate>)dataRequestService
{
    self = [super init];
    if (self)
    {
        _dataRequestService = dataRequestService;
        _acceptContentType = SEDataRequestAcceptContentTypeJSON;
        _qualityOfService = SEDataRequestQOSDefault;
    }
    return self;
}

#pragma mark - Properties

- (NSDictionary<NSString *,NSString *> *)headers
{
    return [_additionalHeaders copy];
}

- (NSArray<SEMultipartRequestContentPart *> *)contentParts
{
    return _contentParts == nil ? nil : [_contentParts copy];
}

#pragma mark - Builder Interface

- (id<SEDataRequestCustomizer>)POST:(NSString *)path success:(void (^)(id _Nonnull, NSURLResponse * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    return [self requestWithMethod:@"POST" path:path success:success failure:failure completionQueue:completionQueue];
}

- (id<SEDataRequestCustomizer>)PUT:(NSString *)path success:(void (^)(id _Nonnull, NSURLResponse * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    return [self requestWithMethod:@"PUT" path:path success:success failure:failure completionQueue:completionQueue];
}

#pragma mark - Customizer Interface

- (id<SECancellableToken>)submitAsUpload:(BOOL)asUpload
{
    return [_dataRequestService submitRequestWithBuilder:self asUpload:asUpload];
}

- (id<SECancellableToken>)submit
{
    BOOL asUpload = self.contentParts != nil;
    return [self submitAsUpload:asUpload];
}

- (void)setQualityOfService:(SEDataRequestQualityOfService)qualityOfService
{
    SEDataRequestVerifyQOS(qualityOfService);
    
    _qualityOfService = qualityOfService;
}

- (void)setDeserializeClass:(Class)class
{
    if (!SECanDeserializeToClass(class))
    {
        INVALID_BUILDER_PARAM(class)
    }
    
    _deserializeClass = class;
    _acceptContentType = SEDataRequestAcceptContentTypeJSON;
}

- (void)setAcceptRawData
{
    if (_deserializeClass != nil)
    {
        INVALID_BUILDER_PARAM(acceptContentType);
    }
    
    _acceptContentType = SEDataRequestAcceptContentTypeData;
}

- (void)setContentEncoding:(NSString *)encoding
{
    if (_contentParts != nil || [_dataRequestService explicitSerializerForMIMEType:encoding] == nil)
    {
        INVALID_BUILDER_PARAM(encoding);
    }
    
    _contentEncoding = encoding;
}

- (void)setHTTPHeader:(NSString *)header forkey:(NSString *)key
{
    if (header == nil) THROW_INVALID_PARAM(header, nil);
    if (key == nil) THROW_INVALID_PARAM(key, nil);
    
    if (_additionalHeaders == nil)
    {
        _additionalHeaders = [[NSMutableDictionary alloc] initWithCapacity:1];
    }
    [_additionalHeaders setObject:header forKey:key];
}

- (void)setExpectedHTTPCodes:(NSIndexSet *)expectedCodes
{
    if (expectedCodes == nil || expectedCodes.count == 0) THROW_INVALID_PARAM(expectedCodes, nil);
    
    _expectedHTTPCodes = [expectedCodes copy];
}

- (void)setBodyParameters:(NSDictionary<NSString *,id> *)parameters
{
    if (_bodyParameters != nil || _contentParts != nil)
    {
        THROW_INCONSISTENCY(@{ NSLocalizedDescriptionKey: @"Cannot set body paramters at this stage." });
    }

    _bodyParameters = [parameters copy];
}

- (void)setCanSendInBackground:(BOOL)canSendInBackground
{
    _canSendInBackground = @(canSendInBackground);
}

- (BOOL)checkMultipartRequestPossibleOrError: (NSError * _Nullable __autoreleasing *)error
{
    if (_bodyParameters != nil || _contentEncoding != nil)
    {
        NSDictionary *info = @{ NSLocalizedDescriptionKey: @"Cannot add multipart content to a request that has body or custom content type." };
        if (error != nil) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceRequestBuilderFailure userInfo:info];
        return NO;
    }
    return YES;
}

- (BOOL)appendPartWithData:(NSData *)data name:(NSString *)name fileName:(NSString *)fileName mimeType:(NSString *)mimeType error:(NSError * _Nullable __autoreleasing *)error
{
    if (data == nil) THROW_INVALID_PARAM(data, nil);
    if (name == nil) THROW_INVALID_PARAM(name, nil);
    
    if (![self checkMultipartRequestPossibleOrError:error]) return NO;
    
    if (mimeType == nil && fileName == nil) return NO;
    
    if (mimeType == nil)
    {
        mimeType = [SEDataSerializer mimeTypeForFileExtension:fileName.pathExtension];
    }
        
    if (_contentParts == nil) _contentParts = [[NSMutableArray alloc] initWithCapacity:1];
    [_contentParts addObject:[[SEMultipartRequestContentPart alloc] initWithData:data name:name fileName:fileName mimeType:mimeType]];
    
    return YES;
}

- (BOOL)appendPartWithData:(NSData *)data name:(NSString *)name mimeType:(NSString *)mimeType error:(NSError * _Nullable __autoreleasing *)error
{
    return [self appendPartWithData:data name:name fileName:nil mimeType:mimeType error:error];
}

- (BOOL)appendPartWithJSON:(NSDictionary<NSString *,id> *)json name:(NSString *)name error:(NSError * _Nullable __autoreleasing *)error
{
    if (json == nil)
    {
        THROW_INVALID_PARAM(json, nil);
    }
    
    if (![self checkMultipartRequestPossibleOrError:error]) return NO;
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:json options:0 error:error];
    if (jsonData == nil)
    {
        return NO;
    }

    [self appendPartWithData:jsonData name:name fileName:nil mimeType:SEDataRequestServiceContentTypeJSON error:error];
    return YES;
}

- (BOOL)appendPartWithFileURL:(NSURL *)fileUrl name:(NSString *)name error:(NSError * _Nullable __autoreleasing *)error
{
    if (![self checkMultipartRequestPossibleOrError:error]) return NO;
    
    if (![fileUrl isFileURL])
    {
        NSDictionary *info = @{ NSLocalizedDescriptionKey: @"Incorrect file URL." };
        if (error != nil) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceRequestBuilderFailure userInfo:info];
        return NO;
    }
    
    BOOL isDirectory = NO;
    NSString *path = fileUrl.path;
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];
    if (!fileExists || isDirectory)
    {
        NSDictionary *info = @{ NSLocalizedDescriptionKey: @"File does not exist or is a directory." };
        if (error != nil) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceRequestBuilderFailure userInfo:info];
        return NO;
    }
    
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:error];
    NSNumber *length = [fileAttributes objectForKey:NSFileSize];
    if (fileAttributes == nil || length == nil || length.longLongValue == 0)
    {
        NSDictionary *info = @{ NSLocalizedDescriptionKey: @"File attributes cannot be obtained." };
        if (error != nil) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceRequestBuilderFailure userInfo:info];
        return NO;
    }
    
    
    NSString *mimeType = [SEDataSerializer mimeTypeForFileExtension:fileUrl.pathExtension];
    
    if (_contentParts == nil) _contentParts = [[NSMutableArray alloc] initWithCapacity:1];
    NSString *fileName = [fileUrl lastPathComponent];
    [_contentParts addObject:[[SEMultipartRequestContentPart alloc] initWithFileURL:fileUrl length:length.unsignedLongLongValue name:name fileName:fileName mimeType:mimeType]];
    
    return YES;
}

#pragma mark - Private Handling

- (id<SEDataRequestCustomizer>)requestWithMethod:(NSString *)method path:(NSString *)path success:(void (^)(id _Nonnull, NSURLResponse * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure completionQueue:(dispatch_queue_t)completionQueue
{
    if (_method != nil)
    {
        THROW_INCONSISTENCY(nil);
    }
    
    if (path == nil) THROW_INVALID_PARAM(path, nil);
    if (success == nil) THROW_INVALID_PARAM(success, nil);
    
    _method = method;
    _path = path;
    _success = success;
    _failure = failure;
    _completionQueue = completionQueue;
    return self;
}

@end
