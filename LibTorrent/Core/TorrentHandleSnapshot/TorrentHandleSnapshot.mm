//
//  TorrentHandleSnapshot.mm
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import "TorrentHandleSnapshot.h"
#import "TorrentHandle_Internal.h"
#import "FileEntry_Internal.h"
#import "TorrentTracker_Internal.h"
#import "Session_Internal.h"
#import "TorrentHandleSnapshot_Internal.h"

#import "libtorrent/magnet_uri.hpp"
#import "libtorrent/load_torrent.hpp"
#import "libtorrent/torrent_info.hpp"
#import "libtorrent/torrent_status.hpp"

@interface TorrentHandleSnapshot (TorrentMetadata)
- (lt::add_torrent_params const * _Nullable)torrentParams;
@end

static lt::add_torrent_params magnetParams(lt::torrent_handle const &handle) {
    lt::add_torrent_params params;
    params.info_hashes = handle.info_hashes();
    params.name = handle.status(lt::torrent_handle::query_name).name;

    for (auto const &tracker : handle.trackers()) {
        params.trackers.push_back(tracker.url);
    }
    for (auto const &urlSeed : handle.url_seeds()) {
        params.url_seeds.push_back(urlSeed);
    }
    return params;
}

@implementation TorrentHandleSnapshot

- (instancetype)initWithStatus:(lt::torrent_status)status
                 torrentHandle:(lt::torrent_handle)torrentHandle
                         owner:(TorrentHandle *)owner
                   torrentPath:(NSString *)torrentPath
                       session:(Session *)session
                    storageUUID:(NSUUID * _Nullable)storageUUID
       isFirstLastPiecePriority:(BOOL)isFirstLastPiecePriority {
    self = [super init];
    if (self) {
        _status = status;
        _torrentHandle = torrentHandle;
        _torrentInfo = status.torrent_file.lock();
        _torrentHandleOwner = owner;
        _torrentPath = torrentPath;
        _session = session;
        _storageUUID = storageUUID;
        _isValid = torrentHandle.is_valid();
        _isFirstLastPiecePriority = isFirstLastPiecePriority;
        _infoHashes = [[TorrentHashes alloc] initWith:status.info_hashes];
    }
    return self;
}

- (BOOL)isValid {
    return _isValid;
}

- (TorrentHashes *)infoHashes {
    return _infoHashes;
}

- (NSString *)name {
    if (_name != nil) { return _name; }

    _name = [NSString stringWithCString:_status.name.c_str() encoding:NSUTF8StringEncoding];
    return _name;
}

- (TorrentHandleState)state {
    switch (_status.state) {
        case lt::torrent_status::state_t::checking_files: return TorrentHandleStateCheckingFiles;
        case lt::torrent_status::state_t::downloading_metadata: return TorrentHandleStateDownloadingMetadata;
        case lt::torrent_status::state_t::downloading: return TorrentHandleStateDownloading;
        case lt::torrent_status::state_t::finished: return TorrentHandleStateFinished;
        case lt::torrent_status::state_t::seeding: return TorrentHandleStateSeeding;
//        case lt::torrent_status::state_t::allocating: return TorrentHandleStateAllocating;
        case lt::torrent_status::state_t::checking_resume_data: return TorrentHandleStateCheckingResumeData;
        default: return TorrentHandleStateCheckingFiles; // This is an error and should never be the case
    }
}

- (NSString * _Nullable)creator {
    if (_didLoadCreator) { return _creator; }
    _didLoadCreator = true;

    if (!_status.has_metadata) { return NULL; }

    auto params = self.torrentParams;
    if (params == nullptr) { return NULL; }
    _creator = [NSString stringWithUTF8String:params->created_by.c_str()];
    return _creator;
}

- (NSString * _Nullable)comment {
    if (_didLoadComment) { return _comment; }
    _didLoadComment = true;

    if (!_status.has_metadata) { return NULL; }

    auto params = self.torrentParams;
    if (params == nullptr) { return NULL; }
    _comment = [NSString stringWithUTF8String:params->comment.c_str()];
    return _comment;
}

