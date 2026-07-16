//
//  NSObject+TorrentHandle.m
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import "TorrentHandle_Internal.h"
#import "TorrentHandleSnapshot_Internal.h"
#import "FileEntry_Internal.h"
#import "TorrentTracker_Internal.h"
#import "Session_Internal.h"

#import "NSData+Hex.h"

#import "libtorrent/torrent_status.hpp"
#import "libtorrent/torrent_info.hpp"
#import "libtorrent/magnet_uri.hpp"

static std::vector<lt::download_priority_t> piecePrioritiesForFiles(
    lt::torrent_info const &torrentInfo,
    std::vector<lt::download_priority_t> const &filePriorities,
    bool firstLastPiecePriorityEnabled)
{
    auto const &files = torrentInfo.files();
    auto piecePriorities = std::vector<lt::download_priority_t>(torrentInfo.num_pieces(), lt::dont_download);

    for (int index = 0; index < files.num_files(); ++index) {
        auto fileIndex = static_cast<lt::file_index_t>(index);
        auto filePriority = filePriorities[index];
        if (filePriority <= lt::dont_download) {
            continue;
        }

        auto fileSize = files.file_size(fileIndex);
        if (fileSize <= 0) {
            continue;
        }

        auto const firstPiece = files.map_file(fileIndex, 0, 0).piece;
        auto const lastPiece = files.map_file(fileIndex, fileSize - 1, 1).piece;
        auto const pieceCount = static_cast<int>(lastPiece - firstPiece) + 1;
        auto const piecePriority = firstLastPiecePriorityEnabled ? lt::top_priority : filePriority;
        std::int64_t const edgeSpan = std::int64_t(torrentInfo.piece_length()) * 100;
        int edgePieceCount = static_cast<int>((fileSize + edgeSpan - 1) / edgeSpan);
        if (edgePieceCount > pieceCount) {
            edgePieceCount = pieceCount;
        }

        for (int pieceOffset = 0; pieceOffset < edgePieceCount; ++pieceOffset) {
            piecePriorities[static_cast<int>(firstPiece) + pieceOffset] = piecePriority;
            piecePriorities[static_cast<int>(lastPiece) - pieceOffset] = piecePriority;
        }

        for (int pieceIndex = static_cast<int>(firstPiece) + edgePieceCount;
             pieceIndex <= static_cast<int>(lastPiece) - edgePieceCount;
             ++pieceIndex) {
            piecePriorities[pieceIndex] = filePriority;
        }
    }

    return piecePriorities;
}

@implementation TorrentHashes

#if LIBTORRENT_VERSION_MAJOR > 1
- (instancetype)initWith:(lt::info_hash_t)infoHash {
    self = [self init];
    if (self) {
        _v1 = [[NSData alloc] initWithBytes:infoHash.v1.data() length:infoHash.v1.size()];
        _v2 = [[NSData alloc] initWithBytes:infoHash.v2.data() length:infoHash.v2.size()];
        _hasV1 = infoHash.has_v1();
        _hasV2 = infoHash.has_v2();

        auto best = infoHash.get_best();
        _best = [[NSData alloc] initWithBytes:best.data() length:best.size()]; ;
    }
    return self;
}
#else
- (instancetype)initWith:(lt::sha1_hash)infoHash {
    self = [self init];
    if (self) {
        _v1 = [[NSData alloc] initWithBytes:infoHash.data() length:infoHash.size()];
        _v2 = NULL;
        _hasV1 = true;
        _hasV2 = false;

        _best = _v1;
    }
    return self;
}
#endif

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    } 

    if (![other isKindOfClass:[TorrentHashes class]]) {
        return NO;
    }

    return [self.best isEqual:((TorrentHashes *)other).best];

//    return [self.v1 isEqual:((TorrentHashes *)other).v1] && [self.v2 isEqual:((TorrentHashes *)other).v2];
}

- (NSUInteger)hash {
    return _best.hash;
}

- (nonnull id)copyWithZone:(nullable NSZone *)zone {
    TorrentHashes* copy = [[[self class] allocWithZone:zone] init];

        if (copy) {
            copy.v1 = self.v1;
            copy.v2 = self.v2;
            copy.hasV1 = self.hasV1;
            copy.hasV2 = self.hasV2;
            copy.best = self.best;
        }

        return copy;
}

@end

@implementation TorrentHandle

- (instancetype)initWith:(lt::torrent_handle)torrentHandle inSession:(Session *)session {
    self = [self init];
    if (self) {
        _session = session;
        _torrentHandle = torrentHandle;
        _torrentPath = session.torrentsPath;
        _sessionDownloadPath = session.downloadPath;
        _isFirstLastPiecePriority = NO;
    }
    return self;
}

- (BOOL)isValid {
    return self.torrentHandle.is_valid();
}

- (NSUInteger)hash {
    return self.infoHashes.best.hash;
}

//- (NSData *)infoHash {
//    return [self.infoHashes best];
//}

- (TorrentHashes *)infoHashes {
#if LIBTORRENT_VERSION_MAJOR > 1
    auto ih = _torrentHandle.info_hashes();
#else
    auto ih = _torrentHandle.info_hash();
#endif
    return [[TorrentHashes alloc] initWith:ih];
}

- (BOOL)isPrivate {
    if (!_torrentHandle.is_valid()) { return NO; }

    auto torrentInfo = _torrentHandle.torrent_file();
    return torrentInfo != nullptr && torrentInfo->priv();
}

// MARK: - Functions

- (void)resume {
    _torrentHandle.unset_flags(lt::torrent_flags::auto_managed);
    _torrentHandle.resume();
}

- (void)pause {
    _torrentHandle.unset_flags(lt::torrent_flags::auto_managed);
    _torrentHandle.pause();
}

