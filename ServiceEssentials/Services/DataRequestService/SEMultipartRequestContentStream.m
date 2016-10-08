//
//  SEMultipartRequestContentStream.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import <ServiceEssentials/SEMultipartRequestContentStream.h>

#include <pthread.h>
#import <ServiceEssentials/SETools.h>
#import <ServiceEssentials/SEMultipartRequestContentPart.h>

static NSString *const SEMultipartStreamContentCRLF = @"\r\n";

static inline void SEMultipartRequestContentStreamDescheduleFormRunLoop(CFRunLoopRef runLoop, CFRunLoopSourceRef runLoopSource, NSString *runLoopMode)
{
    CFRunLoopSourceInvalidate(runLoopSource);
    CFRunLoopRemoveSource(runLoop, runLoopSource, (__bridge CFStringRef)runLoopMode);
    CFRelease(runLoopSource);
    
    CFRelease(runLoop);
}

/** Run Lopp callback context items - equality, hash function and callback itself */
Boolean SEMultipartStreamRunLoopEqualCallBack(const void *info1, const void *info2) { return info1 == info2; }
CFHashCode SEMultipartStreamRunLoopHashCallBack(const void *info) { return ((__bridge SEMultipartRequestContentStream *)info).hash; }
void SEMultipartStreamRunLoopPerformCallBack(void *info);

/** 
 Stream state protocol.
 @discussion Stream will go through a set of states (boundary -> headers -> part content -> [boundary -> headers -> part content ->] final boundary -> complete.
 States are internally implemented as individual objects that handle certain parts of the process, such as status, error and reading contents.
 */
@protocol SEMultipartStreamState <NSObject>
- (NSStreamStatus) streamStatus;
- (NSError *) streamError;
- (BOOL) closeAndReturnError: (NSError * __autoreleasing *) error;

- (BOOL) hasBytesAvailable;
- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len newState:(id<SEMultipartStreamState> __autoreleasing *)newState;
@end

/** 
 Stream state content provider protocol - declares the interface of the stream itself that states use to communicate back to the stream.
 @discussion Content provider allows states to get content part count and individual parts, as well as perform tasks like schedule/unschedule child stream to runloop and forward child stream run loop events.
 */
@protocol SEMultipartStreamStateContentProvider <NSObject>
- (NSUInteger) numberOfParts;
- (SEMultipartRequestContentPart *) partAtIndex: (NSUInteger) index;
- (NSString *) boundaryString;
- (NSStringEncoding) stringEncoding;

- (void)scheduleChildStreamInRunLoop:(NSInputStream *)childStream;
- (void)unscheduleChildStreamInRunLoop:(NSInputStream *)childStream;

- (void)triggerRunLoopEventFromState:(NSStreamEvent)event;
- (void)moveFromState:(id<SEMultipartStreamState>)oldState toNewState:(id<SEMultipartStreamState>)newState withEvent:(NSStreamEvent)event;
@end

/** 
 Base class for stream states that are based on in-memory data (as opposed to files).
 @discussion Data-based states follow the same process: they are always in 'reading' state and let reader go through in-memory data. They don't require any run loop scheduling and always have bytes available until all data is read.
 The difference between individual data-based states is mostly around content composition and the next state that follows.
 */
@interface SEMultipartStreamDataBasedState : NSObject<SEMultipartStreamState>
- (instancetype) initWithContentProvider: (id<SEMultipartStreamStateContentProvider>) contentProvider index: (NSUInteger) index data: (NSData *) data;

@property (nonatomic, readonly, weak) id<SEMultipartStreamStateContentProvider> contentProvider;
@property (nonatomic, readonly, assign) NSUInteger partIndex;
@property (nonatomic, readonly, assign, getter=isAtStart) BOOL atStart;

- (id<SEMultipartStreamState>) createNextState;
@end

@interface SEMultipartStreamBoundaryState : SEMultipartStreamDataBasedState
- (instancetype) initWithContentProvider: (id<SEMultipartStreamStateContentProvider>) contentProvider index: (NSUInteger) index isClosing: (BOOL) isClosing;
@end

@interface SEMultipartStreamHeaderItemState : SEMultipartStreamDataBasedState
- (instancetype) initWithContentProvider: (id<SEMultipartStreamStateContentProvider>) contentProvider index: (NSUInteger) index;
@end

