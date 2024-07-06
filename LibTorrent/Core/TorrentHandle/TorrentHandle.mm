//
//  NSObject+TorrentHandle.m
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import "TorrentHandle_Internal.h"
#import "FileEntry_Internal.h"
#import "TorrentTracker_Internal.h"
#import "Session_Internal.h"

#import "NSData+Hex.h"

#import "libtorrent/torrent_status.hpp"
#import "libtorrent/torrent_info.hpp"
#import "libtorrent/magnet_uri.hpp"

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

@implementation TorrentHandleSnapshot
@end

@implementation TorrentHandle : TorrentHandleSnapshot

- (instancetype)initWith:(lt::torrent_handle)torrentHandle inSession:(Session *)session {
    self = [self init];
    if (self) {
        _session = session;
        _torrentHandle = torrentHandle;
        _torrentPath = session.torrentsPath;
        _sessionDownloadPath = session.downloadPath;
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

- (NSString *)name {
    auto ts = _torrentHandle.status();
    return [NSString stringWithCString:ts.name.c_str() encoding: NSUTF8StringEncoding];
}

- (NSString * _Nullable)creator {
    auto ts = _torrentHandle.status();

    if (ts.has_metadata) {
        auto info = _torrentHandle.torrent_file().get();
        return [[NSString alloc] initWithFormat:@"%s", info->creator().c_str()];
    }

    return NULL;
}

- (NSString * _Nullable)comment {
    auto ts = _torrentHandle.status();

    if (ts.has_metadata) {
        auto info = _torrentHandle.torrent_file().get();
        return [[NSString alloc] initWithFormat:@"%s", info->comment().c_str()];
    }

    return NULL;
}

- (NSDate * _Nullable)creationDate {
    auto ts = _torrentHandle.status();

    if (ts.has_metadata) {
        auto info = _torrentHandle.torrent_file().get();
        return [[NSDate alloc] initWithTimeIntervalSince1970:info->creation_date()];
    }

    return NULL;
}

- (TorrentHandleState)state {
    auto status = _torrentHandle.status();
    switch (status.state) {
        case lt::torrent_status::state_t::checking_files: return TorrentHandleStateCheckingFiles;
        case lt::torrent_status::state_t::downloading_metadata: return TorrentHandleStateDownloadingMetadata;
        case lt::torrent_status::state_t::downloading: return TorrentHandleStateDownloading;
        case lt::torrent_status::state_t::finished: return TorrentHandleStateFinished;
        case lt::torrent_status::state_t::seeding: return TorrentHandleStateSeeding;
//        case lt::torrent_status::state_t::allocating: return TorrentHandleStateAllocating;
        case lt::torrent_status::state_t::checking_resume_data: return TorrentHandleStateCheckingResumeData;
    }
}

- (double)progress {
    auto status = _torrentHandle.status();
    return status.progress;
}

- (double)progressWanted {
    return (double) self.totalWantedDone / (double) self.totalWanted;
}

- (NSUInteger)numberOfPeers {
    auto status = _torrentHandle.status();
    return status.num_peers;
}

- (NSUInteger)numberOfSeeds {
    auto status = _torrentHandle.status();
    return status.num_seeds;
}

- (NSUInteger)numberOfLeechers {
    return self.numberOfPeers - self.numberOfPeers;
}

- (NSUInteger)numberOfTotalPeers {
    auto status = _torrentHandle.status();
    int peers = status.num_complete + status.num_incomplete;
    return peers > 0 ? peers : status.list_peers;
}

- (NSUInteger)numberOfTotalSeeds {
    auto status = _torrentHandle.status();
    int complete = status.num_complete;
    return complete > 0 ? complete : status.list_seeds;
}

- (NSUInteger)numberOfTotalLeechers {
    auto status = _torrentHandle.status();
    int incomplete = status.num_incomplete;
    return incomplete > 0 ? incomplete : status.list_peers - status.list_seeds;
}

- (uint64_t)downloadRate {
    auto status = _torrentHandle.status();
    return status.download_rate;
}

- (uint64_t)uploadRate {
    auto status = _torrentHandle.status();
    return status.upload_rate;
}

- (BOOL)hasMetadata {
    auto status = _torrentHandle.status();
    return status.has_metadata;
}

- (uint64_t)total {
    auto ts = _torrentHandle.status();

    if (ts.has_metadata) {
        auto info = _torrentHandle.torrent_file().get();
        return info->total_size();
    }

    return NULL;
}

- (uint64_t)totalDone {
    auto ts = _torrentHandle.status();
    return ts.total_done;
}

- (uint64_t)totalWanted {
    auto ts = _torrentHandle.status();
    return ts.total_wanted;
}

- (uint64_t)totalWantedDone {
    auto ts = _torrentHandle.status();
    return ts.total_wanted_done;
}

- (uint64_t)totalDownload {
    auto ts = _torrentHandle.status();
    return ts.total_download;
}

- (uint64_t)totalUpload {
    auto ts = _torrentHandle.status();
    return ts.total_upload;
}

- (BOOL)isPaused {
    auto ts = _torrentHandle.status();
    return ts.flags & lt::torrent_flags::paused;
}

- (BOOL)isFinished {
    auto ts = _torrentHandle.status();
    return ts.total_wanted == ts.total_wanted_done;
}

- (BOOL)isSeed {
    auto ts = _torrentHandle.status();
    return ts.is_seeding;
}

- (BOOL)isSequential {
    auto ts = _torrentHandle.status();
    return ts.flags & lt::torrent_flags::sequential_download;
}

- (NSArray<NSNumber *> *)pieces {
    auto stat = _torrentHandle.status();
    auto info = _torrentHandle.torrent_file().get();

    if (!self.hasMetadata)
        return NULL;

    auto array = [[NSMutableArray<NSNumber *> alloc] init];
    for (int i = 0; i < info->end_piece(); i++) {
        [array addObject: [NSNumber numberWithBool: stat.pieces.get_bit(i)]];
    }
    return array;
}

- (NSString *)magnetLink {
    auto uri = lt::make_magnet_uri(_torrentHandle);
    return [[NSString alloc] initWithFormat:@"%s", uri.c_str()];
}

- (NSString *)torrentFilePath {
    if (!self.isValid || !self.hasMetadata) return NULL;

    auto fileInfo = _torrentHandle.torrent_file().get();
    NSString *fileName = [NSString stringWithFormat:@"%s.torrent", fileInfo->name().c_str()];
    NSString *filePath = [_torrentPath stringByAppendingPathComponent:fileName];

    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath])
        return NULL;

    return filePath;
}

