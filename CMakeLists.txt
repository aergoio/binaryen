PROJECT(binaryen C CXX)
CMAKE_MINIMUM_REQUIRED(VERSION 2.8.7)
INCLUDE(GNUInstallDirs)

IF(NOT CMAKE_BUILD_TYPE)
  MESSAGE(STATUS "No build type selected, default to Release")
  SET(CMAKE_BUILD_TYPE "Release")
ENDIF()

OPTION(BUILD_STATIC_LIB "Build as a static library" ON)

# Support functionality.

FUNCTION(ADD_COMPILE_FLAG value)
  MESSAGE(STATUS "Building with ${value}")
  FOREACH(variable CMAKE_C_FLAGS CMAKE_CXX_FLAGS)
    SET(${variable} "${${variable}} ${value}" PARENT_SCOPE)
  ENDFOREACH(variable)
ENDFUNCTION()

FUNCTION(ADD_CXX_FLAG value)
  MESSAGE(STATUS "Building with ${value}")
  SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${value}" PARENT_SCOPE)
ENDFUNCTION()

FUNCTION(ADD_DEBUG_COMPILE_FLAG value)
  IF("${CMAKE_BUILD_TYPE}" MATCHES "Debug")
    MESSAGE(STATUS "Building with ${value}")
  ENDIF()
  FOREACH(variable CMAKE_C_FLAGS_DEBUG CMAKE_CXX_FLAGS_DEBUG)
    SET(${variable} "${${variable}} ${value}" PARENT_SCOPE)
  ENDFOREACH(variable)
ENDFUNCTION()

FUNCTION(ADD_NONDEBUG_COMPILE_FLAG value)
  IF(NOT "${CMAKE_BUILD_TYPE}" MATCHES "Debug")
    MESSAGE(STATUS "Building with ${value}")
  ENDIF()
  FOREACH(variable CMAKE_C_FLAGS_RELEASE CMAKE_CXX_FLAGS_RELEASE CMAKE_C_FLAGS_RELWITHDEBINFO CMAKE_CXX_FLAGS_RELWITHDEBINFO CMAKE_C_FLAGS_MINSIZEREL CMAKE_CXX_FLAGS_MINSIZEREL)
    SET(${variable} "${${variable}} ${value}" PARENT_SCOPE)
  ENDFOREACH(variable)
ENDFUNCTION()

FUNCTION(ADD_LINK_FLAG value)
  MESSAGE(STATUS "Linking with ${value}")
  FOREACH(variable CMAKE_EXE_LINKER_FLAGS)
    SET(${variable} "${${variable}} ${value}" PARENT_SCOPE)
  ENDFOREACH(variable)
ENDFUNCTION()

FUNCTION(ADD_SOURCES)
  FOREACH(LIB_SOURCE ${ARGV})
    GET_FILENAME_COMPONENT(LIB_SOURCE_ABSOLUTE ${LIB_SOURCE} ABSOLUTE)
    LIST(APPEND LIB_SOURCES_ABSOLUTE ${LIB_SOURCE_ABSOLUTE})
  ENDFOREACH()
  TARGET_SOURCES(binaryen PRIVATE ${LIB_SOURCES_ABSOLUTE})
ENDFUNCTION()

# Compiler setup.

INCLUDE_DIRECTORIES(${CMAKE_CURRENT_SOURCE_DIR}/src)

# Force output to bin/ and lib/. This is to suppress CMake multigenerator output paths and avoid bin/Debug, bin/Release/ and so on, which is CMake default.
FOREACH(SUFFIX "_DEBUG" "_RELEASE" "_RELWITHDEBINFO" "_MINSIZEREL" "")
  SET(CMAKE_RUNTIME_OUTPUT_DIRECTORY${SUFFIX} "${PROJECT_BINARY_DIR}/bin")
  SET(CMAKE_LIBRARY_OUTPUT_DIRECTORY${SUFFIX} "${PROJECT_BINARY_DIR}/lib")
  SET(CMAKE_ARCHIVE_OUTPUT_DIRECTORY${SUFFIX} "${CMAKE_CURRENT_LIST_DIR}/../../lib")
ENDFOREACH()