@interface SEMultipartStreamDataItemState : SEMultipartStreamDataBasedState
- (instancetype) initWithContentProvider: (id<SEMultipartStreamStateContentProvider>) contentProvider index: (NSUInteger) index;
@end

/** File content state - provides contents of a file as a child stream. */
@interface SEMultipartStreamFileItemState : NSObject<SEMultipartStreamState, NSStreamDelegate>
- (instancetype) initWithContentProvider: (id<SEMultipartStreamStateContentProvider>) contentProvider index: (NSUInteger) index;
@end

/** Complete state - an end of stream processing, either successful completion or error. */
@interface SEMultipartStreamCompleteState : NSObject<SEMultipartStreamState>
- (instancetype) initWithError: (NSError *) error closed: (BOOL) closed;
@end

#pragma mark - Multipart Content Stream Class
/** Multipart Content Stream Class */
@interface SEMultipartRequestContentStream () <NSStreamDelegate, SEMultipartStreamStateContentProvider>
- (void) performScheduledRunLoopEvent;
@end

@implementation SEMultipartRequestContentStream
{
    NSArray<SEMultipartRequestContentPart *> *_contentParts;
    NSString *_boundary;
    NSStringEncoding _stringEncoding;
    
    pthread_mutex_t _lock;
    __weak id<NSStreamDelegate> _delegate;
    
    CFRunLoopRef _runLoop;
    NSString *_runLoopMode;
    CFRunLoopSourceRef _runLoopSource;
    CFOptionFlags _requestedEvents;
    CFReadStreamClientCallBack _copiedCallback;
    CFStreamClientContext *_copiedContext;
    
    id<SEMultipartStreamState> _currentState;
}

- (instancetype)init
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithData:(NSData *)data
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithFileAtPath:(NSString *)path
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithURL:(NSURL *)url
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithParts:(NSArray<SEMultipartRequestContentPart *> *)parts boundary:(NSString *)boundary stringEncoding:(NSStringEncoding)stringEncoding
{
    self = [super init];
    if (self)
    {
        _boundary = boundary;
        _contentParts = parts;
        _stringEncoding = stringEncoding;
        
        pthread_mutex_init(&_lock, NULL);
        _delegate = self;
    }
    return self;
}

- (void)dealloc
{
    if (_runLoop != NULL)
    {
        SEMultipartRequestContentStreamDescheduleFormRunLoop(_runLoop, _runLoopSource, _runLoopMode);
    }
    pthread_mutex_destroy(&_lock);
}

+ (unsigned long long)contentLengthForParts:(NSArray<SEMultipartRequestContentPart *> *)parts boundary:(NSString *)boundary stringEncoding:(NSStringEncoding)stringEncoding
{
    NSString *const preBoundary = @"--";
    NSData *pseudoData = [preBoundary dataUsingEncoding:stringEncoding];
    NSUInteger preBoundaryLength = pseudoData.length;
    
    pseudoData = [SEMultipartStreamContentCRLF dataUsingEncoding:stringEncoding];
    NSUInteger crlfLength = pseudoData.length;
    
    NSUInteger boundaryLength = boundary == nil ? 0 : [boundary dataUsingEncoding:stringEncoding].length;
    
    unsigned long long totalLength = 0;
    
    for (SEMultipartRequestContentPart *part in parts)
    {
        totalLength += preBoundaryLength + boundaryLength + crlfLength ;
        for (NSString *header in part.headers)
        {
            NSString *value = part.headers[header];
            NSString *fullLine = [NSString stringWithFormat:@"%@: %@", header, value];
            totalLength += [fullLine dataUsingEncoding:stringEncoding].length + crlfLength;
        }
        
        totalLength += crlfLength + part.contentSize + crlfLength;
    }
    
    totalLength += preBoundaryLength + boundaryLength + preBoundaryLength;
    return totalLength;
}

#pragma mark - Abstract functionality - NSStream - implementation

- (void)open
{
    @try
    {
        pthread_mutex_lock(&_lock);
        
        if (_currentState == nil)
        {
            _currentState = [[SEMultipartStreamBoundaryState alloc] initWithContentProvider:self index:0 isClosing:NO];
            
            // If scheduled to run loop - signal available data and open
            if (_runLoopSource != NULL) [self triggerEventOnRunLoop];
        }
    }
    @finally
    {
        pthread_mutex_unlock(&_lock);
    }
}

