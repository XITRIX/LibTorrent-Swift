//
//  ExceptionCatcher.m
//  TorrentKit
//
//  Created by Даниил Виноградов on 02.05.2022.
//

#import "ExceptionCatcher.h"


@implementation ObjCatch

+ (void) tryBlock:(void(^)(void))block {
    try {
        block();
    }
    catch (...) { }
}

@end
