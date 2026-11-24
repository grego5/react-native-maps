# 11 Drag preview appearance

[Back to TASKS.md](../TASKS.md)

Status: Completed (Android build and device checks not run: no phone. iOS not run: no Mac.)

## Objective

Let the app style the native drag preview so it can replace the planner's JS overlay (`RouteMapInsertOverlay`):

- `DragPreview { strokeColor?: string; strokeWidth?: number; dashPattern?: number[]; image?: MarkerImage; anchor?: MapPoint }`.
- `RouteDrag.preview?: DragPreview` styles a route drag.
- Surface prop `pinDragPreview?: DragPreview` styles a standalone pin drag.
- Defaults match today's preview:
  - connector: `#007AFF`, 3 points wide, solid;
  - pin: a filled circle with a 6-point radius on Android and 5 on iOS. Unify both to 6.
- The image's `anchor` sits on the lifted drag point. The default anchor is the bottom center `{ 0.5, 1 }`.

## Non-goals

- Changing the 32-point lift, the 400 ms long-press delay, or hit testing.
- Animating the preview.
- Showing extra markers during a drag. The app can add them to `markers` on `onDrag` `start`.

## Read before editing

- `src/MapSurface.nitro.ts` (`RouteDrag`, props) and `src/index.tsx`, including the validators added in tasks 07 and 09.
- `android/.../SurfaceDrag.kt`: `paint`, `draw`, `begin`, `Drag`.
- `android/.../HybridMapSurface.kt`: `afterUpdate()` (`pinEnabled`), `SurfaceHost`.
- `android/.../MarkerImages.kt`: `load` and its callback.
- `ios/MapDragGesture.swift`: `preview` layer setup and `draw`.
- `ios/HybridMapSurface.swift`: `updatePresentation()` (`pinEnabled`).
- `ios/MarkerImages.swift`.

## Current behavior to preserve

- The preview draws lines from each anchor to the lifted point plus a circle, and clears on end or cancel.
- Drag events and coordinates are unchanged.
- A drag cancels when the dragged route's anchors change (`updateRoutes`). A change in `preview` alone must not cancel.

## Steps

1. Spec and JS:
   - Add `DragPreview`, `RouteDrag.preview`, and `pinDragPreview`.
   - Validate color, width, and dash with the same rules as `RouteAppearance` by extracting the existing checks into a shared `validateStroke` helper.
   - Resolve `require` images as in task 10.
   - Run `npm run nitrogen`.
2. Android `SurfaceDrag`:
   - Hold `pinPreview: DragPreview?`, set from `HybridMapSurface.afterUpdate()`.
   - At `begin()`, pick `drag.route?.drag?.preview ?: pinPreview` (the pin preview only for pin drags) and store it in `Drag`.
   - Build a per-drag `Paint` from it: color, width × density, and `DashPathEffect` from the dash pattern × density.
   - Draw the connectors with `canvas.drawLine`. With `DashPathEffect`, a `Path` with `drawPath` is required, so use a `Path` for both cases.
   - If `image` is set, request the bitmap with `MarkerImages.load` when preview props change, not at drag start. Keep the loaded bitmaps in a map keyed by `MarkerImage`.
   - Draw the bitmap at `point - anchor × size`. While it is loading or after a failure, draw the circle.
3. iOS `MapDragGesture`:
   - Same selection at `.began`.
   - Set `preview.strokeColor`, `lineWidth`, and `lineDashPattern` for the connector path.
   - Use a separate `CALayer` (`pinLayer`) with `contents = image.cgImage`, sized to the image and positioned by the anchor, for the pin image. Load through `MarkerImages.shared.load` when the props change.
   - Hide `pinLayer` and keep the circle when there is no image.
   - Clear both layers in `finish`.
   - `HybridMapSurface` passes `pinDragPreview` beside `pinEnabled`.
4. Docs: add a "Drag preview" paragraph to `docs/api.md`, with the defaults.

## Rules

- Preview images load before a drag, so the first frame of a drag never waits on I/O. A drag that starts before the image loads draws the circle.
- Drawing stays on the UI or main thread. No per-move allocations beyond the existing `Path` or `UIBezierPath`.

## Tests

- Example: a draggable route with `preview { strokeColor: '#FF3B30', strokeWidth: 4, dashPattern: [6, 4], image: pin }` and a `pinDragPreview` with a different image.
- Each provider:
  - a route drag draws red dashed connectors and the route's pin image, with its anchor at the lifted point;
  - a pin drag shows the other image;
  - with no preview, the default blue look remains;
  - changing only `preview` during a drag does not cancel it.

## Validation

- `npm run nitrogen` stable. `npm run typecheck` (package and example).
- Android device checks. iOS simulator checks for both providers on a Mac, or report not run.

## Completion criteria

- Both drag kinds render the styled preview on all providers, with the defaults unchanged when unset.
- The docs are updated.

## Commit

`feat: style the drag preview`
