//
//  SEServiceLocator.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <Foundation/Foundation.h>

@interface SEServiceLocator : NSObject

/** Default initializer - initializes a root service locator */
- (instancetype) init;

/** 
 Initialises a service locator with a pointer to parent
 @param parent parent service locator
 @discussion Service locator hierarchy roughly corresponds to use cases and scopes: root locator is global, lower-level locators are scoped - typically to specific use cases.
 When a service locator has a parent, it first attempts to find a service in its own registry, if that fails - requests it from the parent.
 */
- (instancetype) initWithParent: (SEServiceLocator *) parent;

/**
 Finds and returns a service that implements a protocol
 @param protocol a protocol that a service beeing searched for implements
 @return an implementation of a service
 @discussion Throws an exception if a service cannot be found
 */
- (id) serviceForProtocol: (Protocol *) protocol;

/**
 Registers a new service for protocol
 @param service service implementation
 @protocol protocol that the service registers to implement
 */
- (void) registerService: (id) service forProtocol: (Protocol *) protocol;

/**
 Registers a new service for protocol, keeping only a weak reference
 @param service service implementation
 @protocol protocol that the service registers to implement
 @discussion Using this method of service registration may be necessary to break a retention loop if a service needs a reference to a locator and has to be registered in it at the same time. This should, however, be rare.
 */
- (void) registerServiceWeak: (id) service forProtocol: (Protocol *) protocol;

/**
 Registers a new weak service proxy for protocol
 @param service service implementation
 @protocol protocol that the service registers to implement
 @discussion Service proxy is different from other methods in that service locator does not maintain or return a reference to the original object, instead keeping and returning a proxy object. That proxy forwards messages to the actual service implementation. 
 The advantage is that there is no way for a consumer to accidentally retain the service either through service locator itself or through a service reference, which may be helpful in some cases. 
 However, there are a few limitations:
 1. Proxy only supports required instance methods, it does not support optional or class methods.
 2. Proxy does not support KVO/KVC.
 3. When subscribing to a notification, an object cannot specify the service as the sender, because it will not be one.
 */
- (void) registerServiceProxyWeak: (id) service forProtocol: (Protocol *) protocol;

/**
 Registers a new lazy evaluated service for protocol, using a constructor block
 @param constructionBlock a block that will be invoked do construct a service when it is needed
 @protocol protocol that the service registers to implement
 @discussion Registering a service using this method may be beneficial if the service is not always needed or may be resource consuming. It may be true for services performing isolated use cases, such as background work or rarely used views.
 */
- (void) registerLazyEvaluatedServiceWithConstructionBlock: (id(^)(SEServiceLocator *serviceLocator))constructionBlock forProtocol:(Protocol *) protocol;

@end
