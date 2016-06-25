//
//  SEServiceLocatorTests.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "SEServiceLocator.h"
#import "SEServiceWeakProxy.h"

@interface SEServiceLocatorTests : XCTestCase

@end

@protocol TestServiceProtocol1 <NSObject>
- (void) method1;
@end

@protocol TestServiceProtocol2 <NSObject>
- (void) method2;
@end

@interface TestServiceImplementation : NSObject <TestServiceProtocol1>

@end

@implementation SEServiceLocatorTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void) testNonexistingProtocolFails {
    SEServiceLocator *serviceLocator = [[SEServiceLocator alloc] init];
    
#ifdef DEBUG
    XCTAssertThrows([serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)]);
#else
    XCTAssertNil([serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)]);
#endif
}

- (void) testSimpleRegisterAndRequest {
    SEServiceLocator *serviceLocator = [[SEServiceLocator alloc] init];
    
    TestServiceImplementation *impl = [[TestServiceImplementation alloc] init];
    XCTAssertNoThrow([serviceLocator registerService:impl forProtocol:@protocol(TestServiceProtocol1)]);
    
    id<TestServiceProtocol1> service = [serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)];
    
    XCTAssertEqual(service, impl);
}

- (void) testSimpleRegisterAndRequestOther {
    SEServiceLocator *serviceLocator = [[SEServiceLocator alloc] init];
    
    TestServiceImplementation *impl = [[TestServiceImplementation alloc] init];
    XCTAssertNoThrow([serviceLocator registerService:impl forProtocol:@protocol(TestServiceProtocol1)]);
    
#ifdef DEBUG
    XCTAssertThrows([serviceLocator serviceForProtocol:@protocol(TestServiceProtocol2)]);
#else
    XCTAssertNil([serviceLocator serviceForProtocol:@protocol(TestServiceProtocol2)]);
#endif
}

- (void) testWeakRegisterAndRequest {
    SEServiceLocator *serviceLocator = [[SEServiceLocator alloc] init];
    
    @autoreleasepool {
        TestServiceImplementation *impl = [[TestServiceImplementation alloc] init];
        XCTAssertNoThrow([serviceLocator registerServiceWeak:impl forProtocol:@protocol(TestServiceProtocol1)]);
        
        id<TestServiceProtocol1> service = [serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)];
        
        XCTAssertEqual(service, impl);
        
        // remove all live references, the only reference should be weak at this point
        service = nil;
        impl = nil;
    }
    
#ifdef DEBUG
    XCTAssertThrows([serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)]);
#else
    XCTAssertNil([serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)]);
#endif
}

- (void) testHierarchicalServiceLocationFindsChild {
    SEServiceLocator *serviceLocator = [[SEServiceLocator alloc] init];
    SEServiceLocator *childLocator = [[SEServiceLocator alloc] initWithParent:serviceLocator];
    
    TestServiceImplementation *impl = [[TestServiceImplementation alloc] init];
    [childLocator registerService:impl forProtocol:@protocol(TestServiceProtocol1)];
    
    XCTAssertEqual([childLocator serviceForProtocol:@protocol(TestServiceProtocol1)], impl);
    
#ifdef DEBUG
    XCTAssertThrows([serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)]);
#else
    XCTAssertNil([serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)]);
#endif
    
}

- (void) testHierarchicalServiceLocationFindsParent {
    SEServiceLocator *serviceLocator = [[SEServiceLocator alloc] init];
    SEServiceLocator *childLocator = [[SEServiceLocator alloc] initWithParent:serviceLocator];
    
    TestServiceImplementation *impl = [[TestServiceImplementation alloc] init];
    [serviceLocator registerService:impl forProtocol:@protocol(TestServiceProtocol1)];
    
    XCTAssertEqual([childLocator serviceForProtocol:@protocol(TestServiceProtocol1)], impl);
    XCTAssertEqual([serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)], impl);
}

- (void) testHierarchicalServiceLocationFindsChildFirst {
    SEServiceLocator *serviceLocator = [[SEServiceLocator alloc] init];
    SEServiceLocator *childLocator = [[SEServiceLocator alloc] initWithParent:serviceLocator];
    
    TestServiceImplementation *impl = [[TestServiceImplementation alloc] init];
    [serviceLocator registerService:impl forProtocol:@protocol(TestServiceProtocol1)];
    
    TestServiceImplementation *impl2 = [[TestServiceImplementation alloc] init];
    [childLocator registerService:impl2 forProtocol:@protocol(TestServiceProtocol1)];
    
    XCTAssertEqual([childLocator serviceForProtocol:@protocol(TestServiceProtocol1)], impl2);
    XCTAssertEqual([serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)], impl);
}

- (void)testWeakProxyRegisterAndRequest {
    SEServiceLocator *serviceLocator = [[SEServiceLocator alloc] init];
    id<TestServiceProtocol1> serviceProxy = nil;
    
    @autoreleasepool {
        TestServiceImplementation *impl = [[TestServiceImplementation alloc] init];
        XCTAssertNoThrow([serviceLocator registerServiceProxyWeak:impl forProtocol:@protocol(TestServiceProtocol1)]);

        serviceProxy = [serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)];

        XCTAssertNotNil(serviceProxy);
        XCTAssertNotEqual(serviceProxy, impl);
        XCTAssertNoThrow([serviceProxy method1]);

        // remove all live references, the only reference should be weak at this point
        impl = nil;
    }

#ifdef DEBUG
    XCTAssertThrows([serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)]);
#else
    XCTAssertNil([serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)]);
#endif

    // calling any method on a proxy throws an exception because the object beingf proxied was deallocated
    XCTAssertFalse(((SEServiceWeakProxy *)serviceProxy).isValid);
}

- (void)testLazyConstructedService {
    SEServiceLocator *serviceLocator = [[SEServiceLocator alloc] init];
    
    __block NSUInteger serviceEvaluationCount = 0;
    [serviceLocator registerLazyEvaluatedServiceWithConstructionBlock:^id(SEServiceLocator *serviceLocator) {
        serviceEvaluationCount++;
        TestServiceImplementation *impl = [[TestServiceImplementation alloc] init];
        return impl;
    } forProtocol:@protocol(TestServiceProtocol1)];
    
    XCTAssertEqual(0, serviceEvaluationCount, @"Should not evaluate the service just yet");
    
    id<TestServiceProtocol1> serviceReference1 = [serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)];
    XCTAssertEqual(1, serviceEvaluationCount, @"Should evaluate the service once");
    XCTAssertNotNil(serviceReference1);
    
    id<TestServiceProtocol1> serviceReference2 = [serviceLocator serviceForProtocol:@protocol(TestServiceProtocol1)];
    XCTAssertEqual(1, serviceEvaluationCount, @"Should not evaluate again");
    XCTAssertNotNil(serviceReference2);
    XCTAssertEqual(serviceReference1, serviceReference2);
}

@end

@implementation TestServiceImplementation
- (void)method1 {
}
@end