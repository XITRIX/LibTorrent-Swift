//
//  TorrentSession.m
//  TorrentKit
//
//  Created by Даниил Виноградов on 24.04.2022.
//

#import <Foundation/Foundation.h>
#import "LibTorrent/LibTorrent-Swift.h"

#import "Session_Internal.h"
#import "Downloadable.h"
#import "TorrentFile_Internal.h"
#import "TorrentHandle_Internal.h"
#import "NSData+Hex.h"

//libtorrent
#import "libtorrent/session.hpp"
#import "libtorrent/session_params.hpp"
#import "libtorrent/pread_disk_io.hpp"
#import "libtorrent/alert.hpp"
#import "libtorrent/alert_types.hpp"

#import "libtorrent/write_resume_data.hpp"
#import "libtorrent/torrent_handle.hpp"
#import "libtorrent/torrent_info.hpp"
#import "libtorrent/magnet_uri.hpp"

#import "libtorrent/bencode.hpp"
#import "libtorrent/bdecode.hpp"

static NSErrorDomain ErrorDomain = @"ru.xitrix.TorrentKit.Session.error";
static NSString *EventsQueueIdentifier = @"ru.xitrix.TorrentKit.Session.events.queue";
static NSString *FileEntriesQueueIdentifier = @"ru.xitrix.TorrentKit.Session.files.queue";

@interface Session (TorrentPersistence)
- (void)requestTorrentFileSave:(lt::torrent_handle const&)handle;
- (void)removeStoredTorrentOrMagnet:(lt::torrent_handle)handle infoHashes:(TorrentHashes *)infoHashes;
- (BOOL)hasValidTorrentFileForInfoHashes:(TorrentHashes *)infoHashes;
- (BOOL)saveTorrentFileWithParams:(lt::add_torrent_params const&)params;
- (NSArray<NSString *> *)storedMagnetURIs;
- (void)writeStoredMagnetURIs:(NSArray<NSString *> *)magnetURIs;
- (TorrentHashes * _Nullable)infoHashesForMagnetURI:(NSString *)magnetURI;
- (void)removeMagnetURIWithInfoHashes:(TorrentHashes *)infoHashes;
- (void)restoreMagnetURIs;
@end

@interface Session (TorrentErrorRecovery)
- (void)torrentMadeProgress:(lt::torrent_alert *)alert;
- (void)handleTorrentError:(lt::torrent_error_alert *)alert;
@end

static lt::add_torrent_params magnetParams(lt::torrent_handle const &handle) {
    lt::add_torrent_params params;
    params.info_hashes = handle.info_hashes();
    params.name = handle.status(lt::torrent_handle::query_name).name;

    for (auto const &tracker : handle.trackers()) {
        params.trackers.push_back(tracker.url);
    }
    for (auto const &urlSeed : handle.url_seeds()) {
        params.url_seeds.push_back(urlSeed);
    }
    return params;
}

@implementation StorageModel : NSObject
@end

@implementation Session : NSObject

std::unordered_map<lt::sha1_hash, std::unordered_map<std::string, std::unordered_map<lt::tcp::endpoint, std::unordered_map<int, int>>>> updatedTrackerStatuses;

// MARK: - Init
- (instancetype)initWith:(NSURL *)downloadPath torrentsPath:(NSURL *)torrentsPath fastResumePath:(NSURL *)fastResumePath settings:(SessionSettings *)settings storages:(NSDictionary<NSUUID*, StorageModel*>*)storages {
    self = [super init];
    if (self) {
        _downloadPath = downloadPath.path;
        _torrentsPath = torrentsPath.path;
        _fastResumePath = fastResumePath.path;
        _settings = settings;
        _storages = storages;

        NSError * error;
        [[NSFileManager defaultManager] createDirectoryAtURL:downloadPath withIntermediateDirectories:YES attributes:nil error:&error];
        [[NSFileManager defaultManager] createDirectoryAtURL:torrentsPath withIntermediateDirectories:YES attributes:nil error:&error];
        [[NSFileManager defaultManager] createDirectoryAtURL:fastResumePath withIntermediateDirectories:YES attributes:nil error:&error];

        auto params = lt::session_params(_settings.settingsPack);
        params.disk_io_constructor = &lt::pread_disk_io_constructor;
        _session = new lt::session(std::move(params));

        // Init session properties
        _filesQueue = dispatch_queue_create([FileEntriesQueueIdentifier UTF8String], DISPATCH_QUEUE_SERIAL);
        _torrentsMap = [[NSMutableDictionary alloc] init];
        _automaticErrorRecoveryAttempts = [[NSMutableSet alloc] init];
        _delegates = [NSHashTable weakObjectsHashTable];

        // restore session
        [self restoreSession];

        // start alerts loop
        _eventsThread = [[NSThread alloc] initWithTarget:self selector:@selector(alertsLoop) object:nil];
        [_eventsThread setName: EventsQueueIdentifier];
        [_eventsThread setQualityOfService:NSQualityOfServiceDefault];
        [_eventsThread start];

    }
    return self;
}

