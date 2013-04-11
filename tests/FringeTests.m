#import <Foundation/Foundation.h>
#import "FringeObjectStore.h"
#import "FringeObject.h"
#import "NSObject+JSONSafety.h"
#import "SBJSON/SBJSON.h"

#define STORE_PATH @"/tmp"

@interface FringeObjectStore ()

- (NSDictionary*)loadAllObjects;
- (void)removeObjectWithUUID:(NSString*)uuid;

@end



@interface TestObject : FringeObject

@property (atomic, strong) NSString *stringProperty;
@property (atomic, strong) NSString *stringPropertyNonDynamic;
@property (atomic, strong, setter=setPropertyString:) NSString *stringPropertySetter;
@property (atomic, strong, getter=getPropertyString) NSString *stringPropertyGetter;
@property (atomic, strong, setter=setPropertyString2:, getter=getPropertyString2) NSString *stringPropertySetterGetter;
@property (atomic, copy) NSString *copyStringProperty;
@property (atomic, weak) NSString *weakStringProperty;

@property (atomic, assign) uint64_t uint64Property;
@property (atomic, assign) int64_t int64Property;
@property (atomic, assign) uint32_t uint32Property;
@property (atomic, assign) int32_t int32Property;
@property (atomic, assign) double doubleProperty;
@property (atomic, assign) float floatProperty;
@property (atomic, assign) BOOL boolProperty;

@end

@implementation TestObject

@dynamic stringProperty;
@synthesize stringPropertyNonDynamic;
@dynamic stringPropertySetter;
@dynamic stringPropertyGetter;
@dynamic stringPropertySetterGetter;
@dynamic copyStringProperty;
@dynamic weakStringProperty;

@dynamic uint64Property;
@dynamic int64Property;
@dynamic uint32Property;
@dynamic int32Property;
@dynamic doubleProperty;
@dynamic floatProperty;
@dynamic boolProperty;

+ (NSURL*)defaultCommitPath {
    return [NSURL fileURLWithPath:STORE_PATH];
}

@end



@interface TestObjectSubclass : TestObject

@property (atomic, strong) NSString *subclassPropertyString;

@end

@implementation TestObjectSubclass

@dynamic subclassPropertyString;

@end



@interface TestObjectFail : FringeObject

@property (atomic, assign) short invalidProperty;

@end

@implementation TestObjectFail

@dynamic invalidProperty;

@end


