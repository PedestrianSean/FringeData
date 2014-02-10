//
//  NSObject+JSONSafety.m
//
//  Created by Sean Meiners on 2012/07/11.
//  Copyright (c) 2012 Sean Meiners. All rights reserved.
//

#import "NSObject+JSONSafety.h"

@implementation NSObject (JSONSafety)

- (NSObject*)jsonObjectForKey:(NSString*)key
{
    if( ! self ) return nil;
    id object = nil;
    if( [self respondsToSelector:@selector(objectForKey:)] )
        object = [(id)self objectForKey:key];
    if( object == [NSNull null] )
        return nil;
    return object;
}

- (NSObject*)jsonObjectAt:(NSUInteger)index
{
    if( ! self ) return nil;
    id object = nil;
    if( [self respondsToSelector:@selector(objectAtIndex:)] )
        object = [(id)self objectAtIndex:index];
    if( object == [NSNull null] )
        return nil;
    return object;
}


- (NSString*)jsonStringForKey:(NSString*)key
{
    return [self jsonStringForKey:key withDefault:nil];
}

- (NSString*)jsonStringForKey:(NSString*)key withDefault:(NSString*)defaultValue
{
    if( ! self ) return defaultValue;
    id object = [self jsonObjectForKey:key];
    if( [object isKindOfClass:[NSString class]] )
        return object;
    if( [object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSDictionary class]] )
        return defaultValue;
    if( object )
        return [object description];
    return defaultValue;
}

- (NSString*)jsonStringAt:(NSUInteger)index
{
    return [self jsonStringAt:index withDefault:nil];
}

- (NSString*)jsonStringAt:(NSUInteger)index withDefault:(NSString*)defaultValue
{
    if( ! self ) return defaultValue;
    id object = [self jsonObjectAt:index];
    if( [object isKindOfClass:[NSString class]] )
        return object;
    if( [object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSDictionary class]] )
        return defaultValue;
    if( object )
        return [object description];
    return defaultValue;
}

- (BOOL)jsonBoolForKey:(NSString*)key
{
    return [self jsonBoolForKey:key withDefault:NO];
}

- (BOOL)jsonBoolForKey:(NSString*)key withDefault:(BOOL)defaultValue
{
    NSString *str = [self jsonStringForKey:key];
    if( ! str )
        return defaultValue;
    return [str intValue] != 0;
}

- (BOOL)jsonBoolAt:(NSUInteger)index
{
    return [self jsonBoolAt:index withDefault:NO];
}

- (BOOL)jsonBoolAt:(NSUInteger)index withDefault:(BOOL)defaultValue
{
    NSString *str = [self jsonStringAt:index];
    if( ! str )
        return defaultValue;
    return [str intValue] != 0;
}

