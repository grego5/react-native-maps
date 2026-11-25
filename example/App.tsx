import { useCallback, useRef, useState, type ReactNode } from 'react';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import Constants from 'expo-constants';
import {
  Platform,
  Pressable,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  View,
  type LayoutChangeEvent,
} from 'react-native';
import {
  MapSurface,
  type DragPreview,
  type EdgePadding,
  type InitialFit,
  type MapCamera,
  type MapCameraEvent,
  type MapDragEvent,
  type MapMarker,
  type MapPoint,
  type MapPoiTap,
  type MapProvider,
  type MapRoute,
  type MapSurfaceMethods,
  type MapTap,
  type MapType,
} from 'react-native-maps';

const start = { latitude: 38.5, longitude: -120.2 };
const imageURI = process.env.EXPO_PUBLIC_TEST_IMAGE;
const pin = require('./assets/pin.png');
const canSwitchProvider = Platform.OS === 'ios' && Constants.expoConfig?.extra?.googleIOS === true;
const initialProvider: MapProvider =
  Platform.OS === 'android' || (canSwitchProvider && process.env.EXPO_PUBLIC_PROVIDER === 'google')
    ? 'google'
    : 'apple';

// Markers: the start pin plus a stack for anchor, zIndex, callout, and require() checks.
const startMarker: MapMarker = {
  id: 'start',
  coordinate: start,
  title: 'Route start',
  image: imageURI ? { uri: imageURI, scale: 2 } : undefined,
};
// `top` draws above `middle`, which draws above `bottom` (equal zIndex, input order).
const stackMarkers: MapMarker[] = [
  {
    id: 'top',
    coordinate: { latitude: 39.2, longitude: -120.6 },
    title: 'A: zIndex 2',
    description: 'Tap opens this callout',
    zIndex: 2,
  },
  {
    id: 'middle',
    coordinate: { latitude: 39.19, longitude: -120.61 },
    title: 'B: zIndex 1, first',
    description: 'Opened from the button',
    zIndex: 1,
  },
  {
    id: 'bottom',
    coordinate: { latitude: 39.18, longitude: -120.62 },
    title: 'zIndex 1, second',
    zIndex: 1,
  },
  {
    id: 'bundled',
    coordinate: { latitude: 39.6, longitude: -121.2 },
    title: 'require() asset',
    image: pin,
  },
  {
    id: 'dot',
    coordinate: { latitude: 39.0, longitude: -120.9 },
    title: 'Centered',
    anchor: { x: 0.5, y: 0.5 },
    image: imageURI ? { uri: imageURI, scale: 2 } : undefined,
  },
];

// Camera: the map opens fitted above a 200-point bottom sheet; `initialFit` wins over `initialCamera`.
const coordinates = [
  start,
  { latitude: 40.7, longitude: -120.95 },
  { latitude: 43.252, longitude: -126.453 },
];
const initialCamera: MapCamera = { center: start, zoom: 6 };
const sheetPadding: EdgePadding = { top: 40, right: 20, bottom: 200, left: 20 };
const initialFit: InitialFit = { coordinates, padding: sheetPadding, maxZoom: 15 };
const sheetFit = { padding: sheetPadding, maxZoom: 15, duration: 300 };
const farPair = [start, { latitude: 47.6, longitude: -122.3 }];
const describeCamera = ({ center, zoom }: MapCamera) =>
  `${center.latitude.toFixed(4)}, ${center.longitude.toFixed(4)} z${zoom.toFixed(2)}`;

