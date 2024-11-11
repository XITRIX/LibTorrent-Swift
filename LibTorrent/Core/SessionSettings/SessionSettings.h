//
//  SessionSettings.h
//  TorrentKit
//
//  Created by Даниил Виноградов on 14.05.2022.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, SessionSettingsEncryptionPolicy) {
    SessionSettingsEncryptionPolicyEnabled,
    SessionSettingsEncryptionPolicyForced,
    SessionSettingsEncryptionPolicyDisabled
} NS_SWIFT_NAME(SessionSettings.EncryptionPolicy);


typedef NS_ENUM(NSUInteger, SessionSettingsProxyType) {
    SessionSettingsProxyTypeNone,
    SessionSettingsProxyTypeSocks4,
    SessionSettingsProxyTypeSocks5,
    SessionSettingsProxyTypeHttp,
    SessionSettingsProxyTypeI2p_proxy
} NS_SWIFT_NAME(SessionSettings.ProxyType);

NS_SWIFT_NAME(Session.Settings)
@interface SessionSettings : NSObject

@property (readwrite, nonatomic) NSString* agentName;
@property (readwrite, nonatomic) BOOL preallocateStorage;

@property (readwrite, nonatomic) NSInteger maxActiveTorrents;
@property (readwrite, nonatomic) NSInteger maxDownloadingTorrents;
@property (readwrite, nonatomic) NSInteger maxUploadingTorrents;

@property (readwrite, nonatomic) NSUInteger maxDownloadSpeed;
@property (readwrite, nonatomic) NSUInteger maxUploadSpeed;

@property (readwrite, nonatomic) BOOL isDhtEnabled;
@property (readwrite, nonatomic) BOOL isLsdEnabled;
@property (readwrite, nonatomic) BOOL isUtpEnabled;
@property (readwrite, nonatomic) BOOL isUpnpEnabled;
@property (readwrite, nonatomic) BOOL isNatEnabled;

@property (readwrite, nonatomic) SessionSettingsEncryptionPolicy encryptionPolicy;

@property (readwrite, nonatomic) NSInteger port;
@property (readwrite, nonatomic) NSInteger portBindRetries;

@property (readwrite, nonatomic) NSString* outgoingInterfaces;
@property (readwrite, nonatomic) NSString* listenInterfaces;

@property (readwrite, nonatomic) SessionSettingsProxyType proxyType;
@property (readwrite, nonatomic) NSString* proxyHostname;
@property (readwrite, nonatomic) NSInteger proxyHostPort;
@property (readwrite, nonatomic) BOOL proxyAuthRequired;
@property (readwrite, nonatomic) NSString* proxyUsername;
@property (readwrite, nonatomic) NSString* proxyPassword;
@property (readwrite, nonatomic) BOOL proxyPeerConnections;

@end

NS_ASSUME_NONNULL_END
