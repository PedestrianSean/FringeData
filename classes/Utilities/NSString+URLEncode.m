//
//  NSString+URLEncode.m
//  Givit
//
//  Created by Sean Meiners on 2011/11/01.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "NSString+URLEncode.h"

@implementation NSString (URLEncode)

- (NSString*)URLEncoded
{
    NSString *newString = CFBridgingRelease((CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                                     (__bridge CFStringRef)self,
                                                                                     NULL,
                                                                                     CFSTR(":/?#[]@!$ &'()*+,;=\"<>%{}|\\^~`"),
                                                                                     kCFStringEncodingUTF8)));
    if( newString )
        return newString;
    return @"";
}

@end
