//
//  FringeObject.m
//
//  Created by Sean Meiners on 2012/10/01.
//  Copyright (c) 2012 Sean Meiners. All rights reserved.
//
//

#import "FringeObject.h"

#import <objc/runtime.h>
#import <objc/objc-sync.h>

#import "FringeObjectStore.h"
#import "NSObject+JSONSafety.h"
#import "NSString+UUID.h"
#import "FringeWeakObject.h"
#import "NSData+Base64.h"

static NSMutableDictionary *__strong s_registeredClasses = nil;

extern BOOL isFringeObjectClass(Class clas);

NSString *makeFileNameSafe(NSString *fileName)
{
    NSString *newString = CFBridgingRelease((CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                                     (__bridge CFStringRef)fileName,
                                                                                     NULL,
                                                                                     CFSTR(":/&%\\"),
                                                                                     kCFStringEncodingUTF8)));
    if( ! newString )
        return @"";
    if( [newString lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > NAME_MAX )
        newString = [NSString stringWithFormat:@"%d:%@:%@",
                     (int)[newString hash],
                     [newString substringWithRange:NSMakeRange(0, 20)],
                     [newString substringWithRange:NSMakeRange([newString length] - 20, 20)]];
    return newString;
}

NSString *makeFileNameUnSafe(NSString *fileName)
{
    NSString *newString = CFBridgingRelease((CFURLCreateStringByReplacingPercentEscapes(kCFAllocatorDefault,
                                                                                        (__bridge CFStringRef)fileName,
                                                                                        CFSTR(""))));
    if( ! newString )
        return @"";
    return newString;
}

#pragma mark - FringeObjectClassPropertyMetaData

@interface FringeObjectClassPropertyMetaData : NSObject {
@public
    unichar type;
    struct {
        unsigned atomic : 1;
        unsigned readonly : 1;
        unsigned copy : 1;
        unsigned weak : 1;
    } flags;
    SEL getter;
    Class transformerClass;
    Class objectType;
}
@end

@implementation FringeObjectClassPropertyMetaData
@end

#pragma mark - FringeObjectClassMetaData

@interface FringeObjectClassMetaData : NSObject

@property (nonatomic, strong) NSDictionary *selectorToPropertyNameMap;
@property (nonatomic, strong) NSDictionary *propertyMetaDataMap;

@end

@implementation FringeObjectClassMetaData
@end

#pragma mark - FringeObjectStore (Internal)

@interface FringeObjectStore (Internal)

- (void)removeObjectWithUUID:(NSString*)uuid;
- (void)addObject:(FringeObject*)object;
- (void)addChangedObject:(FringeObject*)object;

@end

#pragma mark - FringeObject

@interface FringeObject ()

@property (nonatomic, assign) BOOL isOnDisk;
@property (nonatomic, strong) FringeObjectStore *store;
@property (atomic, strong) NSMutableDictionary *jsonDataInternal;

@property (atomic, strong) NSDictionary *indexPaths;

@end

NSString *upperCaseFirst(NSString *str) {
    char *cstr = strdup([str UTF8String]);
    if( cstr[0] >= 'a' )
        cstr[0] -= ('a' - 'A');
    NSString *result = [NSString stringWithUTF8String:cstr];
    free(cstr);
    return result;
}

@implementation FringeObject

@synthesize isOnDisk = _isOnDisk;
@synthesize store = _store;
@synthesize jsonDataInternal = _jsonDataInternal;

@dynamic indexPaths;

- (void)setDefaultValues {
    // stub
}

- (id)initCommon {
    if( (self = [super init]) )
    {
        if( ! s_registeredClasses )
            s_registeredClasses = [NSMutableDictionary dictionaryWithCapacity:10];

        for( Class clas = [self class]; clas != [NSObject class]; clas = [clas superclass] )
        {
            if( ! [s_registeredClasses objectForKey:NSStringFromClass(clas)] ) {
                if( ! [self registerDynamicMethodsForClass:clas] ) {
                    return nil;
                }
            }
        }
    }

    return self;
}

- (id)initWithStore:(FringeObjectStore*)store {
    //NSLog(@"%p [%@ %@]", self, NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    if( (self = [self initCommon]) ) {
        _store = store;
        _jsonDataInternal = [NSMutableDictionary dictionaryWithCapacity:10];
        [_store lockWriteSync:^{
            [self setDefaultValues];
            [self.jsonDataInternal setObject:NSStringFromClass([self class]) forKey:@"class"];
            [self.jsonDataInternal setObject:[NSString stringWithNewUUID] forKey:@"uuid"];
        }];
        [_store addChangedObject:self];
    }
    return self;
}

- (id)initWithDictionary:(NSDictionary*)dictionary inStore:(FringeObjectStore*)store {
    //NSLog(@"%p [%@ %@]", self, NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    if( (self = [self initCommon]) ) {
        _store = store;
        _jsonDataInternal = [NSMutableDictionary dictionaryWithCapacity:10];
        [_store lockWriteSync:^{
            [self setDefaultValues];
            if( dictionary )
                [self.jsonDataInternal addEntriesFromDictionary:dictionary];
        }];
    }
    return self;
}

- (id)init {
    NSAssert([[[[self class] defaultCommitPath] absoluteString] length], @"%@ doesn't appear to be a root object, calling init is probably not what you want", NSStringFromClass([self class]));
    //NSLog(@"%p [%@ %@]", self, NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    if( (self = [self initCommon]) )
    {
        _jsonDataInternal = [NSMutableDictionary dictionaryWithCapacity:10];
        [self.jsonDataInternal setObject:[NSString stringWithNewUUID] forKey:@"uuid"];
        [self.jsonDataInternal setObject:NSStringFromClass([self class]) forKey:@"class"];
        _store = [FringeObjectStore storeWithRootObject:self atPath:nil];
        [_store lockWriteSync:^{
            [self setDefaultValues];
        }];
    }

    return self;
}