- (void)setSettings:(SessionSettings *)settings {
    _settings = settings;
    _session->pause(); // Pause to break current connections in case networking settings will be changed
    _session->apply_settings(settings.settingsPack);
    _session->resume();
}

- (void)pause {
    _session->pause();
}

- (void)resume {
    _session->resume();
}

- (void)reannounceToAllTrackers {
    for (TorrentHandle* torrent in _torrentsMap.allValues) {
        @synchronized (torrent) {
            auto handle = torrent.torrentHandle;
            if (!handle.is_valid()) { continue; }

            try {
                handle.force_reannounce(0, -1, lt::torrent_handle::ignore_min_interval);
            } catch (std::exception const &exception) {
                NSString *message = [NSString stringWithUTF8String:exception.what()] ?: @"Unknown C++ exception";
                [self reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                                operation:@"reannounceToAllTrackers"
                                  message:message];
            } catch (...) {
                [self reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                                operation:@"reannounceToAllTrackers"
                                  message:@"Unknown C++ exception"];
            }
        }
    }
}

- (void)dealloc {
    delete _session;
}

// MARK: - Path
- (NSString *)fastResumePathForInfoHashes:(TorrentHashes *)infoHashes {
    return [[_fastResumePath stringByAppendingPathComponent:infoHashes.best.hexString] stringByAppendingPathExtension:@"fastresume"];
}

- (NSString *)torrentFilePathForInfoHashes:(TorrentHashes *)infoHashes {
    return [[_torrentsPath stringByAppendingPathComponent:infoHashes.best.hexString] stringByAppendingPathExtension:@"torrent"];
}

- (NSString *)magnetURIsFilePath {
    return [_fastResumePath stringByAppendingPathComponent:@"magnet_links"];
}

// MARK: - Public
- (NSArray<TorrentHandle *> *)torrents {
    return _torrentsMap.allValues;
}

- (void)restoreSession {
    NSError *error;
    // load .torrents files
    NSArray *torrentsDirFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_torrentsPath error:&error];
    NSLog(@"%@", _torrentsPath);
    if (error) { NSLog(@"%@", error); }

    torrentsDirFiles = [torrentsDirFiles filteredArrayUsingPredicate:
                        [NSPredicate predicateWithFormat:@"self ENDSWITH %@", @".torrent"]];
    for (NSString *fileName in torrentsDirFiles) {
        NSString *filePath = [_torrentsPath stringByAppendingPathComponent:fileName];
        NSURL *fileURL = [NSURL fileURLWithPath:filePath];
        TorrentFile *torrent = [[TorrentFile alloc] initUnsafeWithFileAtURL:fileURL];
        if (torrent == nil) { continue; }
        [self addTorrent:torrent];
    }

    [self restoreMagnetURIs];
}
- (void)addDelegate:(id<SessionDelegate>)delegate {
    [self.delegates addObject:delegate];
}

- (void)removeDelegate:(id<SessionDelegate>)delegate {
    [self.delegates removeObject:delegate];
}

- (TorrentHandle* _Nullable)addTorrent:(id<Downloadable>)torrent {
    return [self addTorrent:torrent to:NULL];
}

