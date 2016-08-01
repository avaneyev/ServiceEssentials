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

### Service-Oriented Approach
**Service-oriented approach** is a way of representing the MVC application model level as a combination of services and data, where services are active components (they perform operations) and data is passive and only used to be passed around and stored. In a lot of ways services are similar to API endpoints.
**Services have the following attributes:**
* _Defined by contract_. A service has a contract (protocol that a service conforms to) and that is the only thing that is needed to consume a service. That is similar to API contract defining a URL, method and parameters.
* _Discoverable_. A service can be found by its definition. [Service Locator](../master/README.md#service-locator) allows finding a registered implementation for a service contract. That is similar to URL.
* _Domain-specific_. A service implements a set of functionality that belongs to a certain domain. An application can have multiple domains, such as users, authentication, persistence, as well as those more specific to the application. That is similar to REST URLs and paths that specify different domains of objects and operations.
* _Stackable_. A service may depend on other services. More specifically, a more specialized service may depend on more generic services. For example, application-specific services may depend on the network stack (data request service) and persistence.
* _Testable_. Since services are defined by contract and not by implementation, it is easy to substitute real implementations with mocks for unit or integration tests.
* It is recommended that services are _stateless_ - for example, they query the data and transform it in a domain-specifc way or perform an operation and pass the data further down the stack, which eventually leads to a network request or persistence.
* It is recommended that data accepted and returned by the services is _immutable_. That makes data thread-safe (since an object cannot be modified it does not need synchronization), reduces the issues of ownership (which object is responsible for handling mutations and how does it detect them), and helps make code more robust and testable (mutations may be hard to debug and even harder to account for in tests; immutable objects are plain and simple).

Service-oriented approach has many benefits. It helps keep complexity under control, improves quality through testability and better organization of the code and is easily understood by most engineers from different backgrounds.

### Service Locator
Service Locator is a dependency injection container. It has two main features: register a dependency and resolve a dependency. All service identification is based on protocols.
Service Locator is implemented by the `SEServiceLocator` class.
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

Data Request Service interface is defined in the `SEDataRequestService` protocol, the implementation is provided by the `SEDataRequestServiceImpl` class.

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
###### 1. Create a request builder:
```objective-c
id<SEDataRequestBuilder> builder = [dataRequestService createRequestBuilder];
```
###### 2. Define required request attributes, such as method and callbacks:
```objective-c
id<SEDataRequestCustomizer> request = [builder POST:@"endpoint_path" success:^(id  _Nullable data, NSURLResponse * _Nonnull response) {
        // handle successful response, same way as with simple requests
    } failure:^(NSError * _Nonnull error) {
        // handle error
    } completionQueue:dispatch_get_main_queue()]
```
###### 3. Customize the request parameters. A few examples:
* Set model class to deserialize the response (works the same way as with simple methods).
```objective-c
[request setDeserializeClass:[MyDataModel class]];
```
* Set content encoding
```objective-c
[request setContentEncoding:encoding];
```
* Set headers
```objective-c
[request setHTTPHeader:@"Header-value" forkey:@"Header-Name"];
```
* Set request body
```objective-c
[request setBodyParameters:@{ @"parameter": @"value" }];
```
* Attach multipart content
There are a few ways to attach multipart content, depending on content type.
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
###### 4. Submit the request
Use either
```objective-c
id<SECancellableToken> requestToken = [request submit];
```
or
```objective-c
id<SECancellableToken> requestToken = [request submitAsUpload:YES];
```
First version determines how to send a request (as an upload or not) on its own. The second allows specifying it explicitly.
Upload requests are only supported for methods that have body (`POST` and `PUT`), and theoretically can be used with a background session.

### Persistence Service
Persistence Service is a generic service for storing data in Core Data. It does most of the heavy lifting when performing CRUD operations (create, read, update, delete).
Features include:
* Simple methods for one-line CRUD operations;
* Synchronous and asynchronous versions;
* Multiple contexts through hierarchical service instances;
* Customizable update propagation;
* Transforms.

#### Persistence Service basics
* Persistence Service instances correspond to Managed Object Contexts and are hierarchical same way as Managed Object Contexts are. Root instance is backed by a context that is associated with a persistent store and child instances are backed by nexted contexts and may be used for main queue operations or worker contexts.

* All methods that manipulate records have 2 versions: synchronous and asynchronous. 
  * Asynchronous version takes a pair of callbacks (`success` and `failure`) and a queue that will be used to invoke the callbacks. 
  * Synchronous version has a word `Wait` in the method name to highlight the fact that it will block the current thread and wait until the method completes. It returns `YES` if the operation succeeds or `NO` if it fails. In case of failure an error may be returned to the autoreleasing `error` parameter. For an example, see [Creating records](../master/README.md#creating-records)

* *Transforms* are a way of preventing Managed Objects from travelling across different components of the application. Using Managed Objects across the application usually implies the complexity of managing object mutability, their belonging to different contexts and non-trivial concurrency model. An alternative to that is to use transient (and preferrably read-only) objects across the application, loading data from managed objects to transient objects and storing transient object as managed. Simply put, *Transforms* are a single point of conversion between managed and transient objects for operations like *create* or *read*.

* Persistence options enum value (`SEPersistenceServiceSaveOptions`) is taken by every method that modifies the data. There are 3 possible values:
  * `SEPersistenceServiceDontSave` leads to any changes to not be saved. The changes are kept in the context and may be persisted later (explicitly or as part of another operation) or reverted.
  * `SEPersistenceServiceSaveCurrentOnly` causes the changes to be saved in the context that backs the service, but does not propagate the changes further (to a a context it is nested in or to a persistent store).
  * `SEPersistenceServiceSaveAndPersist` causes the changes to be saved to the context that backs the service and then all the way to persistent store.

* Persistence service interface is defined in the `SEPersistenceService` protocol, the implementation is provided by the `SEPersistenceServiceImpl` class.

#### Initialization
There are 2 ways to initialize a root persistence service.
First uses a *managed object model* object:
```objective-c
- (nonnull instancetype)initWithDataModel:(nonnull NSManagedObjectModel *)dataModel storePath:(nonnull NSString *)storePath;
```
Second uses a *managed object model name*:
```objective-c
- (nonnull instancetype)initWithDataModelName:(nonnull NSString *)dataModelName storePath:(nonnull NSString *)storePath;
```
The first is most useful when a model is created at runtime in memory, the second is for loading the managed object model files (`*.momd`).
Here's an example:
```objective-c
NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
NSString *documentsDirectory = [paths objectAtIndex:0];
NSString *coreDataPath = [documentsDirectory stringByAppendingPathComponent:@"MyDataModel.sqlite"];
SEPersistenceServiceImpl *persistenceService = [[SEPersistenceServiceImpl alloc] initWithDataModelName:@"MyDataModel" storePath:coreDataPath];
```
**Note:** the persistent service initializes asynchronously to avoid blocking the calling thread. The initialization may be time consuming, since it may need to create or migrate the physical store. When the service is initialized and ready to be used, `isInitialized` flag is set to `YES`. Performing any operations on an uninitialized service causes an exception.

There are a couple of methods to create child service instances, first creates a service backed by a main queue context and second creates a service backed by a private queue:
```objective-c
- (nonnull id<SEPersistenceService>)createChildPersistenceServiceWithMainQueueConcurrency;
- (nonnull id<SEPersistenceService>)createChildPersistenceServiceWithPrivateQueueConcurrency;
```

If explicit nested Managed Object Contexts are needed, there are methods to create them as well:
```objective-c
- (nonnull NSManagedObjectContext *)createChildContextWithMainQueueConcurrency;
- (nonnull NSManagedObjectContext *)createChildContextWithPrivateQueueConcurrency;
```
**Note:** a child persistence service instance is considered initialized only when its parent is initialized.

#### Creating Records
There are two ways to create records with Persistence Service: individually or by transforming objects.
* Creating an individual record requires an object class (which **must** be a subclass of `NSManagedObject`) and an initializer block which should assign initial values to the newly created object. The method accept two additional parameters: `obtainPermanentId` determines if permanent ID should be obtained when creating an object in case it is needed for future reference, otherwise a temporary ID will be assigned to the object until it is persisted; `saveOptions` define how the result of the operation is persisted (see [basics](../master/README.md#persistence-service-basics) for details).
**Note:** Initializer is invoked on the managed context queue.
  * Asynchronous:
  ```objective-c
  [_persistenceService createObjectOfType:[MyManagedObject class] obtainPermanentId:NO initializer:^(MyManagedObject * _Nonnull instance) {
    // Initializing the newly created instance, for example assign a couple of fields
    instance.field1 = @"Value 1";
    instance.field2 = 2;
  } saveOptions:SEPersistenceServiceSaveAndPersist success:^{
    // handling successful object creation
  } failure:^(NSError * _Nonnull error) {
    // handling failure
  } completionQueue:dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0)];
  ```
  * Synchronous:
  ```objective-c
  NSError *error = nil;
  BOOL result = [_persistenceService createAndWaitObjectOfType:[MyManagedObject class] obtainPermanentId:NO initializer:^(MyManagedObject * _Nonnull instance) {
    // Initializing the newly created instance, for example assign a couple of fields
    instance.field1 = @"Value 1";
    instance.field2 = 2;
  } saveOptions:SEPersistenceServiceSaveAndPersist error:&error];
  ```
  
* Creating records by transforming objects is an easy way to create any number of objects of the same type from other objects (usually non-managed). Transforms take in an array of objects to transform and an initializer block that takes in an individual original object and its managed counterpart that is being created. Initializer block is invoked once for each object in the array.
  * Asynchronous:
  ```objective-c
  NSArray *people = @[ @"Alice", @"Bob", @"Carl" ];
  [_persistenceService createObjectOfType:[Person class] byTransformingObjects:people withTransform:^(NSString * _Nonnull name, Person * _Nonnull instance) {
    // Initializing the newly created instance, for example assign a field.
    instance.name = name;
  } saveOptions:SEPersistenceServiceSaveAndPersist success:^{
    // handling successful object creation
  } failure:^(NSError * _Nonnull error) {
    // handling failure
  } completionQueue:dispatch_get_main_queue()];
  ```
  * Synchronous:
  ```objective-c
  NSError *error = nil;
  NSArray *tags = @[ @"AAA1111", @"BBB2222", @"CCC3333" ];
  BOOL result = [_persistenceService createAndWaitObjectOfType:[Vehicle class] byTransformingObjects:tags withTransform:^(NSString * _Nonnull tag, Vehicle * _Nonnull instance) {
    // Initializing the newly created instance, for example assign a field.
    instance.tag = tag;
  } saveOptions:SEPersistenceServiceSaveAndPersist error:&error];
  ```
  
#### Fetching Records (Read-Only)
There are three ways to read the data provided by the Persistence Service: fetch-transform, fetch with manual processing, and fetch by IDs with manual processing.
**Warning:** Managed objects that are sent to processing blocks are mutable (as normal managed objects), but the service is going to make best effort to detect if objects were modified, and will raise an error in that case. Methods capble of fetching and updating records should be used if objects need to be modified. See [Updating Records](../master/README.md#updating-records-fetch-for-writing).
* *Fetch-transform* is the opposite of create transform. It allows fetching records and simultaneously transforming them to objects of a different kind so that they have no relation to the managed store and can be used across the application. Fetch-transform takes in an object class (which **must** be a subclass of `NSManagedObject`), optional fetch parameters, and a transform block which takes in an object of requested class and returns a transformed object. Transform is invoked for each fetched object on the managed context queue. The result of the operation is an array of transformed objects.
  * Asynchronous:
  ```objective-c
  // Create fetch parameters with a predicate
  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"...", ];
  SEFetchParameters *parameters = [SEFetchParameters fetchParametersWithPredicate:predicate];
  // Suppose there is a managed object class Person (a subclass of NSManagedObject),
  // and for each person we need a FullName object (not managed, subclass of NSObject),
  // which consists of first name and last name.
  // This example shows that a transform can be to any kind of object, not just strings or numbers.
  [_persistenceService fetchTransformObjectsOfType:[Person class] fetchParameters:parameters transform:^id _Nonnull(Person * _Nonnull person) {
    return [[FullName alloc] initWithFirstName:person.firstName lastName:person.lastName];
  } success:^(NSArray<FullName *> * _Nonnull results) {
    // handle the results, they are transformed objects at this point
  } failure:^(NSError * _Nonnull error) {
    // handle an error
  } completionQueue:dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)];
  ```

  * Synchronous:
  ```objective-c
  // Create fetch parameters
  SEFetchParameters *parameters = ...;
  NSError *error = nil;
  NSArray<FullName *> *results = [_persistenceService fetchAndWaitTransformObjectsOfType:[Person class] fetchParameters:parameters transform:^id _Nonnull(Person * _Nonnull person) {
    return [[FullName alloc] initWithFirstName:person.firstName lastName:person.lastName];
  } error:&error];
  ```
  
* Fetch with manual processing takes in an object class, an optional fetch parameters and a block for processing results, but, unlike fetch-transform, the block gets an array of managed object (all fetch results), and those results may be processed as needed.
  * Asynchronous:
  ```objective-c
  // For example, we need the earliest manufacture year of all cars satisfying a predicate
  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"...", ];
  // Create parameters that include the predicate and sort by the year
  SEFetchParameters *parameters = [SEFetchParameters fetchParametersWithPredicate:predicate sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"modelYear" ascending:YES];
  __block NSInteger earliestYear = MAX_INT;
  [_persistenceService fetchReadOnlyObjectsOfType:[Car class] fetchParameters:parameters fetchedObjectProcessor:^(NSArray<Car *> * _Nonnull cars) {
    Car *earliest = cars.firstObject;
    earliestYear = earliest ? earliest.modelYear : MAX_INT;
  } success:^() {
    // handle the success, there are no explicit results, only what was captured in fetch processor.
    NSLog(@"Earliest year a car was made: %li", (long)earliestYear);
  } failure:^(NSError * _Nonnull error) {
    // handle an error
  } completionQueue:dispatch_get_main_queue()];
  ```

  * Synchronous:
  ```objective-c
  // For example, need a total number of cars satisfying a predicate
  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"...", ];
  SEFetchParameters *parameters = [SEFetchParameters fetchParametersWithPredicate:predicate];
  __block NSUInteger count = 0;
  NSError *error = nil;
  BOOL result = [_persistenceService fetchReadOnlyAndWaitObjectsOfType:[Car class] fetchParameters:parameters fetchedObjectProcessor:^(NSArray<Car *> * _Nonnull cars) {
    count = cars.count;
  } error:&error];
  ```
  
* Fetch by IDs is similar to other kinds of fetch, but instead of taking in an object class and fetch parameters it takes in a list of object IDs. 
  * Asynchronous:
  ```objective-c
  // Suppose there are two objects that need to be fetched:
  NSManagedObjectID *firstObject = ...;
  NSManagedObjectID *secondObject = ...;
  [_persistenceService fetchReadOnlyObjectsByIds:@[ firstObject, secondObject ] fetchedObjectProcessor:^(NSArray<NSManagedObject *> * _Nonnull objects) {
    // do what's needed with the objects.
  } success:^() {
    // handle the success, there are no explicit results, only what was captured in fetch processor.
  } failure:^(NSError * _Nonnull error) {
    // handle an error
  } completionQueue:dispatch_get_main_queue()];
  ```

  * Synchronous:
  ```objective-c
  NSManagedObjectID *firstObject = ...;
  NSManagedObjectID *secondObject = ...;
  NSError *error = nil;
  BOOL result = [_persistenceService fetchReadOnlyAndWaitObjectsByIds:@[ firstObject, secondObject ] fetchedObjectProcessor:^(NSArray<NSManagedObject *> * _Nonnull objects) {
    // do what's needed with the objects.
  } error:&error];
  ```

#### Updating Records (Fetch for Writing)
Updating records is very similar to reading them. The difference is that there is no transform - only manual update is available - and preocessing blocks now have a return value that determines how the changes should be persisted. For available persistence options see [basics](../master/README.md#persistence-service-basics)

There are two ways to select records for updating - with a query and with a list of record IDs.
* Updating records with a query takes the same parameters as read-only fetch does - object class and optional query parameters.
  * Asynchronous:
  ```objective-c
  SEFetchParameters *parameters = [SEFetchParameters ...];
  [_persistenceService fetchObjectsOfType:[Car class] fetchParameters:parameters fetchedObjectProcessor:SEPersistenceServiceSaveOptions^(NSArray<Car *> * _Nonnull cars) {
    for (Car *car in cars) 
    {
      car.needsMaintenance = YES;
    }
    return SEPersistenceServiceSaveAndPersist;
  } success:^() {
    // handle the success, there are no explicit results, only what was captured in fetch processor.
  } failure:^(NSError * _Nonnull error) {
    // handle an error
  } completionQueue:dispatch_get_main_queue()];
  ```

  * Synchronous:
  ```objective-c
  SEFetchParameters *parameters = [SEFetchParameters ...];
  NSError *error = nil;
  BOOL result = [_persistenceService fetchAndWaitObjectsOfType:[Car class] fetchParameters:parameters fetchedObjectProcessor:^(NSArray<Car *> * _Nonnull cars) {
    // Perform the updates.
  } error:&error];
  ```

* Updating records with a list of record IDs is also similar to its fetch counterpart. It takes a list of IDs and a processing block.
  * Asynchronous:
  ```objective-c
  // For example, a particular car just underwent maintenance
  NSManagedObjectID *aCarId = ...;
  [_persistenceService fetchObjectsByIds:@[ aCarId ] fetchedObjectProcessor:^(NSArray<Car *> * _Nonnull cars) {
    cars.firstObject.needsMaintenance = NO;
    return SEPersistenceServiceSaveCurrentOnly;
  } success:^() {
    // handle the success, there are no explicit results, only what was captured in fetch processor.
  } failure:^(NSError * _Nonnull error) {
    // handle an error
  } completionQueue:dispatch_get_main_queue()];
  ```

  * Synchronous:
  ```objective-c
  NSManagedObjectID *firstObject = ...;
  NSManagedObjectID *secondObject = ...;
  NSError *error = nil;
  BOOL result = [_persistenceService fetchReadOnlyAndWaitObjectsByIds:@[ firstObject, secondObject ] fetchedObjectProcessor:^(NSArray<NSManagedObject *> * _Nonnull objects) {
    // make necessary updates
    return SEPersistenceServiceDontSave;
  } error:&error];
  ```

#### Deleting Records
Deleting records can be done by query or by a list of IDs, same way as fetch absent processing blocks.
* By query:
  * Asynchronous:
  ```objective-c
  SEFetchParameters *parameters = [SEFetchParameters ...];
  [_persistenceService deleteObjectsOfType:[Person class] fetchParameters:parameters saveOptions:SEPersistenceServiceSaveAndPersist success:^() { ... } failure:^(NSError * _Nonnull error) { ... } completionQueue:dispatch_get_main_queue()]];
  ```
  
  * Synchronous:
  ```objective-c
  SEFetchParameters *parameters = [SEFetchParameters ...];
  NSError *error = nil;
  BOOL result = [_persistenceService deleteObjectsAndWaitOfType:[Person class] fetchParameters:nil saveOptions:SEPersistenceServiceSaveAndPersist error:&error];
  ```
  
* By list of object IDs:
  * Asynchronous:
  ```objective-c
  // Don't specify any of the callbacks or a queue. 
  // This is a "submit and forget" kind of request, where request is put on the queue and the execution returns immediately.
  NSManagedObjectID *objectId = ...;
  [_persistenceService deleteObjectsByIds:@[ objectId ] saveOptions:SEPersistenceServiceSaveAndPersist success:nil failure:nil completionQueue:nil];
  ```
  * Synchronous:
  ```objective-c
  NSError *error = nil;
  BOOL result = [_persistenceService deleteObjectsAndWaitByIds:@[ objectId ] saveOptions:SEPersistenceServiceSaveAndPersist error:&error];  
  ```

#### Explicitly Committing or Reverting Changes
Each mutating operation specifies a way its changes should be persisted. That makes persistence very flexible and performant.
For example:
* Transactions consisting of a number of related operations are possible. Operations should be performed with no persistence, and explicitly committed in the end. If one of the operations fails, they can all be reverted.
* Worker instances can perform and persist changes locally and periodically submit them to persistent store.
* Critical operation results may me persisted all the way to a backing store. The operation will not succeed until the change makes it all the way to the store.

##### Saving changes:
  * Asynchronous:
  
  ```objective-c
  [_persistenceService saveAllWithOptions:SEPersistenceServiceSaveAndPersist success:^{ ... } failure:^(NSError * _Nonnull error) { ... } completionQueue:dispatch_get_main_queue()];
  ```
  * Synchronous:
  
  ```objective-c
  NSError *error = nil;
  BOOL result = [_persistenceService saveAllAndWaitWithOptions:SEPersistenceServiceSaveAndPersist error:&error];  
  ```
  
##### Reverting changes
  * Asynchronous:
  
  ```objective-c
  [_persistenceService rollbackWithCompletion:^{ ... } completionQueue:dispatch_get_main_queue()];
  ```
  * Synchronous:
  
  ```objective-c
  [_persistenceService rollbackAndWait];  
  ```

### Credits
* This project uses [OCMock](http://ocmock.org), a great framework for creating mocks in all kinds of tests.
* This project uses a few modified code pieces and a number of ideas from [AFNetworking](https://github.com/AFNetworking/AFNetworking).
* An idea to implement a version of Service Locator came from [Nikita Leonov](https://github.com/nikita-leonov/NLServiceLocator).
* My first experience with Service Location and service-oriented applications came from [Microsoft Prism](https://msdn.microsoft.com/en-us/library/ff921142.aspx), it was very useful at the time.

### License
Service Essentials are released under the BSD license. See LICENSE for details.
