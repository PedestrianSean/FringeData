//
//  FringeObjectStore.m
//
//  Created by Sean Meiners on 2012/10/01.
//  Copyright (c) 2012 Sean Meiners. All rights reserved.
//
//

#import "FringeObjectStore.h"

#import <objc/runtime.h>
#import <pthread.h>

#import "FringeObject.h"
#import "SBJson/SBJson.h"
#import "FringeWeakObject.h"
#import "NSURL+ApplicationPath.h"

#ifndef lcl_log
#define lcl_log(a, b, format, ...) NSLog(format, ##__VA_ARGS__)
#endif

NSString *__strong const kFringeObjectStoreFileExtension = @"fds";
NSString *__strong const kFringeDataErrorDomain = @"FringeDataErrorDomain";

/*
 The object graph here is kind of complex, but it works pretty well.
 It looks something like this: ( | - weak connection, || - strong connection )
 
                            s_knownStores
                                    |
                                FringeWeakObject
                            FringeObjectStore
                            //       ||     \\
                      objects        ||      changedObjects
                            \        ||     //
                        FringeWeakObject   ^^    //
                                FringeObject

 This accomplishes a couple of goals:
 1) If any FringeObjects in a given FringeObjectStore have changed, it will prevent both the
    FringeObjectStore and the FringeObjects from being released until one of the following is called:
    a) [FringeObjectStore commit]
    b) [FringeObjectStore rollback]
    c) [FringeObjectStore delete]
 2) If none of the FringeObjects in a given FringeObjectStore have changed, they will be released
    as soon as the user gives up all references to them (and the current autoreleasepool drains)
 */

static NSMutableDictionary *__strong s_knownStores = nil;

static NSString *__strong const RootKey = @"root";

#pragma mark - FringeObject (Internal)

@interface FringeObject (Internal)

@property (atomic, strong) NSMutableDictionary *jsonDataInternal;
@property (nonatomic, strong) FringeObjectStore *store;
@property (atomic, strong) NSDictionary *indexPaths;

- (void)setUuidInternal:(NSString *)uuid;
- (void)setStore:(FringeObjectStore*)store;
- (BOOL)isOnDisk;
- (void)setIsOnDisk:(BOOL)onDisk;
- (NSSet*)getPropertyNamesOfFringeObjectProperties;

@end

#pragma mark - FringeObjectStore

@interface FringeObjectStore ()

@property (nonatomic, strong) NSString *rootUUID;
@property (nonatomic, strong) NSMutableDictionary *objects;
@property (nonatomic, strong) NSMutableDictionary *changedObjects;
@property (nonatomic, strong) NSMutableSet *removedObjects;
@property (nonatomic, weak) NSDictionary *cachedJSON;

@property (nonatomic, strong) dispatch_queue_t lockQueue;
@property (nonatomic, strong) NSString *lockQueueKey;

@end

BOOL isFringeObjectClass(Class clas) {
    if( ! clas )
        return NO;
    if( clas == [FringeObject class] )
        return YES;
    return isFringeObjectClass(class_getSuperclass(clas));
}

@implementation FringeObjectStore

- (NSString*)description {
    return [NSString stringWithFormat:@"<%@: %p {rootUUID: %@, commitPath: %@ objects: %@, changedObjects: %@, removedObjects: %@, cachedJSON: %@}>",
            NSStringFromClass([self class]), self,
            _rootUUID, _commitPath, _objects, _changedObjects, _removedObjects, _cachedJSON];
}

- (id)initCommon {
    if( (self = [super init]) ) {
        _lockQueueKey = [NSString stringWithFormat:@"com.ssttr.FringeObjectStoreLock.%p", self];
        _lockQueue = dispatch_queue_create([_lockQueueKey UTF8String], DISPATCH_QUEUE_CONCURRENT);
        dispatch_queue_set_specific(_lockQueue, (__bridge void *)_lockQueueKey, (__bridge void *)self, NULL);
        _objects = [NSMutableDictionary dictionaryWithCapacity:10];
        _changedObjects = [NSMutableDictionary dictionaryWithCapacity:10];
        _removedObjects = [NSMutableSet setWithCapacity:10];
    }
    return self;
}

