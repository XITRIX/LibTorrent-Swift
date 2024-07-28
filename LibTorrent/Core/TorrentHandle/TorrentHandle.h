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

NS_SWIFT_NAME(TorrentHashes)
@interface TorrentHashes : NSObject<NSCopying>
@property (readonly) BOOL hasV1;
@property (readonly) BOOL hasV2;
@property (readonly) NSData *v1;
@property (readonly) NSData *v2;
@property (readonly) NSData *best;
@end

NS_SWIFT_SENDABLE
NS_SWIFT_NAME(TorrentHandle.Snapshot)
@interface TorrentHandleSnapshot : NSObject

@property (readonly) BOOL isValid;
//@property (readonly) NSData *infoHash DEPRECATED_MSG_ATTRIBUTE("Use infoHashes instead");
@property (readonly) TorrentHashes *infoHashes;
@property (readonly) NSString* name;
@property (readonly) TorrentHandleState state;
@property (readonly, nullable) NSString *creator;
@property (readonly, nullable) NSString *comment;
@property (readonly, nullable) NSDate *creationDate;
@property (readonly) double progress;
@property (readonly) double progressWanted;
@property (readonly) NSUInteger numberOfPeers;
@property (readonly) NSUInteger numberOfSeeds;
@property (readonly) NSUInteger numberOfLeechers;
@property (readonly) NSUInteger numberOfTotalPeers;
@property (readonly) NSUInteger numberOfTotalSeeds;
@property (readonly) NSUInteger numberOfTotalLeechers;
@property (readonly) uint64_t downloadRate;
@property (readonly) uint64_t uploadRate;
@property (readonly) BOOL hasMetadata;
@property (readonly) uint64_t total;
@property (readonly) uint64_t totalDone;
@property (readonly) uint64_t totalWanted;
@property (readonly) uint64_t totalWantedDone;
@property (readonly) uint64_t totalDownload;
@property (readonly) uint64_t totalUpload;
@property (readonly) BOOL isPaused;
@property (readonly) BOOL isFinished;
@property (readonly) BOOL isSeed;
@property (readonly) BOOL isSequential;
@property (readonly, nullable) NSArray<NSNumber *> *pieces;
@property (readonly) NSArray<FileEntry *> *files;
@property (readonly) NSArray<TorrentTracker *> *trackers;
@property (readonly) NSString* magnetLink;
@property (readonly, nullable) NSString* torrentFilePath;
@property (readonly, nullable) NSURL* downloadPath;
@property (readonly, nullable) NSUUID* storageUUID;
@property (readonly) BOOL isStorageMissing;
@end

@interface TorrentHandle : TorrentHandleSnapshot

@property (readonly) Session* session;
@property (readonly) TorrentHandleSnapshot* snapshot;

//@property (readonly) NSArray<NSNumber *> *pieces;

@property (readonly) NSUInteger filesCount;
@property (readonly) NSArray<FileEntry *> *files;
- (FileEntry *)getFileAt:(int)index;

- (void)resume;
- (void)pause;
- (void)rehash;
- (void)reload;

- (void)setSequentialDownload:(BOOL)enabled;

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
