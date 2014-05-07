//
//  FringeDataUtils.m
//
//  Created by Sean Meiners on 2012/10/04.
//  Copyright (c) 2012 Sean Meiners. All rights reserved.
//
//

#import "FringeDataUtils.h"

#import "FringeObject.h"
#import "FringeObjectStore.h"

#import "NSURL+ApplicationPath.h"
#import "NSString+UUID.h"

NSString *const kFringeDataItemDeleted = @"FringeDataItemDeleted";

#pragma mark - FringeObjectStore (Internal)

@interface FringeObjectStore (Internal)

- (void)removeObjectWithUUID:(NSString*)uuid;

@end

@implementation NSArray (FringeObject)

- (NSUInteger)indexOfFringeObject:(FringeObject*)anObject {
    if( ! anObject )
        return NSNotFound;
    NSString *uuid = anObject.uuid;
    return [self indexOfObjectPassingTest:^BOOL(FringeObject *obj, NSUInteger idx, BOOL *stop) {
        if( [uuid isEqual:obj.uuid] ) {
            *stop = YES;
            return YES;
        }
        return NO;
    }];
}

@end

@implementation NSOrderedSet (FringeObject)

- (NSUInteger)indexOfFringeObject:(FringeObject*)anObject {
    if( ! anObject )
        return NSNotFound;
    NSString *uuid = anObject.uuid;
    return [self indexOfObjectPassingTest:^BOOL(FringeObject *obj, NSUInteger idx, BOOL *stop) {
        if( [uuid isEqual:obj.uuid] ) {
            *stop = YES;
            return YES;
        }
        return NO;
    }];
}

@end

#pragma mark - FringeObject

@implementation FringeDataUtils

- (id)init {
    return nil;
}

#pragma mark - Helpers

+ (NSArray*)rootObjectsAtPath:(NSURL*)path limit:(NSUInteger)limit
{
    NSMutableArray *roots = [NSMutableArray arrayWithCapacity:10];
    NSArray *resourceKeys = @[ NSURLIsReadableKey, NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey, NSURLCreationDateKey ];
    NSFileManager *fm = [[NSFileManager alloc] init];
    NSArray *urls = [[fm contentsOfDirectoryAtURL:[path fileURL]
                       includingPropertiesForKeys:resourceKeys
                                          options:NSDirectoryEnumerationSkipsHiddenFiles
                                            error:nil] sortedArrayUsingComparator:^NSComparisonResult(NSURL *url1, NSURL *url2) {
        NSDate *d1 = nil, *d2 = nil;
        if( ! [url1 getResourceValue:&d1 forKey:NSURLCreationDateKey error:NULL]
           || ! [url2 getResourceValue:&d2 forKey:NSURLCreationDateKey error:NULL] )
            return NSOrderedSame;
        return [d2 compare:d1]; // reverse sort (newest first)
    }];
    NSURL *url;
    for( url in urls ) {
        NSDictionary *values = [url resourceValuesForKeys:resourceKeys error:NULL];
        if( ! [[values objectForKey:NSURLIsReadableKey] boolValue] )
            continue;
        if( [[values objectForKey:NSURLIsSymbolicLinkKey] boolValue] ) {
            NSURL *real = [url URLByResolvingSymlinksInPath];
            if( ! [fm fileExistsAtPath:[real path]] ) {
                [FringeObjectStore cleanIndexes];
                continue;
            }
            url = real;
        }
        else if( ! [[values objectForKey:NSURLIsRegularFileKey] boolValue] )
            continue;

        NSString *file = [url lastPathComponent];
        if ([[file pathExtension] isEqualToString:kFringeObjectStoreFileExtension]) {
            FringeObjectStore *store = [FringeObjectStore storeWithUUID:[file stringByDeletingPathExtension]
                                                                 atPath:[[url path] stringByDeletingLastPathComponent]];
            id root = store.rootObject;
            if( root )
                [roots addObject:store.rootObject];
            if( limit && [roots count] >= limit )
                return roots;
        }
    }
    return roots;
}

