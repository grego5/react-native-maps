# 07 Marker anchor, order, and touch handling

[Back to TASKS.md](../TASKS.md)

Status: Completed (device checks not run: the phone was unreachable over Wi-Fi ADB. iOS builds and simulator checks not run: no Mac.)

Later change: the per-marker `touchEnabled` flag was removed. Every marker is a hit target, and an app maps a decorative marker's ID to the marker it covers in `onTap`. References to it below are historical.

## Objective

Add three marker fields:

- `anchor?: MapPoint`: the image point placed on the coordinate, as fractions of the image size. The default is `{ x: 0.5, y: 1 }`, the bottom center. The planner uses `{ 0.5, 0.5 }` for dots and `{ 0.5, 0.88 }` for the selection arrow.
- `zIndex?: number`: markers draw from low to high, and input order breaks ties, as routes do. The default is 0.
- `touchEnabled?: boolean`: the default is `true`. A touch-disabled marker never appears as `markerId` in `onTap`.

## Non-goals

- Marker opacity, rotation, flat markers, or drag.
- Ordering markers relative to routes. Markers always draw above routes.

## Read before editing

- `src/MapSurface.nitro.ts` (`MapMarker`) and `src/index.tsx` (`validateMarkers`).
- `android/.../HybridMapSurface.kt`: the `applyMarkers()`, the marker click listener, and `reportTap`.
- `android/.../SurfaceDrag.kt`: `mapTapped`.
- `ios/GoogleMapPresenter.swift`: `applyMarkers`, and `didTap marker`.
- `ios/AppleMapPresenter.swift`:
  - `applyMarkers`, `configureIcon`, `marker(at:)`, `viewFor`;
  - the snapshot marker drawing and `markerOrder`.
- `ios/MapPresenter.swift`: `orderedRoutes`, the pattern to reuse for markers.
- `ios/MapDragGesture.swift`: `handleTap`.

## Current behavior to preserve

- The default pin and loaded icons sit bottom-center. MapKit sets `centerOffset = (0, -height / 2)`, and the snapshot draws at `point.y - size.height`.
- A marker tap reports the marker's coordinate and `markerId`, with no route IDs.

## Steps

1. Spec and JS:
   - Add the three fields to `MapMarker`.
   - In `validateMarkers`, reject an `anchor` with non-finite components and a non-finite `zIndex`. Anchor values outside 0 to 1 are allowed, since SDKs accept them.
   - Run `npm run nitrogen`.
2. Ordering helper:
   - Android: sort the markers with `markers.withIndex().sortedWith(compareBy({ it.value.zIndex ?: 0.0 }, { it.index }))`, and give each a rank equal to its sorted index.
   - iOS: add `orderedMarkers(_:)` beside `orderedRoutes` in `MapPresenter.swift`, with the same stable rule.
3. Android `applyMarkers()`:
   - `setAnchor(x, y)` when changed, or `0.5f, 1f` by default.
   - `zIndex = rank.toFloat()` when changed. Ranks keep equal values in input order, which the SDK does not guarantee for equal floats.
   - Keep a `touchEnabled` lookup by marker ID, updated each apply.
   - In the marker click listener:
     - if the marker has touch disabled, call `reportTap(liveMap, marker.position, null)` and return `true`, so the SDK does not select it or open its info window;
     - otherwise keep the current path.
4. Google iOS:
   - `groundAnchor = CGPoint(x, y)`.
   - `zIndex = Int32(rank)`.
   - `isTappable = spec.touchEnabled ?? true`. Touch-disabled markers pass the tap to `didTapAt`.
5. MapKit:
   - Keep each annotation's `anchor`, `rank`, and `touchEnabled` on the `Annotation` subclass.
   - `configureIcon` sets `centerOffset = ((0.5 - x) * width, (0.5 - y) * height)` for the icon's size.
   - `viewFor` and every icon update set `view.zPriority = MKAnnotationViewZPriority(rawValue: Float(rank))` and `view.isEnabled = touchEnabled`.
   - Replace `markerOrder` with the ordered IDs from `orderedMarkers`.
   - `marker(at:)` walks that order in reverse, skipping touch-disabled annotations.
   - The snapshot draws icons in that order at `point - anchor * size`.
6. Docs: document the three fields in `docs/api.md`, including the anchor default and the tie rule.

## Rules

- Update SDK properties only when the value changed, as the existing reconciliation does.
- Rank changes for one marker may change other markers' ranks. Recompute all ranks on each apply.

## Tests

- Example: three overlapping markers with `zIndex` 2, 1, 1 and a dot image with `anchor { 0.5, 0.5 }`.
  - Each provider: the zIndex-2 marker draws on top, the two zIndex-1 markers draw in input order, and the dot's center sits on its coordinate at several zoom levels.
- Mark a marker `touchEnabled: false` with nothing under it. Tapping it reports `onTap` without `markerId` and opens no callout. On Google iOS and MapKit, a touch-enabled marker under it receives the tap instead. On Android, the tap stays a map tap at the marker's position.
- MapKit snapshot: icons appear at the same anchors and order as on screen.

## Validation

- `npm run nitrogen` stable. `npm run typecheck` (package and example).
- Android device checks. iOS simulator checks for both providers on a Mac, or report not run.

## Completion criteria

- All three fields behave the same on all providers, apart from the documented Android tap-position limit: Android reports a touch-disabled marker's position, not the finger's.
- The docs are updated.

## Commit

`feat: add marker anchor, zIndex and touchEnabled`
