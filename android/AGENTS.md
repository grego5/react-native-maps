# Android

- Production Kotlin and Java live under `src/main/java/com/margelo/nitro/mapssession/`. `src/main/cpp/OnLoad.cpp` registers the generated bindings.
- Keep Google Maps and view mutations on the Android UI thread. Reconcile SDK handles per surface by feature ID. Remove old listeners and invalidate callbacks when the surface is released.
- Keep tap and drag arbitration in `SurfaceDrag.kt`. Preserve ordinary Google Maps gestures when the coordinator does not claim a drag. Check camera movement, a second pointer, cancellation, and the next ordinary tap when changing gesture behavior.
- Use the [Android example](../docs/validation.md#android) to validate integration. The optional Gradle harness under `lab/` can check library compilation.
