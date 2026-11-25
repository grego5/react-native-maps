const googleIOSKey = process.env.GOOGLE_MAPS_IOS_API_KEY;

module.exports = {
  name: 'React Native Maps Example',
  slug: 'react-native-maps-example',
  android: {
    package: 'com.maps.example',
    scheme: 'com.maps.example',
    config: { googleMaps: { apiKey: process.env.GOOGLE_MAPS_ANDROID_API_KEY } },
  },
  ios: { bundleIdentifier: 'com.maps.example' },
  plugins: [
    ['react-native-maps', { iosGoogleMapsApiKey: googleIOSKey }],
    ['expo-build-properties', { android: { cmakeVersion: '4.1.2' } }],
  ],
  extra: {
    googleIOS: Boolean(googleIOSKey),
    eas: {
      projectId: '8ca3910b-5a13-4828-890d-818c4bd969e3',
    },
  },
};
