//
//  TorrentFile.m
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import "Session.h"
#import "TorrentFile_Internal.h"
#import "TorrentHandle_Internal.h"

#import "libtorrent/torrent_info.hpp"
#import "libtorrent/torrent_handle.hpp"
#import "libtorrent/read_resume_data.hpp"
#import "libtorrent/add_torrent_params.hpp"
#import "libtorrent/load_torrent.hpp"

#include <fstream>

@interface TorrentFile (Loading)
- (BOOL)loadTorrentData:(NSData *)data;
@end

static void mergeTorrentFileParams(
    lt::add_torrent_params &resume,
    lt::add_torrent_params const &torrentFile)
{
    // Resume data owns mutable session state. The .torrent file remains the
    // authoritative source for immutable metadata and fills optional fields
    // missing from older resume files.
    resume.ti = torrentFile.ti;
    resume.info_hashes = torrentFile.info_hashes;

    if (resume.trackers.empty()) {
        resume.trackers = torrentFile.trackers;
        resume.tracker_tiers = torrentFile.tracker_tiers;
    }
    if (resume.url_seeds.empty()) resume.url_seeds = torrentFile.url_seeds;
    if (resume.dht_nodes.empty()) resume.dht_nodes = torrentFile.dht_nodes;
    if (resume.merkle_trees.empty()) {
        resume.merkle_trees = torrentFile.merkle_trees;
        resume.merkle_tree_mask = torrentFile.merkle_tree_mask;
        resume.verified_leaf_hashes = torrentFile.verified_leaf_hashes;
    }
    if (resume.renamed_files.empty()) resume.renamed_files = torrentFile.renamed_files;
    if (resume.name.empty()) resume.name = torrentFile.name;
    if (resume.comment.empty()) resume.comment = torrentFile.comment;
    if (resume.created_by.empty()) resume.created_by = torrentFile.created_by;
    if (resume.creation_date == 0) resume.creation_date = torrentFile.creation_date;
    if (resume.root_certificate.empty()) resume.root_certificate = torrentFile.root_certificate;
}

@implementation TorrentFile : NSObject

- (instancetype)initUnsafeWithFileAtURL:(NSURL *)fileURL {
    self = [self init];
    if (self) {
        try {
            if (![self loadTorrentData:[NSData dataWithContentsOfURL:fileURL]]) { return nil; }
        }
        catch (...) { return nil; }
    }
    return self;
}

- (instancetype)initUnsafeWithFileWithData:(NSData *)data {
    self = [self init];
    if (self) {
        try {
            if (![self loadTorrentData:data]) { return nil; }
        }
        catch (...) { return nil; }
    }
    return self;
}

- (BOOL)loadTorrentData:(NSData *)data {
    if (data == nil) return NO;

    _fileData = data;
    _firstLastPiecePriorityEnabled = NO;

    auto buffer = lt::span<char const>(
        static_cast<char const *>(data.bytes),
        static_cast<std::ptrdiff_t>(data.length)
    );
    _torrentParams = lt::load_torrent_buffer(buffer);
    if (_torrentParams.ti == nullptr || !_torrentParams.ti->is_valid()) return NO;

    auto const &layout = _torrentParams.ti->layout();
    lt::renamed_files renamedFiles;
    renamedFiles.import_filenames(layout, _torrentParams.renamed_files);
    lt::filenames files(layout, renamedFiles);

    _priorities = [[NSMutableArray alloc] initWithCapacity:files.num_files()];
    NSMutableArray<FileEntry *> *results = [[NSMutableArray alloc] initWithCapacity:files.num_files()];
    for (int i = 0; i < files.num_files(); ++i) {
        [_priorities addObject:@(FilePriorityDefaultPriority)];

        auto index = static_cast<lt::file_index_t>(i);
        auto path = files.file_path(index);

        FileEntry *fileEntry = [[FileEntry alloc] init];
        fileEntry.index = i;
        fileEntry.isPrototype = true;
        fileEntry.priority = FilePriorityDefaultPriority;
        fileEntry.path = [NSString stringWithUTF8String:path.c_str()];
        fileEntry.name = fileEntry.path.lastPathComponent;
        fileEntry.size = files.file_size(index);
        [results addObject:fileEntry];
    }
    _filesCache = [results copy];
    return YES;
}

- (TorrentHashes *)infoHashes {
    return [[TorrentHashes alloc] initWith:_torrentParams.ti->info_hashes()];
}

