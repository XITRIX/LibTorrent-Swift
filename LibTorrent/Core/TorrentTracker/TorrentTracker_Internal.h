//
//  TorrentTracker_Internal.h
//  TorrentKit
//
//  Created by Даниил Виноградов on 02.05.2022.
//

#import "TorrentTracker.h"
#import "TorrentHandle_Internal.h"
#import "libtorrent/announce_entry.hpp"

NS_ASSUME_NONNULL_BEGIN

@interface TorrentTrackerEndpoint ()

@property (readwrite) NSString* name;
@property (readwrite) NSInteger btVersion;

@property (readwrite) TorrentTrackerState state;
@property (readwrite, nullable) NSString* message;

@property (readwrite) NSInteger seeds;
@property (readwrite) NSInteger peers;
@property (readwrite) NSInteger leeches;
@property (readwrite) NSInteger downloaded;

@property (readwrite) NSDate* nextAnnounceTime;
@property (readwrite) NSDate* minAnnounceTime;

@end

@interface TorrentTracker ()

//- (instancetype)initWithAnnounceEntry:(lt::announce_entry)announceEntry;
- (instancetype)initWithAnnounceEntry:(lt::announce_entry)announceEntry from:(TorrentHandle*)torrentHandle;

@end

NS_ASSUME_NONNULL_END