// Routes: overlapping draggable routes with a styled preview, and a dashed connector.
const routePreview: DragPreview = {
  strokeColor: '#FF3B30',
  strokeWidth: 4,
  dashPattern: [6, 4],
  image: pin,
};
const pinDragPreview: DragPreview = {
  strokeColor: '#5856D6',
  image: imageURI ? { uri: imageURI, scale: 2 } : undefined,
  anchor: { x: 0.5, y: 0.5 },
};
const routes: MapRoute[] = [
  {
    id: 'route',
    coordinates,
    hitSlop: 18,
    strokeColor: '#FF9500',
    strokeWidth: 5,
    zIndex: 1,
    drag: { anchors: [start], preview: routePreview },
  },
  // Overlaps `route`, so a drag on the shared line reports both IDs.
  {
    id: 'route-outline',
    coordinates,
    strokeColor: '#71368A',
    strokeWidth: 10,
    drag: { anchors: [coordinates[2]] },
  },
  {
    id: 'connector',
    coordinates: [start, { latitude: 37.8, longitude: -122.4 }],
    strokeColor: '#34C759',
    strokeWidth: 4,
    dashPattern: [8, 6],
  },
];

const solidRoutes = routes.map(({ dashPattern: _, ...route }) => route);

const hidePoiStyle = JSON.stringify([{ featureType: 'poi', stylers: [{ visibility: 'off' }] }]);
const toPoint = ({ latitude, longitude }: MapTap['coordinate']) =>
  `${latitude.toFixed(4)}, ${longitude.toFixed(4)}`;

const sections = ['Surface', 'Options', 'Camera', 'Markers', 'Routes', 'Hits', 'Events'] as const;