- (NSDate * _Nullable)creationDate {
    if (_didLoadCreationDate) { return _creationDate; }
    _didLoadCreationDate = true;

    if (!_status.has_metadata) { return NULL; }

    auto params = self.torrentParams;
    if (params == nullptr) { return NULL; }
    _creationDate = [[NSDate alloc] initWithTimeIntervalSince1970:params->creation_date];
    return _creationDate;
}

- (lt::add_torrent_params const * _Nullable)torrentParams {
    if (_didLoadTorrentParams) return _torrentParams.get();
    _didLoadTorrentParams = YES;

    NSString *filePath = self.torrentFilePath;
    if (filePath == nil) return nullptr;

    lt::error_code error;
    auto params = lt::load_torrent_file(filePath.UTF8String, error, lt::load_torrent_limits{});
    if (error || params.ti == nullptr) return nullptr;

    _torrentParams = std::make_shared<lt::add_torrent_params const>(std::move(params));
    return _torrentParams.get();
}

- (NSDate * _Nullable)addedDate {
    if (_status.added_time <= 0) { return NULL; }
    return [[NSDate alloc] initWithTimeIntervalSince1970:_status.added_time];
}

- (double)progress {
    return _status.progress;
}

- (double)progressWanted {
    auto totalWanted = (double)self.totalWanted;
    if (totalWanted == 0) { return 0; }
    return (double)self.totalWantedDone / totalWanted;
}

- (NSUInteger)numberOfPeers {
    return _status.num_peers;
}

- (NSUInteger)numberOfSeeds {
    return _status.num_seeds;
}

- (NSUInteger)numberOfLeechers {
    return self.numberOfPeers - self.numberOfSeeds;
}

- (NSUInteger)numberOfTotalPeers {
    int peers = _status.num_complete + _status.num_incomplete;
    return peers > 0 ? peers : _status.list_peers;
}

- (NSUInteger)numberOfTotalSeeds {
    int complete = _status.num_complete;
    return complete > 0 ? complete : _status.list_seeds;
}

- (NSUInteger)numberOfTotalLeechers {
    int incomplete = _status.num_incomplete;
    return incomplete > 0 ? incomplete : _status.list_peers - _status.list_seeds;
}

- (uint64_t)downloadRate {
    return _status.download_rate;
}

- (uint64_t)uploadRate {
    return _status.upload_rate;
}

- (BOOL)hasMetadata {
    return _status.has_metadata;
}

- (uint64_t)total {
    if (_didLoadTotal) { return _total; }
    _didLoadTotal = true;

    if (!_status.has_metadata) { return 0; }

    auto info = _torrentInfo.get();
    if (info == nullptr) { return 0; }
    _total = info->total_size();
    return _total;
}

- (uint64_t)totalDone {
    return _status.total_done;
}

- (uint64_t)totalWanted {
    return _status.total_wanted;
}

- (uint64_t)totalWantedDone {
    return _status.total_wanted_done;
}

- (uint64_t)totalDownload {
    return _status.total_download;
}

- (uint64_t)totalUpload {
    return _status.total_upload;
}

- (BOOL)isPaused {
    return static_cast<bool>(_status.flags & lt::torrent_flags::paused);
}

- (BOOL)isFinished {
    return _status.total_wanted == _status.total_wanted_done;
}

- (BOOL)isSeed {
    return _status.is_seeding;
}

- (BOOL)isSequential {
    return static_cast<bool>(_status.flags & lt::torrent_flags::sequential_download);
}

- (BOOL)isFirstLastPiecePriority {
    return _isFirstLastPiecePriority;
}

