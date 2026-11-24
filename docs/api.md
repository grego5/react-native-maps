# API

## Map surface

Keep markers and routes in application state and pass them to the mounted map. The surface accepts ordered arrays and updates native features by ID. Use nonempty IDs that are unique within each array. Pass new arrays when data changes. Omitted arrays are empty.

`markers` and `routes` are separate native props. Each one crosses into native code, and is reconciled, only when its array identity changes. Memoize both arrays so a marker change does no route work, and keep event handlers stable with `useCallback`: the wrapper reuses its native callback while the handler is the same function.

```tsx
import { MapSurface, type MapMarker } from '@grego5/react-native-maps';

const markers: MapMarker[] = [
  { id: 'station', coordinate: { latitude: 37.78, longitude: -122.42 } },
];

export function MapScreen() {
  return <MapSurface provider="google" markers={markers} style={{ flex: 1 }} />;
}
```

Use `provider="apple"` for MapKit on iOS. Google Maps is supported on Android and requires the optional Google Maps build on iOS.

## Route styling

Pass decoded coordinates in each route's `coordinates` array, with at least two points.

Routes accept `strokeColor` as `#RRGGBB` or `#RRGGBBAA`, `strokeWidth` in display points, and `zIndex`. The defaults are blue, four points, and zero. Routes draw from low to high `zIndex`, preserving session order for equal values. `hitSlop` controls the route tap radius in display points. Zero or omission disables route taps.

`dashPattern` lists alternating dash and gap lengths in display points, for example `[8, 6]`. It must be a nonempty, even-length list of positive lengths; omit it for a solid line. Changing it updates the existing line in place. Google maps on iOS draws dashes as geographic lengths, so they are rescaled to display points when the camera settles, and they stretch or shrink during a zoom gesture.

## Marker callouts

`title` and `description` fill the native callout: the Google info window or the MapKit callout. Tapping a marker with a `title` opens its callout, and a marker tap never moves the camera on any provider. `showCallout(markerId)` opens a marker's callout and closes any other; it rejects for an unknown ID. `hideCallout()` closes the open callout. The SDK's selection is the only callout state, and removing a marker closes its callout.

## Marker placement and order

| Field | Default | Behavior |
| --- | --- | --- |
| `anchor` | `{ x: 0.5, y: 1 }` | The image point placed on the coordinate, as fractions of the image size. Bottom center by default; use `{ x: 0.5, y: 0.5 }` for a centered dot. Values outside 0 to 1 are allowed. |
| `zIndex` | `0` | Markers draw from low to high. Equal values draw in input order. Markers always draw above routes. |

## Marker images

Set a marker's `image` to `{ uri, scale }`. Scale is source pixels per display point and defaults to 1. Use app-accessible `file:` URIs or `https:` URLs. `http:` depends on transport configuration, and Android also accepts `content:` URIs. Input is limited to 8 MiB and decoded at a bounded size.

The mounted surface loads marker images on demand and uses the default pin while loading or after a failure.


`image` also accepts a `require()` asset, such as `require('./pin.png')` with `@2x` and `@3x` variants. The wrapper resolves it with `Image.resolveAssetSource` to `{ uri, scale }` before it reaches native code, and throws for an asset it cannot resolve. Debug builds load assets from Metro over `http:`, which React Native debug builds allow on Android. Android release builds resolve to bundled resource names, which the native loader reads without density rescaling. iOS release builds resolve to `file:` URIs in the app bundle.

## Map options

| Prop | Default | Providers |
| --- | --- | --- |
| `mapStyle` | SDK default | Google only. A Google style JSON string. An invalid style logs a warning and keeps the default style. |
| `mapType` | `'standard'` | `'none'` hides the base map on Google only. MapKit always shows the standard map. |
| `scrollEnabled`, `zoomEnabled`, `rotateEnabled`, `pitchEnabled` | `true` | All |
| `showsBuildings` | `true` | All |
| `showsIndoors` | `true` | Google only |

A route or pin drag on iOS suspends camera gestures. Releasing the drag restores the latest gesture props, including changes made during the drag. The Google Android map toolbar is always off.

## Camera

`MapCamera` is `{ center, zoom }`. Zoom uses Google zoom levels on every provider; MapKit converts with 256-point tiles. The camera is always north-up and flat.

- `initialCamera` sets the camera the map shows on its first frame. It is read only when the native map is created, including after a provider switch or reattach; later changes are ignored. Use `setCamera` to move an existing map.
- `initialFit: { coordinates, padding?, maxZoom? }` fits the coordinates on the map's first nonempty layout, before `onReady`. It is read when the native map is created, like `initialCamera`, and wins when both are set. An invalid fit, such as padding that leaves no area, logs a warning and keeps the default camera.
- `getCamera()` resolves the current camera.
- `onCameraMove` reports `{ phase, camera }`. `start` arrives once when the camera starts moving, from a gesture or an animation, and `idle` arrives once when it stops. SDKs that report several starts during one movement still produce one `start` per `idle`. No per-frame events are sent. Events stop when the surface detaches.

