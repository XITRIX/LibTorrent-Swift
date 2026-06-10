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
#import "libtorrent/torrent_info.hpp"
#import "libtorrent/torrent_status.hpp"


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
        _torrentHandleOwner = owner;
        _torrentPath = torrentPath;
        _session = session;
        _storageUUID = storageUUID;
        _isValid = torrentHandle.is_valid();
        _isFirstLastPiecePriority = isFirstLastPiecePriority;
    }
    return self;
}

- (BOOL)isValid {
    return _isValid;
}

- (TorrentHashes *)infoHashes {
#if LIBTORRENT_VERSION_MAJOR > 1
    auto ih = _torrentHandle.info_hashes();
#else
    auto ih = _torrentHandle.info_hash();
#endif
    return [[TorrentHashes alloc] initWith:ih];
}

- (NSString *)name {
    return [NSString stringWithCString:_status.name.c_str() encoding:NSUTF8StringEncoding];
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
    if (!_status.has_metadata) { return NULL; }

    auto info = _torrentHandle.torrent_file().get();
    return [NSString stringWithCString:info->creator().c_str() encoding:NSUTF8StringEncoding];
}

- (NSString * _Nullable)comment {
    if (!_status.has_metadata) { return NULL; }

    auto info = _torrentHandle.torrent_file().get();
    return [NSString stringWithCString:info->comment().c_str() encoding:NSUTF8StringEncoding];
}

- (NSDate * _Nullable)creationDate {
    if (!_status.has_metadata) { return NULL; }

    auto info = _torrentHandle.torrent_file().get();
    return [[NSDate alloc] initWithTimeIntervalSince1970:info->creation_date()];
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
    if (!_status.has_metadata) { return 0; }

    auto info = _torrentHandle.torrent_file().get();
    return info->total_size();
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
    if (!_status.has_metadata) { return NULL; }

    auto info = _torrentHandle.torrent_file().get();
    auto array = [[NSMutableArray<NSNumber *> alloc] init];
    for (auto i = static_cast<lt::piece_index_t>(0); i < info->end_piece(); i++) {
        [array addObject:[NSNumber numberWithBool:_status.pieces.get_bit(i)]];
    }
    return array;
}

- (NSArray<FileEntry *> *)files {
    auto th = _torrentHandle;
    NSMutableArray *results = [[NSMutableArray alloc] init];
    auto ti = th.torrent_file();
    if (ti == nullptr) {
//        NSLog(@"No metadata for torrent with name: %s", th.status().name.c_str());
        return [results copy];
    }

    std::vector<int64_t> progresses;
    th.file_progress(progresses);
    auto priorities = th.get_file_priorities();

    auto info = ti.get();
    auto files = info->files();
    const int pieceLength = info->piece_length();

    for (int index = 0; index < files.num_files(); index++) {
        auto i = static_cast<lt::file_index_t>(index);
        auto name = std::string(files.file_name(i));
        auto path = files.file_path(i);
        auto size = files.file_size(i);
        uint8_t priority = static_cast<uint8_t>(priorities[index]);

        FileEntry *fileEntry = [[FileEntry alloc] init];
        fileEntry.index = index;
        fileEntry.name = [NSString stringWithUTF8String:name.c_str()];
        fileEntry.path = [NSString stringWithUTF8String:path.c_str()];
        fileEntry.size = size;
        fileEntry.downloaded = progresses[index];
        fileEntry.priority = (FilePriority)priority;

        const auto fileSize = files.file_size(i);// > 0 ? files.file_size(i) : 0;
        const auto fileOffset = files.file_offset(i);

        const long long beginIdx = (fileOffset / pieceLength);
        const long long endIdx = ((fileOffset + fileSize) / pieceLength);

        fileEntry.begin_idx = beginIdx;
        fileEntry.end_idx = endIdx;
        fileEntry.num_pieces = (int)(endIdx - beginIdx);
        auto array = [[NSMutableArray<NSNumber *> alloc] init];
        for (int j = 0; j < fileEntry.num_pieces; j++) {
            auto index = static_cast<lt::piece_index_t>(j + (int)beginIdx);
            [array addObject:[NSNumber numberWithBool:_status.pieces.get_bit(index)]];
        }
        fileEntry.pieces = array;

        [results addObject:fileEntry];
    }
    return [results copy];
}

- (NSArray<TorrentTracker *> *)trackers {
    TorrentHandle *owner = _torrentHandleOwner;
    if (owner == nil) { return @[]; }

    auto trackers = _torrentHandle.trackers();
    NSMutableArray *results = [[NSMutableArray alloc] init];

    for (auto tracker : trackers) {
        [results addObject:[[TorrentTracker alloc] initWithAnnounceEntry:tracker from:owner]];
    }

    return results;
}

- (NSString *)magnetLink {
    auto uri = lt::make_magnet_uri(_torrentHandle);
    return [NSString stringWithCString:uri.c_str() encoding:NSUTF8StringEncoding];
}

- (NSString * _Nullable)torrentFilePath {
    if (!self.isValid || !self.hasMetadata) { return NULL; }

    auto fileInfo = _torrentHandle.torrent_file().get();
    NSString *fileName = [NSString stringWithFormat:@"%s.torrent", fileInfo->name().c_str()];
    NSString *filePath = [_torrentPath stringByAppendingPathComponent:fileName];

    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        return NULL;
    }

    return filePath;
}

- (NSURL * _Nullable)downloadPath {
    if (!self.isValid || !self.hasMetadata) { return NULL; }

    auto savePath = _status.save_path;
//    auto url = [NSString stringWithFormat:@"file://%s", savePath.c_str()];
//    return [NSURL URLWithString: url].URLByStandardizingPath;
    auto path = [NSString stringWithUTF8String:savePath.c_str()];
    return [NSURL fileURLWithPath:path];
}

- (NSUUID * _Nullable)storageUUID {
    return _storageUUID;
}

- (BOOL)isStorageMissing {
    if (_storageUUID == NULL) { return false; }
    return !_session.storages[_storageUUID].allowed;
}

@end
