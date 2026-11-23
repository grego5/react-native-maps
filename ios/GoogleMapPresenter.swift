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
  private var rendered = false

  var onRendered: (() -> Void)?
  var onSDKTap: ((CLLocationCoordinate2D, String?) -> Void)?
  var onCameraMoving: ((Bool) -> Void)?
  var view: UIView { map }

  override init() {
    super.init()
    map.delegate = self
  }

  func apply(_ features: MapFeatures) {
    let ids = Set(features.markers.map(\.id))
    for id in markers.keys.filter({ !ids.contains($0) }) {
      markerIcons.removeValue(forKey: id)
      markers.removeValue(forKey: id)?.map = nil
    }
    for spec in features.markers {
      let marker = markers[spec.id] ?? GMSMarker(position: spec.coordinate.location)
      if marker.position.latitude != spec.coordinate.latitude ||
          marker.position.longitude != spec.coordinate.longitude {
        marker.position = spec.coordinate.location
      }
      if marker.title != spec.title { marker.title = spec.title }
      if markers[spec.id] == nil {
        marker.userData = spec.id
        marker.map = map
        markers[spec.id] = marker
      }
      updateMarkerIcon(spec.id, marker: marker, source: spec.image)
    }

    let specs = features.routes
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
    }
    routeSpecs = specs
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
    map.selectedMarker = nil
  }

  func setCamera(_ center: CLLocationCoordinate2D, zoom: Double, animated: Bool) {
    guard CLLocationCoordinate2DIsValid(center), zoom.isFinite else { return }
    let camera = GMSCameraPosition(target: center, zoom: Float(zoom), bearing: 0, viewingAngle: 0)
    if animated { map.animate(to: camera) } else { map.camera = camera }
  }

  func project(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
    map.projection.point(for: coordinate)
  }

  func unproject(_ point: CGPoint) -> CLLocationCoordinate2D {
    map.projection.coordinate(for: point)
  }

  func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
    onCameraMoving?(true)
  }

  func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
    onCameraMoving?(false)
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

  func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
    onSDKTap?(marker.position, marker.userData as? String)
    return false
  }

  func suspendCameraGestures() -> () -> Void {
    let settings = map.settings
    let scroll = settings.scrollGestures
    let zoom = settings.zoomGestures
    let rotate = settings.rotateGestures
    let tilt = settings.tiltGestures
    settings.setAllGesturesEnabled(false)
    return {
      settings.scrollGestures = scroll
      settings.zoomGestures = zoom
      settings.rotateGestures = rotate
      settings.tiltGestures = tilt
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
    onCameraMoving = nil
    map.delegate = nil
    clearFeatures()
  }
}
#endif
