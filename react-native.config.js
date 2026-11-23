module.exports = {
  dependency: {
    platforms: {
      android: {
        packageImportPath: 'import com.margelo.nitro.mapssession.ReactNativeMapsPackage;',
        packageInstance: 'new ReactNativeMapsPackage()',
      },
      ios: { podspecPath: 'ReactNativeMaps.podspec' },
    },
  },
};
