#include <fbjni/fbjni.h>
#include "ReactNativeMapsOnLoad.hpp"

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  return facebook::jni::initialize(vm, [] {
    margelo::nitro::mapssession::registerAllNatives();
  });
}
