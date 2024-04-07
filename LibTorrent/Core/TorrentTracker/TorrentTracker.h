//
//  TorrentTracker.h
//  TorrentKit
//
//  Created by Даниил Виноградов on 02.05.2022.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, TorrentTrackerState) {
    TorrentTrackerStateNotContacted,
    TorrentTrackerStateWorking,
    TorrentTrackerStateUpdating,
    TorrentTrackerStateNotWorking,
    TorrentTrackerStateTrackerError,
    TorrentTrackerStateUnreachable
} NS_SWIFT_NAME(TorrentTracker.State);

@interface TorrentTrackerEndpoint : NSObject

@property (readonly) NSString* name;
@property (readonly) NSInteger btVersion;

@property (readonly) TorrentTrackerState state;
@property (readonly, nullable) NSString* message;

@property (readonly) NSInteger seeds;
@property (readonly) NSInteger peers;
@property (readonly) NSInteger leeches;
@property (readonly) NSInteger downloaded;

@property (readonly) NSDate* nextAnnounceTime;
@property (readonly) NSDate* minAnnounceTime;

@end


@interface TorrentTracker : NSObject

@property (readonly) NSString *trackerUrl;
@property (readonly) NSInteger tire;

@property (readonly) TorrentTrackerState state;
@property (readonly, nullable) NSString *message;

@property (readonly) NSInteger seeds;
@property (readonly) NSInteger peers;
@property (readonly) NSInteger leeches;
@property (readonly) NSInteger downloaded;

@property (readonly) NSDate* nextAnnounceTime;
@property (readonly) NSDate* minAnnounceTime;

@property (readonly) NSArray<TorrentTrackerEndpoint *> *endpoints;

@end

NS_ASSUME_NONNULL_END