- (NSURL *)downloadPath {
    if (!self.isValid || !self.hasMetadata) return NULL;
    
    auto savePath = _torrentHandle.status().save_path;
//    auto url = [NSString stringWithFormat:@"file://%s", savePath.c_str()];
//    return [NSURL URLWithString: url].URLByStandardizingPath;
    auto path = [NSString stringWithUTF8String: savePath.c_str()];
    return [NSURL fileURLWithPath: path];
}

- (BOOL)isStorageMissing {
    if (self.storageUUID == NULL) return false;
    return !_session.storages[self.storageUUID].allowed;
}

//- (StorageModel*) storage {
//    if (self.downloadPath.path == _session.downloadPath) { return NULL; }
//
//    for (StorageModel* storage in _session.storages.allValues) {
//
//    }
//    
//    return NULL;
////        TorrentService.shared.storages.first(where: { $0.value.url.normalized == downloadPath.normalized })?.value
//}

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
    auto torrentFile = [[TorrentFile alloc] initUnsafeWithFileAtURL: [[NSURL alloc] initFileURLWithPath: self.torrentFilePath]]; //torrentFilePath
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
}

- (NSUInteger) filesCount {
    return _torrentHandle.torrent_file()->files().num_files();
}

- (FileEntry *)getFileAt:(int)index {
    auto stat = _torrentHandle.status();
    auto info = _torrentHandle.torrent_file();
    auto files = info->files();
    auto priorities = _torrentHandle.get_file_priorities();
    const int pieceLength = info->piece_length();

    std::vector<int64_t> progresses;
    _torrentHandle.file_progress(progresses);

    auto name = std::string(files.file_name(index));
    auto path = files.file_path(index);
    auto size = files.file_size(index);
    uint8_t priority = priorities[index];

    FileEntry *fileEntry = [[FileEntry alloc] init];
    fileEntry.index = index;
    fileEntry.name = [NSString stringWithUTF8String:name.c_str()];
    fileEntry.path = [NSString stringWithUTF8String:path.c_str()];
    fileEntry.size = size;
    fileEntry.downloaded = progresses[index];
    fileEntry.priority = (FilePriority) priority;

    const auto fileSize = files.file_size(index);// > 0 ? files.file_size(i) : 0;
    const auto fileOffset = files.file_offset(index);

    const long long beginIdx = (fileOffset / pieceLength);
    const long long endIdx = ((fileOffset + fileSize) / pieceLength);

    fileEntry.begin_idx = beginIdx;
    fileEntry.end_idx = endIdx;
    fileEntry.num_pieces = (int)(endIdx - beginIdx);
    auto array = [[NSMutableArray<NSNumber *> alloc] init];
    for (int j = 0; j < fileEntry.num_pieces; j++) {
        [array addObject: [NSNumber numberWithBool: stat.pieces.get_bit(j + (int)beginIdx)]];
    }
    fileEntry.pieces = array;
    return fileEntry;
}