- (void)dealloc {
    //NSLog(@"%p [%@ %@]", self, NSStringFromClass([self class]), NSStringFromSelector(_cmd));
}

- (void)registerMethodWithSelectorName:(NSString*)selectorName
                            toSelector:(SEL)selector
                             withTypes:(const char*)types
                               onClass:(Class)clas
                       forPropertyName:(NSString*)propName
                       withPropertyMap:(NSMutableDictionary*)propertyMap
{
    //NSLog(@"registering [%@ %@] to [FringeObject %@]", NSStringFromClass(clas), selectorName, NSStringFromSelector(selector));
    class_addMethod(clas, sel_registerName([selectorName UTF8String]),
                    [self methodForSelector:selector], types);
    [propertyMap setObject:propName forKey:selectorName];
}

- (void)appendPropertiesOf:(Class)clas toString:(NSMutableString*)str
{
    FringeObjectClassMetaData *classMetaData = [s_registeredClasses objectForKey:NSStringFromClass(clas)];
    if( ! classMetaData )
        return;

#define APPEND_PRIMITIVE(TYPE, FORMAT) \
{ \
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[clas instanceMethodSignatureForSelector:propertyMetaData->getter]]; \
    [invocation setSelector:propertyMetaData->getter]; \
    [invocation setTarget:self]; \
    [invocation invoke]; \
    TYPE value; \
    [invocation getReturnValue:&value]; \
    [str appendFormat:FORMAT, value]; \
}
    
    [classMetaData.propertyMetaDataMap enumerateKeysAndObjectsUsingBlock:^(NSString *propNameStr, FringeObjectClassPropertyMetaData *propertyMetaData, BOOL *stop) {

        [str appendFormat:@"%@: ", propNameStr];
        switch (propertyMetaData->type) {
            case '@':
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                if( isFringeObjectClass(propertyMetaData->objectType) )
                    [str appendFormat:@"%@", [self getProperty:propNameStr]];
                else
                    [str appendFormat:@"%@", [self performSelector:propertyMetaData->getter]];
#pragma clang diagnostic pop
                break;

            case 'Q':
                APPEND_PRIMITIVE(uint64_t, @"%llu");
                break;

            case 'q':
                APPEND_PRIMITIVE(int64_t, @"%lld");
                break;

            case 'I':
                APPEND_PRIMITIVE(uint32_t, @"%u");
                break;

            case 'i':
                APPEND_PRIMITIVE(int32_t, @"%d");
                break;

            case 'd':
                APPEND_PRIMITIVE(double, @"%g");
                break;

            case 'f':
                APPEND_PRIMITIVE(float, @"%g");
                break;

            case 'c':
                APPEND_PRIMITIVE(char, @"%hhd");
                break;

            default:
                [str appendString:@"[?]"];
                break;
        }

        [str appendString:@", "];
    }];
}

- (NSString*)description {
    NSMutableString *result = [[NSMutableString alloc] initWithCapacity:40];
    [result appendFormat:@"<%@ \"%@\" {", NSStringFromClass([self class]), self.uuid];

    for( Class clas = [self class]; clas != [NSObject class]; clas = [clas superclass] )
        [self appendPropertiesOf:clas toString:result];

    [result appendString:@"}>"];
    return result;
}

- (BOOL)isEqual:(id)object {
    if( ! [object isKindOfClass:[FringeObject class]] )
        return NO;
    return [self.uuid isEqualToString:((FringeObject*)object).uuid];
}

