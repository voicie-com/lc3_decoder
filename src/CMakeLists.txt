cmake_minimum_required(VERSION 3.10)

project(lc3_decoder_library VERSION 0.0.1 LANGUAGES C)

# Define sources from liblc3
set(LC3_SOURCES
  "../src/liblc3/src/attdet.c"
  "../src/liblc3/src/bits.c"
  "../src/liblc3/src/bwdet.c"
  "../src/liblc3/src/energy.c"
  "../src/liblc3/src/lc3.c"
  "../src/liblc3/src/ltpf.c"
  "../src/liblc3/src/mdct.c"
  "../src/liblc3/src/plc.c"
  "../src/liblc3/src/sns.c"
  "../src/liblc3/src/spec.c"
  "../src/liblc3/src/tables.c"
  "../src/liblc3/src/tns.c"
)

add_library(lc3_decoder SHARED
  ${LC3_SOURCES}
)

# Include the liblc3 headers
target_include_directories(lc3_decoder PUBLIC "../src/liblc3/include")

set_target_properties(lc3_decoder PROPERTIES
  PUBLIC_HEADER "../src/liblc3/include/lc3.h"
  OUTPUT_NAME "lc3"
)

target_compile_definitions(lc3_decoder PUBLIC DART_SHARED_LIB)

if (MSVC)
   target_compile_options(lc3_decoder PRIVATE "/wd4244" "/wd4305" "/fp:fast")
else()
   target_compile_options(lc3_decoder PRIVATE "-ffast-math")
endif()

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(lc3_decoder PRIVATE "-Wl,-z,max-page-size=16384")
endif()
