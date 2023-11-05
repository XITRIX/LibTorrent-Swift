//
//  TorrentTracker.m
//  TorrentKit
//
//  Created by Даниил Виноградов on 02.05.2022.
//

#import "TorrentTracker_Internal.h"
#import <vector>

@implementation TorrentTracker

- (instancetype)initWithAnnounceEntry:(lt::announce_entry)announceEntry from:(TorrentHandle*)torrentHandle {
    self = [self init];
    if (self) {
        _trackerUrl = [[NSString alloc] initWithFormat:@"%s", announceEntry.url.c_str()];
        _messages = @"MSG";
        _seeders = -1;
        _peers = -1;
        _leechs = -1;
        _working = announceEntry.is_working();
        _verified = announceEntry.verified;

        std::vector<int> protocols;
        if (torrentHandle.infoHashes.hasV1) {
            protocols.push_back(0);
        }
        if (torrentHandle.infoHashes.hasV2) {
            protocols.push_back(1);
        }

        for (const lt::announce_endpoint &endpoint : announceEntry.endpoints) {
            for (auto protocolVersion: protocols) {
                auto info = endpoint.info_hashes.at(protocolVersion);

//                _working |= info.is_working();
                _seeders = info.scrape_complete;
                _peers = info.scrape_incomplete;
                _leechs = info.scrape_downloaded;
                _messages = [[NSString alloc] initWithFormat:@"%s", info.message.c_str()];
            }

        }
    }
    return self;
}

@end
