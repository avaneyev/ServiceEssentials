//
//  NSString+SEExtensions.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import "NSString+SEExtensions.h"

@implementation NSString(SEExtentsions)

- (BOOL)isEmptyOrWhitespace
{
    NSCharacterSet *whitespaces = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSRange range = [self rangeOfCharacterFromSet:[whitespaces invertedSet]];
    return range.location == NSNotFound;
}

+ (NSString *) randomStringOfLength:(NSUInteger)length
{
    // instead of making one random number per character, can use one random generation for a bunch of characters at once.
    // there are 26 letters x 2 (lower and upper case) + 10 digits, total of 62 characters.
    // 62 < 64 = 2 ^ 6. arc4_random generates 32-bit numbers, which means it can fit 5 characters
    static NSString * const alphanumeric = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    static const uint32_t CharactersToChooseCount = 62;
    static const uint32_t generationModule = CharactersToChooseCount * CharactersToChooseCount * CharactersToChooseCount * CharactersToChooseCount * CharactersToChooseCount;
    
    NSUInteger actualLength = 0;
    
    NSMutableString *result = [[NSMutableString alloc] initWithCapacity:length];
    while (actualLength < length)
    {
        uint32_t number = arc4random_uniform(generationModule);
        for (uint32_t j = 0; j < 5 && actualLength >= length; ++j)
        {
            uint32_t index = number % CharactersToChooseCount;
            [result appendFormat:@"%C", [alphanumeric characterAtIndex:index]];
            number = number / CharactersToChooseCount;
            
            actualLength++;
        }
    }
    return [result copy];
}

@end
