FringeData
==========

An easy-to-use replacement for CoreData

CoreData is a pretty cool framework. I've had many uses for it and it's generally served my needs well.
However, a while back I was working on a heavily-threaded application where the objects needed to
be modified in a background processing thread as well as the UI thread. To do this in CoreData and not
have it eventually throw an exception required so much locking that my app became unusably slow.
And thus FringeData was born. It was designed from the start to strike a balance between memory usage, speed,
and thread-safety. You can safely read and write to a FringeDataObject from multiple threads and never have
to worry about locking (it's handled for you). Also, since it uses JSON formatted files for its backing store
it's trivial to add or remove properties from your FringeDataObject derived objects.

Features
========
* Thread safe reads and writes.
* FringeDataObject mimics NSManagedObject, so you can continue to use @dynamic properties.
* Properly handles properties with the following types:
** BOOL
** char, int32, uint32, int64 & uint64
** float & double
** NSSet & NSOrderedSet
** NSData (will be Base64 encoded for storage)
** Any class inheriting from FringeObject
** Any class that has a NSValueTransformer implementation (named <class name>Transformer)
* Honors and enforces all @property decorators (e.g.: weak, atomic, getter=, etc).
* Only holds changed and recently accessed objects in memory in order to maintain a low footprint.
* JSON backed for human-readable data files and trivial property addition.
* FringeObjectStore(s) are reused, so there is never more than one instance representing a given backing store.
* Indexing is file-system based and is therefore somewhat limited until I come up with something better.

Requirements
============
* SBJSON 4

Examples
========

This implements a simple FringeObject type that supports indexing of two of its properties.
```objective-c
@interface MyObject : FringeObject

@property (nonatomic, strong) NSString* stringProperty;
@property (nonatomic, strong) NSDictionary *dictProperty;
@property (nonatomic, assign) float floatProperty;

@end

static NSString *const kMyBasePath = @"/tmp/MyObject";

@implementation MyObject

@dynamic stringProperty;
@dynamic floatProperty;

+ (NSURL*)defaultCommitPath {
    return [NSURL fileURLWithPath:[kMyBasePath stringByAppendingPathComponent:@"Data"];
}

+ (NSSet*)indexedPropertyNames {
  return [NSSet setWithArray:@[ @"stringProperty", @"floatProperty" ];
}

+ (NSURL*)indexURLForProperty:(NSString*)name withValue:(id)value forObject:(FringeObject*)object {
    NSString *pathFragment = nil;

    if( [name isEqualToString:@"stringProperty"] ) {
        NSString *first = [value substringToIndex:1];
        if( [first rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].location != NSNotFound )
            pathFragment = [@"FirstLetter" stringByAppendingPathComponent:[first uppercaseString]]];
    }

    else if( [name isEqualToString:@"floatProperty"] ) {
        float floatValue = [value floatValue];
        if( floatValue < 0.f )
            pathFragment = @"PosNeg/-1";
        else if( floatValue > 0.f )
            pathFragment = @"PosNeg/+1";
        else
            pathFragment = @"PosNeg/0";
    }
    
    if( pathFragment )
        return [NSURL fileURLWithPath:[kMyBasePath stringByAppendingPathComponent:pathFragment]];

    return nil;
}

@end
```

To create a few instances of the object you might:
```objective-c
 MyObject *obj;

 obj = [MyObject new];
 obj.stringProperty = @"An object";
 obj.floatProperty = -543.f;
 [FringeDataUtils save:obj];

 obj = [MyObject new];
 obj.stringProperty = @"Another object";
 obj.floatProperty = 432.f;
 [FringeDataUtils save:obj];

 obj = [MyObject new];
 obj.stringProperty = @"Yet another object";
 obj.floatProperty = -354.f;
 [FringeDataUtils save:obj];

```

And to find all the instances where stringProperty begins with 'a' and floatProperty is negative:
```objective-c
 NSArray *paths = @[ [MyObject indexURLForProperty:@"stringProperty" withValue:@"a" forObject:nil],
                       [MyObject indexURLForProperty:@"floatProperty" withValue:@-1.f forObject:nil]
                    ];
 NSArray *objects = [FringeDataUtils rootObjectsAtAllPaths:paths limit:0];

 NSLog(@"result: %@", objects); // should print "result: <MyObject [UUID] {stringProperty: \"An object\", floatProperty: -543.0, dictProperty: nil}>"
```