- (void)close
{
    @try
    {
        pthread_mutex_lock(&_lock);
        
        if (_currentState != nil && [_currentState streamStatus] != NSStreamStatusClosed)
        {
            NSError *error = nil;
            if ([_currentState closeAndReturnError:&error])
            {
                _currentState = [[SEMultipartStreamCompleteState alloc] initWithError:error closed:YES];
            }
            else
            {
                _currentState = [[SEMultipartStreamCompleteState alloc] initWithError:nil closed:YES];
            }
        }
    }
    @finally
    {
        pthread_mutex_unlock(&_lock);
    }
}

- (id<NSStreamDelegate>)delegate
{
    id<NSStreamDelegate> knownDelegate = _delegate;
    if (knownDelegate == nil)
    {
        _delegate = self;
        knownDelegate = self;
    }
    return knownDelegate;
}

- (void)setDelegate:(id<NSStreamDelegate>)delegate
{
    if (delegate == nil) _delegate = self;
    else _delegate = delegate;
}

- (id)propertyForKey:(NSString *)key
{
    // will not implement properties
    return nil;
}

- (BOOL)setProperty:(id)property forKey:(NSString *)key
{
    // will not implement properties
    return NO;
}

- (NSStreamStatus)streamStatus
{
    NSStreamStatus status = NSStreamStatusError;
    @try
    {
        pthread_mutex_lock(&_lock);
        status = _currentState == nil ? NSStreamStatusNotOpen : [_currentState streamStatus];
    }
    @finally
    {
        pthread_mutex_unlock(&_lock);
    }
    
    return status;
}

- (NSError *)streamError
{
    NSError *error = nil;
    @try
    {
        pthread_mutex_lock(&_lock);
        error = _currentState == nil ? nil : [_currentState streamError];
    }
    @finally
    {
        pthread_mutex_unlock(&_lock);
    }
    return error;
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
    [self _scheduleInCFRunLoop:aRunLoop.getCFRunLoop forMode:(__bridge CFStringRef)mode];
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
    [self _unscheduleFromCFRunLoop:aRunLoop.getCFRunLoop forMode:(__bridge CFStringRef)mode];
}

- (void)_scheduleInCFRunLoop:(CFRunLoopRef)aRunLoop forMode:(CFStringRef)aMode
{
    @try
    {
        pthread_mutex_lock(&_lock);

        if (_runLoop == aRunLoop) return;
        
        if (_runLoop != NULL)
        {
#ifdef DEBUG
            THROW_INCONSISTENCY(nil);
#else
            [self removeFromCurrentRunLoop];
#endif
        }
    
        CFRetain(aRunLoop);
        _runLoop = aRunLoop;
        _runLoopMode = (__bridge NSString *)aMode;
        
        CFRunLoopSourceContext context = {
            .version = 0,
            .info = (__bridge void *)self,
            .retain = NULL,
            .release = NULL,
            .copyDescription = NULL,
            .equal = SEMultipartStreamRunLoopEqualCallBack,
            .hash = SEMultipartStreamRunLoopHashCallBack,
            .schedule = NULL,
            .cancel = NULL,
            .perform = SEMultipartStreamRunLoopPerformCallBack
        };
        _runLoopSource = CFRunLoopSourceCreate(NULL, 0, &context);
        CFRunLoopAddSource(_runLoop, _runLoopSource, aMode);
    }
    @finally
    {
        pthread_mutex_unlock(&_lock);
    }
}

- (void)_unscheduleFromCFRunLoop:(CFRunLoopRef)aRunLoop forMode:(CFStringRef)aMode
{
    @try
    {
        pthread_mutex_lock(&_lock);
        
        if (_runLoop != NULL && _runLoop == aRunLoop && [_runLoopMode isEqualToString:(__bridge NSString *)aMode])
        {
            [self removeFromCurrentRunLoop];
        }
    }
    @finally
    {
        pthread_mutex_unlock(&_lock);
    }
}

