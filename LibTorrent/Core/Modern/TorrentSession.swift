//
//  TorrentSession.swift
//  LibTorrent
//
//  Created by OpenAI Codex on 10/06/2026.
//

import Foundation
@_implementationOnly import LibTorrentLegacyObjC

public actor TorrentSession {
    public final class Handle: @unchecked Sendable, Hashable {
        public let infoHashes: TorrentSession.Hashes

        private weak var session: TorrentSession?
        private let snapshotLock = NSLock()
        private var cachedSnapshotValue: TorrentSession.Handle.Snapshot?

        fileprivate init(session: TorrentSession, infoHashes: TorrentSession.Hashes) {
            self.session = session
            self.infoHashes = infoHashes
        }

        public static func == (lhs: Handle, rhs: Handle) -> Bool {
            lhs.infoHashes == rhs.infoHashes
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(infoHashes)
        }

        public var currentSnapshot: TorrentSession.Handle.Snapshot? {
            snapshotLock.lock()
            defer { snapshotLock.unlock() }
            return cachedSnapshotValue
        }

        public func updateCachedSnapshot(_ snapshot: TorrentSession.Handle.Snapshot?) {
            snapshotLock.lock()
            cachedSnapshotValue = snapshot
            snapshotLock.unlock()
        }

        public func snapshot() async -> TorrentSession.Handle.Snapshot? {
            guard let session else { return nil }
            let snapshot = await session.torrent(for: infoHashes)
            updateCachedSnapshot(snapshot)
            return snapshot
        }

        public func remove(deleteFiles: Bool) async {
            guard let session else { return }
            await session.removeTorrent(infoHashes, deleteFiles: deleteFiles)
        }

        public func pause() async {
            guard let session else { return }
            await session.pauseTorrent(infoHashes)
        }

        public func resume() async {
            guard let session else { return }
            await session.resumeTorrent(infoHashes)
        }

        public func reload() async {
            guard let session else { return }
            await session.reloadTorrent(infoHashes)
        }

        public func rehash() async {
            guard let session else { return }
            await session.rehashTorrent(infoHashes)
        }

        public func setSequentialDownload(_ enabled: Bool) async {
            guard let session else { return }
            await session.setSequentialDownload(enabled, for: infoHashes)
        }

        public func setFirstLastPriorityDownload(_ enabled: Bool) async {
            guard let session else { return }
            await session.setFirstLastPriorityDownload(enabled, for: infoHashes)
        }

        public func setFilePriority(_ priority: FileEntry.Priority, at fileIndex: Int) async {
            guard let session else { return }
            await session.setFilePriority(priority, at: fileIndex, for: infoHashes)
        }

        public func setFilesPriority(_ priority: FileEntry.Priority, at fileIndexes: [Int]) async {
            guard let session else { return }
            await session.setFilesPriority(priority, at: fileIndexes, for: infoHashes)
        }

        public func setAllFilesPriority(_ priority: FileEntry.Priority) async {
            guard let session else { return }
            await session.setAllFilesPriority(priority, for: infoHashes)
        }

        public func addTracker(_ url: String) async {
            guard let session else { return }
            await session.addTracker(url, for: infoHashes)
        }

        public func removeTrackers(_ urls: [String]) async {
            guard let session else { return }
            await session.removeTrackers(urls, for: infoHashes)
        }

        public func forceReannounce(trackerIndex: Int? = nil) async {
            guard let session else { return }
            await session.forceReannounceTorrent(infoHashes, trackerIndex: trackerIndex)
        }
    }

    private let session: Session
    private let eventsHub: TorrentSessionEventHub
    private let delegateProxy: LegacySessionDelegateProxy
    private var handleCache: [TorrentSession.Hashes: Handle] = [:]

    public init(
        downloadPath: URL,
        torrentsPath: URL,
        fastResumePath: URL,
        settings: TorrentSession.Configuration,
        storages: [UUID: TorrentSession.Storage] = [:]
    ) {
        let session = Session(
            downloadPath,
            torrentsPath: torrentsPath,
            fastResumePath: fastResumePath,
            settings: settings.legacyValue,
            storages: storages.mapValues(\.legacyValue)
        )
        self.init(session: session)
    }

    init(session: Session) {
        let eventsHub = TorrentSessionEventHub()
        self.eventsHub = eventsHub
        self.delegateProxy = LegacySessionDelegateProxy(eventsHub: eventsHub)
        self.session = session
        self.session.add(self.delegateProxy)
    }

    public func events() -> AsyncStream<TorrentSession.Event> {
        eventsHub.stream()
    }

    public func handleEvents() -> AsyncStream<TorrentSession.HandleEvent> {
        let sourceStream = events()

        return AsyncStream { continuation in
            let task = Task {
                for await event in sourceStream {
                    switch event {
                    case let .torrentAdded(snapshot):
                        continuation.yield(.torrentAdded(self.cachedHandle(for: snapshot.infoHashes)))
                    case let .torrentRemoved(hashes):
                        continuation.yield(.torrentRemoved(hashes))
                    case let .torrentUpdated(snapshot):
                        continuation.yield(.torrentUpdated(self.cachedHandle(for: snapshot.infoHashes)))
                    case let .error(error):
                        continuation.yield(.error(error))
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func configuration() -> TorrentSession.Configuration {
        TorrentSession.Configuration(session.settings)
    }

    public func updateSettings(_ configuration: TorrentSession.Configuration) {
        session.settings = configuration.legacyValue
    }

    public func currentTorrents() -> [TorrentSession.Handle.Snapshot] {
        session.torrentsMap.values.map { handle in
            handle.updateSnapshot()
            return TorrentSession.Handle.Snapshot(handle.snapshot)
        }
    }

    public func currentHandles() -> [TorrentSession.Handle] {
        syncHandleCacheWithSession()
        return session.torrentsMap.map { key, torrent in
            torrent.updateSnapshot()
            let hashes = TorrentSession.Hashes(key)
            let handle = cachedHandle(for: hashes)
            handle.updateCachedSnapshot(TorrentSession.Handle.Snapshot(torrent.snapshot))
            return handle
        }
    }

    public func handle(for hashes: TorrentSession.Hashes) -> TorrentSession.Handle? {
        syncHandleCacheWithSession()
        guard let torrent = torrentHandle(for: hashes) else {
            return nil
        }

        torrent.updateSnapshot()
        let handle = cachedHandle(for: hashes)
        handle.updateCachedSnapshot(TorrentSession.Handle.Snapshot(torrent.snapshot))
        return handle
    }

    public func torrent(for hashes: TorrentSession.Hashes) -> TorrentSession.Handle.Snapshot? {
        guard let torrent = torrentHandle(for: hashes) else {
            return nil
        }

        torrent.updateSnapshot()
        let snapshot = TorrentSession.Handle.Snapshot(torrent.snapshot)
        cachedHandle(for: hashes).updateCachedSnapshot(snapshot)
        return snapshot
    }

    @discardableResult
    public func addTorrent(_ source: TorrentSession.Source, to storageID: UUID? = nil) throws -> TorrentSession.Handle.Snapshot {
        guard let handle = session.addTorrent(source.legacyValue, to: storageID) else {
            throw TorrentSession.Error(code: Int(ErrorCode.badFile.rawValue), message: "Failed to add torrent to session")
        }

        handle.updateSnapshot()
        return TorrentSession.Handle.Snapshot(handle.snapshot)
    }

    @discardableResult
    public func addTorrentHandle(_ source: TorrentSession.Source, to storageID: UUID? = nil) throws -> TorrentSession.Handle {
        guard let torrent = session.addTorrent(source.legacyValue, to: storageID) else {
            throw TorrentSession.Error(code: Int(ErrorCode.badFile.rawValue), message: "Failed to add torrent to session")
        }

        torrent.updateSnapshot()
        let hashes = TorrentSession.Hashes(torrent.infoHashes)
        let handle = cachedHandle(for: hashes)
        handle.updateCachedSnapshot(TorrentSession.Handle.Snapshot(torrent.snapshot))
        return handle
    }

    public func removeTorrent(_ hashes: TorrentSession.Hashes, deleteFiles: Bool) {
        guard let handle = torrentHandle(for: hashes) else {
            handleCache[hashes] = nil
            return
        }

        session.removeTorrent(handle, deleteFiles: deleteFiles)
        handleCache[hashes] = nil
    }

    public func pause() {
        session.pause()
    }

    public func resume() {
        session.resume()
    }

    public func reannounceAllTrackers() {
        session.reannounceToAllTrackers()
    }

    public func pauseTorrent(_ hashes: TorrentSession.Hashes) {
        torrentHandle(for: hashes)?.pause()
    }

    public func resumeTorrent(_ hashes: TorrentSession.Hashes) {
        torrentHandle(for: hashes)?.resume()
    }

    public func reloadTorrent(_ hashes: TorrentSession.Hashes) {
        torrentHandle(for: hashes)?.reload()
    }

    public func rehashTorrent(_ hashes: TorrentSession.Hashes) {
        torrentHandle(for: hashes)?.rehash()
    }

    public func setSequentialDownload(_ enabled: Bool, for hashes: TorrentSession.Hashes) {
        torrentHandle(for: hashes)?.setSequentialDownload(enabled)
    }

    public func setFirstLastPriorityDownload(_ enabled: Bool, for hashes: TorrentSession.Hashes) {
        torrentHandle(for: hashes)?.setFirstLastPriorityDownload(enabled)
    }

    public func setFilePriority(_ priority: FileEntry.Priority, at fileIndex: Int, for hashes: TorrentSession.Hashes) {
        torrentHandle(for: hashes)?.setFilePriority(priority, at: fileIndex)
    }

    public func setFilesPriority(_ priority: FileEntry.Priority, at fileIndexes: [Int], for hashes: TorrentSession.Hashes) {
        torrentHandle(for: hashes)?.setFilesPriority(priority, at: fileIndexes.map(NSNumber.init(value:)))
    }

    public func setAllFilesPriority(_ priority: FileEntry.Priority, for hashes: TorrentSession.Hashes) {
        torrentHandle(for: hashes)?.setAllFilesPriority(priority)
    }

    public func addTracker(_ url: String, for hashes: TorrentSession.Hashes) {
        torrentHandle(for: hashes)?.addTracker(url)
    }

    public func removeTrackers(_ urls: [String], for hashes: TorrentSession.Hashes) {
        torrentHandle(for: hashes)?.removeTrackers(urls)
    }

    public func forceReannounceTorrent(_ hashes: TorrentSession.Hashes, trackerIndex: Int? = nil) {
        guard let handle = torrentHandle(for: hashes) else {
            return
        }

        if let trackerIndex {
            handle.forceReannounce(Int32(trackerIndex))
        } else {
            handle.forceReannounce()
        }
    }

    public func setStorages(_ storages: [UUID: TorrentSession.Storage]) {
        session.storages = storages.mapValues(\.legacyValue)
    }

    public func storages() -> [UUID: TorrentSession.Storage] {
        session.storages.mapValues(TorrentSession.Storage.init)
    }

    public func finishEventStreams() {
        session.remove(delegateProxy)
        handleCache.removeAll()
        eventsHub.finish()
    }

    private func cachedHandle(for hashes: TorrentSession.Hashes) -> Handle {
        if let handleCache = handleCache[hashes] {
            return handleCache
        }

        let handle = Handle(session: self, infoHashes: hashes)
        handleCache[hashes] = handle
        return handle
    }

    private func syncHandleCacheWithSession() {
        let activeHashes = Set(session.torrentsMap.keys.map(TorrentSession.Hashes.init))
        handleCache = handleCache.filter { activeHashes.contains($0.key) }
    }

    private func torrentHandle(for hashes: TorrentSession.Hashes) -> TorrentHandle? {
        session.torrentsMap.first { key, _ in
            TorrentSession.Hashes(key) == hashes
        }?.value
    }
}

private final class TorrentSessionEventHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<TorrentSession.Event>.Continuation] = [:]

    func stream() -> AsyncStream<TorrentSession.Event> {
        let identifier = UUID()

        return AsyncStream { continuation in
            lock.lock()
            continuations[identifier] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(for: identifier)
            }
        }
    }

    func yield(_ event: TorrentSession.Event) {
        lock.lock()
        let activeContinuations = Array(continuations.values)
        lock.unlock()

        for continuation in activeContinuations {
            continuation.yield(event)
        }
    }

    func finish() {
        lock.lock()
        let activeContinuations = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()

        for continuation in activeContinuations {
            continuation.finish()
        }
    }

    private func removeContinuation(for identifier: UUID) {
        lock.lock()
        continuations[identifier] = nil
        lock.unlock()
    }
}

private final class LegacySessionDelegateProxy: NSObject, SessionDelegate, @unchecked Sendable {
    private let eventsHub: TorrentSessionEventHub

    init(eventsHub: TorrentSessionEventHub) {
        self.eventsHub = eventsHub
    }

    func torrentManager(_ manager: Session, didAddTorrent torrent: TorrentHandle) {
        torrent.updateSnapshot()
        eventsHub.yield(.torrentAdded(TorrentSession.Handle.Snapshot(torrent.snapshot)))
    }

    func torrentManager(_ manager: Session, didRemoveTorrentWithHash hashesData: TorrentHashes) {
        eventsHub.yield(.torrentRemoved(TorrentSession.Hashes(hashesData)))
    }

    func torrentManager(_ manager: Session, didReceiveUpdateForTorrent torrent: TorrentHandle) {
        torrent.updateSnapshot()
        eventsHub.yield(.torrentUpdated(TorrentSession.Handle.Snapshot(torrent.snapshot)))
    }

    func torrentManager(_ manager: Session, didErrorOccur error: Error) {
        let nsError = error as NSError
        eventsHub.yield(.error(TorrentSession.Error(code: nsError.code, message: nsError.localizedDescription)))
    }
}
