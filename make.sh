#!/bin/zsh

cmake ./Thirdparty/libtorrent \
    -B./libtorrent-build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=14 \
    -G Xcode \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_XCODE_ATTRIBUTE_ARCHS="arm64 x86_64" \
    -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS="watchsimulator watchos macosx iphonesimulator iphoneos driverkit appletvsimulator appletvos"
