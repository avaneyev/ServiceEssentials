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

#pragma mark - Safety Checks

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

- (void)testRequestFactoryThrowsOnUnsafeFactoryRequiringNoDelegate
{
    XCTAssertThrows([[SEDataRequestFactory alloc] initWithService:_serviceMock secure:NO userAgent:_userAgentString requestPreparationDelegate:_preparationDelegateMock]);
    [self veriyAllMocks];
}

#pragma mark - Simple request factory

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

- (void)_testRequestFactoryCreateRequestSerializesBodyExplicitMimeTypeWithMethod:(NSString *)method appendsCharset:(BOOL)appendsCharset
{
    NSString *const path = @"explicit/path";
    NSString *const mimeType = @"unit/test";
    NSDictionary *const parameters = @{ @"first" : @"value", @"second" : @2 };
    NSData *mockData = [@"some data" dataUsingEncoding:NSUTF8StringEncoding];
    
    OCMockObject *serializerMock = [OCMockObject mockForClass:[SEDataSerializer class]];
    [[[_serviceMock stub] andReturn:serializerMock] explicitSerializerForMIMEType:mimeType];
    
    [[[serializerMock stub] andReturnValue:@(appendsCharset)] shouldAppendCharsetToContentType];
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
    
    NSString *expectedContentType = appendsCharset ? @"unit/test; charset=utf-8" : mimeType;
    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              @"Content-Type" : expectedContentType
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);
    
    [self veriyAllMocks];
    [serializerMock verify];
}

- (void)testRequestFactoryCreatePOSTRequestSerializesBodyExplicitMimeType
{
    [self _testRequestFactoryCreateRequestSerializesBodyExplicitMimeTypeWithMethod:MethodPOST appendsCharset:YES];
}

- (void)testRequestFactoryCreatePUTRequestSerializesBodyExplicitMimeType
{
    [self _testRequestFactoryCreateRequestSerializesBodyExplicitMimeTypeWithMethod:MethodPUT appendsCharset:YES];
}

- (void)testRequestFactoryCreatePOSTRequestSerializesBodyExplicitMimeTypeSerializerDoesNotAppendCharset
{
    [self _testRequestFactoryCreateRequestSerializesBodyExplicitMimeTypeWithMethod:MethodPOST appendsCharset:NO];
}

- (void)testRequestFactoryCreatePOSTRequestRawDataExplicitMIMETypeAllowed
{
    NSString *const path = @"explicit/path";
    NSString *const mimeType = @"unit/test";
    NSData *mockData = [@"some data" dataUsingEncoding:NSUTF8StringEncoding];
    
    [[[_serviceMock stub] andReturn:nil] explicitSerializerForMIMEType:mimeType];
    
    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];
    
    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:MethodPOST baseURL:_baseURL path:path body:mockData mimeType:mimeType error:&error];
    
    XCTAssertNil(error);
    XCTAssertNotNil(request);
    
    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodPOST);
    XCTAssertEqualObjects(request.HTTPBody, mockData);
    
    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              @"Content-Type" : mimeType
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);
    
    [self veriyAllMocks];
}

- (void)testRequestFactoryCreatePOSTRequestRawDataExplicitMIMETypeHasSerializerForItButUsedAsRaw
{
    NSString *const path = @"explicit/path";
    NSString *const mimeType = @"unit/test";
    NSData *mockData = [@"some data" dataUsingEncoding:NSUTF8StringEncoding];

    OCMockObject *serializerMock = [OCMockObject mockForClass:[SEDataSerializer class]];
    [[[_serviceMock stub] andReturn:serializerMock] explicitSerializerForMIMEType:mimeType];
    
    [[[serializerMock stub] andReturnValue:@(NO)] shouldAppendCharsetToContentType];
    [[serializerMock reject]  serializeObject:mockData mimeType:mimeType error:[OCMArg anyObjectRef]];

    [[[_serviceMock stub] andReturn:serializerMock] explicitSerializerForMIMEType:mimeType];
    
    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];
    
    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:MethodPOST baseURL:_baseURL path:path body:mockData mimeType:mimeType error:&error];
    
    XCTAssertNil(error);
    XCTAssertNotNil(request);
    
    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodPOST);
    XCTAssertEqualObjects(request.HTTPBody, mockData);
    
    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              @"Content-Type" : mimeType
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);
    
    [self veriyAllMocks];
    [serializerMock verify];
}

