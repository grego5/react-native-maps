# 02 Split marker and route props

[Back to TASKS.md](../TASKS.md)

Status: Completed (iOS builds and simulator checks not run: no Mac)

## Objective

Make a marker update cost nothing for routes, and the reverse:

- Replace the native `features: MapFeatures` prop with two native props, `markers: MapMarker[]` and `routes: MapRoute[]`.
- Each platform reconciles only the collection whose prop changed.
- The JS wrapper keeps each prop's identity stable while its input array is stable, and keeps event callback wrappers stable while the app's handlers are stable.

## Why

`react-native-nitro-modules/cpp/views/ReactProp.hpp` caches each converted prop against its JS value with `strictEquals`, and converts again only when the identity changes. `src/index.tsx` currently builds a new `{ markers, routes }` object whenever either array changes. Every marker update therefore converts every route coordinate into native structs and reapplies routes.

The planner's routes hold thousands of decoded points, and its markers change on every selection.

The wrapper also calls `callback(onTap)` and the other event wrappers on every render. That gives the host a new function prop each render even when the handler is unchanged.

## Non-goals

- Passing encoded polylines to native code. Revisit only if step 6 shows route conversion is still costly after the split.
- Changing reconciliation by ID inside each collection.

## Read before editing

- `src/MapSurface.nitro.ts`: `MapFeatures` and `MapSurfaceProps`.
- `src/index.tsx`: `MapSurface` and `validateFeatures`.
- `nitrogen/generated/shared/c++/views/HybridMapSurfaceComponent.cpp`: how each prop is converted. Generated, read only.
- `android/.../HybridMapSurface.kt`:
  - `features`, `featuresDirty`, `hasFeatures`;
  - `applyFeatures()`, `clearFeatures()`, `releaseMap()`, `onDropView()`.
- `ios/HybridMapSurface.swift`: `features`, `featuresDirty`, `hasFeatures`, `updatePresentation()`, `drop()`.
- `ios/MapPresenter.swift`: `apply(_ features:)`.
- `ios/AppleMapPresenter.swift`: `apply`, `applyMarkers`, `applyRoutes`.
- `ios/GoogleMapPresenter.swift`: `apply`.
- `ios/MapDragGesture.swift`: `updateRoutes`.
- `example/App.tsx`.

## Current behavior to preserve

- `onReady` waits until the first features apply (`hasFeatures`). Readiness now waits for both collections' first apply. Omitted props count as applied empty arrays.
- Route order, marker icons, drag cancellation when the dragged route's anchors change, and release clearing are unchanged.

## Steps

1. Spec:
   - Delete `MapFeatures`.
   - Add `markers: MapMarker[]` and `routes: MapRoute[]` to the native `MapSurfaceProps`.
   - Run `npm run nitrogen`.
2. `src/index.tsx`:
   - Two `useMemo`s:
     - `const nativeMarkers = useMemo(() => validateMarkers(markers ?? EMPTY_MARKERS), [markers])`;
     - the same for routes, with module-level frozen empty arrays so an omitted prop stays one identity.
   - Split `validateFeatures` into `validateMarkers` and `validateRoutes`, each returning its input.
   - For each event prop, `useMemo(() => handler && callback(handler), [handler])`. Document in `docs/api.md` that apps should keep handlers and arrays stable, with `useCallback` and memoized arrays, to avoid native work.
3. Android:
   - Replace `features` with `override var markers` and `override var routes`, each setting its own dirty flag.
   - Split `applyFeatures()` into `applyMarkers(liveMap)` and `applyRoutes(liveMap)`. Each returns early unless its flag is set, and `drag.updateRoutes` is called only from `applyRoutes`.
   - Track `markersApplied` and `routesApplied`. `signalReady()` requires both.
   - `releaseMap()` sets both dirty flags and clears both applied flags.
   - `onDropView()` empties both arrays.
4. iOS:
   - `HybridMapSurface`: `markers` and `routes` with separate `didSet` dirty flags.
   - In `MapPresenter`, replace `apply(_ features:)` with `applyMarkers(_:)` and `applyRoutes(_:)`. The MapKit presenter already has both privately; make them the protocol methods. Split the Google presenter's `apply` at the route loop.
   - `updatePresentation()` applies each dirty collection, calling `drag.updateRoutes` only with routes. `hasFeatures` becomes `markersApplied && routesApplied`.
   - `releasePresenter()` and `drop()` reset them as on Android.
5. Update `example/App.tsx` to keep its route array memoized while marker props change, so the example exercises the split.
6. Measure the change on the Android example with a route of 5,000 points and a button that changes one marker's coordinate 20 times:
   - add temporary `android.os.Trace` sections or `SystemClock.elapsedRealtimeNanos` logs around `applyRoutes` and around prop conversion;
   - confirm route application no longer runs for marker-only updates;
   - record the before and after numbers in the task report;
   - remove the instrumentation before completion.
7. Docs: update the `docs/api.md` map surface section for the two props and the stability advice, and `docs/architecture.md` for per-collection reconciliation.

## Rules

- No combined features struct remains in the spec or native code.
- Native code never compares array contents to detect a change. Nitro's identity cache decides what changed.

## Tests

- Example on each provider:
  - changing a marker leaves routes untouched (instrumented check in step 6 on Android, and a temporary `os_signpost` or log on iOS);
  - changing a route leaves marker icons untouched, with no icon flicker;
  - `onReady` still fires with no markers and no routes passed;
  - detach and reattach redraws both collections.

## Validation

- `npm run nitrogen` stable. `npm run typecheck` in the package and in `example/` after `npm ci --install-links`.
- Android build and device checks, with the step 6 numbers reported.
- iOS builds and simulator checks on a Mac, or report not run.

## Completion criteria

- Marker-only updates do no route work on any provider.
- Event wrappers and empty arrays are identity-stable.
- The docs are updated.

## Commit

`perf: send markers and routes as separate props`

## Report

Measured on an Android device (SM-G998U) with a 5,000-point route plus the example routes, 20 updates at 250 ms intervals. Timing ran from the first prop setter to the end of `afterUpdate` on the UI thread. It includes the JNI conversion of changed props and reconciliation, but not JS validation or Fabric's C++ prop parsing.

| Update | Median | Min | Max | `applyRoutes` runs |
| --- | --- | --- | --- | --- |
| Marker only (after the split) | 2.2 ms | 1.8 ms | 3.0 ms | 0 of 20 |
| Marker plus same routes re-sent (the old behavior of every marker update) | 21.4 ms | 11.9 ms | 34.3 ms | 20 of 20 |

`markersApplied` and `routesApplied` were merged into one `hasFeatures` flag on both platforms, because both collections always apply in the same pass.
