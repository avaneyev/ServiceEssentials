//
//  SEMultipartRequestContentPart.m
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#import "SEMultipartRequestContentPart.h"

@implementation SEMultipartRequestContentPart
{
    NSString *_mimeType;
    NSDictionary *_headers;
}

- (instancetype) initWithData:(NSData *)data fileUrl:(NSURL *)fileUrl length:(unsigned long long)length name:(NSString *)name fileName:(NSString *)fileName mimeType:(NSString *)mimeType
{
    self = [super init];
    if (self)
    {
        _name = [name copy];
        _mimeType = [mimeType copy];
        if (data != nil)
        {
            _data = [data copy];
            _contentSize = _data.length;
        }
        else if (fileUrl != nil)
        {
            _fileURL = [fileUrl copy];
            _contentSize = length;
        }
        _fileName = [fileName copy];
    }
    return self;
}

- (instancetype)initWithData:(NSData *)data name:(NSString *)name fileName:(NSString *)fileName mimeType:(NSString *)mimeType
{
    return [self initWithData:data fileUrl:nil length:0 name:name fileName:fileName mimeType:mimeType];
}

- (instancetype)initWithFileURL:(NSURL *)fileUrl length:(unsigned long long)length name:(nonnull NSString *)name fileName:(nullable NSString *)fileName mimeType:(nonnull NSString *)mimeType
{
    return [self initWithData:nil fileUrl:fileUrl length:length name:name fileName:fileName mimeType:mimeType];
}

#pragma mark - Properties

- (NSDictionary<NSString *,NSString *> *)headers
{
    if (_headers == nil)
    {
        NSMutableDictionary *headers = [[NSMutableDictionary alloc] init];
        if (_mimeType != nil) [headers setObject:_mimeType forKey:@"Content-Type"];
        NSString *dispositon = _fileName == nil ? [NSString stringWithFormat:@"form-data; name=\"%@\"", _name] : [NSString stringWithFormat:@"form-data; name=\"%@\"; filename=\"%@\"", _name, _fileName];
        [headers setObject:dispositon forKey:@"Content-Disposition"];
        _headers = [headers copy];
    }
    return _headers;
}

@end