- (NSArray<NSNumber *> * _Nullable)pieces {
    @synchronized (self) {
        if (_pieces != nil) { return _pieces; }
        if (!_status.has_metadata) { return NULL; }

        // The status bitfield is the source of truth for this snapshot. Its size may
        // temporarily differ from torrent_file() while metadata or a handle changes.
        const int pieceCount = _status.pieces.size();
        NSMutableArray<NSNumber *> *array = [[NSMutableArray alloc] initWithCapacity:static_cast<NSUInteger>(pieceCount)];
        for (int index = 0; index < pieceCount; ++index) {
            auto pieceIndex = static_cast<lt::piece_index_t>(index);
            [array addObject:[NSNumber numberWithBool:_status.pieces.get_bit(pieceIndex)]];
        }
        _pieces = [array copy];
        return _pieces;
    }
}

- (NSArray<FileEntry *> *)files {
    @synchronized (self) {
        if (_files != nil) { return _files; }

        try {
            auto th = _torrentHandle;
            auto ti = _torrentInfo;
            if (ti == nullptr) {
                _files = @[];
                return _files;
            }

            auto info = ti.get();
            auto const &layout = info->layout();
            lt::filenames files(layout, _status.renamed_files);
            const int fileCount = files.num_files();
            NSMutableArray<FileEntry *> *results = [[NSMutableArray alloc] initWithCapacity:static_cast<NSUInteger>(fileCount)];

            std::vector<int64_t> progresses;
            th.file_progress(progresses);
            auto priorities = th.get_file_priorities();

            const int pieceLength = info->piece_length();
            const int statusPieceCount = _status.pieces.size();

            for (int index = 0; index < fileCount; ++index) {
                auto fileIndex = static_cast<lt::file_index_t>(index);
                auto name = std::string(_status.renamed_files.file_name(layout, fileIndex));
                auto path = files.file_path(fileIndex);
                auto fileSize = files.file_size(fileIndex);
                auto vectorIndex = static_cast<std::size_t>(index);

                auto priority = lt::default_priority;
                if (vectorIndex < priorities.size()) {
                    priority = priorities[vectorIndex];
                }

                uint64_t downloaded = 0;
                if (vectorIndex < progresses.size() && progresses[vectorIndex] > 0) {
                    downloaded = static_cast<uint64_t>(progresses[vectorIndex]);
                }

                FileEntry *fileEntry = [[FileEntry alloc] init];
                fileEntry.index = index;
                fileEntry.name = [NSString stringWithUTF8String:name.c_str()] ?: @"";
                fileEntry.path = [NSString stringWithUTF8String:path.c_str()] ?: @"";
                fileEntry.size = fileSize > 0 ? static_cast<uint64_t>(fileSize) : 0;
                fileEntry.downloaded = downloaded;
                fileEntry.priority = static_cast<FilePriority>(static_cast<uint8_t>(priority));

                int beginIndex = 0;
                int endIndex = 0;
                if (pieceLength > 0 && fileSize > 0) {
                    auto firstPiece = files.map_file(fileIndex, 0, 0).piece;
                    auto lastPiece = files.map_file(fileIndex, fileSize - 1, 1).piece;
                    int firstPieceIndex = static_cast<int>(firstPiece);
                    int lastPieceIndex = static_cast<int>(lastPiece);
                    if (firstPieceIndex >= 0 && lastPieceIndex >= firstPieceIndex) {
                        beginIndex = firstPieceIndex;
                        endIndex = lastPieceIndex + 1;
                    }
                }

                fileEntry.begin_idx = static_cast<uint64_t>(beginIndex);
                fileEntry.end_idx = static_cast<uint64_t>(endIndex);
                fileEntry.num_pieces = endIndex - beginIndex;

                auto array = [[NSMutableArray<NSNumber *> alloc] initWithCapacity:static_cast<NSUInteger>(fileEntry.num_pieces)];
                for (int pieceIndex = beginIndex; pieceIndex < endIndex; ++pieceIndex) {
                    BOOL hasPiece = NO;
                    if (pieceIndex >= 0 && pieceIndex < statusPieceCount) {
                        hasPiece = _status.pieces.get_bit(static_cast<lt::piece_index_t>(pieceIndex));
                    }
                    [array addObject:[NSNumber numberWithBool:hasPiece]];
                }
                fileEntry.pieces = [array copy];

                [results addObject:fileEntry];
            }
            _files = [results copy];
        } catch (std::exception const &exception) {
            // A handle may become invalid while a snapshot is being materialized.
            _files = @[];
            NSString *message = [NSString stringWithUTF8String:exception.what()] ?: @"Unknown C++ exception";
            [_session reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                                operation:@"snapshot.files"
                                  message:message];
        } catch (...) {
            _files = @[];
            [_session reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                                operation:@"snapshot.files"
                                  message:@"Unknown C++ exception"];
        }
        return _files;
    }
}

