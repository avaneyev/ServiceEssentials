//
//  SEJSONSerializerTests.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "SEJSONDataSerializer.h"

@interface SEJSONSerializerTests : XCTestCase

@end

@implementation SEJSONSerializerTests

- (void)testValidJSONSerialize
{
    SEJSONDataSerializer *serializer = [SEJSONDataSerializer new];
    NSError *error = nil;
    
    NSData *result = [serializer serializeObject:@{@"number": @20, @"string": @"some_string"} mimeType:@"application/json" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(result);
}

- (void)testInvalidJSONSerializeFails
{
    SEJSONDataSerializer *serializer = [SEJSONDataSerializer new];
    NSError *error = nil;
    NSURL *someUnsupportedValue = [NSURL URLWithString:@"http://a.b/c"];
    
    NSData *result = [serializer serializeObject:@{@10: someUnsupportedValue, @"string": @"some_string"} mimeType:@"application/json" error:&error];
    XCTAssertNotNil(error);
    XCTAssertNil(result);
}

- (void)testValidJSONDeserialize
{
    SEJSONDataSerializer *serializer = [SEJSONDataSerializer new];
    NSError *error = nil;
    NSString *jsonString = @"{\"number\":32, \"string\": \"string\", \"my-null\": null}";
    NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    
    id result = [serializer deserializeData:data mimeType:@"application/json" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(result);
    XCTAssertTrue([result isKindOfClass:[NSDictionary class]]);
}

- (void)testInvalidJSONDeserializeFails
{
    SEJSONDataSerializer *serializer = [SEJSONDataSerializer new];
    NSError *error = nil;
    NSString *jsonString = @"{\"invalid\":invalid, \"string\": \"string\"}";
    NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    
    id result = [serializer deserializeData:data mimeType:@"application/json" error:&error];
    XCTAssertNotNil(error);
    XCTAssertNil(result);
}


@end