#define FAIL_IF(TEST, FORMAT, ...) \
if( TEST ) { \
NSLog(@"%d: "FORMAT, __LINE__, ## __VA_ARGS__); \
exit(1);                       \
}

BOOL scanArrayForUUID(NSString *uuid, NSArray *array);
BOOL scanDictionaryForUUID(NSString *uuid, NSDictionary *dictionary);
BOOL scanObjectForUUID(NSString *uuid, id object);

BOOL scanArrayForUUID(NSString *uuid, NSArray *array) {
    for( id object in array ) {
        if( scanObjectForUUID(uuid, object) )
            return YES;
    }
    return NO;
}

BOOL scanDictionaryForUUID(NSString *uuid, NSDictionary *dictionary) {
    for( id object in [dictionary allValues] ) {
        if( scanObjectForUUID(uuid, object) )
            return YES;
    }
    return NO;
}

BOOL scanObjectForUUID(NSString *uuid, id object) {
    if( [object isKindOfClass:[NSString class]] )
        return [object isEqualToString:uuid];
    if( [object isKindOfClass:[NSDictionary class]] )
        return scanDictionaryForUUID(uuid, object);
    if( [object isKindOfClass:[NSArray class]] )
        return scanArrayForUUID(uuid, object);
    return NO;
}

int main(int c, char **v)
{
    NSLog(@"testing invalid property type");
    @try {
        TestObjectFail *foo = [[TestObjectFail alloc] initWithStore:nil];
        FAIL_IF(YES, @"accepted unsupported property type :( in %@", foo);
    }
    @catch(NSException *) {
        NSLog(@"didn't accept unsupported property type :)");
    }

    NSLog(@"testing initialization");
    TestObject *test1 = [[TestObject alloc] initWithDictionary:@{ @"uuid": @"UUID-1", @"stringProperty": @"it's a string" } inStore:nil];
    NSLog(@"test1: %@", test1);
    FAIL_IF( ! [test1.stringProperty isEqualToString:@"it's a string"], @"test1.stringProperty didn't initialize - %@", test1.stringProperty);

    NSLog(@"testing properties");
    test1.stringProperty = @"it's a different string";
    [test1 setPropertyString:@"foo"];
    [test1 setPropertyString2:@"bar"];
    test1.uint64Property = UINT64_MAX;
    test1.int64Property = INT64_MIN;
    test1.uint32Property = UINT32_MAX;
    test1.int32Property = INT32_MIN;
    test1.doubleProperty = M_PI;
    test1.floatProperty = M_PI;
    test1.boolProperty = YES;
    NSLog(@"test1: %@", test1);
    NSLog(@"[test1 proxyForJson]: %@", [test1 proxyForJson]);
    FAIL_IF( ! [test1.stringProperty isEqualToString:@"it's a different string"], @"test1.stringProperty didn't change - %@", test1.stringProperty);
    FAIL_IF( test1.int32Property != INT32_MIN, @"test1.intProperty != INT32_MIN");
    FAIL_IF( test1.doubleProperty != M_PI, @"test1.doubleProperty != MP_PI");

    NSLog(@"testing copy attribute");
    NSMutableString *mutableString1 = [NSMutableString stringWithString:@"not mutable"];
    test1.stringProperty = mutableString1;
    [mutableString1 deleteCharactersInRange:NSMakeRange(0, 4)];
    FAIL_IF(![test1.stringProperty isEqualToString:mutableString1], @"strong property isn't");

    NSMutableString *mutableString2 = [NSMutableString stringWithString:@"not mutable"];
    test1.copyStringProperty = mutableString2;
    [mutableString2 deleteCharactersInRange:NSMakeRange(0, 4)];
    FAIL_IF([test1.copyStringProperty isEqualToString:mutableString2], @"copy property didn't");

    NSLog(@"testing weak attribute");
    @autoreleasepool {
        // if you just assign this to @"weak" it creates a NSConstantString which _can't_ be released and so, invalidates the test
        NSString *weakString = [@"we" stringByAppendingString:@"ak"];
        @autoreleasepool {
            test1.weakStringProperty = weakString;
            FAIL_IF(test1.weakStringProperty != weakString, @"weak property released too soon");
        }
        FAIL_IF(test1.weakStringProperty != weakString, @"weak property released too soon");
    }
    FAIL_IF(test1.weakStringProperty, @"weak property not released");

    NSLog(@"testing object over-reuse");
    TestObject *test2 = [[TestObject alloc] initWithDictionary:@{ @"uuid": @"UUID-1", @"int32Property": @(5) } inStore:nil];
    NSLog(@"test2: %@", test2);
    FAIL_IF( test2.int32Property != 5, @"test2.intProperty != 5");

    NSLog(@"testing subclassing");
    TestObjectSubclass *test3 = [[TestObjectSubclass alloc] initWithDictionary:@{ @"uuid": @"UUID-3", @"int32Property": @(5), @"subclassPropertyString": @"boo" } inStore:nil];
    NSLog(@"test3: %@", test3);
    FAIL_IF( ! [test3.subclassPropertyString isEqualToString:@"boo"], @"test3.subclassPropertyString != \"boo\"");
    FAIL_IF( test3.int32Property != 5, @"test3.intProperty != 5");

    NSLog(@"testing store init");
    FringeObjectStore *storeEmpty = [FringeObjectStore storeWithUUID:@"nonexistant" atPath:STORE_PATH];
    FAIL_IF(storeEmpty, @"empty store, isn't");
    
    // TODO: lots more tests

    NSLog(@"All tests passed");
}