- (void)testRequestFactoryCreatePOSTRequestRawDataWithoutMIMETypeSentAsOctetStream
{
    NSString *const path = @"explicit/path";
    NSData *mockData = [@"some data" dataUsingEncoding:NSUTF8StringEncoding];
    
    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];
    
    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:MethodPOST baseURL:_baseURL path:path body:mockData mimeType:nil error:&error];
    
    XCTAssertNil(error);
    XCTAssertNotNil(request);
    
    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodPOST);
    XCTAssertEqualObjects(request.HTTPBody, mockData);
    
    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              @"Content-Type" : SEDataRequestServiceContentTypeOctetStream
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);
    
    [self veriyAllMocks];
}

- (void)testRequestFactoryCreatePOSTRequestUnrecognizedDataTypeProducesError
{
    NSString *const path = @"explicit/path";
    NSURL *unrecognizedData = [NSURL URLWithString:@"https://www.github.com"];
    XCTAssertNotNil(unrecognizedData);
    
    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];
    
    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:MethodPOST baseURL:_baseURL path:path body:unrecognizedData mimeType:nil error:&error];
    
    XCTAssertNil(request);
    XCTAssertNotNil(error);

    [self veriyAllMocks];
}

- (void)testRequestFactoryWithDelegateCreateGETRequestIncludesParameters
{
    NSString *const path = @"yet/another/path";
    NSDictionary *const requestParameters = @{ @"request" : @"request-value" };
    NSDictionary *const delegateParameters = @{ @"additional" : @"some-value" };

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:_preparationDelegateMock];

    [[[_preparationDelegateMock expect] andReturn:delegateParameters] dataRequestService:(id)_serviceMock additionalParametersForRequestMethod:MethodGET path:path];
    [[[_preparationDelegateMock expect] andReturn:nil] dataRequestService:(id)_serviceMock additionalHeadersForRequestMethod:MethodGET path:path];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:MethodGET baseURL:_baseURL path:path body:requestParameters mimeType:nil error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@?additional=some-value&request=request-value", path] relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodGET);
    XCTAssertNil(request.HTTPBody);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
}

- (void)testRequestFactoryWithDelegateCreateGETRequestIncludesParametersAndHeaders
{
    NSString *const path = @"yet/another/path";
    NSDictionary *const requestParameters = @{ @"request" : @"request-value" };
    NSDictionary *const delegateParameters = @{ @"additional" : @"some-value" };
    NSDictionary *const delegateHeaders = @{ @"X-Super-Header" : @"my awesome value" };

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:_preparationDelegateMock];

    [[[_preparationDelegateMock expect] andReturn:delegateParameters] dataRequestService:(id)_serviceMock additionalParametersForRequestMethod:MethodGET path:path];
    [[[_preparationDelegateMock expect] andReturn:delegateHeaders] dataRequestService:(id)_serviceMock additionalHeadersForRequestMethod:MethodGET path:path];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:MethodGET baseURL:_baseURL path:path body:requestParameters mimeType:nil error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@?additional=some-value&request=request-value", path] relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodGET);
    XCTAssertNil(request.HTTPBody);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              @"X-Super-Header": @"my awesome value"
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
}

- (void)testRequestFactoryWithDelegateCreateGETRequestIncludesAuthorizationHeader
{
    NSString *const path = @"yet/another/path";
    NSDictionary *const requestParameters = @{ @"request" : @"request-value" };

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];
    factory.authorizationHeader = @"Token: my-awesome-token";

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:MethodGET baseURL:_baseURL path:path body:requestParameters mimeType:nil error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@?request=request-value", path] relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodGET);
    XCTAssertNil(request.HTTPBody);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Authorization" : @"Token: my-awesome-token",
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
}

