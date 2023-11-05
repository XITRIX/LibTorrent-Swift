#!/bin/zsh

cmake ./Thirdparty/libtorrent \
    -B./libtorrent-build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=14 \
    -G Xcode \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_XCODE_ATTRIBUTE_ARCHS="\$(ARCHS_STANDARD)" \
    -DCMAKE_OSX_SYSROOT="auto" \
    -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS="watchsimulator watchos macosx iphonesimulator iphoneos driverkit appletvsimulator appletvos"

cmake . \
    -B./libtorrent-build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=14 \
    -G Xcode \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_XCODE_ATTRIBUTE_ARCHS="\$(ARCHS_STANDARD)" \
    -DCMAKE_OSX_SYSROOT="auto" \
    -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS="watchsimulator watchos macosx iphonesimulator iphoneos driverkit appletvsimulator appletvos"
