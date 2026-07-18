//
//  TorrentFile_Internal.h
//  TorrentKit
//
//  Created by Даниил Виноградов on 25.04.2022.
//

#import "TorrentFile.h"
#import "FileEntry_Internal.h"

#import "libtorrent/add_torrent_params.hpp"
#import "libtorrent/torrent_handle.hpp"

NS_ASSUME_NONNULL_BEGIN

@interface TorrentFile ()
@property (readonly, nullable) NSMutableArray<NSNumber *> *priorities;
@property (readonly, nullable) NSArray<FileEntry *> *filesCache;
@property BOOL firstLastPiecePriorityEnabled;
@property (readwrite) lt::add_torrent_params torrentParams;
@end

NS_ASSUME_NONNULL_END
