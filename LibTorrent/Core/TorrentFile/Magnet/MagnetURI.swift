//
//  MagnetURI.swift
//  TorrentKit
//
//  Created by Даниил Виноградов on 26.04.2022.
//

import Foundation
@_implementationOnly import LibTorrentLegacyObjC

extension MagnetURI {
    convenience init?(with url: URL) {
        self.init(unsafeWithMagnetURI: url)
    }
}
