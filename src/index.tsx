import { useMemo } from 'react';
import type { ViewProps } from 'react-native';
import { callback, getHostComponent } from 'react-native-nitro-modules';
import viewConfig from '../nitrogen/generated/shared/json/MapSurfaceConfig.json';
import type {
  MapDragEvent,
  MapMarker,
  MapRoute,
  MapProvider,
  MapSurfaceMethods,
  MapSurfaceProps as NativeMapSurfaceProps,
  MapTap,
} from './MapSurface.nitro';

export type { Coordinate, MapMarker, MapRoute, MarkerImage, RouteAppearance, RouteDrag } from './MapSurface.nitro';
export type { MapDragEvent, MapDragPhase, MapPoint, MapProvider, MapSurfaceMethods, MapTap } from './MapSurface.nitro';

export type MapSurfaceProps = Omit<ViewProps, 'children'> & {
  children?: never;
  markers?: MapMarker[];
  routes?: MapRoute[];
  provider: MapProvider;
  onReady?: () => void;
  onRendered?: () => void;
  onTap?: (event: MapTap) => void;
  pinDragEnabled?: boolean;
  onDrag?: (event: MapDragEvent) => void;
  onRef?: (ref: MapSurfaceMethods) => void;
};

const NativeMapSurface = getHostComponent<NativeMapSurfaceProps, MapSurfaceMethods>(
  'MapSurface',
  () => viewConfig,
);

export function MapSurface({ markers, routes, onReady, onRendered, onTap, onDrag, onRef, ...viewProps }: MapSurfaceProps) {
  const features = useMemo(() => validateFeatures(markers ?? [], routes ?? []), [markers, routes]);
  return (
    <NativeMapSurface
      {...viewProps}
      features={features}
      onReady={onReady && callback(onReady)}
      onRendered={onRendered && callback(onRendered)}
      onTap={onTap && callback(onTap)}
      onDrag={onDrag && callback(onDrag)}
      hybridRef={onRef && callback(onRef)}
    />
  );
}

function validateFeatures(markers: MapMarker[], routes: MapRoute[]) {
  validateIds(markers);
  validateIds(routes);
  for (const { coordinate, image } of markers) {
    validateCoordinate(coordinate);
    if (image && (!image.uri || (image.scale !== undefined && !positive(image.scale)))) {
      throw new Error('Invalid marker image source');
    }
  }
  for (const route of routes) {
    if (route.coordinates.length < 2) throw new Error('A route needs at least two coordinates');
    route.coordinates.forEach(validateCoordinate);
    if (route.drag) {
      if (route.drag.anchors.length === 0) throw new Error('A draggable route needs an anchor');
      route.drag.anchors.forEach(validateCoordinate);
    }
    if (route.strokeColor !== undefined && !/^#[\da-f]{6}([\da-f]{2})?$/i.test(route.strokeColor)) {
      throw new Error('Route strokeColor must be #RRGGBB or #RRGGBBAA');
    }
    if (route.strokeWidth !== undefined && (!positive(route.strokeWidth) || route.strokeWidth > 3.4028234663852886e38)) {
      throw new Error('Route strokeWidth must be positive and within the native float range');
    }
    if (route.zIndex !== undefined && !Number.isFinite(route.zIndex)) throw new Error('Route zIndex must be finite');
    if (route.hitSlop !== undefined && (!Number.isFinite(route.hitSlop) || route.hitSlop < 0)) {
      throw new Error('Route hitSlop must be finite and nonnegative');
    }
  }
  return { markers, routes };
}

function validateIds(items: { id: string }[]) {
  const ids = new Set<string>();
  for (const { id } of items) {
    if (!id || ids.has(id)) throw new Error('Map feature IDs must be nonempty and unique within each collection');
    ids.add(id);
  }
}

function validateCoordinate({ latitude, longitude }: MapMarker['coordinate']) {
  if (!(Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180)) {
    throw new Error('Map coordinate is out of range');
  }
}

function positive(value: number) {
  return Number.isFinite(value) && value > 0;
}