- (TorrentHandle* _Nullable)addTorrent:(id<Downloadable>)torrent to: (NSUUID* _Nullable)storage {
    lt::add_torrent_params params;

    try {
        [torrent configureAddTorrentParams:&params forSession:self];
    } catch (std::exception const &exception) {
        NSString *message = [NSString stringWithUTF8String:exception.what()] ?: @"Unknown C++ exception";
        [self reportErrorWithCode:ErrorCodeBadFile operation:@"configureAddTorrent" message:message];
        return NULL;
    } catch (...) {
        [self reportErrorWithCode:ErrorCodeBadFile
                        operation:@"configureAddTorrent"
                          message:@"Unknown C++ exception"];
        return NULL;
    }

    // Set custom or default save path
    StorageModel* storageModel = NULL;
    BOOL customPathSetted = false;
    if (storage != NULL && [_storages objectForKey:storage] != NULL) {
        storageModel = [_storages objectForKey:storage];
        params.save_path = [storageModel.URL.path UTF8String];
        customPathSetted = true;
    } else if (params.save_path.length() != 0) {
        auto storageUUID = [[NSUUID alloc] initWithUUIDString: [[NSString alloc] initWithUTF8String: params.save_path.c_str()]];
        auto storage = [_storages objectForKey:storageUUID];
        if (storage != NULL) {
            storageModel = storage;
            params.save_path = storageModel.URL.path.UTF8String;
            customPathSetted = true;
        }
    }

    if (!customPathSetted) {
        params.save_path = [_downloadPath UTF8String];
    }

    params.storage_mode = _settings.preallocateStorage ? lt::storage_mode_allocate : lt::storage_mode_sparse;

    try {
        auto th = _session->add_torrent(params);
        auto torrentHandle = [[TorrentHandle alloc] initWith:th inSession:self];
        [torrent configureAfterAdded: torrentHandle];
        torrentHandle.storageUUID = storageModel.uuid;
        [self notifyDelegatesWithAdd: torrentHandle];
        return torrentHandle;
    } catch(std::exception const& exception) {
        NSString *message = [NSString stringWithUTF8String:exception.what()] ?: @"Unknown C++ exception";
        [self reportErrorWithCode:ErrorCodeLibtorrentOperationFailed operation:@"addTorrent" message:message];
        return NULL;
    } catch (...) {
        [self reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                        operation:@"addTorrent"
                          message:@"Unknown C++ exception"];
        return NULL;
    }
}

- (void)removeTorrent:(TorrentHandle *)torrent deleteFiles:(BOOL)deleteFiles {
    @synchronized (torrent) {
        [self notifyDelegatesWithRemove:torrent];

        auto handle = torrent.torrentHandle;
        if (!handle.is_valid()) {
            [self reportErrorWithCode:ErrorCodeInvalidTorrentHandle
                            operation:@"removeTorrent"
                              message:@"Handle was invalid before the operation started"];
            return;
        }

        try {
            [self removeStoredTorrentOrMagnet:handle infoHashes:torrent.infoHashes];

            // Remove torrent from session while holding the same lock used by
            // TorrentHandle operations and snapshot replacement.
            if (deleteFiles) {
                _session->remove_torrent(handle, lt::session::delete_files);
            } else {
                _session->remove_torrent(handle);
            }
        } catch (std::exception const &exception) {
            NSString *message = [NSString stringWithUTF8String:exception.what()] ?: @"Unknown C++ exception";
            ErrorCode code = ErrorCodeLibtorrentOperationFailed;
            auto systemError = dynamic_cast<lt::system_error const *>(&exception);
            if (systemError != nullptr && systemError->code() == lt::errors::invalid_torrent_handle) {
                code = ErrorCodeInvalidTorrentHandle;
            }
            [self reportErrorWithCode:code operation:@"removeTorrent" message:message];
        } catch (...) {
            [self reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                            operation:@"removeTorrent"
                              message:@"Unknown C++ exception"];
        }
    }
}

// MARK: - Private
- (void)reportErrorWithCode:(ErrorCode)code
                  operation:(NSString *)operation
                    message:(NSString *)message {
    NSString *nativeStack = [[NSThread callStackSymbols] componentsJoinedByString:@"\n"];
    NSError *error = [NSError errorWithDomain:ErrorDomain
                                         code:code
                                     userInfo:@{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"LibTorrent %@ failed: %@", operation, message],
        @"libtorrent.operation": operation,
        @"libtorrent.message": message,
        @"libtorrent.nativeStack": nativeStack
    }];

    NSLog(@"%@\n%@", error, nativeStack);
    for (id<SessionDelegate>delegate in self.delegates) {
        [delegate torrentManager:self didErrorOccur:error];
    }
}

- (void)removeStoredTorrentOrMagnet:(lt::torrent_handle)th infoHashes:(TorrentHashes *)hashes {
    // Remove stored torrent
    auto ti = th.torrent_file();

    dispatch_async(self.filesQueue, ^{
        [self removeTorrentFileWithInfo:ti];
        [self removeFastResumeFileWithInfo:ti];
        [self removeMagnetURIWithInfoHashes:hashes];
    });
}

