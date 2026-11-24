#if REACT_NATIVE_MAPS_GOOGLE && canImport(GoogleMaps)
import GoogleMaps
import UIKit

final class GoogleMapPresenter: NSObject, MapPresenter, GMSMapViewDelegate {
  private let map = GMSMapView(options: GMSMapViewOptions())
  private var markers = [String: GMSMarker]()
  private final class IconRequest {
    let key: MarkerImages.Key
    init(_ key: MarkerImages.Key) { self.key = key }
  }
  private var markerIcons = [String: IconRequest]()
  private var lines = [String: GMSPolyline]()
  private var routeSpecs: [MapRoute] = []
  private var dashedRoutes = Set<String>()
  private var rendered = false
  private var configured: MapOptions?
  private var gesturesSuspended = false
  private var appliedStyle: String?

  var onRendered: (() -> Void)?
  var onSDKTap: ((CLLocationCoordinate2D, String?) -> Void)?
  var onPOITap: ((MapPoiTap) -> Void)?
  var onCamera: ((MapCameraPhase) -> Void)?
  var view: UIView { map }

  override init() {
    super.init()
    map.delegate = self
  }

  func applyMarkers(_ specs: [MapMarker]) {
    let ids = Set(specs.map(\.id))
    for id in markers.keys.filter({ !ids.contains($0) }) {
      markerIcons.removeValue(forKey: id)
      markers.removeValue(forKey: id)?.map = nil
    }
    for (rank, spec) in orderedMarkers(specs).enumerated() {
      let marker = markers[spec.id] ?? GMSMarker(position: spec.coordinate.location)
      if marker.position.latitude != spec.coordinate.latitude ||
          marker.position.longitude != spec.coordinate.longitude {
        marker.position = spec.coordinate.location
      }
      if marker.title != spec.title { marker.title = spec.title }
      if marker.snippet != spec.description { marker.snippet = spec.description }
      let anchor = spec.anchorPoint
      if marker.groundAnchor != anchor { marker.groundAnchor = anchor }
      if marker.zIndex != Int32(rank) { marker.zIndex = Int32(rank) }
      if markers[spec.id] == nil {
        marker.userData = spec.id
        marker.map = map
        markers[spec.id] = marker
      }
      updateMarkerIcon(spec.id, marker: marker, source: spec.image)
    }
  }

  func applyRoutes(_ specs: [MapRoute]) {
    let routeIds = Set(specs.map(\.id))
    let previous = Dictionary(uniqueKeysWithValues: routeSpecs.map { ($0.id, $0) })
    for id in lines.keys.filter({ !routeIds.contains($0) }) {
      lines.removeValue(forKey: id)?.map = nil
    }
    for (index, spec) in orderedRoutes(specs).enumerated() {
      let line = lines[spec.id] ?? GMSPolyline()
      if previous[spec.id].map({ sameRouteGeometry($0.coordinates, spec.coordinates) }) != true {
        let path = GMSMutablePath()
        for coordinate in spec.coordinates { path.add(coordinate.location) }
        line.path = path
      }
      let rank = Int32(index)
      if line.zIndex != rank { line.zIndex = rank }
      if previous[spec.id]?.strokeColor != spec.strokeColor || lines[spec.id] == nil {
        line.strokeColor = spec.lineColor
      }
      if line.strokeWidth != spec.lineWidth { line.strokeWidth = spec.lineWidth }
      if lines[spec.id] == nil {
        line.map = map
        lines[spec.id] = line
      }
      let old = previous[spec.id]
      if spec.dashPattern != nil {
        dashedRoutes.insert(spec.id)
        if old?.dashPattern != spec.dashPattern || old?.strokeColor != spec.strokeColor || line.spans == nil ||
            old.map({ sameRouteGeometry($0.coordinates, spec.coordinates) }) != true {
          applyDashes(spec, to: line)
        }
      } else if dashedRoutes.remove(spec.id) != nil {
        line.spans = nil
      }
    }
    dashedRoutes.formIntersection(routeIds)
    routeSpecs = specs
  }

  /// GMSPolyline dashes are geographic lengths, so they are converted at the camera's current
  /// scale and recomputed when the camera settles.
  private func applyDashes(_ spec: MapRoute, to line: GMSPolyline) {
    guard let pattern = spec.dashPattern, let path = line.path else { return }
    let camera = map.camera
    let metersPerPoint = 40_075_016.686 * cos(camera.target.latitude * .pi / 180) / (256 * pow(2, Double(camera.zoom)))
    let styles = [GMSStrokeStyle.solidColor(spec.lineColor), GMSStrokeStyle.solidColor(.clear)]
    let lengths = pattern.map { NSNumber(value: $0 * metersPerPoint) }
    line.spans = GMSStyleSpans(path, styles, lengths, .rhumb)
  }

