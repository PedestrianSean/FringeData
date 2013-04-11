//
//  NSURL+ApplicationPath.h
//
//  Created by Sean Meiners on 2011/10/24.
//  Copyright (c) 2012 Sean Meiners. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *const kDownloadsFolderScheme;
extern NSString *const kDocumentFolderScheme;
extern NSString *const kLibraryFolderScheme;
extern NSString *const kTempFolderScheme;
extern NSString *const kCacheFolderScheme;

@interface NSURL (ApplicationPath)

+ (NSURL*)DownloadsURL;
+ (NSURL*)DocumentsURL;
+ (NSURL*)LibraryURL;
+ (NSURL*)CacheURL;
+ (NSURL*)URLWithDownload:(NSString*)file;
+ (NSURL*)URLWithDocument:(NSString*)docfile;
+ (NSURL*)URLWithLibrary:(NSString*)libfile;
+ (NSURL*)URLWithTempFile:(NSString*)tempfile;
+ (NSURL*)URLWithCacheFile:(NSString*)cachefile;

- (NSURL*)fileURL;
- (NSURL*)shortenedURL;

@end
