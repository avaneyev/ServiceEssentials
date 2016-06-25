//
//  SEDataRequestServiceImplTests.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <XCTest/XCTest.h>
#import "SEDataRequestServiceImpl.h"
#import "SEDataRequestServicePrivate.h"

@interface SEDataRequestServiceImplTests : XCTestCase
@end

@implementation SEDataRequestServiceImplTests

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testDataRequestServiceURLAppendQuery
{
    NSURL *urlWithoutQuery = [NSURL URLWithString:@"https://www.awesomehost.com/api/method"];
    NSURL *urlWithQuery = [NSURL URLWithString:@"https://www.awesomehost.com/api/method?firstParam=1"];

    NSURL *result = [SEDataRequestServiceImpl appendQueryStringToURL:urlWithoutQuery query:@"otherParam=2"];
    XCTAssertEqualObjects([NSURL URLWithString:@"https://www.awesomehost.com/api/method?otherParam=2"], result);
    
    result = [SEDataRequestServiceImpl appendQueryStringToURL:urlWithQuery query:@"thirdParam=xyz"];
    XCTAssertEqualObjects([NSURL URLWithString:@"https://www.awesomehost.com/api/method?firstParam=1&thirdParam=xyz"], result);
}


@end