+ (NSArray*)rootObjectsAtAllPaths:(NSArray*)paths limit:(NSUInteger)limit
{
    NSMutableSet *stores = [NSMutableSet setWithCapacity:10];
    NSArray *resourceKeys = @[ NSURLIsReadableKey, NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey, NSURLCreationDateKey ];
    NSFileManager *fm = [[NSFileManager alloc] init];
    BOOL firstPass = YES;
    NSComparisonResult(^reverseDateSort)(NSURL*, NSURL*) = ^NSComparisonResult(NSURL *url1, NSURL *url2) {
        NSDate *d1 = nil, *d2 = nil;
        if( ! [url1 getResourceValue:&d1 forKey:NSURLCreationDateKey error:NULL]
           || ! [url2 getResourceValue:&d2 forKey:NSURLCreationDateKey error:NULL] )
            return NSOrderedSame;
        return [d2 compare:d1]; // reverse sort (newest first)
    };


    for( NSURL *path in paths )
    {
        NSArray *urls = [[fm contentsOfDirectoryAtURL:[path fileURL]
                           includingPropertiesForKeys:resourceKeys
                                              options:NSDirectoryEnumerationSkipsHiddenFiles
                                                error:nil] sortedArrayUsingComparator:reverseDateSort];

        NSMutableSet *theseStores = [NSMutableSet setWithCapacity:10];
        NSURL *url;
        for( url in urls ) {
            NSDictionary *values = [url resourceValuesForKeys:resourceKeys error:NULL];
            if( ! [[values objectForKey:NSURLIsReadableKey] boolValue] )
                continue;
            if( [[values objectForKey:NSURLIsSymbolicLinkKey] boolValue] ) {
                NSURL *real = [url URLByResolvingSymlinksInPath];
                if( ! [fm fileExistsAtPath:[real path]] ) {
                    [FringeObjectStore cleanIndexes];
                    continue;
                }
                url = real;
            }
            else if( ! [[values objectForKey:NSURLIsRegularFileKey] boolValue] )
                continue;

            [theseStores addObject:url];
        }

        if( ! firstPass ) {
            [stores intersectSet:theseStores];
        }
        else {
            stores = theseStores;
            firstPass = NO;
        }
    }

    NSMutableArray *roots = [NSMutableArray arrayWithCapacity:[stores count]];
    for( NSURL *url in stores ) {
        NSString *file = [url lastPathComponent];
        if ([[file pathExtension] isEqualToString:kFringeObjectStoreFileExtension]) {
            FringeObjectStore *store = [FringeObjectStore storeWithUUID:[file stringByDeletingPathExtension]
                                                                 atPath:[[url path] stringByDeletingLastPathComponent]];
            [roots addObject:store.rootObject];
            if( limit && [roots count] >= limit )
                return roots;
        }
    }

    return roots;
}

#pragma mark - Core

+ (BOOL)save:(FringeObject*)object
{
    FringeObjectStore *store = object.fringeObjectStore;
    if( ! store )
        return YES;
    NSError *error = nil;
    if( [store commit:&error] )
        return YES;
    NSLog(@"Error saving %@: %@", store, error);
    return NO;
}

+ (BOOL)deleteObject:(FringeObject*)object
{
    // yes, technically this is premature... but the delete shouldn't fail in the first place
    // and if it does succeed, the object will be invalid, so the reciever would throw an exception
    // if they tried to access it
    [[NSNotificationCenter defaultCenter] postNotificationName:kFringeDataItemDeleted object:object];
    
    FringeObjectStore *store = object.fringeObjectStore;
    if( ! store )
        return NO;

    NSError *error = nil;

    if( store.rootObject != object ) {
        [store lockWriteSync:^{
            [store removeObjectWithUUID:object.uuid];
        }];
        if( [store commit:&error] )
            return YES;
    }
    else {
        if( [store delete:&error] )
            return YES;
    }
    NSLog(@"Error deleting %@: %@", object, error);
    return NO;
}


@end