  private func updateMarkerIcon(_ id: String, marker: GMSMarker, source: MarkerImage?) {
    let key = source.map(MarkerImages.Key.init)
    guard markerIcons[id]?.key != key else { return }
    marker.icon = nil
    guard let key else {
      markerIcons.removeValue(forKey: id)
      return
    }
    let request = IconRequest(key)
    markerIcons[id] = request
    MarkerImages.shared.load(key) { [weak self] result in
      guard let self, self.markerIcons[id] === request, let image = try? result.get() else { return }
      self.markers[id]?.icon = image
    }
  }

  func clearFeatures() {
    markers.values.forEach { $0.map = nil }
    lines.values.forEach { $0.map = nil }
    markers.removeAll()
    markerIcons.removeAll()
    lines.removeAll()
    routeSpecs.removeAll()
    dashedRoutes.removeAll()
    map.selectedMarker = nil
  }

  func moveCamera(_ center: CLLocationCoordinate2D, zoom: Double, duration: Double) {
    let camera = GMSCameraPosition(target: center, zoom: Float(zoom), bearing: 0, viewingAngle: 0)
    guard duration > 0 else {
      map.camera = camera
      return
    }
    CATransaction.begin()
    CATransaction.setAnimationDuration(duration / 1000)
    map.animate(to: camera)
    CATransaction.commit()
  }

  var camera: MapCamera {
    MapCamera(center: map.camera.target.mapCoordinate, zoom: Double(map.camera.zoom))
  }

  func project(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
    map.projection.point(for: coordinate)
  }

  func unproject(_ point: CGPoint) -> CLLocationCoordinate2D {
    map.projection.coordinate(for: point)
  }

  func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
    onCamera?(.start)
  }

  func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
    if !dashedRoutes.isEmpty {
      for spec in routeSpecs where dashedRoutes.contains(spec.id) {
        if let line = lines[spec.id] { applyDashes(spec, to: line) }
      }
    }
    onCamera?(.idle)
  }


  func mapViewSnapshotReady(_ mapView: GMSMapView) {
    if !rendered {
      rendered = true
      onRendered?()
    }
  }

  func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
    onSDKTap?(coordinate, nil)
  }

  /// The SDK reports POI taps here instead of `didTapAt`, so they are never map taps.
  func setPOITapsEnabled(_ enabled: Bool) {}

  func mapView(_ mapView: GMSMapView, didTapPOIWithPlaceID placeID: String, name: String, location: CLLocationCoordinate2D) {
    onPOITap?(MapPoiTap(placeId: placeID, name: name, coordinate: location.mapCoordinate))
  }

  /// Returning true stops the SDK's camera move, so the selection that opens the info window happens here.
  func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
    onSDKTap?(marker.position, marker.userData as? String)
    map.selectedMarker = marker.title == nil ? nil : marker
    return true
  }

  func showCallout(_ id: String) throws {
    guard let marker = markers[id] else { throw MapSurfaceError.unknownMarker }
    map.selectedMarker = marker
  }

  func hideCallout() {
    map.selectedMarker = nil
  }

  func apply(_ options: MapOptions?) {
    configured = options
    if options?.mapStyle != appliedStyle {
      appliedStyle = options?.mapStyle
      if let json = options?.mapStyle {
        do {
          map.mapStyle = try GMSMapStyle(jsonString: json)
        } catch {
          NSLog("MapSurface: Google Maps rejected mapStyle: %@", error.localizedDescription)
          map.mapStyle = nil
        }
      } else {
        map.mapStyle = nil
      }
    }
    map.mapType = options?.mapType == MapType.none ? .none : .normal
    map.isBuildingsEnabled = options?.showsBuildings ?? true
    map.isIndoorEnabled = options?.showsIndoors ?? true
    if !gesturesSuspended { applyGestures() }
  }

  private func applyGestures() {
    let settings = map.settings
    settings.scrollGestures = configured?.scrollEnabled ?? true
    settings.zoomGestures = configured?.zoomEnabled ?? true
    settings.rotateGestures = configured?.rotateEnabled ?? true
    settings.tiltGestures = configured?.pitchEnabled ?? true
  }

  func suspendCameraGestures() -> () -> Void {
    gesturesSuspended = true
    map.settings.setAllGesturesEnabled(false)
    return { [weak self] in
      guard let self else { return }
      self.gesturesSuspended = false
      self.applyGestures()
    }
  }

  func snapshot(_ complete: @escaping (Result<UIImage, Error>) -> Void) throws {
    guard rendered, map.window?.windowScene?.activationState == .foregroundActive,
          !map.bounds.isEmpty else { throw MapSurfaceError.notReady }
    var drawn = false
    let image = UIGraphicsImageRenderer(bounds: map.bounds).image { _ in
      drawn = map.drawHierarchy(in: map.bounds, afterScreenUpdates: false)
    }
    complete(drawn ? .success(image) : .failure(MapSurfaceError.snapshotFailed))
  }

  func close() {
    onRendered = nil
    onSDKTap = nil
    onPOITap = nil
    onCamera = nil
    map.delegate = nil
    clearFeatures()
  }
}
#endif
