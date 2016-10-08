//
//  NSArray+JSONExtensions.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <ServiceEssentials/NSArray+SEJSONExtensions.h>
#import <ServiceEssentials/SETools.h>

@implementation NSArray (SEJSONExtensions)

- (BOOL)verifyAllObjectsOfClass:(__unsafe_unretained Class)cls
{
    for (id object in self)
    {
        if (![object isKindOfClass:cls]) return NO;
    }
    return YES;
}

- (NSArray *)parseJSONObjectsWithIndividualParser:(id(^)(NSDictionary *objectJson))parser
{
    NSMutableArray *parsedObjects = [[NSMutableArray alloc] initWithCapacity:self.count];
    BOOL failed = NO;
    for (NSDictionary *object in self)
    {
        if (![object isKindOfClass:[NSDictionary class]])
        {
#ifdef DEBUG
            if (object == nil) THROW_INVALID_PARAM(object, nil);
#endif
            failed = YES;
        }
        else
        {
            id parsedObject = parser(object);
            if (parsedObject != nil) [parsedObjects addObject:parsedObject];
            else
            {
#ifdef DEBUG
                THROW_INVALID_PARAM(parsedObject, nil);
#else
                failed = YES;
                break;
#endif
            }
        }
    }
    
    if (failed) return nil;
    return [parsedObjects copy];
}


@end
