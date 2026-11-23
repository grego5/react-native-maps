cmake_minimum_required(VERSION 3.22.1)
project(ReactNativeMaps LANGUAGES CXX)

add_library(ReactNativeMaps SHARED src/main/cpp/OnLoad.cpp)
target_compile_features(ReactNativeMaps PRIVATE cxx_std_20)
include(../nitrogen/generated/android/ReactNativeMaps+autolinking.cmake)