Camera methods compute their target natively from the view size and the current camera. `EdgePadding` is `{ top, right, bottom, left }` in display points. It is used only for that one calculation and is never set on the SDK, so map controls and later operations are unaffected. Durations are in milliseconds; zero or omitted moves at once. Use `onCameraMove` `idle` to wait for an animation to finish.

| Method | Behavior |
| --- | --- |
| `setCamera(center, zoom, { duration?, padding? })` | Puts `center` at the middle of the area inside `padding`, at `zoom`. |
| `fitCoordinates(coordinates, { padding?, maxZoom?, duration? })` | Moves to the closest zoom, at most `maxZoom`, that shows every coordinate inside the padded area, centered there. A single coordinate keeps the current zoom, capped by `maxZoom`. Longitude spans across the antimeridian stay contiguous. |
| `cameraFor(coordinates, fit?)` | Resolves the camera `fitCoordinates` would move to, without moving. |
| `revealCoordinates(coordinates, fit?)` | Resolves `'none'` without moving when every coordinate is already inside the padded area, `'pan'` after the smallest pan that brings them inside at the current zoom, or `'fit'` after a fit when they do not fit at the current zoom. `'none'` does not cancel a drag. |

Every operation keeps the camera north-up and flat, and all providers compute the same camera for the same input. Moving operations cancel an active drag. An empty coordinate list, an invalid coordinate, non-finite or negative padding, a negative duration, a non-finite `maxZoom`, or padding that leaves no area rejects before the camera moves. On MapKit, a nonzero duration animates the visible region inside a `UIView` animation; this has not yet been checked on a simulator.

## Surface methods and events

Capture `MapSurfaceMethods` with `onRef`. Wait for `onReady` before using the ref for camera methods, `project`, `unproject`, `takeSnapshot`, and `cancelDrag`. A display snapshot requires a foreground view and a rendered frame.

`onPoiTap` reports taps on the map's built-in points of interest as `{ placeId?, name, coordinate }`. A POI tap does not also emit `onTap`, and none arrives during an active drag. On Google maps, `placeId` is the Google Place ID. On MapKit it is the Apple map item identifier, resolved on iOS 18 and later and omitted on iOS 16 and 17; it is not a Google ID. MapKit makes POIs selectable only while `onPoiTap` is set, and closes its POI card at once.

`onReady` means the laid-out provider and initial features are available. `onRendered` means the provider reported its first fully rendered map. `onTap` reports the coordinate, screen point, optional marker ID, and matching route IDs.

Set `drag: { anchors }` with at least one anchor coordinate to make a route draggable. A long press on the route draws a temporary connector from each anchor to the preview point. Drag hit testing uses the route's `hitSlop` or 20 points when omitted. Zero disables drag hits. Enable `pinDragEnabled` to allow a standalone pin drag when the press misses all draggable routes.

Style the drag preview with `drag.preview` on a route and `pinDragPreview` on the surface for a standalone pin drag. `DragPreview` takes `strokeColor`, `strokeWidth`, and `dashPattern` for the connectors, with the same rules as routes, plus `image` (`{ uri, scale }` or a `require()` asset) and `anchor` for the pin at the lifted point. The defaults are a solid `#007AFF` connector three points wide and a filled circle with a six-point radius; the default anchor is the image's bottom center. Preview images load when the previews change, so a drag that starts before its image loads draws the circle. A change to a route's `preview` alone does not cancel its drag; the drag keeps the preview it started with.

`onDrag` reports `start`, `move`, `end`, and `cancel`, with the preview coordinate, point in display points, and optional route ID. The preview appears 32 points above the finger. Camera movement, a second finger, detachment, and `cancelDrag()` end an active gesture. Update your application state after `end` to persist the edit.

Each drag event also carries `routeIds`: every draggable route under the press, nearest first, fixed for the whole drag; `routeId` is its first entry. On `end`, `markerIds` lists the markers whose coordinate lies within `dropRadius` display points of the drop point, nearest first; it is empty on other phases and when `dropRadius` is 0, the default. Ties keep input order.

`queryFeatures(point, radius)` resolves `{ markerIds, routeIds }` near a point in display points: markers whose coordinate lies within `radius`, and routes within the larger of `radius` and their `hitSlop`, draggable or not. Both lists are nearest first. A marker's coordinate is its anchor point, so image bounds do not count. A negative or non-finite radius rejects.