- (id)init {
    //NSLog(@"%p [%@ %@]", self, NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    if( (self = [self initCommon]) ) {
    }
    return self;
}

- (id)initWithUUID:(NSString*)uuid andCommitPath:(NSString *)path {
    //NSLog(@"%p [%@ %@]", self, NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    if( (self = [self initCommon]) ) {
        _commitPath = path;
        _rootUUID = uuid;
        if( uuid ) {
            [_objects setObject:_rootUUID forKey:RootKey];
            [s_knownStores setObject:[FringeWeakObject weakObject:self] forKey:_rootUUID];
        }
    }
    return self;
}

- (id)initWithRootObject:(FringeObject*)root andCommitPath:(NSString*)path
{
    //NSLog(@"%p [%@ %@]", self, NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    if( (self = [self initCommon]) ) {
        _commitPath = [path length] ? path : [[[root class] defaultCommitPath] path];
        [root setStore:self];
        _rootUUID = root.uuid;
        [_objects setObject:_rootUUID forKey:RootKey];
        [_objects setObject:[FringeWeakObject weakObject:root] forKey:_rootUUID];
        [_changedObjects setObject:root forKey:_rootUUID];
        [s_knownStores setObject:[FringeWeakObject weakObject:self] forKey:_rootUUID];
    }
    return self;
}

- (void)dealloc {
    //NSLog(@"%p [%@ %@]", self, NSStringFromClass([self class]), NSStringFromSelector(_cmd));
}

+ (FringeObjectStore*)storeWithRootObject:(FringeObject*)root atPath:(NSString *)path
{
    if( ! s_knownStores )
        s_knownStores = [NSMutableDictionary dictionaryWithCapacity:10];

    @synchronized(s_knownStores) {
        FringeWeakObject *weakStore = [s_knownStores objectForKey:root.uuid];
        id object = weakStore.object;
        if( object )
            return object;

        return [[FringeObjectStore alloc] initWithRootObject:root andCommitPath:path];
    }
}

+ (FringeObjectStore*)storeWithUUID:(NSString*)uuid atPath:(NSString *)path
{
    if( ! s_knownStores )
        s_knownStores = [NSMutableDictionary dictionaryWithCapacity:10];

    @synchronized(s_knownStores) {
        FringeWeakObject *weakStore = [s_knownStores objectForKey:uuid];
        id object = weakStore.object;
        if( object )
            return object;

        NSString *fullPath = [FringeObjectStore fullPathForUUID:uuid andCommitPath:path];
        if( fullPath && [[[NSFileManager alloc] init] fileExistsAtPath:fullPath] )
            return [[FringeObjectStore alloc] initWithUUID:uuid andCommitPath:path];
        else
            return nil;
    }
}

+ (FringeObjectStore*)storeWithPath:(NSString *)path {
    if( ! s_knownStores )
        s_knownStores = [NSMutableDictionary dictionaryWithCapacity:10];

    NSString *uuid = [[path lastPathComponent] stringByDeletingPathExtension];
    NSString *commitPath = [path stringByDeletingLastPathComponent];

    @synchronized(s_knownStores) {
        FringeWeakObject *weakStore = [s_knownStores objectForKey:uuid];
        id object = weakStore.object;
        if( object )
            return object;
    }
    return [[FringeObjectStore alloc] initWithUUID:uuid andCommitPath:commitPath];
}

+ (NSString*)fullPathForUUID:(NSString*)uuid andCommitPath:(NSString*)commitPath {
    if( ! commitPath )
        return nil;
    return [[[commitPath stringByAppendingPathComponent:uuid] stringByAppendingPathExtension:kFringeObjectStoreFileExtension] stringByStandardizingPath];
}

