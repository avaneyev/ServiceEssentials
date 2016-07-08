## Service Essentials
Service Essentials help build complex, extensible applications. They do it by promoting service-oriented architecture, which decreases coupling, improves testability and reduces unwanted complexity.
More about the approach and its advantages in the [Service-Oriented Approach](../master/README.md#service-oriented-approach) section.

**Service Essentials include these basic building blocks:**
* [Service Locator](../master/README.md#service-locator) to register and find services in the application.
* [Data Request Service](../master/README.md#data-request-service) to make network requests
* [Persistence Service](../master/README.md#persistence-service) to manage persistent data in Core Data storage. 

### Getting Started
Starting with Service Essentials is easy:

* Include a precompiled framework OR add individual files to your project.
* Add frameworks that Service Essentials depend on: `CoreData`, `MobileCoreServices`, `SystemConfiguration`. Add `UIKit` for iOS applications as well.
* Add `-ObjC` linker flag.

That's it!

### Service Locator
Service Locator is a dependency injection container. It has two main features: register a dependency and resolve a dependency. All service identification is based on protocols.
#### Registering a dependency:
There are numerous ways to register a dependency, which could be used in different situations.

* Standard registration - the simplest and most often used. Maintains a strong reference to the dependency.
```objective-c
[serviceLocator registerService:serviceObject forProtocol:@protocol(DependencyProtocol)];
```
* Lazy registration - creates a dependency when it's first required. Works well for dependencies that are expensive to create or maintain and not always needed, or in cases when startup time is the highest priority. Uses a block which is invoked when the dependency is first requested; the block takes the service locator as a parameter and may use it to resolve any dependencies neede to construct the instance.
```objective-c
[serviceLocator registerLazyEvaluatedServiceWithConstructionBlock:^(SEServiceLocator * _Nonnull locator){
                                                      // construct an instance.
                                                      // use service locator passed as a parameter if needed
                                                      return dependency;
                                                    } forProtocol:@protocol(DependencyProtocol)];
```
* Weak registration - container maintains a weak reference to the dependency. May be helpful to break retention cycles when a dependency needs a reference to the service locator.
```objective-c
[serviceLocator registerServiceWeak:serviceObject forProtocol:@protocol(DependencyProtocol)];
```
* Weak proxy registration - container maintains and returns a weak proxy (a proxy that has a weak reference to the actual dependency). In some rare cases it is necessary to ensure that neither container nor any of the objects obtaining a dependency have a strong reference to that dependency. An example of such use case <here>.
```objective-c
[serviceLocator registerServiceProxyWeak:serviceObject forProtocol:@protocol(DependencyProtocol)];
```

#### Resolving a dependency:
To resolve a dependency, call:
```objective-c
id<DependencyProtocol> dependency = [serviceLocator serviceForProtocol:@protocol(DependencyProtocol)];
```
An exception will be thrown if a dependency was not found in the container.
At this stage no information is given about the way dependency was registered.

#### Hierarchical containers:
It is often necessary to create scoped dependencies - limited in either visibility or lifetime. A couple of examples:

* a workflow of 5 views shown one after another where view controllers depend on services that are only used in that workflow - dependencies limited to the lifetime of the workflow;
* partner integration component needs to send network requests differently (with different authorization mechanism and parameters), no other part of the application should be making requests that way - dependencies limited in visibility.

Hierarchical containers provide this ability. A dependency container that has a parent attempts to resolve a dependency within itself, if that fails - tries to do it in its parent, and so on until a dependency is resolved or root is reached. A child container is, in effect, a scope that can be limited in time or visibility, and can cover some dependencies from higher levels of the hierarchy. Root container typically serves as global.

### Data Request Service
Data Request Service is a generic service for making HTTP requests. It combines the convenience of making simple requests with one method call and the power of customizing requests with a request builder.
Features include:
* Single-call data requests, such as `GET` or `POST`;
* Customizable requests, including downloads and multipart, using a builder;
* Thread-safe: requests can be submitted from any thread, cliens can specify a queue where callbacks should be invoked;
* Security features like certificate pinning, unified policy for other services like streaming, and unsafe request making for resources that don't require protection;
* Full deserialization to type-safe models;
* Support for multiple MIME types; support for custom MIME type handlers coming up;
* Reachability tracking;
* Basic support for environment switching.

#### Getting started with Data Request Service
Data request service requires an Environment Service - an object that implements `SEEnvironmentService` protocol. The only requirements to that object are that it returns a valid base URL for network requests and posts a notification if an environment changes. 
If environment switching is not required, Environment Service may just return a constant URL.
Now an instance of the data request service can be created - typically there is just one per application:
```objective-c
// Obtain an instance of environment service
id<SEEnvironmentService> environmentService = ...;
// Choose your session configuration
NSURLSessionConfiguration *sessionConfig = ...; 
// Choose certificate pinning type
SEDataRequestCertificatePinningType pinningType = ...; // None, certificate, public key
// Instantiate a data request service
id<SEDataRequestService> dataRequestService = [[SEDataRequestServiceImpl alloc] initWithEnvironmentService:environmentService sessionConfiguration:sessionConfig pinningType:pinningType applicationBackgroundDefault:NO];
```

#### Making simple data requests
Simple data requests can be made using various convenience methods like `GET:...`, `POST:...` or `PUT:...`, for example:
```objective-c
id<SECancellableToken> requestToken = [dataRequestService GET:@"endpoint_path" parameters:@{ @"param": @"value" } success:^(id  _Nullable data, NSURLResponse * _Nonnull response) {
            // Handle successful response
        } failure:^(NSError * _Nonnull error) {
            // Handle failure
        } completionQueue:dispatch_get_main_queue()];
```
Request methods return a token that can be used to track or cancel a request later.
If the request above completes successfully, success callback is invoked with `data` deserialized to generic types based on MIME type. For example, for `application/json` it might be an instance of `NSDictionary`.

#### Deserializing data to models
To deserialize a JSON response all the way to a type-safe model, a class of that model needs to conform to `SEDataRequestJSONDeserializable` protocol, as in the example below:
```objective-c
@interface MyDataModel : NSObject<SEDataRequestJSONDeserializable>
@end

@implementation MyDataModel
+ (nullable instancetype) deserializeFromJSON: (nonnull NSDictionary *) json
{
    // perform the deserialization
    return model;
}
@end
```
Then a request that will fully deserialize the response can be made:
```objective-c
id<SECancellableToken> requestToken = [dataRequestService GET:@"endpoint_path" parameters:@{ @"param": @"value" } deserializeToClass:[MyDataModel class]  success:^(id  _Nullable data, NSURLResponse * _Nonnull response) {
            // Handle successful response
        } failure:^(NSError * _Nonnull error) {
            // Handle failure
        } completionQueue:dispatch_get_main_queue()];
```
If this request succeeds, `data` returned in the callback is an instance of `MyDataModel` or an array of those instances if the JSON was an array.

#### Downloading data
A download request is just a `GET` request that stores the data on disk as opposed to fetching the data in memory. Downloading data is useful for images, documents and other kinds of user content.
Here's how a download request looks like:
```objective-c
NSURL *localFileURL = ...; // obtain a local file URL - for example, in a documents directory.
id<SECancellableToken> requestToken = [dataRequestService download:@"content_path" parameters:@{...} saveAs:localFileURL success:^(id  _Nullable data, NSURLResponse * _Nonnull response) {
        // Handle successful response
    } failure:^(NSError * _Nonnull error) {
        // Handle failure
    } progress:^(int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpected) {
        // handle progress if needed 
    } completionQueue:dispatch_get_main_queue()];
```

#### Building more complex requests
When a data request requires more fine-grained settings, data request builder can be used.
1. Create a request builder:
```objective-c
id<SEDataRequestBuilder> builder = [dataRequestService createRequestBuilder];
```
2. Define required request attributes, such as method and callbacks:
```objective-c
id<SEDataRequestCustomizer> request = [builder POST:@"endpoint_path" success:^(id  _Nullable data, NSURLResponse * _Nonnull response) {
        // handle successful response, same way as with simple requests
    } failure:^(NSError * _Nonnull error) {
        // handle error
    } completionQueue:dispatch_get_main_queue()]
```
3. Customize the request parameters. A few examples:
⋅⋅* Set model class to deserialize the response (works the same way as with simple methods).
```objective-c
[request setDeserializeClass:[MyDataModel class]];
```
⋅⋅* Set content encoding
```objective-c
[request setContentEncoding:encoding];
```
⋅⋅* Set headers
```objective-c
[request setHTTPHeader:@"Header-value" forkey:@"Header-Name"];
```
⋅⋅* Set request body
[request setBodyParameters:@{ @"parameter": @"value" }];
⋅⋅* Attach multipart content
There are a few ways to attach multipart content, depending on content type:
For arbitrary data:
```objective-c
[request appendPartWithData:data name:@"part-name" fileName:@"file-name-or-nil" mimeType:@"application/pdf" error:&error];
```
For JSON content:
```objective-c
[request appendPartWithJSON:json name:@"part-name" error:&error];
```
For files on device:
```objective-c
NSURL *fileURL = ...; // local file URL
[request appendPartWithFileURL:fileURL name:@"part-name" error:&error];
```

### Persistence Service
*Coming up*

### Service-Oriented Approach
*Coming up*

### Credits
* This project uses [OCMock](http://ocmock.org), a great framework for creating mocks in all kinds of tests.
* This project uses a few modified code pieces and a number of ideas from [AFNetworking](https://github.com/AFNetworking/AFNetworking).
* An idea to implement a version of Service Locator came from [Nikita Leonov](https://github.com/nikita-leonov/NLServiceLocator).
* My first experience with Service Location and service-oriented applications came from [Microsoft Prism](https://msdn.microsoft.com/en-us/library/ff921142.aspx), it was very useful at the time.

### License
Service Essentials are released under the BSD license. See LICENSE for details.
