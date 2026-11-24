# 05 Camera fit, padding, and reveal

[Back to TASKS.md](../TASKS.md)

Status: Completed (device checks skipped at the user's request. iOS builds and simulator checks not run: no Mac. MapKit duration unverified.)

## Objective

Move the planner's camera math into the surface. The native view knows its size, camera, and projection, so the app no longer needs `getCamera()` and `project()` round trips or its own Web Mercator code.

New types:

- `EdgePadding { top; right; bottom; left }`, in display points.
- `CameraMove { duration?: number; padding?: EdgePadding }`:
  - `duration` is in milliseconds, and 0 or omitted moves at once;
  - `padding` defines the area the camera centers in.
- `CameraFit { padding?: EdgePadding; maxZoom?: number; duration?: number }`.
- `CameraReveal = 'none' | 'pan' | 'fit'`.

Methods (`MapSurfaceMethods`):

| Method | Replaces in the planner | Behavior |
| --- | --- | --- |
| `setCamera(center, zoom, move?: CameraMove)` | `setCamera`, `animateCamera`, `getCenterAbove`, `getPaddedCenter` | Places `center` at the middle of the padded area at `zoom`. Replaces the `animated` boolean. |
| `fitCoordinates(coordinates, fit?: CameraFit)` | `fitToCoordinates`, `getFittedCamera` | The closest zoom, at most `maxZoom`, that shows every coordinate inside the padded area, centered there. |
| `revealCoordinates(coordinates, fit?: CameraFit): Promise<CameraReveal>` | `getViewAdjustment` plus the pan or fit it triggers | `'none'` if all are already inside the padded area. Otherwise `'pan'` (the smallest pan that brings them inside, zoom kept) if they fit at the current zoom, and `'fit'` (as `fitCoordinates`) if not. |
| `cameraFor(coordinates, fit?: CameraFit): Promise<MapCamera>` | `getFittedCamera` used to compare zoom targets | The camera `fitCoordinates` would move to, without moving. |

Prop `initialFit?: { coordinates: Coordinate[]; padding?: EdgePadding; maxZoom?: number }` replaces the planner's pre-layout `getFittedCamera` opening camera. The surface applies it on the first non-empty layout, before `onReady`. If both `initialFit` and `initialCamera` (task 04) are set, `initialFit` wins.

## Non-goals

- Persistent map padding, which would shift SDK controls and later camera operations.
- Rotated or tilted cameras. Every camera this task sets is north-up and flat, which the planner requires and which `setCamera` already does on Google iOS.
- An animation completion callback. Wait for `onCameraMove` `idle` (task 04).
- Zoom-target selection (overview, leg, marker). That is planner logic.

## Read before editing

- `src/MapSurface.nitro.ts` and `src/index.tsx`.
- Planner reference (read only): `C:\dev\rikum-systems\agent\components\RoutePlanner\Map\route-map-display.ts`, the functions `getBounds`, `getFittedCamera`, `getCenterAbove`, `getPaddedCenter`, and `getViewAdjustment`. The native math must reproduce them, including antimeridian-aware bounds.
- `android/.../HybridMapSurface.kt`: `setCamera`, `withMap`, `ensureMap()`, `SurfaceHost`.
- `android/build.gradle`: it has no unit-test setup yet.
- `ios/HybridMapSurface.swift`: `setCamera`, `withPresenter`, `Host.layoutChanged`, `signalReady()`.
- `ios/MapPresenter.swift`: `setCamera`, and `camera` from task 04.
- `ios/AppleMapPresenter.swift`: `setCamera` (the zoom-to-map-rect formula).
- `ios/GoogleMapPresenter.swift`: `setCamera`.
- `example/App.tsx`: existing `setCamera` calls.

## Current behavior to preserve

- Camera operations cancel an active drag first.
- Zoom uses Google zoom levels on every provider (task 04).
- Methods reject before `onReady`.

## Steps

1. Spec:
   - Add the types, the four methods, and `initialFit`.
   - Change `setCamera` to `setCamera(center, zoom, move?)`.
   - Run `npm run nitrogen`.
   - Update `example/App.tsx` calls: `true` becomes `{ duration: 300 }`, and `false` drops the argument.
2. Camera math, one small pure module per platform with identical formulas: `android/.../CameraMath.kt` and `ios/CameraMath.swift`. Inputs are display points, Google zoom levels, and 256-point tiles.
   - `bounds(coordinates)`: north, south, east, west. East and west are unwrapped around the first point, as the planner's `getBounds` does.
   - `fit(bounds, viewSize, padding, maxZoom) -> (center, zoom)`:
     - zoom = min(maxZoom ?? ∞, log2(innerWidth × 360 / (256 × lngSpan)), log2(innerHeight × 2π / (256 × mercatorSpan))), where inner sizes subtract the padding;
     - a single point or zero span uses the current zoom capped by `maxZoom`;
     - the bounds' Mercator center is shifted by ((left − right) / 2, (top − bottom) / 2) points at that zoom, so it lands at the middle of the padded area.
   - `paddedCenter(center, zoom, padding) -> center`: the same shift for `setCamera`.
   - `reveal(points in screen space, viewSize, padding) -> none | pan(dx, dy) | fit`: the same rule as the planner's `getViewAdjustment`. The surface feeds it the live projection of each coordinate, so it needs no Mercator math.
   - Non-finite or negative padding, a negative duration, a non-finite `maxZoom`, an empty coordinate list, or invalid coordinates reject with an argument error. Android uses `IllegalArgumentException`, and iOS uses a new `MapSurfaceError.invalidArgument`.
3. A single move primitive per presenter: `moveCamera(center, zoom, duration)`. Every method above computes a target and calls it.
   - Android:
     - `duration > 0` uses `animateCamera(newCameraPosition(CameraPosition(target, zoom, 0, 0)), duration, null)`;
     - otherwise `moveCamera`.
   - Google iOS:
     - `duration > 0` wraps `map.animate(to: GMSCameraPosition(...))` in `CATransaction.begin()`, `setAnimationDuration(duration / 1000)`, and `commit()`;
     - otherwise it sets `map.camera`.
   - MapKit: the existing zoom-to-`MKMapRect` conversion.
     - `duration > 0` calls `setVisibleMapRect(animated: false)` inside `UIView.animate(withDuration:)`. Verify on the simulator that MapKit follows the duration. If it ignores it, use `animated: true` and document that MapKit uses its own duration.
     - Otherwise call `setVisibleMapRect(animated: false)`.
4. Surface methods (Android `HybridMapSurface.kt`, iOS `HybridMapSurface.swift`), each on the UI or main thread through `withMap` or `withPresenter`:
   - `setCamera`: cancel the drag, then call `moveCamera(paddedCenter(...), zoom, duration)`.
   - `fitCoordinates` and `cameraFor`: compute `fit` with the view size in points and the current zoom. `fitCoordinates` cancels the drag and moves.
   - `revealCoordinates`: project the coordinates with the live projection.
     - On `pan`, unproject the view center shifted by (dx, dy) and move there at the current zoom.
     - On `fit`, behave as `fitCoordinates`.
     - Resolve with the outcome. `none` does not move and does not cancel a drag.
5. `initialFit`:
   - Android: in `SurfaceHost.onLayout`, or the `getMapAsync` callback if layout came first, call `moveCamera` with the fit once the host has a non-zero size and the map exists.
   - iOS: from `layoutChanged`, through a presenter call, once bounds are non-empty.
   - `signalReady()` waits until a pending `initialFit` or `initialCamera` has been applied. Clear the pending state on release so a reattached surface applies it again.
6. Tests for the math:
   - Add JUnit to `android/build.gradle` (`testImplementation 'junit:junit:4.13.2'`) and `android/src/test/.../CameraMathTest.kt`. Cover:
     - a fit of two points in a 400×800 view with padding {40, 20, 200, 20} matches values computed with the planner's `getFittedCamera` plus `getPaddedCenter` (paste the expected numbers into the test, computed once with Node);
     - `maxZoom` caps the zoom;
     - bounds across the antimeridian (170 and −170) give a 20° span, not 340°;
     - every reveal case: none, pan in each direction, and fit.
   - Run with the `lab/android-check` harness (`gradlew test`), and document the command in `docs/validation.md`.
   - Swift has no test target. Check the same cases in the example on a Mac by comparing `cameraFor` results with the Android values, to 1e-6 degrees and 0.001 zoom.
7. Docs: update `docs/api.md` with the camera section (types, methods, `initialFit`, and the north-up note) and the MapKit duration note if step 3 needed it.

## Rules

- No persistent SDK padding. Padding exists only inside the math.
- Use one formula set per platform, mirrored, with no provider-specific fit APIs. All three providers then land on the same camera for the same input.
- Main or UI thread only for SDK calls. The math is pure and needs no thread.

## Tests

- JUnit `CameraMathTest` passes.
- Example "Camera" controls on each provider:
  - fit all markers with padding {40, 20, 200, 20} and `maxZoom` 15: every marker is above the bottom 200 points, and a following `getCamera()` equals `cameraFor` for the same input;
  - `setCamera(c, 14, { padding: { top: 0, bottom: 300, left: 0, right: 0 } })` puts `c` at the vertical middle of the top area (`project(c).y ≈ (height − 300) / 2`, within 1 point);
  - `revealCoordinates` returns `none` for an onscreen marker, `pan` for one just outside the padding (the camera zoom is unchanged), and `fit` for a far-apart pair;
  - `initialFit` shows the fitted camera on the first frame, and `onReady` follows;
  - `setCamera(c, z, { duration: 1000 })` takes about one second on Android and Google iOS;
  - an empty coordinate list rejects, and the camera does not move.

## Validation

- `npm run nitrogen` stable. `npm run typecheck` in the package and the example.
- `gradlew test` in `lab/android-check`.
- Android example build and device checks. iOS builds and simulator checks for both providers on a Mac, or report not run.

## Completion criteria

- The four methods and `initialFit` work on all three providers with matching results, and `animated` is gone.
- The camera math is unit-tested on Android.
- The docs are updated.

## Commit

`feat: fit, pad and reveal the camera natively`
