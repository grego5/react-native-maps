require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'ReactNativeMaps'
  s.version = package.fetch('version')
  s.summary = 'Native map surfaces for React Native'
  s.homepage = 'https://github.com/grego5/react-native-maps'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = 'React Native Maps contributors'
  s.source = { :git => 'https://github.com/grego5/react-native-maps.git', :tag => s.version.to_s }
  s.platforms = { :ios => '16.0' }
  s.swift_version = '5.0'
  s.requires_arc = true
  s.static_framework = true
  s.default_subspec = 'Apple'
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/nitrogen/generated/shared/c++" "$(PODS_TARGET_SRCROOT)/nitrogen/generated/ios"'
  }

  s.source_files = 'ios/*.swift'
  s.frameworks = ['UIKit', 'MapKit', 'CoreLocation']
  s.dependency 'React-Core'
  s.dependency 'React-Fabric/components/view'

  load File.join(__dir__, 'nitrogen/generated/ios/ReactNativeMaps+autolinking.rb')
  add_nitrogen_files(s)

  s.subspec 'Apple' do |_apple|
  end

  s.subspec 'Google' do |google|
    google.dependency 'GoogleMaps', '9.4.0'
    google.pod_target_xcconfig = {
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) REACT_NATIVE_MAPS_GOOGLE',
      'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) REACT_NATIVE_MAPS_GOOGLE=1'
    }
  end
end
