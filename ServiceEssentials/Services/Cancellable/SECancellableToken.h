//
//  SECancellableToken.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#ifndef ServiceEssentials_CancellableToken_h
#define ServiceEssentials_CancellableToken_h

@protocol SECancellableItemService;

@protocol SECancellableToken <NSObject, NSCopying>
/** Initializes the token */
- (instancetype) initWithService: (id<SECancellableItemService>) service;
/** Cancels the operation for which the token was returned */
- (void) cancel;
@end

@protocol SECancellableItemService <NSObject>
- (void) cancelItemForToken: (id<SECancellableToken>) token;
@end

#endif