- (void)testRequestFactoryWithDelegateCreateGETRequestIncludesParametersAndHeadersThrowOnCollisions
{
    NSString *const path = @"yet/another/path";
    NSDictionary *const requestParameters = @{ @"request" : @"request-value" };
    NSDictionary *const delegateParameters = @{
                                               @"additional" : @"some-value",
                                               @"request" : @"super-value"
                                               };
    NSDictionary *const delegateHeaders = @{
                                            @"X-Super-Header" : @"my awesome value",
                                            @"Accept" : @"I accept whatever"
                                            };

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:_preparationDelegateMock];

    [[[_preparationDelegateMock expect] andReturn:delegateParameters] dataRequestService:(id)_serviceMock additionalParametersForRequestMethod:MethodGET path:path];
    [[[_preparationDelegateMock expect] andReturn:delegateHeaders] dataRequestService:(id)_serviceMock additionalHeadersForRequestMethod:MethodGET path:path];

    NSError *error = nil;
    XCTAssertThrows([factory createRequestWithMethod:MethodGET baseURL:_baseURL path:path body:requestParameters mimeType:nil error:&error]);

    [self veriyAllMocks];
}

- (void)testRequestFactoryWithDelegateCreatePOSTRequestIncludesParametersIfSerializerAllows
{
    NSString *const path = @"yet/another/path";
    NSString *const mimeType = @"unit/test";
    NSDictionary *const requestParameters = @{ @"request" : @"request-value" };
    NSDictionary *const delegateParameters = @{ @"additional" : @"some-value" };
    NSDictionary *const delegateHeaders = @{ @"X-Super-Header" : @"my awesome value" };
    NSData *const serializedData = [@"useful data" dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableDictionary *expectedObjectToSerialize = [[NSMutableDictionary alloc] init];
    [expectedObjectToSerialize addEntriesFromDictionary:requestParameters];
    [expectedObjectToSerialize addEntriesFromDictionary:delegateParameters];

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:_preparationDelegateMock];

    [[[_preparationDelegateMock expect] andReturn:delegateParameters] dataRequestService:(id)_serviceMock additionalParametersForRequestMethod:MethodPOST path:path];
    [[[_preparationDelegateMock expect] andReturn:delegateHeaders] dataRequestService:(id)_serviceMock additionalHeadersForRequestMethod:MethodPOST path:path];

    OCMockObject *serializerMock = [OCMockObject mockForClass:[SEDataSerializer class]];
    [[[_serviceMock stub] andReturn:serializerMock] explicitSerializerForMIMEType:mimeType];

    [[[serializerMock stub] andReturnValue:@NO] shouldAppendCharsetToContentType];
    [[[serializerMock stub] andReturnValue:@YES] supportsAdditionalParameters];
    [[[serializerMock expect] andReturn:serializedData] serializeObject:expectedObjectToSerialize mimeType:mimeType error:[OCMArg anyObjectRef]];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:MethodPOST baseURL:_baseURL path:path body:requestParameters mimeType:mimeType error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodPOST);
    XCTAssertEqual(request.HTTPBody, serializedData);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              @"Content-Type" : mimeType,
                                                              @"X-Super-Header" : @"my awesome value"
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
    [serializerMock verify];
}

- (void)testRequestFactoryWithDelegateCreatePOSTRequestIncludesParametersOnDefaultJSONSerializer
{
    NSString *const path = @"yet/another/path";
    NSDictionary *const requestParameters = @{ @"request" : @"request-value" };
    NSDictionary *const delegateParameters = @{ @"additional" : @"some-value" };
    NSDictionary *const delegateHeaders = @{ @"X-Super-Header" : @"my awesome value" };

    NSMutableDictionary *expectedObjectToSerialize = [[NSMutableDictionary alloc] init];
    [expectedObjectToSerialize addEntriesFromDictionary:requestParameters];
    [expectedObjectToSerialize addEntriesFromDictionary:delegateParameters];

    NSData *const serializedData = [SEJSONDataSerializer serializeObject:expectedObjectToSerialize error:nil];

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:_preparationDelegateMock];

    [[[_preparationDelegateMock expect] andReturn:delegateParameters] dataRequestService:(id)_serviceMock additionalParametersForRequestMethod:MethodPOST path:path];
    [[[_preparationDelegateMock expect] andReturn:delegateHeaders] dataRequestService:(id)_serviceMock additionalHeadersForRequestMethod:MethodPOST path:path];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:MethodPOST baseURL:_baseURL path:path body:requestParameters mimeType:nil error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodPOST);
    XCTAssertEqualObjects(request.HTTPBody, serializedData);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              @"Content-Type" : @"application/json; charset=utf-8",
                                                              @"X-Super-Header" : @"my awesome value"
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);
    
    [self veriyAllMocks];
}