// MARK: - Alerts Loop

#define ALERTS_LOOP_WAIT_MILLIS 500

- (void)alertsLoop {
    auto max_wait = lt::milliseconds(ALERTS_LOOP_WAIT_MILLIS);
    while (YES) {
        @autoreleasepool {
            try {
                auto const hasAlerts = _session->wait_for_alert(max_wait);
                std::vector<lt::alert *> alerts_queue;
                if (hasAlerts) {
                    _session->pop_alerts(&alerts_queue);
                } else {
                    continue;
                }

                for (auto it = alerts_queue.begin(); it != alerts_queue.end(); ++it) {
                    auto alert = (*it);
                    //            NSLog(@"type:%d msg:%s", alert->type(), alert->message().c_str());
                    switch (alert->type()) {
                        case lt::metadata_received_alert::alert_type: {
                            [self metadataReceivedAlert:(lt::torrent_alert *)alert];
                        } break;

                        case lt::metadata_failed_alert::alert_type: {
                            NSLog(@"TorrentKit metadata_failed - %s", alert->message().c_str());
                        } break;

                        case lt::block_finished_alert::alert_type: {
                        } break;

                        case lt::piece_finished_alert::alert_type: {
                            [self torrentMadeProgress:(lt::torrent_alert *)alert];
                        } break;

                        case lt::add_torrent_alert::alert_type: {
                            [self torrentAddedAlert:(lt::torrent_alert *)alert];
                        } break;

                        case lt::torrent_removed_alert::alert_type: {
                            //                        [self torrentRemovedAlert:(lt::torrent_alert *)alert];
                            continue; // Do not notify about update cause it was already removed
                        } break;

                        case lt::torrent_deleted_alert::alert_type: {
                            continue;
                        } break;

                        case lt::torrent_finished_alert::alert_type: {
                            [self torrentStateChanged:(lt::torrent_alert *)alert];
                        } break;

                        case lt::torrent_paused_alert::alert_type: {
                            [self torrentStateChanged:(lt::torrent_alert *)alert];
                        } break;

                        case lt::torrent_resumed_alert::alert_type: {
                            [self torrentStateChanged:(lt::torrent_alert *)alert];
                        } break;

                        case lt::torrent_error_alert::alert_type: {
                            NSLog(@"TorrentKit torrent_error - %s", alert->message().c_str());
                            [self handleTorrentError:(lt::torrent_error_alert *)alert];
                        } break;

                        case lt::file_error_alert::alert_type: {
                            NSLog(@"TorrentKit file_error - %s", alert->message().c_str());
                        } break;

                        case lt::session_error_alert::alert_type: {
                            NSLog(@"TorrentKit session_error - %s", alert->message().c_str());
                        } break;

                        case lt::peer_error_alert::alert_type: {
                            NSLog(@"TorrentKit peer_error - %s", alert->message().c_str());
                        } break;

                        case lt::tracker_announce_alert::alert_type:
                        case lt::tracker_error_alert::alert_type:
                        case lt::tracker_reply_alert::alert_type:
                        case lt::tracker_warning_alert::alert_type: {
                            NSLog(@"TorrentKit - %s", alert->message().c_str());
                            [self handleTrackerAlert: (lt::tracker_alert *)alert];
                        } break;

                        case lt::external_ip_alert::alert_type: {
                            [self handleExternalIPAlert: (lt::external_ip_alert *)alert];
                        } break;

                        case lt::state_update_alert::alert_type: {
                            auto stateUpdateAlert = static_cast<lt::state_update_alert *>(alert);
                            for (auto const &status : stateUpdateAlert->status) {
                                [self notifyDelegatesWithUpdate:status.handle];
                            }
                            continue;
                        } break;

                        case lt::save_resume_data_alert::alert_type: {
                            [self torrentSaveFastResume:(lt::save_resume_data_alert *)alert];
                            continue; // Not sure if need notify update
                        } break;

                        case lt::save_resume_data_failed_alert::alert_type: {
                            NSLog(@"TorrentKit save_resume_data_failed - %s", alert->message().c_str());
                            continue;
                        } break;

                        case lt::fastresume_rejected_alert::alert_type: {

                        } break;

                            // Skip log alerts
                        case lt::log_alert::alert_type: {
                            continue;
                        } break;

                        case lt::torrent_log_alert::alert_type: {
                            continue;
                        } break;

                        case lt::peer_log_alert::alert_type: {
                            continue;
                        } break;

                        default: break;
                    }

                    //                if (alert->message().size() > 0) {
                    //                    NSLog(@"TorrentKit - %s", alert->message().c_str());
                    //                }

                    if (dynamic_cast<lt::torrent_alert *>(alert) != nullptr) {
                        auto th = ((lt::torrent_alert *)alert)->handle;
                        if (!th.is_valid()) { continue; }

                        if (th.need_save_resume_data())
                            th.save_resume_data();

                        [self notifyDelegatesWithUpdate:th];
                    }
                }

                alerts_queue.clear();
            } catch (std::exception const &exception) {
                NSString *message = [NSString stringWithUTF8String:exception.what()] ?: @"Unknown C++ exception";
                [self reportErrorWithCode:ErrorCodeAlertFail operation:@"alertsLoop" message:message];
            } catch (...) {
                [self reportErrorWithCode:ErrorCodeAlertFail
                                operation:@"alertsLoop"
                                  message:@"Unknown C++ exception"];
            }
            [NSThread sleepForTimeInterval:0.1];
        }
    }
}

