//
//  SEPlainTextSerializer.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <ServiceEssentials/SEPlainTextSerializer.h>
#import <ServiceEssentials/SEDataRequestService.h>

@implementation SEPlainTextSerializer

- (NSData *)serializeObject:(id)object mimeType:(NSString *)mimeType error:(NSError *__autoreleasing *)error
{
    if (![object isKindOfClass:[NSString class]])
    {
        if (error) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:nil];
        return nil;
    }
        
    NSStringEncoding encoding = [SEDataSerializer charsetFromMIMEType:mimeType];
    if (encoding == 0)
    {
        if (error) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:nil];
        return nil;
    }
    
    NSString *string = object;
    if (error) *error = nil;
    return [string dataUsingEncoding:encoding];
}

- (BOOL)shouldAppendCharsetToContentType
{
    return YES;
}

- (id)deserializeData:(NSData *)data mimeType:(NSString *)mimeType error:(NSError *__autoreleasing *)error
{
    NSStringEncoding encoding = [SEDataSerializer charsetFromMIMEType:mimeType];
    if (encoding == 0)
    {
        if (error) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:nil];
        return nil;
    }

    NSString *result = [[NSString alloc] initWithData:data encoding:encoding];
    if (result == nil)
    {
        if (error) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:nil];
    }
    else
    {
        if (error) *error = nil;
    }
    return result;
}

@end
