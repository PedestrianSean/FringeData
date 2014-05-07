//
//  FringeDataUtils.h
//
//  Created by Sean Meiners on 2012/10/04.
//  Copyright (c) 2012 Sean Meiners. All rights reserved.
//
//

#import <Foundation/Foundation.h>

@class FringeObject;
@class FringeObjectStore;

extern NSString *const kFringeDataItemDeleted;

/**
 */
@interface NSArray (FringeObject)

/**
 Return the index of `anObject` comparing them by UUID
 @param anObject The FringeObject to search for.
 @return The index of `anObject` or NSNotFound.
 */
- (NSUInteger)indexOfFringeObject:(FringeObject*)anObject;

@end

/**
 */
@interface NSOrderedSet (FringeObject)

/**
 Return the index of `anObject` comparing them by UUID
 @param anObject The FringeObject to search for.
 @return The index of `anObject` or NSNotFound.
 */
- (NSUInteger)indexOfFringeObject:(FringeObject*)anObject;

@end

/**
 Helper methods.
 */
@interface FringeDataUtils : NSObject

/**
 Saves any changes by calling `[[object store] commit:NULL]`
 @param object The object to save
 @return `YES` on success, `NO` otherwise.
 @warning This will also save all changes to any FringeObjects that share the same FringeObjectStore
 */
+ (BOOL)save:(FringeObject*)object;

/**
 Gets all root FringeObjects at `path`. Generally used on an index directory.
 @param path The directory to scan for FringeObjects
 @param limit the maximum number of FringeObjects to return. Order is not guarenteed. Send 0 to retrieve all objects.
 @return An array of the objects found, possibly empty, never nil
 */
+ (NSArray*)rootObjectsAtPath:(NSURL*)path limit:(NSUInteger)limit;

/**
 Gets all root FringeObjects at `paths`. Useful for multi-index lookups.
 @param paths The directories (as NSString*) to scan for FringeObjects
 @param limit the maximum number of FringeObjects to return. Order is not guarenteed. Send 0 to retrieve all objects.
 @return An array of the objects found, possibly empty, never nil
 */
+ (NSArray*)rootObjectsAtAllPaths:(NSArray*)paths limit:(NSUInteger)limit;

/**
 Removes `object` from its FringeObjectStore. If `object` is the root object, the store will be deleted.
 @param object The object to delete.
 @return `YES` on success, `NO` otherwise.
 */
+ (BOOL)deleteObject:(FringeObject*)object;

@end