export default function App() {
  return (
    <SafeAreaProvider>
      <StatusBar barStyle="dark-content" />
      <SafeAreaView style={styles.screen}>
        <MapDemo />
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

function MapDemo() {
  const [panelOpen, setPanelOpen] = useState(false);
  const [section, setSection] = useState<(typeof sections)[number]>('Surface');
  const [map, setMap] = useState<MapSurfaceMethods>();
  const [visible, setVisible] = useState(true);
  const [provider, setProvider] = useState<MapProvider>(initialProvider);
  const [status, setStatus] = useState('Waiting for map');
  const [timing, setTiming] = useState('');
  const startedMount = useRef(performance.now());
  const mapSize = useRef({ width: 0, height: 0 });
  const moveStarted = useRef(0);
  const lastTapPoint = useRef<MapPoint | undefined>(undefined);

  // Options
  const [poisHidden, setPoisHidden] = useState(false);
  const [mapType, setMapType] = useState<MapType>('standard');
  const [panLocked, setPanLocked] = useState(false);
  const [zoomLocked, setZoomLocked] = useState(false);
  const [tiltLocked, setTiltLocked] = useState(false);
  const [buildings, setBuildings] = useState(true);
  const [indoors, setIndoors] = useState(true);
  // Markers and routes
  const [markers, setMarkers] = useState([startMarker]);
  const [dashed, setDashed] = useState(true);
  // Events
  const [tapEvent, setTapEvent] = useState('none');
  const [poiEvent, setPoiEvent] = useState('none');
  const [dragEvent, setDragEvent] = useState('none');
  const [cameraEvent, setCameraEvent] = useState('none');

  const report = useCallback((error: unknown) => setStatus(String(error)), []);
  const onMapLayout = useCallback(({ nativeEvent: { layout } }: LayoutChangeEvent) => {
    mapSize.current = layout;
  }, []);
  // Stable handlers and module-level arrays: a marker change sends only markers to native code.
  const onReady = useCallback(() => {
    setStatus('Map ready');
    setTiming(`Ready in ${Math.round(performance.now() - startedMount.current)} ms`);
  }, []);
  const onRendered = useCallback(() => {
    const elapsed = Math.round(performance.now() - startedMount.current);
    setTiming((previous) => `${previous} · Rendered in ${elapsed} ms`);
  }, []);
  const onTap = useCallback(({ markerId, routeIds, coordinate, point }: MapTap) => {
    lastTapPoint.current = point;
    setTapEvent(
      `${markerId ? `marker ${markerId}` : toPoint(coordinate)} routes [${routeIds.join(', ')}]`,
    );
  }, []);
  const onPoiTap = useCallback(({ name, placeId }: MapPoiTap) => {
    setPoiEvent(`${name} (${placeId ?? 'no placeId'})`);
  }, []);
  const onDrag = useCallback(({ phase, routeId, routeIds, markerIds }: MapDragEvent) => {
    if (phase === 'move') return;
    const near = phase === 'end' ? ` near [${markerIds.join(', ')}]` : '';
    setDragEvent(`${routeId ?? 'pin'} ${phase} on [${routeIds.join(', ')}]${near}`);
  }, []);
  const onCameraMove = useCallback(({ phase, camera }: MapCameraEvent) => {
    if (phase === 'start') moveStarted.current = performance.now();
    const elapsed =
      phase === 'idle' ? ` after ${Math.round(performance.now() - moveStarted.current)} ms` : '';
    setCameraEvent(`${phase} ${describeCamera(camera)}${elapsed}`);
  }, []);

  const withMap = (action: (ref: MapSurfaceMethods) => Promise<string | void>) => () => {
    if (!map) {
      setStatus('Map ref unavailable');
      return;
    }
    action(map).then((message) => message && setStatus(message), report);
  };

  return (
    <>
      <View style={styles.mapFrame}>
        {visible && (
          <MapSurface
            provider={provider}
            markers={markers}
            routes={dashed ? routes : solidRoutes}
            style={styles.map}
            onLayout={onMapLayout}
            onRef={setMap}
            initialCamera={initialCamera}
            initialFit={initialFit}
            onCameraMove={onCameraMove}
            onReady={onReady}
            onRendered={onRendered}
            onTap={onTap}
            onPoiTap={onPoiTap}
            pinDragEnabled
            pinDragPreview={pinDragPreview}
            dropRadius={48}
            onDrag={onDrag}
            mapStyle={poisHidden ? hidePoiStyle : undefined}
            mapType={mapType}
            scrollEnabled={!panLocked}
            rotateEnabled={!panLocked}
            zoomEnabled={!zoomLocked}
            pitchEnabled={!tiltLocked}
            showsBuildings={buildings}
            showsIndoors={indoors}
          />
        )}
        {!visible && <Text style={styles.emptyMap}>Map detached</Text>}
      </View>
      <View style={styles.toolbar}>
        <Button
          title={panelOpen ? 'Hide controls' : 'Test controls'}
          selected={panelOpen}
          onPress={() => setPanelOpen(!panelOpen)}
        />
      </View>
      {panelOpen && (
        <View style={styles.panel}>
          <View style={styles.tabs}>
            {sections.map((name) => (
              <Button
                key={name}
                title={name}
                selected={section === name}
                onPress={() => setSection(name)}
              />
            ))}
          </View>
          <ScrollView key={section} style={styles.controls} contentContainerStyle={styles.section}>
            {section === 'Surface' && (
              <>
                {canSwitchProvider && (
                  <Button
                    title={provider === 'apple' ? 'Use Google Maps' : 'Use Apple Maps'}
                    onPress={() => {
                      setStatus('Waiting for map');
                      startedMount.current = performance.now();
                      setTiming('');
                      setProvider(provider === 'apple' ? 'google' : 'apple');
                    }}
                  />
                )}
                <Button
                  title={visible ? 'Detach map' : 'Attach map'}
                  onPress={() => {
                    setMap(undefined);
                    setStatus(visible ? 'Map detached' : 'Waiting for map');
                    setTiming('');
                    startedMount.current = performance.now();
                    setVisible(!visible);
                  }}
                />
                <Button title="Run ref checks" onPress={withMap(runRefChecks)} />
              </>
            )}

            {section === 'Options' && (
              <>
                <Row>
                  <Button
                    title={poisHidden ? 'Show POIs' : 'Hide POIs'}
                    onPress={() => setPoisHidden(!poisHidden)}
                  />
                  <Button
                    title={mapType === 'none' ? 'Standard map' : 'No base map'}
                    onPress={() => setMapType(mapType === 'none' ? 'standard' : 'none')}
                  />
                </Row>
                <Row>
                  <Button
                    title={panLocked ? 'Unlock pan' : 'Lock pan'}
                    onPress={() => setPanLocked(!panLocked)}
                  />
                  <Button
                    title={zoomLocked ? 'Unlock zoom' : 'Lock zoom'}
                    onPress={() => setZoomLocked(!zoomLocked)}
                  />
                </Row>
                <Row>
                  <Button
                    title={tiltLocked ? 'Unlock tilt' : 'Lock tilt'}
                    onPress={() => setTiltLocked(!tiltLocked)}
                  />
                  <Button
                    title={buildings ? 'Hide buildings' : 'Show buildings'}
                    onPress={() => setBuildings(!buildings)}
                  />
                  <Button
                    title={indoors ? 'Hide indoors' : 'Show indoors'}
                    onPress={() => setIndoors(!indoors)}
                  />
                </Row>
              </>
            )}

            {section === 'Camera' && (
              <>
                <Button
                  title="Run camera checks"
                  onPress={withMap((ref) => runCameraChecks(ref, mapSize.current))}
                />
                <Row>
                  <Button
                    title="Read camera"
                    onPress={withMap(
                      async (ref) => `Camera ${describeCamera(await ref.getCamera())}`,
                    )}
                  />
                  <Button
                    title="Camera for route"
                    onPress={withMap(
                      async (ref) =>
                        `cameraFor ${describeCamera(await ref.cameraFor(coordinates, sheetFit))}`,
                    )}
                  />
                </Row>
                <Row>
                  <Button
                    title="Start above sheet"
                    onPress={withMap((ref) =>
                      ref.setCamera(start, 12, { padding: sheetPadding, duration: 300 }),
                    )}
                  />
                  <Button
                    title="Slow move (1 s)"
                    onPress={withMap((ref) => ref.setCamera(coordinates[1], 9, { duration: 1000 }))}
                  />
                </Row>
                <Row>
                  <Button
                    title="Fit route"
                    onPress={withMap((ref) => ref.fitCoordinates(coordinates, sheetFit))}
                  />
                  <Button
                    title="Reveal far pair"
                    onPress={withMap(
                      async (ref) => `Reveal: ${await ref.revealCoordinates(farPair, sheetFit)}`,
                    )}
                  />
                </Row>
              </>
            )}

            {section === 'Markers' && (
              <>
                <Row>
                  <Button
                    title="Show stack"
                    onPress={() => setMarkers([startMarker, ...stackMarkers])}
                  />
                  <Button
                    title="Move all"
                    onPress={() =>
                      setMarkers((current) =>
                        current.map((marker) => ({
                          ...marker,
                          coordinate: {
                            latitude: marker.coordinate.latitude + 0.05,
                            longitude: marker.coordinate.longitude,
                          },
                        })),
                      )
                    }
                  />
                </Row>
                <Row>
                  <Button
                    title="Callout on B"
                    onPress={withMap((ref) => ref.showCallout('middle'))}
                  />
                  <Button
                    title="Hide callout"
                    onPress={withMap((ref) =>
                      ref
                        .hideCallout()
                        .then(() => ref.showCallout('missing'))
                        .then(
                          () => 'showCallout(missing) resolved',
                          () => 'Callout hidden; missing ID rejected',
                        ),
                    )}
                  />
                </Row>
                <Row>
                  <Button
                    title="Remove B"
                    onPress={() =>
                      setMarkers((current) => current.filter((marker) => marker.id !== 'middle'))
                    }
                  />
                  <Button title="Clear demo pins" onPress={() => setMarkers([])} />
                  <Button title="Restore" onPress={() => setMarkers([startMarker])} />
                </Row>
              </>
            )}

            {section === 'Routes' && (
              <>
                <Row>
                  <Button
                    title={dashed ? 'Solid connector' : 'Dashed connector'}
                    onPress={() => setDashed(!dashed)}
                  />
                </Row>
                <Text style={styles.detail}>
                  Hold the orange route or an empty spot on the map to start a drag.
                </Text>
              </>
            )}

            {section === 'Hits' && (
              <>
                <Row>
                  <Button
                    title="Query last tap"
                    onPress={withMap(async (ref) => {
                      const point = lastTapPoint.current;
                      if (!point) return 'Tap the map first';
                      const { markerIds, routeIds } = await ref.queryFeatures(point, 24);
                      return `Markers [${markerIds.join(', ')}] routes [${routeIds.join(', ')}]`;
                    })}
                  />
                  <Button
                    title="Query at start"
                    onPress={withMap(async (ref) => {
                      const { markerIds, routeIds } = await ref.queryFeatures(
                        await ref.project(start),
                        24,
                      );
                      return `Markers [${markerIds.join(', ')}] routes [${routeIds.join(', ')}]`;
                    })}
                  />
                </Row>
              </>
            )}

            {section === 'Events' && (
              <>
                <EventRow label="Tap" value={tapEvent} />
                <EventRow label="Point of interest" value={poiEvent} />
                <EventRow label="Drag" value={dragEvent} />
                <EventRow label="Camera" value={cameraEvent} />
              </>
            )}
          </ScrollView>
          <View style={styles.result}>
            <Text style={styles.resultText} numberOfLines={3} selectable>
              {status}
            </Text>
            {section === 'Events' && timing !== '' && <Text style={styles.detail}>{timing}</Text>}
          </View>
        </View>
      )}
    </>
  );
}

function Button({
  title,
  onPress,
  primary,
  selected,
  disabled,
}: {
  title: string;
  onPress: () => void;
  primary?: boolean;
  selected?: boolean;
  disabled?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ selected, disabled }}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        styles.button,
        primary && styles.primary,
        selected && styles.selected,
        (pressed || disabled) && styles.faded,
      ]}>
      <Text style={[styles.buttonText, primary && styles.primaryText]}>{title}</Text>
    </Pressable>
  );
}

function EventRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.event}>
      <Text style={styles.eventLabel}>{label}</Text>
      <Text style={styles.detail} selectable>
        {value === 'none' ? 'No event yet' : value}
      </Text>
    </View>
  );
}

function Row({ children }: { children: ReactNode }) {
  return <View style={styles.row}>{children}</View>;
}

async function runRefChecks(map: MapSurfaceMethods) {
  await map.setCamera(start, 12);
  const current = await map.getCamera();
  if (
    Math.abs(current.center.latitude - start.latitude) > 1e-6 ||
    Math.abs(current.center.longitude - start.longitude) > 1e-6 ||
    Math.abs(current.zoom - 12) > 0.01
  ) {
    throw new Error(`getCamera returned ${describeCamera(current)}`);
  }
  const result = await map.unproject(await map.project(start));
  if (
    Math.abs(result.latitude - start.latitude) > 0.001 ||
    Math.abs(result.longitude - start.longitude) > 0.001
  ) {
    throw new Error('Projection round trip exceeded screen precision');
  }
  const uri = await map.takeSnapshot().catch((error: unknown) => {
    throw new Error(`Camera and projection passed. Snapshot failed: ${String(error)}`);
  });
  if (!uri.startsWith('file:')) throw new Error('Snapshot did not return a file URI');
  return 'Camera, projection, and snapshot passed';
}

