#----------------------------------------------------------------
# Generated CMake target import file for configuration "MinSizeRel".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "LibtorrentRasterbar::torrent-rasterbar" for configuration "MinSizeRel"
set_property(TARGET LibtorrentRasterbar::torrent-rasterbar APPEND PROPERTY IMPORTED_CONFIGURATIONS MINSIZEREL)
set_target_properties(LibtorrentRasterbar::torrent-rasterbar PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_MINSIZEREL "CXX"
  IMPORTED_LOCATION_MINSIZEREL "${_IMPORT_PREFIX}/lib/libtorrent-rasterbar.a"
  )

list(APPEND _cmake_import_check_targets LibtorrentRasterbar::torrent-rasterbar )
list(APPEND _cmake_import_check_files_for_LibtorrentRasterbar::torrent-rasterbar "${_IMPORT_PREFIX}/lib/libtorrent-rasterbar.a" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
