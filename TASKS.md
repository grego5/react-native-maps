# Route planner parity

## Goal

Extend `MapSurface` until it covers everything the route planner (`rikum-systems/agent`, `components/RoutePlanner/`) uses from react-native-maps 1.29.11. Move into the surface the planner's math that depends on the live map: camera fitting, padded centering, revealing, and screen-space hit tests.

The current API already covers markers, routes, taps, projection, `setCamera`, and route or pin drag.

Integrating the planner is not part of this plan. Each task changes the library and its example only.

## Where the math goes

- **Into the surface:** anything that needs the view's size, camera, projection, or marker positions. That covers camera fit, padding, reveal, initial fit, and drag and drop hit queries. The native view knows these exactly. The planner currently reconstructs them in JS with `getCamera()` and `project()` round trips and its own Web Mercator code.
- **Stays in the planner:** pure geometry and app logic. That covers polyline decoding and simplification, bounds for fit points, and choosing zoom targets. It is fast in JS, testable there, and needs no native binding.
- **No shared C++ geometry module.** Kotlin cannot call a Nitro C++ object directly, and returning decoded arrays to JS costs as much as decoding in JS. `native/` stays as it is.
- **Encoded polylines stay in JS.** Task 02 splits markers and routes into separate props, so route coordinates cross into native only when routes change. Revisit only if task 02's measurement shows route conversion is still costly.

## Constraints

- Follow [`AGENTS.md`](AGENTS.md), [`android/AGENTS.md`](android/AGENTS.md), [`ios/AGENTS.md`](ios/AGENTS.md), and the [validation guide](docs/validation.md).
- Backward compatibility is not required. The planner is the only consumer. Prefer the efficient API over upstream names.
- Each task that changes `src/MapSurface.nitro.ts` regenerates bindings with `npm run nitrogen`. Generated specs make every new member required, so the same task implements it on Android, the MapKit presenter, and the Google iOS presenter.
- Keep features as data keyed by ID. The surface owns SDK handles, camera, gestures, and hit testing.
- Update [`docs/api.md`](docs/api.md) in the task that changes public behavior.
- Report build checks separately from device and simulator checks. Record unavailable environments (no Mac, no API key) as not run.

## Tasks

Run them in order. Later tasks edit the same reconciliation, camera, and gesture code.

| # | Task | Outcome |
| --- | --- | --- |
| 01 | [Fix the MapKit snapshotter type](Tasks/01-fix-mapkit-snapshotter.md) | iOS compiles |
| 02 | [Split marker and route props](Tasks/02-split-feature-props.md) | Marker updates do no route work; stable callback props |
| 03 | [Map options](Tasks/03-map-options.md) | Style, map type, gesture toggles, buildings, indoors |
| 04 | [Camera state and events](Tasks/04-camera-state-and-events.md) | `initialCamera`, `getCamera`, `onCameraMove` |
| 05 | [Camera fit, padding, and reveal](Tasks/05-camera-fit-padding-reveal.md) | `setCamera` with padding and duration, `fitCoordinates`, `revealCoordinates`, `cameraFor`, `initialFit` |
| 06 | [Point-of-interest taps](Tasks/06-poi-taps.md) | `onPoiTap` |
| 07 | [Marker anchor, order, and touch handling](Tasks/07-marker-anchor-order-tappable.md) | `anchor`, `zIndex` |
| 08 | [Marker callouts](Tasks/08-marker-callouts.md) | `description`, `showCallout`, `hideCallout`, no camera move on marker tap |
| 09 | [Route dash patterns](Tasks/09-route-dash-patterns.md) | `dashPattern` |
| 10 | [Bundled marker images](Tasks/10-bundled-marker-images.md) | `require()` assets as marker images |
| 11 | [Drag preview appearance](Tasks/11-drag-preview-appearance.md) | Styled connectors and pin image |
| 12 | [Feature hit queries](Tasks/12-feature-hit-queries.md) | All routes under a drag, markers near a drop, `queryFeatures` |
| 13 | [Example and validation coverage](Tasks/13-example-and-validation.md) | Example exercises every addition; validation guide lists the checks |
| 14 | [Peel drag preview](Tasks/14-peel-drag-preview.md) | Route drags can peel the route off the map joint by joint, up to its anchors |

## Not planned

- Marker `opacity`: the planner removes hidden markers from the array instead.
- A per-marker switch that lets taps pass through: every marker is a hit target, and the app maps a decorative marker's ID to the marker it covers in `onTap`.
- Callout press events, custom callout views, and marker drag: the planner does not use them.
- A `showsPointsOfInterest` toggle: on Google maps, hide POIs through `mapStyle`.
- Geometry utilities such as decode, simplify, distance, and bounds: they stay in the planner's JS.
- Planner integration: replacing the dependency, its config plugin, Reanimated wrapping, and touch handlers on the host view.
