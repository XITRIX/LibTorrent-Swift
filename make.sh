#!/bin/zsh

cmake ./Thirdparty/libtorrent \
    -B./libtorrent-build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=14 \
    -G Xcode \
    -DCMAKE_CXX_FLAGS=-DTORRENT_HAVE_MMAP=0 \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_XCODE_ATTRIBUTE_ARCHS="\$(ARCHS_STANDARD)" \
    -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS="xrsimulator xros watchsimulator watchos macosx iphonesimulator iphoneos driverkit appletvsimulator appletvos"

