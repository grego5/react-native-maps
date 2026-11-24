# 13 Example and validation coverage

[Back to TASKS.md](../TASKS.md)

Status: Completed (the checklist was not run on any provider: no Android device, no Mac. Coverage is recorded in docs/validation.md.)

Later change: the per-marker `touchEnabled` flag was removed. Every marker is a hit target, and an app maps a decorative marker's ID to the marker it covers in `onTap`. References to it below are historical.

## Objective

Make the Expo example a single place to check every API added in tasks 02 to 12 on each provider. Also make the validation guide list those checks, so a later integration can be judged against them.

## Non-goals

- Automated UI tests.
- Planner integration.

## Read before editing

- `example/App.tsx` and the test UI added by earlier tasks.
- `docs/validation.md`: "Runtime checks".
- `docs/api.md`, for the final public surface.

## Current behavior to preserve

- The example exercises marker prop updates, detach and reattach, projection, snapshots, the provider switch on iOS, and drags.

## Steps

1. Reorganize `example/App.tsx` into the following named sections. Add any controls missing from earlier tasks.
   - **Options**: style toggle, `mapType` toggle, and gesture toggles.
   - **Camera**: `initialCamera` and `initialFit`, a camera-event readout, `getCamera`, a padded and timed `setCamera`, `fitCoordinates` with `maxZoom`, `revealCoordinates` with its outcome, and `cameraFor`.
   - **Markers**: anchor dot, zIndex stack, touch-disabled marker, description, show and hide callout buttons, and a `require` image.
   - **Routes**: dashed and solid routes, overlapping draggable routes with a styled preview, a pin preview, and `dropRadius`.
   - **Hits**: a `queryFeatures` probe at the last tap, and the `routeIds` and `markerIds` of the last drag.
   - **Events**: a log of the last `onTap`, `onPoiTap`, `onDrag`, and `onCameraMove`.
   Keep it one file unless it passes about 400 lines. Above that, split each section into `example/sections/<Name>.tsx`.
2. Add the per-task runtime checks to `docs/validation.md` "Runtime checks" as one checklist grouped by area. Note for each check which provider it applies to.
3. Run the whole checklist on Android. Run it on both iOS providers when a Mac is available. In the "Runtime checks" coverage paragraph, record which providers were checked and which were not.

## Tests

The checklist itself. Each item passes on each applicable provider, or is recorded as not run.

## Validation

- `npm run typecheck` in the example after `npm ci --install-links`.
- Android example build and the device run.
- iOS builds and simulator runs on a Mac, or report not run.

## Completion criteria

- Every public prop and method in `docs/api.md` has a control or readout in the example.
- `docs/validation.md` lists the checks and records the actual coverage.

## Commit

`docs: cover route planner parity in the example and validation guide`
