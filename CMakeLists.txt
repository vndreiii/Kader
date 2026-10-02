cmake_minimum_required(VERSION 3.21)

# Versioning is semantic: MAJOR.MINOR.FIX. This is the single source of
# truth — PKGBUILD, AppImage names and the in-app updater all read it.
project(Kader VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

option(KADER_WITH_AI "Build semantic AI search (needs llama.cpp)" ON)
set(KADER_UPDATE_CHANNEL "" CACHE STRING
    "How this build is distributed: 'appimage', 'arch' or empty (auto-detect)")
set(KADER_UPDATE_REPO "vndreiii/kader" CACHE STRING "GitHub owner/repo the updater reads releases from")

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core Gui Qml Quick ShaderTools QuickDialogs2 Sql Positioning Concurrent Multimedia DBus Network)
# QtLocation backs the optional classic 2D map (QML only); the 3D globe has no
# dependency on it.
find_package(Qt6 6.5 QUIET OPTIONAL_COMPONENTS Location Test QuickTest)
find_package(Threads REQUIRED)
find_package(OpenSSL REQUIRED COMPONENTS Crypto)
find_package(PkgConfig REQUIRED)
pkg_check_modules(VIPS REQUIRED IMPORTED_TARGET vips-cpp)
pkg_check_modules(EXIV2 REQUIRED IMPORTED_TARGET exiv2)
pkg_check_modules(LIBRAW REQUIRED IMPORTED_TARGET libraw_r)
pkg_check_modules(POPPLER REQUIRED IMPORTED_TARGET poppler-cpp)

# Sibling-app event bus (private; optional so public CI and AppImages build).
find_package(MilfsConnect QUIET)

# llama.cpp for semantic search
set(KADER_HAVE_LLAMA 0)
if(KADER_WITH_AI)
    find_library(LLAMA_LIBRARY llama)
    find_library(MTMD_LIBRARY mtmd)
    find_path(LLAMA_INCLUDE_DIR llama.h)
    find_path(MTMD_INCLUDE_DIR mtmd.h)
    if(LLAMA_LIBRARY AND MTMD_LIBRARY AND LLAMA_INCLUDE_DIR AND MTMD_INCLUDE_DIR)
        set(KADER_HAVE_LLAMA 1)
    else()
        message(WARNING "llama.cpp not found — building without AI search")
    endif()
endif()

enable_testing()

set(SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src)
set(INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)

# ── Rust core (rust/kader-core) ─────────────────────────────────────────────
# Built with cargo as part of the normal build. The crate has no external
# dependencies, so this works offline (makepkg, CI, AppImage).
find_program(CARGO_EXECUTABLE cargo HINTS $ENV{HOME}/.cargo/bin REQUIRED)
set(KADER_CORE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/rust/kader-core)
set(KADER_CORE_TARGET_DIR ${CMAKE_CURRENT_BINARY_DIR}/cargo)
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(KADER_CORE_PROFILE_FLAG "")
    set(KADER_CORE_PROFILE_DIR debug)
else()
    set(KADER_CORE_PROFILE_FLAG "--release")
    set(KADER_CORE_PROFILE_DIR release)
