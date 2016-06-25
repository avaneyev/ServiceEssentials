//
//  SEWebFormSerializerTests.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "SEWebFormSerializer.h"

@interface SEWebFormSerializerTests : XCTestCase
@end

@implementation SEWebFormSerializerTests

- (void)testExplicitURLEncodeSerializationSimpleDictionary
{
    NSDictionary *simpeDictionary = @{
                                      @"one" : @1,
                                      @"two" : @"two"
                                      };
    NSString *result = [SEWebFormSerializer webFormEncodedStringFromDictionary:simpeDictionary withEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(result, @"one=1&two=two");
}

- (void)testExplicitURLEncodeSerializationNullValues
{
    NSDictionary *simpeDictionary = @{
                                      @"object" : @"o",
                                      @"not-object" : [NSNull null]
                                      };
    NSString *result = [SEWebFormSerializer webFormEncodedStringFromDictionary:simpeDictionary withEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(result, @"not-object&object=o");
}

- (void)testExplicitURLEncodeSerializationPercentEncodeValues
{
    NSDictionary *simpeDictionary = @{
                                      @"some key" : @"its=value",
                                      @"other~key" : @"has&value?"
                                      };
    NSString *result = [SEWebFormSerializer webFormEncodedStringFromDictionary:simpeDictionary withEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(result, @"other~key=has%26value%3F&some%20key=its%3Dvalue");
}

- (void)testExplicitURLEncodeSerializationSet
{
    NSSet *set = [NSSet setWithObjects:@"a", @"b", @"c", nil];
    NSDictionary *simpeDictionary = @{
                                      @"key" : @"value",
                                      @"set" : set
                                      };
    NSString *result = [SEWebFormSerializer webFormEncodedStringFromDictionary:simpeDictionary withEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(result, @"key=value&set=a&set=b&set=c");
}

- (void)testExplicitURLEncodeSerializationArray
{
    NSArray *array = @[@"1", @2, @"3"];
    NSDictionary *simpeDictionary = @{
                                      @"otherkey" : @"value",
                                      @"array" : array
                                      };
    NSString *result = [SEWebFormSerializer webFormEncodedStringFromDictionary:simpeDictionary withEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(result, @"array[]=1&array[]=2&array[]=3&otherkey=value");
}

- (void)testExplicitURLEncodeSerializationInnerDictionary
{
    NSDictionary *dictionary = @{ @"number" : @1, @"string" : @"str", @"null" : [NSNull null] };
    NSDictionary *simpeDictionary = @{
                                      @"1"    : @"1",
                                      @"z"    : @"ztring",
                                      @"dict" : dictionary
                                      };
    NSString *result = [SEWebFormSerializer webFormEncodedStringFromDictionary:simpeDictionary withEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(result, @"1=1&dict[null]&dict[number]=1&dict[string]=str&z=ztring");
}

- (void)testExplicitURLEncodeSerializationCombineAllTypes
{
    NSArray *array = @[@"x", @YES, @"NO"];
    NSSet *set = [NSSet setWithObjects:@"p", nil];
    NSDictionary *dictionary = @{ @"number" : @1, @"string" : @"str", @"null" : [NSNull null], @"set" : set };
    NSDictionary *simpeDictionary = @{
                                      @"arr"  : array,
                                      @"z"    : @"ztring",
                                      @"dict" : dictionary
                                      };
    NSString *result = [SEWebFormSerializer webFormEncodedStringFromDictionary:simpeDictionary withEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(result, @"arr[]=x&arr[]=1&arr[]=NO&dict[null]&dict[number]=1&dict[set]=p&dict[string]=str&z=ztring");
}

- (void) testWebFormSerializationProducesURLEncode
{
    SEWebFormSerializer *serializer = [SEWebFormSerializer new];
    NSDictionary *simpeDictionary = @{
                                      @"one" : @1,
                                      @"two" : @"two"
                                      };
    NSString * const expectedResult = @"one=1&two=two";
    NSData * const expectedData = [expectedResult dataUsingEncoding:NSUTF8StringEncoding];
    
    NSError *error = nil;
    NSData *result = [serializer serializeObject:simpeDictionary mimeType:@"application/x-www-form-urlencoded; charset=utf-8" error:&error];
    
    XCTAssertEqualObjects(expectedData, result);
}

- (void)testURLEncodeSerializationPerformance {
    NSArray *array = @[@"x", @YES, @"NO"];
    NSSet *set = [NSSet setWithObjects:@"p", nil];
    NSDictionary *dictionary = @{ @"number" : @1, @"string" : @"str", @"null" : [NSNull null], @"set" : set };
    NSDictionary *simpeDictionary = @{
                                      @"arr"  : array,
                                      @"z"    : @"ztring",
                                      @"dict" : dictionary
                                      };
    [self measureBlock:^{
        [SEWebFormSerializer webFormEncodedStringFromDictionary:simpeDictionary withEncoding:NSUTF8StringEncoding];
    }];
}

@end
