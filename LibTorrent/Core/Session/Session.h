//
//  TorrentSession.h
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import <Foundation/Foundation.h>

#import <LibTorrent/Downloadable.h>
#import <LibTorrent/TorrentFile.h>
#import <LibTorrent/FileEntry.h>
#import <LibTorrent/SessionSettings.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ErrorCode) {
    ErrorCodeBadFile,
    ErrorCodeUndefined
} NS_SWIFT_NAME(ErrorCode);

@class Session, TorrentHandle;
@protocol SessionDelegate
- (void)torrentManager:(Session *)manager didAddTorrent:(TorrentHandle *)torrent;
- (void)torrentManager:(Session *)manager didRemoveTorrentWithHash:(TorrentHashes *)hashesData;
- (void)torrentManager:(Session *)manager didReceiveUpdateForTorrent:(TorrentHandle *)torrent;
- (void)torrentManager:(Session *)manager didErrorOccur:(NSError *)error;
@end

@interface StorageModel : NSObject
@property (readwrite, strong, nonatomic) NSUUID* uuid;
@property (readwrite, strong, nonatomic) NSString* name;
@property (readwrite, strong, nonatomic) NSData* pathBookmark;
/// Resolved URL, if cannot be resolved - last cached value
@property (readwrite, strong, nonatomic) NSURL* URL;
/// Path exists and was resolved
@property (readwrite, nonatomic) BOOL resolved;
/// Path exists and allowed to be used
@property (readwrite, nonatomic) BOOL allowed;
@end

@interface Session : NSObject

@property (readwrite, strong, nonatomic) NSString *downloadPath;
@property (readwrite, strong, nonatomic) NSString *torrentsPath;
@property (readwrite, strong, nonatomic) NSString *fastResumePath;

@property (readwrite, nonatomic) SessionSettings *settings;

@property (readonly) NSArray<TorrentHandle *> *torrents;
@property (readonly, strong, nonatomic) NSDictionary<TorrentHashes*, TorrentHandle*> *torrentsMap;

@property (readwrite) NSDictionary<NSUUID*, StorageModel*> *storages;

- (instancetype)initWith:(NSString *)downloadPath torrentsPath:(NSString *)torrentsPath fastResumePath:(NSString *)fastResumePath settings:(SessionSettings *)settings storages:(NSDictionary<NSUUID*, StorageModel*>*)storages;

- (NSString *)fastResumePathForInfoHashes:(TorrentHashes *)infoHashes;

- (void)addDelegate:(id<SessionDelegate>)delegate;
- (void)removeDelegate:(id<SessionDelegate>)delegate;

- (void)restoreSession;

- (TorrentHandle* _Nullable)addTorrent:(id<Downloadable>)torrent;
- (TorrentHandle* _Nullable)addTorrent:(id<Downloadable>)torrent to: (NSUUID* _Nullable)storage;
- (void)removeTorrent:(TorrentHandle *)torrent deleteFiles:(BOOL)deleteFiles;

- (void)pause;
- (void)resume;

@end

NS_ASSUME_NONNULL_END
