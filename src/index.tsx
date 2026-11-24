import { useMemo } from 'react';
import { Image, type ImageRequireSource, type ViewProps } from 'react-native';
import { callback, getHostComponent } from 'react-native-nitro-modules';
import viewConfig from '../nitrogen/generated/shared/json/MapSurfaceConfig.json';
import type {
  DragPreview as NativeDragPreview,
  EdgePadding,
  InitialFit,
  MapCamera,
  MapCameraEvent,
  MapDragEvent,
  MapMarker as NativeMapMarker,
  MapOptions,
  MapPoiTap,
  MapRoute as NativeMapRoute,
  MapPoint,
  MapProvider,
  MapSurfaceMethods,
  MapSurfaceProps as NativeMapSurfaceProps,
  MapTap,
  MarkerImage,
  RouteAppearance as NativeRouteAppearance,
  RouteDrag as NativeRouteDrag,
} from './MapSurface.nitro';

export type { Coordinate, MarkerImage } from './MapSurface.nitro';
export type { CameraFit, CameraMove, CameraReveal, EdgePadding, InitialFit } from './MapSurface.nitro';
export type { MapCamera, MapCameraEvent, MapCameraPhase } from './MapSurface.nitro';
export type { MapDragEvent, MapDragPhase, MapFeatureHits, MapPoint, MapPoiTap, MapProvider, MapSurfaceMethods, MapTap, MapType } from './MapSurface.nitro';

/** A marker image: `{ uri, scale }` or a `require()` asset. */
export type ImageSource = MarkerImage | ImageRequireSource;
export type MapMarker = Omit<NativeMapMarker, 'image'> & { image?: ImageSource };
export type DragPreview = Omit<NativeDragPreview, 'image'> & { image?: ImageSource };
export type RouteDrag = Omit<NativeRouteDrag, 'preview'> & { preview?: DragPreview };
export type RouteAppearance = Omit<NativeRouteAppearance, 'drag'> & { drag?: RouteDrag };
export type MapRoute = Omit<NativeMapRoute, 'drag'> & { drag?: RouteDrag };

export type MapSurfaceProps = Omit<ViewProps, 'children'> & MapOptions & {
  children?: never;
  markers?: MapMarker[];
  routes?: MapRoute[];
  provider: MapProvider;
  /** The camera the map starts at. Read only when the map is created. */
  initialCamera?: MapCamera;
  /** Fits these coordinates on the first layout. Read only when the map is created. Wins over `initialCamera`. */
  initialFit?: InitialFit;
  onCameraMove?: (event: MapCameraEvent) => void;
  onReady?: () => void;
  onRendered?: () => void;
  onTap?: (event: MapTap) => void;
  /** Taps on the map's built-in points of interest. They do not also emit `onTap`. */
  onPoiTap?: (event: MapPoiTap) => void;
  pinDragEnabled?: boolean;
  /** Styles a standalone pin drag. */
  pinDragPreview?: DragPreview;
  /** Display points around a drop point that `onDrag` `end` searches for markers. Defaults to 0. */
  dropRadius?: number;
  onDrag?: (event: MapDragEvent) => void;
  onRef?: (ref: MapSurfaceMethods) => void;
};

const NativeMapSurface = getHostComponent<NativeMapSurfaceProps, MapSurfaceMethods>(
  'MapSurface',
  () => viewConfig,
);

const EMPTY_MARKERS: NativeMapMarker[] = Object.freeze([]) as unknown as NativeMapMarker[];
const EMPTY_ROUTES: NativeMapRoute[] = Object.freeze([]) as unknown as NativeMapRoute[];

/**
 * Each prop crosses into native code only when its identity changes. Keep `markers`, `routes`,
 * and event handlers stable (memoized arrays, `useCallback`) to avoid native work.
 */
