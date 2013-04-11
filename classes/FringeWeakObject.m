//
//  WeakObject.m
//  fringetests
//
//  Created by Sean Meiners on 2012/10/04.
//  Copyright (c) 2012 Sean Meiners. All rights reserved.
//

#import "FringeWeakObject.h"

@implementation FringeWeakObject

+ (FringeWeakObject*)weakObject:(id<NSObject>)object {
    FringeWeakObject *weakObject = [[FringeWeakObject alloc] init];
    weakObject.object = object;
    return weakObject;
}

- (id)proxyForJson {
    return _object;
}

- (NSString*)description {
    return [NSString stringWithFormat:@"<%@: %p {%@}>", NSStringFromClass([self class]), self, _object];
}

@end
