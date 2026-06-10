//
//  TorrentSession+Configuration.swift
//  LibTorrent
//
//  Created by OpenAI Codex on 10/06/2026.
//

import Foundation
@_implementationOnly import LibTorrentLegacyObjC

public extension TorrentSession {
    struct Configuration: Equatable, Sendable, Codable {
        public var agentName: String
        public var preallocateStorage: Bool
        public var maxActiveTorrents: Int
        public var maxDownloadingTorrents: Int
        public var maxUploadingTorrents: Int
        public var maxDownloadSpeed: UInt
        public var maxUploadSpeed: UInt
        public var isDhtEnabled: Bool
        public var isLsdEnabled: Bool
        public var isUtpEnabled: Bool
        public var isUpnpEnabled: Bool
        public var isNatEnabled: Bool
        public var encryptionPolicy: EncryptionPolicy
        public var validateHttpsTrackers: Bool
        public var port: Int
        public var portBindRetries: Int
        public var outgoingInterfaces: String
        public var listenInterfaces: String
        public var proxyType: ProxyType
        public var proxyHostname: String
        public var proxyHostPort: Int
        public var proxyAuthRequired: Bool
        public var proxyUsername: String
        public var proxyPassword: String
        public var proxyPeerConnections: Bool

        public init(
            agentName: String = "",
            preallocateStorage: Bool = false,
            maxActiveTorrents: Int = 0,
            maxDownloadingTorrents: Int = 0,
            maxUploadingTorrents: Int = 0,
            maxDownloadSpeed: UInt = 0,
            maxUploadSpeed: UInt = 0,
            isDhtEnabled: Bool = true,
            isLsdEnabled: Bool = true,
            isUtpEnabled: Bool = true,
            isUpnpEnabled: Bool = true,
            isNatEnabled: Bool = true,
            encryptionPolicy: EncryptionPolicy = .enabled,
            validateHttpsTrackers: Bool = true,
            port: Int = 0,
            portBindRetries: Int = 0,
            outgoingInterfaces: String = "",
            listenInterfaces: String = "",
            proxyType: ProxyType = .none,
            proxyHostname: String = "",
            proxyHostPort: Int = 0,
            proxyAuthRequired: Bool = false,
            proxyUsername: String = "",
            proxyPassword: String = "",
            proxyPeerConnections: Bool = false
        ) {
            self.agentName = agentName
            self.preallocateStorage = preallocateStorage
            self.maxActiveTorrents = maxActiveTorrents
            self.maxDownloadingTorrents = maxDownloadingTorrents
            self.maxUploadingTorrents = maxUploadingTorrents
            self.maxDownloadSpeed = maxDownloadSpeed
            self.maxUploadSpeed = maxUploadSpeed
            self.isDhtEnabled = isDhtEnabled
            self.isLsdEnabled = isLsdEnabled
            self.isUtpEnabled = isUtpEnabled
            self.isUpnpEnabled = isUpnpEnabled
            self.isNatEnabled = isNatEnabled
            self.encryptionPolicy = encryptionPolicy
            self.validateHttpsTrackers = validateHttpsTrackers
            self.port = port
            self.portBindRetries = portBindRetries
            self.outgoingInterfaces = outgoingInterfaces
            self.listenInterfaces = listenInterfaces
            self.proxyType = proxyType
            self.proxyHostname = proxyHostname
            self.proxyHostPort = proxyHostPort
            self.proxyAuthRequired = proxyAuthRequired
            self.proxyUsername = proxyUsername
            self.proxyPassword = proxyPassword
            self.proxyPeerConnections = proxyPeerConnections
        }

