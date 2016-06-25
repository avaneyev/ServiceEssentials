//
//  SEFetchParameters.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <Foundation/Foundation.h>

@interface SEFetchParameters : NSObject

+ (nonnull instancetype)fetchParametersWithPredicate:(nullable NSPredicate *)predicate;
+ (nonnull instancetype)fetchParametersWithPredicate:(nullable NSPredicate *)predicate sort:(nullable NSArray< NSSortDescriptor *> *)sort;
+ (nonnull instancetype)fetchParametersWithPredicate:(nullable NSPredicate *)predicate sort:(nullable NSArray< NSSortDescriptor *> *)sort fetchLimit:(NSUInteger)fetchLimit;

@property (nonatomic, readonly, strong, nullable) NSPredicate *predicate;
@property (nonatomic, readonly, strong, nullable) NSArray< NSSortDescriptor *> *sort;
@property (nonatomic, readonly, assign) NSUInteger fetchLimit;

@end
