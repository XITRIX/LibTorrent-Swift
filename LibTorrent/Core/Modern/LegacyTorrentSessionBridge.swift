//
//  LegacyTorrentSessionBridge.swift
//  LibTorrent
//
//  Created by OpenAI Codex on 10/06/2026.
//

import Foundation
@_implementationOnly import LibTorrentLegacyObjC

public enum LegacyTorrentSessionEvent {
    case torrentAdded(TorrentHandle)
    case torrentRemoved(TorrentHashes)
    case torrentUpdated(TorrentHandle)
    case error(Error)
}

public final class LegacyTorrentSessionBridge: @unchecked Sendable {
    let session: Session
    private let modernSession: TorrentSession

    private let eventsHub = LegacyTorrentSessionEventHub()
    private let delegateProxy: LegacySessionBridgeDelegateProxy

    public init(
        downloadPath: URL,
        torrentsPath: URL,
        fastResumePath: URL,
        configuration: TorrentSession.Configuration,
        storages: [UUID: TorrentSession.Storage] = [:]
    ) {
        self.delegateProxy = LegacySessionBridgeDelegateProxy(eventsHub: eventsHub)
        let session = Session(
            downloadPath,
            torrentsPath: torrentsPath,
            fastResumePath: fastResumePath,
            settings: configuration.legacyValue,
            storages: storages.mapValues(\.legacyValue)
        )
        self.session = session
        self.modernSession = TorrentSession(session: session)
        self.session.add(delegateProxy)
    }

    deinit {
        session.remove(delegateProxy)
        let modernSession = self.modernSession
        Task {
            await modernSession.finishEventStreams()
        }
        eventsHub.finish()
    }

    public func events() -> AsyncStream<LegacyTorrentSessionEvent> {
        eventsHub.stream()
    }

    public func handleEvents() -> AsyncStream<TorrentSession.HandleEvent> {
        Task { _ = await modernSession.currentHandles() }
        return AsyncStream { continuation in
            let task = Task {
                let stream = await modernSession.handleEvents()
                for await event in stream {
                    continuation.yield(event)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public var configuration: TorrentSession.Configuration {
        get { TorrentSession.Configuration(session.settings) }
        set { session.settings = newValue.legacyValue }
    }

    public var torrentsMap: [TorrentHashes: TorrentHandle] {
        session.torrentsMap
    }

    public var storages: [UUID: TorrentSession.Storage] {
        get { session.storages.mapValues(TorrentSession.Storage.init) }
        set { session.storages = newValue.mapValues(\.legacyValue) }
    }

    public func addTorrent(_ source: TorrentSession.Source, to storage: UUID? = nil) -> TorrentHandle? {
        session.addTorrent(source.legacyValue, to: storage)
    }

    public func removeTorrent(_ torrent: TorrentHandle, deleteFiles: Bool) {
        session.removeTorrent(torrent, deleteFiles: deleteFiles)
    }

    public func removeTorrent(_ hashes: TorrentSession.Hashes, deleteFiles: Bool) async {
        await modernSession.removeTorrent(hashes, deleteFiles: deleteFiles)
    }

    public func reloadTorrent(_ hashes: TorrentSession.Hashes) async {
        await modernSession.reloadTorrent(hashes)
    }

    public func pause() {
        session.pause()
    }

    public func resume() {
        session.resume()
    }

    public func reannounceToAllTrackers() {
        session.reannounceToAllTrackers()
    }

    public func modernHandles() async -> [TorrentSession.Handle] {
        await modernSession.currentHandles()
    }

    public func modernHandle(for hashes: TorrentSession.Hashes) async -> TorrentSession.Handle? {
        await modernSession.handle(for: hashes)
    }
}

private final class LegacyTorrentSessionEventHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<LegacyTorrentSessionEvent>.Continuation] = [:]

    func stream() -> AsyncStream<LegacyTorrentSessionEvent> {
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

    func yield(_ event: LegacyTorrentSessionEvent) {
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

private final class LegacySessionBridgeDelegateProxy: NSObject, SessionDelegate {
    private let eventsHub: LegacyTorrentSessionEventHub

    init(eventsHub: LegacyTorrentSessionEventHub) {
        self.eventsHub = eventsHub
    }

    func torrentManager(_ manager: Session, didAddTorrent torrent: TorrentHandle) {
        eventsHub.yield(.torrentAdded(torrent))
    }

    func torrentManager(_ manager: Session, didRemoveTorrentWithHash hashesData: TorrentHashes) {
        eventsHub.yield(.torrentRemoved(hashesData))
    }

    func torrentManager(_ manager: Session, didReceiveUpdateForTorrent torrent: TorrentHandle) {
        eventsHub.yield(.torrentUpdated(torrent))
    }

    func torrentManager(_ manager: Session, didErrorOccur error: Error) {
        eventsHub.yield(.error(error))
    }
}
