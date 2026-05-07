cmake_minimum_required(VERSION 3.16)

project(Kader VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick Sql Positioning Location Concurrent)

# Define directories
set(SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src)
set(INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)
set(QML_DIR ${CMAKE_CURRENT_SOURCE_DIR}/qml)

# Include directories
include_directories(${INCLUDE_DIR})

# Sources
set(SOURCES
    ${SOURCE_DIR}/main.cpp
    ${SOURCE_DIR}/ThemeManager.cpp
    ${SOURCE_DIR}/FileScanner.cpp
)

# Headers
set(HEADERS
    ${INCLUDE_DIR}/ThemeManager.h
    ${INCLUDE_DIR}/FileScanner.h
)

# Add resources
qt_add_resources(Kader_RESOURCES
    ${QML_DIR}/main.qml
    ${QML_DIR}/components/MediaGrid.qml
    ${QML_DIR}/views/TimelineView.qml
)

add_executable(Kader
    ${SOURCES}
    ${HEADERS}
    ${Kader_RESOURCES}
)

target_compile_definitions(Kader PRIVATE CMAKE_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")

target_link_libraries(Kader PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::Sql
    Qt6::Positioning
    Qt6::Location
    Qt6::Concurrent
)

# QmlMaterial Library Integration
# Note: We'll add this as an import path in main.cpp to keep things simple for now,
# or we can add it as a subdirectory if it has its own CMakeLists.txt.
# For now, let's assume it's just a QML module we point to.