- (BOOL)registerDynamicMethodsForClass:(Class)clas
{
    //NSLog(@"registerDynamicMethodsForClass: %@", NSStringFromClass(clas));

    IMP getterImplementationObject = [self methodForSelector:@selector(getObjectProperty)];
    IMP setterImplementationObject = [self methodForSelector:@selector(setObjectProperty:)];

    IMP getterImplementationData = [self methodForSelector:@selector(getDataProperty)];
    IMP setterImplementationData = [self methodForSelector:@selector(setDataProperty:)];

    IMP getterImplementationFringeObject = [self methodForSelector:@selector(getFringeObjectProperty)];
    IMP setterImplementationFringeObject = [self methodForSelector:@selector(setFringeObjectProperty:)];

    IMP getterImplementationTransformableObject = [self methodForSelector:@selector(getTransformableObjectProperty)];
    IMP setterImplementationTransformableObject = [self methodForSelector:@selector(setTransformableObjectProperty:)];

    IMP getterImplementationBool = [self methodForSelector:@selector(getBoolProperty)];
    IMP setterImplementationBool = [self methodForSelector:@selector(setBoolProperty:)];

    IMP getterImplementationUInt64 = [self methodForSelector:@selector(getUInt64Property)];
    IMP setterImplementationUInt64 = [self methodForSelector:@selector(setUInt64Property:)];

    IMP getterImplementationInt64 = [self methodForSelector:@selector(getInt64Property)];
    IMP setterImplementationInt64 = [self methodForSelector:@selector(setInt64Property:)];

    IMP getterImplementationUInt32 = [self methodForSelector:@selector(getUInt32Property)];
    IMP setterImplementationUInt32 = [self methodForSelector:@selector(setUInt32Property:)];

    IMP getterImplementationInt32 = [self methodForSelector:@selector(getInt32Property)];
    IMP setterImplementationInt32 = [self methodForSelector:@selector(setInt32Property:)];
    
    IMP getterImplementationFloat = [self methodForSelector:@selector(getFloatProperty)];
    IMP setterImplementationFloat = [self methodForSelector:@selector(setFloatProperty:)];

    IMP getterImplementationDouble = [self methodForSelector:@selector(getDoubleProperty)];
    IMP setterImplementationDouble = [self methodForSelector:@selector(setDoubleProperty:)];

    IMP getterImplementationNSSet = [self methodForSelector:@selector(getNSSetProperty)];
    IMP setterImplementationNSSet = [self methodForSelector:@selector(setNSSetProperty:)];

    IMP getterImplementationNSOrderedSet = [self methodForSelector:@selector(getNSOrderedSetProperty)];
    IMP setterImplementationNSOrderedSet = [self methodForSelector:@selector(setNSOrderedSetProperty:)];

    unsigned int propsCount = 0;
    objc_property_t *props = class_copyPropertyList(clas, &propsCount);

    NSMutableDictionary *propertyMap = [NSMutableDictionary dictionaryWithCapacity:(propsCount*2)];
    NSMutableDictionary *propertyMetaDataMap = [NSMutableDictionary dictionaryWithCapacity:(propsCount*2)];

    for( unsigned int i = 0; i < propsCount; ++i ) {
        NSString *propAttrsStr = [NSString stringWithUTF8String:property_getAttributes(props[i])];
        NSArray *propAttrs = [propAttrsStr componentsSeparatedByString:@","];

        // not dynamic, skip it
        if( [propAttrs indexOfObject:@"D"] == NSNotFound )
            continue;

        const char *propName = property_getName(props[i]);
        NSString *propNameStr = [NSString stringWithUTF8String:propName];
        FringeObjectClassPropertyMetaData *propertyMetaData = [[FringeObjectClassPropertyMetaData alloc] init];

        //NSLog(@"property - %@ - %@", propNameStr, propAttrs);

        propertyMetaData->flags.atomic      = [propAttrs indexOfObject:@"N"] == NSNotFound ? 1 : 0;
        propertyMetaData->flags.weak        = [propAttrs indexOfObject:@"W"] == NSNotFound ? 0 : 1;
        propertyMetaData->flags.readonly    = [propAttrs indexOfObject:@"R"] == NSNotFound ? 0 : 1;
        propertyMetaData->flags.copy        = [propAttrs indexOfObject:@"C"] == NSNotFound ? 0 : 1;

        [propertyMetaDataMap setObject:propertyMetaData forKey:propNameStr];

        NSUInteger index;

        index = [propAttrs indexOfObjectPassingTest:^BOOL(NSString *str, NSUInteger idx, BOOL *stop) {
            if( [str length] > 1 && [[str substringToIndex:1] isEqualToString:@"T"] ) {
                *stop = YES;
                return YES;
            }
            return NO;
        }];

        NSString *propTypeStr = [[propAttrs objectAtIndex:index] substringFromIndex:1];

        IMP getterImpl = NULL, setterImpl = NULL;
        const char *getterTypes = NULL, *setterTypes = NULL;

        propertyMetaData->type = [propTypeStr characterAtIndex:0];
        switch( propertyMetaData->type ) {
            case '@':
            {
                NSString *typeName = [propTypeStr substringFromIndex:1];
                if( [typeName length] > 2 && [typeName characterAtIndex:0] == '"' )
                    typeName = [typeName substringWithRange:NSMakeRange(1, [typeName length] - 2)];

                propertyMetaData->objectType = NSClassFromString(typeName);

                if( propertyMetaData->objectType == [NSSet class] ) {
                    getterImpl = getterImplementationNSSet;
                    setterImpl = setterImplementationNSSet;

                    NSString *propNameCap = upperCaseFirst(propNameStr);

                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"%@Count", propNameStr]
                                              toSelector:@selector(getNSSetCount)
                                               withTypes:"I@:"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];
                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"add%@Object:", propNameCap]
                                              toSelector:@selector(addObjectToNSSet:)
                                               withTypes:"v@:@"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];
                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"add%@:", propNameCap]
                                              toSelector:@selector(addObjectsToNSSet:)
                                               withTypes:"v@:@"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];

                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"remove%@Object:", propNameCap]
                                              toSelector:@selector(removeObjectFromNSSet:)
                                               withTypes:"v@:@"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];
                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"remove%@:", propNameCap]
                                              toSelector:@selector(removeObjectsFromNSSet:)
                                               withTypes:"v@:@"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];

                }
                else if( propertyMetaData->objectType == [NSOrderedSet class] ) {
                    getterImpl = getterImplementationNSOrderedSet;
                    setterImpl = setterImplementationNSOrderedSet;

                    NSString *propNameCap = upperCaseFirst(propNameStr);

                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"%@Count", propNameStr]
                                              toSelector:@selector(getNSOrderedSetCount)
                                               withTypes:"I@:"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];
                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"%@AtIndex:", propNameStr]
                                              toSelector:@selector(getNSOrderedSetObjectAtIndex:)
                                               withTypes:"@@:I"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];
                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"%@AtIndexes:", propNameStr]
                                              toSelector:@selector(getNSOrderedSetObjectsAtIndexes:)
                                               withTypes:"@@:@"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];
                    
                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"add%@Object:", propNameCap]
                                              toSelector:@selector(addObjectToNSOrderedSet:)
                                               withTypes:"v@:@"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];
                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"add%@:", propNameCap]
                                              toSelector:@selector(addObjectsToNSOrderedSet:)
                                               withTypes:"v@:@"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];

                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"remove%@Object:", propNameCap]
                                              toSelector:@selector(removeObjectFromNSOrderedSet:)
                                               withTypes:"v@:@"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];
                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"remove%@:", propNameCap]
                                              toSelector:@selector(removeObjectsFromNSOrderedSet:)
                                               withTypes:"v@:@"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];

                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"insertObject:in%@AtIndex:", propNameCap]
                                              toSelector:@selector(insertObject:inNSOrderedSetAtIndex:)
                                               withTypes:"v@:@I"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];
                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"insert%@:atIndexes:", propNameCap]
                                              toSelector:@selector(insertObjects:inNSOrderedSetAtIndexes:)
                                               withTypes:"v@:@@"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];

                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"replaceObjectIn%@AtIndex:withObject:", propNameCap]
                                              toSelector:@selector(replaceObjectInNSOrderedSetAtIndex:withObject:)
                                               withTypes:"v@:I@"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];
                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"replace%@AtIndexes:with%@:", propNameCap, propNameCap]
                                              toSelector:@selector(replaceObjectsInNSOrderedSetAtIndexes:withObjects:)
                                               withTypes:"v@:@@"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];

                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"removeObjectFrom%@AtIndex:", propNameCap]
                                              toSelector:@selector(removeObjectFromNSOrderedSetAtIndex:)
                                               withTypes:"v@:I"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];
                    [self registerMethodWithSelectorName:[NSString stringWithFormat:@"remove%@AtIndexes:", propNameCap]
                                              toSelector:@selector(removeObjectsFromNSOrderedSetAtIndexes:)
                                               withTypes:"v@:@"
                                                 onClass:clas
                                         forPropertyName:propNameStr
                                         withPropertyMap:propertyMap];
                }
                else if( propertyMetaData->objectType == [NSData class] ) {
                    getterImpl = getterImplementationData;
                    setterImpl = setterImplementationData;
                    getterTypes = [[propTypeStr stringByAppendingString:@"@:"] UTF8String];
                    setterTypes = [[@"v@:" stringByAppendingString:propTypeStr] UTF8String];
                }
                else {
                    if( isFringeObjectClass(propertyMetaData->objectType) ) {
                        getterImpl = getterImplementationFringeObject;
                        setterImpl = setterImplementationFringeObject;
                    }
                    else {
                        NSString *transformer = [typeName stringByAppendingString:@"Transformer"];
                        Class transformerClass = NSClassFromString(transformer);
                        if( transformerClass && [transformerClass superclass] == [NSValueTransformer class] ) {
                            propertyMetaData->transformerClass = transformerClass;
                            getterImpl = getterImplementationTransformableObject;
                            setterImpl = setterImplementationTransformableObject;
                        }
                        else {
                            getterImpl = getterImplementationObject;
                            setterImpl = setterImplementationObject;
                        }
                    }
                }
                getterTypes = [[propTypeStr stringByAppendingString:@"@:"] UTF8String];
                setterTypes = [[@"v@:" stringByAppendingString:propTypeStr] UTF8String];
                break;
            }

            case 'Q':
                getterImpl = getterImplementationUInt64;
                getterTypes = "Q@:";
                setterImpl = setterImplementationUInt64;
                setterTypes = "v@:Q";
                break;

            case 'q':
                getterImpl = getterImplementationInt64;
                getterTypes = "q@:";
                setterImpl = setterImplementationInt64;
                setterTypes = "v@:q";
                break;

            case 'I':
                getterImpl = getterImplementationUInt32;
                getterTypes = "I@:";
                setterImpl = setterImplementationUInt32;
                setterTypes = "v@:I";
                break;

            case 'i':
                getterImpl = getterImplementationInt32;
                getterTypes = "i@:";
                setterImpl = setterImplementationInt32;
                setterTypes = "v@:i";
                break;

            case 'd':
                getterImpl = getterImplementationDouble;
                getterTypes = "d@:";
                setterImpl = setterImplementationDouble;
                setterTypes = "v@:d";
                break;

            case 'f':
                getterImpl = getterImplementationFloat;
                getterTypes = "f@:";
                setterImpl = setterImplementationFloat;
                setterTypes = "v@:f";
                break;

            case 'c':
                getterImpl = getterImplementationBool;
                getterTypes = "c@:";
                setterImpl = setterImplementationBool;
                setterTypes = "v@:c";
                break;

            default:
                [NSException raise:NSInternalInconsistencyException format:@"Unrecognized type: \"%@\"", propTypeStr];
                break;
        }

        // look for the getter name
        index = [propAttrs indexOfObjectPassingTest:^BOOL(NSString *str, NSUInteger idx, BOOL *stop) {
            if( [str length] > 1 && [[str substringToIndex:1] isEqualToString:@"G"] ) {
                *stop = YES;
                return YES;
            }
            return NO;
        }];

        SEL getterSelector = NULL;
        // use the property name as the default getter
        if( index == NSNotFound )
            getterSelector = sel_registerName([propNameStr UTF8String]);
        else
            getterSelector = sel_registerName([[[propAttrs objectAtIndex:index] substringFromIndex:1] UTF8String]);

        //NSLog(@"getter = '%@'", NSStringFromSelector(getterSelector));

        class_addMethod(clas, getterSelector, getterImpl, getterTypes);
        [propertyMap setObject:propNameStr forKey:NSStringFromSelector(getterSelector)];
        propertyMetaData->getter = getterSelector;

        if( propertyMetaData->flags.readonly )
            continue;

        // look for the setter name
        index = [propAttrs indexOfObjectPassingTest:^BOOL(NSString *str, NSUInteger idx, BOOL *stop) {
            if( [str length] > 1 && [[str substringToIndex:1] isEqualToString:@"S"] ) {
                *stop = YES;
                return YES;
            }
            return NO;
        }];

        SEL setterSelector = NULL;
        // use "set<property name>" as the default setter
        if( index == NSNotFound ) {
            size_t propNameLen = strlen(propName);
            char *setterName = malloc(propNameLen+5);
            memcpy(setterName, "set", 3);
            memcpy(setterName+3, propName, propNameLen);
            if( setterName[3] >= 97 ) // upper-case
                setterName[3] -= 32;
            setterName[propNameLen+3] = ':';
            setterName[propNameLen+4] = 0;
            setterSelector = sel_registerName(setterName);
            free(setterName);
        }
        else
            setterSelector = sel_registerName([[[propAttrs objectAtIndex:index] substringFromIndex:1] UTF8String]);

        //NSLog(@"setter = '%@'", NSStringFromSelector(setterSelector));

        class_addMethod(clas, setterSelector, setterImpl, setterTypes);
        [propertyMap setObject:propNameStr forKey:NSStringFromSelector(setterSelector)];
    }
    free(props);

    FringeObjectClassMetaData *classMetaData = [[FringeObjectClassMetaData alloc] init];
    classMetaData.selectorToPropertyNameMap = [NSDictionary dictionaryWithDictionary:propertyMap];
    classMetaData.propertyMetaDataMap = [NSDictionary dictionaryWithDictionary:propertyMetaDataMap];
    [s_registeredClasses setObject:classMetaData forKey:NSStringFromClass(clas)];

    return YES;
}

