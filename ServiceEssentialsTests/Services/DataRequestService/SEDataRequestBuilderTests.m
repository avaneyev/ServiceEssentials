//
//  SEDataRequestBuilderTests.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

@import XCTest;
@import OCMock;

#import "SEDataRequestService.h"
#import "SEInternalDataRequestBuilder.h"
#import "SEDataRequestServicePrivate.h"
#import "SEMultipartRequestContentPart.h"

@interface SEDataRequestBuilderClassThatSupportsDeserialization : NSObject<SEDataRequestJSONDeserializable>
@end

@interface SEDataRequestBuilderClassThatSupportsDeserializationThrougParent : SEDataRequestBuilderClassThatSupportsDeserialization
@end

@interface SEDataRequestBuilderClassThatDoesNotSupportsDeserialization : NSObject
@end


@interface SEDataRequestBuilderTests : XCTestCase
@property (nonatomic, readwrite, strong) OCMockObject<SEDataRequestServicePrivate> *dataRequestServiceMock;
@property (nonatomic, readwrite, strong) NSURL *dummyImageFileURL;
@end

@implementation SEDataRequestBuilderTests

- (void)setUp
{
    [super setUp];
    self.dataRequestServiceMock = OCMStrictProtocolMock(@protocol(SEDataRequestServicePrivate));
}

- (void)tearDown
{
    [self removeTestFileIfNeeded];
    [super tearDown];
}

- (id<SEDataRequestCustomizer>) createSimpleBuilderAndPost
{
    NSString * const path = @"other/path";
    
    void (^success)(id data, NSURLResponse *response) = ^(id data, NSURLResponse *response){ };
    void (^failure)(NSError *error) = ^(NSError *error){ };
    dispatch_queue_t queue = dispatch_get_main_queue();
    
    SEInternalDataRequestBuilder *builder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:self.dataRequestServiceMock];
    return [builder POST:path success:success failure:failure completionQueue:queue];
}

- (NSData *) createSomeData
{
    static NSString *someDataContents = @"Hey, data!";
    NSData *data = [someDataContents dataUsingEncoding:NSUTF8StringEncoding];
    return data;
}

- (void)testSimplePostRequest
{
    NSString * const path = @"some/path";
    
    void (^success)(id data, NSURLResponse *response) = ^(id data, NSURLResponse *response){ };
    void (^failure)(NSError *error) = ^(NSError *error){ };
    dispatch_queue_t queue = dispatch_get_main_queue();
    
    SEInternalDataRequestBuilder *builder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:self.dataRequestServiceMock];
    
    id<SEDataRequestCustomizer> customizer = [builder POST:path success:success failure:failure completionQueue:queue];
    XCTAssertNotNil(customizer);
    XCTAssertEqualObjects(@"POST", builder.method);
    XCTAssertEqualObjects(path, builder.path);
    XCTAssertEqual(success, builder.success);
    XCTAssertEqual(failure, builder.failure);
    XCTAssertEqual(queue, builder.completionQueue);
    XCTAssertNil(builder.bodyParameters);
    XCTAssertNil(builder.contentEncoding);
    XCTAssertNil(builder.contentParts);
    XCTAssertNil(builder.deserializeClass);
    XCTAssertNil(builder.headers);
}

- (void)testSimplePutRequest
{
    NSString * const path = @"other/path";
    
    void (^success)(id data, NSURLResponse *response) = ^(id data, NSURLResponse *response){ };
    void (^failure)(NSError *error) = ^(NSError *error){ };
    dispatch_queue_t queue = dispatch_get_main_queue();
    
    SEInternalDataRequestBuilder *builder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:self.dataRequestServiceMock];
    
    id<SEDataRequestCustomizer> customizer = [builder PUT:path success:success failure:failure completionQueue:queue];
    XCTAssertNotNil(customizer);
    XCTAssertEqualObjects(@"PUT", builder.method);
    XCTAssertEqualObjects(path, builder.path);
    XCTAssertEqual(success, builder.success);
    XCTAssertEqual(failure, builder.failure);
    XCTAssertEqual(queue, builder.completionQueue);
}