- (NSString*)fullCommitPath {
    return [FringeObjectStore fullPathForUUID:_rootUUID andCommitPath:_commitPath];
}

- (id)rootObject
{
    return [self objectWithUUID:_rootUUID];
}

- (BOOL)setRootObject:(FringeObject*)rootObject {
    @synchronized(s_knownStores) {
        if( [s_knownStores objectForKey:rootObject.uuid] )
            return NO;
        _rootUUID = rootObject.uuid;
        [_objects setObject:_rootUUID forKey:RootKey];
        [_objects setObject:[FringeWeakObject weakObject:rootObject] forKey:_rootUUID];
        [_changedObjects setObject:rootObject forKey:_rootUUID];
        [s_knownStores setObject:[FringeWeakObject weakObject:self] forKey:_rootUUID];
        return YES;
    }
}

- (BOOL)setCommitPath:(NSString *)commitPath error:(NSError**)errorOut {
    if( ! _commitPath ) {
        _commitPath = commitPath;
        return YES;
    }

    if( [_commitPath isEqualToString:commitPath] )
        return YES;

    NSFileManager *fm = [[NSFileManager alloc] init];
    NSString *oldFullPath = [self fullCommitPath];
    _commitPath = commitPath;
    NSString *newFullPath = [self fullCommitPath];

    if( ! [fm fileExistsAtPath:oldFullPath] )
        return YES;

    NSError *error = nil;
    if( ! [fm moveItemAtPath:oldFullPath toPath:newFullPath error:&error] ) {
        if( errorOut )
            *errorOut = error;
        return NO;
    }

    return YES;
}

- (id)cachedJSON {
    if( _cachedJSON )
        return _cachedJSON;

    NSString *fullPath = [self fullCommitPath];
    NSError *error = nil;
    NSString *rawStr = [NSString stringWithContentsOfFile:fullPath
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];
    if( ! [rawStr length] ) {
        return nil;
    }
    NSDictionary *json = [[[SBJsonParser alloc] init] objectWithString:rawStr];
    if( ! json || ! [json isKindOfClass:[NSDictionary class]] ) {
        lcl_log(lcl_cFringeData, lcl_vError, @"Unparsable json in %@: %@", fullPath, rawStr);
        [self delete:NULL];
        [FringeObjectStore cleanIndexes];
        return nil;
    }

    _cachedJSON = json;

    return _cachedJSON;
}

- (id)reloadObjectWithUUID:(NSString*)uuid
{
    if( [_removedObjects member:uuid] )
        return nil;
    
    NSDictionary *rawObject = [[self cachedJSON] objectForKey:uuid];
    if( ! rawObject )
        return nil;

    NSString *className = [rawObject objectForKey:@"class"];
    if( [className isKindOfClass:[NSString class]] && [className length] ) {
        Class clas = objc_getClass([className UTF8String]);
        FringeObject *fo = nil;
        if( isFringeObjectClass(clas) )
            fo = [[clas alloc] initWithDictionary:rawObject inStore:self];
        else
            fo = [[FringeObject alloc] initWithDictionary:rawObject inStore:self];
        [fo setIsOnDisk:YES];
        return fo;
    }

    return nil;
}

