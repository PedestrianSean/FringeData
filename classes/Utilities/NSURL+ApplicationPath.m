//
//  NSURL+ApplicationPath.m
//  Givit
//
//  Created by Sean Meiners on 2011/10/24.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "NSURL+ApplicationPath.h"
#import "NSString+URLEncode.h"
#import <objc/runtime.h>

NSString *const kDownloadsFolderScheme = @"downloads";
NSString *const kDocumentFolderScheme = @"document";
NSString *const kLibraryFolderScheme = @"library";
NSString *const kTempFolderScheme = @"temp";
NSString *const kCacheFolderScheme = @"cache";

static inline NSString *downloadsFolder() {
    static NSString *__strong downloadsFolder = nil;
    if( ! downloadsFolder )
        downloadsFolder = [[[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByStandardizingPath] stringByAppendingPathComponent:@"Downloads"];
    return downloadsFolder;
}

static inline NSString *docFolder() {
    static NSString *__strong docFolder = nil;
    if( ! docFolder )
        docFolder = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByStandardizingPath];
    return docFolder;
}

static inline NSString *libFolder() {
    static NSString *__strong libFolder = nil;
    if( ! libFolder )
        libFolder = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject] stringByStandardizingPath];
    return libFolder;

}

static inline NSString *cacheFolder() {
    static NSString *__strong cacheFolder = nil;
    if( ! cacheFolder )
        cacheFolder = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByStandardizingPath];
    return cacheFolder;

}

static inline NSString *tempFolder() {
    static NSString *tempFolder = nil;
    if( ! tempFolder )
        tempFolder = [NSTemporaryDirectory() stringByStandardizingPath];
    return tempFolder;
}

@implementation NSURL (ApplicationPath)

+ (NSURL*)DownloadsURL {
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@:/",
                                 kDownloadsFolderScheme]];
}

+ (NSURL*)URLWithDownload:(NSString*)file {
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@:/%@",
                                 kDownloadsFolderScheme,
                                 [file URLEncoded]]];
}

+ (NSURL*)LibraryURL {
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@:/",
                                 kLibraryFolderScheme]];
}

+ (NSURL*)URLWithLibrary:(NSString *)file {
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@:/%@",
                                 kLibraryFolderScheme,
                                 [file URLEncoded]]];
}

+ (NSURL*)CacheURL {
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@:/",
                                 kCacheFolderScheme]];
}

+ (NSURL*)URLWithCacheFile:(NSString *)file {
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@:/%@",
                                 kCacheFolderScheme,
                                 [file URLEncoded]]];
}

- (NSString*)libraryPath {
    return [libFolder() stringByAppendingString:[self filePath]];
}

- (NSURL*)fileURLFromLibraryURL {
    if( ! [kLibraryFolderScheme isEqualToString:[self scheme]] ) {
        return nil;
    }
    return [NSURL fileURLWithPath:[self libraryPath]];
}

- (NSString*)downloadsPath {
    return [downloadsFolder() stringByAppendingString:[self filePath]];
}

- (NSURL*)fileURLFromDownloadsURL {
    if( ! [kDownloadsFolderScheme isEqualToString:[self scheme]] ) {
        return nil;
    }
    return [NSURL fileURLWithPath:[self downloadsPath]];
}

+ (NSURL*)DocumentsURL {
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@:/",
                                 kDocumentFolderScheme]];
}

+ (NSURL*)URLWithDocument:(NSString*)docfile {
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@:/%@",
                                 kDocumentFolderScheme,
                                 [docfile URLEncoded]]];
}

- (NSString*)documentPath {
    return [docFolder() stringByAppendingString:[self filePath]];
}

- (NSURL*)fileURLFromDocumentURL {
    if( ! [kDocumentFolderScheme isEqualToString:[self scheme]] ) {
        return nil;
    }
    return [NSURL fileURLWithPath:[self documentPath]];
}

+ (NSURL*)URLWithTempFile:(NSString*)tempfile {
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@:/%@",
                                 kTempFolderScheme,
                                 [tempfile URLEncoded]]];
    
}

