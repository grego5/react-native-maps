# 14 Peel drag preview

[Back to TASKS.md](../TASKS.md)

Status: Planned

## Objective

Add a second route drag preview style, where the route itself peels off the map toward the finger instead of two straight connectors appearing:

- At first the pressed section stretches toward the finger as a soft curve. It moves less than the finger, so the pull meets resistance.
- Past a tension threshold, the section lets go of the next joint on each side. That joint's stretch of route lifts off its original position and joins the pulled section.
- Each further release peels one more joint, until the release reaches the route's drag anchors. From then on, the two pulled lines stretch freely, as the `'lines'` preview does.

API:

- `DragPreview.style?: 'lines' | 'peel'`. Defaults to `'lines'`, today's preview.
- `DragPreview.peel?: PeelOptions`, read only for `'peel'`:
  - `jointSpacing?: number`: the smallest on-screen distance, in display points, between a held joint and the press. Closer joints are skipped. Default 24.
  - `resistance?: number`, from 0 to 1: how far the grabbed point lags the finger. 0 follows exactly. Default 0.35.
  - `releaseStretch?: number`, greater than 1: how far the link next to a held joint may stretch, as a multiple of its rest length, before that joint lets go. Default 1.6.

## Decisions

- Peeling never goes past the drag anchors (`RouteDrag.anchors`), which are the route's stops. Joints of a decoded polyline are geometry, not stops.
- Visual only. Drag events, coordinates, `routeIds`, `markerIds`, and the drop are the same as for `'lines'`.
- The peeled section draws with the route's own `strokeColor`, `strokeWidth`, and `dashPattern`, so it reads as the same line. The preview's `strokeColor`, `strokeWidth`, and `dashPattern` are ignored for `'peel'`. The preview `image` and `anchor` still mark the finger.

## Non-goals

- Pin drags. They have no route to peel.
- A release or snap-back animation after `end` or `cancel`. The route restores at once.
- Haptics.
- Gravity, inertia after release, or collisions. The map is viewed from above.

## Read before editing

- `src/MapSurface.nitro.ts` (`DragPreview`) and `src/index.tsx` (`validatePreview`).
- `android/.../SurfaceDrag.kt`: `Drag`, `begin()`, `draw()`, `finish()`, `loadPreviewImages()`.
- `android/.../HybridMapSurface.kt`: `applyRoutes()` (style mapping and `routeHandles`), `SurfaceHost` (how it builds `SurfaceDrag`).
- `android/.../CameraMath.kt` and `android/src/test/.../CameraMathTest.kt`: the pattern for a pure math module and its tests.
- `ios/MapDragGesture.swift`: `Drag`, `handle(_:)`, `style(for:)`, `draw(_:)`, `finish(_:)`.
- `ios/MapPresenter.swift`, `ios/AppleMapPresenter.swift` (`applyRoutes`, `routeStyle`, overlay levels), and `ios/GoogleMapPresenter.swift` (`applyRoutes`, `applyDashes`).
- `ios/CameraMath.swift`: the mirrored-module pattern.

## Current behavior to preserve

- `'lines'` draws exactly as task 11 left it.
- Camera gestures stay suspended during a drag, so screen positions of route joints do not change while one is active.
- A drag cancels when its route's anchors change (`updateRoutes`). A route geometry change during a peel drag also cancels it, because the projected joints are no longer valid.
- The 32-point lift, the 400 ms long-press delay, and hit testing are unchanged.

## Model

The model is a pure module per platform, mirrored like `CameraMath`: `android/.../PeelPreview.kt` and `ios/PeelPreview.swift`. It works in screen points with no SDK calls.

1. **Start.**
   - Input: the projected route joints `P[0..n]`, the press point, the drag anchors mapped once to their nearest joint indices, and the options.
   - Find the segment `k..k+1` nearest the press, and the grab point `G` on it.
   - The left limit is the largest anchor index `<= k`, or 0 when there is none. The right limit is the smallest anchor index `>= k + 1`, or `n`.
   - Held joint `L` is the largest index `<= k`, but not below the left limit, whose distance from `G` is at least `jointSpacing`. Use the left limit when no joint qualifies. Held joint `R` mirrors this on the right.
2. **Chain.**
   - The free chain is the original path from `P[L]` through `G` to `P[R]`, resampled to evenly spaced particles: one per `jointSpacing / 2` of path length, at most 64.
   - Each link's rest length is its original screen length.
   - `P[L]` and `P[R]` are pinned. The grab particle is driven by the finger.
3. **Step**, at 120 Hz fixed steps:
   - The grab target is `G + (finger − G) × (1 − resistance)`. The grab particle moves to it.
   - Integrate with Verlet, with damping 0.9 per step, then 8 passes of distance constraints. Links may stretch but not compress below their rest length.
4. **Release.**
   - After each step, check the link next to `L`. If it exceeds `releaseStretch` × its rest length and `L` is above the left limit, move `L` outward to the next joint at least `jointSpacing` from the old `L`, clamped to the left limit.
   - Insert the passed joints as new particles at their original positions, linked with their original lengths, so they visibly lift off. Resample to keep at most 64 particles. Mirror this for `R`.
   - At most one release per side per step.