- (BOOL)_setCFClientFlags:(CFOptionFlags)inFlags callback:(CFReadStreamClientCallBack)inCallback context:(CFStreamClientContext *)inContext
{
    @try
    {
        pthread_mutex_lock(&_lock);
        
        if (inCallback != NULL)
        {
            if (_copiedCallback != NULL) return NO;
            
            _requestedEvents = inFlags;
            _copiedCallback = inCallback;
            
            if (inContext != NULL)
            {
                _copiedContext = malloc(sizeof(CFStreamClientContext));
                memcpy(_copiedContext, inContext, sizeof(CFStreamClientContext));
                
                if (_copiedContext->info != NULL && _copiedContext->retain != NULL)
                {
                    _copiedContext->retain(_copiedContext->info);
                }
            }
        }
        else
        {
            if (_copiedCallback != NULL)
            {
                _requestedEvents = kCFStreamEventNone;
                _copiedCallback = NULL;
                if (_copiedContext != NULL)
                {
                    if (_copiedContext->info && _copiedContext->release)
                    {
                        _copiedContext->release(_copiedContext->info);
                    }
                    free(_copiedContext);
                }
            }
        }
    }
    @finally
    {
        pthread_mutex_unlock(&_lock);
    }
    return YES;
}

#pragma mark - Abstract functionality - NSInputStream - implementation

- (BOOL)hasBytesAvailable
{
    BOOL hasBytesAvailable = NO;
    @try
    {
        pthread_mutex_lock(&_lock);
        hasBytesAvailable = _currentState == nil ? NO : [_currentState hasBytesAvailable];
    }
    @finally
    {
        pthread_mutex_unlock(&_lock);
    }

    return hasBytesAvailable;
}

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len
{
    NSInteger bytesRead = 0;
    @try
    {
        pthread_mutex_lock(&_lock);
        
        if (_currentState != nil && [_currentState hasBytesAvailable])
        {
            BOOL continueReading = NO;
            uint8_t *localBuffer = buffer;
            NSUInteger remainingLength = len;
            
            do
            {
                continueReading = NO;
                id<SEMultipartStreamState> newState = nil;
                NSInteger readIncrement = [_currentState read:localBuffer maxLength:remainingLength newState:&newState];
                
                if (newState != nil) _currentState = newState;
                
                if (readIncrement > 0)
                {
                    localBuffer += readIncrement;
                    bytesRead += readIncrement;
                    
                    if (remainingLength <= readIncrement)
                    {
                        remainingLength = 0;
                        break;
                    }
                    
                    remainingLength -= readIncrement;
                }
                
                if (newState != nil)
                {
                    NSStreamStatus status = [newState streamStatus];
                    if (status == NSStreamStatusError || status == NSStreamStatusAtEnd)
                    {
                        if (_runLoopSource != NULL) [self triggerEventOnRunLoop];
                    }
                    else if ([newState hasBytesAvailable])
                    {
                        continueReading = YES;
                    }
                }
            } while (continueReading);
        }
    }
    @finally
    {
        pthread_mutex_unlock(&_lock);
    }

    return bytesRead;
}

- (BOOL)getBuffer:(uint8_t * _Nullable *)buffer length:(NSUInteger *)len
{
    // will not implement this at all
    return NO;
}

#pragma mark - Content Provider

- (NSUInteger)numberOfParts
{
    return _contentParts.count;
}

- (SEMultipartRequestContentPart *)partAtIndex:(NSUInteger)index
{
    return [_contentParts objectAtIndex:index];
}

- (NSString *)boundaryString
{
    return _boundary;
}

- (NSStringEncoding)stringEncoding
{
    return _stringEncoding;
}

- (void)scheduleChildStreamInRunLoop:(NSInputStream *)childStream
{
    if (_runLoop != NULL)
    {
        CFReadStreamScheduleWithRunLoop((__bridge CFReadStreamRef)childStream, _runLoop, (__bridge CFStringRef)_runLoopMode);
    }
}

- (void)unscheduleChildStreamInRunLoop:(NSInputStream *)childStream
{
    if (_runLoop != NULL)
    {
        CFReadStreamUnscheduleFromRunLoop((__bridge CFReadStreamRef)childStream, _runLoop, (__bridge CFStringRef)_runLoopMode);
    }
}

- (void)triggerRunLoopEventFromState:(NSStreamEvent)event
{
    [self notifyAllChannelsWithEventCode:event];
}

- (void)moveFromState:(id<SEMultipartStreamState>)oldState toNewState:(id<SEMultipartStreamState>)newState withEvent:(NSStreamEvent)event
{
    @try
    {
        pthread_mutex_lock(&_lock);

        if (_currentState == oldState) _currentState = newState;
    }
    @finally
    {
        pthread_mutex_unlock(&_lock);
    }
    
    if (event != NSStreamEventNone) [self notifyAllChannelsWithEventCode:event];
}