- (void)notifyDelegatesWithAdd:(TorrentHandle*) torrent {
    [_torrentsMap setObject:torrent forKey: torrent.infoHashes];
    for (id<SessionDelegate>delegate in self.delegates) {
        [delegate torrentManager:self didAddTorrent:torrent];
    }
}

- (void)notifyDelegatesWithRemove:(TorrentHandle*) torrent {
    [_torrentsMap removeObjectForKey: torrent.infoHashes];
    @synchronized (_automaticErrorRecoveryAttempts) {
        [_automaticErrorRecoveryAttempts removeObject:torrent.infoHashes];
    }
    TorrentHashes *hashesData = torrent.infoHashes;
    for (id<SessionDelegate>delegate in self.delegates) {
        [delegate torrentManager:self didRemoveTorrentWithHash:hashesData];
    }
}

- (void)notifyDelegatesWithUpdate:(lt::torrent_handle)th {
    if (!th.is_valid()) return;

    auto ih = th.info_hashes();

    auto hashes = [[TorrentHashes alloc] initWith:ih];
    
    auto torrent = _torrentsMap[hashes];
    if (torrent == NULL) {
        torrent = [[TorrentHandle alloc] initWith:th inSession:self];
    }

    for (id<SessionDelegate>delegate in self.delegates) {
        [delegate torrentManager:self didReceiveUpdateForTorrent:torrent];
    }
}

- (void)metadataReceivedAlert:(lt::torrent_alert *)alert {
    auto th = alert->handle;

    if (th.status().has_metadata) {
        [self requestTorrentFileSave:th];

        auto hashes = [[TorrentHashes alloc] initWith: th.info_hashes()];
        auto torrentHandle = _torrentsMap[hashes];
        if (torrentHandle.isFirstLastPiecePriority) {
            [torrentHandle applyPriorityConfiguration];
        }
    }
}

- (void)torrentAddedAlert:(lt::torrent_alert *)alert {
    auto th = alert->handle;
//    [self notifyDelegatesWithAdd:th];
    if (!th.is_valid()) {
        NSLog(@"%s: torrent_handle is invalid!", __FUNCTION__);
        return;
    }

    if (th.status().has_metadata) {
        auto hashes = [[TorrentHashes alloc] initWith:th.info_hashes()];
        if ([self hasValidTorrentFileForInfoHashes:hashes]) {
            dispatch_async(self.filesQueue, ^{
                [self removeMagnetURIWithInfoHashes:hashes];
            });
        } else {
            [self requestTorrentFileSave:th];
        }
        return;
    }

    auto magnetURI = lt::make_magnet_uri(magnetParams(th));
    dispatch_async(self.filesQueue, ^{
        [self saveMagnetURIWithContent:magnetURI];
    });
}

- (void)handleTrackerAlert:(lt::tracker_alert *)alert {
    auto th = alert->handle;

    if (alert->type() == lt::tracker_reply_alert::alert_type)
    {
        const int numPeers = static_cast<const lt::tracker_reply_alert *>(alert)->num_peers;
        auto hash = th.info_hashes().get_best();
        const int protocolVersionNum = (static_cast<const lt::tracker_reply_alert *>(alert)->version == lt::protocol_version::V1) ? 1 : 2;
        updatedTrackerStatuses[hash][std::string(alert->tracker_url())][alert->local_endpoint][protocolVersionNum] = numPeers;
    }
}