#define JSON_PRIMITIVE_INT(NAME, TYPE, CFUNC, SELECTOR) \
- (TYPE)json##NAME##ForKey:(NSString*)key \
{ return [self json##NAME##ForKey:key withDefault:0]; } \
\
- (TYPE)json##NAME##ForKey:(NSString*)key withDefault:(TYPE)defaultValue \
{ \
    if( ! self ) return defaultValue; \
    id object = [self jsonObjectForKey:key]; \
    if( [object isKindOfClass:[NSString class]] ) \
        return (TYPE)CFUNC([object UTF8String], NULL, 0); \
    if( [object respondsToSelector:@selector(SELECTOR)] ) \
        return [object SELECTOR]; \
    return defaultValue; \
} \
\
- (TYPE)json##NAME##At:(NSUInteger)index \
{ return [self json##NAME##At:index withDefault:0]; } \
\
- (TYPE)json##NAME##At:(NSUInteger)index withDefault:(TYPE)defaultValue \
{ \
    if( ! self ) return defaultValue; \
    id object = [self jsonObjectAt:index]; \
    if( [object isKindOfClass:[NSString class]] ) \
        return (TYPE)CFUNC([object UTF8String], NULL, 0); \
    if( [object respondsToSelector:@selector(SELECTOR)] ) \
        return [object SELECTOR]; \
    return defaultValue; \
}

JSON_PRIMITIVE_INT(UInt64, uint64_t, strtoull, unsignedLongLongValue);
JSON_PRIMITIVE_INT(Int64, int64_t, strtoll, longLongValue);
JSON_PRIMITIVE_INT(UInt32, uint32_t, strtoul, unsignedIntValue);
JSON_PRIMITIVE_INT(Int32, int32_t, strtol, intValue);

#define JSON_PRIMITIVE_FP(NAME, TYPE, CFUNC, SELECTOR) \
- (TYPE)json##NAME##ForKey:(NSString*)key \
{ return [self json##NAME##ForKey:key withDefault:0]; } \
\
- (TYPE)json##NAME##ForKey:(NSString*)key withDefault:(TYPE)defaultValue \
{ \
    if( ! self ) return defaultValue; \
    id object = [self jsonObjectForKey:key]; \
    if( [object isKindOfClass:[NSString class]] ) \
        return (TYPE)CFUNC([object UTF8String], NULL); \
    if( [object respondsToSelector:@selector(SELECTOR)] ) \
        return (TYPE)[object SELECTOR]; \
    return defaultValue; \
} \
\
- (TYPE)json##NAME##At:(NSUInteger)index \
{ return [self jsonUInt64At:index withDefault:0]; } \
\
- (TYPE)json##NAME##At:(NSUInteger)index withDefault:(TYPE)defaultValue \
{ \
    if( ! self ) return defaultValue; \
    id object = [self jsonObjectAt:index]; \
    if( [object isKindOfClass:[NSString class]] ) \
        return (TYPE)CFUNC([object UTF8String], NULL); \
    if( [object respondsToSelector:@selector(SELECTOR)] ) \
        return (TYPE)[object SELECTOR]; \
    return defaultValue; \
}

JSON_PRIMITIVE_FP(Double, double, strtod, doubleValue);
JSON_PRIMITIVE_FP(Float, float, strtof, floatValue);

static NSArray *arrayFromDict(NSDictionary *dict) {
    if( [dict count] == 0 )
        return [NSMutableArray arrayWithCapacity:1];
    // check for 0 or 1 based arrays
    id first = [dict objectForKey:@"0"];
    if( ! first )
        first = [dict objectForKey:@"1"];
    // and check for NSNumber keys
    if( ! first )
        first = [dict objectForKey:@0];
    if( ! first )
        first = [dict objectForKey:@1];
    if( ! first )
        return nil;

    NSMutableArray *keys = [NSMutableArray arrayWithArray:[dict allKeys]];
    [keys sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        int int1 = [obj1 intValue];
        int int2 = [obj2 intValue];
        if( int1 > int2 )
            return NSOrderedDescending;
        if( int2 < int1 )
            return NSOrderedAscending;
        return NSOrderedSame;
    }];

    NSMutableArray *array = [NSMutableArray arrayWithCapacity:[keys count]];
    for( id key in keys ) {
        id obj = [dict objectForKey:key];
        [array addObject:obj];
    }
    return array;
}

- (NSArray*)jsonArrayForKey:(NSString*)key
{
    if( ! self ) return nil;
    id object = [self jsonObjectForKey:key];
    if( [object isKindOfClass:[NSArray class]] )
        return object;
    if( [object isKindOfClass:[NSDictionary class]] )
        return arrayFromDict(object);
    return nil;
}

- (NSArray*)jsonArrayAt:(NSUInteger)index
{
    if( ! self ) return nil;
    id object = [self jsonObjectAt:index];
    if( [object isKindOfClass:[NSArray class]] )
        return object;
    if( [object isKindOfClass:[NSDictionary class]] )
        return arrayFromDict(object);
    return nil;
}


- (NSDictionary*)jsonDictionaryForKey:(NSString*)key
{
    if( ! self ) return nil;
    id object = [self jsonObjectForKey:key];
    if( [object isKindOfClass:[NSDictionary class]] )
        return object;
    return nil;
}

- (NSDictionary*)jsonDictionaryAt:(NSUInteger)index
{
    if( ! self ) return nil;
    id object = [self jsonObjectAt:index];
    if( [object isKindOfClass:[NSDictionary class]] )
        return object;
    return nil;
}


@end
