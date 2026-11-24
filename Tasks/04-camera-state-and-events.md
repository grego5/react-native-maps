# 04 Camera state and events

[Back to TASKS.md](../TASKS.md)

Status: Completed (iOS builds and simulator checks not run: no Mac. A pan during a pin drag was not tested on the device: it needs two fingers.)

## Objective

Let the app read the camera, start the map at a known camera, and react to camera movement:

- `MapCamera { center: Coordinate; zoom: number }`.
- Prop `initialCamera?: MapCamera`: the camera the map shows before `onReady`.
- Method `getCamera(): Promise<MapCamera>`.
- Prop `onCameraMove?: (event: MapCameraEvent) => void`, where `MapCameraEvent { phase: 'start' | 'idle'; camera: MapCamera }`.

The planner uses these for `initialCamera`, `getCamera()`, `onRegionChangeStart`, and `onRegionChangeComplete`.

## Non-goals

- Bearing, tilt, or altitude in `MapCamera`. The planner keeps the map north-up and flat.
- Continuous per-frame camera events.
- Fit and animation duration (task 05).

## Read before editing

- `src/MapSurface.nitro.ts` and `src/index.tsx`.
- `android/.../HybridMapSurface.kt`:
  - `ensureMap()`, where `MapView(context)` is created and the camera listeners are registered;
  - `setCamera`, `withMap`, `requireLiveMap`, and `releaseMap()`.
- `ios/HybridMapSurface.swift`: `updatePresentation()`, `withPresenter`, and `setCamera`.
- `ios/MapPresenter.swift`: `onCameraMoving` and `setCamera`.
- `ios/AppleMapPresenter.swift`: `setCamera` (its zoom formula) and the `regionWillChange` and `regionDidChange` delegates.
- `ios/GoogleMapPresenter.swift`: `willMove`, `idleAt`, and `setCamera`.
- `ios/MapDragGesture.swift`: `cameraDidMove` and the `onCameraMoving` assignment.

## Current behavior to preserve

- Camera movement cancels an active drag:
  - Android: `SurfaceDrag.cameraMoving`;
  - iOS: `MapDragGesture` owns `presenter.onCameraMoving`.
- Zoom uses Google zoom levels on all providers. MapKit's `setCamera` converts with 256-point tiles: `visibleWidth = worldWidth * boundsWidth / (256 * 2^zoom)`.

## Steps

1. Spec:
   - Add `MapCamera`, `MapCameraPhase`, and `MapCameraEvent`.
   - Add `initialCamera?: MapCamera` and `onCameraMove?: (event: MapCameraEvent) => void` to the native props.
   - Add `getCamera(): Promise<MapCamera>` to `MapSurfaceMethods`.
   - Mirror them in `src/index.tsx`, wrapping `onCameraMove` with `callback()` like the other events.
   - Validate `initialCamera` with `validateCoordinate`, and check that its zoom is finite.
   - Run `npm run nitrogen`.
2. Android:
   - `ensureMap()`:
     - Create `MapView(context, GoogleMapOptions().camera(CameraPosition.fromLatLngZoom(...)))` when `initialCamera` is set. Read it at map creation only.
   - Camera listeners:
     - In the move-started listener, keep `drag.cameraMoving = true` and emit `onCameraMove(MapCameraEvent(START, current(liveMap)))`.
     - In the idle listener, keep `cameraMoving = false` and emit `IDLE`.
     - Emit only while `attached && !dropped && map === liveMap`.
   - Track `cameraMoving` locally so a `START` is not emitted twice before `IDLE`. The SDK can report several move starts during one animation.
   - `getCamera()`: `withMap { MapCamera(cameraPosition.target.toCoordinate(), cameraPosition.zoom.toDouble()) }`.
3. iOS shared:
   - Change `onCameraMoving: ((Bool) -> Void)?` in `MapPresenter` to `onCamera: ((MapCameraPhase) -> Void)?`.
   - Add `var camera: MapCamera { get }` and `func setInitialCamera(_ camera: MapCamera)`.
   - `MapDragGesture` keeps cancelling on `.start`.
   - `HybridMapSurface` needs the events too. Make `MapDragGesture` forward through a closure set by the surface: `drag.onCamera = { [weak self] phase in ... }`, emitting `MapCameraEvent(phase, presenter.camera)`. Do not add a second presenter callback.
   - In `updatePresentation()`, call `presenter.setInitialCamera` once when the presenter is created and `initialCamera` is set, before markers and routes apply.
   - `getCamera()`: `withPresenter { $0.camera }`.
4. MapKit:
   - `camera` returns `center = map.centerCoordinate` and `zoom = log2(worldWidth * bounds.width / (256 * visibleMapRect.width))`.
   - `setInitialCamera` calls `setCamera(animated: false)` and repeats once on the first layout with non-empty bounds if the bounds were empty. Store a pending camera and apply it from `HybridMapSurface`'s `layoutChanged`, through a presenter `layoutDidChange()` call.
   - Emit `.start` from `regionWillChange` and `.idle` from `regionDidChange`. Use the same duplicate guard as Android.
5. Google iOS:
   - `camera` returns `map.camera.target` and `Double(map.camera.zoom)`.
   - `setInitialCamera` sets `map.camera` directly.
   - Emit `.start` from `willMove` and `.idle` from `idleAt`.
6. Docs: add `initialCamera`, `getCamera`, and `onCameraMove` to `docs/api.md`. State that zoom uses Google zoom levels on every provider.

## Rules

- Events are dropped after release. `releaseMap()` and `releasePresenter()` reset the duplicate guard.
- `getCamera()` rejects with "not ready" before `onReady`, like the other methods.

## Tests

- Example: show the last `onCameraMove` phase and camera, and a button that logs `getCamera()`.
- Each provider:
  - pan, then check that one `start` and one `idle` arrive;
  - `setCamera(c, 12, false)` followed by `getCamera()` returns `c` and 12 within 1e-6 degrees and 0.01 zoom;
  - starting with `initialCamera` shows that camera on the first rendered frame, with no jump.
- A pan during a pin drag still cancels the drag.

## Validation

- `npm run nitrogen` stable, then `npm run typecheck` (package and example).
- Android example build and device checks.
- iOS builds in both configurations on a Mac, then simulator checks per provider. Otherwise report not run.

## Completion criteria

- All three providers implement `initialCamera`, `getCamera`, and `onCameraMove` with the guard.
- Drag cancellation on camera movement still works.
- The docs are updated.

## Commit

`feat: read the camera, set an initial camera, and report camera movement`
