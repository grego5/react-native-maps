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

Start Metro separately with `npm run start` or `npm run starte` (LAN), both on port 8088. Use `npm run android:emulator` for an x86_64 emulator, or `npm run android:release` to assemble an ARM64 release APK. The debug commands install to a matching online device when available. Pass `-- -Device SERIAL` to select a device. With the map open, `npm run android:lifecycle` checks that the process survives backgrounding and resuming. Verify the map still responds on the device.

[`lab/android-check/`](../lab/android-check/) is an optional Gradle harness that includes the library and Nitro dependency directly. It checks library compilation without installing or launching the example. It depends on the local Android toolchain and the root React Native Gradle plugin dependency.

The camera math has JVM unit tests in `android/src/test/`. Run them through the example project after refreshing the installed package:

```sh
cd example && npm ci --install-links
cd android && ./gradlew :react-native-maps:testDebugUnitTest
```

The `lab/android-check` harness does not run them: its Android Gradle plugin needs Gradle 9.5, and its React Native codegen task looks for `@react-native/codegen` under `lab/`. The Swift camera math has no test target. It is dependency free and mirrors the Kotlin formulas.

## iOS

On a Mac, install the example dependencies and run `npm run ios` from `example/` for MapKit. For a Google-enabled build, set `GOOGLE_MAPS_IOS_API_KEY` before Expo prebuild and CocoaPods installation. Rebuild the app after changing the native provider configuration. The Google-enabled app starts on Google Maps and exposes a provider switch. Set `EXPO_PUBLIC_PROVIDER=apple` when bundling to start with MapKit instead.

## Runtime checks

For a change that affects the surface or interaction, check the relevant provider for readiness and rendering, marker and route taps, projection and snapshots, and detach and reattach. For gesture changes, also check normal panning, route and standalone pin drag, interruption by camera movement or another finger, and a normal tap immediately after cancellation.

Open **Test controls** for Surface, Options, Camera, Markers, Routes, Hits, and Events. Work through this checklist per provider. G-A is Google Maps on Android, G-i is Google Maps on iOS, and MK is MapKit.

**Options**
- [ ] Hide POIs removes POI labels and Show POIs restores them (G-A, G-i; MapKit ignores `mapStyle`).
- [ ] No base map hides the map tiles and keeps markers and routes (G-A, G-i).
- [ ] Lock pan, Lock zoom, and Lock tilt block their gestures, and unlocking restores them (all). On iOS, changing a lock during a drag applies after release.
- [ ] Hide buildings and Hide indoors change the map (buildings: all; indoors: G-A, G-i).

**Camera**
- [ ] The map opens fitted to the route above the bottom 200 points, with no jump, before `onReady` (all).
- [ ] Each pan or animation reports one `start` and one `idle` in the Events section (all).
- [ ] Run camera checks passes: fit equals `cameraFor`, padded `setCamera`, every reveal outcome, and an empty fit rejects without moving (all).
- [ ] Slow move takes about 1000 ms from `start` to `idle` (G-A, G-i; MapKit unverified).
- [ ] Run ref checks passes, including `getCamera` after `setCamera` and a snapshot (all).

**Markers**
- [ ] Show stack: A draws above B, B above the third marker, and the dot or pin marked Centered sits centered on its coordinate at several zooms (all).
- [ ] Tapping A opens its callout with its description, and the camera stays still (all).
- [ ] Callout on B moves the callout to B, Hide callout closes it and reports that a missing ID rejected, and Remove B closes B's open callout (all).
- [ ] The `require()` pin renders at the same size as its scale implies in debug and release builds (all).

**Routes**
- [ ] The green connector draws 8-point dashes with 6-point gaps, and the toggle switches it between solid and dashed in place (all; G-i rescales on idle).
- [ ] Long-pressing the orange route draws red dashed connectors and the bundled pin at the lifted point; a pin drag draws the pin preview (all).
- [ ] A drag on the shared orange and purple line reports both route IDs on every phase, and a drop near markers lists them on `end` only (all).
- [ ] Camera movement, a second finger, and detach cancel a drag, and a tap right after works normally (all).

**Hits and events**
- [ ] Query at start returns the start marker first and the routes through it; Query last tap reports the features at the last tap (all).
- [ ] Tapping a restaurant or other POI fills `onPoiTap` and leaves `onTap` unchanged; Google reports a place ID (all; MapKit place IDs need iOS 18).
- [ ] Detach map and Attach map restore readiness, features, and events (all).

Coverage for the route planner parity work (tasks 02 to 12): Android device checks ran for split feature props (task 02), options (task 03), and camera state and events (task 04) on a Samsung SM-G998U. Every later checklist item is not run on any provider: no Android device was available and no Mac was available for iOS. The camera math has JVM unit tests, and the same cases passed for the Swift math compiled on Windows.

Before the repository move, Android emulator checks covered SDK and image preparation, readiness and rendering, marker display and taps, route taps, projection, snapshots, reattachment, and drag and cancellation behavior. Both iOS example configurations built for the simulator. MapKit simulator checks covered readiness, projection, route and pin drags, and a normal tap after dragging. MapKit panning and complete rendering, and Google Maps iOS gestures, still need runtime verification. The MapKit simulator camera also stayed stationary during swipes in an SDK-only control.
