//
//  TorrentSession+AddConfiguration.swift
//  LibTorrent
//
//  Created by OpenAI Codex on 10/06/2026.
//

import Foundation
@_implementationOnly import LibTorrentLegacyObjC

public extension TorrentSession {
    struct AddConfiguration: Hashable, Sendable {
        public var filePriorities: [FileEntry.Priority]
        public var isFirstLastPiecePriorityEnabled: Bool

        public init(
            filePriorities: [FileEntry.Priority] = [],
            isFirstLastPiecePriorityEnabled: Bool = false
        ) {
            self.filePriorities = filePriorities
            self.isFirstLastPiecePriorityEnabled = isFirstLastPiecePriorityEnabled
        }

        init(_ torrentFile: TorrentFile) {
            self.filePriorities = torrentFile.files.map(\.priority)
            self.isFirstLastPiecePriorityEnabled = torrentFile.firstLastPiecePriorityEnabled
        }

        func apply(to torrentFile: TorrentFile) {
            torrentFile.setValue(isFirstLastPiecePriorityEnabled, forKey: "firstLastPiecePriorityEnabled")

            guard filePriorities.count == torrentFile.files.count else { return }

            for (index, priority) in filePriorities.enumerated() {
                torrentFile.setFilePriority(priority, at: index)
            }
        }
    }
}

extension TorrentSession.Source {
    init(_ torrentFile: TorrentFile) {
        self = .init(torrentData: torrentFile.fileData, configuration: .init(torrentFile))!
    }
}