#pragma mark - Delegate Handling

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    if (aStream != self)
    {
        [self notifyAllChannelsWithEventCode:eventCode];
    }
}

- (void) notifyAllChannelsWithEventCode:(NSStreamEvent)eventCode
{
    [self notifyDelegateWithEventCode:eventCode];
    [self notifyCallbackWithEventCode:eventCode];
}

- (void) notifyDelegateWithEventCode:(NSStreamEvent) event
{
    id<NSStreamDelegate> delegate = self.delegate;
    if (delegate != nil && delegate != self)
    {
        [delegate stream:self handleEvent:event];
    }
}

- (void) notifyCallbackWithEventCode:(NSStreamEvent) event
{
    if (_copiedCallback != nil)
    {
        void *info = _copiedContext == nil ? NULL : _copiedContext->info;
        switch (event) {
            case NSStreamEventOpenCompleted:
                if (_requestedEvents & kCFStreamEventOpenCompleted) _copiedCallback((__bridge CFReadStreamRef)self, kCFStreamEventOpenCompleted, info);
                break;
                
            case NSStreamEventHasBytesAvailable:
                if (_requestedEvents &  kCFStreamEventHasBytesAvailable) _copiedCallback((__bridge CFReadStreamRef)self, kCFStreamEventHasBytesAvailable, info);
                break;
                
            case NSStreamEventErrorOccurred:
                if (_requestedEvents & kCFStreamEventErrorOccurred) _copiedCallback((__bridge CFReadStreamRef)self, kCFStreamEventErrorOccurred, info);
                break;
                
            case NSStreamEventEndEncountered:
                if (_requestedEvents & kCFStreamEventEndEncountered) {
                    _copiedCallback((__bridge CFReadStreamRef)self, kCFStreamEventEndEncountered, info);
                }
                break;

            default:
                break;
        }
    }
}

- (void) triggerEventOnRunLoop
{
    CFRunLoopSourceSignal(_runLoopSource);
    CFRunLoopWakeUp(_runLoop);
}

#pragma mark - Run Loop utilities

- (void) removeFromCurrentRunLoop
{
    SEMultipartRequestContentStreamDescheduleFormRunLoop(_runLoop, _runLoopSource, _runLoopMode);
    _runLoopSource = NULL;    
    _runLoop = NULL;
    _runLoopMode = nil;
}

- (void)performScheduledRunLoopEvent
{
    NSStreamStatus status = self.streamStatus;
    switch (status)
    {
        case NSStreamStatusOpen:
            [self notifyAllChannelsWithEventCode:NSStreamEventOpenCompleted];
            [self notifyAllChannelsWithEventCode:NSStreamEventHasBytesAvailable];
            break;
        case NSStreamStatusAtEnd:
            [self notifyAllChannelsWithEventCode:NSStreamEventEndEncountered];
            break;
        case NSStreamStatusError:
            [self notifyAllChannelsWithEventCode:NSStreamEventErrorOccurred];
            
        default:
            break;
    }
}

@end

#pragma mark - Individual states

@implementation SEMultipartStreamDataBasedState
{
    NSUInteger _dataIndex;
    NSData *_underlyingData;
}

- (instancetype)init
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithContentProvider:(id<SEMultipartStreamStateContentProvider>)contentProvider index:(NSUInteger)index data:(NSData *)data
{
    self = [super init];
    if (self)
    {
        _contentProvider = contentProvider;
        _partIndex = index;
        _dataIndex = 0;
        _underlyingData = data;
    }
    return self;
}

- (BOOL)isAtStart
{
    return (_partIndex == 0 && _dataIndex == 0);
}

- (NSStreamStatus)streamStatus
{
    return NSStreamStatusReading;
}

- (NSError *)streamError
{
    return nil;
}

- (BOOL)closeAndReturnError:(NSError *__autoreleasing *)error
{
    if (error != nil) *error = nil;
    return YES;
}