- (void)testRequestFactoryWithDelegateCreatePOSTRequestIgnoresParametersIfSerializerDoesNotAllow
{
    NSString *const path = @"yet/another/path";
    NSString *const mimeType = @"unit/test";
    NSDictionary *const requestParameters = @{ @"request" : @"request-value" };
    NSDictionary *const delegateHeaders = @{ @"X-Super-Header" : @"my awesome value" };
    NSData *const serializedData = [@"useful data" dataUsingEncoding:NSUTF8StringEncoding];

    NSDictionary *expectedObjectToSerialize = requestParameters;

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:_preparationDelegateMock];

    [[_preparationDelegateMock reject] dataRequestService:[OCMArg any] additionalParametersForRequestMethod:[OCMArg any] path:[OCMArg any]];
    [[[_preparationDelegateMock expect] andReturn:delegateHeaders] dataRequestService:(id)_serviceMock additionalHeadersForRequestMethod:MethodPOST path:path];

    OCMockObject *serializerMock = [OCMockObject mockForClass:[SEDataSerializer class]];
    [[[_serviceMock stub] andReturn:serializerMock] explicitSerializerForMIMEType:mimeType];

    [[[serializerMock stub] andReturnValue:@NO] shouldAppendCharsetToContentType];
    [[[serializerMock stub] andReturnValue:@NO] supportsAdditionalParameters];
    [[[serializerMock expect] andReturn:serializedData] serializeObject:expectedObjectToSerialize mimeType:mimeType error:[OCMArg anyObjectRef]];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithMethod:MethodPOST baseURL:_baseURL path:path body:requestParameters mimeType:mimeType error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodPOST);
    XCTAssertEqual(request.HTTPBody, serializedData);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              @"Content-Type" : mimeType,
                                                              @"X-Super-Header" : @"my awesome value"
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);
    
    [self veriyAllMocks];
    [serializerMock verify];
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


#pragma mark - Download request

- (void)testRequestFactoryCreateDownloadRequestNoDelegate
{
    NSString *const path = @"cms/image.png";

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];

    NSError *error = nil;
    NSURLRequest *request = [factory createDownloadRequestWithBaseURL:_baseURL path:path body:nil error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodGET);
    XCTAssertNil(request.HTTPBody);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
}

- (void)testRequestFactoryCreateDownloadRequestWithDelegate
{
    NSString *const path = @"yet/another/path";
    NSDictionary *const delegateHeaders = @{ @"X-Super-Header" : @"my awesome value" };

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:_preparationDelegateMock];

    [[[_preparationDelegateMock expect] andReturn:nil] dataRequestService:(id)_serviceMock additionalParametersForRequestMethod:MethodGET path:path];
    [[[_preparationDelegateMock expect] andReturn:delegateHeaders] dataRequestService:(id)_serviceMock additionalHeadersForRequestMethod:MethodGET path:path];

    NSError *error = nil;
    NSURLRequest *request = [factory createDownloadRequestWithBaseURL:_baseURL path:path body:nil error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodGET);
    XCTAssertNil(request.HTTPBody);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"X-Super-Header" : @"my awesome value"
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
}


#pragma mark - Request builder - non-multipart

