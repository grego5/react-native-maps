import CoreLocation
import UIKit

final class MapDragGesture: NSObject, UIGestureRecognizerDelegate {
  private struct Drag {
    let route: MapRoute?
    /// Every draggable route under the press, nearest first, fixed for the whole drag.
    let routeIds: [String]
    var point: CGPoint
    /// Chosen at drag start, so a preview-only route update never changes or cancels the drag.
    let preview: DragPreview?
  }

  private weak var presenter: (any MapPresenter)?
  private let recognizer = UILongPressGestureRecognizer()
  private let tap = UITapGestureRecognizer()
  /// Connectors, the default circle, and the optional pin image.
  private let preview = CAShapeLayer()
  private let dot = CAShapeLayer()
  private let pinLayer = CALayer()
  /// Preview images, loaded when previews change so a drag never waits on I/O. Nil while loading or failed.
  private var previewImages = [MarkerImages.Key: UIImage?]()
  private var routes: [MapRoute] = []
  /// Markers in input order, for drop and query hits.
  private var markers: [MapMarker] = []
  /// Display points around the drop point searched for markers on `.end`.
  var dropRadius: Double = 0
  private var active: Drag?
  private var cameraMoving = false
  private var restoreCameraGestures: (() -> Void)?

  var pinEnabled = false {
    didSet {
      if !pinEnabled, let active, active.route == nil { cancel() }
    }
  }
  /// Styles a standalone pin drag; route drags use their route's `drag.preview`.
  var pinPreview: DragPreview? {
    didSet { loadPreviewImages() }
  }
  var onDrag: ((MapDragEvent) -> Void)?
  var onTap: ((MapTap) -> Void)?
  var onCamera: ((MapCameraPhase) -> Void)?

