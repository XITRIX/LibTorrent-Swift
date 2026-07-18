//
//  TorrentHandleSnapshot.h
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import <Foundation/Foundation.h>
#import "TorrentHandleSnapshot.h"
#import "libtorrent/torrent_info.hpp"
#import "libtorrent/add_torrent_params.hpp"

NS_ASSUME_NONNULL_BEGIN

@interface TorrentHandleSnapshot () {
    lt::torrent_status _status;
    lt::torrent_handle _torrentHandle;
    std::shared_ptr<const lt::torrent_info> _torrentInfo;
    std::shared_ptr<const lt::add_torrent_params> _torrentParams;
    __weak TorrentHandle *_torrentHandleOwner;
    NSString *_torrentPath;
    Session *_session;
    NSUUID *_storageUUID;
    TorrentHashes *_infoHashes;
    NSString *_name;
    NSString *_creator;
    NSString *_comment;
    NSDate *_creationDate;
    NSArray<NSNumber *> *_pieces;
    NSArray<FileEntry *> *_files;
    NSArray<TorrentTracker *> *_trackers;
    NSString *_magnetLink;
    NSString *_torrentFilePath;
    NSURL *_downloadPath;
    uint64_t _total;
    BOOL _didLoadCreator;
    BOOL _didLoadComment;
    BOOL _didLoadCreationDate;
    BOOL _didLoadTorrentParams;
    BOOL _didLoadTorrentFilePath;
    BOOL _didLoadDownloadPath;
    BOOL _didLoadTotal;
    BOOL _isValid;
    BOOL _isFirstLastPiecePriority;
}

- (instancetype)initWithStatus:(lt::torrent_status)status
                 torrentHandle:(lt::torrent_handle)torrentHandle
                         owner:(TorrentHandle *)owner
                   torrentPath:(NSString *)torrentPath
                       session:(Session *)session
                    storageUUID:(NSUUID * _Nullable)storageUUID
       isFirstLastPiecePriority:(BOOL)isFirstLastPiecePriority;
@end

NS_ASSUME_NONNULL_END
