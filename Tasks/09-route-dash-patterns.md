# 09 Route dash patterns

[Back to TASKS.md](../TASKS.md)

Status: Completed (Android build and device checks not run: no phone. iOS not run: no Mac.)

## Objective

Add `RouteAppearance.dashPattern?: number[]`, alternating dash and gap lengths in display points. Omitted means solid. The planner draws straight legs and connectors dashed (`lineDashPattern`).

## Non-goals

- Dot patterns, line caps or joins as props, gradients.
- Dashes in the drag preview (task 11 reuses this field).

## Read before editing

- `src/MapSurface.nitro.ts` (`RouteAppearance`) and `src/index.tsx` (`validateRoutes`).
- `android/.../HybridMapSurface.kt`: `applyRoutes()`, including the density use for width.
- `ios/GoogleMapPresenter.swift`: `applyRoutes`, `idleAt`.
- `ios/AppleMapPresenter.swift`: `RouteStyle`, `routeStyles`, `applyStyle`, the style-only update branch in `applyRoutes`, `rendererFor`, and the snapshot route drawing.
- `ios/MapPresenter.swift`: `MapRoute` extensions.

## Current behavior to preserve

- Style-only changes update the existing SDK line without recreating it: Android sets properties, Google iOS sets properties, and MapKit updates the renderer.
- Route order and hit testing do not depend on the stroke.

## Steps

1. Spec and JS:
   - Add `dashPattern` to `RouteAppearance`.
   - In `validateRoutes`, reject a pattern that is empty, has odd length, or has a non-finite or non-positive entry.
   - Run `npm run nitrogen`.
2. Android:
   - Map the pattern to `List<PatternItem>`, alternating `Dash(px)` and `Gap(px)`, where px is points × density.
   - Set `PolylineOptions.pattern` at creation.
   - On update, compare against `appliedRoutes[id]?.dashPattern` with `contentEquals`, and set `existing.pattern` (or `null`) only when it changed.
3. MapKit:
   - Extend `RouteStyle` with `dash: [NSNumber]?`.
   - Include `dashPattern` in the style-change comparison.
   - `applyStyle` sets `renderer.lineDashPattern`.
   - The snapshot calls `context.setLineDash(phase: 0, lengths:)` per route, and resets it to solid for solid routes.
4. Google iOS: `GMSPolyline` dashes are geographic lengths through `spans`, not screen points.
   - Add a helper `dashSpans(for spec: MapRoute, path: GMSPath, metersPerPoint: Double) -> [GMSStyleSpan]` using `GMSStyleSpans(path, [GMSStrokeStyle.solidColor(color), GMSStrokeStyle.solidColor(.clear)], lengths, .rhumb)`, with lengths = pattern × metersPerPoint.
   - `metersPerPoint = 40_075_016.686 * cos(latitude in radians) / (256 * pow(2, zoom))` at the camera target.
   - Apply spans for dashed routes in `applyRoutes`, and set `spans = nil` for solid ones.
   - In `mapView(_:idleAt:)`, recompute spans for dashed routes only, so dash lengths stay constant on screen after zooming.
   - Keep a set of dashed route IDs to avoid scanning all lines.
5. Docs: add `dashPattern` to the route styling section of `docs/api.md`. Note that Google iOS rescales dashes when the camera settles, so dash lengths stretch during a zoom gesture.

## Rules

- Do not recreate SDK lines for a dash change.
- Recompute Google iOS spans on the main thread in the delegate callback only.

## Tests

- Example: one route with `dashPattern: [8, 6]` beside a solid route.
  - Each provider: dashes are about 8 points with 6-point gaps at two zoom levels. On Google iOS, check after the camera settles.
  - Toggle the pattern off and on with a button. The line switches between solid and dashed without flicker or re-ordering.
- MapKit snapshot shows the dashed route dashed.
- `dashPattern: [4]` throws in JS.

## Validation

- `npm run nitrogen` stable. `npm run typecheck` (package and example).
- Android device checks. iOS simulator checks for both providers on a Mac, or report not run.

## Completion criteria

- Dashes in display points on Android and MapKit, and rescaled on idle on Google iOS.
- The docs note the Google iOS behavior.

## Commit

`feat: add route dash patterns`
