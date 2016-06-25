//
//  CancelableTokenTests.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

@import XCTest;
@import OCMock;

#import "SECancellableTokenImpl.h"

@interface SECancelableTokenTests : XCTestCase

@end

@implementation SECancelableTokenTests

- (void)testCancelableTokenCancelsItem
{
    id<SECancellableItemService> service = OCMStrictProtocolMock(@protocol(SECancellableItemService));
    SECancellableTokenImpl *token = [[SECancellableTokenImpl alloc] initWithService:service];
    
    OCMExpect([service cancelItemForToken:token]);
    [token cancel];
    
    OCMVerifyAll((OCMockObject *)service);
}

@end