-(void)handleExternalIPAlert:(lt::external_ip_alert *)alert {
    auto externalIP = [[NSString alloc] initWithUTF8String: alert->external_address.to_string().c_str()];
    if (_lastExternalIP != externalIP) {
        if (_lastExternalIP != NULL) // Probably need add isReannounceWhenAddressChangedEnabled setting
            [self reannounceToAllTrackers];
        _lastExternalIP = externalIP;
    }

}

- (void)torrentRemoved:(lt::torrent_handle)handle {
//    [self notifyDelegatesWithRemove:th];
//    if (!handle.is_valid()) {
//        NSLog(@"%s: torrent_handle is invalid!", __FUNCTION__);
//        return;
//    }
//
//    auto torrent_info = handle.torrent_file();
////    auto info_hash = th.info_hash();
//
//    [self removeStoredTorrentOrMagnet:handle];
//    dispatch_async(self.filesQueue, ^{
////        [self removeStoredTorrentOrMagnet:th];
////        [self removeTorrentFileWithInfo:torrent_info];
////        [self removeMagnetURIWithHash:info_hash];
//    });
}

- (void)torrentStateChanged:(lt::torrent_alert *)alert {
//    auto th = alert->handle;
//    if (!th.is_valid()) return;
}

- (void)torrentMadeProgress:(lt::torrent_alert *)alert {
    auto th = alert->handle;
    auto hashes = [[TorrentHashes alloc] initWith: th.info_hashes()];
    @synchronized (_automaticErrorRecoveryAttempts) {
        [_automaticErrorRecoveryAttempts removeObject:hashes];
    }
}

- (void)handleTorrentError:(lt::torrent_error_alert *)alert {
    auto th = alert->handle;
    if (!th.is_valid()) { return; }

    auto hashes = [[TorrentHashes alloc] initWith:th.info_hashes()];
    auto torrentHandle = _torrentsMap[hashes];
    if (torrentHandle == nil) { return; }

    // Automatically retry errors that point at torrent storage. Other torrent
    // errors (invalid metadata, SSL configuration, duplicate torrents, etc.)
    // need a specific fix and must not be cleared in a tight alert loop.
    BOOL storageAccessRestored = NO;
    NSUUID *storageUUID = torrentHandle.storageUUID;
    if (storageUUID != nil) {
        StorageModel *storage = _storages[storageUUID];
        storageAccessRestored = storage != nil && [storage resolveSequrityScopes];
    }

    char const *errorFilename = alert->filename();
    NSString *filename = errorFilename != nullptr
        ? ([NSString stringWithUTF8String:errorFilename] ?: @"")
        : @"";
    NSString *defaultStoragePrefix = [_downloadPath stringByAppendingString:@"/"];
    BOOL isDefaultStorageError = [filename isEqualToString:_downloadPath]
        || [filename hasPrefix:defaultStoragePrefix];

    if (!storageAccessRestored && !isDefaultStorageError) { return; }

    // One automatic attempt is allowed until the torrent successfully writes
    // another block. This recovers transient I/O failures without repeatedly
    // clearing permanent failures such as a full disk.
    @synchronized (_automaticErrorRecoveryAttempts) {
        if ([_automaticErrorRecoveryAttempts containsObject:hashes]) { return; }
        [_automaticErrorRecoveryAttempts addObject:hashes];
    }

    try {
        th.clear_error();
        th.post_status();
    } catch (std::exception const &exception) {
        @synchronized (_automaticErrorRecoveryAttempts) {
            [_automaticErrorRecoveryAttempts removeObject:hashes];
        }
        NSString *message = [NSString stringWithUTF8String:exception.what()] ?: @"Unknown C++ exception";
        [self reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                        operation:@"recoverTorrentError"
                          message:message];
    } catch (...) {
        @synchronized (_automaticErrorRecoveryAttempts) {
            [_automaticErrorRecoveryAttempts removeObject:hashes];
        }
        [self reportErrorWithCode:ErrorCodeLibtorrentOperationFailed
                        operation:@"recoverTorrentError"
                          message:@"Unknown C++ exception"];
    }
}