5. **At a limit.** Once `L` sits on the left limit, the link next to it has no maximum length. That side then stretches toward the finger as a straight line. Mirror this for `R`.
6. **Output.** The particle polyline to draw, plus the current `L` and `R`. `L` and `R` change only on release.

## Steps

1. Spec and JS:
   - Add `PeelOptions`, `DragPreview.style`, and `DragPreview.peel`.
   - In `validatePreview`:
     - reject a `style` other than the two values;
     - reject `jointSpacing` that is not finite and positive;
     - reject `resistance` outside 0 to 1;
     - reject `releaseStretch` that is not finite and greater than 1.
   - Run `npm run nitrogen`.
2. Pure module: implement the model above in Kotlin and Swift with identical constants and order of operations.
3. Hide the peeled range of the original line. Add one operation per platform, driven by the drag coordinator: show route `id` with joints `L..R` removed, or restore it.
   - The surface draws the untouched prefix `0..L` and suffix `R..n` as two temporary SDK lines. They copy the route's style and rank. The original line is hidden.
   - The temporary lines update only when `L` or `R` changes. Restore on `end`, `cancel`, route removal, and release of the surface.
   - Android: `HybridMapSurface` gives `SurfaceDrag` a `peelRoute(id, from, to)` / `restoreRoute(id)` pair. It hides the line with `isVisible = false` and adds the two temporary `Polyline`s.
   - iOS: add `func peelRoute(_ id: String, from: Int, to: Int)` and `func restoreRoute(_ id: String)` to `MapPresenter`, implemented by both presenters.
     - MapKit adds two `MKPolyline` overlays at the original's level and removes the original until restore.
     - Google iOS hides the line by clearing its `map` and reapplies dashes to the temporary lines.
4. Frame loop:
   - Android: in `SurfaceDrag`, when a `'peel'` drag starts, post a `Choreographer` frame callback that advances the model by the elapsed time in fixed steps, updates `L` and `R` through `peelRoute`, and invalidates the host. Stop it in `finish`.
   - iOS: a `CADisplayLink` in `MapDragGesture`, with the same rules. Invalidate it in `finish` and `close`.
   - Feed the finger position from touch moves. Do not run the model inside touch handling.
5. Drawing:
   - Android draws the particle polyline in `draw()` with a per-drag `Paint` built from the route's style, including `DashPathEffect` for its `dashPattern`. Reuse one `Path`.
   - iOS sets the particle path on the `preview` layer, styled from the route.
   - Both draw the preview image or the default circle at the finger, as for `'lines'`.
6. Tests:
   - JUnit `PeelPreviewTest`:
     - joint selection skips joints closer than `jointSpacing`;
     - held joints never pass the anchor limits;
     - a short pull releases nothing;
     - a long pull releases joints one at a time, each side up to its limit;
     - the chain stays continuous from `P[L]` to `P[R]` through the grab particle;
     - the particle count stays at or under 64;
     - `resistance` 0 puts the grab particle on the finger.
   - Compile `ios/PeelPreview.swift` on Windows against stand-in types, as was done for `CameraMath.swift`, and run the same cases.
7. Example:
   - Give the orange route `preview: { style: 'peel', image: pin }`, and keep a `'lines'` route for comparison.
   - Add sliders, or plus and minus buttons, for the three options, so they can be tuned on a device.
8. Docs: describe `style` and `peel` in the drag preview paragraph of `docs/api.md`. Add a device checklist item to `docs/validation.md`.

## Rules

- The SDK lines change only on release, never per frame. Per-frame work is the model step and one overlay path.
- No allocation per frame beyond the resampled particle arrays, which are reused.
- Everything runs on the UI or main thread. The model needs no thread.
- The temporary SDK lines are owned by the surface and released with it, like other SDK handles.

## Tests

- JUnit `PeelPreviewTest` passes. The Swift mirror passes the same cases.
- Device, each provider:
  - a short pull bends the pressed section toward the finger with visible lag;
  - pulling further releases joints one at a time, outward, and each released stretch lifts off its original place;
  - releases stop at the anchors, then both lines stretch straight to the finger;
  - the original route is complete again after `end` and after `cancel`;
  - a `'lines'` route still draws as before;
  - 60 fps on a long decoded route, measured with Android GPU rendering profiling or Instruments.
- Tuning: record the option values that feel right on a device and make them the defaults.

## Validation

- `npm run nitrogen` stable. `npm run typecheck` (package and example).
- `:react-native-maps:testDebugUnitTest` through `example/android`.
- Android device checks and tuning. iOS simulator checks for both providers on a Mac, or report not run.

## Completion criteria

- `'peel'` works on all three providers, with the release limited by the anchors and the route restored after every drag.
- The model is unit-tested on Android and mirrored in Swift.
- The defaults come from device tuning, or are recorded as untuned.
- The docs are updated.

## Commit

`feat: add a peel drag preview for routes`