- (NSArray<TorrentTracker *> *)trackers {
    if (_trackers != nil) { return _trackers; }

    TorrentHandle *owner = _torrentHandleOwner;
    if (owner == nil) {
        _trackers = @[];
        return _trackers;
    }

    try {
        auto trackers = _torrentHandle.trackers();
        NSMutableArray<TorrentTracker *> *results = [[NSMutableArray alloc] initWithCapacity:trackers.size()];

        for (auto tracker : trackers) {
            [results addObject:[[TorrentTracker alloc] initWithAnnounceEntry:tracker from:owner]];
        }

        _trackers = [results copy];
    } catch (std::exception const &exception) {
        _trackers = @[];
        NSString *message = [NSString stringWithUTF8String:exception.what()] ?: @"Unknown C++ exception";
        [_session reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                            operation:@"snapshot.trackers"
                              message:message];
    } catch (...) {
        _trackers = @[];
        [_session reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                            operation:@"snapshot.trackers"
                              message:@"Unknown C++ exception"];
    }
    return _trackers;
}

- (NSString *)magnetLink {
    if (_magnetLink != nil) { return _magnetLink; }

    try {
        auto uri = lt::make_magnet_uri(magnetParams(_torrentHandle));
        _magnetLink = [NSString stringWithCString:uri.c_str() encoding:NSUTF8StringEncoding] ?: @"";
    } catch (std::exception const &exception) {
        _magnetLink = @"";
        NSString *message = [NSString stringWithUTF8String:exception.what()] ?: @"Unknown C++ exception";
        [_session reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                            operation:@"snapshot.magnetLink"
                              message:message];
    } catch (...) {
        _magnetLink = @"";
        [_session reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                            operation:@"snapshot.magnetLink"
                              message:@"Unknown C++ exception"];
    }
    return _magnetLink;
}

- (NSString * _Nullable)torrentFilePath {
    if (_didLoadTorrentFilePath) { return _torrentFilePath; }
    _didLoadTorrentFilePath = true;

    if (!self.isValid || !self.hasMetadata) { return NULL; }

    NSString *filePath = [_session torrentFilePathForInfoHashes:self.infoHashes];

    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        return NULL;
    }

    _torrentFilePath = filePath;
    return _torrentFilePath;
}

- (NSURL * _Nullable)downloadPath {
    if (_didLoadDownloadPath) { return _downloadPath; }
    _didLoadDownloadPath = true;

    if (!self.isValid || !self.hasMetadata) { return NULL; }

    auto savePath = _status.save_path;
//    auto url = [NSString stringWithFormat:@"file://%s", savePath.c_str()];
//    return [NSURL URLWithString: url].URLByStandardizingPath;
    auto path = [NSString stringWithUTF8String:savePath.c_str()];
    _downloadPath = [NSURL fileURLWithPath:path];
    return _downloadPath;
}

- (NSUUID * _Nullable)storageUUID {
    return _storageUUID;
}

- (BOOL)isStorageMissing {
    if (_storageUUID == NULL) { return false; }
    return !_session.storages[_storageUUID].allowed;
}

@end
