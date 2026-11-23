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
  image?: MarkerImage;
}

export interface RouteDrag {
  anchors: Coordinate[];
}

export interface RouteAppearance {
  /** Hex RGB or RGBA, with a leading #. */
  strokeColor?: string;
  /** Width in display points. */
  strokeWidth?: number;
  zIndex?: number;
  /** A long press on this route draws a preview from each anchor to the pin. */
  drag?: RouteDrag;
}

export interface MapRoute extends RouteAppearance {
  id: string;
  coordinates: Coordinate[];
  /** Tap radius in display points. Zero or omitted disables route hits. */
  hitSlop?: number;
}

export interface MapFeatures {
  markers: MapMarker[];
  routes: MapRoute[];
}

export type MapProvider = 'apple' | 'google';

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

export type MapDragPhase = 'start' | 'move' | 'end' | 'cancel';

export interface MapDragEvent {
  phase: MapDragPhase;
  coordinate: Coordinate;
  point: MapPoint;
  routeId?: string;
}

export interface MapSurfaceProps extends HybridViewProps {
  features: MapFeatures;
  provider: MapProvider;
  onReady?: () => void;
  onRendered?: () => void;
  onTap?: (event: MapTap) => void;
  pinDragEnabled?: boolean;
  onDrag?: (event: MapDragEvent) => void;
}

export interface MapSurfaceMethods extends HybridViewMethods {
  setCamera(center: Coordinate, zoom: number, animated: boolean): Promise<void>;
  project(coordinate: Coordinate): Promise<MapPoint>;
  unproject(point: MapPoint): Promise<Coordinate>;
  takeSnapshot(): Promise<string>;
  cancelDrag(): Promise<void>;
}

export type MapSurface = HybridView<MapSurfaceProps, MapSurfaceMethods>;
