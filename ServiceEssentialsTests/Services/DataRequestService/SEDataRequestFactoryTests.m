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
#import <ServiceEssentials/SEJSONDataSerializer.h>

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

- (void)_testRequestFactoryCreateRequestWithoutBodyNoDelegateWithMethod:(NSString *)method
{
    NSString *const path = @"some-path";
    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:method baseURL:_baseURL path:path body:nil mimeType:nil error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    XCTAssertEqualObjects(request.URL, [NSURL URLWithString:path relativeToURL:_baseURL]);
    XCTAssertEqualObjects(request.HTTPMethod, method);
    XCTAssertNil(request.HTTPBody);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8"
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
}

- (void)testRequestFactoryCreateGETRequestWithoutBodyNoDelegate
{
    [self _testRequestFactoryCreateRequestWithoutBodyNoDelegateWithMethod:MethodGET];
}

- (void)testRequestFactoryCreatePOSTRequestWithoutBodyNoDelegate
{
    [self _testRequestFactoryCreateRequestWithoutBodyNoDelegateWithMethod:MethodPOST];
}

- (void)testRequestFactoryCreatePUTRequestWithoutBodyNoDelegate
{
    [self _testRequestFactoryCreateRequestWithoutBodyNoDelegateWithMethod:MethodPUT];
}

- (void)testRequestFactoryCreateHEADRequestWithoutBodyNoDelegate
{
    [self _testRequestFactoryCreateRequestWithoutBodyNoDelegateWithMethod:MethodHEAD];
}

- (void)_testRequestFactoryCreateRequestConvertsBodyToURLQueryWithMethod:(NSString *)method
{
    NSString *const path = @"other-path";
    NSDictionary *const parameters = @{ @"first" : @"value", @"second" : @2 };
    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:method baseURL:_baseURL path:path body:parameters mimeType:nil error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:@"other-path?first=value&second=2" relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, method);
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
    [self _testRequestFactoryCreateRequestConvertsBodyToURLQueryWithMethod:MethodGET];
}

- (void)testRequestFactoryCreateHEADRequestConvertsBodyToURLQuery
{
    [self _testRequestFactoryCreateRequestConvertsBodyToURLQueryWithMethod:MethodHEAD];
}

- (void)_testRequestFactoryCreateRequestSerializesBodyDefaultMimeTypeWithMethod:(NSString *)method
{
    NSString *const path = @"different/path";
    NSDictionary *const parameters = @{ @"first" : @"value", @"second" : @2 };
    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:method baseURL:_baseURL path:path body:parameters mimeType:nil error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, method);
    XCTAssertEqualObjects(request.HTTPBody, [SEJSONDataSerializer serializeObject:parameters error:nil]);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              @"Content-Type" : @"application/json; charset=utf-8"
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
}

- (void)testRequestFactoryCreatePOSTRequestSerializesBodyDefaultMimeType
{
    [self _testRequestFactoryCreateRequestSerializesBodyDefaultMimeTypeWithMethod:MethodPOST];
}

- (void)testRequestFactoryCreatePUTRequestSerializesBodyDefaultMimeType
{
    [self _testRequestFactoryCreateRequestSerializesBodyDefaultMimeTypeWithMethod:MethodPUT];
}

- (void)_testRequestFactoryCreateRequestSerializesBodyExplicitMimeTypeWithMethod:(NSString *)method
{
    NSString *const path = @"explicit/path";
    NSString *const mimeType = @"unit/test";
    NSDictionary *const parameters = @{ @"first" : @"value", @"second" : @2 };
    NSData *mockData = [@"some data" dataUsingEncoding:NSUTF8StringEncoding];
    
    OCMockObject *serializerMock = [OCMockObject mockForClass:[SEDataSerializer class]];
    [[[_serviceMock stub] andReturn:serializerMock] explicitSerializerForMIMEType:mimeType];
    [[[serializerMock expect] andReturn:mockData] serializeObject:parameters mimeType:mimeType error:[OCMArg anyObjectRef]];
    
    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];
    
    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:method baseURL:_baseURL path:path body:parameters mimeType:mimeType error:&error];
    
    XCTAssertNil(error);
    XCTAssertNotNil(request);
    
    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, method);
    XCTAssertEqualObjects(request.HTTPBody, mockData);
    
    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              @"Content-Type" : @"unit/test; charset=utf-8"
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);
    
    [self veriyAllMocks];
    [serializerMock verify];
}

- (void)testRequestFactoryCreatePOSTRequestSerializesBodyExplicitMimeType
{
    [self _testRequestFactoryCreateRequestSerializesBodyExplicitMimeTypeWithMethod:MethodPOST];
}

- (void)testRequestFactoryCreatePUTRequestSerializesBodyExplicitMimeType
{
    [self _testRequestFactoryCreateRequestSerializesBodyExplicitMimeTypeWithMethod:MethodPUT];
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