- (void)testRequestFactoryCreateRequestWithBuilderBasicFieldsOnly
{
    NSString *const path = @"build/a/path";
    SEInternalDataRequestBuilder *requestBuilder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:_serviceMock];
    [requestBuilder POST:path
                 success:^(id o, NSURLResponse *r){ XCTFail(@"Should never invoke"); }
                 failure:^(NSError * _Nonnull error) { XCTFail(@"Should never invoke"); }
         completionQueue:dispatch_get_main_queue()];

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithBuilder:requestBuilder baseURL:_baseURL error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodPOST);
    XCTAssertNil(request.HTTPBody);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
}

- (void)testRequestFactoryCreateRequestWithBuilderDataTypes
{
    NSString *const path = @"build/a/path";
    NSString *const contentEncoding = @"test/unit";
    NSDictionary *const parameters = @{ @"useful" : @"value", @"not useful" : @2 };
    NSData *const serializedData = [@"not at all useful data" dataUsingEncoding:NSUTF8StringEncoding];

    OCMockObject *serializerMock = [OCMockObject mockForClass:[SEDataSerializer class]];
    [[[_serviceMock stub] andReturn:serializerMock] explicitSerializerForMIMEType:contentEncoding];

    [[[serializerMock stub] andReturnValue:@YES] shouldAppendCharsetToContentType];
    [[[serializerMock expect] andReturn:serializedData] serializeObject:parameters mimeType:contentEncoding error:[OCMArg anyObjectRef]];

    SEInternalDataRequestBuilder *requestBuilder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:_serviceMock];
    [requestBuilder POST:path
                 success:^(id o, NSURLResponse *r){ XCTFail(@"Should never invoke"); }
                 failure:^(NSError * _Nonnull error) { XCTFail(@"Should never invoke"); }
         completionQueue:dispatch_get_main_queue()];

    [requestBuilder setAcceptRawData];
    [requestBuilder setContentEncoding:contentEncoding];
    [requestBuilder setBodyParameters:parameters];

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithBuilder:requestBuilder baseURL:_baseURL error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodPOST);
    XCTAssertEqualObjects(request.HTTPBody, serializedData);

    NSString *expectedContentType = [contentEncoding stringByAppendingString:@"; charset=utf-8"];
    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Content-Type" : expectedContentType,
                                                          };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
    [serializerMock verify];
}

- (void)testRequestFactoryCreateRequestWithBuilderRawData
{
    NSString *const path = @"build/a/path";
    NSString *const contentEncoding = @"test/unit";
    NSData *const serializedData = [@"not at all useful data" dataUsingEncoding:NSUTF8StringEncoding];

    [[_serviceMock reject] explicitSerializerForMIMEType:contentEncoding];

    SEInternalDataRequestBuilder *requestBuilder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:_serviceMock];
    [requestBuilder POST:path
                 success:^(id o, NSURLResponse *r){ XCTFail(@"Should never invoke"); }
                 failure:^(NSError * _Nonnull error) { XCTFail(@"Should never invoke"); }
         completionQueue:dispatch_get_main_queue()];

    [requestBuilder setAcceptRawData];
    [requestBuilder setContentEncoding:contentEncoding];
    [requestBuilder setBodyData:serializedData];

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithBuilder:requestBuilder baseURL:_baseURL error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodPOST);
    XCTAssertEqualObjects(request.HTTPBody, serializedData);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Content-Type" : contentEncoding,
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);
    
    [self veriyAllMocks];
}

- (void)testRequestFactoryCreateRequestWithBuilderCustomHeaders
{
    NSString *const path = @"build/a/path";
    NSData *const serializedData = [@"not at all useful data" dataUsingEncoding:NSUTF8StringEncoding];

    [[_serviceMock reject] explicitSerializerForMIMEType:[OCMArg any]];

    SEInternalDataRequestBuilder *requestBuilder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:_serviceMock];
    [requestBuilder POST:path
                 success:^(id o, NSURLResponse *r){ XCTFail(@"Should never invoke"); }
                 failure:^(NSError * _Nonnull error) { XCTFail(@"Should never invoke"); }
         completionQueue:dispatch_get_main_queue()];

    [requestBuilder setBodyData:serializedData];
    [requestBuilder setHTTPHeader:@"first value" forKey:@"X-First-Header"];
    [requestBuilder setHTTPHeader:@"second value" forKey:@"X-Second-Header"];

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithBuilder:requestBuilder baseURL:_baseURL error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodPOST);
    XCTAssertEqualObjects(request.HTTPBody, serializedData);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              @"Content-Type" : SEDataRequestServiceContentTypeOctetStream,
                                                              @"X-First-Header": @"first value",
                                                              @"X-Second-Header": @"second value"
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
}

