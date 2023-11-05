set(_TARGET_INTERFACE_LINK_LIBRARIES "-framework CoreFoundation;-framework SystemConfiguration;/opt/homebrew/Cellar/openssl@3/3.1.3/lib/libssl.dylib;/opt/homebrew/Cellar/openssl@3/3.1.3/lib/libcrypto.dylib")
set(_TARGET_INTERFACE_COMPILE_OPTIONS "-fexceptions")
set(_TARGET_INTERFACE_INCLUDE_DIRS "$<0:/Users/daniilvinogradov/Documents/Dev/iOS/LibTorrent/Thirdparty/libtorrent/include>;${CMAKE_INSTALL_PREFIX}/$<1:include>;/opt/homebrew/Cellar/openssl@3/3.1.3/include;/opt/homebrew/include")
set(_TARGET_INTERFACE_DEFINITIONS "$<$<CONFIG:Debug>:TORRENT_USE_ASSERTS>;BOOST_ASIO_ENABLE_CANCELIO;BOOST_ASIO_NO_DEPRECATED;TORRENT_USE_OPENSSL;TORRENT_USE_LIBCRYPTO;TORRENT_SSL_PEERS;OPENSSL_NO_SSL2")
set(_TARGET_OUTPUT_NAME "torrent-rasterbar")

set(_INSTALL_LIBDIR "lib")
set(_INSTALL_INCLUDEDIR "include")
set(_SHARED_LIBRARY_PREFIX "lib")

set(_PROJECT_NAME "libtorrent")
set(_PROJECT_DESCRIPTION "Bittorrent library")
set(_PROJECT_VERSION "2.0.9")
