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
#import "NSData+Sha1Hash.h"

//libtorrent
#import "libtorrent/session.hpp"
#import "libtorrent/alert.hpp"
#import "libtorrent/alert_types.hpp"

#import "libtorrent/write_resume_data.hpp"
#import "libtorrent/torrent_handle.hpp"
#import "libtorrent/torrent_info.hpp"
#import "libtorrent/create_torrent.hpp"
#import "libtorrent/magnet_uri.hpp"

#import "libtorrent/bencode.hpp"
#import "libtorrent/bdecode.hpp"

#include <fstream>

static NSErrorDomain ErrorDomain = @"ru.xitrix.TorrentKit.Session.error";
static NSString *EventsQueueIdentifier = @"ru.xitrix.TorrentKit.Session.events.queue";
static NSString *FileEntriesQueueIdentifier = @"ru.xitrix.TorrentKit.Session.files.queue";

@implementation StorageModel : NSObject
@end

@implementation Session : NSObject

std::unordered_map<lt::sha1_hash, std::unordered_map<std::string, std::unordered_map<lt::tcp::endpoint, std::unordered_map<int, int>>>> updatedTrackerStatuses;

// MARK: - Init
- (instancetype)initWith:(NSString *)downloadPath torrentsPath:(NSString *)torrentsPath fastResumePath:(NSString *)fastResumePath settings:(SessionSettings *)settings storages:(NSDictionary<NSUUID*, StorageModel*>*)storages {
    self = [super init];
    if (self) {
        _downloadPath = downloadPath;
        _torrentsPath = torrentsPath;
        _fastResumePath = fastResumePath;
        _settings = settings;
        _storages = storages;

        NSError * error;
        [[NSFileManager defaultManager] createDirectoryAtPath:downloadPath withIntermediateDirectories:YES attributes:nil error:&error];
        [[NSFileManager defaultManager] createDirectoryAtPath:torrentsPath withIntermediateDirectories:YES attributes:nil error:&error];
        [[NSFileManager defaultManager] createDirectoryAtPath:fastResumePath withIntermediateDirectories:YES attributes:nil error:&error];

        _session = new lt::session(_settings.settingsPack);

        _filesQueue = dispatch_queue_create([FileEntriesQueueIdentifier UTF8String], DISPATCH_QUEUE_SERIAL);
        _torrentsMap = [[NSMutableDictionary alloc] init];
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
        try {
            torrent.torrentHandle.force_reannounce(0, -1, lt::torrent_handle::ignore_min_interval);
        } catch (const std::exception &) {}
    }
}

- (void)dealloc {
    delete _session;
}

// MARK: - Path
- (NSString *)fastResumePathForInfoHashes:(TorrentHashes *)infoHashes {
    return [[_fastResumePath stringByAppendingPathComponent:infoHashes.best.hexString] stringByAppendingPathExtension:@"fastresume"];
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
        [self addTorrent:torrent];
    }
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
    } catch (...) {
        NSError *error = [self errorWithCode:ErrorCodeBadFile message:@"Failed to add torrent"];
        NSLog(@"%@", error);
//        [self notifyDelegatesAboutError:error];
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
    } catch(std::exception const& ex) {
        return NULL;
    }
}

- (void)removeTorrent:(TorrentHandle *)torrent deleteFiles:(BOOL)deleteFiles {
    [self notifyDelegatesWithRemove:torrent];
    [self removeStoredTorrentOrMagnet:torrent.torrentHandle];

    // Remove torrrent from session
    if (deleteFiles) {
        _session->remove_torrent(torrent.torrentHandle, lt::session::delete_files);
    } else {
        _session->remove_torrent(torrent.torrentHandle);
    }
}

