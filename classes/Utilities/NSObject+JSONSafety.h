//
//  NSObject+JSONSafety.h
//
//  Created by Sean Meiners on 2012/07/11.
//  Copyright (c) 2012 Sean Meiners. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSObject (JSONSafety)

- (NSObject*)jsonObjectForKey:(NSString*)key;
- (NSObject*)jsonObjectAt:(NSUInteger)index;

- (NSString*)jsonStringForKey:(NSString*)key;
- (NSString*)jsonStringAt:(NSUInteger)index;

#define JSON_SAFE_PRIMITIVE(NAME, TYPE) \
- (TYPE)json##NAME##ForKey:(NSString*)key; \
- (TYPE)json##NAME##ForKey:(NSString*)key withDefault:(TYPE)defaultValue; \
- (TYPE)json##NAME##At:(NSUInteger)index; \
- (TYPE)json##NAME##At:(NSUInteger)index withDefault:(TYPE)defaultValue;

JSON_SAFE_PRIMITIVE(Bool, BOOL);
JSON_SAFE_PRIMITIVE(Double, double);
JSON_SAFE_PRIMITIVE(Float, float);
JSON_SAFE_PRIMITIVE(UInt64, uint64_t);
JSON_SAFE_PRIMITIVE(Int64, int64_t);
JSON_SAFE_PRIMITIVE(UInt32, uint32_t);
JSON_SAFE_PRIMITIVE(Int32, int32_t);

- (NSArray*)jsonArrayForKey:(NSString*)key;
- (NSArray*)jsonArrayAt:(NSUInteger)index;

- (NSDictionary*)jsonDictionaryForKey:(NSString*)key;
- (NSDictionary*)jsonDictionaryAt:(NSUInteger)index;

@end
