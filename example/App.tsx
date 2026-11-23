import { useRef, useState } from 'react';
import Constants from 'expo-constants';
import { Button, Platform, StyleSheet, Text, View } from 'react-native';
import {
  MapSurface,
  type MapMarker, type MapProvider, type MapRoute, type MapSurfaceMethods,
} from 'react-native-maps';

const start = { latitude: 38.5, longitude: -120.2 };
const imageURI = process.env.EXPO_PUBLIC_TEST_IMAGE;
const startMarker: MapMarker = {
  id: 'start',
  coordinate: start,
  title: 'Route start',
  image: imageURI ? { uri: imageURI, scale: 2 } : undefined,
};
const canSwitchProvider = Platform.OS === 'ios' && Constants.expoConfig?.extra?.googleIOS === true;
const initialProvider: MapProvider =
  Platform.OS === 'android' || (canSwitchProvider && process.env.EXPO_PUBLIC_PROVIDER === 'google')
    ? 'google' : 'apple';
const coordinates = [start, { latitude: 40.7, longitude: -120.95 }, { latitude: 43.252, longitude: -126.453 }];
const routes: MapRoute[] = [
  { id: 'route', coordinates, hitSlop: 18, strokeColor: '#FF9500', strokeWidth: 5, zIndex: 1, drag: { anchors: [start] } },
  { id: 'route-outline', coordinates, strokeColor: '#71368A', strokeWidth: 10 },
];

export default function App() {
  const [markers, setMarkers] = useState([startMarker]);
  const [map, setMap] = useState<MapSurfaceMethods>();
  const [visible, setVisible] = useState(true);
  const startedMount = useRef(performance.now());
  const [timing, setTiming] = useState('');
  const [provider, setProvider] = useState<MapProvider>(initialProvider);
  const [status, setStatus] = useState('Waiting for map');

  return (
    <View style={styles.screen}>
      {visible && (
        <MapSurface
          provider={provider}
          markers={markers}
          routes={routes}
          style={styles.map}
          onRef={setMap}
          onReady={() => {
            setStatus('Map ready');
            setTiming(`Ready in ${Math.round(performance.now() - startedMount.current)} ms`);
          }}
          onRendered={() => {
            const elapsed = Math.round(performance.now() - startedMount.current);
            setTiming((previous) => `${previous} · Rendered in ${elapsed} ms`);
          }}
          pinDragEnabled
          onDrag={({ phase, routeId }) => {
            if (phase !== 'move') setStatus(`${routeId ?? 'pin'} drag ${phase}`);
          }}
          onTap={({ markerId, routeIds, coordinate }) =>
            setStatus(markerId ?? routeIds[0] ?? `${coordinate.latitude.toFixed(4)}, ${coordinate.longitude.toFixed(4)}`)
          }
        />
      )}
      <Text numberOfLines={2}>{status}</Text>
      {timing !== '' && <Text>{timing}</Text>}
      {canSwitchProvider && (
        <Button title={provider === 'apple' ? 'Use Google Maps' : 'Use Apple Maps'} onPress={() => {
          setStatus('Waiting for map');
          startedMount.current = performance.now();
          setTiming('');
          setProvider(provider === 'apple' ? 'google' : 'apple');
        }} />
      )}
      <Button title="Center on route" onPress={() => {
        map?.setCamera(start, 7, true).catch((error: unknown) => setStatus(String(error)));
      }} />
      <Button title="Run ref checks" onPress={() => {
        if (!map) {
          setStatus('Map ref unavailable');
          return;
        }
        setStatus('Checking projection');
        void (async () => {
          await map.setCamera(start, 12, false);
          const projected = await map.project(start);
          const result = await map.unproject(projected);
          if (Math.abs(result.latitude - start.latitude) > 0.001 ||
              Math.abs(result.longitude - start.longitude) > 0.001) {
            throw new Error('Projection round trip exceeded screen precision');
          }
          setStatus('Projection passed, waiting for snapshot');
          const uri = await map.takeSnapshot().catch((error: unknown) => {
            throw new Error(`Projection passed. Snapshot failed: ${String(error)}`);
          });
          if (!uri.startsWith('file:')) throw new Error('Snapshot did not return a file URI');
          setStatus('Projection and snapshot passed');
        })().catch((error: unknown) => setStatus(String(error)));
      }} />
      <Button title="Remove marker" onPress={() => setMarkers([])} />
      <Button title="Restore marker" onPress={() => setMarkers([startMarker])} />
      <Button title={visible ? 'Detach map' : 'Attach map'} onPress={() => {
        setMap(undefined);
        setStatus(visible ? 'Map detached' : 'Waiting for map');
        setTiming('');
        startedMount.current = performance.now();
        setVisible(!visible);
      }} />
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, paddingTop: 56, paddingBottom: 30 },
  map: { flex: 1 },
});