- (void)testDuplicateMethodThrowsError
{
    NSString * const path = @"other/path";
    
    void (^success)(id data, NSURLResponse *response) = ^(id data, NSURLResponse *response){ };
    void (^failure)(NSError *error) = ^(NSError *error){ };
    dispatch_queue_t queue = dispatch_get_main_queue();
    
    SEInternalDataRequestBuilder *builder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:self.dataRequestServiceMock];
    
    XCTAssertNoThrow([builder PUT:path success:success failure:failure completionQueue:queue]);
    XCTAssertThrows([builder PUT:path success:success failure:failure completionQueue:queue]);
    
    builder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:self.dataRequestServiceMock];
    XCTAssertNoThrow([builder POST:path success:success failure:failure completionQueue:queue]);
    XCTAssertThrows([builder PUT:path success:success failure:failure completionQueue:queue]);

    builder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:self.dataRequestServiceMock];
    XCTAssertNoThrow([builder PUT:path success:success failure:failure completionQueue:queue]);
    XCTAssertThrows([builder POST:path success:success failure:failure completionQueue:queue]);
}

- (void)testSimpleRequestSubmit
{
    id<SEDataRequestCustomizer> customizer = [self createSimpleBuilderAndPost];
    OCMExpect([self.dataRequestServiceMock submitRequestWithBuilder:(SEInternalDataRequestBuilder *)customizer asUpload:NO]);
    [customizer submit];
    
    OCMVerifyAll(self.dataRequestServiceMock);
}

- (void)testAdditionalRequestConfigurationBodyParameters
{
    NSString * const path = @"some/my/path";
    
    void (^success)(id data, NSURLResponse *response) = ^(id data, NSURLResponse *response){ };
    void (^failure)(NSError *error) = ^(NSError *error){ };
    dispatch_queue_t queue = dispatch_get_main_queue();
    
    NSDictionary *const bodyParameters = @{ @"param" : @100, @"param_other" : @"value" };

    SEInternalDataRequestBuilder *builder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:self.dataRequestServiceMock];
    
    id<SEDataRequestCustomizer> customizer = [builder POST:path success:success failure:failure completionQueue:queue];
    
    [customizer setBodyParameters: bodyParameters];
    
    XCTAssertNotNil(customizer);
    XCTAssertEqualObjects(@"POST", builder.method);
    XCTAssertEqualObjects(path, builder.path);
    XCTAssertEqual(success, builder.success);
    XCTAssertEqual(failure, builder.failure);
    XCTAssertEqual(queue, builder.completionQueue);
    XCTAssertEqualObjects(bodyParameters, builder.bodyParameters);
    XCTAssertNil(builder.body);
    XCTAssertNil(builder.contentEncoding);
    XCTAssertNil(builder.contentParts);
    XCTAssertNil(builder.deserializeClass);
    XCTAssertNil(builder.headers);
    
    OCMVerifyAll(self.dataRequestServiceMock);
}

- (void)testAdditionalRequestConfigurationBody
{
    NSString * const path = @"some/my/path";

    void (^success)(id data, NSURLResponse *response) = ^(id data, NSURLResponse *response){ };
    void (^failure)(NSError *error) = ^(NSError *error){ };
    dispatch_queue_t queue = dispatch_get_main_queue();

    NSData *const body = [@"some data here" dataUsingEncoding:NSUTF8StringEncoding];

    SEInternalDataRequestBuilder *builder = [[SEInternalDataRequestBuilder alloc] initWithDataRequestService:self.dataRequestServiceMock];

    id<SEDataRequestCustomizer> customizer = [builder POST:path success:success failure:failure completionQueue:queue];

    [customizer setBodyData:body];

    XCTAssertNotNil(customizer);
    XCTAssertEqualObjects(@"POST", builder.method);
    XCTAssertEqualObjects(path, builder.path);
    XCTAssertEqual(success, builder.success);
    XCTAssertEqual(failure, builder.failure);
    XCTAssertEqual(queue, builder.completionQueue);
    XCTAssertEqualObjects(body, builder.body);
    XCTAssertNil(builder.bodyParameters);
    XCTAssertNil(builder.contentEncoding);
    XCTAssertNil(builder.contentParts);
    XCTAssertNil(builder.deserializeClass);
    XCTAssertNil(builder.headers);

    OCMVerifyAll(self.dataRequestServiceMock);
}

