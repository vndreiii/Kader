cmake_minimum_required(VERSION 3.16)

project(Kader VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickDialogs2 Sql Positioning Location Concurrent Multimedia Test QuickTest)
find_package(OpenSSL REQUIRED COMPONENTS Crypto)
find_package(PkgConfig REQUIRED)
pkg_check_modules(VIPS REQUIRED vips-cpp)
pkg_check_modules(EXIV2 REQUIRED exiv2)

enable_testing()

# Define directories
set(SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src)
set(INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)
set(QML_DIR ${CMAKE_CURRENT_SOURCE_DIR}/qml)

# Include directories
include_directories(${INCLUDE_DIR} ${VIPS_INCLUDE_DIRS} ${EXIV2_INCLUDE_DIRS})

# QmlMaterial Subdirectory
add_subdirectory(lib/QmlMaterial)

# Sources
set(SOURCES
    ${SOURCE_DIR}/ThemeManager.cpp
    ${SOURCE_DIR}/FileScanner.cpp
    ${SOURCE_DIR}/DatabaseManager.cpp
    ${SOURCE_DIR}/ThumbnailGenerator.cpp
    ${SOURCE_DIR}/ThumbnailProvider.cpp
    ${SOURCE_DIR}/MediaModel.cpp
    ${SOURCE_DIR}/TimelineModel.cpp
    ${SOURCE_DIR}/AlbumModel.cpp
    ${SOURCE_DIR}/SettingsManager.cpp
    ${SOURCE_DIR}/StorageManager.cpp
)

# Headers
set(HEADERS
    ${INCLUDE_DIR}/ThemeManager.h
    ${INCLUDE_DIR}/FileScanner.h
    ${INCLUDE_DIR}/DatabaseManager.h
    ${INCLUDE_DIR}/ThumbnailGenerator.h
    ${INCLUDE_DIR}/ThumbnailProvider.h
    ${INCLUDE_DIR}/MediaModel.h
    ${INCLUDE_DIR}/TimelineModel.h
    ${INCLUDE_DIR}/AlbumModel.h
    ${INCLUDE_DIR}/SettingsManager.h
    ${INCLUDE_DIR}/StorageManager.h
)

add_library(KaderLib STATIC
    ${SOURCES}
    ${HEADERS}
)

target_link_libraries(KaderLib PUBLIC
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickDialogs2
    Qt6::Sql
    Qt6::Positioning
    Qt6::Location
    Qt6::Concurrent
    Qt6::Multimedia
    OpenSSL::Crypto
    ${VIPS_LIBRARIES}
    ${EXIV2_LIBRARIES}
    qml_material
)

# QML Module setup
qt_add_qml_module(KaderApp
    STATIC
    URI Kader
    VERSION 1.0
    RESOURCE_PREFIX /
    QML_FILES
        qml/main.qml
        qml/components/MediaGrid.qml
        qml/components/MediaInfoPanel.qml
        qml/components/SidebarItem.qml
        qml/components/ImagePanner.qml
        qml/components/ExifModal.qml
        qml/components/M3Icon.qml
        qml/components/M3Switch.qml
        qml/components/SettingsRow.qml
        qml/components/SettingsSection.qml
        qml/components/Sidebar.qml
        qml/components/Tile.qml
        qml/components/AlbumGrid.qml
        qml/views/AlbumListView.qml
        qml/views/AlbumDetailView.qml
        qml/views/ViewerOverlay.qml
        qml/views/SettingsView.qml
        qml/views/MapView.qml
    RESOURCES
        assets/icon.svg
)

add_executable(kader
    ${SOURCE_DIR}/main.cpp
)

target_compile_definitions(kader PRIVATE CMAKE_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(kader PRIVATE KaderLib KaderApp)

# --- Testing ---
if(BUILD_TESTING)
    # Backend Tests
    add_executable(backend_tests tests/backend_tests.cpp)
    target_link_libraries(backend_tests PRIVATE KaderLib Qt6::Test)
    add_test(NAME backend_tests COMMAND backend_tests)

    # UI Tests (C++ Driver)
    set(UI_TEST_SOURCES tests/ui_test_driver.cpp)
    add_executable(ui_tests ${UI_TEST_SOURCES})
    target_compile_definitions(ui_tests PRIVATE CMAKE_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}" IS_TEST_BUILD)
    target_link_libraries(ui_tests PRIVATE
        KaderLib
        KaderApp
        Qt6::QuickTest Qt6::Test
    )
    add_test(NAME ui_tests COMMAND ui_tests)
endif()
