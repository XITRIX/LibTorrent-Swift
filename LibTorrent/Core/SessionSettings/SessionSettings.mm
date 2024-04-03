//
//  NSObject+SessionSettings.m
//  TorrentKit
//
//  Created by Даниил Виноградов on 14.05.2022.
//

#import "SessionSettings_Internal.h"

#import "libtorrent/alert.hpp"

lt::settings_pack::proxy_type_t proxyTypeConverter(SessionSettings *pack) {
    switch (pack.proxyType) {
        case SessionSettingsProxyTypeNone:
            return lt::settings_pack::proxy_type_t::none;
        case SessionSettingsProxyTypeSocks4:
            return lt::settings_pack::proxy_type_t::socks4;
        case SessionSettingsProxyTypeSocks5:
            return pack.proxyAuthRequired ?
                lt::settings_pack::proxy_type_t::socks5_pw :
                lt::settings_pack::proxy_type_t::socks5;
        case SessionSettingsProxyTypeHttp:
            return pack.proxyAuthRequired ?
                lt::settings_pack::proxy_type_t::http_pw :
                lt::settings_pack::proxy_type_t::http;
        case SessionSettingsProxyTypeI2p_proxy:
            return lt::settings_pack::proxy_type_t::i2p_proxy;
    }
}

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
    settings.set_int(lt::settings_pack::alert_mask, lt::alert_category_t::all());

    // Torrent limitations
    settings.set_int(lt::settings_pack::active_limit, (int)_maxActiveTorrents);
    settings.set_int(lt::settings_pack::active_downloads, (int)_maxDownloadingTorrents);
    settings.set_int(lt::settings_pack::active_seeds, (int)_maxUploadingTorrents);

    // Speed limitations
    settings.set_int(lt::settings_pack::download_rate_limit, (int)_maxDownloadSpeed);
    settings.set_int(lt::settings_pack::upload_rate_limit, (int)_maxUploadSpeed);

    // Networking protocols
    settings.set_bool(lt::settings_pack::enable_dht, _isDhtEnabled);
    settings.set_bool(lt::settings_pack::enable_lsd, _isLsdEnabled);
    settings.set_bool(lt::settings_pack::enable_incoming_utp, _isUtpEnabled);
    settings.set_bool(lt::settings_pack::enable_outgoing_utp, _isUtpEnabled);
    settings.set_bool(lt::settings_pack::enable_upnp, _isUpnpEnabled);
    settings.set_bool(lt::settings_pack::enable_natpmp, _isNatEnabled);

    // Encryption policy
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

    // Ports
    if (_portBindRetries >= 0)
        settings.set_int(lt::settings_pack::max_retry_port_bind, (int)_portBindRetries);

    // Interfaces
    settings.set_str(lt::settings_pack::outgoing_interfaces, [_outgoingInterfaces UTF8String]);
    settings.set_str(lt::settings_pack::listen_interfaces, [_listenInterfaces UTF8String]);

    // Proxy
    settings.set_int(lt::settings_pack::proxy_type, proxyTypeConverter(self));
    if (_proxyType != SessionSettingsProxyTypeNone) {
        settings.set_int(lt::settings_pack::proxy_port, (int)_proxyHostPort);
        settings.set_str(lt::settings_pack::proxy_hostname, [_proxyHostname UTF8String]);
        if (_proxyAuthRequired) {
            settings.set_str(lt::settings_pack::proxy_username, [_proxyUsername UTF8String]);
            settings.set_str(lt::settings_pack::proxy_password, [_proxyPassword UTF8String]);
        }
        settings.set_bool(lt::settings_pack::proxy_peer_connections, _proxyPeerConnections);
        settings.set_bool(lt::settings_pack::proxy_tracker_connections, true);
        settings.set_bool(lt::settings_pack::proxy_hostnames, true);
    }

    return settings;
}

@end
