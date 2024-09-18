cmake_minimum_required(VERSION 3.29)
project(flint)

set(CMAKE_CXX_STANDARD 23)

include_directories(include)

# TEMPORARY
# static linking flags, so just the .exe is required to run
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static-libgcc -static-libstdc++ -static")

add_executable(flint src/Flint.cpp
        src/Token.cpp
        include/Token.h
        src/Scanner.cpp
        include/Scanner.h
        include/Flint.h)
