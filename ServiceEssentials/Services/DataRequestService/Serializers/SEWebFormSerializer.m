//
//  SEWebFormSerializer.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 AlphaNgen. All rights reserved.
//

#import <ServiceEssentials/SEWebFormSerializer.h>

#import <ServiceEssentials/SEDataRequestService.h>

static inline NSString * PercentEscapedQueryString(NSString *string, CFStringRef exceptCharacters, NSStringEncoding encoding)
{
    static NSString * const QueryStringEscapedCharacters = @":/?&=;+!@#$()',*";

    return (__bridge_transfer  NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (__bridge CFStringRef)string, exceptCharacters, (__bridge CFStringRef)QueryStringEscapedCharacters, CFStringConvertNSStringEncodingToEncoding(encoding));
    
}

static inline NSString * PercentEscapedQueryStringKey(NSString *string, NSStringEncoding encoding)
{
    static NSString * const EscapeStringKeyExceptions = @"[].";
    return PercentEscapedQueryString(string, (__bridge CFStringRef)EscapeStringKeyExceptions, encoding);
}

static inline NSString * PercentEscapedQueryStringValue(NSString *string, NSStringEncoding encoding)
{
    return PercentEscapedQueryString(string, NULL, encoding);
}

static inline void AppendQueryComponent(NSMutableString *mutableString, NSString *encodedPiece)
{
    if (mutableString.length > 0)
    {
        [mutableString appendString:@"&"];
    }
    [mutableString appendString:encodedPiece];
}

@implementation SEWebFormSerializer

#pragma mark - Public interface

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
    if (![object isKindOfClass:[NSDictionary class]])
    {
        if (error) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:@{ NSLocalizedDescriptionKey: @"Object being serialized is invalid" }];
    }
    NSStringEncoding encoding = [SEDataSerializer charsetFromMIMEType:mimeType];
    NSString *resultString = [SEWebFormSerializer webFormEncodedStringFromDictionary:object withEncoding:encoding];
    NSData *result = [resultString dataUsingEncoding:encoding];
    
    if ((result == nil) && (error != nil))
    {
        *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:@{ NSLocalizedDescriptionKey: @"Could not serialize an object using Web Form Encoding" }];
    }
    return result;
}

- (id)deserializeData:(NSData *)data mimeType:(NSString *)mimeType error:(NSError *__autoreleasing *)error
{
    // Not supported, maybe later
    return nil;
}

+ (NSString *)webFormEncodedStringFromDictionary:(NSDictionary *)dictionary withEncoding:(NSStringEncoding)encoding
{
    if (![dictionary isKindOfClass:[NSDictionary class]])
    {
#ifdef DEBUG
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Object being serialized is not a dictionary" userInfo:nil];
#else
        return nil;
#endif
    }
    
    return [self URLEncodedObject:dictionary withKey:nil encoding:encoding];
}

#pragma mark - Private stuff

+ (NSString *)URLEncodedKey: (id) key value: (id) value withEncoding:(NSStringEncoding)stringEncoding
{
    if (!value || [value isEqual:[NSNull null]])
    {
        return PercentEscapedQueryStringKey([key description], stringEncoding);
    }
    else
    {
        return [NSString stringWithFormat:@"%@=%@", PercentEscapedQueryStringKey([key description], stringEncoding), PercentEscapedQueryStringValue([value description], stringEncoding)];
    }
}

+ (NSString *) URLEncodedObject: (id) object withKey: (NSString *) key encoding: (NSStringEncoding) encoding
{
    NSMutableString *mutableString = nil;
    if ([object isKindOfClass:[NSDictionary class]])
    {
        // "key[innerKey]=value&key[otherKey]=otherValue
        return [self URLEncodeDictionary:object withKey:key encoding:encoding];
    }
    else if ([object isKindOfClass:[NSArray class]])
    {
        // key[]=value&key[]=otherValue
        NSArray *array = object;
        NSString *subscriptedKey = [NSString stringWithFormat:@"%@[]", key];
        mutableString = [[NSMutableString alloc] init];
        for (id innerObject in array)
        {
            NSString *encodedObject = [self URLEncodedKey:subscriptedKey value:innerObject withEncoding:encoding];
            AppendQueryComponent(mutableString, encodedObject);
        }
    }
    else if ([object isKindOfClass:[NSSet class]])
    {
        // key=value&key=otherValue
        NSSet *set = object;
        mutableString = [[NSMutableString alloc] init];
        for (id innerObject in set)
        {
            NSString *encodedObject = [self URLEncodedKey:key value:innerObject withEncoding:encoding];
            AppendQueryComponent(mutableString, encodedObject);
        }
    }
    else
    {
        // key=value
        return [self URLEncodedKey:key value:object withEncoding:encoding];
    }
    return [NSString stringWithString:mutableString];
}

+ (NSString *) URLEncodeDictionary: (NSDictionary *) dictionary withKey: (NSString *) key encoding: (NSStringEncoding) encoding
{
    // Follow the same pattern as AFNetworking does:
    // Sort dictionary keys to ensure consistent ordering in query string, which is important when deserializing potentially ambiguous sequences, such as an array of dictionaries
    
    NSArray *allKeys = [dictionary allKeys];
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"description" ascending:YES selector:@selector(caseInsensitiveCompare:)];
    allKeys = [allKeys sortedArrayUsingDescriptors:@[sortDescriptor]];
    NSMutableString *mutableString = [[NSMutableString alloc] init];
    for (id innerKey in allKeys)
    {
        id innerValue = [dictionary objectForKey:innerKey];
        if (innerValue)
        {
            NSString *newKey = key ? [NSString stringWithFormat:@"%@[%@]", key, innerKey] : innerKey;
            NSString *encodedObject = [self URLEncodedObject:innerValue withKey:newKey encoding:encoding];
            AppendQueryComponent(mutableString, encodedObject);
        }
    }
    return [NSString stringWithString:mutableString];
}

@end
