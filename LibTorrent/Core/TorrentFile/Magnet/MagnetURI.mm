//
//  NSObject+TorrentMagnet.m
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import "MagnetURI_Internal.h"
#import "TorrentHandle_Internal.h"

@implementation MagnetURI : NSObject

- (instancetype)initUnsafeWithMagnetURI:(NSURL *)magnetURI {
    self = [self init];
    if (self) {
        _magnetURI = magnetURI;

        lt::error_code ec;
        _torrentParams = lt::parse_magnet_uri([_magnetURI.absoluteString UTF8String], ec);
        if (ec.failed()) { return NULL; }
    }
    return self;
}

- (TorrentHashes *)infoHashes {
#if LIBTORRENT_VERSION_MAJOR > 1
    auto ih = _torrentParams.info_hashes;
#else
    auto ih = _torrentParams.info_hash;
#endif
    return [[TorrentHashes alloc] initWith:ih];
}

- (BOOL)isMagnetLinkValid {
    lt::error_code ec;
    lt::string_view uri = lt::string_view([_magnetURI.absoluteString UTF8String]);
    lt::parse_magnet_uri(uri, ec);
    return !ec.failed();
}

- (void)configureAddTorrentParams:(void *)params forSession:(Session *)session {
    lt::add_torrent_params *_params = (lt::add_torrent_params *)params;
    lt::error_code ec;
    lt::string_view uri = lt::string_view([self.magnetURI.absoluteString UTF8String]);
    lt::parse_magnet_uri(uri, (*_params), ec);
    if (ec.failed()) {
        NSLog(@"%s, error_code: %s", __FUNCTION__, ec.message().c_str());
    }
    _params->storage_mode = session.settings.preallocateStorage ? lt::storage_mode_allocate : lt::storage_mode_sparse;
}

- (void)configureAfterAdded:(TorrentHandle *)torrentHandle { }

@end