- (void)testAdditionalRequestConfigurationContentType
{
    NSString *const contentEncoding = @"my-encoding";
    id serializer = [NSObject new];
    
    id<SEDataRequestCustomizer> customizer = [self createSimpleBuilderAndPost];
    OCMExpect([self.dataRequestServiceMock explicitSerializerForMIMEType:contentEncoding]).andReturn(serializer);
    
    [customizer setContentEncoding:contentEncoding];
    
    SEInternalDataRequestBuilder *builder = (SEInternalDataRequestBuilder *)customizer;
    XCTAssertEqualObjects(contentEncoding, builder.contentEncoding);
    OCMVerifyAll(self.dataRequestServiceMock);
}

- (void)testAdditionalRequestConfigurationUnsupportedContentType
{
    id<SEDataRequestCustomizer> customizer = [self createSimpleBuilderAndPost];
    NSString *const contentEncoding = @"unsupported-encoding";
    
    OCMExpect([self.dataRequestServiceMock explicitSerializerForMIMEType:contentEncoding]).andReturn(nil);
    XCTAssertThrows([customizer setContentEncoding:contentEncoding]);
    
    OCMVerifyAll(self.dataRequestServiceMock);
}

- (void)testAdditionalRequestConfigurationValidDeserializationClass
{
    id<SEDataRequestCustomizer> customizer = [self createSimpleBuilderAndPost];
    [customizer setDeserializeClass:[SEDataRequestBuilderClassThatSupportsDeserialization class]];
    
    SEInternalDataRequestBuilder *builder = (SEInternalDataRequestBuilder *)customizer;
    XCTAssertEqual(builder.deserializeClass, [SEDataRequestBuilderClassThatSupportsDeserialization class]);
}

- (void)testAdditionalRequestConfigurationValidDeserializationClassThroughSubclass
{
    id<SEDataRequestCustomizer> customizer = [self createSimpleBuilderAndPost];
    [customizer setDeserializeClass:[SEDataRequestBuilderClassThatSupportsDeserializationThrougParent class]];
    
    SEInternalDataRequestBuilder *builder = (SEInternalDataRequestBuilder *)customizer;
    XCTAssertEqual(builder.deserializeClass, [SEDataRequestBuilderClassThatSupportsDeserializationThrougParent class]);
}

- (void)testAdditionalRequestConfigurationUnsupportedDeserializationClass
{
    id<SEDataRequestCustomizer> customizer = [self createSimpleBuilderAndPost];
    
    XCTAssertThrows([customizer setDeserializeClass:[SEDataRequestBuilderClassThatDoesNotSupportsDeserialization class]]);
}

- (void)testAdditionalRequestConfigurationCustomHeaders
{
    static NSString *const FirstHeader = @"FirstHeader";
    static NSString *const FirstHeaderValue = @"FirstHeaderValue";
    static NSString *const SecondHeader = @"SecondHeader";
    static NSString *const SecondHeaderValue = @"OtherHeaderValue";

    id<SEDataRequestCustomizer> customizer = [self createSimpleBuilderAndPost];
    [customizer setHTTPHeader:FirstHeaderValue forkey:FirstHeader];
    [customizer setHTTPHeader:SecondHeaderValue forkey:SecondHeader];
    
    SEInternalDataRequestBuilder *builder = (SEInternalDataRequestBuilder *)customizer;
    NSDictionary *headers = builder.headers;
    XCTAssertNotNil(headers);
    XCTAssertEqualObjects(FirstHeaderValue, headers[FirstHeader]);
    XCTAssertEqualObjects(SecondHeaderValue, headers[SecondHeader]);
}

