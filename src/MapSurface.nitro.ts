import type { HybridView, HybridViewProps, HybridViewMethods } from 'react-native-nitro-modules';
export interface Coordinate {
  latitude: number;
  longitude: number;
}

export interface MarkerImage {
  uri: string;
  scale?: number;
}

export interface MapMarker {
  id: string;
  coordinate: Coordinate;
  title?: string;
  /** The callout's second line, under `title`. */
  description?: string;
  image?: MarkerImage;
  /** The image point placed on the coordinate, as fractions of the image size. Defaults to `{ x: 0.5, y: 1 }`. */
  anchor?: MapPoint;
  /** Markers draw from low to high; input order breaks ties. Defaults to 0. Markers always draw above routes. */
  zIndex?: number;
}

/** Styles the drag preview: connectors from each anchor and the pin at the lifted point. */
export interface DragPreview {
  /** Connector color, hex RGB or RGBA. Defaults to #007AFF. */
  strokeColor?: string;
  /** Connector width in display points. Defaults to 3. */
  strokeWidth?: number;
  /** Connector dash and gap lengths in display points. Omitted draws solid connectors. */
  dashPattern?: number[];
  /** Replaces the default 6-point circle. */
  image?: MarkerImage;
  /** The image point placed on the lifted point, as fractions of the image size. Defaults to `{ x: 0.5, y: 1 }`. */
  anchor?: MapPoint;
}

export interface RouteDrag {
  anchors: Coordinate[];
  preview?: DragPreview;
}

export interface RouteAppearance {
  /** Hex RGB or RGBA, with a leading #. */
  strokeColor?: string;
  /** Width in display points. */
  strokeWidth?: number;
  zIndex?: number;
  /** Alternating dash and gap lengths in display points. Omitted draws a solid line. */
  dashPattern?: number[];
  /** A long press on this route draws a preview from each anchor to the pin. */
  drag?: RouteDrag;
}

export interface MapRoute extends RouteAppearance {
  id: string;
  coordinates: Coordinate[];
  /** Tap radius in display points. Zero or omitted disables route hits. */
  hitSlop?: number;
}

export type MapProvider = 'apple' | 'google';

export type MapType = 'standard' | 'none';

export interface MapOptions {
  /** Google style JSON. Google maps only. */
  mapStyle?: string;
  /** `'none'` hides the base map on Google maps. */
  mapType?: MapType;
  scrollEnabled?: boolean;
  zoomEnabled?: boolean;
  rotateEnabled?: boolean;
  pitchEnabled?: boolean;
  showsBuildings?: boolean;
  /** Google maps only. */
  showsIndoors?: boolean;
}

export interface MapPoint {
  x: number;
  y: number;
}

export interface MapTap {
  coordinate: Coordinate;
  point: MapPoint;
  markerId?: string;
  routeIds: string[];
}

export interface MapPoiTap {
  /** Google Place ID on Google maps; the Apple map item identifier on MapKit (iOS 18+), when available. */
  placeId?: string;
  name: string;
  coordinate: Coordinate;
}

export type MapDragPhase = 'start' | 'move' | 'end' | 'cancel';

export interface MapDragEvent {
  phase: MapDragPhase;
  coordinate: Coordinate;
  point: MapPoint;
  /** The route whose anchors are previewed: `routeIds[0]`. */
  routeId?: string;
  /** Every draggable route under the press, nearest first; the same on every event of one drag. */
  routeIds: string[];
  /** On `end` only: markers within `dropRadius` of the drop point, nearest first. */
  markerIds: string[];
}

export interface MapFeatureHits {
  /** Markers whose coordinate lies within the radius, nearest first. */
  markerIds: string[];
  /** Routes within the larger of the radius and their `hitSlop`, nearest first. */
  routeIds: string[];
}

/** `zoom` uses Google zoom levels on every provider. */
export interface MapCamera {
  center: Coordinate;
  zoom: number;
}

export type MapCameraPhase = 'start' | 'idle';

export interface MapCameraEvent {
  phase: MapCameraPhase;
  camera: MapCamera;
}

/** Display points kept clear around the area a camera operation centers in. */
export interface EdgePadding {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export interface CameraMove {
  /** Milliseconds. Zero or omitted moves at once. */
  duration?: number;
  /** The camera centers in the area inside this padding. */
  padding?: EdgePadding;
}

export interface CameraFit {
  padding?: EdgePadding;
  /** The closest zoom the fit may use. */
  maxZoom?: number;
  /** Milliseconds. Zero or omitted moves at once. */
  duration?: number;
}

/** `pan` keeps the zoom; `fit` moves as `fitCoordinates` does. */
export type CameraReveal = 'none' | 'pan' | 'fit';

export interface InitialFit {
  coordinates: Coordinate[];
  padding?: EdgePadding;
  maxZoom?: number;
}

export interface MapSurfaceProps extends HybridViewProps {
  markers: MapMarker[];
  routes: MapRoute[];
  provider: MapProvider;
  options?: MapOptions;
  /** Read when the map is created. */
  initialCamera?: MapCamera;
  /** Read when the map is created and applied on its first layout. Wins over `initialCamera`. */
  initialFit?: InitialFit;
  onCameraMove?: (event: MapCameraEvent) => void;
  onReady?: () => void;
  onRendered?: () => void;
  onTap?: (event: MapTap) => void;
  /** Taps on the map's built-in points of interest. On MapKit, POIs are selectable only while this is set. */
  onPoiTap?: (event: MapPoiTap) => void;
  pinDragEnabled?: boolean;
  /** Styles a standalone pin drag. */
  pinDragPreview?: DragPreview;
  /** Display points around a drop point that `onDrag` `end` searches for markers. Defaults to 0, which reports none. */
  dropRadius?: number;
  onDrag?: (event: MapDragEvent) => void;
}

export interface MapSurfaceMethods extends HybridViewMethods {
  setCamera(center: Coordinate, zoom: number, move?: CameraMove): Promise<void>;
  getCamera(): Promise<MapCamera>;
  fitCoordinates(coordinates: Coordinate[], fit?: CameraFit): Promise<void>;
  revealCoordinates(coordinates: Coordinate[], fit?: CameraFit): Promise<CameraReveal>;
  cameraFor(coordinates: Coordinate[], fit?: CameraFit): Promise<MapCamera>;
  project(coordinate: Coordinate): Promise<MapPoint>;
  unproject(point: MapPoint): Promise<Coordinate>;
  takeSnapshot(): Promise<string>;
  cancelDrag(): Promise<void>;
  /** Markers and routes near a point in display points, nearest first. */
  queryFeatures(point: MapPoint, radius: number): Promise<MapFeatureHits>;
  /** Opens this marker's callout and closes any other. Rejects for an unknown ID. */
  showCallout(markerId: string): Promise<void>;
  hideCallout(): Promise<void>;
}

export type MapSurface = HybridView<MapSurfaceProps, MapSurfaceMethods>;
