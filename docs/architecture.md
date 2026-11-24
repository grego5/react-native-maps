# Architecture

Application state owns markers and routes. React passes ordered feature arrays to the Nitro `MapSurface` host. The host applies its latest props on the platform UI thread after the provider becomes available. Markers and routes are separate props. Nitro converts a prop only when its JS identity changes, and the host reconciles only the collection whose prop changed. Each presenter reconciles its own SDK handles by feature ID. Route order uses `zIndex` and input order for ties.

The mounted surface owns camera state, projection, display snapshots, gestures, and readiness. Releasing it clears SDK handles and invalidates old callbacks. A new surface renders the arrays supplied by the app. Marker images load as needed using the platform image cache.

Native gesture coordinators assemble feature taps and own a claimed drag through release or cancellation. The SDK handles normal map navigation and provides camera state and projection. The drag preview belongs to the view. The app can persist a drop by updating its state. On MapKit, the coordinator's tap recognizer emits a map tap one main-queue turn after the touch, and skips it when the presenter selected a point of interest in that window, so a POI tap never also becomes `onTap`.

[`src/MapSurface.nitro.ts`](../src/MapSurface.nitro.ts) defines the generated bindings. Run `npm run nitrogen` to regenerate them. Android Gradle and CMake and the iOS podspec compile the generated code alongside handwritten implementations. The package manifest declares `@grego5/react-native-maps`. The example installs the local package under the `react-native-maps` alias.
