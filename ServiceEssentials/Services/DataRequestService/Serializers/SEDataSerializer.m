//
//  SEDefaultDataSerializer.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import "SEDataSerializer.h"

@import MobileCoreServices;

#import "SEDataRequestService.h"

@implementation SEDataSerializer

- (NSData *)serializeObject:(id)object mimeType:(NSString *)mimeType error:(NSError *__autoreleasing *)error
{
    if ([object isKindOfClass:[NSData class]])
    {
        if (error) *error = nil;
        return object;
    }
    else
    {
        if (error) *error = [NSError errorWithDomain:SEErrorDomain code:SEDataRequestServiceSerializationFailure userInfo:nil];
        return nil;
    }
}

- (id)deserializeData:(NSData *)data mimeType:(NSString *)mimeType error:(NSError *__autoreleasing *)error
{
    return data;
}

#pragma mark - Static helpers

+ (NSStringEncoding)charsetFromMIMEType:(NSString *)mimeType
{
    NSRange range = [mimeType rangeOfString:@";"];
    NSStringEncoding result = NSUTF8StringEncoding;
    if (range.location != NSNotFound)
    {
        NSString *parameters = [mimeType substringFromIndex:range.location + 1];
        NSArray *splitParameters = [parameters componentsSeparatedByString:@";"];
        for (NSString *parameter in splitParameters)
        {
            NSStringEncoding encodingFromParameter = [self encodingFromParameter:parameter];
            if (encodingFromParameter != 0)
            {
                result = encodingFromParameter;
                break;
            }
        }
    }
    return result;
}

+ (NSString *) mimeTypeForFileExtension: (NSString *) extension
{
    NSString *mimeType = nil;
    if (extension == nil || extension.length == 0)
    {
        mimeType = SEDataRequestServiceContentTypeOctetStream;
    }
    else
    {
        CFStringRef identifier = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)extension, NULL);
        if (identifier != NULL)
        {
            mimeType = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass(identifier, kUTTagClassMIMEType);
            CFRelease(identifier);
        }
        
        if (mimeType == nil) mimeType = SEDataRequestServiceContentTypeOctetStream;
    }
    
    return mimeType;
}

/** Function attempts to extract encoding from parameter.
 A parameter should be in a form 'charset=<encoding>'
 @return returns 0 if encoding was not found, and an encoding value otherwise
 */
+ (NSStringEncoding) encodingFromParameter: (NSString *) parameter
{
    static dispatch_once_t onceToken;
    static NSDictionary *knownCharsetTypes = nil;
    NSCharacterSet *whitespaces = [NSCharacterSet whitespaceCharacterSet];
    NSScanner *scanner = [[NSScanner alloc] initWithString:parameter];
    // skip any whitespaces that there may be
    [scanner scanCharactersFromSet:whitespaces intoString:nil];
    
    // scan the first word that should be 'charset'
    if (![scanner scanString:@"charset" intoString:nil]) return 0;

    // skip any whitespaces that there may be
    [scanner scanCharactersFromSet:whitespaces intoString:nil];
    
    // scan '=' sign
    if (![scanner scanString:@"=" intoString:nil]) return 0;
    
    // skip any whitespaces that there may be
    [scanner scanCharactersFromSet:whitespaces intoString:nil];
    
    // now scan the charset value
    NSString *charsetValue = nil;
    if (![scanner scanUpToCharactersFromSet:whitespaces intoString:&charsetValue]) return 0;
    if (charsetValue.length == 0) return 0;
    
    dispatch_once(&onceToken, ^{
        NSNumber *ascii = @(NSASCIIStringEncoding);
        NSNumber *latin = @(NSISOLatin1StringEncoding);
        knownCharsetTypes = @{
                              // Unicodes
                              @"utf-8"    : @(NSUTF8StringEncoding),
                              @"utf-16"   : @(NSUTF16StringEncoding),
                              @"utf-16be" : @(NSUTF16BigEndianStringEncoding),
                              @"utf-16le" : @(NSUTF16LittleEndianStringEncoding),
                              @"utf-32"   : @(NSUTF32StringEncoding),
                              @"utf-32be" : @(NSUTF32BigEndianStringEncoding),
                              @"utf-32le" : @(NSUTF32LittleEndianStringEncoding),
                              
                              // ASCII
                              @"us-ascii" : ascii,
                              @"iso-ir-6" : ascii,
                              @"iso646-us": ascii,
                              @"us"       : ascii,
                              
                              // Latin1
                              @"iso-ir-100" : latin,
                              @"latin1"     : latin,
                              @"l1"         : latin,
                              @"iso-8859-1" : latin,
                              @"iso_8859-1" : latin
                              };
    });
    
    charsetValue = [charsetValue lowercaseString];
    NSNumber *charsetType = [knownCharsetTypes objectForKey:charsetValue];
    if (charsetType == nil) return 0;
    return charsetType.integerValue;
}

@end