- (BOOL)hasBytesAvailable
{
    return _dataIndex < _underlyingData.length;
}

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len newState:(__autoreleasing id<SEMultipartStreamState> *)newState
{
    NSRange readRange = { .location = _dataIndex, .length = 0 };
    NSUInteger underlyingLength = _underlyingData.length;
    readRange.length = (_dataIndex + len < underlyingLength) ? len : underlyingLength - _dataIndex;
    [_underlyingData getBytes:buffer range:readRange];
    _dataIndex += readRange.length;
    if (_dataIndex >= underlyingLength)
    {
        id<SEMultipartStreamState> createdState = [self createNextState];
        *newState = createdState;
    }
    return readRange.length;
}

- (id<SEMultipartStreamState>)createNextState
{
    THROW_ABSTRACT(nil);
}

@end

@implementation SEMultipartStreamBoundaryState
{
    BOOL _isClosing;
    NSData *_boundaryData;
}

- (instancetype)initWithContentProvider:(id<SEMultipartStreamStateContentProvider>)contentProvider index:(NSUInteger)index isClosing:(BOOL)isClosing
{
    NSString *boundary = [contentProvider boundaryString];
    NSMutableString *boundaryComposer = [[NSMutableString alloc] initWithCapacity:boundary.length + 10];
    if (index > 0) [boundaryComposer appendString:SEMultipartStreamContentCRLF];
    [boundaryComposer appendString:@"--"];
    if (boundary != nil) [boundaryComposer appendString:boundary];
    if (isClosing) [boundaryComposer appendString:@"--"];
    else [boundaryComposer appendString:SEMultipartStreamContentCRLF];
    
    NSData *boundaryData = [boundaryComposer dataUsingEncoding:[contentProvider stringEncoding]];

    self = [super initWithContentProvider:contentProvider index:index data:boundaryData];
    if (self)
    {
        _isClosing = isClosing;
    }
    return self;
}

- (NSStreamStatus)streamStatus
{
    if (self.atStart) return NSStreamStatusOpen;
    return NSStreamStatusReading;
}

- (id<SEMultipartStreamState>)createNextState
{
    if (_isClosing)
    {
        return [[SEMultipartStreamCompleteState alloc] initWithError:nil closed:NO];
    }
    else
    {
        return [[SEMultipartStreamHeaderItemState alloc] initWithContentProvider:self.contentProvider index:self.partIndex];
    }
}

@end

@implementation SEMultipartStreamHeaderItemState

- (instancetype)initWithContentProvider:(id<SEMultipartStreamStateContentProvider>)contentProvider index:(NSUInteger)index
{
    SEMultipartRequestContentPart *part = [contentProvider partAtIndex:index];
    NSDictionary *headers = part.headers;
    NSMutableString *headerString = [[NSMutableString alloc] init];
    for (NSString *header in headers)
    {
        NSString *value = [headers objectForKey:header];
        [headerString appendFormat:@"%@: %@%@", header, value, SEMultipartStreamContentCRLF];
    }
    [headerString appendString:SEMultipartStreamContentCRLF];
    NSData *headerData = [headerString dataUsingEncoding:[contentProvider stringEncoding]];

    self = [super initWithContentProvider:contentProvider index:index data:headerData];
    return self;
}

- (id<SEMultipartStreamState>)createNextState
{
    SEMultipartRequestContentPart *part = [self.contentProvider partAtIndex:self.partIndex];
    if (part.data) return [[SEMultipartStreamDataItemState alloc] initWithContentProvider:self.contentProvider index:self.partIndex];
    return [[SEMultipartStreamFileItemState alloc] initWithContentProvider:self.contentProvider index:self.partIndex];
}

@end

@implementation SEMultipartStreamDataItemState

- (instancetype)initWithContentProvider:(id<SEMultipartStreamStateContentProvider>)contentProvider index:(NSUInteger)index
{
    SEMultipartRequestContentPart *part = [contentProvider partAtIndex:index];
    self = [super initWithContentProvider:contentProvider index:index data:part.data];
    return self;
}

- (id<SEMultipartStreamState>)createNextState
{
    BOOL final = [self.contentProvider numberOfParts] == self.partIndex + 1;
    return [[SEMultipartStreamBoundaryState alloc] initWithContentProvider:self.contentProvider index:self.partIndex + 1 isClosing:final];
}

@end

@implementation SEMultipartStreamFileItemState
{
    __weak id<SEMultipartStreamStateContentProvider> _contentProvider;
    NSUInteger _partIndex;
    NSInputStream *_innerFileStream;
}

