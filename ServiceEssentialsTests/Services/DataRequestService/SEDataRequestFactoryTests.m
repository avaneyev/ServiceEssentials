//
//  SEDataRequestFactoryTests.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "SEDataRequestFactory.h"

@interface SEDataRequestFactoryTests : XCTestCase

@end

@implementation SEDataRequestFactoryTests
{
    OCMockObject<SEDataRequestServicePrivate> *_serviceMock;
    OCMockObject<SEDataRequestPreparationDelegate> *_preparationDelegateMock;
    
    NSString *_userAgentString;
    NSURL *_baseURL;
}

- (void)setUp
{
    [super setUp];
    
    _serviceMock = [OCMockObject mockForProtocol:@protocol(SEDataRequestServicePrivate)];
    _preparationDelegateMock = [OCMockObject mockForProtocol:@protocol(SEDataRequestPreparationDelegate)];
    _userAgentString = @"Mock user agent";
    _baseURL = [NSURL URLWithString:@"https://service.essentials.com"];
}

- (void)tearDown
{
    [super tearDown];
    
    _serviceMock = nil;
    _preparationDelegateMock = nil;
}

- (void)testRequestFactoryThrowsOnUnsafeFactoryCreatingSimpleRequest
{
    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:_preparationDelegateMock];
    
    NSError *error = nil;
    XCTAssertThrows([factory createRequestWithMethod:@"GET" baseURL:_baseURL path:@"my_path/method" body:nil mimeType:nil error:&error]);
}

@end
