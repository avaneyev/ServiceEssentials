//
//  SEJSONDataSerializer.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <Foundation/Foundation.h>
#import "SEDataSerializer.h"

@interface SEJSONDataSerializer : SEDataSerializer

+ (NSData *)serializeObject:(id)object error:(NSError *__autoreleasing *)error;

@end
