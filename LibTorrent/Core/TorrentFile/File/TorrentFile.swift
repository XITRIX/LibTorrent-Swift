//
//  TorrentFile.swift
//  TorrentKit
//
//  Created by Даниил Виноградов on 26.04.2022.
//

import Foundation

public enum RemoteTorrentFileError: Error, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case invalidTorrent
}

public extension TorrentFile {
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
public extension TorrentFile {
    static func download(from url: URL) async throws -> TorrentFile {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let response = response as? HTTPURLResponse else {
            throw RemoteTorrentFileError.invalidResponse
        }
        guard 200 ..< 300 ~= response.statusCode else {
            throw RemoteTorrentFileError.httpStatus(response.statusCode)
        }
        guard let torrentFile = TorrentFile(with: data) else {
            throw RemoteTorrentFileError.invalidTorrent
        }

        return torrentFile
    }
}