        init(_ settings: Session.Settings) {
            self.init(
                agentName: settings.agentName,
                preallocateStorage: settings.preallocateStorage,
                maxActiveTorrents: settings.maxActiveTorrents,
                maxDownloadingTorrents: settings.maxDownloadingTorrents,
                maxUploadingTorrents: settings.maxUploadingTorrents,
                maxDownloadSpeed: settings.maxDownloadSpeed,
                maxUploadSpeed: settings.maxUploadSpeed,
                isDhtEnabled: settings.isDhtEnabled,
                isLsdEnabled: settings.isLsdEnabled,
                isUtpEnabled: settings.isUtpEnabled,
                isUpnpEnabled: settings.isUpnpEnabled,
                isNatEnabled: settings.isNatEnabled,
                encryptionPolicy: .init(settings.encryptionPolicy),
                validateHttpsTrackers: settings.validateHttpsTrackers,
                port: settings.port,
                portBindRetries: settings.portBindRetries,
                outgoingInterfaces: settings.outgoingInterfaces,
                listenInterfaces: settings.listenInterfaces,
                proxyType: .init(settings.proxyType),
                proxyHostname: settings.proxyHostname,
                proxyHostPort: settings.proxyHostPort,
                proxyAuthRequired: settings.proxyAuthRequired,
                proxyUsername: settings.proxyUsername,
                proxyPassword: settings.proxyPassword,
                proxyPeerConnections: settings.proxyPeerConnections
            )
        }

        var legacyValue: Session.Settings {
            let settings = Session.Settings()
            settings.agentName = agentName
            settings.preallocateStorage = preallocateStorage
            settings.maxActiveTorrents = maxActiveTorrents
            settings.maxDownloadingTorrents = maxDownloadingTorrents
            settings.maxUploadingTorrents = maxUploadingTorrents
            settings.maxDownloadSpeed = maxDownloadSpeed
            settings.maxUploadSpeed = maxUploadSpeed
            settings.isDhtEnabled = isDhtEnabled
            settings.isLsdEnabled = isLsdEnabled
            settings.isUtpEnabled = isUtpEnabled
            settings.isUpnpEnabled = isUpnpEnabled
            settings.isNatEnabled = isNatEnabled
            settings.encryptionPolicy = encryptionPolicy.legacyValue
            settings.validateHttpsTrackers = validateHttpsTrackers
            settings.port = port
            settings.portBindRetries = portBindRetries
            settings.outgoingInterfaces = outgoingInterfaces
            settings.listenInterfaces = listenInterfaces
            settings.proxyType = proxyType.legacyValue
            settings.proxyHostname = proxyHostname
            settings.proxyHostPort = proxyHostPort
            settings.proxyAuthRequired = proxyAuthRequired
            settings.proxyUsername = proxyUsername
            settings.proxyPassword = proxyPassword
            settings.proxyPeerConnections = proxyPeerConnections
            return settings
        }
    }
}

public extension TorrentSession.Configuration {
    enum EncryptionPolicy: UInt, CaseIterable, Sendable, Codable {
        case enabled
        case forced
        case disabled

        init(_ legacyValue: Session.Settings.EncryptionPolicy) {
            switch legacyValue {
            case .enabled:
                self = .enabled
            case .forced:
                self = .forced
            case .disabled:
                self = .disabled
            @unknown default:
                self = .enabled
            }
        }

        var legacyValue: Session.Settings.EncryptionPolicy {
            switch self {
            case .enabled:
                return .enabled
            case .forced:
                return .forced
            case .disabled:
                return .disabled
            }
        }
    }

    enum ProxyType: UInt, CaseIterable, Sendable, Codable {
        case none
        case socks4
        case socks5
        case http
        case i2pProxy

        init(_ legacyValue: Session.Settings.ProxyType) {
            switch legacyValue {
            case .none:
                self = .none
            case .socks4:
                self = .socks4
            case .socks5:
                self = .socks5
            case .http:
                self = .http
            case .i2p_proxy:
                self = .i2pProxy
            @unknown default:
                self = .none
            }
        }

        var legacyValue: Session.Settings.ProxyType {
            switch self {
            case .none:
                return .none
            case .socks4:
                return .socks4
            case .socks5:
                return .socks5
            case .http:
                return .http
            case .i2pProxy:
                return .i2p_proxy
            }
        }
    }
}