+ (NSURL*)defaultCommitPath {
    return nil;
}

+ (NSSet*)indexedPropertyNames {
    return nil;
}

+ (NSURL*)indexURLForProperty:(NSString *)name withValue:(id)value forObject:(FringeObject*)object {
    return nil;
}

- (BOOL)forSelector:(SEL)selector getPropertyKey:(NSString**)key andPropertyMetaData:(FringeObjectClassPropertyMetaData**)propertyMetaData {
    NSString *selectorName = NSStringFromSelector(selector);
    for( Class clas = [self class]; clas != [NSObject class]; clas = [clas superclass] ) {
        FringeObjectClassMetaData *classMetaData = [s_registeredClasses objectForKey:NSStringFromClass(clas)];
        NSString *key_ = [classMetaData.selectorToPropertyNameMap objectForKey:selectorName];
        if( key_ ) {
            if( key )
                *key = key_;
            if( propertyMetaData )
                *propertyMetaData = [classMetaData.propertyMetaDataMap objectForKey:key_];
            return YES;
        }
    }
    return NO;
}

BOOL isFringeObjectProperty(Class clas) {
    if( ! clas )
        return NO;
    if( clas == [NSSet class] || clas == [NSOrderedSet class] )
        return YES;
    if( clas == [FringeObject class] )
        return YES;
    return isFringeObjectClass(class_getSuperclass(clas));
}

