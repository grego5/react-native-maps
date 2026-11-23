# API

## Map surface

Keep markers and routes in application state and pass them to the mounted map. The surface accepts ordered arrays and updates native features by ID. Use nonempty IDs that are unique within each array. Pass new arrays when data changes. Omitted arrays are empty.

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

## Marker images

Set a marker's `image` to `{ uri, scale }`. Scale is source pixels per display point and defaults to 1. Use app-accessible `file:` URIs or `https:` URLs. `http:` depends on transport configuration, and Android also accepts `content:` URIs. Input is limited to 8 MiB and decoded at a bounded size.

The mounted surface loads marker images on demand and uses the default pin while loading or after a failure.

## Surface methods and events

Capture `MapSurfaceMethods` with `onRef`. Wait for `onReady` before using the ref for `setCamera`, `project`, `unproject`, `takeSnapshot`, and `cancelDrag`. A display snapshot requires a foreground view and a rendered frame.

`onReady` means the laid-out provider and initial features are available. `onRendered` means the provider reported its first fully rendered map. `onTap` reports the coordinate, screen point, optional marker ID, and matching route IDs.

Set `drag: { anchors }` with at least one anchor coordinate to make a route draggable. A long press on the route draws a temporary connector from each anchor to the preview point. Drag hit testing uses the route's `hitSlop` or 20 points when omitted. Zero disables drag hits. Enable `pinDragEnabled` to allow a standalone pin drag when the press misses all draggable routes.

`onDrag` reports `start`, `move`, `end`, and `cancel`, with the preview coordinate, point in display points, and optional route ID. The preview appears 32 points above the finger. Camera movement, a second finger, detachment, and `cancelDrag()` end an active gesture. Update your application state after `end` to persist the edit.
