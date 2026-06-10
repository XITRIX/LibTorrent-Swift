//
//  TorrentSession+AddPreview.swift
//  LibTorrent
//
//  Created by OpenAI Codex on 10/06/2026.
//

import Foundation
@_implementationOnly import LibTorrentLegacyObjC

public extension TorrentSession {
    final class AddPreview {
        private let torrentFile: TorrentFile

        public var name: String { torrentFile.name }
        public var files: [Handle.Snapshot.FileEntrySnapshot] { torrentFile.files.map(Handle.Snapshot.FileEntrySnapshot.init) }
        public var infoHashes: Hashes { Hashes(torrentFile.infoHashes) }
        public var source: Source { .init(torrentFile) }

        public init?(torrentFileURL url: URL) {
            guard let torrentFile = TorrentFile(with: url) else { return nil }
            self.torrentFile = torrentFile
        }

        public init?(torrentData data: Data) {
            guard let torrentFile = TorrentFile(with: data) else { return nil }
            self.torrentFile = torrentFile
        }

        public func file(at index: Int) -> Handle.Snapshot.FileEntrySnapshot {
            Handle.Snapshot.FileEntrySnapshot(torrentFile.getAt(Int32(index)))
        }

        public func setFilePriority(_ priority: FileEntry.Priority, at index: Int) {
            torrentFile.setFilePriority(priority, at: index)
        }

        public func setFilesPriority(_ priority: FileEntry.Priority, at indexes: [Int]) {
            torrentFile.setFilesPriority(priority, at: indexes.map(NSNumber.init(value:)))
        }

        public func setAllFilesPriority(_ priority: FileEntry.Priority) {
            torrentFile.setAllFilesPriority(priority)
        }
    }
}

@available(iOS 13.0, *)
@available(tvOS 15.0, *)
public extension TorrentSession.AddPreview {
    convenience init?(remote url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            self.init(torrentData: data)
        } catch {
            return nil
        }
    }
}