- (BOOL)isValid {
    return _torrentParams.ti != nullptr && _torrentParams.ti->is_valid();
}

- (void)configureAddTorrentParams:(void *)params forSession:(Session *)session {
    lt::add_torrent_params *_params = (lt::add_torrent_params *)params;
    *_params = _torrentParams;

    // Save torrent file
    NSString *filePath = [session torrentFilePathForInfoHashes:self.infoHashes];

    if (_fileData != NULL && ![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        BOOL success = [_fileData writeToFile:filePath atomically:YES];
        if (!success) { NSLog(@"Can't save .torrent file"); }
    }

    auto nspath = [session fastResumePathForInfoHashes: self.infoHashes];
    std::string path = std::string([nspath UTF8String]);

    std::ifstream ifs(path, std::ios_base::binary);
    if (ifs.good()) {
        ifs.unsetf(std::ios_base::skipws);

        std::vector<char> buf{std::istream_iterator<char>(ifs)
        , std::istream_iterator<char>()};

        lt::load_torrent_limits cfg = {};
        lt::error_code ec;

        lt::bdecode_node rd = lt::bdecode(buf, ec, NULL, cfg.max_decode_depth
            , cfg.max_decode_tokens);

        auto resume = lt::read_resume_data(rd, ec, cfg.max_pieces);

        if (!ec) {
            mergeTorrentFileParams(resume, _torrentParams);
            *_params = resume;
        }

        // Set save_path as empty, so if it will be resolved later, we can check by empty string
        // If not resolved just set it as default iTorrent storage path
        _params->save_path = "";

        const bool hasResumeDictionary = rd.type() == lt::bdecode_node::dict_t;

        // Try to resolve storage path
        if (!ec && hasResumeDictionary) {
            auto storageID = [NSString stringWithUTF8String: std::string(rd.dict_find_string_value("storage_uuid")).c_str()];
            if (storageID.length != 0) {
                // Use save_path as temporary storage uuid holder
                _params->save_path = storageID.UTF8String;
            }
        }

        // Get files priorities from fast resume and apply to TorrentFile storage
        if (_priorities.count == resume.file_priorities.size()) {
            for (int i = 0; i < _priorities.count; i++) {
                _priorities[i] = [NSNumber numberWithInt: static_cast<uint8_t>(resume.file_priorities[i])];
            }
        }

        _firstLastPiecePriorityEnabled = hasResumeDictionary
            && (rd.dict_find_int_value("first_last_piece_priority", 0) != 0);
    }

    _params->storage_mode = session.settings.preallocateStorage ? lt::storage_mode_allocate : lt::storage_mode_sparse;
}

- (void)configureAfterAdded:(TorrentHandle *)torrentHandle {
    torrentHandle.isFirstLastPiecePriority = self.firstLastPiecePriorityEnabled;
    if (_priorities == NULL) return;

    std::vector<lt::download_priority_t> priorities;
    for (int i = 0; i < _priorities.count; i++) {
        priorities.push_back((lt::download_priority_t)_priorities[i].intValue);
    }

    [torrentHandle applyPriorityConfigurationWithFilePriorities:priorities saveResumeData:NO];
}

- (NSString *)name {
    return [NSString stringWithCString:_torrentParams.ti->name().c_str() encoding:NSUTF8StringEncoding];
}

- (NSArray<FileEntry *> *)files {
    return _filesCache;
}

- (FileEntry *)getFileAt:(int)index {
    auto file = self.files[index];
    file.priority = (FilePriority) _priorities[index].intValue;
    return file;
}

- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex {
    _filesCache[fileIndex].priority = priority;
    [_priorities setObject:[NSNumber numberWithInt:priority] atIndexedSubscript:fileIndex];
}

- (void)setFilesPriority:(FilePriority)priority at:(NSArray<NSNumber *> *)fileIndexes {
    std::vector<lt::download_priority_t> array;
    for (int i = 0; i < fileIndexes.count; i++) {
        _filesCache[fileIndexes[i].integerValue].priority = priority;
        [_priorities setObject:[NSNumber numberWithInt:priority] atIndexedSubscript: fileIndexes[i].integerValue];
    }
}

- (void)setAllFilesPriority:(FilePriority)priority {
    for (int i = 0; i < _priorities.count; i++) {
        _filesCache[i].priority = priority;
        [_priorities setObject:[NSNumber numberWithInt:priority] atIndexedSubscript:i];
    }
}

@end
