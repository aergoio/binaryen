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

# Compiler setup.

INCLUDE_DIRECTORIES(${CMAKE_CURRENT_SOURCE_DIR}/src)

# Force output to bin/ and lib/. This is to suppress CMake multigenerator output paths and avoid bin/Debug, bin/Release/ and so on, which is CMake default.
FOREACH(SUFFIX "_DEBUG" "_RELEASE" "_RELWITHDEBINFO" "_MINSIZEREL" "")
  SET(CMAKE_RUNTIME_OUTPUT_DIRECTORY${SUFFIX} "${PROJECT_BINARY_DIR}/bin")
  SET(CMAKE_LIBRARY_OUTPUT_DIRECTORY${SUFFIX} "${PROJECT_BINARY_DIR}/lib")
  SET(CMAKE_ARCHIVE_OUTPUT_DIRECTORY${SUFFIX} "${PROJECT_BINARY_DIR}/lib")
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

# Static libraries
# Current (partial) dependency structure is as follows:
# passes -> wasm -> asmjs -> support
# TODO: It's odd that wasm should depend on asmjs, maybe we should fix that.
#ADD_SUBDIRECTORY(src/ir)
#ADD_SUBDIRECTORY(src/asmjs)
#ADD_SUBDIRECTORY(src/cfg)
#ADD_SUBDIRECTORY(src/emscripten-optimizer)
#ADD_SUBDIRECTORY(src/passes)
#ADD_SUBDIRECTORY(src/support)
#ADD_SUBDIRECTORY(src/wasm)

# Sources.


SET(binaryen_SOURCES
  src/binaryen-c.cpp
  src/passes/pass.cpp
  src/passes/CoalesceLocals.cpp
  src/passes/CodePushing.cpp
  src/passes/CodeFolding.cpp
  src/passes/ConstHoisting.cpp
  src/passes/DataFlowOpts.cpp
  src/passes/DeadArgumentElimination.cpp
  src/passes/DeadCodeElimination.cpp
  src/passes/DuplicateFunctionElimination.cpp
  src/passes/ExtractFunction.cpp
  src/passes/Flatten.cpp
  src/passes/FuncCastEmulation.cpp
  src/passes/I64ToI32Lowering.cpp
  src/passes/Inlining.cpp
  src/passes/InstrumentLocals.cpp
  src/passes/InstrumentMemory.cpp
  src/passes/LegalizeJSInterface.cpp
  src/passes/LocalCSE.cpp
  src/passes/LogExecution.cpp
  src/passes/LoopInvariantCodeMotion.cpp
  src/passes/MemoryPacking.cpp
  src/passes/MergeBlocks.cpp
  src/passes/MergeLocals.cpp
  src/passes/Metrics.cpp
  src/passes/NameList.cpp
  src/passes/OptimizeInstructions.cpp
  src/passes/PickLoadSigns.cpp
  src/passes/PostEmscripten.cpp
  src/passes/Precompute.cpp
  src/passes/Print.cpp
  src/passes/PrintCallGraph.cpp
  src/passes/StackIR.cpp
  src/passes/RedundantSetElimination.cpp
  src/passes/RelooperJumpThreading.cpp
  src/passes/ReReloop.cpp
  src/passes/RemoveImports.cpp
  src/passes/RemoveMemory.cpp
  src/passes/RemoveNonJSOps.cpp
  src/passes/RemoveUnusedBrs.cpp
  src/passes/RemoveUnusedNames.cpp
  src/passes/RemoveUnusedModuleElements.cpp
  src/passes/ReorderLocals.cpp
  src/passes/ReorderFunctions.cpp
  src/passes/TrapMode.cpp
  src/passes/SafeHeap.cpp
  src/passes/SimplifyLocals.cpp
  src/passes/Souperify.cpp
  src/passes/SpillPointers.cpp
  src/passes/SSAify.cpp
  src/passes/Untee.cpp
  src/passes/Vacuum.cpp
  src/passes/WasmIntrinsics.cpp
  src/wasm/literal.cpp
  src/wasm/wasm.cpp
  src/wasm/wasm-binary.cpp
  src/wasm/wasm-emscripten.cpp
  src/wasm/wasm-interpreter.cpp
  src/wasm/wasm-io.cpp
  src/wasm/wasm-s-parser.cpp
  src/wasm/wasm-type.cpp
  src/wasm/wasm-validator.cpp
  src/asmjs/asm_v_wasm.cpp
  src/asmjs/asmangle.cpp
  src/asmjs/shared-constants.cpp
  src/emscripten-optimizer/optimizer-shared.cpp
  src/emscripten-optimizer/parser.cpp
  src/emscripten-optimizer/simple_ast.cpp
  src/ir/ExpressionAnalyzer.cpp
  src/ir/ExpressionManipulator.cpp
  src/ir/LocalGraph.cpp
  src/cfg/Relooper.cpp
  src/support/archive.cpp
  src/support/bits.cpp
  src/support/colors.cpp
  src/support/file.cpp
  src/support/safe_integer.cpp
  src/support/threads.cpp
)
ADD_LIBRARY(binaryen STATIC ${binaryen_SOURCES})
TARGET_LINK_LIBRARIES(binaryen ${CMAKE_THREAD_LIBS_INIT})

add_custom_command(
  OUTPUT ${PROJECT_SOURCE_DIR}/src/passes/WasmIntrinsics.cpp
  COMMAND python ${PROJECT_SOURCE_DIR}/scripts/embedwast.py ${PROJECT_SOURCE_DIR}/src/passes/wasm-intrinsics.wast ${PROJECT_SOURCE_DIR}/src/passes/WasmIntrinsics.cpp
  DEPENDS ${PROJECT_SOURCE_DIR}/scripts/embedwast.py ${PROJECT_SOURCE_DIR}/src/passes/wasm-intrinsics.wast)
add_custom_target(intrinsic-gen DEPENDS ${PROJECT_SOURCE_DIR}/src/passes/WasmIntrinsics.cpp)
add_dependencies(binaryen intrinsic-gen)

SET_TARGET_PROPERTIES(binaryen PROPERTIES 
  ARCHIVE_OUTPUT_DIRECTORY_RELEASE ${CMAKE_CURRENT_SOURCE_DIR}/../../lib
  ARCHIVE_OUTPUT_DIRECTORY_DEBUG ${CMAKE_CURRENT_SOURCE_DIR}/../../lib
)

CONFIGURE_FILE(${CMAKE_CURRENT_SOURCE_DIR}/src/binaryen-c.h ${CMAKE_CURRENT_SOURCE_DIR}/../../include COPYONLY)
CONFIGURE_FILE(${CMAKE_CURRENT_SOURCE_DIR}/src/compiler-support.h ${CMAKE_CURRENT_SOURCE_DIR}/../../include COPYONLY)