- (void)torrentSaveFastResume:(lt::save_resume_data_alert *)alert {
    lt::torrent_handle h = alert->handle;
    if (!h.is_valid()) return;

    auto ih = h.info_hashes();

    lt::entry rd = lt::write_resume_data(alert->params);
    rd["storage_uuid"] = "";

    auto hashes = [[TorrentHashes alloc] initWith:ih];
    if (alert->params.ti != nullptr && [self saveTorrentFileWithParams:alert->params]) {
        dispatch_async(self.filesQueue, ^{
            [self removeMagnetURIWithInfoHashes:hashes];
        });
    }

    auto torrentHandle = _torrentsMap[hashes];
    auto storageUUID = torrentHandle.storageUUID;

    if (storageUUID != NULL) {
        for (StorageModel *storage in _storages.allValues) {
            if ([storage.uuid isEqual:storageUUID]) {
                rd["storage_uuid"] = storage.uuid.UUIDString.UTF8String;

                // Do not save fast resume if storage is not allowed
                if (!storage.allowed) return;
                break;
            }
        }
    }

    rd["first_last_piece_priority"] = torrentHandle.isFirstLastPiecePriority ? 1 : 0;

    auto ret = lt::bencode(rd);

    auto nspath = [self fastResumePathForInfoHashes: hashes];
    NSData *data = [NSData dataWithBytes:ret.data() length:ret.size()];
    NSError *error;
    if (![data writeToFile:nspath options:NSDataWritingAtomic error:&error]) {
        NSLog(@"Failed to save fast-resume data at %@: %@", nspath, error);
    }
}

// MARK: - Torrent saving
- (void)requestTorrentFileSave:(lt::torrent_handle const&)handle {
    try {
        handle.save_resume_data(lt::torrent_handle::save_info_dict);
    } catch (std::exception const& error) {
        NSLog(@"Failed to request torrent metadata save: %s", error.what());
    }
}

- (BOOL)hasValidTorrentFileForInfoHashes:(TorrentHashes *)infoHashes {
    NSString *filePath = [self torrentFilePathForInfoHashes:infoHashes];
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) { return NO; }

    TorrentFile *torrent = [[TorrentFile alloc] initUnsafeWithFileAtURL:[NSURL fileURLWithPath:filePath]];
    return torrent != nil && [torrent.infoHashes isEqual:infoHashes];
}

- (BOOL)saveTorrentFileWithParams:(lt::add_torrent_params const&)params {
    if (params.ti == nullptr) { return NO; }

    auto hash = params.ti->info_hashes();
    auto hashes = [[TorrentHashes alloc] initWith:hash];
    NSString *filePath = [self torrentFilePathForInfoHashes:hashes];
    if ([self hasValidTorrentFileForInfoHashes:hashes]) { return YES; }

    try {
        // Magnet-sourced v2 torrents may not have every piece layer until the
        // content is complete. Libtorrent can restore and fetch them on demand.
        auto torrentData = lt::write_torrent_file_buf(
            params,
            lt::write_flags::allow_missing_piece_layer
        );
        NSData *data = [NSData dataWithBytes:torrentData.data() length:torrentData.size()];
        NSError *error;
        if (![data writeToFile:filePath options:NSDataWritingAtomic error:&error]) {
            NSLog(@"Failed to save torrent file at %@: %@", filePath, error);
            return NO;
        }
        return YES;
    } catch (std::exception const& error) {
        NSLog(@"Failed to serialize torrent file at %@: %s", filePath, error.what());
        return NO;
    }
}

- (void)saveMagnetURIWithContent:(std::string)uri {
    if (uri.length() < 1) { return; }

    NSString *magnetURI = [NSString stringWithUTF8String:uri.c_str()];
    [self appendMagnetURIToFileStore:magnetURI];
}

- (void)appendMagnetURIToFileStore:(NSString *)magnetURI {
    TorrentHashes *newHashes = [self infoHashesForMagnetURI:magnetURI];
    NSMutableArray<NSString *> *magnetURIs = [[NSMutableArray alloc] init];
    for (NSString *storedURI in [self storedMagnetURIs]) {
        TorrentHashes *storedHashes = [self infoHashesForMagnetURI:storedURI];
        if (newHashes != nil && [storedHashes isEqual:newHashes]) { continue; }
        if ([storedURI caseInsensitiveCompare:magnetURI] == NSOrderedSame) { continue; }
        [magnetURIs addObject:storedURI];
    }
    [magnetURIs addObject:magnetURI];
    [self writeStoredMagnetURIs:magnetURIs];
}