- (void)testRequestFactoryCreateRequestWithBuilderCustomHeadersOverwrittenByContent
{
    NSString *const path = @"build/a/path";
    NSData *const serializedData = [@"not at all useful data" dataUsingEncoding:NSUTF8StringEncoding];

    [[_serviceMock reject] explicitSerializerForMIMEType:[OCMArg any]];

    SEInternalDataRequestBuilder *requestBuilder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:_serviceMock];
    [requestBuilder POST:path
                 success:^(id o, NSURLResponse *r){ XCTFail(@"Should never invoke"); }
                 failure:^(NSError * _Nonnull error) { XCTFail(@"Should never invoke"); }
         completionQueue:dispatch_get_main_queue()];

    [requestBuilder setBodyData:serializedData];
    [requestBuilder setHTTPHeader:@"first value" forKey:@"X-First-Header"];
    [requestBuilder setHTTPHeader:@"second value" forKey:@"X-Second-Header"];
    [requestBuilder setHTTPHeader:@"random stuff" forKey:@"Content-Type"];

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];

    NSError *error = nil;
    NSURLRequest *request = [factory createRequestWithBuilder:requestBuilder baseURL:_baseURL error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodPOST);
    XCTAssertEqualObjects(request.HTTPBody, serializedData);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              @"Content-Type" : SEDataRequestServiceContentTypeOctetStream,
                                                              @"X-First-Header": @"first value",
                                                              @"X-Second-Header": @"second value"
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);
    
    [self veriyAllMocks];
}


#pragma mark - Request builder - multipart

- (void)testRequestFactoryCreateRequestWithBuilderMultipartContent
{
    NSString *const path = @"build/a/multipart";
    NSString *const partName = @"partName";
    NSString *const boundary = @"BoUNdaRy-";
    NSData *const serializedData = [@"not at all useful data" dataUsingEncoding:NSUTF8StringEncoding];

    SEInternalDataRequestBuilder *requestBuilder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:_serviceMock];

    NSError *error = nil;
    [requestBuilder POST:path
                 success:^(id o, NSURLResponse *r){ XCTFail(@"Should never invoke"); }
                 failure:^(NSError * _Nonnull error) { XCTFail(@"Should never invoke"); }
         completionQueue:dispatch_get_main_queue()];

    BOOL result = [requestBuilder appendPartWithData:serializedData name:partName mimeType:SEDataRequestServiceContentTypePlainText error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);

    SEDataRequestFactory *factory = [[SEDataRequestFactory alloc] initWithService:_serviceMock secure:YES userAgent:_userAgentString requestPreparationDelegate:nil];

    NSURLRequest *request = [factory createMultipartRequestWithBuilder:requestBuilder baseURL:_baseURL boundary:boundary error:&error];

    XCTAssertNil(error);
    XCTAssertNotNil(request);

    NSURL *expectedURL = [NSURL URLWithString:path relativeToURL:_baseURL];
    XCTAssertEqualObjects(request.URL, expectedURL);
    XCTAssertEqualObjects(request.HTTPMethod, MethodPOST);
    XCTAssertNil(request.HTTPBody);

    NSDictionary<NSString *, NSString *> *expectedHeaders = @{
                                                              @"User-Agent" : _userAgentString,
                                                              @"Accept" : @"application/json; charset=utf-8",
                                                              @"Content-Length" : @"127",
                                                              @"Content-Type" : @"multipart/form-data; boundary=BoUNdaRy-"
                                                              };
    XCTAssertEqualObjects(request.allHTTPHeaderFields, expectedHeaders);

    [self veriyAllMocks];
}


@end
