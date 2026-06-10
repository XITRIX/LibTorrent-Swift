//
//  TorrentHandleSnapshot.h
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import <Foundation/Foundation.h>
#import "TorrentHandleSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

@interface TorrentHandleSnapshot () {
    lt::torrent_status _status;
    lt::torrent_handle _torrentHandle;
    __weak TorrentHandle *_torrentHandleOwner;
    NSString *_torrentPath;
    Session *_session;
    NSUUID *_storageUUID;
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
