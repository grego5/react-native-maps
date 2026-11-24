# 12 Feature hit queries

[Back to TASKS.md](../TASKS.md)

Status: Completed (Android build, device checks and the step 5 timing not run: no phone. iOS not run: no Mac.)

Later change: the per-marker `touchEnabled` flag was removed. Every marker is a hit target, and an app maps a decorative marker's ID to the marker it covers in `onTap`. References to it below are historical.

## Objective

Move the planner's drop geometry (`route-map-drop-geometry.ts`) into the surface, which already projects routes for tap and drag hit tests:

- `MapDragEvent.routeIds: string[]`: every draggable route under the press, nearest first, the same on every event of one drag. `routeId` stays the route whose anchors are previewed, which is `routeIds[0]`. The planner's insert candidates are "the legs the drag started on, nearest first".
- `MapDragEvent.markerIds: string[]`: on `end` only, the touch-enabled markers whose anchor point lies within `dropRadius` points of the drop point, nearest first. The array is empty on other phases. The planner's nearby visit markers at the drop use a 48-point radius.
- Prop `dropRadius?: number`, in display points. The default is 0, which reports no markers.
- Method `queryFeatures(point: MapPoint, radius: number): Promise<MapFeatureHits>`, where `MapFeatureHits { markerIds: string[]; routeIds: string[] }`:
  - markers: the touch-enabled markers whose anchor lies within `radius` of `point`;
  - routes: every route within `max(radius, its hitSlop)` of `point`, regardless of draggability;
  - both lists are nearest first.

## Non-goals

- Marker hit areas based on image bounds. Distance to the anchor point matches the planner's rule.
- Deciding what a drop means (insert, replace, cancel). That is planner logic.
- Clipping segments to the viewport for speed, as the planner's snapshot did. Projection per query is enough at planner sizes. Revisit only if step 5 measures more than 4 ms per query.

## Read before editing

- Planner reference (read only): `C:\dev\rikum-systems\agent\components\RoutePlanner\Map\route-map-drop-geometry.ts` (`getRouteMapInsertCandidates`, `getRouteMapDropHits`, `getRouteMapNearbyMarkers`) and `use-route-map-insert.ts` (the constants and how candidates are used).
- `src/MapSurface.nitro.ts`: `MapDragEvent`, `MapSurfaceMethods`.
- `android/.../SurfaceDrag.kt`: `Drag`, `begin()`, `routeIdsAt`, `dispatch`, `updateRoutes`.
- `android/.../PolylineHits.java`.
- `android/.../HybridMapSurface.kt`: `applyMarkers` (task 02), the marker `touchEnabled` lookup (task 07), and `withMap`.
- `ios/MapDragGesture.swift`: `Drag`, `handle(_:)`, `route(at:)`, `routeHits`, `emit`.
- `ios/HybridMapSurface.swift`: where `drag.updateRoutes` is called.
- `ios/MapPresenter.swift` and the presenters: marker storage, anchor, and touchEnabled (task 07).

## Current behavior to preserve

- Drag hit testing uses each route's `hitSlop`, or 20 points when it is omitted. Zero disables drag hits.
- Tap hit testing (`onTap.routeIds`) is unchanged.
- Drag start, move, end, and cancel phases and the 32-point lift are unchanged.

## Steps

1. Spec:
   - Add `routeIds` and `markerIds` to `MapDragEvent`, `dropRadius` to the props, and `MapFeatureHits` and `queryFeatures`.
   - Run `npm run nitrogen`.
   - Export the new type from `src/index.tsx`.
2. Marker positions for hit testing:
   - The drag coordinators get a marker list. Each entry has an ID and coordinate, and only touch-enabled markers are included.
     - Android: `SurfaceDrag.updateMarkers(list)`, called from `applyMarkers`.
     - iOS: `MapDragGesture.updateMarkers(_:)`, called from `updatePresentation()` when markers apply.
   - Coordinates are the anchor point by definition (task 07), so projecting the coordinate gives the anchor's screen point.
3. Android `SurfaceDrag`:
   - `Drag` stores `routeIds` computed once in `begin()` with `routeIdsAt(origin, forDrag = true)`.
   - `dispatch` passes `routeIds`, plus `markerIds` on `END` from `markersNear(drag.point, dropRadius)`. That function projects each marker, keeps those within the radius in pixels (radius × density), and sorts by distance, then input order.
   - Add `queryFeatures(point, radius)` used by the surface method, with the point converted from points to pixels. Routes use `PolylineHits` with the slop `max(radius, hitSlop ?: 0)`.
4. iOS `MapDragGesture`: the same additions, using `routeHits` with `forDrag: true` at `.began` and a `markersNear` helper. `HybridMapSurface.queryFeatures` calls the gesture's helper through `withPresenter`.
5. Measure on the Android example: 300 markers and 50 routes of 500 points each. Time `queryFeatures` with temporary `SystemClock.elapsedRealtimeNanos` logs, report the median, and remove the logs.
6. Docs: update the drag section of `docs/api.md` (`routeIds`, `markerIds`, `dropRadius`) and add `queryFeatures`.

## Rules

- Queries run on the UI or main thread with the live projection, as tap hits do.
- Touch-disabled markers never appear in results.
- Ties sort by input order, so results are deterministic.

## Tests

- Example: two overlapping draggable routes, markers near a drop zone, and `dropRadius: 48`.
- Each provider:
  - a drag started where both routes overlap reports both IDs in `routeIds`, nearest first, on every phase;
  - a drop near two markers reports both in `markerIds` on `end` only, nearest first;
  - a touch-disabled marker in range is not reported;
  - `queryFeatures` at a marker returns it first, and at a route returns that route.

## Validation

- `npm run nitrogen` stable. `npm run typecheck` (package and example).
- Android device checks and the step 5 measurement. iOS simulator checks for both providers on a Mac, or report not run.

## Completion criteria

- The planner can build its insert candidates and nearby markers from drag events alone.
- `queryFeatures` works on all providers.
- The docs are updated.

## Commit

`feat: report hit routes and nearby markers for drags and queries`
