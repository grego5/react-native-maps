# Validation lab

- Put standalone C++ tests in `test/` and use `run-cpp-tests.ps1` to build and run them. The runner writes binaries to `build/cpp-tests/`.
- `android-check/` is a standalone Gradle harness for library compilation. Use the example app for runtime checks.
- Put local validation outputs in `build/`. Keep generated binaries, emulator images, Gradle caches, and credentials out of source control.
- Document repeatable checks in the [validation guide](../docs/validation.md).