  init(presenter: any MapPresenter) {
    self.presenter = presenter
    super.init()
    recognizer.minimumPressDuration = 0.4
    recognizer.allowableMovement = 10
    recognizer.cancelsTouchesInView = true
    recognizer.addTarget(self, action: #selector(handle(_:)))
    recognizer.delegate = self
    presenter.view.addGestureRecognizer(recognizer)
    if presenter.needsMapTapRecognizer {
      tap.cancelsTouchesInView = false
      tap.addTarget(self, action: #selector(handleTap(_:)))
      tap.delegate = self
      tap.require(toFail: recognizer)
      presenter.view.addGestureRecognizer(tap)
    }
    presenter.onCamera = { [weak self] phase in self?.cameraDidMove(phase) }
    presenter.onSDKTap = { [weak self] coordinate, markerId in
      guard let self, let presenter = self.presenter else { return }
      self.emitTap(at: presenter.project(coordinate), coordinate: coordinate, markerId: markerId)
    }
    preview.fillColor = nil
    preview.lineCap = .round
    preview.zPosition = 1
    dot.zPosition = 1
    pinLayer.zPosition = 1
    pinLayer.isHidden = true
    presenter.view.layer.addSublayer(preview)
    presenter.view.layer.addSublayer(dot)
    presenter.view.layer.addSublayer(pinLayer)
  }

  func updateRoutes(_ routes: [MapRoute]) {
    self.routes = routes
    loadPreviewImages()
    if let route = active?.route {
      guard let updated = routes.first(where: { $0.id == route.id }),
            let anchors = updated.drag?.anchors, let previous = route.drag?.anchors,
            sameRouteGeometry(anchors, previous) else {
        cancel()
        return
      }
    }
  }

  /// SDKs can report several starts during one animation; forward one `.start` per `.idle`.
  private func cameraDidMove(_ phase: MapCameraPhase) {
    let moving = phase == .start
    if moving { cancel() }
    guard cameraMoving != moving else { return }
    cameraMoving = moving
    onCamera?(phase)
  }

  func cancel() {
    finish(.cancel)
    recognizer.isEnabled = false
    recognizer.isEnabled = true
  }

  func close() {
    cancel()
    presenter?.view.removeGestureRecognizer(recognizer)
    presenter?.view.removeGestureRecognizer(tap)
    presenter?.onCamera = nil
    presenter?.onSDKTap = nil
    preview.removeFromSuperlayer()
    dot.removeFromSuperlayer()
    pinLayer.removeFromSuperlayer()
    onDrag = nil
    onTap = nil
    onCamera = nil
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    if gestureRecognizer === tap { return active == nil }
    return !cameraMoving && (pinEnabled || route(at: gestureRecognizer.location(in: presenter?.view)) != nil)
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    (gestureRecognizer === tap || otherGestureRecognizer === tap)
      && gestureRecognizer !== recognizer && otherGestureRecognizer !== recognizer
  }

  var isActive: Bool { active != nil }

  @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
    guard let presenter else { return }
    let point = gesture.location(in: presenter.view)
    let marker = presenter.marker(at: point)
    // MapKit selects a point of interest during the same touch; wait one main-queue turn so a
    // POI selection can claim the tap instead of it also becoming a map tap.
    DispatchQueue.main.async { [weak self, weak presenter] in
      guard let self, let presenter, self.presenter === presenter, !presenter.consumePOITap() else { return }
      self.emitTap(at: point, coordinate: marker?.coordinate ?? presenter.unproject(point), markerId: marker?.id)
    }
  }

  private func emitTap(at point: CGPoint, coordinate: CLLocationCoordinate2D, markerId: String?) {
    guard active == nil, let onTap, let presenter else { return }
    let ids = markerId == nil ? routeHits(routes: routes, near: point, project: presenter.project) : []
    onTap(MapTap(
      coordinate: coordinate.mapCoordinate,
      point: MapPoint(x: point.x, y: point.y),
      markerId: markerId,
      routeIds: ids
    ))
  }

  @objc private func handle(_ gesture: UILongPressGestureRecognizer) {
    guard let presenter else { return }
    let finger = gesture.location(in: presenter.view)
    let point = CGPoint(x: finger.x, y: finger.y - 32)
    switch gesture.state {
    case .began:
      guard gesture.numberOfTouches == 1, !cameraMoving else { return }
      let routeIds = routeHits(routes: routes, near: finger, forDrag: true, project: presenter.project)
      let route = routeIds.first.flatMap { id in routes.first { $0.id == id } }
      guard route != nil || pinEnabled else { return }
      let restore = presenter.suspendCameraGestures()
      guard recognizer.state == .began, !cameraMoving else {
        restore()
        return
      }
      restoreCameraGestures = restore
      let drag = Drag(route: route, routeIds: routeIds, point: point, preview: route != nil ? route?.drag?.preview : pinPreview)
      active = drag
      style(for: drag.preview)
      draw(drag)
      emit(drag, phase: .start)
    case .changed:
      guard gesture.numberOfTouches == 1 else { cancel(); return }
      guard var drag = active else { return }
      drag.point = point
      active = drag
      draw(drag)
      emit(drag, phase: .move)
    case .ended:
      active?.point = point
      finish(.end)
    case .cancelled, .failed:
      finish(.cancel)
    default:
      break
    }
  }

  private func route(at point: CGPoint) -> MapRoute? {
    guard let presenter else { return nil }
    let id = routeHits(routes: routes, near: point, forDrag: true, project: presenter.project).first
    return routes.first { $0.id == id }
  }

  func updateMarkers(_ markers: [MapMarker]) {
    self.markers = markers
  }

  /// Markers and routes near `point` in display points, nearest first.
  func queryFeatures(_ point: CGPoint, radius: Double) throws -> MapFeatureHits {
    guard radius.isFinite, radius >= 0 else {
      throw MapSurfaceError.invalidArgument("Radius must be finite and nonnegative")
    }
    guard let presenter else { throw MapSurfaceError.detached }
    return MapFeatureHits(
      markerIds: markersNear(point, radius: radius),
      routeIds: routeHits(routes: routes, near: point, minRadius: CGFloat(radius), project: presenter.project)
    )
  }

  /// Markers whose coordinate projects within `radius` points of `point`, nearest first, then input order.
  private func markersNear(_ point: CGPoint, radius: Double) -> [String] {
    guard radius > 0, let presenter else { return [] }
    return markers.enumerated().compactMap { index, marker -> (id: String, distance: CGFloat, index: Int)? in
      let projected = presenter.project(marker.coordinate.location)
      let distance = hypot(projected.x - point.x, projected.y - point.y)
      return distance <= CGFloat(radius) ? (marker.id, distance, index) : nil
    }.sorted {
      $0.distance == $1.distance ? $0.index < $1.index : $0.distance < $1.distance
    }.map(\.id)
  }

  private func finish(_ phase: MapDragPhase) {
    guard let drag = active else { return }
    active = nil
    let restore = restoreCameraGestures
    restoreCameraGestures = nil
    restore?()
    preview.path = nil
    dot.path = nil
    pinLayer.isHidden = true
    pinLayer.contents = nil
    emit(drag, phase: phase)
  }

  /// Requests every image the current previews use and drops the ones no longer used.
  private func loadPreviewImages() {
    var wanted = Set(routes.compactMap { $0.drag?.preview?.image.map(MarkerImages.Key.init) })
    if let image = pinPreview?.image { wanted.insert(MarkerImages.Key(image)) }
    guard wanted != Set(previewImages.keys) else { return }
    previewImages = previewImages.filter { wanted.contains($0.key) }
    for key in wanted where previewImages[key] == nil {
      previewImages[key] = .some(nil)
      MarkerImages.shared.load(key) { [weak self] result in
        guard let self, self.previewImages[key] != nil, let image = try? result.get() else { return }
        self.previewImages[key] = image
      }
    }
  }

  private func style(for preview: DragPreview?) {
    let color = preview?.strokeColor.map(parseHexColor) ?? UIColor.systemBlue
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    self.preview.strokeColor = color.cgColor
    self.preview.lineWidth = CGFloat(preview?.strokeWidth ?? 3)
    self.preview.lineDashPattern = preview?.dashPattern?.map { NSNumber(value: $0) }
    dot.fillColor = color.cgColor
    CATransaction.commit()
  }

  private func draw(_ drag: Drag) {
    guard let presenter else { return }
    let path = UIBezierPath()
    for anchor in drag.route?.drag?.anchors ?? [] {
      path.move(to: presenter.project(anchor.location))
      path.addLine(to: drag.point)
    }
    let image = drag.preview?.image.flatMap { previewImages[MarkerImages.Key($0)] ?? nil }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    preview.frame = presenter.view.bounds
    preview.path = path.cgPath
    dot.frame = presenter.view.bounds
    if let image {
      let anchor = drag.preview?.anchor
      let size = image.size
      pinLayer.contents = image.cgImage
      pinLayer.contentsScale = image.scale
      pinLayer.frame = CGRect(
        x: drag.point.x - CGFloat(anchor?.x ?? 0.5) * size.width,
        y: drag.point.y - CGFloat(anchor?.y ?? 1) * size.height,
        width: size.width, height: size.height
      )
      pinLayer.isHidden = false
      dot.path = nil
    } else {
      pinLayer.isHidden = true
      dot.path = UIBezierPath(arcCenter: drag.point, radius: 6, startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath
    }
    CATransaction.commit()
  }

  private func emit(_ drag: Drag, phase: MapDragPhase) {
    guard let presenter else { return }
    onDrag?(MapDragEvent(
      phase: phase, coordinate: presenter.unproject(drag.point).mapCoordinate,
      point: MapPoint(x: drag.point.x, y: drag.point.y), routeId: drag.route?.id,
      routeIds: drag.routeIds, markerIds: phase == .end ? markersNear(drag.point, radius: dropRadius) : []
    ))
  }

}

private func routeHits(
  routes: [MapRoute],
  near tap: CGPoint,
  forDrag: Bool = false,
  minRadius: CGFloat = 0,
  project: (CLLocationCoordinate2D) -> CGPoint
) -> [String] {
  var hits: [(id: String, index: Int, distance: CGFloat)] = []
  for (index, route) in routes.enumerated() {
    if forDrag && route.drag == nil { continue }
    // The larger of `minRadius` and the route's slop: `hitSlop`, or 20 points for drags.
    let radius = max(route.hitSlop.map { CGFloat($0) } ?? (forDrag ? 20 : 0), minRadius)
    guard radius > 0 else { continue }
    let points = route.coordinates.map { project($0.location) }
    var nearest = CGFloat.infinity
    for (a, b) in zip(points, points.dropFirst()) {
      let dx = b.x - a.x
      let dy = b.y - a.y
      let lengthSquared = dx * dx + dy * dy
      let projection = lengthSquared == 0
        ? 0 : ((tap.x - a.x) * dx + (tap.y - a.y) * dy) / lengthSquared
      let t = min(1, max(0, projection))
      nearest = min(nearest, hypot(tap.x - (a.x + t * dx), tap.y - (a.y + t * dy)))
    }
    if nearest <= radius { hits.append((route.id, index, nearest)) }
  }
  return hits.sorted {
    $0.distance == $1.distance ? $0.index < $1.index : $0.distance < $1.distance
  }.map(\.id)
}
