//
//  FringeObject.h
//
//  Created by Sean Meiners on 2012/10/01.
//  Copyright (c) 2012 Sean Meiners. All rights reserved.
//
//

#import <Foundation/Foundation.h>

extern NSString *makeFileNameSafe(NSString *key);
extern NSString *makeFileNameUnSafe(NSString *key);

@class FringeObjectStore;

NS_REQUIRES_PROPERTY_DEFINITIONS
@interface FringeObject : NSObject

@property (nonatomic, readonly) FringeObjectStore *fringeObjectStore;

@property (nonatomic, readonly) NSString *uuid;

+ (NSURL*)defaultCommitPath;
+ (NSSet*)indexedPropertyNames;
+ (NSURL*)indexURLForProperty:(NSString*)name withValue:(id)value forObject:(FringeObject*)object;

- (void)setDefaultValues; // override this instead of init

- (id)initWithStore:(FringeObjectStore*)store;
- (id)initWithDictionary:(NSDictionary*)dictionary inStore:(FringeObjectStore*)store;

- (id)proxyForJson;

- (id)getProperty:(NSString*)name;
- (void)setProperty:(NSString*)name value:(id)value;

/* For NSSet properties, implements the following:
 
 - (NSSet*)foos;
 - (NSUInteger)foosCount;
 - (void)setFoos:(NSSet*)foos;

 - (void)addFoosObject:(Foo *)value;
 - (void)addFoos:(NSSet *)values;

 - (void)removeFoosObject:(Foo *)value;
 - (void)removeFoos:(NSSet *)values;
*/

 /* For NSOrderedSet properties, implements the following:

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

@end
