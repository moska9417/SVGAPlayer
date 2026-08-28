cmake_minimum_required(VERSION 3.5.0)
project(svgaplayer LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(PROTOBUF_HNP "${CMAKE_CURRENT_SOURCE_DIR}/third_party/protobuf.hnp")
set(PROTOBUF_EXTRACT_ROOT "${CMAKE_CURRENT_BINARY_DIR}/third_party")
set(PROTOBUF_ROOT "${PROTOBUF_EXTRACT_ROOT}/protobuf_3.25.2")

if(NOT EXISTS "${PROTOBUF_ROOT}/include/google/protobuf/message_lite.h")
    file(MAKE_DIRECTORY "${PROTOBUF_EXTRACT_ROOT}")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E tar xvf "${PROTOBUF_HNP}"
        WORKING_DIRECTORY "${PROTOBUF_EXTRACT_ROOT}"
        RESULT_VARIABLE PROTOBUF_EXTRACT_RESULT
        OUTPUT_QUIET
        ERROR_VARIABLE PROTOBUF_EXTRACT_ERROR
    )
    if(NOT PROTOBUF_EXTRACT_RESULT EQUAL 0)
        message(FATAL_ERROR "Failed to extract protobuf.hnp: ${PROTOBUF_EXTRACT_ERROR}")
    endif()
endif()

set(absl_DIR "${PROTOBUF_ROOT}/lib/cmake/absl")
set(utf8_range_DIR "${PROTOBUF_ROOT}/lib/cmake/utf8_range")
set(protobuf_DIR "${PROTOBUF_ROOT}/lib/cmake/protobuf")

find_package(Threads REQUIRED)
find_package(absl CONFIG REQUIRED)
find_package(utf8_range CONFIG REQUIRED)
find_package(protobuf CONFIG REQUIRED)

add_library(svgaplayer SHARED
    generated/svga.pb.cc
    napi_init.cpp
    svga_napi.cpp
    svga_parser.cpp
)

target_include_directories(svgaplayer
    BEFORE
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/compat"
)

target_link_libraries(svgaplayer
    PRIVATE
        libace_napi.z.so
        protobuf::libprotobuf-lite
        z
)