- (NSSet*)getPropertyNamesOfFringeObjectProperties {
    NSMutableSet *properties = [NSMutableSet setWithCapacity:5];
    for( Class clas = [self class]; clas != [NSObject class]; clas = [clas superclass] ) {
        FringeObjectClassMetaData *classMetaData = [s_registeredClasses objectForKey:NSStringFromClass(clas)];
        [classMetaData.propertyMetaDataMap enumerateKeysAndObjectsUsingBlock:^(NSString *key, FringeObjectClassPropertyMetaData *propertyMetaData, BOOL *stop) {
            if( isFringeObjectProperty(propertyMetaData->objectType) )
                [properties addObject:key];
        }];
    }
    return properties;
}

#define GET_KEY(RETVALUE) \
    NSString *key = nil; \
    FringeObjectClassPropertyMetaData *propertyMetaData = nil; \
    if( ! [self forSelector:_cmd getPropertyKey:&key andPropertyMetaData:&propertyMetaData] ) \
        return RETVALUE

- (FringeObjectStore*)fringeObjectStore {
    return _store;
}

- (void)setChanged {
    [_store addChangedObject:self];
}

- (id)proxyForJson {
    return _jsonDataInternal;
}

- (NSDictionary*)jsonData {
    return _jsonDataInternal;
}

- (NSString*)uuid {
    return [_jsonDataInternal objectForKey:@"uuid"];
}

- (void)setUuidInternal:(NSString *)uuid {
    [_store lockWriteAsync:^{
        [_jsonDataInternal setObject:uuid forKey:@"uuid"];
        [self setChanged];
    }];
}

#define SYNC_START_GET() \
    [_store lockReadSync:^{ \
        if( propertyMetaData->flags.atomic ) \
            objc_sync_enter(self)

#define SYNC_STOP_GET() \
        if( propertyMetaData->flags.atomic ) \
            objc_sync_exit(self); \
    }];

#define SYNC_START_SET() \
    [_store lockWriteAsync:^{ \
        if( propertyMetaData->flags.atomic ) \
            objc_sync_enter(self)

#define SYNC_STOP_SET() \
        if( propertyMetaData->flags.atomic ) \
            objc_sync_exit(self); \
    }];

- (FringeObjectClassPropertyMetaData*)getPropertyMetaDataFor:(NSString*)property {
    for( Class clas = [self class]; clas != [NSObject class]; clas = [clas superclass] ) {
        FringeObjectClassMetaData *classMetaData = [s_registeredClasses objectForKey:NSStringFromClass(clas)];
        FringeObjectClassPropertyMetaData *propertyMetaData = [classMetaData.propertyMetaDataMap objectForKey:property];
        if( propertyMetaData )
            return propertyMetaData;
    }
    return nil;
}

- (id)getProperty:(NSString*)key
{
    FringeObjectClassPropertyMetaData *propertyMetaData = [self getPropertyMetaDataFor:key];
    if( ! propertyMetaData )
        return nil;
    __block id obj = nil;
    SYNC_START_GET();
    obj = [_jsonDataInternal jsonObjectForKey:key];
    if( propertyMetaData->flags.weak )
        obj = [(FringeWeakObject*)obj object];
    SYNC_STOP_GET();
    return obj;
}

