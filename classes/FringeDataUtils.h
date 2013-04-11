//
//  FringeDataUtils.h
//  Givit
//
//  Created by Sean Meiners on 2012/10/04.
//
//

#import <Foundation/Foundation.h>

@class FringeObject;
@class FringeObjectStore;

extern NSString *const kFringeDataItemDeleted;

@interface NSArray (FringeObject)

- (NSUInteger)indexOfFringeObject:(FringeObject*)anObject;

@end

@interface NSOrderedSet (FringeObject)

- (NSUInteger)indexOfFringeObject:(FringeObject*)anObject;

@end

@interface FringeDataUtils : NSObject

+ (BOOL)save:(FringeObject*)object;

+ (NSArray*)rootObjectsAtPath:(NSURL*)path limit:(NSUInteger)limit;

+ (BOOL)deleteObject:(FringeObject*)object;

@end