- (instancetype)init
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithContentProvider:(id<SEMultipartStreamStateContentProvider>)contentProvider index:(NSUInteger)index
{
    self = [super init];
    if (self)
    {
        _contentProvider = contentProvider;
        _partIndex = index;
        SEMultipartRequestContentPart *part = [contentProvider partAtIndex:index];
        _innerFileStream = [[NSInputStream alloc] initWithURL:part.fileURL];
        _innerFileStream.delegate = self;
        [contentProvider scheduleChildStreamInRunLoop:_innerFileStream];
        [_innerFileStream open];
    }
    return self;
}

- (void)dealloc
{
    [self closeStreamIfNeeded];
}

- (NSStreamStatus)streamStatus
{
    return NSStreamStatusReading;
}

- (NSError *)streamError
{
    return nil;
}

- (BOOL)closeAndReturnError:(NSError *__autoreleasing *)error
{
    if (error != nil) *error = nil;
    [self closeStreamIfNeeded];
    return YES;
}

- (BOOL)hasBytesAvailable
{
    NSStreamStatus innerStatus = _innerFileStream.streamStatus;
    if (innerStatus == NSStreamStatusOpening) return NO;
    return _innerFileStream.hasBytesAvailable;
}

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len newState:(__autoreleasing id<SEMultipartStreamState> *)newState
{
    NSUInteger result = [_innerFileStream read:buffer maxLength:len];
    if (_innerFileStream.streamStatus == NSStreamStatusError)
    {
        *newState = [self nextStateWithError:_innerFileStream.streamError];
    }
    else if (_innerFileStream.streamStatus == NSStreamStatusAtEnd)
    {
        *newState = [self nextStateWithError:nil];
    }
    return result;
}

- (id<SEMultipartStreamState>)nextStateWithError:(NSError *)error
{
    id<SEMultipartStreamState> newState;
    if (error != nil)
    {
        newState = [[SEMultipartStreamCompleteState alloc] initWithError:error closed:NO];
    }
    else
    {
        BOOL final = [_contentProvider numberOfParts] == _partIndex + 1;
        newState = [[SEMultipartStreamBoundaryState alloc] initWithContentProvider:_contentProvider index:_partIndex + 1 isClosing:final];
    }
    
    [self closeStreamIfNeeded];

    return newState;
}

- (void)closeStreamIfNeeded
{
    if (_innerFileStream != nil)
    {
        [_innerFileStream close];
        [_contentProvider unscheduleChildStreamInRunLoop:_innerFileStream];
        _innerFileStream = nil;
    }
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode)
    {
        case NSStreamEventHasBytesAvailable:
            if (_innerFileStream != nil && _innerFileStream.hasBytesAvailable)
            {
                [_contentProvider triggerRunLoopEventFromState:NSStreamEventHasBytesAvailable];
            }
            break;
            
        case NSStreamEventEndEncountered:
            [_contentProvider moveFromState:self toNewState:[self nextStateWithError:nil] withEvent:NSStreamEventHasBytesAvailable];
            break;
            
        case NSStreamEventErrorOccurred:
            [_contentProvider moveFromState:self toNewState:[self nextStateWithError:_innerFileStream.streamError] withEvent:NSStreamEventErrorOccurred];
            
        default:
            break;
    }
}

@end

@implementation SEMultipartStreamCompleteState
{
    NSError *_error;
    BOOL _closed;
}

- (instancetype)init
{
    THROW_NOT_IMPLEMENTED(nil);
}

- (instancetype)initWithError:(NSError *)error closed:(BOOL)closed
{
    self = [super init];
    if (self)
    {
        _error = error;
        _closed = closed;
    }
    return self;
}

- (NSStreamStatus)streamStatus
{
    if (_closed) return NSStreamStatusClosed;
    return _error == nil ? NSStreamStatusAtEnd : NSStreamStatusError;
}

- (NSError *)streamError
{
    return _error;
}

- (BOOL)closeAndReturnError:(NSError *__autoreleasing *)error
{
    if (error != nil) *error = nil;
    return YES;
}

- (BOOL)hasBytesAvailable
{
    return NO;
}

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len newState:(__autoreleasing id<SEMultipartStreamState> *)newState
{
    return 0;
}

@end

void SEMultipartStreamRunLoopPerformCallBack(void *info)
{
    SEMultipartRequestContentStream *stream = (__bridge SEMultipartRequestContentStream *)info;
    [stream performScheduledRunLoopEvent];
}
