//
//  SEMultipartRequestContentStreamTests.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

@import XCTest;

#import "SEDataRequestService.h"
#import "SEMultipartRequestContentPart.h"
#import "SEMultipartRequestContentStream.h"

@interface SEMultipartRequestContentStreamTests : XCTestCase

@end

@implementation SEMultipartRequestContentStreamTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testSinglePartContentStream
{
    NSString *const firstPart = @"first";
    NSString *const boundary = @"AbcDef";
    
    NSData *firstPartData = [firstPart dataUsingEncoding:NSUTF8StringEncoding];
    SEMultipartRequestContentPart *part = [[SEMultipartRequestContentPart alloc] initWithData:firstPartData name:firstPart fileName:nil mimeType:SEDataRequestServiceContentTypePlainText];
    
    SEMultipartRequestContentStream *stream = [[SEMultipartRequestContentStream alloc] initWithParts:@[ part ] boundary:boundary stringEncoding:NSUTF8StringEncoding];
 
    NSMutableData *accumulator = [[NSMutableData alloc] initWithCapacity:1024];
    uint8_t buffer[1024];
    
    [stream open];
    while ([stream hasBytesAvailable])
    {
        NSInteger readCount = [stream read:buffer maxLength:1024];
        XCTAssert(readCount > 0);
        if (readCount > 0) [accumulator appendBytes:buffer length:readCount];
    }
    XCTAssertEqual(NSStreamStatusAtEnd, stream.streamStatus);
    [stream close];
    
    XCTAssertEqual(NSStreamStatusClosed, stream.streamStatus);
    
    XCTAssert(accumulator.length > 0);
    NSString *actualContents = [[NSString alloc] initWithData:accumulator encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(@"--AbcDef\r\nContent-Disposition: form-data; name=\"first\"\r\nContent-Type: text/plain\r\n\r\nfirst\r\n--AbcDef--", actualContents);
}

- (void)testTwoDataPartsContentStream
{
    NSString *const firstPart = @"first";
    NSString *const secondPart = @"second";
    NSString *const boundary = @"AbcDef";
    
    NSData *firstPartData = [firstPart dataUsingEncoding:NSUTF8StringEncoding];
    SEMultipartRequestContentPart *part = [[SEMultipartRequestContentPart alloc] initWithData:firstPartData name:firstPart fileName:nil mimeType:SEDataRequestServiceContentTypePlainText];

    NSData *secondPartData = [secondPart dataUsingEncoding:NSUTF8StringEncoding];
    SEMultipartRequestContentPart *anotherPart = [[SEMultipartRequestContentPart alloc] initWithData:secondPartData name:secondPart fileName:nil mimeType:SEDataRequestServiceContentTypePlainText];

    SEMultipartRequestContentStream *stream = [[SEMultipartRequestContentStream alloc] initWithParts:@[ part, anotherPart ] boundary:boundary stringEncoding:NSUTF8StringEncoding];
    
    NSMutableData *accumulator = [[NSMutableData alloc] initWithCapacity:1024];
    uint8_t buffer[1024];
    
    [stream open];
    while ([stream hasBytesAvailable])
    {
        NSInteger readCount = [stream read:buffer maxLength:1024];
        XCTAssert(readCount > 0);
        if (readCount > 0) [accumulator appendBytes:buffer length:readCount];
    }
    XCTAssertEqual(NSStreamStatusAtEnd, stream.streamStatus);
    [stream close];
    
    XCTAssertEqual(NSStreamStatusClosed, stream.streamStatus);
    XCTAssert(accumulator.length > 0);
    NSString *actualContents = [[NSString alloc] initWithData:accumulator encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(@"--AbcDef\r\nContent-Disposition: form-data; name=\"first\"\r\nContent-Type: text/plain\r\n\r\nfirst\r\n--AbcDef\r\nContent-Disposition: form-data; name=\"second\"\r\nContent-Type: text/plain\r\n\r\nsecond\r\n--AbcDef--", actualContents);
}

- (void)testTwoDataPartsSmallBufferRequiresSplitting
{
    NSString *const firstPart = @"first";
    NSString *const secondPart = @"second";
    NSString *const boundary = @"AbcDef";
    
    NSData *firstPartData = [firstPart dataUsingEncoding:NSUTF8StringEncoding];
    SEMultipartRequestContentPart *part = [[SEMultipartRequestContentPart alloc] initWithData:firstPartData name:firstPart fileName:nil mimeType:SEDataRequestServiceContentTypePlainText];
    
    NSData *secondPartData = [secondPart dataUsingEncoding:NSUTF8StringEncoding];
    SEMultipartRequestContentPart *anotherPart = [[SEMultipartRequestContentPart alloc] initWithData:secondPartData name:secondPart fileName:nil mimeType:SEDataRequestServiceContentTypePlainText];
    
    SEMultipartRequestContentStream *stream = [[SEMultipartRequestContentStream alloc] initWithParts:@[ part, anotherPart ] boundary:boundary stringEncoding:NSUTF8StringEncoding];
    
    NSMutableData *accumulator = [[NSMutableData alloc] initWithCapacity:1024];
    uint8_t buffer[20];
    
    [stream open];
    NSUInteger iterations = 0;
    while ([stream hasBytesAvailable])
    {
        ++iterations;
        NSInteger readCount = [stream read:buffer maxLength:20];
        XCTAssert(readCount > 0);
        if (readCount > 0) [accumulator appendBytes:buffer length:readCount];
    }
    XCTAssert(iterations > 1);
    XCTAssertEqual(NSStreamStatusAtEnd, stream.streamStatus);
    [stream close];
    
    XCTAssertEqual(NSStreamStatusClosed, stream.streamStatus);
    XCTAssert(accumulator.length > 0);
    NSString *actualContents = [[NSString alloc] initWithData:accumulator encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(@"--AbcDef\r\nContent-Disposition: form-data; name=\"first\"\r\nContent-Type: text/plain\r\n\r\nfirst\r\n--AbcDef\r\nContent-Disposition: form-data; name=\"second\"\r\nContent-Type: text/plain\r\n\r\nsecond\r\n--AbcDef--", actualContents);
}

- (void)testMultipartContentLengthUTF8
{
    NSString *const firstPart = @"first";
    NSString *const secondPart = @"second";
    NSString *const boundary = @"AbcDef";
    
    NSData *firstPartData = [firstPart dataUsingEncoding:NSUTF8StringEncoding];
    SEMultipartRequestContentPart *part = [[SEMultipartRequestContentPart alloc] initWithData:firstPartData name:firstPart fileName:nil mimeType:SEDataRequestServiceContentTypePlainText];
    
    NSData *secondPartData = [secondPart dataUsingEncoding:NSUTF8StringEncoding];
    SEMultipartRequestContentPart *anotherPart = [[SEMultipartRequestContentPart alloc] initWithData:secondPartData name:secondPart fileName:nil mimeType:SEDataRequestServiceContentTypePlainText];

    NSArray *parts = @[ part, anotherPart ];
    unsigned long long length = [SEMultipartRequestContentStream contentLengthForParts:parts boundary:boundary stringEncoding:NSUTF8StringEncoding];
    
    NSMutableData *accumulator = [[NSMutableData alloc] initWithCapacity:1024];
    uint8_t buffer[1024];
    
    SEMultipartRequestContentStream *stream = [[SEMultipartRequestContentStream alloc] initWithParts:parts boundary:boundary stringEncoding:NSUTF8StringEncoding];
    [stream open];
    while ([stream hasBytesAvailable])
    {
        NSInteger readCount = [stream read:buffer maxLength:1024];
        XCTAssert(readCount > 0);
        if (readCount > 0) [accumulator appendBytes:buffer length:readCount];
    }
    XCTAssertEqual(NSStreamStatusAtEnd, stream.streamStatus);
    [stream close];

    XCTAssertEqual(length, accumulator.length);
}

- (void)testMultipartContentLengthUTF16
{
    NSString *const firstPart = @"first";
    NSString *const secondPart = @"second";
    NSString *const boundary = @"AbcDef";
    
    NSData *firstPartData = [firstPart dataUsingEncoding:NSUTF16StringEncoding];
    SEMultipartRequestContentPart *part = [[SEMultipartRequestContentPart alloc] initWithData:firstPartData name:firstPart fileName:nil mimeType:SEDataRequestServiceContentTypePlainText];
    
    NSData *secondPartData = [secondPart dataUsingEncoding:NSUTF16StringEncoding];
    SEMultipartRequestContentPart *anotherPart = [[SEMultipartRequestContentPart alloc] initWithData:secondPartData name:secondPart fileName:nil mimeType:SEDataRequestServiceContentTypePlainText];
    
    NSArray *parts = @[ part, anotherPart ];
    unsigned long long length = [SEMultipartRequestContentStream contentLengthForParts:parts boundary:boundary stringEncoding:NSUTF8StringEncoding];
    
    NSMutableData *accumulator = [[NSMutableData alloc] initWithCapacity:1024];
    uint8_t buffer[1024];
    
    SEMultipartRequestContentStream *stream = [[SEMultipartRequestContentStream alloc] initWithParts:parts boundary:boundary stringEncoding:NSUTF8StringEncoding];
    [stream open];
    while ([stream hasBytesAvailable])
    {
        NSInteger readCount = [stream read:buffer maxLength:1024];
        XCTAssert(readCount > 0);
        if (readCount > 0) [accumulator appendBytes:buffer length:readCount];
    }
    XCTAssertEqual(NSStreamStatusAtEnd, stream.streamStatus);
    [stream close];
    
    XCTAssertEqual(length, accumulator.length);
}

@end
