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

typedef void (^TorrentHandleOperation)(lt::torrent_handle const &handle);

@interface TorrentHandle (SafeOperations)
- (void)performOperation:(NSString *)operation action:(TorrentHandleOperation)action;
- (void)reportException:(std::exception const &)exception operation:(NSString *)operation;
- (void)reportUnknownExceptionForOperation:(NSString *)operation;
- (void)applyPriorityConfigurationToHandle:(lt::torrent_handle const &)handle
                            filePriorities:(std::vector<lt::download_priority_t> const &)filePriorities
                            saveResumeData:(BOOL)saveResumeData;
@end

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
#if LIBTORRENT_VERSION_MAJOR > 1
        _cachedInfoHashes = [[TorrentHashes alloc] initWith:torrentHandle.info_hashes()];
#else
        _cachedInfoHashes = [[TorrentHashes alloc] initWith:torrentHandle.info_hash()];
#endif
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
    return _cachedInfoHashes;
}

- (BOOL)isPrivate {
    __block BOOL result = NO;
    [self performOperation:@"isPrivate" action:^(lt::torrent_handle const &handle) {
        auto torrentInfo = handle.torrent_file();
        result = torrentInfo != nullptr && torrentInfo->priv();
    }];
    return result;
}

// MARK: - Functions

- (void)resume {
    [self performOperation:@"resume" action:^(lt::torrent_handle const &handle) {
        // resume() alone does not recover a torrent that libtorrent placed in
        // an error state. clear_error() both clears that state and makes the
        // torrent eligible to start again.
        handle.clear_error();
        handle.unset_flags(lt::torrent_flags::auto_managed);
        handle.resume();
    }];
}

- (void)pause {
    [self performOperation:@"pause" action:^(lt::torrent_handle const &handle) {
        handle.unset_flags(lt::torrent_flags::auto_managed);
        handle.pause();
    }];
}

- (void)clearError {
    [self performOperation:@"clearError" action:^(lt::torrent_handle const &handle) {
        handle.clear_error();
        handle.post_status();
    }];
}

- (void)rehash {
    [self performOperation:@"rehash" action:^(lt::torrent_handle const &handle) {
        handle.force_recheck();
        handle.set_flags(lt::torrent_flags::auto_managed);
    }];
}

- (void)reload {
    BOOL didReload = NO;
    @synchronized (self) {
        auto torrentHandle = _torrentHandle;
        if (!torrentHandle.is_valid()) {
            [_session reportErrorWithCode:ErrorCodeInvalidTorrentHandle
                                operation:@"reload"
                                  message:@"Handle was invalid before the operation started"];
            return;
        }

        try {
            auto status = torrentHandle.status();
            auto snapshot = [self createSnapshotFromStatus:status
                                             torrentHandle:torrentHandle
                                                     owner:self
                                               torrentPath:_torrentPath
                                                   session:_session
                                               storageUUID:self.storageUUID
                                  isFirstLastPiecePriority:self.isFirstLastPiecePriority];

            NSString *torrentFilePath = snapshot.torrentFilePath;
            if (torrentFilePath == nil) {
                [_session reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                                    operation:@"reload"
                                      message:@"No persisted torrent file was available"];
                return;
            }

            auto torrentFile = [[TorrentFile alloc] initUnsafeWithFileAtURL:[[NSURL alloc] initFileURLWithPath:torrentFilePath]];
            _session.session->remove_torrent(torrentHandle);
            auto newTorrentHandle = [_session addTorrent:torrentFile];
            if (newTorrentHandle == nil) {
                [_session reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                                    operation:@"reload"
                                      message:@"Failed to add the torrent after removing its previous handle"];
                return;
            }

            _torrentHandle = newTorrentHandle.torrentHandle;
            _cachedInfoHashes = newTorrentHandle.infoHashes;
            didReload = YES;
        } catch (std::exception const &exception) {
            [self reportException:exception operation:@"reload"];
        } catch (...) {
            [self reportUnknownExceptionForOperation:@"reload"];
        }
    }
    if (didReload) {
        [self updateSnapshot];
    }
}

- (void)setSequentialDownload:(BOOL)enabled {
    [self performOperation:@"setSequentialDownload" action:^(lt::torrent_handle const &handle) {
        if (enabled) {
            handle.set_flags(lt::torrent_flags::sequential_download);
        } else {
            handle.unset_flags(lt::torrent_flags::sequential_download);
        }
        handle.save_resume_data();
        handle.post_status();
    }];
}

- (void)applyPriorityConfiguration {
    [self performOperation:@"applyPriorityConfiguration" action:^(lt::torrent_handle const &handle) {
        auto filePriorities = handle.get_file_priorities();
        [self applyPriorityConfigurationToHandle:handle
                                 filePriorities:filePriorities
                                 saveResumeData:YES];
    }];
}

- (void)applyPriorityConfigurationWithFilePriorities:(const std::vector<lt::download_priority_t> &)filePriorities
                                      saveResumeData:(BOOL)saveResumeData {
    [self performOperation:@"applyPriorityConfiguration" action:^(lt::torrent_handle const &handle) {
        [self applyPriorityConfigurationToHandle:handle
                                 filePriorities:filePriorities
                                 saveResumeData:saveResumeData];
    }];
}

