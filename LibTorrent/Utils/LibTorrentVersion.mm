//
//  LibTorrentVersion.m
//  LibTorrent
//
//  Created by Даниил Виноградов on 30.03.2024.
//

#import "LibTorrentVersion.h"
#import "libtorrent/version.hpp"

@implementation Version

+ (NSString *)libtorrentVersion {
    return [[NSString alloc] initWithFormat:@"%s", LIBTORRENT_VERSION];
}

@end