- (NSDictionary*)loadAllObjects {
    NSMutableDictionary *allObjects = [NSMutableDictionary dictionaryWithCapacity:[_objects count]];
    NSDictionary *json = [self cachedJSON];

    NSMutableSet *keys = [NSMutableSet setWithArray:[json allKeys]];
    [keys unionSet:[NSSet setWithArray:[_objects allKeys]]];
    [keys minusSet:_removedObjects];

    for( NSString *key in keys ) {
        FringeWeakObject *weakObject = [_objects objectForKey:key];
        if( weakObject ) {
            if( ! [weakObject isKindOfClass:[FringeWeakObject class]] ) {
                [allObjects setObject:weakObject forKey:key];
                continue;
            }

            id object = weakObject.object;
            if( object ) {
                [allObjects setObject:object forKey:key];
                continue;
            }
        }

        NSDictionary *obj = [json objectForKey:key];
        if( [obj isKindOfClass:[NSDictionary class]] )
        {
            if( ! weakObject ) {
                weakObject = [[FringeWeakObject alloc] init];
                [_objects setObject:weakObject forKey:key];
            }
            
            NSString *className = [obj objectForKey:@"class"];
            if( [className isKindOfClass:[NSString class]] && [className length] ) {
                Class clas = objc_getClass([className UTF8String]);
                if( isFringeObjectClass(clas) ) {
                    FringeObject *fo = [[clas alloc] initWithDictionary:obj inStore:self];
                    [fo setIsOnDisk:YES];
                    [allObjects setObject:fo forKey:key];
                    weakObject.object = fo;
                    continue;
                }
            }
            FringeObject *fo = [[FringeObject alloc] initWithDictionary:obj inStore:self];
            [fo setIsOnDisk:YES];
            [allObjects setObject:fo forKey:key];
            weakObject.object = fo;
        }
    };

    return allObjects;
}

- (id)objectWithUUID:(NSString*)uuid
{
    if( ! [uuid length] )
        return nil;
    if( [_removedObjects member:uuid] )
        return nil;

    // this object seems redundant, but it's necessary to 'trick' the optimizer
    // into holding onto the object long enough for us to return it
    id object = nil;
    FringeWeakObject *weakObject = [_objects objectForKey:uuid];
    object = weakObject.object;
    if( ! object ) {
        if( ! weakObject ) {
            weakObject = [[FringeWeakObject alloc] init];
            [_objects setObject:weakObject forKey:uuid];
        }
        object = [self reloadObjectWithUUID:uuid];
        weakObject.object = object;
    }
    return object;
}

- (void)removeObjectWithUUID:(NSString*)uuid
{
    if( ! [uuid length] )
        return;

    [_objects removeObjectForKey:uuid];
    [_removedObjects addObject:uuid];

    // recursively locate all references to this uuid & remove it
    [self loadAllObjects];
    NSMutableSet *keys = [NSMutableSet setWithArray:[[self cachedJSON] allKeys]];
    [keys unionSet:[NSSet setWithArray:[_objects allKeys]]];
    [keys minusSet:_removedObjects];
    [keys removeObject:RootKey];
    for( NSString *key in keys ) {
        FringeObject *object = [self objectWithUUID:key];
        NSSet *fringeObjectProperties = [object getPropertyNamesOfFringeObjectProperties];
        for( NSString *property in fringeObjectProperties ) {
            id value = [object.jsonDataInternal objectForKey:property];
            if( [value isKindOfClass:[NSString class]] && [value isEqualToString:uuid] ) {
                [object.jsonDataInternal removeObjectForKey:property];
                [self addChangedObject:object];
            }
            else if( [value isKindOfClass:[NSArray class]] && [value indexOfObject:uuid] != NSNotFound ) {
                [value removeObject:uuid];
                [self addChangedObject:object];
            }
        }
    }
}

- (void)addObject:(FringeObject*)object
{
    //NSLog(@"[%@ %@:%p]", NSStringFromClass([self class]), NSStringFromSelector(_cmd), object);
    if( object && [object.uuid length] ) {
        if( ! [_objects objectForKey:object.uuid] )
            [_objects setObject:[FringeWeakObject weakObject:object] forKey:object.uuid];
        [_removedObjects removeObject:object.uuid];
        [_changedObjects setObject:object forKey:object.uuid];
        object.store = self;
    }
}

- (void)addChangedObject:(FringeObject*)object
{
    if( object && [object.uuid length] )
        [_changedObjects setObject:object forKey:object.uuid];
}

