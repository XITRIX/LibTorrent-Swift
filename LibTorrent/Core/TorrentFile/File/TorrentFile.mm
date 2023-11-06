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
        _priorities = [[NSMutableArray alloc] initWithCapacity:files.num_files()];
        for (int i=0; i<files.num_files(); i++) {
            [_priorities setObject:[NSNumber numberWithInt:FilePriorityDefaultPriority] atIndexedSubscript:i];
        }
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
        catch(std::exception const& ex)
        { return NULL; }
    }
    return self;
}

- (lt::torrent_info)torrent_info {
    uint8_t *buffer = (uint8_t *)[self.fileData bytes];
    size_t size = [self.fileData length];
    return lt::torrent_info((char *)buffer, (int)size);
}

- (TorrentHashes *)infoHashes {
    auto ih = self.torrent_info.info_hashes();
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

    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath] && _fileData != NULL) {
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
    }

    _params->ti = std::make_shared<lt::torrent_info>(ti);
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
    auto info = [self torrent_info];
    auto files = info.files();
    NSMutableArray *results = [[NSMutableArray alloc] init];

    for (int i=0; i<files.num_files(); i++) {
        auto path = files.file_path(i);
        auto size = files.file_size(i);
        [_priorities setObject:[NSNumber numberWithInt:FilePriorityDefaultPriority] atIndexedSubscript:i];

        FileEntry *fileEntry = [[FileEntry alloc] init];
        fileEntry.index = i;
        fileEntry.isPrototype = true;
        fileEntry.priority = FilePriorityDefaultPriority;
        fileEntry.path = [NSString stringWithUTF8String:path.c_str()];
        fileEntry.name = [fileEntry.path lastPathComponent];
        fileEntry.size = size;

        [results addObject:fileEntry];
    }

    return [results copy];
}

- (FileEntry *)getFileAt:(int)index {
    auto info = [self torrent_info];
    auto files = info.files();

    auto path = files.file_path(index);
    auto size = files.file_size(index);

    FileEntry *fileEntry = [[FileEntry alloc] init];
    fileEntry.index = index;
    fileEntry.isPrototype = true;
    fileEntry.priority = (FilePriority) _priorities[index].intValue;
    fileEntry.path = [NSString stringWithUTF8String:path.c_str()];
    fileEntry.name = [fileEntry.path lastPathComponent];
    fileEntry.size = size;
    return fileEntry;
}

- (void)setFilePriority:(FilePriority)priority at:(NSInteger)fileIndex {
    [_priorities setObject:[NSNumber numberWithInt:priority] atIndexedSubscript:fileIndex];
}

- (void)setFilesPriority:(FilePriority)priority at:(NSArray<NSNumber *> *)fileIndexes {
    std::vector<lt::download_priority_t> array;
    for (int i = 0; i < fileIndexes.count; i++) {
        [_priorities setObject:[NSNumber numberWithInt:priority] atIndexedSubscript:i];
    }
}

- (void)setAllFilesPriority:(FilePriority)priority {
    for (int i = 0; i < _priorities.count; i++)
        [_priorities setObject:[NSNumber numberWithInt:priority] atIndexedSubscript:i];
}

@end
