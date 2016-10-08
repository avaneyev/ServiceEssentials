//
//  SEServiceLocator.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <ServiceEssentials/SEServiceLocator.h>

#import <pthread.h>
#import <ServiceEssentials/SETools.h>
#import <ServiceEssentials/SEServiceWeakProxy.h>

@interface SEServiceContainer : NSObject
- (instancetype) initWithObject: (id) object;
- (id) object;
@end

@interface SEWeakServiceContainer : SEServiceContainer
@end

@interface SEStrongServiceContainer : SEServiceContainer
@end

@interface SEProxyServiceContainer : SEServiceContainer
@end

@interface LazyServiceContainer : SEServiceContainer
- (instancetype)initWithConstructionBlock:(id (^)(SEServiceLocator *))constructionBlock protocol: (Protocol *) protocol serviceLocator: (SEServiceLocator *) serviceLocator;
@end

@implementation SEServiceLocator
{
@private
    SEServiceLocator *_parent;
    NSMutableDictionary *_knownServices;
}

- (instancetype)init
{
    return [self initWithParent:nil];
}

- (instancetype)initWithParent:(SEServiceLocator *)parent
{
    self = [super init];
    if (self)
    {
        _parent = parent;
        _knownServices = [[NSMutableDictionary alloc] initWithCapacity:2];
    }
    return self;
}

- (void)registerService:(id)service forProtocol:(Protocol *)protocol
{
    if (![self validateService:service forProtocol:protocol])
        return;
    
    [_knownServices setObject:[[SEStrongServiceContainer alloc] initWithObject:service] forKey: NSStringFromProtocol(protocol)];
}

- (void)registerServiceWeak:(id)service forProtocol:(Protocol *)protocol
{
    if (![self validateService:service forProtocol:protocol])
        return;
    
    [_knownServices setObject:[[SEWeakServiceContainer alloc] initWithObject:service] forKey: NSStringFromProtocol(protocol)];
}

- (void)registerServiceProxyWeak:(id)service forProtocol:(Protocol *)protocol
{
    if (![self validateService:service forProtocol:protocol])
        return;
    
    SEServiceWeakProxy *proxy = [[SEServiceWeakProxy alloc] initWithTarget:service protocol:protocol];
    [_knownServices setObject:[[SEProxyServiceContainer alloc] initWithObject:proxy] forKey: NSStringFromProtocol(protocol)];
}

- (void)registerLazyEvaluatedServiceWithConstructionBlock:(id (^)(SEServiceLocator *))constructionBlock forProtocol:(Protocol *)protocol
{
#ifdef DEBUG
    if (constructionBlock == nil) THROW_INVALID_PARAM(constructionBlock, nil);
#else
    if (constructionBlock == nil) return;
#endif

    LazyServiceContainer *container = [[LazyServiceContainer alloc] initWithConstructionBlock:constructionBlock protocol:protocol serviceLocator:self];
    [_knownServices setObject:container forKey:NSStringFromProtocol(protocol)];
}

- (id)serviceForProtocol:(Protocol *)protocol
{
    NSString *name = NSStringFromProtocol(protocol);
    SEServiceContainer *serviceContainer = [self serviceContainerForProtocolNameNoThrow:name];
    
    id service = serviceContainer ? serviceContainer.object : nil;
    
#ifdef DEBUG
    if (service == nil)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Service for protocol %@ is not registered", name] userInfo:nil];
#endif
    
    return service;
}

#pragma mark - Private members

- (SEServiceContainer *) serviceContainerForProtocolNameNoThrow: (NSString *) name
{
    SEServiceContainer *serviceContainer = [_knownServices objectForKey:name];
    if (serviceContainer != nil)
    {
        if (serviceContainer.object == nil)
        {
            [_knownServices removeObjectForKey:name];
            serviceContainer = nil;
        }
    }
    else if (_parent != nil)
    {
        serviceContainer = [_parent serviceContainerForProtocolNameNoThrow:name];
    }
    
    return serviceContainer;
}

- (BOOL) validateService: (id)service forProtocol:(Protocol *)protocol
{
#ifdef DEBUG
    if (service == nil)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Service cannot be nil." userInfo:nil];
    
    if (![service conformsToProtocol:protocol])
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Service does not conform to  the protocol %@ which it is registered to service.", NSStringFromProtocol(protocol)] userInfo:nil];
    
#else
    if ((service == nil) || ![service conformsToProtocol:protocol])
        return NO;
#endif
    
    return YES;
}

@end

@implementation SEServiceContainer

- (instancetype)init
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithObject:(id)object
{
    self = [super init];
    return self;
}

- (id)object
{
    return nil;
}
@end

@implementation SEStrongServiceContainer
{
    id _object;
}

- (instancetype)initWithObject:(id)object
{
    self = [super initWithObject:object];
    if (self)
    {
        _object = object;
    }
    return self;
}

- (id)object
{
    return _object;
}
@end

@implementation SEWeakServiceContainer
{
    __weak id _object;
}

- (instancetype)initWithObject:(id)object
{
    self = [super initWithObject:object];
    if (self)
    {
        _object = object;
    }
    return self;
}

- (id)object
{
    return _object;
}
@end

@implementation SEProxyServiceContainer
{
    SEServiceWeakProxy *_proxy;
}

- (instancetype)initWithObject:(id)object
{
    self = [super initWithObject:object];
    if (self)
    {
        _proxy = object;
    }
    return self;
}

- (id)object
{
    return _proxy.isValid ? _proxy : nil;
}

@end

@implementation LazyServiceContainer
{
    pthread_mutex_t _lock;
    id (^_constructionBlock)(SEServiceLocator *serviceLocator);
    id _lazyObject;
    __weak SEServiceLocator *_serviceLocator;
    __unsafe_unretained Protocol *_protocol;
}

- (instancetype)initWithObject:(id)object
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithConstructionBlock:(id (^)(SEServiceLocator *))constructionBlock protocol: (Protocol *) protocol serviceLocator: (SEServiceLocator *) serviceLocator
{
    self = [super initWithObject:nil];
    if (self)
    {
        pthread_mutex_init(&_lock, NULL);
        _constructionBlock = constructionBlock;
        _lazyObject = nil;
        _serviceLocator = serviceLocator;
        _protocol = protocol;
    }
    return self;
}

- (void)dealloc
{
    pthread_mutex_destroy(&_lock);
}

- (id)object
{
    id result = nil;
    @try
    {
        pthread_mutex_lock(&_lock);
        if (_lazyObject == nil)
        {
            SEServiceLocator *strongServiceLocator = _serviceLocator;
            if (strongServiceLocator == nil || _constructionBlock == nil) return nil;
            
            _lazyObject = _constructionBlock(strongServiceLocator);
            if (![_lazyObject conformsToProtocol:_protocol])
            {
#ifdef DEBUG
                THROW_INVALID_PARAM(_constructionBlock, nil);
#else
                _lazyObject = nil;
#endif
            }
            
            _serviceLocator = nil;
            _constructionBlock = nil;
        }
        result = _lazyObject;
    }
    @finally
    {
        pthread_mutex_unlock(&_lock);
    }
    return result;
}

@end