- (void)setProperty:(NSString*)key value:(id)value
{
    FringeObjectClassPropertyMetaData *propertyMetaData = [self getPropertyMetaDataFor:key];
    if( ! propertyMetaData )
        return;
    if( propertyMetaData->flags.copy )
        value = [value copy];
    if( propertyMetaData->flags.weak )
        value = [FringeWeakObject weakObject:value];
    SYNC_START_SET();
    if( value )
        [self.jsonDataInternal setObject:value forKey:key];
    else
        [self.jsonDataInternal removeObjectForKey:key];
    [self setChanged];
    SYNC_STOP_SET();
}

- (id)getObjectProperty {
    GET_KEY(nil);
    __block id obj = nil;
    SYNC_START_GET();
    obj = [_jsonDataInternal jsonObjectForKey:key];
    if( propertyMetaData->flags.weak )
        obj = [(FringeWeakObject*)obj object];
    SYNC_STOP_GET();
    return obj;
}

- (void)setObjectProperty:(id)value {
    GET_KEY();
    if( propertyMetaData->flags.copy )
        value = [value copy];
    if( propertyMetaData->flags.weak )
        value = [FringeWeakObject weakObject:value];
    SYNC_START_SET();
    if( value )
        [self.jsonDataInternal setObject:value forKey:key];
    else
        [self.jsonDataInternal removeObjectForKey:key];
    [self setChanged];
    SYNC_STOP_SET();
}

- (id)getFringeObjectProperty {
    GET_KEY(nil);
    __block id obj = nil;
    SYNC_START_GET();
    NSString *uuid = [_jsonDataInternal jsonStringForKey:key];
    obj = [_store objectWithUUID:uuid];
    SYNC_STOP_GET();
    return obj;
}

- (void)setFringeObjectProperty:(FringeObject*)value {
    GET_KEY();
    SYNC_START_SET();
    NSString *uuid = [_jsonDataInternal jsonStringForKey:key];
    if( uuid ) {
        if( [uuid isEqualToString:value.uuid] )
            return;
        [self.store removeObjectWithUUID:uuid];
    }
    if( value  ) {
        [self.store addObject:value];
        [self.jsonDataInternal setObject:value.uuid forKey:key];
    }
    else
        [self.jsonDataInternal removeObjectForKey:key];
    [self setChanged];
    SYNC_STOP_SET();
}

- (id)getDataProperty {
    GET_KEY(nil);

    __block id value = nil;
    SYNC_START_GET();
    value = [_jsonDataInternal jsonObjectForKey:key];
    SYNC_STOP_GET();
    if( ! value )
        return nil;
    return [NSData dataWithBase64EncodedString:value];
}

- (void)setDataProperty:(id)value {
    GET_KEY();

    value = [value base64Encoding];
    SYNC_START_SET();
    if( value )
        [self.jsonDataInternal setObject:value forKey:key];
    else
        [self.jsonDataInternal removeObjectForKey:key];
    [self setChanged];
    SYNC_STOP_SET();
}

- (id)getTransformableObjectProperty {
    GET_KEY(nil);

    if( ! [propertyMetaData->transformerClass allowsReverseTransformation] )
        return nil;

    __block id value = nil;
    SYNC_START_GET();
    value = [_jsonDataInternal jsonObjectForKey:key];
    SYNC_STOP_GET();
    if( ! value )
        return nil;

    id transformerInput = nil;

    if( [propertyMetaData->transformerClass transformedValueClass] == [NSString class] ) {
        if( [value isKindOfClass:[NSString class]] )
            transformerInput = value;
        else if( [value respondsToSelector:@selector(stringValue)] )
            transformerInput = [value stringValue];
        else
            transformerInput = [value description];
    }
    else if( [propertyMetaData->transformerClass transformedValueClass] == [NSData class] ) {
        if( [value isKindOfClass:[NSString class]] )
            transformerInput = [value dataUsingEncoding:NSUTF8StringEncoding];
        else if( [value respondsToSelector:@selector(stringValue)] )
            transformerInput = [[value stringValue] dataUsingEncoding:NSUTF8StringEncoding];
        else
            transformerInput = [[value description] dataUsingEncoding:NSUTF8StringEncoding];
    }

    if( ! transformerInput )
        return nil;

    NSValueTransformer *transformer = [[propertyMetaData->transformerClass alloc] init];
    return [transformer reverseTransformedValue:transformerInput];
}

- (void)setTransformableObjectProperty:(id)value {
    GET_KEY();

    NSValueTransformer *transformer = [[propertyMetaData->transformerClass alloc] init];
    id transformedValue = [transformer transformedValue:value];
    if( [propertyMetaData->transformerClass transformedValueClass] == [NSData class] )
        transformedValue = [[NSString alloc] initWithData:transformedValue encoding:NSUTF8StringEncoding];

    SYNC_START_SET();
    if( transformedValue )
        [self.jsonDataInternal setObject:transformedValue forKey:key];
    else
        [self.jsonDataInternal removeObjectForKey:key];
    [self setChanged];
    SYNC_STOP_SET();
}

#define PRIMITIVE_PROPERTY(TYPE, NAME)  \
- (TYPE)get##NAME##Property { \
    GET_KEY(0); \
    __block TYPE value; \
    SYNC_START_GET(); \
    value = [_jsonDataInternal json##NAME##ForKey:key]; \
    SYNC_STOP_GET(); \
    return value; \
} \
\
- (void)set##NAME##Property:(TYPE)value { \
    GET_KEY(); \
    SYNC_START_SET(); \
    [self.jsonDataInternal setObject:@(value) forKey:key]; \
    [self setChanged]; \
    SYNC_STOP_SET(); \
}