async function runCameraChecks(
  map: MapSurfaceMethods,
  { width, height }: { width: number; height: number },
) {
  const fit = { padding: sheetPadding, maxZoom: 15 };
  const expected = await map.cameraFor(coordinates, fit);
  await map.fitCoordinates(coordinates, fit);
  const fitted = await map.getCamera();
  if (
    Math.abs(fitted.center.latitude - expected.center.latitude) > 1e-6 ||
    Math.abs(fitted.center.longitude - expected.center.longitude) > 1e-6 ||
    Math.abs(fitted.zoom - expected.zoom) > 0.001
  ) {
    throw new Error(`fit ${describeCamera(fitted)} != cameraFor ${describeCamera(expected)}`);
  }
  for (const coordinate of coordinates) {
    const { x, y } = await map.project(coordinate);
    if (
      y > height - sheetPadding.bottom + 1 ||
      y < sheetPadding.top - 1 ||
      x < sheetPadding.left - 1 ||
      x > width - sheetPadding.right + 1
    ) {
      throw new Error(
        `Fitted coordinate at ${x.toFixed(1)}, ${y.toFixed(1)} is outside the padded area`,
      );
    }
  }

  await map.setCamera(start, 14, { padding: { top: 0, right: 0, bottom: 300, left: 0 } });
  const above = await map.project(start);
  if (Math.abs(above.y - (height - 300) / 2) > 1 || Math.abs(above.x - width / 2) > 1) {
    throw new Error(`Padded center at ${above.x.toFixed(1)}, ${above.y.toFixed(1)}`);
  }

  await map.setCamera(start, 10);
  if ((await map.revealCoordinates([start], fit)) !== 'none')
    throw new Error('Onscreen reveal moved');
  const hidden = await map.unproject({ x: width / 2, y: height - 100 });
  const before = await map.getCamera();
  if ((await map.revealCoordinates([hidden], fit)) !== 'pan')
    throw new Error('Reveal under the sheet did not pan');
  const panned = await map.getCamera();
  if (Math.abs(panned.zoom - before.zoom) > 0.01) throw new Error('Reveal pan changed the zoom');
  const shown = await map.project(hidden);
  if (Math.abs(shown.y - (height - sheetPadding.bottom)) > 1.5)
    throw new Error(`Revealed point at y ${shown.y.toFixed(1)}`);
  if ((await map.revealCoordinates(farPair, fit)) !== 'fit')
    throw new Error('Far reveal did not fit');

  const settled = await map.getCamera();
  const rejected = await map.fitCoordinates([], fit).then(
    () => false,
    () => true,
  );
  const after = await map.getCamera();
  if (
    !rejected ||
    after.zoom !== settled.zoom ||
    after.center.latitude !== settled.center.latitude
  ) {
    throw new Error('An empty fit did not reject cleanly');
  }
  return `Camera checks passed (fit z${expected.zoom.toFixed(2)})`;
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#F7F9FC' },
  mapFrame: { flex: 1, backgroundColor: '#E8EDF4', justifyContent: 'center' },
  map: StyleSheet.absoluteFill,
  emptyMap: { textAlign: 'center', color: '#34465D', fontSize: 16 },
  toolbar: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  panel: { maxHeight: '42%', borderTopWidth: StyleSheet.hairlineWidth, borderColor: '#BCC9D8' },
  tabs: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 4,
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  controls: { flexGrow: 0, flexShrink: 1, backgroundColor: '#FFFFFF' },
  section: { padding: 12, gap: 8 },
  row: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  button: {
    minHeight: 44,
    justifyContent: 'center',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 10,
    backgroundColor: '#E8EEF6',
  },
  primary: { backgroundColor: '#174795' },
  selected: { backgroundColor: '#C9DCF8' },
  faded: { opacity: 0.55 },
  buttonText: { color: '#172B46', fontSize: 14, fontWeight: '600' },
  primaryText: { color: '#FFFFFF' },
  detail: { color: '#34465D', fontSize: 14, lineHeight: 20 },
  event: { gap: 3, paddingVertical: 6 },
  eventLabel: { color: '#172B46', fontWeight: '700' },
  result: { paddingHorizontal: 16, paddingVertical: 8, gap: 4 },
  resultText: { color: '#172B46', fontSize: 14, fontWeight: '600' },
});

