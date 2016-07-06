## Service Essentials
Service Essentials help build complex, extensible applications. They do it by promoting service-oriented architecture, which decreases coupling, improves testability and reduces unwanted complexity.
More about the approach and its advantages in the [Service-Oriented Approach](../master/README.md#service-oriented-approach) section.

*Service Essentials include these basic building blocks:*
* Service Locator to register and find services in the application.
* Data Request Service to make network requests
* Persistence Service to manage persistent data in Core Data storage. 

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

* a workflow of 5 views shown one after another needs depends on services that are only used in that workflow - dependencies limited to the lifetime of the workflow;
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
