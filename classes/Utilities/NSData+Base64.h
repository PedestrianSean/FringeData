#import <Foundation/Foundation.h>

@interface NSData (Base64)

// ================================================================================================
//  base64.h
//  ViewTransitions
//
//  Created by Neo on 5/11/08.
//  Copyright 2008 Kaliware, LLC. All rights reserved.
//
// FOUND HERE http://idevkit.com/forums/tutorials-code-samples-sdk/8-nsdata-base64-extension.html
// ================================================================================================
+ (NSData *) dataWithBase64EncodedString:(NSString *) string;
- (id) initWithBase64EncodedString:(NSString *) string;

- (NSString *) base64Encoding;
- (NSString *) base64EncodingWithLineLength:(unsigned int) lineLength;

@end
