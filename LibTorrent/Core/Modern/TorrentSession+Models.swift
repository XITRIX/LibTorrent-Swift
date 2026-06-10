//
//  TorrentSession+Models.swift
//  LibTorrent
//
//  Created by OpenAI Codex on 10/06/2026.
//

import Foundation
@_implementationOnly import LibTorrentLegacyObjC

public extension TorrentSession {
    struct Hashes: Hashable, Sendable {
        public let hasV1: Bool
        public let hasV2: Bool
        public let v1: Data
        public let v2: Data
        public let best: Data

        public init(hasV1: Bool, hasV2: Bool, v1: Data, v2: Data, best: Data) {
            self.hasV1 = hasV1
            self.hasV2 = hasV2
            self.v1 = v1
            self.v2 = v2
            self.best = best
        }

        public init(_ hashes: TorrentHashes) {
            self.init(hasV1: hashes.hasV1, hasV2: hashes.hasV2, v1: hashes.v1, v2: hashes.v2, best: hashes.best)
        }
    }

    struct Storage: Hashable, Sendable, Codable, Identifiable {
        public let uuid: UUID
        public var id: UUID { uuid }
        public var name: String
        public var pathBookmark: Data
        public var url: URL
        public var resolved: Bool
        public var allowed: Bool

        public init(uuid: UUID, name: String, pathBookmark: Data, url: URL, resolved: Bool, allowed: Bool) {
            self.uuid = uuid
            self.name = name
            self.pathBookmark = pathBookmark
            self.url = url
            self.resolved = resolved
            self.allowed = allowed
        }

        init(_ storage: StorageModel) {
            self.init(
                uuid: storage.uuid,
                name: storage.name,
                pathBookmark: storage.pathBookmark,
                url: storage.url,
                resolved: storage.resolved,
                allowed: storage.allowed
            )
        }

        var legacyValue: StorageModel {
            let storage = StorageModel(uuid: uuid, name: name, pathBookmark: pathBookmark)
            storage.url = url
            storage.resolved = resolved
            storage.allowed = allowed
            return storage
        }
    }

    struct Error: Swift.Error, Equatable, Sendable {
        public let code: Int
        public let message: String

        public init(code: Int, message: String) {
            self.code = code
            self.message = message
        }
    }

    enum Event: Sendable {
        case torrentAdded(Handle.Snapshot)
        case torrentRemoved(Hashes)
        case torrentUpdated(Handle.Snapshot)
        case error(Error)
    }

    enum HandleEvent: Sendable {
        case torrentAdded(Handle)
        case torrentRemoved(Hashes)
        case torrentUpdated(Handle)
        case error(Error)
    }

    struct Source: Sendable {
        private enum Backing: Sendable {
            case torrentFile(URL, configuration: AddConfiguration)
            case torrentData(Data, configuration: AddConfiguration)
            case magnet(URL)
        }

        private let backing: Backing
        public let infoHashes: Hashes

        public init?(torrentFileURL url: URL, configuration: AddConfiguration = .init()) {
            guard let torrentFile = TorrentFile(with: url) else { return nil }
            configuration.apply(to: torrentFile)
            self.backing = .torrentFile(url, configuration: configuration)
            self.infoHashes = Hashes(torrentFile.infoHashes)
        }

        public init?(torrentData data: Data, configuration: AddConfiguration = .init()) {
            guard let torrentFile = TorrentFile(with: data) else { return nil }
            configuration.apply(to: torrentFile)
            self.backing = .torrentData(data, configuration: configuration)
            self.infoHashes = Hashes(torrentFile.infoHashes)
        }

        public init?(magnetURL url: URL) {
            guard let magnet = MagnetURI(with: url) else { return nil }
            self.backing = .magnet(url)
            self.infoHashes = Hashes(magnet.infoHashes)
        }

        var legacyValue: any Downloadable {
            switch backing {
            case let .torrentFile(url, configuration):
                let torrentFile = TorrentFile(with: url)!
                configuration.apply(to: torrentFile)
                return torrentFile
            case let .torrentData(data, configuration):
                let torrentFile = TorrentFile(with: data)!
                configuration.apply(to: torrentFile)
                return torrentFile
            case let .magnet(url):
                return MagnetURI(with: url)!
            }
        }
    }
}

public extension TorrentSession.Handle {
    enum State: String, CaseIterable, Codable, Hashable, Sendable {
        case checkingFiles
        case downloadingMetadata
        case downloading
        case finished
        case seeding
        case checkingResumeData
        case paused
        case storageError

        init(_ state: TorrentHandle.State) {
            switch state {
            case .checkingFiles:
                self = .checkingFiles
            case .downloadingMetadata:
                self = .downloadingMetadata
            case .downloading:
                self = .downloading
            case .finished:
                self = .finished
            case .seeding:
                self = .seeding
            case .checkingResumeData:
                self = .checkingResumeData
            case .paused:
                self = .paused
            case .storageError:
                self = .storageError
            @unknown default:
                assertionFailure("Unregistered \(TorrentHandle.State.self) enum value is not allowed: \(state)")
                self = .paused
            }
        }
    }

