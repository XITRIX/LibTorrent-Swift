//
//  NSObject+SessionSettings.m
//  TorrentKit
//
//  Created by Даниил Виноградов on 14.05.2022.
//

#import "SessionSettings_Internal.h"

#import "libtorrent/alert.hpp"

@implementation SessionSettings

- (instancetype)init {
    self = [super init];

    if (self) {
        _preallocateStorage = false;
    }

    return self;
}

- (lt::settings_pack)settingsPack {
    lt::settings_pack settings;

    // Must have
    settings.set_int(lt::settings_pack::alert_mask, lt::alert_category::all);

    // Settings pack
    settings.set_int(lt::settings_pack::active_limit, (int)_maxActiveTorrents);
    settings.set_int(lt::settings_pack::active_downloads, (int)_maxDownloadingTorrents);
    settings.set_int(lt::settings_pack::active_seeds, (int)_maxUploadingTorrents);

    settings.set_int(lt::settings_pack::download_rate_limit, (int)_maxDownloadSpeed);
    settings.set_int(lt::settings_pack::upload_rate_limit, (int)_maxUploadSpeed);

    settings.set_bool(lt::settings_pack::enable_dht, _isDhtEnabled);
    settings.set_bool(lt::settings_pack::enable_lsd, _isLsdEnabled);
    settings.set_bool(lt::settings_pack::enable_incoming_utp, _isUtpEnabled);
    settings.set_bool(lt::settings_pack::enable_outgoing_utp, _isUtpEnabled);
    settings.set_bool(lt::settings_pack::enable_upnp, _isUpnpEnabled);
    settings.set_bool(lt::settings_pack::enable_natpmp, _isNatEnabled);

    switch (_encryptionPolicy) {
        case SessionSettingsEncryptionPolicyEnabled:
            settings.set_int(lt::settings_pack::out_enc_policy, lt::settings_pack::pe_enabled);
            settings.set_int(lt::settings_pack::in_enc_policy, lt::settings_pack::pe_enabled);
            break;
        case SessionSettingsEncryptionPolicyForced:
            settings.set_int(lt::settings_pack::out_enc_policy, lt::settings_pack::pe_forced);
            settings.set_int(lt::settings_pack::in_enc_policy, lt::settings_pack::pe_forced);
            break;
        case SessionSettingsEncryptionPolicyDisabled:
            settings.set_int(lt::settings_pack::out_enc_policy, lt::settings_pack::pe_disabled);
            settings.set_int(lt::settings_pack::in_enc_policy, lt::settings_pack::pe_disabled);
            break;
    }

    return settings;
}

@end
