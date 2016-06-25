//
//  SEPlainTextSerializerTests.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "SEPlainTextSerializer.h"

@interface SEPlainTextSerializerTests : XCTestCase
{
    SEPlainTextSerializer *_serializer;
}

@end

@implementation SEPlainTextSerializerTests

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
    _serializer = [SEPlainTextSerializer new];
}

- (void)testSerializeInvalidDataTypeReturnsError
{
    NSNumber *number = @100;
    NSError *error = nil;
    
    NSData *result = [_serializer serializeObject:number mimeType:@"text/plain" error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testSerializeUtf8StringReturnsUtf8Data
{
    NSString *someLocalString = @"Very local - £10 ¢20 §av текст";
    NSData *utf8data = [someLocalString dataUsingEncoding:NSUTF8StringEncoding];
    NSData *utf16data = [someLocalString dataUsingEncoding:NSUTF16StringEncoding];
    NSData *asciidata = [someLocalString dataUsingEncoding:NSASCIIStringEncoding];
    NSError *error = nil;
    
    NSData *actualData = [_serializer serializeObject:someLocalString mimeType:@"text/plain; charset=utf-8" error:&error];
    XCTAssertEqualObjects(utf8data, actualData);
    XCTAssertNotEqualObjects(utf16data, actualData);
    XCTAssertNotEqualObjects(asciidata, actualData);
}

- (void)testSerializeUtf16StringReturnsUtf16Data
{
    NSString *someLocalString = @"Very local - £10 ¢20 §av текст";
    NSData *utf8data = [someLocalString dataUsingEncoding:NSUTF8StringEncoding];
    NSData *utf16data = [someLocalString dataUsingEncoding:NSUTF16StringEncoding];
    NSData *asciidata = [someLocalString dataUsingEncoding:NSASCIIStringEncoding];
    NSError *error = nil;
    
    NSData *actualData = [_serializer serializeObject:someLocalString mimeType:@"text/plain; charset=utf-16" error:&error];
    XCTAssertEqualObjects(utf16data, actualData);
    XCTAssertNotEqualObjects(utf8data, actualData);
    XCTAssertNotEqualObjects(asciidata, actualData);
}


@end
