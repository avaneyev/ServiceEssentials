//
//  SEWebFormSerializer.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <ServiceEssentials/SEDataSerializer.h>

@interface SEWebFormSerializer : SEDataSerializer

+ (NSString *) webFormEncodedStringFromDictionary: (NSDictionary *) dictionary withEncoding: (NSStringEncoding) encoding;

@end
