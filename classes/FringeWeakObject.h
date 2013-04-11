//
//  FringeWeakObject.h
//
//  Created by Sean Meiners on 2012/10/04.
//  Copyright (c) 2012 Sean Meiners. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FringeWeakObject : NSObject

@property (nonatomic, weak) id<NSObject> object;

+ (FringeWeakObject*)weakObject:(id<NSObject>)object;

@end