    struct Snapshot: Hashable, Sendable {
        public let isValid: Bool
        public let infoHashes: TorrentSession.Hashes
        public let name: String
        public let state: State
        public let creator: String?
        public let comment: String?
        public let creationDate: Date?
        public let progress: Double
        public let progressWanted: Double
        public let numberOfPeers: Int
        public let numberOfSeeds: Int
        public let numberOfLeechers: Int
        public let numberOfTotalPeers: Int
        public let numberOfTotalSeeds: Int
        public let numberOfTotalLeechers: Int
        public let downloadRate: UInt64
        public let uploadRate: UInt64
        public let hasMetadata: Bool
        public let total: UInt64
        public let totalDone: UInt64
        public let totalWanted: UInt64
        public let totalWantedDone: UInt64
        public let totalDownload: UInt64
        public let totalUpload: UInt64
        public let isPaused: Bool
        public let isFinished: Bool
        public let isSeed: Bool
        public let isSequential: Bool
        public let isFirstLastPiecePriority: Bool
        public let pieces: [Int]
        public let files: [FileEntrySnapshot]
        public let trackers: [TrackerSnapshot]
        public let magnetLink: String
        public let torrentFilePath: String?
        public let downloadPath: URL?
        public let storageUUID: UUID?
        public let isStorageMissing: Bool

        public init(_ snapshot: TorrentHandle.Snapshot) {
            self.isValid = snapshot.isValid
            self.infoHashes = TorrentSession.Hashes(snapshot.infoHashes)
            self.name = snapshot.name
            self.state = State(snapshot.state)
            self.creator = snapshot.creator
            self.comment = snapshot.comment
            self.creationDate = snapshot.creationDate
            self.progress = snapshot.progress
            self.progressWanted = snapshot.progressWanted
            self.numberOfPeers = Int(snapshot.numberOfPeers)
            self.numberOfSeeds = Int(snapshot.numberOfSeeds)
            self.numberOfLeechers = Int(snapshot.numberOfLeechers)
            self.numberOfTotalPeers = Int(snapshot.numberOfTotalPeers)
            self.numberOfTotalSeeds = Int(snapshot.numberOfTotalSeeds)
            self.numberOfTotalLeechers = Int(snapshot.numberOfTotalLeechers)
            self.downloadRate = snapshot.downloadRate
            self.uploadRate = snapshot.uploadRate
            self.hasMetadata = snapshot.hasMetadata
            self.total = snapshot.total
            self.totalDone = snapshot.totalDone
            self.totalWanted = snapshot.totalWanted
            self.totalWantedDone = snapshot.totalWantedDone
            self.totalDownload = snapshot.totalDownload
            self.totalUpload = snapshot.totalUpload
            self.isPaused = snapshot.isPaused
            self.isFinished = snapshot.isFinished
            self.isSeed = snapshot.isSeed
            self.isSequential = snapshot.isSequential
            self.isFirstLastPiecePriority = snapshot.isFirstLastPiecePriority
            self.pieces = snapshot.pieces?.map(\.intValue) ?? []
            self.files = snapshot.files.map(FileEntrySnapshot.init)
            self.trackers = snapshot.trackers.map(TrackerSnapshot.init)
            self.magnetLink = snapshot.magnetLink
            self.torrentFilePath = snapshot.torrentFilePath
            self.downloadPath = snapshot.downloadPath
            self.storageUUID = snapshot.storageUUID
            self.isStorageMissing = snapshot.isStorageMissing
        }
    }
}

public extension TorrentSession.Handle.Snapshot {
    struct FileEntrySnapshot: Hashable, Sendable {
        public let index: Int
        public let isPrototype: Bool
        public let name: String
        public let path: String
        public let size: UInt64
        public let downloaded: UInt64
        public let priority: FileEntry.Priority
        public let pieces: [Int]

        public init(_ file: FileEntry) {
            self.index = Int(file.index)
            self.isPrototype = file.isPrototype
            self.name = file.name
            self.path = file.path
            self.size = file.size
            self.downloaded = file.downloaded
            self.priority = file.priority
            self.pieces = file.pieces.map(\.intValue)
        }
    }

    struct TrackerEndpointSnapshot: Hashable, Sendable {
        public let name: String
        public let btVersion: Int
        public let state: TorrentTracker.State
        public let message: String?
        public let seeds: Int
        public let peers: Int
        public let leeches: Int
        public let downloaded: Int
        public let nextAnnounceTime: Date
        public let minAnnounceTime: Date

        init(_ endpoint: TorrentTrackerEndpoint) {
            self.name = endpoint.name
            self.btVersion = endpoint.btVersion
            self.state = endpoint.state
            self.message = endpoint.message
            self.seeds = endpoint.seeds
            self.peers = endpoint.peers
            self.leeches = endpoint.leeches
            self.downloaded = endpoint.downloaded
            self.nextAnnounceTime = endpoint.nextAnnounceTime
            self.minAnnounceTime = endpoint.minAnnounceTime
        }
    }

    struct TrackerSnapshot: Hashable, Sendable {
        public let trackerURL: String
        public let tier: Int
        public let state: TorrentTracker.State
        public let message: String?
        public let seeds: Int
        public let peers: Int
        public let leeches: Int
        public let downloaded: Int
        public let nextAnnounceTime: Date
        public let minAnnounceTime: Date
        public let endpoints: [TrackerEndpointSnapshot]

        public init(_ tracker: TorrentTracker) {
            self.trackerURL = tracker.trackerUrl
            self.tier = tracker.tire
            self.state = tracker.state
            self.message = tracker.message
            self.seeds = tracker.seeds
            self.peers = tracker.peers
            self.leeches = tracker.leeches
            self.downloaded = tracker.downloaded
            self.nextAnnounceTime = tracker.nextAnnounceTime
            self.minAnnounceTime = tracker.minAnnounceTime
            self.endpoints = tracker.endpoints.map(TrackerEndpointSnapshot.init)
        }
    }
}
