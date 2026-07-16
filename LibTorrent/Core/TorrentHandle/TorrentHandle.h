//
//  NSObject+TorrentHandle.h
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import <Foundation/Foundation.h>

#import <LibTorrent/TorrentHandleState.h>
#import <LibTorrent/TorrentTracker.h>
#import <LibTorrent/FileEntry.h>

NS_ASSUME_NONNULL_BEGIN

@class Session;
@class StorageModel;
@class TorrentHandleSnapshot;

NS_SWIFT_NAME(TorrentHashes)
@interface TorrentHashes : NSObject<NSCopying>
@property (readonly) BOOL hasV1;
@property (readonly) BOOL hasV2;
@property (readonly) NSData *v1;
@property (readonly) NSData *v2;
@property (readonly) NSData *best;
@end

@interface TorrentHandle : NSObject

@property (readonly, nullable) NSUUID* storageUUID;
@property (readonly) TorrentHashes *infoHashes;
@property (readonly) BOOL isPrivate;

@property (readonly) Session* session;
@property (readonly) TorrentHandleSnapshot* snapshot;

- (void)resume;
- (void)pause;
- (void)rehash;
- (void)reload;

- (void)setSequentialDownload:(BOOL)enabled;
- (void)setFirstLastPriorityDownload:(BOOL)enabled;

- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex;
- (void)setFilesPriority:(FilePriority)priority at:(NSArray<NSNumber *> *)fileIndexes;
- (void)setAllFilesPriority:(FilePriority)priority;

- (void)addTracker:(NSString *)url;
- (void)removeTrackers:(NSArray<NSString *> *)urls;
- (void)forceReannounce;
- (void)forceReannounce:(int)index;

- (void)updateSnapshot;
@end

NS_ASSUME_NONNULL_END
