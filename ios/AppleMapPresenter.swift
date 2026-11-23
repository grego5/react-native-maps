import MapKit
import UIKit

final class AppleMapPresenter: NSObject, MapPresenter, MKMapViewDelegate {
  private final class IconRequest {
    let key: MarkerImages.Key
    init(_ key: MarkerImages.Key) { self.key = key }
  }

  private final class Annotation: MKPointAnnotation {
    var iconRequest: IconRequest?
    var icon: UIImage?
  }

  private let map = MKMapView()
  private let defaultIcon = UIImage(
    systemName: "mappin.circle.fill",
    withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)
  )?.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
  private var markers = [String: Annotation]()
  private var markerOrder: [String] = []
  private var lines = [String: MKPolyline]()
  private var routeSpecs: [MapRoute] = []
  private typealias RouteStyle = (color: UIColor, width: CGFloat)
  private var routeStyles = [ObjectIdentifier: RouteStyle]()
  private var snapshotters = [UUID: MKMapFeaturester]()
  private var rendered = false
  private var closed = false

  var onRendered: (() -> Void)?
  var onSDKTap: ((CLLocationCoordinate2D, String?) -> Void)?
  var needsMapTapRecognizer: Bool { true }
  var onCameraMoving: ((Bool) -> Void)?
  var view: UIView { map }

  override init() {
    super.init()
    map.delegate = self
  }

  func apply(_ features: MapFeatures) {
    applyMarkers(features.markers)
    applyRoutes(features.routes)
  }

  private func applyMarkers(_ specs: [MapMarker]) {
    let ids = Set(specs.map(\.id))
    for id in markers.keys.filter({ !ids.contains($0) }) {
      if let removed = markers.removeValue(forKey: id) { map.removeAnnotation(removed) }
    }
    for spec in specs {
      if let marker = markers[spec.id] {
        if marker.coordinate.latitude != spec.coordinate.latitude ||
            marker.coordinate.longitude != spec.coordinate.longitude {
          marker.coordinate = spec.coordinate.location
        }
        if marker.title != spec.title { marker.title = spec.title }
        updateMarkerIcon(marker, source: spec.image)
      } else {
        let marker = Annotation()
        marker.coordinate = spec.coordinate.location
        marker.title = spec.title
        markers[spec.id] = marker
        map.addAnnotation(marker)
        updateMarkerIcon(marker, source: spec.image)
      }
    }
    markerOrder = specs.map(\.id)
  }

  private func updateMarkerIcon(_ marker: Annotation, source: MarkerImage?) {
    let key = source.map(MarkerImages.Key.init)
    guard marker.iconRequest?.key != key else { return }
    marker.iconRequest = nil
    marker.icon = nil
    if let view = map.view(for: marker) { configureIcon(defaultIcon, on: view) }
    guard let key else { return }
    let request = IconRequest(key)
    marker.iconRequest = request
    MarkerImages.shared.load(key) { [weak self, weak marker] result in
      guard let self, let marker, marker.iconRequest === request,
            let image = try? result.get() else { return }
      marker.icon = image
      if let view = self.map.view(for: marker) { self.configureIcon(image, on: view) }
    }
  }

  private func configureIcon(_ icon: UIImage?, on view: MKAnnotationView) {
    view.image = icon
    view.centerOffset = CGPoint(x: 0, y: -(icon?.size.height ?? 0) / 2)
  }

  private func applyRoutes(_ input: [MapRoute]) {
    let specs = orderedRoutes(input)
    let ids = Set(specs.map(\.id))
    let previous = Dictionary(uniqueKeysWithValues: routeSpecs.map { ($0.id, $0) })
    let oldOrder = orderedRoutes(routeSpecs).map(\.id).filter { ids.contains($0) }
    let newOrder = specs.map(\.id).filter { lines[$0] != nil }
    if oldOrder != newOrder {
      map.removeOverlays(lines.values.map { $0 })
    }
    for id in lines.keys.filter({ !ids.contains($0) }) {
      if let removed = lines.removeValue(forKey: id) {
        routeStyles.removeValue(forKey: ObjectIdentifier(removed))
        map.removeOverlay(removed)
      }
    }

    var previousLine: MKPolyline?
    for spec in specs {
      let old = lines[spec.id]
      if let old, let oldSpec = previous[spec.id],
         sameRouteGeometry(oldSpec.coordinates, spec.coordinates) {
        if oldSpec.strokeColor != spec.strokeColor || oldSpec.strokeWidth != spec.strokeWidth {
          let style: RouteStyle = (spec.lineColor, spec.lineWidth)
          routeStyles[ObjectIdentifier(old)] = style
          if let renderer = map.renderer(for: old) as? MKPolylineRenderer {
            applyStyle(style, to: renderer)
            renderer.setNeedsDisplay()
          }
        }
        insertIfNeeded(old, after: previousLine, before: nil)
        previousLine = old
      } else {
        let points = spec.coordinates.map(\.location)
        let line = MKPolyline(coordinates: points, count: points.count)
        lines[spec.id] = line
        routeStyles[ObjectIdentifier(line)] = (spec.lineColor, spec.lineWidth)
        if let old { routeStyles.removeValue(forKey: ObjectIdentifier(old)) }
        if let old, let index = levelIndex(old) {
          map.insertOverlay(line, at: index, level: .aboveRoads)
          map.removeOverlay(old)
        } else {
          let firstKept = previousLine == nil
            ? specs.lazy.compactMap { self.lines[$0.id] }.first { self.levelIndex($0) != nil }
            : nil
          insertIfNeeded(line, after: previousLine, before: firstKept)
        }
        previousLine = line
      }
    }
    routeSpecs = input
  }

  private func levelIndex(_ line: MKPolyline) -> Int? {
    map.overlays(in: .aboveRoads).firstIndex { $0 as AnyObject === line }
  }

  private func insertIfNeeded(_ line: MKPolyline, after previous: MKPolyline?, before following: MKPolyline?) {
    if levelIndex(line) != nil { return }
    if let previous, let index = levelIndex(previous) {
      map.insertOverlay(line, at: index + 1, level: .aboveRoads)
    } else if let following, let index = levelIndex(following) {
      map.insertOverlay(line, at: index, level: .aboveRoads)
    } else {
      map.addOverlay(line, level: .aboveRoads)
    }
  }

  func clearFeatures() {
    map.removeAnnotations(markers.values.map { $0 })
    map.removeOverlays(lines.values.map { $0 })
    markers.removeAll()
    markerOrder.removeAll()
    lines.removeAll()
    routeSpecs.removeAll()
    routeStyles.removeAll()
  }

  func setCamera(_ center: CLLocationCoordinate2D, zoom: Double, animated: Bool) {
    guard CLLocationCoordinate2DIsValid(center), zoom.isFinite else { return }
    let worldWidth = MKMapRect.world.size.width
    let width = min(worldWidth, max(1, worldWidth * Double(map.bounds.width) / (256 * pow(2, zoom))))
    let height = width * Double(map.bounds.height / map.bounds.width)
    let point = MKMapPoint(center)
    map.setVisibleMapRect(
      MKMapRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height),
      animated: animated
    )
  }

  func project(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
    map.convert(coordinate, toPointTo: map)
  }

  func unproject(_ point: CGPoint) -> CLLocationCoordinate2D {
    map.convert(point, toCoordinateFrom: map)
  }

  func marker(at point: CGPoint) -> (id: String, coordinate: CLLocationCoordinate2D)? {
    for id in markerOrder.reversed() {
      guard let marker = markers[id], let view = map.view(for: marker), !view.isHidden else { continue }
      if view.point(inside: view.convert(point, from: map), with: nil) {
        return (id, marker.coordinate)
      }
    }
    return nil
  }

  func suspendCameraGestures() -> () -> Void {
    let scroll = map.isScrollEnabled
    let zoom = map.isZoomEnabled
    let rotate = map.isRotateEnabled
    let pitch = map.isPitchEnabled
    map.isScrollEnabled = false
    map.isZoomEnabled = false
    map.isRotateEnabled = false
    map.isPitchEnabled = false
    return { [map] in
      map.isScrollEnabled = scroll
      map.isZoomEnabled = zoom
      map.isRotateEnabled = rotate
      map.isPitchEnabled = pitch
    }
  }

  func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
    onCameraMoving?(true)
  }

  func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
    onCameraMoving?(false)
  }

  func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
    if fullyRendered && !rendered {
      rendered = true
      onRendered?()
    }
  }

  func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
    guard let annotation = annotation as? Annotation else { return nil }
    let reuseID = "NitroMapMarker"
    let marker = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)
      ?? MKAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
    marker.annotation = annotation
    marker.canShowCallout = true
    configureIcon(annotation.icon ?? defaultIcon, on: marker)
    return marker
  }

  func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
    guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
    let renderer = MKPolylineRenderer(polyline: line)
    if let style = routeStyles[ObjectIdentifier(line)] { applyStyle(style, to: renderer) }
    renderer.lineJoin = .round
    renderer.lineCap = .round
    return renderer
  }

  private func applyStyle(_ style: RouteStyle, to renderer: MKPolylineRenderer) {
    renderer.strokeColor = style.color
    renderer.lineWidth = style.width
  }

  func snapshot(_ complete: @escaping (Result<UIImage, Error>) -> Void) throws {
    guard rendered, map.window?.windowScene?.activationState == .foregroundActive else { throw MapSurfaceError.notReady }
    let options = MKMapFeaturester.Options()
    options.camera = map.camera
    options.size = map.bounds.size
    options.traitCollection = map.traitCollection
    let snapshotter = MKMapFeaturester(options: options)
    let id = UUID()
    snapshotters[id] = snapshotter
    let points = markerOrder.compactMap { id -> (CLLocationCoordinate2D, UIImage)? in
      guard let marker = markers[id], let icon = marker.icon ?? defaultIcon else { return nil }
      return (marker.coordinate, icon)
    }
    let routes = orderedRoutes(routeSpecs)
    snapshotter.start(with: .main) { [weak self] result, error in
      guard let self, self.snapshotters.removeValue(forKey: id) != nil else { return }
      if let result {
        let format = UIGraphicsImageRendererFormat()
        format.scale = result.image.scale
        let image = UIGraphicsImageRenderer(size: result.image.size, format: format).image { renderer in
          result.image.draw(at: .zero)
          let context = renderer.cgContext

          context.setLineCap(.round)
          context.setLineJoin(.round)
          for route in routes {
            context.setLineWidth(route.lineWidth)
            context.setStrokeColor(route.lineColor.cgColor)
            context.addLines(between: route.coordinates.map { result.point(for: $0.location) })
            context.strokePath()
          }
          for (coordinate, icon) in points {
            let point = result.point(for: coordinate)
            let size = icon.size
            icon.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height))
          }
        }
        complete(.success(image))
      } else {
        complete(.failure(error ?? MapSurfaceError.snapshotFailed))
      }
    }
  }

  func close() {
    if closed { return }
    closed = true
    onRendered = nil
    onSDKTap = nil
    onCameraMoving = nil
    map.delegate = nil
    snapshotters.values.forEach { $0.cancel() }
    snapshotters.removeAll()
    clearFeatures()
  }
}
