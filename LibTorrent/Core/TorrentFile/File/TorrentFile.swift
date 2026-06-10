//
//  TorrentFile.swift
//  TorrentKit
//
//  Created by Даниил Виноградов on 26.04.2022.
//

import Foundation
@_implementationOnly import LibTorrentLegacyObjC

extension TorrentFile {
    convenience init?(with file: URL) {
        self.init(unsafeWithFileAt: file)
        if !isValid { return nil }
    }

    convenience init?(with data: Data) {
        self.init(unsafeWithFileWith: data)
        if !isValid { return nil }
    }
}

@available(iOS 13.0, *)
@available(tvOS 15.0, *)
extension TorrentFile {
    convenience init?(remote url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            self.init(with: data)
        } catch { return nil }
    }
}
