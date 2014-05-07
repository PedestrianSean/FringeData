//
//  FringeObject.h
//
//  Created by Sean Meiners on 2012/10/01.
//  Copyright (c) 2012 Sean Meiners. All rights reserved.
//
//

#import <Foundation/Foundation.h>

extern NSString *fringedata_makeFileNameSafe(NSString *key);
extern NSString *fringedata_makeFileNameUnSafe(NSString *key);

/**
 Like NSManagedObject, this class will dynamically create the property
 getters and setters for any @property you declare as @dynamic.
 Like NSManagedObject, most objects will get a standard getter and setter
 only, but properties of types NSSet and NSOrderedSet will also cause
 the following methods to be generated:

 For an NSSet property named 'foo', implements the following:
 
    - (NSSet*)foos;
    - (NSUInteger)foosCount;
    - (void)setFoos:(NSSet*)foos;

    - (void)addFoosObject:(Foo *)value;
    - (void)addFoos:(NSSet *)values;

    - (void)removeFoosObject:(Foo *)value;
    - (void)removeFoos:(NSSet *)values;

 For an NSOrderedSet property named 'foo', implements the following:

    - (NSOrderedSet*)foos;
    - (NSUInteger)foosCount;
    - (Foo *)foosAtIndex:(NSUInteger)index;
    - (NSOrderedSet*)foosAtIndexes:(NSIndexSet*)indexes;
    - (void)setFoos:(NSOrderedSet*)foos;

    - (void)addFoosObject:(Foo *)value;
    - (void)addFoos:(NSOrderedSet *)values;

    - (void)removeFoosObject:(Foo *)value;
    - (void)removeFoos:(NSOrderedSet *)values;

    - (void)insertObject:(Foo *)value inFoosAtIndex:(NSUInteger)idx;
    - (void)insertFoos:(NSArray *)value atIndexes:(NSIndexSet *)indexes;

    - (void)replaceObjectInFoosAtIndex:(NSUInteger)idx withObject:(Foo *)value;
    - (void)replaceFoosAtIndexes:(NSIndexSet *)indexes withFoos:(NSArray *)values;

    - (void)removeObjectFromFoosAtIndex:(NSUInteger)idx;
    - (void)removeFoosAtIndexes:(NSIndexSet *)indexes;

  */
@class FringeObjectStore;

NS_REQUIRES_PROPERTY_DEFINITIONS
@interface FringeObject : NSObject

/** The store this object belongs to */
@property (nonatomic, readonly) FringeObjectStore *fringeObjectStore;

/** This object's UUID, this will never change */
@property (nonatomic, readonly) NSString *uuid;

/**
 The default implementation returns `nil`. This must be implmented for any root object.
 @return The directory (as a file:// URL) where objects of this type should be stored.
 */
+ (NSURL*)defaultCommitPath;
/**
 The default implementation returns `nil`. This should be implmented for any root object.
 @return the (NSString*) names of the properties that should be indexed.
 */
+ (NSSet*)indexedPropertyNames;
/**
 The default implementation returns `nil`. This should be implmented for any root object.
 @param name The name of the property that will be indexed.
 @param value The value of the property.
 @param object The FringeObject the property belongs to.
 @return The path (as a file:// URL) to where the index for the specified property should be stored.
*/
+ (NSURL*)indexURLForProperty:(NSString*)name withValue:(id)value forObject:(FringeObject*)object;

/**
 This is the method you should override this instead of init (aka the common initializer)
*/
- (void)setDefaultValues;

/**
 Only use this method when creating a root object that implements defaultCommitPath.
 A FringeObjectStore will be automatically created for you.
 */
- (id)init;

/**
 Use this method when creating a non-root object, or when creating a root object and you already have a FringeObjectStore to add it to.
 @param store The FringeObjectStore to which this object belongs
 */
- (id)initWithStore:(FringeObjectStore*)store;

/**
 Primarily for internal use only. Can be overridden to modify the dictionary on creation.
 @param dictionary The NSDictionary that contains the values parsed from the FringeObjectStore
 @param store The FringeObjectStore to which this object belongs
 */
- (id)initWithDictionary:(NSDictionary*)dictionary inStore:(FringeObjectStore*)store;

/**
 Primarily used by FringeObjectStore for commiting the object to disk.
 */
- (id)proxyForJson;

/**
 Useful when you need to override the default getter or when you want to bypass the built-in type conversion.
 @param name The name of the property to retrieve
 @return The raw value of property `name`
 */
- (id)getProperty:(NSString*)name;

/**
 Useful when you need to override the default setter or when you want to bypass the built-in type conversion.
 @param name The name of the property to set
 @param value The raw value of property `name`
 */
- (void)setProperty:(NSString*)name value:(id)value;

@end
