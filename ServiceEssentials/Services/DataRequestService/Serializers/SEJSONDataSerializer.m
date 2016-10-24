//
//  SEJSONDataSerializer.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <ServiceEssentials/SEJSONDataSerializer.h>
#import <ServiceEssentials/SEDataRequestService.h>

static NSData *_SerializeJSON(id object, NSError *__autoreleasing *error)
{
    NSError *innerError = nil;
    @try
    {
        NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&innerError];
        if (error) *error = innerError;
        if (innerError)
        {
            return nil;
        }
        else
        {
            return data;
        }
    }
    @catch (NSException *exception)
    {
        if(error) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:@{NSLocalizedDescriptionKey: exception.description, @"innerException": exception}];
        return nil;
    }
}

@implementation SEJSONDataSerializer

- (BOOL)supportsAdditionalParameters
{
    return YES;
}

- (BOOL)shouldAppendCharsetToContentType
{
    return YES;
}

- (NSData *)serializeObject:(id)object mimeType:(NSString *)mimeType error:(NSError *__autoreleasing *)error
{
    return _SerializeJSON(object, error);
}

- (id)deserializeData:(NSData *)data mimeType:(NSString *)mimeType error:(NSError *__autoreleasing *)error
{
    NSError *innerError = nil;
    @try
    {
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&innerError];
        if (innerError)
        {
            if (error) *error = innerError;
            return nil;
        }
        else
        {
            return object;
        }
    }
    @catch (NSException *exception)
    {
        if(error) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:@{NSLocalizedDescriptionKey: exception.description, @"innerException": exception}];
        return nil;
    }
}

#pragma mark - Class method version of the serializer

+ (NSData *)serializeObject:(id)object error:(NSError *__autoreleasing *)error
{
    return _SerializeJSON(object, error);
}

@end
