//
//  TorrentTracker.m
//  TorrentKit
//
//  Created by Даниил Виноградов on 02.05.2022.
//

#import "TorrentTracker_Internal.h"
#import "libtorrent/version.hpp"
#import <vector>

@implementation TorrentTrackerEndpoint
@end

@implementation TorrentTracker

std::string toString(const lt::tcp::endpoint &ltTCPEndpoint) {
    return (std::stringstream() << ltTCPEndpoint).str();
}

NSDate* fromLTTimePoint32(const lt::time_point32 &timePoint)
{
    const auto ltNow = lt::clock_type::now();
    const auto secsSinceNow = lt::duration_cast<lt::seconds>(timePoint - ltNow + lt::milliseconds(500)).count();
    return [[NSDate alloc] initWithTimeIntervalSinceNow:secsSinceNow];
}

- (instancetype)initWithAnnounceEntry:(lt::announce_entry)announceEntry from:(TorrentHandle*)torrentHandle {
    self = [self init];
    if (self) {
        _tire = announceEntry.tier;
        _trackerUrl = [[NSString alloc] initWithFormat:@"%s", announceEntry.url.c_str()];

        std::vector<int> protocols;
        if (torrentHandle.infoHashes.hasV1) {
            protocols.push_back(0);
        }
        if (torrentHandle.infoHashes.hasV2) {
            protocols.push_back(1);
        }

        int numUpdating = 0;
        int numWorking = 0;
        int numNotWorking = 0;
        int numTrackerError = 0;
        int numUnreachable = 0;

        const auto numEndpoints = announceEntry.endpoints.size() * protocols.size();

        auto localEndpoints = [[NSMutableArray alloc] initWithCapacity:announceEntry.endpoints.size()];
        for (const lt::announce_endpoint &endpoint : announceEntry.endpoints) {
            const auto endpointName = toString(endpoint.local_endpoint);

            for (auto protocolVersion: protocols) {
#if LIBTORRENT_VERSION_MAJOR > 1
                auto info = endpoint.info_hashes.at(protocolVersion);
#else
                auto info = endpoint;
#endif
                TorrentTrackerEndpoint *status = [[TorrentTrackerEndpoint alloc] init];
                status.name = [[NSString alloc] initWithUTF8String:endpointName.c_str()];
                status.btVersion = protocolVersion;
//                status.peers = endpointUpdateInfo.value(protocolVersion, status.numPeers);
                status.peers = -1;
                status.seeds = info.scrape_complete;
                status.leeches = info.scrape_incomplete;
                status.downloaded = info.scrape_downloaded;
                status.nextAnnounceTime = fromLTTimePoint32(info.next_announce);
                status.minAnnounceTime = fromLTTimePoint32(info.min_announce);


                if (info.updating) 
                {
                    status.state = TorrentTrackerStateUpdating;
                    ++numUpdating;
                }
                else if (info.fails > 0)
                {
                    if (info.last_error == lt::errors::tracker_failure)
                    {
                        status.state = TorrentTrackerStateTrackerError;
                        ++numTrackerError;
                    }
                    else if (info.last_error == lt::errors::announce_skipped)
                    {
                        status.state = TorrentTrackerStateUnreachable;
                        ++numUnreachable;
                    }
                    else
                    {
                        status.state = TorrentTrackerStateNotWorking;
                        ++numNotWorking;
                    }
                }
                else if (announceEntry.verified)
                {
                    status.state = TorrentTrackerStateWorking;
                    ++numWorking;
                }
                else
                {
                    status.state = TorrentTrackerStateNotContacted;
                }

                if (!info.message.empty())
                {
                    status.message = [[NSString alloc] initWithUTF8String:info.message.c_str()];
                }
                else if (info.last_error)
                {
                    status.message = [[NSString alloc] initWithUTF8String:info.last_error.message().c_str()];
                }
                else
                {
                    status.message = NULL;
                }

                [localEndpoints addObject:status];
            }
        }
        _endpoints = localEndpoints;

        if (numEndpoints > 0)
        {
            if (numUpdating > 0)
            {
                _state = TorrentTrackerStateUpdating;
            }
            else if (numWorking > 0)
            {
                _state = TorrentTrackerStateWorking;
            }
            else if (numTrackerError > 0)
            {
                _state = TorrentTrackerStateTrackerError;
            }
            else if (numUnreachable == numEndpoints)
            {
                _state = TorrentTrackerStateUnreachable;
            }
            else if ((numUnreachable + numNotWorking) == numEndpoints)
            {
                _state = TorrentTrackerStateNotWorking;
            }
        }

        _peers = -1;
        _seeds = -1;
        _leeches = -1;
        _downloaded = -1;
        _nextAnnounceTime = [[NSDate alloc] init];
        _minAnnounceTime = [[NSDate alloc] init];
        _message = NULL;

        for (const TorrentTrackerEndpoint *endpointStatus : _endpoints)
        {
            _peers = std::max(_peers, endpointStatus.peers);
            _seeds = std::max(_seeds, endpointStatus.seeds);
            _leeches = std::max(_leeches, endpointStatus.leeches);
            _downloaded = std::max(_downloaded, endpointStatus.downloaded);

            if (endpointStatus.state == _state)
            {
//                if (!_nextAnnounceTime.isValid() ||)
                if ((_nextAnnounceTime > endpointStatus.nextAnnounceTime))
                {
                    _nextAnnounceTime = endpointStatus.nextAnnounceTime;
                    _minAnnounceTime = endpointStatus.minAnnounceTime;
                    if ((endpointStatus.state != TorrentTrackerStateWorking)
                        || !(endpointStatus.message == NULL || [endpointStatus.message length] == 0))
                    {
                        _message = endpointStatus.message;
                    }
                }

                if (endpointStatus.state == TorrentTrackerStateWorking)
                {
                    if (_message == NULL || [_message length] == 0)
                        _message = endpointStatus.message;
                }
            }
        }
    }
    return self;
}

@end
