#!/bin/zsh

cmake ./Thirdparty/libtorrent \
    -B./libtorrent-build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=14 \
    -G Xcode \
    -DCMAKE_XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET=12.0 \
    -DCMAKE_XCODE_ATTRIBUTE_TVOS_DEPLOYMENT_TARGET=12.0 \
    -DCMAKE_XCODE_ATTRIBUTE_XROS_DEPLOYMENT_TARGET=1.0 \
    -DCMAKE_XCODE_ATTRIBUTE_WATCHOS_DEPLOYMENT_TARGET=4.0 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=10.13 \
    -DCMAKE_CXX_FLAGS="-DTORRENT_HAVE_MMAP=0 -DNDEBUG" \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_XCODE_ATTRIBUTE_ARCHS="\$(ARCHS_STANDARD)" \
    -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS="xrsimulator xros watchsimulator watchos macosx iphonesimulator iphoneos driverkit appletvsimulator appletvos"