PRIMITIVE_PROPERTY(BOOL, Bool);
PRIMITIVE_PROPERTY(double, Double);
PRIMITIVE_PROPERTY(float, Float);
PRIMITIVE_PROPERTY(uint64_t, UInt64);
PRIMITIVE_PROPERTY(int64_t, Int64);
PRIMITIVE_PROPERTY(uint32_t, UInt32);
PRIMITIVE_PROPERTY(int32_t, Int32);

#define GET_NSSET_UUIDS(CREATE) \
    NSMutableArray *uuids = (NSMutableArray*)[_jsonDataInternal jsonArrayForKey:key]; \
    if( ! uuids && CREATE ) { \
        uuids = [NSMutableArray arrayWithCapacity:5]; \
        [_jsonDataInternal setObject:uuids forKey:key]; \
    } \

#pragma mark - NSSet

- (NSUInteger)getNSSetCount {
    if( ! _store )
        return 0;
    GET_KEY(0);
    __block NSUInteger count = 0;
    SYNC_START_GET();
    GET_NSSET_UUIDS(NO);
    count = [uuids count];
    SYNC_STOP_GET();
    return count;
}

- (NSSet*)getNSSetProperty
{
    if( ! _store )
        return nil;
    GET_KEY(nil);
    __block NSMutableSet *items = nil;
    SYNC_START_GET();
    GET_NSSET_UUIDS(NO);
    items = [NSMutableSet setWithCapacity:[uuids count]];
    for( NSString *uuid in uuids ) {
        id object = [_store objectWithUUID:uuid];
        if( object )
            [items addObject:object];
    }
    SYNC_STOP_GET();
    return items;
}

- (void)setNSSetProperty:(NSSet*)value
{
    GET_KEY();
    SYNC_START_SET();
    NSMutableArray *uuidsOld = (NSMutableArray*)[_jsonDataInternal jsonArrayForKey:key];
    NSMutableArray *uuidsNew = [NSMutableArray arrayWithCapacity:[value count]];
    for( FringeObject *fo in value ) {
        [self.store addObject:fo];
        [uuidsNew addObject:fo.uuid];
        [uuidsOld removeObject:fo.uuid];
    }
    [self setChanged];
    [self.jsonDataInternal setObject:uuidsNew forKey:key];
    for( NSString *uuid in uuidsOld )
        [self.store removeObjectWithUUID:uuid];
    SYNC_STOP_SET();
}

- (void)addObjectToNSSet:(FringeObject*)value
{
    GET_KEY();
    SYNC_START_SET();
    GET_NSSET_UUIDS(YES);
    if( ! [uuids containsObject:value.uuid] ) {
        [self.store addObject:value];
        [uuids addObject:value.uuid];
        [self setChanged];
    }
    SYNC_STOP_SET();
}

- (void)removeObjectFromNSSet:(FringeObject*)value
{
    GET_KEY();
    SYNC_START_SET();
    GET_NSSET_UUIDS(NO);
    [self.store removeObjectWithUUID:value.uuid];
    [self setChanged];
    SYNC_STOP_SET();
}

- (void)addObjectsToNSSet:(NSSet*)values
{
    GET_KEY();
    SYNC_START_SET();
    GET_NSSET_UUIDS(YES);
    NSMutableArray *valuesUUIDs = [NSMutableArray arrayWithCapacity:[values count]];
    for( FringeObject *fo in values ) {
        [self.store addObject:fo];
        [valuesUUIDs addObject:fo.uuid];
    }
    [self setChanged];
    [uuids addObjectsFromArray:valuesUUIDs];
    SYNC_STOP_SET();
}

- (void)removeObjectsFromNSSet:(NSSet*)values
{
    GET_KEY();
    SYNC_START_SET();
    GET_NSSET_UUIDS(NO);
    for( FringeObject *fo in values )
        [self.store removeObjectWithUUID:fo.uuid];
    [self setChanged];
    SYNC_STOP_SET();
}


#pragma mark - NSOrderedSet

- (NSUInteger)getNSOrderedSetCount {
    if( ! _store )
        return 0;
    GET_KEY(0);
    __block NSUInteger count = 0;
    SYNC_START_GET();
    GET_NSSET_UUIDS(NO);
    count = [uuids count];
    SYNC_STOP_GET();
    return count;
}

- (FringeObject*)getNSOrderedSetObjectAtIndex:(NSUInteger)index
{
    if( ! _store )
        return nil;
    GET_KEY(nil);
    __block FringeObject *obj = nil;
    SYNC_START_GET();
    GET_NSSET_UUIDS(NO);
    obj = [_store objectWithUUID:[uuids objectAtIndex:index]];
    SYNC_STOP_GET();
    return obj;
}

- (NSOrderedSet*)getNSOrderedSetObjectsAtIndexes:(NSIndexSet*)indexes
{
    if( ! _store )
        return nil;
    GET_KEY(nil);
    __block NSMutableOrderedSet *items = nil;
    SYNC_START_GET();
    GET_NSSET_UUIDS(NO);
    items = [NSMutableOrderedSet orderedSetWithCapacity:[indexes count]];
    for( NSString *uuid in [uuids objectsAtIndexes:indexes] ) {
        id object = [_store objectWithUUID:uuid];
        if( object )
            [items addObject:object];
    }
    SYNC_STOP_GET();
    return items;
}

- (NSOrderedSet*)getNSOrderedSetProperty
{
    if( ! _store )
        return nil;
    GET_KEY(nil);
    __block NSMutableOrderedSet *items = nil;
    SYNC_START_GET();
    GET_NSSET_UUIDS(NO);
    items = [NSMutableOrderedSet orderedSetWithCapacity:[uuids count]];
    for( NSString *uuid in uuids ) {
        id object = [_store objectWithUUID:uuid];
        if( object )
            [items addObject:object];
    }
    SYNC_STOP_GET();
    return items;
}