- (NSString*)tempFilePath {
    return [tempFolder() stringByAppendingString:[self filePath]];
}

- (NSURL*)fileURLFromTempFileURL {
    if( ! [kTempFolderScheme isEqualToString:[self scheme]] ) {
        return nil;
    }
    return [NSURL fileURLWithPath:[self tempFilePath]];
}

- (NSString*)cacheFilePath {
    return [cacheFolder() stringByAppendingString:[self filePath]];
}

- (NSURL*)fileURLFromCacheFileURL {
    if( ! [kCacheFolderScheme isEqualToString:[self scheme]] ) {
        return nil;
    }
    return [NSURL fileURLWithPath:[self cacheFilePath]];
}

static Method s_origPathMethod = nil;

+ (void)initialize {
    s_origPathMethod = class_getInstanceMethod(self, @selector(path));
    method_exchangeImplementations(s_origPathMethod,
                                   class_getInstanceMethod(self, @selector(filePath)));
}

- (NSString*)filePath {
    NSString *scheme = [self scheme];
    if( [scheme isEqualToString:@"file"] ) {
        return [self filePath];
    }
    else if( [scheme isEqualToString:kDocumentFolderScheme] ) {
        return [self documentPath];
    }
    else if( [scheme isEqualToString:kDownloadsFolderScheme] ) {
        return [self downloadsPath];
    }
    else if( [scheme isEqualToString:kLibraryFolderScheme] ) {
        return [self libraryPath];
    }
    else if( [scheme isEqualToString:kTempFolderScheme] ) {
        return [self tempFilePath];
    }
    else if( [scheme isEqualToString:kCacheFolderScheme] ) {
        return [self cacheFilePath];
    }
    return [self filePath];
}

- (NSURL*)fileURL {
    NSString *scheme = [self scheme];
    if( [scheme isEqualToString:@"file"] ) {
        return self;
    }
    else if( [scheme isEqualToString:kDocumentFolderScheme] ) {
        return [self fileURLFromDocumentURL];
    }
    else if( [scheme isEqualToString:kDownloadsFolderScheme] ) {
        return [self fileURLFromDownloadsURL];
    }
    else if( [scheme isEqualToString:kLibraryFolderScheme] ) {
        return [self fileURLFromLibraryURL];
    }
    else if( [scheme isEqualToString:kTempFolderScheme] ) {
        return [self fileURLFromTempFileURL];
    }
    else if( [scheme isEqualToString:kCacheFolderScheme] ) {
        return [self fileURLFromCacheFileURL];
    }
    return self;
}

- (NSURL*)shortenedURL
{
    NSString *scheme = [self scheme];
    if( ! [scheme isEqualToString:@"file"] )
        return self;
    
    NSString *path = [[self filePath] stringByStandardizingPath];
    NSString *folder;

    folder = downloadsFolder();
    if( [path length] > [folder length] && [[path substringToIndex:[folder length]] isEqualToString:folder] )
        return [NSURL URLWithDownload:[path substringFromIndex:([folder length]+1)]];

    folder = docFolder();
    if( [path length] > [folder length] && [[path substringToIndex:[folder length]] isEqualToString:folder] )
        return [NSURL URLWithDocument:[path substringFromIndex:([folder length]+1)]];

    folder = libFolder();
    if( [path length] > [folder length] && [[path substringToIndex:[folder length]] isEqualToString:folder] )
        return [NSURL URLWithLibrary:[path substringFromIndex:([folder length]+1)]];

    folder = tempFolder();
    if( [path length] > [folder length] && [[path substringToIndex:[folder length]] isEqualToString:folder] )
        return [NSURL URLWithTempFile:[path substringFromIndex:([folder length]+1)]];

    folder = cacheFolder();
    if( [path length] > [folder length] && [[path substringToIndex:[folder length]] isEqualToString:folder] )
        return [NSURL URLWithCacheFile:[path substringFromIndex:([folder length]+1)]];

    return self;
}

@end
