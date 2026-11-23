# Validation

## Bindings and TypeScript

From the package root:

```sh
npm ci
npm run nitrogen
npm run typecheck
```

Install or refresh the local package from `example/` after regenerating bindings or changing library source:

```sh
npm ci --install-links
npm run typecheck
```

## Standalone geometry tests

On Windows, with PowerShell 7 and Clang on PATH, run from the package root:

```powershell
pwsh -File lab/run-cpp-tests.ps1
```

The runner compiles and runs the sources in [`lab/test/`](../lab/test/). It writes executables to `lab/build/cpp-tests/`.

## Android

With the example dependencies installed, set `GOOGLE_MAPS_ANDROID_API_KEY` in the build environment and run `npm run android` from `example/`. The example exercises marker prop updates, surface detach and reattach, projection, and snapshots.

[`lab/android-check/`](../lab/android-check/) is an optional Gradle harness that includes the library and Nitro dependency directly. It checks library compilation without installing or launching the example. It depends on the local Android toolchain and the root React Native Gradle plugin dependency.

## iOS

On a Mac, install the example dependencies and run `npm run ios` from `example/` for MapKit. For a Google-enabled build, set `GOOGLE_MAPS_IOS_API_KEY` before Expo prebuild and CocoaPods installation. Rebuild the app after changing the native provider configuration. The Google-enabled app exposes a provider switch.

## Runtime checks

For a change that affects the surface or interaction, check the relevant provider for readiness and rendering, marker and route taps, projection and snapshots, and detach and reattach. For gesture changes, also check normal panning, route and standalone pin drag, interruption by camera movement or another finger, and a normal tap immediately after cancellation.

Before the repository move, Android emulator checks covered SDK and image preparation, readiness and rendering, marker display and taps, route taps, projection, snapshots, reattachment, and drag and cancellation behavior. Both iOS example configurations built for the simulator. MapKit simulator checks covered readiness, projection, route and pin drags, and a normal tap after dragging. MapKit panning and complete rendering, and Google Maps iOS gestures, still need runtime verification. The MapKit simulator camera also stayed stationary during swipes in an SDK-only control.