- (void)testContentPartsAfterBodyFails
{
    id<SEDataRequestCustomizer> customizer = [self createSimpleBuilderAndPost];
    [customizer setBodyParameters:@{ @"1": @2 }];
    NSError *error = nil;
    XCTAssertFalse([customizer appendPartWithData:[self createSomeData] name:@"partName" mimeType:SEDataRequestServiceContentTypePlainText error:&error]);
}

- (void)testContentPartsAddDataPart
{
    id<SEDataRequestCustomizer> customizer = [self createSimpleBuilderAndPost];
    NSData *data = [self createSomeData];
    NSString *const name = @"part_name";
    NSError *error = nil;

    id serializer = [NSObject new];
    OCMExpect([self.dataRequestServiceMock explicitSerializerForMIMEType:SEDataRequestServiceContentTypePlainText]).andReturn(serializer);
    
    BOOL result = [customizer appendPartWithData:data name:name mimeType:SEDataRequestServiceContentTypePlainText error:&error];
    
    XCTAssertTrue(result);
    XCTAssertNil(error);
    
    SEInternalDataRequestBuilder *builder = (SEInternalDataRequestBuilder *)customizer;
    XCTAssertNotNil(builder.contentParts);
    XCTAssertEqual(1, builder.contentParts.count);
    
    SEMultipartRequestContentPart *part = builder.contentParts.firstObject;
    XCTAssertNotNil(part);
    XCTAssertEqualObjects(name, part.name);
    XCTAssertNil(part.fileName);
    XCTAssertNil(part.fileURL);
    XCTAssertEqualObjects(data, part.data);
    
    NSDictionary *headers = part.headers;
    XCTAssertNotNil(headers);
    XCTAssertEqualObjects(SEDataRequestServiceContentTypePlainText, headers[@"Content-Type"]);
}

- (void)testContentPartsAddJSONPart
{
    id<SEDataRequestCustomizer> customizer = [self createSimpleBuilderAndPost];
    NSDictionary *json = @{ @"field": @"value", @"number": @5 };
    NSString *const name = @"json";
    NSError *error = nil;

    id serializer = [NSObject new];
    OCMExpect([self.dataRequestServiceMock explicitSerializerForMIMEType:SEDataRequestServiceContentTypeJSON]).andReturn(serializer);
    
    BOOL result = [customizer appendPartWithJSON:json name:name error:&error];
    
    XCTAssertTrue(result);
    XCTAssertNil(error);
    
    SEInternalDataRequestBuilder *builder = (SEInternalDataRequestBuilder *)customizer;
    XCTAssertNotNil(builder.contentParts);
    XCTAssertEqual(1, builder.contentParts.count);
    
    SEMultipartRequestContentPart *part = builder.contentParts.firstObject;
    XCTAssertNotNil(part);
    XCTAssertEqualObjects(name, part.name);
    XCTAssertNil(part.fileName);
    XCTAssertNil(part.fileURL);
    NSData *partData = part.data;
    XCTAssertNotNil(partData);
    id deserialized = [NSJSONSerialization JSONObjectWithData:partData options:0 error:&error];
    XCTAssertNotNil(deserialized);
    XCTAssertTrue([deserialized isKindOfClass:[NSDictionary class]]);
    XCTAssertEqual(2, [deserialized count]);
    
    NSDictionary *headers = part.headers;
    XCTAssertNotNil(headers);
    XCTAssertEqualObjects(SEDataRequestServiceContentTypeJSON, headers[@"Content-Type"]);
    NSString *expectedDisposition = [NSString stringWithFormat:@"form-data; name=\"%@\"", name];
    XCTAssertEqualObjects(expectedDisposition, headers[@"Content-Disposition"]);
}

- (void)testContentPartsAddFilePartNotFileURLFailure
{
    NSURL *url = [NSURL URLWithString:@"https://www.org"];
    NSString *const name = @"file";
    NSError *error = nil;
    id<SEDataRequestCustomizer> customizer = [self createSimpleBuilderAndPost];

    XCTAssertFalse([customizer appendPartWithFileURL:url name:name error:&error]);
}