- (void)setNSOrderedSetProperty:(NSOrderedSet*)value
{
    GET_KEY();
    SYNC_START_SET();
    NSMutableArray *uuidsOld = (NSMutableArray*)[_jsonDataInternal jsonArrayForKey:key];
    NSMutableArray *uuidsNew = [NSMutableArray arrayWithCapacity:[value count]];
    for( FringeObject *fo in value ) {
        [self.store addObject:fo];
        [uuidsNew addObject:fo.uuid];
        [uuidsOld removeObject:fo.uuid];
    }
    [self setChanged];
    [self.jsonDataInternal setObject:uuidsNew forKey:key];
    for( NSString *uuid in uuidsOld )
        [self.store removeObjectWithUUID:uuid];
    SYNC_STOP_SET();
}

- (void)addObjectToNSOrderedSet:(FringeObject*)value
{
    GET_KEY();
    SYNC_START_SET();
    GET_NSSET_UUIDS(YES);
    if( ! [uuids containsObject:value.uuid] ) {
        [self.store addObject:value];
        [self setChanged];
        [uuids addObject:value.uuid];
    }
    SYNC_STOP_SET();
}

- (void)removeObjectFromNSOrderedSetAtIndex:(NSUInteger)idx
{
    GET_KEY();
    SYNC_START_SET();
    GET_NSSET_UUIDS(NO);
    [self.store removeObjectWithUUID:[uuids objectAtIndex:idx]];
    [self setChanged];
    SYNC_STOP_SET();
}

- (void)removeObjectFromNSOrderedSet:(FringeObject*)object
{
    GET_KEY();
    SYNC_START_SET();
    GET_NSSET_UUIDS(NO);
    [self.store removeObjectWithUUID:object.uuid];
    [self setChanged];
    SYNC_STOP_SET();
}

- (void)replaceObjectInNSOrderedSetAtIndex:(NSUInteger)idx withObject:(FringeObject*)value
{
    GET_KEY();
    SYNC_START_SET();
    GET_NSSET_UUIDS(NO);
    [self.store addObject:value];
    NSString *oldUUID = [uuids objectAtIndex:idx];
    [uuids replaceObjectAtIndex:idx withObject:value.uuid];
    [self.store removeObjectWithUUID:oldUUID];
    [self setChanged];
    SYNC_STOP_SET();
}

- (void)insertObject:(FringeObject*)value inNSOrderedSetAtIndex:(NSUInteger)idx
{
    GET_KEY();
    SYNC_START_SET();
    GET_NSSET_UUIDS(YES);
    [self.store addObject:value];
    [self setChanged];
    [uuids insertObject:value.uuid atIndex:idx];
    SYNC_STOP_SET();
}

- (void)insertObjects:(NSArray*)values inNSOrderedSetAtIndexes:(NSIndexSet*)indexes
{
    GET_KEY();
    SYNC_START_SET();
    GET_NSSET_UUIDS(YES);
    NSMutableArray *valuesUUIDs = [NSMutableArray arrayWithCapacity:[values count]];
    for( FringeObject *fo in values ) {
        [self.store addObject:fo];
        [valuesUUIDs addObject:fo.uuid];
    }
    [self setChanged];
    [uuids insertObjects:valuesUUIDs atIndexes:indexes];
    SYNC_STOP_SET();
}

- (void)removeObjectsFromNSOrderedSetAtIndexes:(NSIndexSet*)indexes
{
    GET_KEY();
    SYNC_START_SET();
    GET_NSSET_UUIDS(NO);
    NSMutableArray *removedUUIDs = [NSMutableArray arrayWithCapacity:[indexes count]];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [removedUUIDs addObject:[uuids objectAtIndex:idx]];
    }];
    for( NSString *uuid in removedUUIDs )
        [self.store removeObjectWithUUID:uuid];
    [self setChanged];
    SYNC_STOP_SET();
}

- (void)replaceObjectsInNSOrderedSetAtIndexes:(NSIndexSet*)indexes withObjects:(NSArray*)values
{
    GET_KEY();
    SYNC_START_SET();
    GET_NSSET_UUIDS(NO);
    NSMutableArray *valuesUUIDs = [NSMutableArray arrayWithCapacity:[values count]];
    NSMutableArray *removedUUIDs = [NSMutableArray arrayWithCapacity:[indexes count]];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [removedUUIDs addObject:[uuids objectAtIndex:idx]];
    }];
    for( FringeObject *fo in values ) {
        [self.store addObject:fo];
        [valuesUUIDs addObject:fo.uuid];
    }
    [uuids replaceObjectsAtIndexes:indexes withObjects:valuesUUIDs];
    for( NSString *uuid in removedUUIDs )
        [self.store removeObjectWithUUID:uuid];
    [self setChanged];
    SYNC_STOP_SET();
}

- (void)addObjectsToNSOrderedSet:(NSOrderedSet*)values
{
    GET_KEY();
    SYNC_START_SET();
    GET_NSSET_UUIDS(YES);
    NSMutableArray *valuesUUIDs = [NSMutableArray arrayWithCapacity:[values count]];
    for( FringeObject *fo in values ) {
        [self.store addObject:fo];
        [valuesUUIDs addObject:fo.uuid];
    }
    [self setChanged];
    [uuids addObjectsFromArray:valuesUUIDs];
    SYNC_STOP_SET();
}

- (void)removeObjectsFromNSOrderedSet:(NSOrderedSet*)values
{
    GET_KEY();
    SYNC_START_SET();
    GET_NSSET_UUIDS(NO);
    for( FringeObject *fo in values )
        [self.store removeObjectWithUUID:fo.uuid];
    [self setChanged];
    SYNC_STOP_SET();
}


@end