- (void)updateIndexes
{
    NSFileManager *fm = [[NSFileManager alloc] init];

    FringeObject *root = [self rootObject];
    NSString *fullPath = [self fullCommitPath];

    Class clas = [root class];
    NSSet *indexedProperties = [clas indexedPropertyNames];

    NSDictionary *oldIndexPaths = root.indexPaths;
    NSMutableDictionary *newIndexPaths = [NSMutableDictionary dictionaryWithCapacity:[indexedProperties count]];

    for( NSString *property in indexedProperties ) {
        id value = [root getProperty:property];
        NSURL *newURL = [[clas indexURLForProperty:property withValue:value forObject:root] shortenedURL];
        NSURL *oldURL = [[NSURL URLWithString:[oldIndexPaths objectForKey:property]] shortenedURL];
        if( ! [oldURL isEqual:newURL] )
        {
            if( oldURL )
                [fm removeItemAtPath:[oldURL path] error:NULL];

            if( newURL ) {
                NSString *newPath = [newURL path];
                [fm createDirectoryAtPath:[newPath stringByDeletingLastPathComponent]
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:NULL];

                NSString *commonPath = [fullPath commonPrefixWithString:newPath options:0];

                NSString *fullPathDiff = [fullPath substringFromIndex:[commonPath length]];
                NSString *newPathDiff = [newPath substringFromIndex:[commonPath length]];

                NSUInteger subDirs = [[[newPathDiff stringByDeletingLastPathComponent] pathComponents] count];
                NSMutableString *relativePath = [NSMutableString stringWithString:fullPathDiff];
                while( subDirs-- )
                    [relativePath insertString:@"../" atIndex:0];

                [fm createSymbolicLinkAtPath:newPath
                         withDestinationPath:relativePath
                                       error:NULL];
            }
        }

        if( newURL )
            [newIndexPaths setObject:[newURL absoluteString] forKey:property];
    }

    root.indexPaths = newIndexPaths;
}

- (BOOL)commit:(NSError**)errorOut {
    if( ! _commitPath ) {
        if( errorOut )
            *errorOut = [NSError errorWithDomain:kFringeDataErrorDomain
                                            code:FringeDataError_NoCommitPath
                                        userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedString(@"Can not save with no path.", @"Fringe Data error") }];
        return YES;
    }
    if( ! _rootUUID ) {
        if( errorOut )
            *errorOut = [NSError errorWithDomain:kFringeDataErrorDomain
                                            code:FringeDataError_NoRootObject
                                        userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedString(@"Can not save with no root.", @"Fringe Data error") }];
        return NO;

    }
    if( ! [_changedObjects count] )
        return YES;
    
    @synchronized(self) {
        NSString *fullPath = [self fullCommitPath];

        // make sure the file exits before updating the indexes
        NSFileManager *fm = [[NSFileManager alloc] init];

        [fm createDirectoryAtPath:[fullPath stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES
                       attributes:nil
                            error:NULL];

        if( ! [fm fileExistsAtPath:fullPath] )
            [fm createFileAtPath:fullPath contents:[@"{}" dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];

        __block BOOL success = YES;
        [self lockWriteSync:^{
            NSError *error = nil;
            NSDictionary *allObjects = [self loadAllObjects];
            _cachedJSON = allObjects;
            [self updateIndexes];
            NSString *data = [[[SBJsonWriter alloc] init] stringWithObject:allObjects];

            // finally, write it out. this is done after updateIndexes since that will actually change the content of _objects
            if( ! [data writeToFile:fullPath atomically:YES encoding:NSUTF8StringEncoding error:&error] || error ) {
                //NSLog(@"failed to write %@ - %@ (data: %@)", [self fullCommitPath], error, data);
                if( errorOut )
                    *errorOut = error;
                success = NO;
            }
            [_objects enumerateKeysAndObjectsUsingBlock:^(id key, FringeWeakObject *obj, BOOL *stop) {
                if( ! [key isEqualToString:RootKey] )
                    [(FringeObject*)obj.object setIsOnDisk:YES];
            }];
            [_changedObjects removeAllObjects];

            //NSLog(@"[%@ %@]: wrote %u bytes", NSStringFromClass([self class]), NSStringFromSelector(_cmd), [data length]);
            //NSLog(@"[%@ %@]: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), data);
        }];

        return success;
    }
}

- (BOOL)delete:(NSError**)errorOut {
    if( ! [_commitPath length] ) {
        if( errorOut )
            *errorOut = [NSError errorWithDomain:kFringeDataErrorDomain
                                            code:FringeDataError_NoCommitPath
                                        userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedString(@"Can not delete with no path.", @"Fringe Data error") }];
        return NO;
    }
    if( ! [_rootUUID length] ) {
        if( errorOut )
            *errorOut = [NSError errorWithDomain:kFringeDataErrorDomain
                                            code:FringeDataError_NoRootObject
                                        userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedString(@"Can not delete with no root.", @"Fringe Data error") }];
        return NO;

    }

    @synchronized(s_knownStores) {
        NSError *error = nil;
        NSString *fullPath = [self fullCommitPath];
        NSFileManager *fm = [[NSFileManager alloc] init];
        if( ! [fm fileExistsAtPath:fullPath] )
            return YES;

        if( ! [fm removeItemAtPath:fullPath error:&error] ) {
            //NSLog(@"failed to delete %@ - %@", fullPath, error);
            if( errorOut )
                *errorOut = error;
            return NO;
        }

        NSDictionary *indexPaths = [[self rootObject] indexPaths];
        [indexPaths enumerateKeysAndObjectsUsingBlock:^(NSString *propertyName, NSString *path, BOOL *stop) {
            NSError *removeError = nil;
            if( ! [fm removeItemAtPath:[[NSURL URLWithString:path] path] error:&removeError] )
                lcl_log(lcl_cFringeData, lcl_vError, @"Unable to remove index @ %@ - %@", path, removeError);
        }];

        [s_knownStores removeObjectForKey:_rootUUID];
    }

    _rootUUID = nil;
    [_objects removeAllObjects];
    [_changedObjects removeAllObjects];

    return YES;
}