- (void)rehash {
    _torrentHandle.force_recheck();
    _torrentHandle.set_flags(lt::torrent_flags::auto_managed);
}

- (void)reload {
    auto status = _torrentHandle.status();
    auto snapshot = [self createSnapshotFromStatus:status
                                     torrentHandle:_torrentHandle
                                             owner:self
                                       torrentPath:_torrentPath
                                           session:_session
                                       storageUUID:self.storageUUID
                          isFirstLastPiecePriority:self.isFirstLastPiecePriority];
    
    auto torrentFile = [[TorrentFile alloc] initUnsafeWithFileAtURL:[[NSURL alloc] initFileURLWithPath:snapshot.torrentFilePath]];
    _session.session->remove_torrent(_torrentHandle);
    auto newTorrentHandle = [_session addTorrent: torrentFile];
    _torrentHandle = newTorrentHandle.torrentHandle;
    [self updateSnapshot];
}

- (void)setSequentialDownload:(BOOL)enabled {
    if (!_torrentHandle.is_valid()) return;
    
    if (enabled) {
        _torrentHandle.set_flags(lt::torrent_flags::sequential_download);
    } else {
        _torrentHandle.unset_flags(lt::torrent_flags::sequential_download);
    }
    _torrentHandle.save_resume_data();
    _torrentHandle.post_status();

}

- (void)applyPriorityConfiguration {
    if (!_torrentHandle.is_valid()) return;

    auto filePriorities = _torrentHandle.get_file_priorities();
    [self applyPriorityConfigurationWithFilePriorities:filePriorities saveResumeData:YES];
}

- (void)applyPriorityConfigurationWithFilePriorities:(const std::vector<lt::download_priority_t> &)filePriorities
                                      saveResumeData:(BOOL)saveResumeData {
    if (!_torrentHandle.is_valid()) return;

    // File priorities remain the source of truth. Piece priorities are derived from them
    // and the first/last-piece flag whenever any priority-related setting changes.
    _torrentHandle.prioritize_files(filePriorities);

    auto torrentInfoPtr = _torrentHandle.torrent_file();
    if (torrentInfoPtr != nullptr) {
        auto piecePriorities = piecePrioritiesForFiles(*torrentInfoPtr, filePriorities, _isFirstLastPiecePriority);
        _torrentHandle.prioritize_pieces(piecePriorities);
    }

    if (saveResumeData) {
        _torrentHandle.save_resume_data();
    }
}

- (void)setFirstLastPriorityDownload:(BOOL)enabled {
    _isFirstLastPiecePriority = enabled;
    [self applyPriorityConfiguration];
}

- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex {
    auto priorities = _torrentHandle.get_file_priorities();
    priorities[(int)fileIndex] = static_cast<lt::download_priority_t>(priority);
    [self applyPriorityConfigurationWithFilePriorities:priorities saveResumeData:YES];
}

- (void)setFilesPriority:(FilePriority)priority at:(NSArray<NSNumber *> *)fileIndexes {
    auto priorities = _torrentHandle.get_file_priorities();
    for (int i = 0; i < fileIndexes.count; i++) {
        int index = (int)fileIndexes[i].integerValue;
        priorities[index] = static_cast<lt::download_priority_t>(priority);
    }
    [self applyPriorityConfigurationWithFilePriorities:priorities saveResumeData:YES];
}

- (void)setAllFilesPriority:(FilePriority)priority {
    std::vector<lt::download_priority_t> array;
    for (int i = 0; i < _torrentHandle.torrent_file().get()->files().num_files(); i++) {
        array.push_back(static_cast<lt::download_priority_t>(priority));
    }
    [self applyPriorityConfigurationWithFilePriorities:array saveResumeData:YES];
}

- (void)addTracker:(NSString *)url {
    _torrentHandle.add_tracker(lt::announce_entry(url.UTF8String));
}

- (void)removeTrackers:(NSArray<NSString *> *)urls {
    auto trackers = _torrentHandle.trackers();
    std::vector<lt::announce_entry> newTrackers;

    for (auto tracker: trackers) {
        if ([urls containsObject: [NSString stringWithFormat:@"%s", tracker.url.c_str()]]) { continue; }
        newTrackers.push_back(tracker);
    }

    _torrentHandle.replace_trackers(newTrackers);
    _torrentHandle.force_reannounce();
}

- (void)forceReannounce {
    [self forceReannounce: -1];
}

- (void)forceReannounce:(int)index {
    _torrentHandle.force_reannounce(0, index);
}

- (void)updateSnapshot {
    if (!self.isValid) return;

    try {
        auto status = _torrentHandle.status();
        self.snapshot = [self createSnapshotFromStatus:status
                                          torrentHandle:_torrentHandle
                                                  owner:self
                                            torrentPath:_torrentPath
                                                session:_session
                                            storageUUID:_storageUUID
                               isFirstLastPiecePriority:_isFirstLastPiecePriority];
    } catch(...) {}
}

- (TorrentHandleSnapshot*)createSnapshotFromStatus:(lt::torrent_status) status
                                     torrentHandle: (lt::torrent_handle) torrentHandle
                                             owner: (TorrentHandle*) owner
                                       torrentPath: (NSString*) torrentPath
                                           session: (Session*) session
                                       storageUUID: (NSUUID* _Nullable) storageUUID
                          isFirstLastPiecePriority: (BOOL) isFirstLastPiecePriority
  {
      return [[TorrentHandleSnapshot alloc] initWithStatus:status
                                             torrentHandle:torrentHandle
                                                     owner:owner
                                               torrentPath:torrentPath
                                                   session:session
                                               storageUUID:storageUUID
                                  isFirstLastPiecePriority:isFirstLastPiecePriority];
  }

@end
