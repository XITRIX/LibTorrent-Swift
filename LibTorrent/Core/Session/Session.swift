//
//  Session.swift
//  LibTorrent
//
//  Created by Daniil Vinogradov on 03/07/2024.
//

import Foundation

extension StorageModel: Codable {
    public convenience init(uuid: UUID, name: String, pathBookmark: Data) {
        self.init()
        self.uuid = uuid
        self.name = name
        self.pathBookmark = pathBookmark
    }

    public required convenience init(from decoder: any Decoder) throws {
        self.init()

        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        pathBookmark = try container.decode(Data.self, forKey: .pathBookmark)
        uuid = try container.decode(UUID.self, forKey: .uuid)
        url = try container.decode(URL.self, forKey: .url)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(pathBookmark, forKey: .pathBookmark)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(url, forKey: .url)
    }

    private enum CodingKeys: CodingKey {
        case name
        case pathBookmark
        case uuid
        case url
    }
}

extension StorageModel: Identifiable {
    public var id: UUID { uuid }
}
