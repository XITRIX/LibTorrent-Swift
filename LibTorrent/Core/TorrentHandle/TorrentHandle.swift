//
//  TorrentHandle.swift
//  TorrentKit
//
//  Created by Даниил Виноградов on 25.04.2022.
//

import Foundation

extension TorrentHandle {}
extension TorrentHandle.State: Equatable {}
extension TorrentHandle.State: CaseIterable {
    public static var allCases: [TorrentHandle.State] = {
        [
            .checkingFiles,
            .downloadingMetadata,
            .downloading,
            .finished,
            .seeding,
            //    Allocating, // deprecated
            .checkingResumeData,
            .paused,

            // Custom state for storage error
            .storageError
        ]
    }()
}
