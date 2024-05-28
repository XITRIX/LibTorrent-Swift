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

#include <fstream>

@implementation TorrentFile : NSObject

- (instancetype)initUnsafeWithFileAtURL:(NSURL *)fileURL {
    self = [self init];
    if (self) {
        _fileData = [NSData dataWithContentsOfURL:fileURL];
        try {
            if (!self.torrent_info.is_valid()) { return NULL; }
        }
        catch(std::exception const& ex)
        { return NULL; }

        auto info = [self torrent_info];
        auto files = info.files();

        // Generate priorities array (should be replaced with filesCache and removed)
        _priorities = [[NSMutableArray alloc] initWithCapacity:files.num_files()];
        for (int i=0; i<files.num_files(); i++) {
            [_priorities setObject:[NSNumber numberWithInt:FilePriorityDefaultPriority] atIndexedSubscript:i];
        }

        // Generate files cache
        NSMutableArray *results = [[NSMutableArray alloc] init];

        for (int i=0; i<files.num_files(); i++) {
            auto path = files.file_path(i);
            auto size = files.file_size(i);

            FileEntry *fileEntry = [[FileEntry alloc] init];
            fileEntry.index = i;
            fileEntry.isPrototype = true;
            fileEntry.priority = (FilePriority) _priorities[i].intValue;
            fileEntry.path = [NSString stringWithUTF8String:path.c_str()];
            fileEntry.name = [fileEntry.path lastPathComponent];
            fileEntry.size = size;

            [results addObject:fileEntry];
        }

        _filesCache = [results copy];
    }
    return self;
}

- (instancetype)initUnsafeWithFileWithData:(NSData *)data {
    self = [self init];
    if (self) {
        _fileData = data;
        try {
            if (!self.torrent_info.is_valid()) { return NULL; }
        }
        catch(...)
        { return NULL; }

        auto info = [self torrent_info];
        auto files = info.files();

        // Generate priorities array (should be replaced with filesCache and removed)
        _priorities = [[NSMutableArray alloc] initWithCapacity:files.num_files()];
        for (int i=0; i<files.num_files(); i++) {
            [_priorities setObject:[NSNumber numberWithInt:FilePriorityDefaultPriority] atIndexedSubscript:i];
        }

        // Generate files cache
        NSMutableArray *results = [[NSMutableArray alloc] init];

        for (int i=0; i<files.num_files(); i++) {
            auto path = files.file_path(i);
            auto size = files.file_size(i);

            FileEntry *fileEntry = [[FileEntry alloc] init];
            fileEntry.index = i;
            fileEntry.isPrototype = true;
            fileEntry.priority = (FilePriority) _priorities[i].intValue;
            fileEntry.path = [NSString stringWithUTF8String:path.c_str()];
            fileEntry.name = [fileEntry.path lastPathComponent];
            fileEntry.size = size;

            [results addObject:fileEntry];
        }

        _filesCache = [results copy];
    }
    return self;
}

- (lt::torrent_info)torrent_info {
    uint8_t *buffer = (uint8_t *)[self.fileData bytes];
    size_t size = [self.fileData length];
    return lt::torrent_info((char *)buffer, (int)size);
}

- (TorrentHashes *)infoHashes {
#if LIBTORRENT_VERSION_MAJOR > 1
    auto ih = self.torrent_info.info_hashes();
#else
    auto ih = self.torrent_info.info_hash();
#endif
    return [[TorrentHashes alloc] initWith:ih];
}

- (BOOL)isValid {
    return self.torrent_info.is_valid();
}

- (void)configureAddTorrentParams:(void *)params forSession:(Session *)session {
    lt::add_torrent_params *_params = (lt::add_torrent_params *)params;
    lt::torrent_info ti = [self torrent_info];

    // Save torrent file
    NSString *fileName = [NSString stringWithFormat:@"%s.torrent", ti.name().c_str()];
    NSString *filePath = [session.torrentsPath stringByAppendingPathComponent:fileName];

    if (_fileData != NULL) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            // Remove existing torrent file with same name
            // Probably should store torrent files by HASH value
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:NULL];
        }
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

        lt::error_code ec;
        auto resume = lt::read_resume_data(buf, ec);
        if (ec.value() == 0) {
            *_params = resume;
        }

        // Get files priorities from fast resume and apply to TorrentFile storage
        if (_priorities.count == resume.file_priorities.size()) {
            for (int i = 0; i < _priorities.count; i++) {
                _priorities[i] = [NSNumber numberWithInt: resume.file_priorities[i]];
            }
        }
    }

    _params->ti = std::make_shared<lt::torrent_info>(ti);
    _params->storage_mode = session.settings.preallocateStorage ? lt::storage_mode_allocate : lt::storage_mode_sparse;
}

- (void)configureAfterAdded:(TorrentHandle *)torrentHandle {
    if (_priorities == NULL) return;

    std::vector<lt::download_priority_t> priorities;
    for (int i = 0; i < _priorities.count; i++) {
        priorities.push_back((lt::download_priority_t)_priorities[i].intValue);
    }

    torrentHandle.torrentHandle.prioritize_files(priorities);
}

- (NSString *)name {
    return [[NSString alloc] initWithFormat:@"%s", self.torrent_info.name().c_str()];
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
