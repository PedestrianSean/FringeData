//
//  FringeObjectStore.h
//
//  Created by Sean Meiners on 2012/10/01.
//  Copyright (c) 2012 Sean Meiners. All rights reserved.
//
//

#import <Foundation/Foundation.h>

@class FringeObject;

extern NSString *const kFringeObjectStoreFileExtension;
extern NSString *const kFringeDataErrorDomain;

/**
 These are the only valid values for [NSError code] when [NSError domain] is set to `kFringeDataErrorDomain`
 */
typedef NS_ENUM(NSUInteger, FringeDataErrorCode) {
    /** Returned when `commitPath` is `nil`, usually because the root object has not implemented [FringeObject defaultCommitPath] */
    FringeDataError_NoCommitPath = 1000,
    /** Returned when the root object is `nil` */
    FringeDataError_NoRootObject
} FringeDataErrorCode;

/**
 FringeObjectStore represents a single data file and N indexes. Each store contains exactly one root object, which in
 turn may contain several FringeObjects.
 */
@interface FringeObjectStore : NSObject

/**
 The path where this store will read and write its data.
 */
@property (nonatomic, readonly) NSString *commitPath;

/**
 Creates a new FringeObjectStore
 @param path The directory where the new store should read & write its data.
 @return A new FringeObjectStore instance.
 */
+ (FringeObjectStore*)storeWithPath:(NSString*)path;
/**
 Creates a new FringeObjectStore
 @param path The directory where the new store should read & write its data.
 @param uuid the UUID of the root object at `path`
 @return A new FringeObjectStore instance or `nil` if the `uuid` does not exist at `path`.
 */
+ (FringeObjectStore*)storeWithUUID:(NSString*)uuid atPath:(NSString*)path;
/**
 Creates a new FringeObjectStore
 @param root the root object for the store.
 @param path The directory where the new store should read & write its data.
 @return A new FringeObjectStore instance.
 */
+ (FringeObjectStore*)storeWithRootObject:(FringeObject*)root atPath:(NSString*)path;

/**
 Looks for and removed dead indexes.
 */
+ (void)cleanIndexes;

/**
 Moves the store to a new location.
 @param commitPath The path to the new directory where this store should read & write its data.
 @param error Set if there was a problem moving the store.
 @return `YES` on success, `NO` on failure.
 */
- (BOOL)setCommitPath:(NSString*)commitPath error:(out NSError**)error;

/**
 @return The current root object.
 */
- (id)rootObject;
/**
 Changes the root object for this store.
 @param rootObject The new root object.
 @return `NO` if the new root is already root for another store, `YES` otherwise.
 */
- (BOOL)setRootObject:(FringeObject*)rootObject;
/**
 @param uuid the UUID of the object to retrieve
 @return The FringeObject with `uuid` or `nil` if it could not be found.
 */
- (id)objectWithUUID:(NSString*)uuid;

/**
 Commits changes to all FringeObjects in this store to disk and updates the indexes.
 @param error Any error encountered.
 @return `YES` on success, `NO` on failure.
 */
- (BOOL)commit:(out NSError**)error;
/**
 Deletes this store.
 @param error Any error encountered.
 @return `YES` on success, `NO` on failure.
 @warning Do not attempt to call any other methods if this succeeds.
 */
- (BOOL)delete:(out NSError**)error;

/**
 Executes the block under the store's read lock, returning when complete.
 @param readBlock The block to execute
 */
- (void)lockReadSync:(void(^)())readBlock;
/**
 Executes the block under the store's write lock, returning when complete.
 @param writeBlock The block to execute
 */
- (void)lockWriteSync:(void(^)())writeBlock;
/**
 Executes the block under the store's write lock, returning immedately.
 @param writeBlock The block to execute
 */
- (void)lockWriteAsync:(void(^)())writeBlock;

@end