- (void)applyPriorityConfigurationToHandle:(lt::torrent_handle const &)handle
                            filePriorities:(const std::vector<lt::download_priority_t> &)filePriorities
                            saveResumeData:(BOOL)saveResumeData {
    // File priorities remain the source of truth. Piece priorities are derived from them
    // and the first/last-piece flag whenever any priority-related setting changes.
    handle.prioritize_files(filePriorities);

    auto torrentInfoPtr = handle.torrent_file();
    if (torrentInfoPtr != nullptr) {
        auto piecePriorities = piecePrioritiesForFiles(*torrentInfoPtr, filePriorities, _isFirstLastPiecePriority);
        handle.prioritize_pieces(piecePriorities);
    }

    if (saveResumeData) {
        handle.save_resume_data();
    }
}

- (void)setFirstLastPriorityDownload:(BOOL)enabled {
    [self performOperation:@"setFirstLastPriorityDownload" action:^(lt::torrent_handle const &handle) {
        _isFirstLastPiecePriority = enabled;
        auto filePriorities = handle.get_file_priorities();
        [self applyPriorityConfigurationToHandle:handle
                                 filePriorities:filePriorities
                                 saveResumeData:YES];
    }];
}

- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex {
    [self performOperation:@"setFilePriority" action:^(lt::torrent_handle const &handle) {
        auto priorities = handle.get_file_priorities();
        if (fileIndex < 0 || static_cast<std::size_t>(fileIndex) >= priorities.size()) { return; }
        priorities[static_cast<std::size_t>(fileIndex)] = static_cast<lt::download_priority_t>(priority);
        [self applyPriorityConfigurationToHandle:handle filePriorities:priorities saveResumeData:YES];
    }];
}

- (void)setFilesPriority:(FilePriority)priority at:(NSArray<NSNumber *> *)fileIndexes {
    [self performOperation:@"setFilesPriority" action:^(lt::torrent_handle const &handle) {
        auto priorities = handle.get_file_priorities();
        for (NSNumber *fileIndex in fileIndexes) {
            NSInteger index = fileIndex.integerValue;
            if (index < 0 || static_cast<std::size_t>(index) >= priorities.size()) { continue; }
            priorities[static_cast<std::size_t>(index)] = static_cast<lt::download_priority_t>(priority);
        }
        [self applyPriorityConfigurationToHandle:handle filePriorities:priorities saveResumeData:YES];
    }];
}

- (void)setAllFilesPriority:(FilePriority)priority {
    [self performOperation:@"setAllFilesPriority" action:^(lt::torrent_handle const &handle) {
        auto torrentInfo = handle.torrent_file();
        if (torrentInfo == nullptr) { return; }

        std::vector<lt::download_priority_t> priorities(
            static_cast<std::size_t>(torrentInfo->files().num_files()),
            static_cast<lt::download_priority_t>(priority)
        );
        [self applyPriorityConfigurationToHandle:handle filePriorities:priorities saveResumeData:YES];
    }];
}

- (void)addTracker:(NSString *)url {
    [self performOperation:@"addTracker" action:^(lt::torrent_handle const &handle) {
        handle.add_tracker(lt::announce_entry(url.UTF8String));
    }];
}

- (void)removeTrackers:(NSArray<NSString *> *)urls {
    [self performOperation:@"removeTrackers" action:^(lt::torrent_handle const &handle) {
        auto trackers = handle.trackers();
        std::vector<lt::announce_entry> newTrackers;

        for (auto tracker: trackers) {
            if ([urls containsObject:[NSString stringWithFormat:@"%s", tracker.url.c_str()]]) { continue; }
            newTrackers.push_back(tracker);
        }

        handle.replace_trackers(newTrackers);
        handle.force_reannounce();
    }];
}

- (void)forceReannounce {
    [self forceReannounce: -1];
}

- (void)forceReannounce:(int)index {
    [self performOperation:@"forceReannounce" action:^(lt::torrent_handle const &handle) {
        handle.force_reannounce(0, index);
    }];
}

- (void)updateSnapshot {
    @synchronized (self) {
        auto torrentHandle = _torrentHandle;
        if (!torrentHandle.is_valid()) { return; }

        try {
            auto status = torrentHandle.status();
            self.snapshot = [self createSnapshotFromStatus:status
                                              torrentHandle:torrentHandle
                                                      owner:self
                                                torrentPath:_torrentPath
                                                    session:_session
                                                storageUUID:_storageUUID
                                   isFirstLastPiecePriority:_isFirstLastPiecePriority];
        } catch (std::exception const &exception) {
            [self reportException:exception operation:@"updateSnapshot"];
        } catch (...) {
            [self reportUnknownExceptionForOperation:@"updateSnapshot"];
        }
    }
}

- (void)performOperation:(NSString *)operation action:(TorrentHandleOperation)action {
    @synchronized (self) {
        auto handle = _torrentHandle;
        if (!handle.is_valid()) {
            [_session reportErrorWithCode:ErrorCodeInvalidTorrentHandle
                                operation:operation
                                  message:@"Handle was invalid before the operation started"];
            return;
        }

        try {
            action(handle);
        } catch (std::exception const &exception) {
            [self reportException:exception operation:operation];
        } catch (...) {
            [self reportUnknownExceptionForOperation:operation];
        }
    }
}

- (void)reportException:(std::exception const &)exception operation:(NSString *)operation {
    ErrorCode code = ErrorCodeLibtorrentOperationFailed;
    auto systemError = dynamic_cast<lt::system_error const *>(&exception);
    if (systemError != nullptr && systemError->code() == lt::errors::invalid_torrent_handle) {
        code = ErrorCodeInvalidTorrentHandle;
    }

    NSString *message = [NSString stringWithUTF8String:exception.what()] ?: @"Unknown C++ exception";
    [_session reportErrorWithCode:code operation:operation message:message];
}

- (void)reportUnknownExceptionForOperation:(NSString *)operation {
    [_session reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                        operation:operation
                          message:@"Unknown C++ exception"];
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
