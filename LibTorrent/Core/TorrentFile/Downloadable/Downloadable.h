//
//  Downloadable.h
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import <Foundation/Foundation.h>

#import <LibTorrent/TorrentHandle.h>

NS_ASSUME_NONNULL_BEGIN

@class Session;

NS_SWIFT_SENDABLE
@protocol Downloadable <NSObject>

@property (readonly) TorrentHashes *infoHashes;

- (void)configureAddTorrentParams:(void *)params forSession:(Session *)session;
- (void)configureAfterAdded:(TorrentHandle *)torrentHandle;

@end

NS_ASSUME_NONNULL_END
