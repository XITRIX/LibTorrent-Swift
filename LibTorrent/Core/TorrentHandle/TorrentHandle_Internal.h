//
//  TorrentHandle_Internal.h
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import <Foundation/Foundation.h>
#import "TorrentHandle.h"

#import "libtorrent/torrent_handle.hpp"
#import "libtorrent/torrent_status.hpp"
#import "libtorrent/version.hpp"
#import "Session.h"

NS_ASSUME_NONNULL_BEGIN

@interface TorrentHashes ()
@property (readwrite) BOOL hasV1;
@property (readwrite) BOOL hasV2;
@property (readwrite) NSData *v1;
@property (readwrite) NSData *v2;
@property (readwrite) NSData *best;
@end

@interface TorrentHandle ()
@property lt::torrent_handle torrentHandle;
@property NSString *torrentPath;
@property NSString *sessionDownloadPath;
@property Session *session;

@property (readwrite) BOOL isFirstLastPiecePriority;
@property (readwrite, nullable) NSUUID* storageUUID;
@property (readwrite) TorrentHandleSnapshot* snapshot;

- (instancetype)initWith:(lt::torrent_handle)torrentHandle inSession:(Session *)session;
- (void)applyPriorityConfiguration;
- (void)applyPriorityConfigurationWithFilePriorities:(const std::vector<lt::download_priority_t> &)filePriorities
                                      saveResumeData:(BOOL)saveResumeData;


- (TorrentHandleSnapshot*)createSnapshotFromStatus:(lt::torrent_status) status
                                     torrentHandle: (lt::torrent_handle) torrentHandle
                                             owner: (TorrentHandle*) owner
                                       torrentPath: (NSString*) torrentPath
                                           session: (Session*) session
                                       storageUUID: (NSUUID* _Nullable) storageUUID
                          isFirstLastPiecePriority: (BOOL) isFirstLastPiecePriority;
@end


@interface TorrentHashes ()
#if LIBTORRENT_VERSION_MAJOR > 1
- (instancetype)initWith:(lt::info_hash_t)infoHash;
#else
- (instancetype)initWith:(lt::sha1_hash)infoHash;
#endif
@end

NS_ASSUME_NONNULL_END