endif()
set(KADER_CORE_LIB ${KADER_CORE_TARGET_DIR}/${KADER_CORE_PROFILE_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}kader_core${CMAKE_STATIC_LIBRARY_SUFFIX})
file(GLOB_RECURSE KADER_CORE_SOURCES CONFIGURE_DEPENDS ${KADER_CORE_DIR}/src/*.rs)
add_custom_command(
    OUTPUT ${KADER_CORE_LIB}
    COMMAND ${CMAKE_COMMAND} -E env CARGO_TARGET_DIR=${KADER_CORE_TARGET_DIR}
            ${CARGO_EXECUTABLE} build --offline --locked ${KADER_CORE_PROFILE_FLAG}
            --manifest-path ${KADER_CORE_DIR}/Cargo.toml
    DEPENDS ${KADER_CORE_SOURCES} ${KADER_CORE_DIR}/Cargo.toml ${KADER_CORE_DIR}/Cargo.lock
    COMMENT "Building Rust core (kader-core)"
    USES_TERMINAL
    VERBATIM)
add_custom_target(kader_core_build DEPENDS ${KADER_CORE_LIB})
add_library(kader_core STATIC IMPORTED GLOBAL)
set_target_properties(kader_core PROPERTIES IMPORTED_LOCATION ${KADER_CORE_LIB})
add_dependencies(kader_core kader_core_build)

# ── Backend library ─────────────────────────────────────────────────────────
set(SOURCES
    ${SOURCE_DIR}/ThemeManager.cpp
    ${SOURCE_DIR}/FileScanner.cpp
    ${SOURCE_DIR}/DatabaseManager.cpp
    ${SOURCE_DIR}/MediaRepository.cpp
    ${SOURCE_DIR}/AlbumRepository.cpp
    ${SOURCE_DIR}/ThumbnailGenerator.cpp
    ${SOURCE_DIR}/ThumbnailProvider.cpp
    ${SOURCE_DIR}/MediaModel.cpp
    ${SOURCE_DIR}/TimelineModel.cpp
    ${SOURCE_DIR}/AlbumModel.cpp
    ${SOURCE_DIR}/SettingsManager.cpp
    ${SOURCE_DIR}/StorageManager.cpp
    ${SOURCE_DIR}/SemanticSearchEngine.cpp
    ${SOURCE_DIR}/VideoEditor.cpp
    ${SOURCE_DIR}/Sort.cpp
    ${SOURCE_DIR}/GlobeItem.cpp
)

set(HEADERS
    ${INCLUDE_DIR}/ThemeManager.h
    ${INCLUDE_DIR}/FileScanner.h
    ${INCLUDE_DIR}/DatabaseManager.h
    ${INCLUDE_DIR}/MediaRepository.h
    ${INCLUDE_DIR}/AlbumRepository.h
    ${INCLUDE_DIR}/ThumbnailGenerator.h
    ${INCLUDE_DIR}/ThumbnailProvider.h
    ${INCLUDE_DIR}/MediaModel.h
    ${INCLUDE_DIR}/TimelineModel.h
    ${INCLUDE_DIR}/AlbumModel.h
    ${INCLUDE_DIR}/SettingsManager.h
    ${INCLUDE_DIR}/StorageManager.h
    ${INCLUDE_DIR}/SemanticSearchEngine.h
    ${INCLUDE_DIR}/VideoEditor.h
    ${INCLUDE_DIR}/Sort.h
    ${INCLUDE_DIR}/GlobeItem.h
    ${INCLUDE_DIR}/kader_core.h
)

add_library(KaderLib STATIC ${SOURCES} ${HEADERS})
target_include_directories(KaderLib PUBLIC ${INCLUDE_DIR})
target_compile_definitions(KaderLib PUBLIC
    KADER_VERSION="${PROJECT_VERSION}"
    KADER_HAVE_LLAMA=${KADER_HAVE_LLAMA})

target_link_libraries(KaderLib PUBLIC
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickDialogs2
    Qt6::Sql
    Qt6::Positioning
    Qt6::Concurrent
    Qt6::Multimedia
    Qt6::DBus
    Qt6::Network
    OpenSSL::Crypto
    PkgConfig::VIPS
    PkgConfig::EXIV2
    PkgConfig::LIBRAW
    PkgConfig::POPPLER
    kader_core
    Threads::Threads
    ${CMAKE_DL_LIBS}
)
if(KADER_HAVE_LLAMA)
    target_include_directories(KaderLib PRIVATE ${LLAMA_INCLUDE_DIR} ${MTMD_INCLUDE_DIR})
    target_link_libraries(KaderLib PUBLIC ${LLAMA_LIBRARY} ${MTMD_LIBRARY})
endif()

# ── QML module ──────────────────────────────────────────────────────────────
qt_add_qml_module(KaderApp
    STATIC
    URI Kader
    VERSION 1.0
    RESOURCE_PREFIX /
    QML_FILES
        qml/I18n.js
        qml/main.qml
        qml/components/MediaGrid.qml
        qml/components/MediaInfoPanel.qml
        qml/components/SidebarItem.qml
        qml/components/ImagePanner.qml
        qml/components/ExifModal.qml
        qml/components/MaterialSymbol.qml
        qml/components/M3Menu.qml
        qml/components/M3MenuItem.qml
        qml/components/M3MenuSeparator.qml
        qml/components/M3Icon.qml
        qml/components/M3Switch.qml
        qml/components/M3CheckBox.qml
        qml/components/SettingsRow.qml
        qml/components/SettingsSection.qml
        qml/components/Sidebar.qml
        qml/components/Tile.qml
        qml/components/AlbumEditModal.qml
        qml/components/AlbumGrid.qml
        qml/components/PasswordPrompt.qml
        qml/components/CascadeMenu.qml
        qml/components/CascadeMenuItem.qml
        qml/components/SortMenu.qml
        qml/components/PlacePopup.qml
        qml/views/AlbumListView.qml
        qml/views/AlbumDetailView.qml
        qml/views/ViewerOverlay.qml
        qml/views/ViewerWindow.qml
        qml/views/SettingsView.qml
        qml/views/MapView.qml
        qml/views/GlobeView.qml
        qml/views/DashboardView.qml
    RESOURCES
        "assets/Kader Logoicon.svg"
        assets/KaderPNGicon.png
        assets/MaterialSymbolsRounded.ttf
)

# BATCHABLE: scene-graph materials need the batchable vertex-shader variant.
qt_add_shaders(KaderApp "kader_shaders"
    BATCHABLE
    PREFIX
        "/shaders"
    BASE
        "qml/shaders"
    FILES
        qml/shaders/globe_shape.vert
        qml/shaders/globe_shape.frag
        qml/shaders/globe_sphere.vert
        qml/shaders/globe_sphere.frag
)

# ── Application ─────────────────────────────────────────────────────────────
add_executable(kader ${SOURCE_DIR}/main.cpp)

# The 5 MB vector world dataset is linked as an object file rather than a
# generated C++ array (BIG_RESOURCES) to keep compile time and memory down.
qt_add_resources(kader "kader_geo"
    PREFIX "/Kader"
    BIG_RESOURCES
    FILES assets/geo/world.kgeo)

target_link_libraries(kader PRIVATE KaderLib KaderApp)
if(MilfsConnect_FOUND)
    target_link_libraries(kader PRIVATE MilfsConnect::MilfsConnect)
    target_compile_definitions(kader PRIVATE KADER_HAVE_MILFS=1)
endif()

include(GNUInstallDirs)
install(TARGETS kader RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES kader.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES "assets/Kader Logoicon.svg"
        DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps RENAME kader.svg)
install(FILES assets/KaderPNGicon.png
        DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/256x256/apps RENAME kader.png)

message(STATUS "Kader ${PROJECT_VERSION}: AI search=${KADER_HAVE_LLAMA} milfs-connect=${MilfsConnect_FOUND} "
               "QtLocation=${Qt6Location_FOUND} update-channel='${KADER_UPDATE_CHANNEL}'")

# ── Tests ───────────────────────────────────────────────────────────────────
if(BUILD_TESTING)
    add_test(NAME rust_core
             COMMAND ${CMAKE_COMMAND} -E env CARGO_TARGET_DIR=${KADER_CORE_TARGET_DIR}
                     ${CARGO_EXECUTABLE} test --offline --locked --release
                     --manifest-path ${KADER_CORE_DIR}/Cargo.toml)
    if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/tests/backend_tests.cpp AND TARGET Qt6::Test)
        add_executable(backend_tests tests/backend_tests.cpp)
        target_link_libraries(backend_tests PRIVATE KaderLib Qt6::Test)
        add_test(NAME backend_tests COMMAND backend_tests)
    endif()
endif()
