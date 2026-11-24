# 08 Marker callouts

[Back to TASKS.md](../TASKS.md)

Status: Completed (Android build and device checks not run: no phone. iOS not run: no Mac.)

Later change: the per-marker `touchEnabled` flag was removed. Every marker is a hit target, and an app maps a decorative marker's ID to the marker it covers in `onTap`. References to it below are historical.

## Objective

Give the app control over the native title callout (Google info window, MapKit callout):

- `MapMarker.description?: string`: the second line, shown under `title`.
- `showCallout(markerId: string): Promise<void>` opens that marker's callout and closes any other.
- `hideCallout(): Promise<void>` closes the open callout.
- A marker tap never moves the camera. It still opens the tapped marker's callout when the marker has a `title`, as each SDK does by default.

The planner uses `title` and `description`, `showCallout()` and `hideCallout()` on marker refs, and `moveOnMarkerPress={false}`.

## Non-goals

- Callout press events, custom callout views, and callout anchors.
- Reporting callout open and close to JS. The planner tracks the open callout itself.

## Read before editing

- `src/MapSurface.nitro.ts` and `src/index.tsx`.
- `android/.../HybridMapSurface.kt`: the marker loop, the marker click listener (as left by task 07), `withMap`, and `clearFeatures`.
- `ios/HybridMapSurface.swift`: `withPresenter`.
- `ios/MapPresenter.swift`.
- `ios/GoogleMapPresenter.swift`: marker loop, `didTap marker`, `clearFeatures` (`selectedMarker`).
- `ios/AppleMapPresenter.swift`: `Annotation`, `applyMarkers`, `viewFor` (`canShowCallout`).

## Current behavior to preserve

- Google SDKs on marker tap select the marker, open its info window if it has a title, and center the camera on it. This task removes only the camera move.
- MapKit selects the annotation and shows its callout when `title` is set. MapKit does not move the camera on selection.
- Touch-disabled markers (task 07) never open a callout from a tap. `showCallout` still opens them, because the app asked.

## Steps

1. Spec and JS:
   - Add `description` to `MapMarker`.
   - Add the two methods to `MapSurfaceMethods`.
   - Run `npm run nitrogen`.
2. Android:
   - Set `snippet` from `description` at creation and when changed.
   - In the marker click listener, for touch-enabled markers:
     - call `reportTap`;
     - if `marker.title != null`, call `marker.showInfoWindow()`;
     - return `true`, which stops the default camera move.
   - `showCallout(id)`: `withMap`. Reject with `IllegalArgumentException("Unknown marker")` when `markers[id]` is missing. Call `showInfoWindow()`, which closes the previous one automatically.
   - `hideCallout()`: `withMap`. Call `hideInfoWindow()` on the marker whose `isInfoWindowShown` is true.
3. iOS shared:
   - Add `func showCallout(_ id: String) throws` and `func hideCallout()` to `MapPresenter`.
   - `HybridMapSurface` routes both through `withPresenter`.
   - Add `MapSurfaceError.unknownMarker`.
4. Google iOS:
   - Set `snippet` from `description`.
   - In `didTap marker`, after `onSDKTap`, set `map.selectedMarker = marker.title == nil ? nil : marker` and return `true`. Returning `true` stops the default camera move, so selection has to be done here.
   - `showCallout` sets `map.selectedMarker` and throws `unknownMarker` when the ID is unknown.
   - `hideCallout` sets `map.selectedMarker = nil`.
5. MapKit:
   - Set `subtitle` from `description` on create and update.
   - `showCallout`: `map.selectAnnotation(marker, animated: true)`. This works for touch-disabled annotations too, because selection through the API ignores `isEnabled`. Verify on the simulator. If it does not show the callout, enable the view for the duration of the selection and disable it again in `didDeselect`.
   - `hideCallout`: deselect all `selectedAnnotations` that are `Annotation`.
6. Removing a marker whose callout is open closes the callout. Removing the SDK object handles this on all providers. Verify it, and add no code unless the test fails.
7. Docs: document `description`, the two methods, and the marker tap behavior in `docs/api.md`.

## Rules

- The methods run on the UI or main thread through `withMap` and `withPresenter`, and reject before `onReady`.
- Do not store callout state in the surface. The SDK selection is the single source.

## Tests

- Example: markers with a title and description, and buttons for "Show callout on B" and "Hide callout".
- Each provider:
  - tapping A opens A's callout and the camera stays still;
  - "Show callout on B" closes A's and opens B's;
  - "Hide callout" closes it;
  - `showCallout('missing')` rejects;
  - removing B from the array while its callout is open closes it.

## Validation

- `npm run nitrogen` stable. `npm run typecheck` (package and example).
- Android device checks. iOS simulator checks for both providers on a Mac, or report not run.

## Completion criteria

- Description, programmatic callouts, and the no-camera-move tap work on all providers.
- The docs are updated.

## Commit

`feat: control marker callouts and keep the camera still on marker taps`
