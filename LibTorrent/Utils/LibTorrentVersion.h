//
//  LibTorrentVersion.h
//  LibTorrent
//
//  Created by Даниил Виноградов on 30.03.2024.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Version : NSObject
@property (class, strong, readonly) NSString *libtorrentVersion;
@end

NS_ASSUME_NONNULL_END
