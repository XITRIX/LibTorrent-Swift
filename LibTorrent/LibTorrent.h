//
//  LibTorrent.h
//  LibTorrent
//
//  Created by Daniil Vinogradov on 23/10/2023.
//

#import <Foundation/Foundation.h>

//! Project version number for LibTorrent.
FOUNDATION_EXPORT double LibTorrentVersionNumber;

//! Project version string for LibTorrent.
FOUNDATION_EXPORT const unsigned char LibTorrentVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <LibTorrent/PublicHeader.h>

#import <LibTorrent/Session.h>
#import <LibTorrent/FileEntry.h>
#import <LibTorrent/FilePriority.h>
#import <LibTorrent/TorrentTracker.h>
#import <LibTorrent/TorrentHandle.h>
#import <LibTorrent/TorrentHandleState.h>
#import <LibTorrent/Downloadable.h>
#import <LibTorrent/TorrentFile.h>
#import <LibTorrent/MagnetURI.h>
#import <LibTorrent/NSData+Hex.h>
#import <LibTorrent/ExceptionCatcher.h>


