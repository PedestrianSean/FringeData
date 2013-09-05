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

typedef enum : NSUInteger {
    FringeDataError_NoCommitPath = 1000,
    FringeDataError_NoRootObject,
    FringeDataError_Exception
} FringeDataErrorCode;

@interface FringeObjectStore : NSObject

@property (nonatomic, readonly) NSString *commitPath;

+ (FringeObjectStore*)storeWithPath:(NSString*)path;
+ (FringeObjectStore*)storeWithUUID:(NSString*)uuid atPath:(NSString*)path;
+ (FringeObjectStore*)storeWithRootObject:(FringeObject*)root atPath:(NSString*)path;

+ (void)cleanIndexes;

- (BOOL)setCommitPath:(NSString*)commitPath error:(NSError**)error;

- (id)rootObject;
- (BOOL)setRootObject:(FringeObject*)rootObject;
- (id)objectWithUUID:(NSString*)uuid;

- (BOOL)commit:(NSError**)error;
- (BOOL)delete:(NSError**)error;

- (void)lockReadSync:(void(^)())readBlock;
- (void)lockWriteSync:(void(^)())writeBlock;
- (void)lockWriteAsync:(void(^)())writeBlock;

@end
