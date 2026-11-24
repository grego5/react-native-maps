# 06 Point-of-interest taps

[Back to TASKS.md](../TASKS.md)

Status: Completed (device checks not run: the phone was unreachable over Wi-Fi ADB. iOS builds and simulator checks not run: no Mac. The MapKit tap deferral is unverified.)

## Objective

Report taps on the map's built-in points of interest:

- `MapPoiTap { placeId?: string; name: string; coordinate: Coordinate }`.
- Prop `onPoiTap?: (event: MapPoiTap) => void`.

On Google maps, `placeId` is the Google Place ID that the planner passes to its place-details query. On MapKit it is the Apple map item identifier when available. It is not a Google ID.

## Non-goals

- Showing or styling POIs. Visibility comes from `mapStyle` (task 03).
- Selecting POIs while a drag is active.

## Read before editing

- `src/MapSurface.nitro.ts` and `src/index.tsx`.
- `android/.../HybridMapSurface.kt`: the listener block in `ensureMap()`, and `reportTap`.
- `android/.../SurfaceDrag.kt`: `captured` and `mapTapped`.
- `ios/MapPresenter.swift`: `onSDKTap`.
- `ios/MapDragGesture.swift`: the `onSDKTap` handler and the tap recognizer.
- `ios/GoogleMapPresenter.swift`: delegate methods.
- `ios/AppleMapPresenter.swift`: `init`, delegate methods.

## Current behavior to preserve

- A POI tap is not a map tap. Google SDKs call the POI listener instead of the map click listener, so `onTap` stays silent. MapKit's own tap recognizer in `MapDragGesture` must not also emit `onTap` for the same touch.
- A drag that captured the touch suppresses taps (`SurfaceDrag.captured`).

## Steps

1. Spec:
   - Add `MapPoiTap` and `onPoiTap` to the native props.
   - Mirror the prop in `src/index.tsx` with `callback()`.
   - Run `npm run nitrogen`.
2. Android:
   - In `getMapAsync`, call `liveMap.setOnPoiClickListener { poi -> reportPoi(liveMap, poi) }`.
   - `reportPoi` returns early on the same conditions as `reportTap`, and when the drag has captured the touch. Expose `SurfaceDrag.captured` as a read-only `isCapturing`.
   - Emit `MapPoiTap(poi.placeId, poi.name, poi.latLng.toCoordinate())`.
3. iOS shared:
   - Add `var onPOITap: ((MapPoiTap) -> Void)?` to `MapPresenter`, and clear it in each presenter's `close()`.
   - `HybridMapSurface` sets it when it creates the presenter and forwards to `onPoiTap` if the host has a window.
   - Add `func setPOITapsEnabled(_ enabled: Bool)` and call it from `updatePresentation()` with `onPoiTap != nil`.
4. Google iOS: implement `mapView(_:didTapPOIWithPlaceID:name:location:)` and emit with the place ID.
5. MapKit:
   - `setPOITapsEnabled` sets `map.selectableMapFeatures = enabled ? [.pointsOfInterest] : []`.
   - In `mapView(_:didSelect annotation:)`, when the annotation is an `MKMapFeatureAnnotation`:
     - deselect it at once (`map.deselectAnnotation(annotation, animated: false)`), so the default POI card does not stay open;
     - emit `name = annotation.title ?? ""` and `coordinate = annotation.coordinate`.
     - On iOS 18 and later, resolve `placeId` with `MKMapItemRequest(mapFeatureAnnotation:).getMapItem` and `mapItem.identifier?.rawValue` before emitting. On iOS 16 and 17, emit without `placeId`.
   - Return `nil` from `viewFor` for `MKMapFeatureAnnotation`, which the existing guard already does.
   - Check that `MapDragGesture.handleTap` does not also emit `onTap` for a POI selection. If it does, skip the map tap when the touch selected a feature. MapKit selects on the same tap, so compare `map.selectedAnnotations` before and after on the main queue, or gate the recognizer with `gestureRecognizer(_:shouldReceive:)` on a hit test against feature annotation views. Pick the approach that passes the test below and document it in `docs/architecture.md` in one sentence.
6. Docs: add `onPoiTap` to `docs/api.md`, with the provider difference for `placeId`.

## Rules

- Emit only from the UI or main thread while attached.
- Clear the callbacks on release.

## Tests

- Example: log `onPoiTap` events.
- Google, both platforms: tapping a restaurant icon emits one `onPoiTap` with a non-empty `placeId` and no `onTap`.
- MapKit: tapping a POI emits one `onPoiTap` and no `onTap`, and the POI card does not stay open.
- With `onPoiTap` unset on MapKit, POIs are not selectable.
- During an active drag, no `onPoiTap` arrives.

## Validation

- `npm run nitrogen` stable. `npm run typecheck` (package and example).
- Android device check. iOS simulator checks for both providers on a Mac, or report not run.

## Completion criteria

- POI taps reach the app on all three providers, with no double `onTap`.
- The docs are updated.

## Commit

`feat: report point-of-interest taps`
