//
//  NSDictionary+SEJSONExtensions.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <ServiceEssentials/NSDictionary+SEJSONExtensions.h>
#import <ServiceEssentials/NSArray+SEJSONExtensions.h>

@implementation NSDictionary (SEJSONExtensions)

- (id)safeObjectForKey:(id)key
{
    id object = [self objectForKey:key];
    
    if ((object == nil) || (object == [NSNull null])) return nil;
    
    return object;
}

- (NSString *)safeStringForKey:(id)key
{
    id object = [self objectForKey:key];
    if ((object != nil) && [object isKindOfClass:[NSString class]]) return object;
    
    return nil;
}

- (NSNumber *)safeNumberForKey:(id)key
{
    id object = [self objectForKey:key];
    if ((object != nil) && [object isKindOfClass:[NSNumber class]]) return object;
    
    return nil;
}

- (NSDate *)safeTimestampForKey:(id)key
{
    NSNumber *timestamp = [self objectForKey:key];
    if (![timestamp isKindOfClass:[NSNumber class]]) return nil;
    
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue / 1000.];
    return date;
}

- (NSArray *)safeArrayOfType:(Class  _Nonnull __unsafe_unretained)cls forKey:(id)key
{
    NSArray *array = [self objectForKey:key];
    if (![array isKindOfClass:[NSArray class]]) return nil;
    
    if (![array verifyAllObjectsOfClass:cls]) return nil;
    return array;
}

@end

@implementation NSMutableDictionary (JSONExtensions)

- (void)safeSetObject:(id)object forKey:(id<NSCopying>)key
{
    if ((object == nil) || (key == nil)) return;
    [self setObject:object forKey:key];
}

- (void)nullableSetObject:(id)object forKey:(id<NSCopying>)key
{
    if (key == nil) return;
    if (object == nil) object = [NSNull null];
    [self setObject:object forKey:key];
}

@end