+ (void)cleanIndexes {
    NSFileManager *fm = [[NSFileManager alloc] init];
    NSArray *resourceKeys = @[ NSURLIsReadableKey, NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey ];
    NSDirectoryEnumerator *dir = [fm enumeratorAtURL:[[NSURL URLWithLibrary:@"FringeData"] fileURL]
                          includingPropertiesForKeys:resourceKeys
                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                        errorHandler:^BOOL(NSURL *url, NSError *error) {
                                            return YES;
                                        }];
    NSURL *url = nil;
    for( url in dir ) {
        NSDictionary *values = [url resourceValuesForKeys:resourceKeys error:NULL];
        if( ! [[values objectForKey:NSURLIsReadableKey] boolValue] )
            continue;
        if( [[values objectForKey:NSURLIsRegularFileKey] boolValue] )
            continue;
        if( ! [[values objectForKey:NSURLIsSymbolicLinkKey] boolValue] )
            continue;

        NSError *error = nil;
        NSURL *dest = [url URLByResolvingSymlinksInPath];
        if( ! [fm fileExistsAtPath:[dest path]] )
            if( ! [fm removeItemAtURL:url error:&error] )
                lcl_log(lcl_cFringeData, lcl_vError, @"Unable to remove index @ %@ - %@", url, error);
    }
}

- (void)lockReadSync:(void(^)())readBlock
{
	if( dispatch_get_specific((__bridge void *)_lockQueueKey) )
        readBlock();
    else
        dispatch_sync(_lockQueue, readBlock);
}

- (void)lockWriteSync:(void(^)())writeBlock
{
	if( dispatch_get_specific((__bridge void *)_lockQueueKey) )
        writeBlock();
    else
        dispatch_barrier_sync(_lockQueue, writeBlock);
}

- (void)lockWriteAsync:(void(^)())writeBlock
{
	if( dispatch_get_specific((__bridge void *)_lockQueueKey) )
        writeBlock();
    else
        dispatch_barrier_async(_lockQueue, writeBlock);
}

@end