export function MapSurface({
  markers, routes, initialCamera, initialFit, onCameraMove, onReady, onRendered, onTap, onPoiTap, onDrag, onRef, pinDragPreview,
  mapStyle, mapType, scrollEnabled, zoomEnabled, rotateEnabled, pitchEnabled, showsBuildings, showsIndoors,
  ...viewProps
}: MapSurfaceProps) {
  const options = useMemo<MapOptions>(
    () => ({ mapStyle, mapType, scrollEnabled, zoomEnabled, rotateEnabled, pitchEnabled, showsBuildings, showsIndoors }),
    [mapStyle, mapType, scrollEnabled, zoomEnabled, rotateEnabled, pitchEnabled, showsBuildings, showsIndoors],
  );
  const nativeMarkers = useMemo(() => (markers ? validateMarkers(resolveMarkerImages(markers)) : EMPTY_MARKERS), [markers]);
  const nativeRoutes = useMemo(() => (routes ? validateRoutes(resolveRoutePreviews(routes)) : EMPTY_ROUTES), [routes]);
  const nativePinDragPreview = useMemo(
    () => pinDragPreview && validatePreview(resolvePreview(pinDragPreview)),
    [pinDragPreview],
  );
  const nativeInitialCamera = useMemo(() => initialCamera && validateCamera(initialCamera), [initialCamera]);
  const nativeInitialFit = useMemo(() => initialFit && validateInitialFit(initialFit), [initialFit]);
  const nativeOnCameraMove = useMemo(() => onCameraMove && callback(onCameraMove), [onCameraMove]);
  const nativeOnReady = useMemo(() => onReady && callback(onReady), [onReady]);
  const nativeOnRendered = useMemo(() => onRendered && callback(onRendered), [onRendered]);
  const nativeOnTap = useMemo(() => onTap && callback(onTap), [onTap]);
  const nativeOnPoiTap = useMemo(() => onPoiTap && callback(onPoiTap), [onPoiTap]);
  const nativeOnDrag = useMemo(() => onDrag && callback(onDrag), [onDrag]);
  const nativeRef = useMemo(() => onRef && callback(onRef), [onRef]);
  return (
    <NativeMapSurface
      {...viewProps}
      markers={nativeMarkers}
      routes={nativeRoutes}
      options={options}
      initialCamera={nativeInitialCamera}
      initialFit={nativeInitialFit}
      onCameraMove={nativeOnCameraMove}
      onReady={nativeOnReady}
      onRendered={nativeOnRendered}
      onTap={nativeOnTap}
      onPoiTap={nativeOnPoiTap}
      onDrag={nativeOnDrag}
      pinDragPreview={nativePinDragPreview}
      hybridRef={nativeRef}
    />
  );
}

/** Resolves `require()` assets to `{ uri, scale }`; native code never sees asset numbers. */
function resolveMarkerImages(markers: MapMarker[]): NativeMapMarker[] {
  if (!markers.some((marker) => typeof marker.image === 'number')) return markers as NativeMapMarker[];
  return markers.map((marker) => ({ ...marker, image: resolveImage(marker.image) }));
}

function resolveRoutePreviews(routes: MapRoute[]): NativeMapRoute[] {
  if (!routes.some((route) => typeof route.drag?.preview?.image === 'number')) return routes as NativeMapRoute[];
  return routes.map((route) => {
    const preview = route.drag?.preview;
    if (!route.drag || !preview) return route as NativeMapRoute;
    return { ...route, drag: { ...route.drag, preview: resolvePreview(preview) } };
  });
}

function resolvePreview(preview: DragPreview): NativeDragPreview {
  return typeof preview.image === 'number' ? { ...preview, image: resolveImage(preview.image) } : preview as NativeDragPreview;
}

function resolveImage(image: ImageSource | undefined): MarkerImage | undefined {
  if (typeof image !== 'number') return image;
  const source = Image.resolveAssetSource(image);
  if (!source?.uri) throw new Error('Unresolvable marker image asset');
  return { uri: source.uri, scale: source.scale };
}

function validateImage(image: MarkerImage | undefined) {
  if (image && (!image.uri || (image.scale !== undefined && !positive(image.scale)))) {
    throw new Error('Invalid marker image source');
  }
}

