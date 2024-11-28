cmake_minimum_required(VERSION 3.20.0)
project(flint)
set(CMAKE_CXX_STANDARD 20)

find_package(LLVM REQUIRED CONFIG)

message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

execute_process(COMMAND llvm-config-19 --includedir OUTPUT_VARIABLE LLVM_INCLUDE_DIR OUTPUT_STRIP_TRAILING_WHITESPACE)

# Add the include directory to your project
include_directories(${LLVM_INCLUDE_DIR})
separate_arguments(LLVM_DEFINITIONS_LIST NATIVE_COMMAND ${LLVM_DEFINITIONS})
add_definitions(${LLVM_DEFINITIONS_LIST})

# Now build our tools
add_executable(flint src/Main.cpp)

# Find the libraries that correspond to the LLVM components
# that we wish to use
llvm_map_components_to_libnames(llvm_libs support core irreader orcjit native)

# Link against LLVM libraries
target_link_libraries(flint ${llvm_libs} ${LLVM_SYSTEM_LIBS})