- (NSArray<FileEntry *> *)files {
    auto th = _torrentHandle;
    NSMutableArray *results = [[NSMutableArray alloc] init];
    auto ti = th.torrent_file();
    if (ti == nullptr) {
        NSLog(@"No metadata for torrent with name: %s", th.status().name.c_str());
        return [results copy];
    }

    std::vector<int64_t> progresses;
    th.file_progress(progresses);
    auto priorities = th.get_file_priorities();

    auto info = ti.get();
    auto stat = th.status();
    auto files = info->files();
    const int pieceLength = info->piece_length();
    
    for (int i=0; i<files.num_files(); i++) {
        auto name = std::string(files.file_name(i));
        auto path = files.file_path(i);
        auto size = files.file_size(i);
        uint8_t priority = priorities[i];

        FileEntry *fileEntry = [[FileEntry alloc] init];
        fileEntry.index = i;
        fileEntry.name = [NSString stringWithUTF8String:name.c_str()];
        fileEntry.path = [NSString stringWithUTF8String:path.c_str()];
        fileEntry.size = size;
        fileEntry.downloaded = progresses[i];
        fileEntry.priority = (FilePriority) priority;

        const auto fileSize = files.file_size(i);// > 0 ? files.file_size(i) : 0;
        const auto fileOffset = files.file_offset(i);

        const long long beginIdx = (fileOffset / pieceLength);
        const long long endIdx = ((fileOffset + fileSize) / pieceLength);

        fileEntry.begin_idx = beginIdx;
        fileEntry.end_idx = endIdx;
        fileEntry.num_pieces = (int)(endIdx - beginIdx);
        auto array = [[NSMutableArray<NSNumber *> alloc] init];
        for (int j = 0; j < fileEntry.num_pieces; j++) {
            [array addObject: [NSNumber numberWithBool: stat.pieces.get_bit(j + (int)beginIdx)]];
        }
        fileEntry.pieces = array;

        [results addObject:fileEntry];
    }
    return [results copy];
}

- (NSArray<TorrentTracker *> *)trackers {
    auto trackers = _torrentHandle.trackers();
    NSMutableArray *results = [[NSMutableArray alloc] init];

    for (auto tracker : trackers) {
        [results addObject: [[TorrentTracker alloc] initWithAnnounceEntry: tracker from: self]];
    }

    return results;
}

- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex {
    _torrentHandle.file_priority((int)fileIndex, priority);
    _torrentHandle.save_resume_data();
}

- (void)setFilesPriority:(FilePriority)priority at:(NSArray<NSNumber *> *)fileIndexes {
    auto priorities = _torrentHandle.get_file_priorities();
    for (int i = 0; i < fileIndexes.count; i++) {
        int index = (int)fileIndexes[i].integerValue;
        priorities[index] = priority;
    }
    _torrentHandle.prioritize_files(priorities);
    _torrentHandle.save_resume_data();
}

- (void)setAllFilesPriority:(FilePriority)priority {
    std::vector<lt::download_priority_t> array;
    for (int i = 0; i < _torrentHandle.torrent_file().get()->files().num_files(); i++) {
        array.push_back(priority);
    }
    _torrentHandle.prioritize_files(array);
    _torrentHandle.save_resume_data();
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

- (void)updateSnapshot {
    if (!self.isValid) return;

    auto snapshot = [[TorrentHandleSnapshot alloc] init];
    try {
        snapshot.isValid = self.isValid;
        snapshot.infoHashes = self.infoHashes;
        snapshot.name = self.name;
        snapshot.state = self.state;
        snapshot.creator = self.creator;
        snapshot.comment = self.comment;
        snapshot.creationDate = self.creationDate;
        snapshot.progress = self.progress;
        snapshot.progressWanted = self.progressWanted;
        snapshot.numberOfPeers = self.numberOfPeers;
        snapshot.numberOfSeeds = self.numberOfSeeds;
        snapshot.numberOfLeechers = self.numberOfLeechers;
        snapshot.numberOfTotalPeers = self.numberOfTotalPeers;
        snapshot.numberOfTotalSeeds = self.numberOfTotalSeeds;
        snapshot.numberOfTotalLeechers = self.numberOfTotalLeechers;
        snapshot.downloadRate = self.downloadRate;
        snapshot.uploadRate = self.uploadRate;
        snapshot.hasMetadata = self.hasMetadata;
        snapshot.total = self.total;
        snapshot.totalDone = self.totalDone;
        snapshot.totalWanted = self.totalWanted;
        snapshot.totalWantedDone = self.totalWantedDone;
        snapshot.totalDownload = self.totalDownload;
        snapshot.totalUpload = self.totalUpload;
        snapshot.isPaused = self.isPaused;
        snapshot.isFinished = self.isFinished;
        snapshot.isSeed = self.isSeed;
        snapshot.isSequential = self.isSequential;
        snapshot.pieces = self.pieces;
        snapshot.files = self.files;
        snapshot.trackers = self.trackers;
        snapshot.magnetLink = self.magnetLink;
        snapshot.torrentFilePath = self.torrentFilePath;
        snapshot.downloadPath = self.downloadPath;
        snapshot.storageUUID = self.storageUUID;
        snapshot.isStorageMissing = self.isStorageMissing;

        self.snapshot = snapshot;
    } catch(...) {}
}

@end
