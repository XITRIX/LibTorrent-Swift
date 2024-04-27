//
//  TorrentFile.h
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import <Foundation/Foundation.h>

#import <LibTorrent/Downloadable.h>
#import <LibTorrent/FileEntry.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_SENDABLE
@interface TorrentFile : NSObject <Downloadable>
@property (readonly, strong, nonatomic) NSData *fileData;
@property (readonly) NSString *name;
@property (readonly) NSArray<FileEntry *> *files;
@property (readonly) BOOL isValid;

- (instancetype)initUnsafeWithFileAtURL:(NSURL *)fileURL;
- (instancetype)initUnsafeWithFileWithData:(NSData *)data ;

- (FileEntry *)getFileAt:(int)index;
- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex;
- (void)setFilesPriority:(FilePriority)priority at:(NSArray<NSNumber *> *)fileIndexes;
- (void)setAllFilesPriority:(FilePriority)priority;

@end

NS_ASSUME_NONNULL_END
