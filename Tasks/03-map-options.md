# 03 Map options

[Back to TASKS.md](../TASKS.md)

Status: Completed (iOS builds and simulator checks not run: no Mac)

## Objective

Add the map display and gesture options the planner sets, as surface props:

| Prop | Type | Default | Planner use |
| --- | --- | --- | --- |
| `mapStyle` | `string` (Google style JSON) | none | `customMapStyle={MAP_STYLE}` |
| `mapType` | `'standard' \| 'none'` | `'standard'` | warm-up map uses `'none'` |
| `scrollEnabled` | `boolean` | `true` | off during drags |
| `zoomEnabled` | `boolean` | `true` | off during drags |
| `rotateEnabled` | `boolean` | `true` | `false` |
| `pitchEnabled` | `boolean` | `true` | `false` |
| `showsBuildings` | `boolean` | `true` | `false` |
| `showsIndoors` | `boolean` | `true` | `false` |

Also turn off the Google Android map toolbar permanently. The planner sets `toolbarEnabled={false}`, and no app of this package needs the toolbar.

## Non-goals

- POI visibility toggles. Hide POIs through `mapStyle`.
- Satellite, hybrid, or terrain map types.
- Camera events or marker tap camera behavior (tasks 04 and 08).

## Read before editing

- `src/MapSurface.nitro.ts`: `MapSurfaceProps`.
- `src/index.tsx`: `MapSurfaceProps`, `MapSurface`.
- `android/.../HybridMapSurface.kt`: property overrides, `afterUpdate()`, `ensureMap()` `getMapAsync` block.
- `ios/HybridMapSurface.swift`: properties, `updatePresentation()`.
- `ios/MapPresenter.swift`: `MapPresenter`.
- `ios/AppleMapPresenter.swift` and `ios/GoogleMapPresenter.swift`: `suspendCameraGestures()`.
- `ios/MapDragGesture.swift`: where `suspendCameraGestures()` is called and its restore closure runs.

## Current behavior to preserve

- All gestures are enabled and the Google style is the SDK default.
- During an iOS drag, `MapDragGesture` disables camera gestures through `suspendCameraGestures()` and restores them on release. Android does not suspend gestures. `SurfaceDrag` captures the touch and sends `ACTION_CANCEL` to the map.

## Steps

1. Add a `MapOptions` interface to `src/MapSurface.nitro.ts` with all eight fields optional. Add `options?: MapOptions` to the native `MapSurfaceProps`. One struct prop keeps native application in one place.
2. In `src/index.tsx`, accept the eight props flat on the public `MapSurfaceProps`. Build `options` with `useMemo` over the eight values and pass it to the host. Export `MapType`.
3. Run `npm run nitrogen`.
4. Android (`HybridMapSurface.kt`):
   - Add `override var options: MapOptions?`. Its setter marks `optionsDirty = true`.
   - Add `applyOptions(liveMap)`, called from `afterUpdate()` after `ensureMap()` and from the `getMapAsync` callback before `applyMarkers()` and `applyRoutes()`. It returns early unless `optionsDirty`.
   - `mapStyle`: `liveMap.setMapStyle(MapStyleOptions(json))`, or `setMapStyle(null)` when absent. If the SDK returns `false`, log one warning through `android.util.Log`. Do not throw.
   - `mapType`: `GoogleMap.MAP_TYPE_NONE` or `MAP_TYPE_NORMAL`.
   - `uiSettings.isScrollGesturesEnabled`, `isZoomGesturesEnabled`, `isRotateGesturesEnabled`, and `isTiltGesturesEnabled` from the gesture props.
   - `isBuildingsEnabled` and `isIndoorEnabled`.
   - In the `getMapAsync` callback, set `uiSettings.isMapToolbarEnabled = false` once.
   - Reset `optionsDirty = true` in `releaseMap()` so a new map receives the options.
5. iOS shared:
   - Add `func apply(_ options: MapOptions)` to `MapPresenter`.
   - In `HybridMapSurface.swift`, add `var options: MapOptions?` with `didSet { optionsDirty = true }`.
   - In `updatePresentation()`, apply options when the presenter is new or `optionsDirty` is set, before applying markers and routes.
6. MapKit (`AppleMapPresenter.swift`):
   - Store the latest options as `configured`.
   - Apply `isScrollEnabled`, `isZoomEnabled`, `isRotateEnabled`, `isPitchEnabled`, and `showsBuildings`.
   - Ignore `mapStyle`, `mapType: 'none'`, and `showsIndoors`. Document them as Google-only.
   - While a drag suspends gestures, `apply(_ options:)` stores `configured` but does not touch the gesture flags.
   - Change `suspendCameraGestures()` so its restore closure applies the gesture flags from `configured` at restore time, not values captured at suspend time.
7. Google iOS (`GoogleMapPresenter.swift`):
   - Same pattern with `map.settings.scrollGestures`, `zoomGestures`, `rotateGestures`, and `tiltGestures`.
   - `mapStyle`: `map.mapStyle = try? GMSMapStyle(jsonString:)`, or `nil` when absent. On a parse failure, log once with `NSLog` and keep the default style.
   - `mapType`: `.none` or `.normal`.
   - `isBuildingsEnabled` and `isIndoorEnabled`.
8. Document the props in `docs/api.md` under a new "Map options" section. Mark `mapStyle`, `mapType: 'none'`, and `showsIndoors` as Google-only.

## Rules

- Apply SDK settings on the UI or main thread only, as the existing `afterUpdate()` and `updatePresentation()` paths do.
- A drag must never leave gestures in a state different from the latest `options`.

## Tests

- `npm run typecheck`.
- Example (task 13 extends it): toggle `scrollEnabled` and `rotateEnabled` and apply a style that hides POIs. Pans and rotations stop and resume, and POIs disappear.
- iOS: start a pin drag, change `scrollEnabled` to `false` mid-drag, release. Scrolling stays disabled.

## Validation

- `npm run nitrogen` leaves no diff on a second run.
- `npm run typecheck` in the package root and in `example/` after `npm ci --install-links`.
- Android example build. iOS builds in both configurations on a Mac, or report not run.
- Device or simulator checks as above, reported separately.

## Completion criteria

- All eight props reach every provider that supports them. The Google Android toolbar never appears on marker tap.
- iOS drag restore respects the latest options.
- `docs/api.md` documents the props and the provider limits.

## Commit

`feat: add map style, map type, gesture, building and indoor options`
