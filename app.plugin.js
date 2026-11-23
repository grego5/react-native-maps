const {
  withAppDelegate,
  withInfoPlist,
  withPodfile,
} = require('@expo/config-plugins');
const {
  mergeContents,
  removeContents,
} = require('@expo/config-plugins/build/utils/generateCode');

const POD_TAG = 'react-native-maps-google-pod';
const IMPORT_TAG = 'react-native-maps-google-import';
const INIT_TAG = 'react-native-maps-google-init';

const MATCH_INIT =
  /\bsuper\.application\(\w+?, didFinishLaunchingWithOptions: \w+?\)/g;

function merge(src, tag, newSrc, anchor, comment, file) {
  try {
    return mergeContents({tag, src, newSrc, anchor, offset: 0, comment})
      .contents;
  } catch (error) {
    if (error.code === 'ERR_NO_MATCH') {
      throw new Error(
        `react-native-maps: cannot find ${anchor} in the project's ${file}.`,
      );
    }
    throw error;
  }
}

function remove(src, tags) {
  return tags.reduce(
    (contents, tag) => removeContents({src: contents, tag}).contents,
    src,
  );
}

const withGoogleMapsPod = (config, enabled) =>
  withPodfile(config, mod => {
    const src = mod.modResults.contents;
    mod.modResults.contents = enabled
      ? merge(
          src,
          POD_TAG,
          "  pod 'ReactNativeMaps/Google', :path => File.dirname(`node --print \"require.resolve('react-native-maps/package.json')\"`)",
          /use_native_modules/,
          '#',
          'Podfile',
        )
      : remove(src, [POD_TAG]);
    return mod;
  });

const withGoogleMapsAppDelegate = (config, enabled) =>
  withAppDelegate(config, mod => {
    const src = mod.modResults.contents;
    if (!enabled) {
      mod.modResults.contents = remove(src, [IMPORT_TAG, INIT_TAG]);
      return mod;
    }
    if (mod.modResults.language !== 'swift') {
      throw new Error(
        `react-native-maps: the Google Maps setup supports a Swift AppDelegate, not ${mod.modResults.language}.`,
      );
    }
    const withImport = merge(
      src,
      IMPORT_TAG,
      ['#if canImport(GoogleMaps)', 'import GoogleMaps', '#endif'].join('\n'),
      /(@main|@UIApplicationMain)/,
      '//',
      'AppDelegate',
    );
    mod.modResults.contents = merge(
      withImport,
      INIT_TAG,
      [
        '#if canImport(GoogleMaps)',
        'GMSServices.provideAPIKey(Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as! String)',
        '#endif',
      ].join('\n'),
      MATCH_INIT,
      '//',
      'AppDelegate',
    );
    return mod;
  });

module.exports = (config, props) => {
  const apiKey = props?.iosGoogleMapsApiKey;
  config = withInfoPlist(config, mod => {
    if (apiKey) mod.modResults.GMSApiKey = apiKey;
    return mod;
  });
  config = withGoogleMapsPod(config, Boolean(apiKey));
  return withGoogleMapsAppDelegate(config, Boolean(apiKey));
};