// MARK: - Torrent deletion
- (void)removeFastResumeFileWithInfo:(std::shared_ptr<const lt::torrent_info>)ti {
    if (ti == nullptr) { return; }

    auto hash = ti->info_hashes();

    auto data = [[TorrentHashes alloc] initWith:hash];

    NSString *filePath = [self fastResumePathForInfoHashes:data];

    NSError *error;
    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
    if (error) { NSLog(@"success: %d, %@", success, error); }
}

- (void)removeTorrentFileWithInfo:(std::shared_ptr<const lt::torrent_info>)ti {
    if (ti == nullptr) { return; }

    auto hash = ti->info_hashes();
    auto hashes = [[TorrentHashes alloc] initWith:hash];
    NSString *filePath = [self torrentFilePathForInfoHashes:hashes];

    NSError *error;
    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
    if (error) { NSLog(@"success: %d, %@", success, error); }
}

- (NSArray<NSString *> *)storedMagnetURIs {
    NSString *path = [self magnetURIsFilePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) { return @[]; }

    NSError *error;
    NSString *fileContent = [NSString stringWithContentsOfFile:path
                                                      encoding:NSUTF8StringEncoding
                                                         error:&error];
    if (fileContent == nil) {
        NSLog(@"Failed to read stored magnet links at %@: %@", path, error);
        return @[];
    }

    NSPredicate *notEmpty = [NSPredicate predicateWithBlock:^BOOL(NSString *value, NSDictionary *_) {
        return value.length > 0;
    }];
    return [[fileContent componentsSeparatedByString:@"\n"] filteredArrayUsingPredicate:notEmpty];
}

- (void)writeStoredMagnetURIs:(NSArray<NSString *> *)magnetURIs {
    NSString *path = [self magnetURIsFilePath];
    NSString *fileContent = [magnetURIs componentsJoinedByString:@"\n"];
    NSError *error;
    if (![fileContent writeToFile:path
                       atomically:YES
                         encoding:NSUTF8StringEncoding
                            error:&error]) {
        NSLog(@"Failed to save magnet links at %@: %@", path, error);
    }
}

- (TorrentHashes * _Nullable)infoHashesForMagnetURI:(NSString *)magnetURI {
    lt::error_code error;
    auto params = lt::parse_magnet_uri(magnetURI.UTF8String, error);
    if (error) { return NULL; }

    return [[TorrentHashes alloc] initWith:params.info_hashes];
}

- (void)removeMagnetURIWithInfoHashes:(TorrentHashes *)infoHashes {
    NSMutableArray<NSString *> *remainingURIs = [[NSMutableArray alloc] init];
    BOOL didRemove = NO;
    for (NSString *magnetURI in [self storedMagnetURIs]) {
        TorrentHashes *storedHashes = [self infoHashesForMagnetURI:magnetURI];
        if (storedHashes != nil && [storedHashes isEqual:infoHashes]) {
            didRemove = YES;
            continue;
        }
        [remainingURIs addObject:magnetURI];
    }
    if (didRemove) { [self writeStoredMagnetURIs:remainingURIs]; }
}

- (void)restoreMagnetURIs {
    NSMutableArray<NSString *> *remainingURIs = [[NSMutableArray alloc] init];
    BOOL didRemoveStaleURI = NO;

    for (NSString *magnetURI in [self storedMagnetURIs]) {
        TorrentHashes *hashes = [self infoHashesForMagnetURI:magnetURI];
        if (hashes != nil && _torrentsMap[hashes] != nil) {
            didRemoveStaleURI = YES;
            continue;
        }

        NSURL *url = [NSURL URLWithString:magnetURI];
        MagnetURI *magnet = url == nil ? nil : [[MagnetURI alloc] initUnsafeWithMagnetURI:url];
        if (magnet != nil) { [self addTorrent:magnet]; }
        [remainingURIs addObject:magnetURI];
    }

    if (didRemoveStaleURI) { [self writeStoredMagnetURIs:remainingURIs]; }
}

- (std::unordered_map<lt::sha1_hash, std::unordered_map<std::string, std::unordered_map<lt::tcp::endpoint, std::unordered_map<int, int>>>>)updatedTrackerStatuses {
    return updatedTrackerStatuses;
}

@end
