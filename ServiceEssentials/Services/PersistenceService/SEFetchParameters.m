//
//  SEFetchParameters.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <ServiceEssentials/SEFetchParameters.h>

@implementation SEFetchParameters

- (instancetype)init
{
    return [self initWihPredicate:nil sort:nil fetchLimit:0];
}

- (instancetype)initWihPredicate:(NSPredicate *)predicate sort:(NSArray<NSSortDescriptor *> *)sort fetchLimit:(NSUInteger)fetchLimit
{
    self = [super init];
    if (self)
    {
        _predicate = [predicate copy];
        _sort = [sort copy];
        _fetchLimit = fetchLimit;
    }
    return self;
}

+ (instancetype)fetchParametersWithPredicate:(NSPredicate *)predicate
{
    return [[SEFetchParameters alloc] initWihPredicate:predicate sort:nil fetchLimit:0];
}

+ (instancetype)fetchParametersWithPredicate:(NSPredicate *)predicate sort:(NSArray<NSSortDescriptor *> *)sort
{
    return [[SEFetchParameters alloc] initWihPredicate:predicate sort:sort fetchLimit:0];
}

+ (instancetype)fetchParametersWithPredicate:(NSPredicate *)predicate sort:(NSArray<NSSortDescriptor *> *)sort fetchLimit:(NSUInteger)fetchLimit
{
    return [[SEFetchParameters alloc] initWihPredicate:predicate sort:sort fetchLimit:fetchLimit];
}

@end