// MARK: - Private
- (NSError *)errorWithCode:(ErrorCode)code message:(NSString *)message {
    return [NSError errorWithDomain:ErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (void)removeStoredTorrentOrMagnet:(lt::torrent_handle)th {
    // Remove stored torrent
    auto ti = th.torrent_file();

    dispatch_async(self.filesQueue, ^{
        [self removeTorrentFileWithInfo:ti];
        [self removeFastResumeFileWithInfo:ti];
        auto ih = th.info_hash();
        [self removeMagnetURIWithHash:ih];
    });
}

// MARK: - Alerts Loop

#define ALERTS_LOOP_WAIT_MILLIS 500

- (void)alertsLoop {
    auto max_wait = lt::milliseconds(ALERTS_LOOP_WAIT_MILLIS);
    while (YES) {
        @autoreleasepool {
            try {
                auto alert_ptr = _session->wait_for_alert(max_wait);
                std::vector<lt::alert *> alerts_queue;
                if (alert_ptr != nullptr) {
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
                            //                    [self metadataReceivedAlert:(lt::torrent_alert *)alert];
                        } break;

                        case lt::block_finished_alert::alert_type: {
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
                            [self torrentInputOutputError:(lt::torrent_alert *) alert];
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

                        case lt::save_resume_data_alert::alert_type: {
                            [self torrentSaveFastResume:(lt::save_resume_data_alert *)alert];
                            continue; // Not sure if need notify update
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
            } catch (...) {
                NSError *error = [self errorWithCode:ErrorCodeAlertFail message:@"Failed to handle alerts"];
                NSLog(@"%@", error);
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
#if LIBTORRENT_VERSION_MAJOR > 1
    TorrentHashes *hashesData = [[TorrentHashes alloc] initWith:torrent.torrentHandle.info_hashes()];
#else
    TorrentHashes *hashesData = [[TorrentHashes alloc] initWith:torrent.torrentHandle.info_hash()];
#endif
    for (id<SessionDelegate>delegate in self.delegates) {
        [delegate torrentManager:self didRemoveTorrentWithHash:hashesData];
    }
}

- (void)notifyDelegatesWithUpdate:(lt::torrent_handle)th {
    if (!th.is_valid()) return;

#if LIBTORRENT_VERSION_MAJOR > 1
    auto ih = th.info_hashes();
#else
    auto ih = th.info_hash();
#endif

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
    auto info = th.torrent_file();

    if (th.status().has_metadata) {
        [self saveTorrentFileWithInfo:info];
        [self removeMagnetURIWithHash:th.info_hash()];
    }
}

- (void)torrentAddedAlert:(lt::torrent_alert *)alert {
    auto th = alert->handle;
//    [self notifyDelegatesWithAdd:th];
    if (!th.is_valid()) {
        NSLog(@"%s: torrent_handle is invalid!", __FUNCTION__);
        return;
    }

    bool has_metadata = th.status().has_metadata;
    auto torrent_info = th.torrent_file();
    auto margnet_uri = lt::make_magnet_uri(th);
    dispatch_async(self.filesQueue, ^{
        if (has_metadata) {
            [self saveTorrentFileWithInfo:torrent_info];
        } else {
            [self saveMagnetURIWithContent:margnet_uri];
        }
    });
}

- (void)handleTrackerAlert:(lt::tracker_alert *)alert {
    auto th = alert->handle;

    if (alert->type() == lt::tracker_reply_alert::alert_type)
    {
        const int numPeers = static_cast<const lt::tracker_reply_alert *>(alert)->num_peers;
#if LIBTORRENT_VERSION_MAJOR > 1        
        auto hash = th.info_hashes().get_best();
        const int protocolVersionNum = (static_cast<const lt::tracker_reply_alert *>(alert)->version == lt::protocol_version::V1) ? 1 : 2;
#else
        auto hash = th.info_hash();
        const int protocolVersionNum = 1;
#endif
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

- (void)torrentInputOutputError:(lt::torrent_alert *)alert {
    auto th = alert->handle;
    auto hashes = [[TorrentHashes alloc] initWith: th.info_hashes()];
    auto torrentHandle = _torrentsMap[hashes];
    [_storages[torrentHandle.storageUUID] resolveSequrityScopes];
}

- (void)torrentSaveFastResume:(lt::save_resume_data_alert *)alert {
    lt::torrent_handle h = alert->handle;
    if (!h.is_valid()) return;

#if LIBTORRENT_VERSION_MAJOR > 1
    auto ih = h.info_hashes();
#else
    auto ih = h.info_hash();
#endif

    std::vector<char> ret;
    lt::entry rd = lt::write_resume_data(alert->params);
    rd["storage_uuid"] = "";

    auto hashes = [[TorrentHashes alloc] initWith:ih];
    auto torrentHandle = _torrentsMap[hashes];
    auto storageUUID = torrentHandle.storageUUID;

    if (storageUUID != NULL) {
        for (StorageModel *storage in _storages.allValues) {
            if (storage.uuid == storageUUID) {
                rd["storage_uuid"] = storage.uuid.UUIDString.UTF8String;

                // Do not save fast resume if storage is not allowed
                if (!storage.allowed) return;
                break;
            }
        }
    }

    bencode(std::back_inserter(ret), rd);

    auto nspath = [self fastResumePathForInfoHashes: hashes];
    std::string path = std::string([nspath UTF8String]);

    std::fstream f(path, std::ios_base::trunc | std::ios_base::out | std::ios_base::binary);
    f.write(ret.data(), ret.size());
}

// MARK: - Torrent saving
- (void)saveTorrentFileWithInfo:(std::shared_ptr<const lt::torrent_info>)ti {
    if (ti == nullptr) { return; }

    NSString *fileName = [NSString stringWithFormat:@"%s.torrent", (*ti).name().c_str()];
    NSString *filePath = [_torrentsPath stringByAppendingPathComponent:fileName];

    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        lt::create_torrent new_torrent(*ti);
        std::vector<char> out_file;

        NSString* appName = NSBundle.mainBundle.infoDictionary[(NSString*) kCFBundleNameKey];
        NSString* appVersion = [NSBundle.mainBundle objectForInfoDictionaryKey: @"CFBundleShortVersionString"];
        NSString* creator = [NSString stringWithFormat:@"%@ %@", appName, appVersion];

        new_torrent.set_creator([creator cStringUsingEncoding: NSUTF8StringEncoding]);
        lt::bencode(std::back_inserter(out_file), new_torrent.generate());

        NSData *data = [NSData dataWithBytes:out_file.data() length:out_file.size()];
        BOOL success = [data writeToFile:filePath atomically:YES];
        if (!success) { NSLog(@"Can't save .torrent file"); }
    }
}

- (void)saveMagnetURIWithContent:(std::string)uri {
    if (uri.length() < 1) { return; }

    NSString *magnetURI = [NSString stringWithUTF8String:uri.c_str()];
    [self appendMagnetURIToFileStore:magnetURI];
}

- (void)appendMagnetURIToFileStore:(NSString *)magnetURI {
    // read from existing file
    NSError *error;
    NSString *fileContent = [NSString stringWithContentsOfFile:[self magnetURIsFilePath]
                                                      encoding:NSUTF8StringEncoding
                                                         error:&error];
    if (error) { NSLog(@"%@", error); }

    NSMutableArray *magnetURIs = [[fileContent componentsSeparatedByString:@"\n"] mutableCopy];
    if (magnetURIs == nil) {
        magnetURIs = [[NSMutableArray alloc] init];
    }
    // remove all existing copies
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"NOT (SELF CONTAINS[cd] %@)", magnetURI];
    [magnetURIs filterUsingPredicate:predicate];
    // add new uri
    [magnetURIs addObject:magnetURI];

    // save to file
    fileContent = [magnetURIs componentsJoinedByString:@"\n"];
    [fileContent writeToFile:[self magnetURIsFilePath]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:&error];
    if (error) { NSLog(@"%@", error); }
}

// MARK: - Torrent deletion
- (void)removeFastResumeFileWithInfo:(std::shared_ptr<const lt::torrent_info>)ti {
    if (ti == nullptr) { return; }

#if LIBTORRENT_VERSION_MAJOR > 1
    auto hash = ti->info_hashes();
#else
    auto hash = ti->info_hash();
#endif

    auto data = [[TorrentHashes alloc] initWith:hash];

    NSString *filePath = [self fastResumePathForInfoHashes:data];

    NSError *error;
    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
    if (error) { NSLog(@"success: %d, %@", success, error); }
}

- (void)removeTorrentFileWithInfo:(std::shared_ptr<const lt::torrent_info>)ti {
    if (ti == nullptr) { return; }

    NSString *fileName = [NSString stringWithFormat:@"%s.torrent", (*ti).name().c_str()];
    NSString *filePath = [_torrentsPath stringByAppendingPathComponent:fileName];

    NSError *error;
    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
    if (error) { NSLog(@"success: %d, %@", success, error); }
}

- (void)removeMagnetURIWithHash:(lt::sha1_hash)info_hash {
    NSData *hashData = [[NSData alloc] initWith:info_hash];
    [self removeFromFileStoreMagnetURIWithHash:hashData.hexString];
}

- (void)removeFromFileStoreMagnetURIWithHash:(NSString *)hashString {
    // read from existing file
    NSError *error;
    NSString *fileContent = [NSString stringWithContentsOfFile:[self magnetURIsFilePath]
                                                      encoding:NSUTF8StringEncoding
                                                         error:&error];
    if (error) { NSLog(@"%@", error); }

    NSMutableArray *magnetURIs = [[fileContent componentsSeparatedByString:@"\n"] mutableCopy];
    // remove all existing copies
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"NOT (SELF CONTAINS[cd] %@)", hashString];
    [magnetURIs filterUsingPredicate:predicate];

    // save to file
    fileContent = [magnetURIs componentsJoinedByString:@"\n"];
    [fileContent writeToFile:[self magnetURIsFilePath]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:&error];
    if (error) { NSLog(@"%@", error); }
}

- (std::unordered_map<lt::sha1_hash, std::unordered_map<std::string, std::unordered_map<lt::tcp::endpoint, std::unordered_map<int, int>>>>)updatedTrackerStatuses {
    return updatedTrackerStatuses;
}

@end