IF(MSVC)
  IF(CMAKE_CXX_COMPILER_VERSION VERSION_LESS "19.0") # VS2013 and older explicitly need /arch:sse2 set, VS2015 no longer has that option, but always enabled.
    ADD_COMPILE_FLAG("/arch:sse2")
  ENDIF()
  ADD_COMPILE_FLAG("/wd4146") # Ignore warning "warning C4146: unary minus operator applied to unsigned type, result still unsigned", this pattern is used somewhat commonly in the code.
  # 4267 and 4244 are conversion/truncation warnings. We might want to fix these but they are currently pervasive.
  ADD_COMPILE_FLAG("/wd4267")
  ADD_COMPILE_FLAG("/wd4244")
  # 4722 warns that destructors never return, even with WASM_NORETURN.
  ADD_COMPILE_FLAG("/wd4722")
  ADD_COMPILE_FLAG("/WX-")
  ADD_DEBUG_COMPILE_FLAG("/Od")
  ADD_NONDEBUG_COMPILE_FLAG("/O2")
  ADD_COMPILE_FLAG("/D_CRT_SECURE_NO_WARNINGS")
  ADD_COMPILE_FLAG("/D_SCL_SECURE_NO_WARNINGS")
  # Visual Studio 2018 15.8 implemented conformant support for std::aligned_storage, but the conformant support is only enabled when the following flag is passed, to avoid
  # breaking backwards compatibility with code that relied on the non-conformant behavior (the old nonconformant behavior is not used with Binaryen)
  ADD_COMPILE_FLAG("/D_ENABLE_EXTENDED_ALIGNED_STORAGE")
  # Don't warn about using "strdup" as a reserved name.
  ADD_COMPILE_FLAG("/D_CRT_NONSTDC_NO_DEPRECATE")

  ADD_NONDEBUG_COMPILE_FLAG("/UNDEBUG") # Keep asserts.
  # Also remove /D NDEBUG to avoid MSVC warnings about conflicting defines.
  if( NOT CMAKE_BUILD_TYPE MATCHES "Debug" )
    foreach (flags_var_to_scrub
        CMAKE_CXX_FLAGS_RELEASE
        CMAKE_CXX_FLAGS_RELWITHDEBINFO
        CMAKE_CXX_FLAGS_MINSIZEREL
        CMAKE_C_FLAGS_RELEASE
        CMAKE_C_FLAGS_RELWITHDEBINFO
        CMAKE_C_FLAGS_MINSIZEREL)
      string (REGEX REPLACE "(^| )[/-]D *NDEBUG($| )" " "
        "${flags_var_to_scrub}" "${${flags_var_to_scrub}}")

      # Compile with `/MT` to link against `libcmt.lib`, removing a dependency
      # on `msvcrt.dll`. May result in slightly larger binaries but they should
      # be more portable across systems.
      string(REPLACE "/MD" "/MT" ${flags_var_to_scrub} "${${flags_var_to_scrub}}")
    endforeach()
  endif()

  ADD_LINK_FLAG("/STACK:8388608")

  IF(RUN_STATIC_ANALYZER)
    ADD_DEFINITIONS(/analyze)
  ENDIF()
ELSE()

  OPTION(ENABLE_WERROR "Enable -Werror" ON)

  SET(THREADS_PREFER_PTHREAD_FLAG ON)
  SET(CMAKE_THREAD_PREFER_PTHREAD ON)
  FIND_PACKAGE(Threads REQUIRED)
  ADD_CXX_FLAG("-std=c++11")
  if (NOT EMSCRIPTEN)
    if (CMAKE_SYSTEM_PROCESSOR MATCHES "^i.86$")
      # wasm doesn't allow for x87 floating point math
      ADD_COMPILE_FLAG("-msse2")
      ADD_COMPILE_FLAG("-mfpmath=sse")
    elseif (CMAKE_SYSTEM_PROCESSOR MATCHES "^armv[2-6]" AND NOT CMAKE_CXX_FLAGS MATCHES "-mfpu=")
      ADD_COMPILE_FLAG("-mfpu=vfpv3")
    endif ()
  endif ()
  ADD_COMPILE_FLAG("-Wall")
  if(ENABLE_WERROR)
    ADD_COMPILE_FLAG("-Werror")
  endif()
  ADD_COMPILE_FLAG("-Wextra")
  ADD_COMPILE_FLAG("-Wno-unused-parameter")
  ADD_COMPILE_FLAG("-fno-omit-frame-pointer")
  ADD_COMPILE_FLAG("-Wswitch") # we explicitly expect this in the code
  IF(WIN32)
    ADD_COMPILE_FLAG("-D_GNU_SOURCE")
    ADD_LINK_FLAG("-Wl,--stack,8388608")
  ELSE()
    ADD_COMPILE_FLAG("-fPIC")
  ENDIF()
  ADD_DEBUG_COMPILE_FLAG("-O0")
  ADD_DEBUG_COMPILE_FLAG("-g3")
  ADD_NONDEBUG_COMPILE_FLAG("-O2")
  ADD_NONDEBUG_COMPILE_FLAG("-UNDEBUG") # Keep asserts.
ENDIF()

# clang doesn't print colored diagnostics when invoked from Ninja
IF (UNIX AND
    CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND
    CMAKE_GENERATOR STREQUAL "Ninja")
  ADD_COMPILE_FLAG("-fcolor-diagnostics")
ENDIF()

IF(BUILD_STATIC_LIB)
  ADD_LIBRARY(binaryen STATIC)
ELSE()
  ADD_LIBRARY(binaryen SHARED)
ENDIF()

# Static libraries
# Current (partial) dependency structure is as follows:
# passes -> wasm -> asmjs -> support
# TODO: It's odd that wasm should depend on asmjs, maybe we should fix that.
ADD_SUBDIRECTORY(src/ir)
ADD_SUBDIRECTORY(src/asmjs)
ADD_SUBDIRECTORY(src/cfg)
ADD_SUBDIRECTORY(src/emscripten-optimizer)
ADD_SUBDIRECTORY(src/passes)
ADD_SUBDIRECTORY(src/support)
ADD_SUBDIRECTORY(src/wasm)

# Sources.


SET(binaryen_SOURCES
  src/binaryen-c.cpp
)
ADD_SOURCES(${binaryen_SOURCES})

#TARGET_LINK_LIBRARIES(binaryen PRIVATE ${CMAKE_THREAD_LIBS_INIT})
ADD_DEPENDENCIES(binaryen GenerateWasmIntrinsics)

SET_SOURCE_FILES_PROPERTIES(
  ${CMAKE_CURRENT_BINARY_DIR}/src/passes/WasmIntrinsics.cpp PROPERTIES GENERATED TRUE)

FILE(INSTALL src/binaryen-c.h src/compiler-support.h
     DESTINATION ${CMAKE_CURRENT_SOURCE_DIR}/../../include)
