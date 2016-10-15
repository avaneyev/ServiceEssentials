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
#import "SEInternalDataRequestBuilder.h"

static NSString *const MethodGET = @"GET";
static NSString *const MethodPOST = @"POST";
static NSString *const MethodPUT = @"PUT";
static NSString *const MethodHEAD = @"HEAD";


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
    [[[_serviceMock stub] andReturnValue:@(NSUTF8StringEncoding)] stringEncoding];
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

- (void)veriyAllMocks
{
    [_serviceMock verify];
    [_preparationDelegateMock verify];
}

- (void)testRequestFactoryThrowsOnUnsafeFactoryCreatingRequestsRequiringSecure
{
    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:NO userAgent:_userAgentString requestPreparationDelegate:nil];
    
    NSError *error = nil;
    XCTAssertThrows([factory createRequestWithMethod:@"GET" baseURL:_baseURL path:@"my_path/method" body:nil mimeType:nil error:&error]);

    XCTAssertThrows([factory createDownloadRequestWithBaseURL:_baseURL path:@"path" body:nil error:&error]);

    SEInternalDataRequestBuilder *builder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:_serviceMock];
    XCTAssertThrows([factory createRequestWithBuilder:builder baseURL:_baseURL error:&error]);

    XCTAssertThrows([factory createMultipartRequestWithBuilder:builder baseURL:_baseURL boundary:@"boundary" error:&error]);

    [self veriyAllMocks];
}

- (void)testRequestFactoryThrowsOnUnsafeFactoryCreatingRequestsRequiringUnsafe
{
    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:_preparationDelegateMock];

    NSError *error = nil;
    XCTAssertThrows([factory createUnsafeRequestWithMethod:@"GET" URL:_baseURL parameters:nil mimeType:nil error:&error]);

    [self veriyAllMocks];
}

- (void)testRequestFactoryCreateRequestWithoutBodyNoDelegate
{
    NSString *const path = @"some-path";
    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:MethodGET baseURL:_baseURL path:path body:nil mimeType:nil error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    XCTAssertEqualObjects(request.URL, [NSURL URLWithString:path relativeToURL:_baseURL]);
    XCTAssertEqualObjects(request.HTTPMethod, MethodGET);
    XCTAssertNil(request.HTTPBody);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8"
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
}

- (void)testRequestFactoryCreateGETRequestConvertsBodyToURLQuery
{
    NSString *const path = @"other-path";
    NSDictionary *const parameters = @{ @"first" : @"value", @"second" : @2 };
    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:MethodGET baseURL:_baseURL path:path body:parameters mimeType:nil error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:@"other-path?first=value&second=2" relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodGET);
    XCTAssertNil(request.HTTPBody);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8"
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
}

- (void)testRequestFactoryCreateUnsafeRequestWithoutBody
{
    NSURL *url = [_baseURL URLByAppendingPathComponent:@"some-other-path"];
    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:NO userAgent:_userAgentString requestPreparationDelegate:nil];

    NSError *error = nil;
    NSURLRequest *request = [factory createUnsafeRequestWithMethod:MethodGET URL:url parameters:nil mimeType:nil error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    XCTAssertEqualObjects(request.URL, url);
    XCTAssertEqualObjects(request.HTTPMethod, MethodGET);
    XCTAssertNil(request.HTTPBody);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
}


@end
