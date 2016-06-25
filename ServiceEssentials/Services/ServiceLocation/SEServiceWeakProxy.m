//
//  SEServiceWeakProxy.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import "SEServiceWeakProxy.h"
#import "SETools.h"
#include <objc/runtime.h>

@implementation SEServiceWeakProxy
{
    __weak id _target;
    Protocol *_protocol;
}

- (instancetype)initWithTarget:(id)target protocol:(Protocol *)protocol
{
    if (target == nil || ![target conformsToProtocol:protocol] || [target isProxy]) THROW_INVALID_PARAM(target, nil);
    
    _target = target;
    _protocol = protocol;
    
    return self;
}

- (BOOL)isValid
{
    return _target != nil;
}

- (id)forwardingTargetForSelector:(SEL)aSelector
{
    struct objc_method_description description = protocol_getMethodDescription(_protocol, aSelector, YES, YES);
    if (description.name != NULL)
    {
        return _target;
    }
    return nil;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    // attempt to get required instance methods only. don't attempt optional or class methods, they make no sense for services
    NSMethodSignature *methodSignature = nil;
    struct objc_method_description description = protocol_getMethodDescription(_protocol, sel, YES, YES);
    if (description.name != NULL)
    {
        methodSignature = [NSMethodSignature signatureWithObjCTypes:description.types];
    }
    return methodSignature;
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    id strongTarget = _target;
    NSString *reason = nil;
    if (strongTarget == nil)
    {
        reason = @"Proxied object was deallocated";
    }
    else
    {
        if ([strongTarget respondsToSelector:invocation.selector]) [invocation invokeWithTarget:strongTarget];
        else reason = @"Proxied object does not respond to selector";
    }
    
    if (reason != nil)
    {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
    }
}

- (BOOL)conformsToProtocol:(Protocol *)aProtocol
{
    return protocol_conformsToProtocol(aProtocol, _protocol);
}

- (BOOL)isKindOfClass:(Class)aClass
{
    return [_target isKindOfClass:aClass];
}

- (BOOL)respondsToSelector:(SEL)aSelector
{
    struct objc_method_description description = protocol_getMethodDescription(_protocol, aSelector, YES, YES);
    return description.name != NULL;
}

@end