- (void)testContentPartsAddFilePartFileDoesNotExist
{
    NSURL *resourcePath = [[NSBundle mainBundle] resourceURL];
    NSURL *nonExistentUrl = [NSURL URLWithString:@"some-file-that-does-not-exist.exe" relativeToURL:resourcePath];
    NSString *const name = @"file";
    NSError *error = nil;
    id<SEDataRequestCustomizer> customizer = [self createSimpleBuilderAndPost];
    
    XCTAssertFalse([customizer appendPartWithFileURL:nonExistentUrl name:name error:&error]);
}

- (void)testContentPartsAddFilePartFileExists
{
    // First, create a test file. In unit tests, there is no bundle and no images.
    NSURL *fileURL = [self setupTestFile];
    
    NSString *const name = @"file";
    NSError *error = nil;
    id<SEDataRequestCustomizer> customizer = [self createSimpleBuilderAndPost];
    
    BOOL result = [customizer appendPartWithFileURL:fileURL name:name error:&error];
    
    XCTAssertTrue(result);
    XCTAssertNil(error);
    
    SEInternalDataRequestBuilder *builder = (SEInternalDataRequestBuilder *)customizer;
    XCTAssertNotNil(builder.contentParts);
    XCTAssertEqual(1, builder.contentParts.count);
    
    SEMultipartRequestContentPart *part = builder.contentParts.firstObject;
    XCTAssertNotNil(part);
    XCTAssertEqualObjects(name, part.name);
    XCTAssertNotNil(part.fileName);
    XCTAssertNotNil(part.fileURL);
    XCTAssertNil(part.data);
    
    NSDictionary *headers = part.headers;
    XCTAssertNotNil(headers);
    XCTAssertEqualObjects(@"image/png", headers[@"Content-Type"]);
    NSString *expectedDisposition = [NSString stringWithFormat:@"form-data; name=\"%@\"; filename=\"%@\"", name, fileURL.lastPathComponent];
    XCTAssertEqualObjects(expectedDisposition, headers[@"Content-Disposition"]);
}

#pragma mark - Mock file management

- (NSURL *)setupTestFile
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    NSString *imagePath = [documentsDirectory stringByAppendingPathComponent:@"DataBuilderTest"];
    NSString *imageFileName = [imagePath stringByAppendingPathComponent:@"dymmy-image.png"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory;
    BOOL directoryExists = [fileManager fileExistsAtPath:imagePath isDirectory:&isDirectory] && isDirectory;
    
    if (!directoryExists)
    {
        directoryExists = [fileManager createDirectoryAtPath:imagePath withIntermediateDirectories:NO attributes:nil error:nil];
    }
    
    if (directoryExists)
    {
        NSURL *dummyFileUrl = [[NSURL alloc] initFileURLWithPath:imageFileName];
        if (![fileManager fileExistsAtPath:imageFileName isDirectory:&isDirectory])
        {
            NSString *randomData = @"Random File contents";
            NSData *binaryData = [randomData dataUsingEncoding:NSUTF8StringEncoding];
            [binaryData writeToURL:dummyFileUrl atomically:YES];
        }
        self.dummyImageFileURL = dummyFileUrl;
    }
    
    return self.dummyImageFileURL;
}

- (void)removeTestFileIfNeeded
{
    if (self.dummyImageFileURL != nil)
    {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager removeItemAtURL:self.dummyImageFileURL error:nil];
        [fileManager removeItemAtURL:[self.dummyImageFileURL URLByDeletingLastPathComponent] error:nil];
    }
}

@end

@implementation SEDataRequestBuilderClassThatSupportsDeserialization

+ (instancetype)deserializeFromJSON:(NSDictionary *)json
{
    return nil;
}

@end

@implementation SEDataRequestBuilderClassThatSupportsDeserializationThrougParent
@end

@implementation SEDataRequestBuilderClassThatDoesNotSupportsDeserialization
@end
