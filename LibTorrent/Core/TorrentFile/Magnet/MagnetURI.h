//
//  NSObject+TorrentMagnet.h
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import <Foundation/Foundation.h>

#import <LibTorrent/Downloadable.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_SENDABLE
@interface MagnetURI : NSObject <Downloadable>
@property (readonly, strong, nonatomic) NSURL *magnetURI;

- (instancetype)initUnsafeWithMagnetURI:(NSURL *)magnetURI;

@end

NS_ASSUME_NONNULL_END
