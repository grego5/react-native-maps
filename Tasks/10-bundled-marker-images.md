# 10 Bundled marker images

[Back to TASKS.md](../TASKS.md)

Status: Completed (Android debug and release builds and device checks not run: no phone. iOS not run: no Mac.)

## Objective

Accept `require()` image assets as marker images, so the planner's PNG pins work without copying them to files:

- Public `MapMarker.image` accepts `MarkerImage | ImageRequireSource`.
- JS resolves a `require` number to `{ uri, scale }` with `Image.resolveAssetSource` before it reaches native code.
- Android loads the URIs that resolution produces in release builds: bare drawable resource names such as `assets_icons_dot`.

## Non-goals

- Remote image headers, caching policy changes, or SVG.
- Changing the native `MarkerImage` struct.

## Read before editing

- `src/index.tsx`: `MapSurfaceProps`, `MapSurface`, `validateMarkers`.
- `src/MapSurface.nitro.ts`: `MapMarker` and `MarkerImage`. The native types stay unchanged.
- `android/.../MarkerImages.kt`: `load`, `decode` (scheme switch), and the size limit.
- `ios/MarkerImages.swift`: `load` (scheme check).

## Current behavior to preserve

- Accepted schemes:
  - Android: `https`, `http`, `file`, and `content`;
  - iOS: `https`, `http`, and `file`.
- Input is limited to 8 MiB and decoded at a bounded size. A failure leaves the default pin.
- `scale` is source pixels per display point.

What `require` resolves to:

| Build | Android | iOS |
| --- | --- | --- |
| Debug with Metro | `http://<host>:8081/assets/...?platform=android` | `http://<host>:8081/assets/...` |
| Release | bare resource name | `file:` URI inside the app bundle |

Debug and iOS release already load. Only Android release needs native work.

## Steps

1. `src/index.tsx`:
   - Define the public marker type as `Omit<MapMarker, 'image'> & { image?: MarkerImage | ImageRequireSource }`.
   - Export it as `MapMarker`, and keep exporting the native type under another name only if something else needs it.
   - In the markers `useMemo`, map markers whose `image` is a number to `{ ...marker, image: { uri, scale } }` from `Image.resolveAssetSource`. When resolution fails, throw `Error('Unresolvable marker image asset')`.
   - Validate after resolving.
2. Android `MarkerImages.decode`:
   - Add a branch for URIs with no scheme. Look up `context.resources.getIdentifier(uri, "drawable", context.packageName)` and fall back to `"raw"`. When the ID is 0, throw `FileNotFoundException`.
   - Read the bytes with `resources.openRawResource(id)` under the same 8 MiB limit, so density buckets do not rescale the bitmap. The `scale` from step 1 already describes the chosen bucket.
3. iOS: no change. Confirm in a release build that the bundle `file:` URI loads.
4. Docs:
   - In the marker images section of `docs/api.md`, add `require()` assets.
   - State that debug builds load them from Metro over `http:`. On Android, that needs cleartext traffic to the dev server, which React Native debug builds allow.

## Rules

- Resolution runs in JS only. Native code never sees asset numbers.
- Keep marker arrays referentially stable when the input is stable. The `useMemo` dependencies stay `[markers, routes]`.

## Tests

- Example: one marker using `require('./assets/pin.png')` at 1x, 2x, and 3x. Add the asset to the example.
- Android debug and release builds: the pin shows at the correct size (same display size as a `file:` copy with matching scale).
- iOS debug and release: the same check.
- An invalid asset throws in JS.

## Validation

- `npm run typecheck` (package and example).
- Android release build of the example (`npx expo run:android --variant release`, or the Gradle `assembleRelease` task), installed on a device.
- iOS release build on a Mac, or report not run.

## Completion criteria

- `require` assets render in debug and release on all providers.
- The docs are updated.

## Commit

`feat: accept bundled image assets as marker images`