function validateAnchor(anchor: MapPoint | undefined) {
  if (anchor && !(Number.isFinite(anchor.x) && Number.isFinite(anchor.y))) throw new Error('Anchor must be finite');
}

/** Shared by routes and drag previews. */
function validateStroke({ strokeColor, strokeWidth, dashPattern }: Pick<NativeDragPreview, 'strokeColor' | 'strokeWidth' | 'dashPattern'>) {
  if (strokeColor !== undefined && !/^#[\da-f]{6}([\da-f]{2})?$/i.test(strokeColor)) {
    throw new Error('strokeColor must be #RRGGBB or #RRGGBBAA');
  }
  if (strokeWidth !== undefined && (!positive(strokeWidth) || strokeWidth > 3.4028234663852886e38)) {
    throw new Error('strokeWidth must be positive and within the native float range');
  }
  if (dashPattern !== undefined && (dashPattern.length === 0 || dashPattern.length % 2 !== 0 || !dashPattern.every(positive))) {
    throw new Error('dashPattern must be a nonempty, even-length list of positive lengths');
  }
}

function validatePreview(preview: NativeDragPreview) {
  validateStroke(preview);
  validateImage(preview.image);
  validateAnchor(preview.anchor);
  return preview;
}

function validateMarkers(markers: NativeMapMarker[]) {
  validateIds(markers);
  for (const { coordinate, image, anchor, zIndex } of markers) {
    validateCoordinate(coordinate);
    validateAnchor(anchor);
    if (zIndex !== undefined && !Number.isFinite(zIndex)) throw new Error('Marker zIndex must be finite');
    validateImage(image);
  }
  return markers;
}

function validateRoutes(routes: NativeMapRoute[]) {
  validateIds(routes);
  for (const route of routes) {
    if (route.coordinates.length < 2) throw new Error('A route needs at least two coordinates');
    route.coordinates.forEach(validateCoordinate);
    if (route.drag) {
      if (route.drag.anchors.length === 0) throw new Error('A draggable route needs an anchor');
      route.drag.anchors.forEach(validateCoordinate);
      if (route.drag.preview) validatePreview(route.drag.preview);
    }
    validateStroke(route);
    if (route.zIndex !== undefined && !Number.isFinite(route.zIndex)) throw new Error('Route zIndex must be finite');
    if (route.hitSlop !== undefined && (!Number.isFinite(route.hitSlop) || route.hitSlop < 0)) {
      throw new Error('Route hitSlop must be finite and nonnegative');
    }
  }
  return routes;
}

function validateCamera(camera: MapCamera) {
  validateCoordinate(camera.center);
  if (!Number.isFinite(camera.zoom)) throw new Error('Camera zoom must be finite');
  return camera;
}

function validateInitialFit(fit: InitialFit) {
  if (fit.coordinates.length === 0) throw new Error('initialFit needs a coordinate');
  fit.coordinates.forEach(validateCoordinate);
  if (fit.padding) validatePadding(fit.padding);
  if (fit.maxZoom !== undefined && !Number.isFinite(fit.maxZoom)) throw new Error('maxZoom must be finite');
  return fit;
}

function validatePadding({ top, right, bottom, left }: EdgePadding) {
  if (![top, right, bottom, left].every((value) => Number.isFinite(value) && value >= 0)) {
    throw new Error('Padding must be finite and nonnegative');
  }
}

function validateIds(items: { id: string }[]) {
  const ids = new Set<string>();
  for (const { id } of items) {
    if (!id || ids.has(id)) throw new Error('Map feature IDs must be nonempty and unique within each collection');
    ids.add(id);
  }
}

function validateCoordinate({ latitude, longitude }: NativeMapMarker['coordinate']) {
  if (!(Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180)) {
    throw new Error('Map coordinate is out of range');
  }
}

function positive(value: number) {
  return Number.isFinite(value) && value > 0;
}
