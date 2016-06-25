//
//  SEDataRequestJSONDeserializable.h
//  Service Essentials
//
//  Created by Anton Vaneev.
//  Copyright (c) 2015 Anton Vaneev. All rights reserved.
//
//  Distributed under BSD license. See LICENSE for details.
//

#ifndef SEDataRequestJSONDeserializable_h
#define SEDataRequestJSONDeserializable_h

/** A protocol that determines JSON-deserializable class. A class that conforms to the protocol can be used as a deserialzation class in the <code>DataRequestService</code>. */
@protocol SEDataRequestJSONDeserializable <NSObject>
/** Deserializes a JSON object (a dictionary) to a type-safe object. 
 @parame json JSON object to deserialize.
 @return A deserialized object or <code>nil</code> if an object cannot be deserialized - for example, a mandatory parameter value is missing. 
 */
+ (nullable instancetype) deserializeFromJSON: (nonnull NSDictionary *) json;
@end

#endif /* SEDataRequestJSONDeserializable_h */
