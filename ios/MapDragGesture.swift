import CoreLocation
import UIKit

final class MapDragGesture: NSObject, UIGestureRecognizerDelegate {
  private struct Drag {
    let route: MapRoute?
    var point: CGPoint
  }

  private weak var presenter: (any MapPresenter)?
  private let recognizer = UILongPressGestureRecognizer()
  private let tap = UITapGestureRecognizer()
  private let preview = CAShapeLayer()
  private var routes: [MapRoute] = []
  private var active: Drag?
  private var cameraMoving = false
  private var restoreCameraGestures: (() -> Void)?

  var pinEnabled = false {
    didSet {
      if !pinEnabled, let active, active.route == nil { cancel() }
    }
  }
  var onDrag: ((MapDragEvent) -> Void)?
  var onTap: ((MapTap) -> Void)?

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
    presenter.onCameraMoving = { [weak self] moving in self?.cameraDidMove(moving) }
    presenter.onSDKTap = { [weak self] coordinate, markerId in
      guard let self, let presenter = self.presenter else { return }
      self.emitTap(at: presenter.project(coordinate), coordinate: coordinate, markerId: markerId)
    }
    preview.strokeColor = UIColor.systemBlue.cgColor
    preview.fillColor = UIColor.systemBlue.cgColor
    preview.lineWidth = 3
    preview.lineCap = .round
    preview.zPosition = 1
    presenter.view.layer.addSublayer(preview)
  }

  func updateRoutes(_ routes: [MapRoute]) {
    self.routes = routes
    if let route = active?.route {
      guard let updated = routes.first(where: { $0.id == route.id }),
            let anchors = updated.drag?.anchors, let previous = route.drag?.anchors,
            sameRouteGeometry(anchors, previous) else {
        cancel()
        return
      }
    }
  }

  private func cameraDidMove(_ moving: Bool) {
    cameraMoving = moving
    if moving { cancel() }
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
    presenter?.onCameraMoving = nil
    presenter?.onSDKTap = nil
    preview.removeFromSuperlayer()
    onDrag = nil
    onTap = nil
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

  @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
    guard let presenter else { return }
    let point = gesture.location(in: presenter.view)
    let marker = presenter.marker(at: point)
    emitTap(at: point, coordinate: marker?.coordinate ?? presenter.unproject(point), markerId: marker?.id)
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
      let route = route(at: finger)
      guard route != nil || pinEnabled else { return }
      let restore = presenter.suspendCameraGestures()
      guard recognizer.state == .began, !cameraMoving else {
        restore()
        return
      }
      restoreCameraGestures = restore
      let drag = Drag(route: route, point: point)
      active = drag
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

  private func finish(_ phase: MapDragPhase) {
    guard let drag = active else { return }
    active = nil
    let restore = restoreCameraGestures
    restoreCameraGestures = nil
    restore?()
    preview.path = nil
    emit(drag, phase: phase)
  }

  private func draw(_ drag: Drag) {
    guard let presenter else { return }
    let path = UIBezierPath()
    for anchor in drag.route?.drag?.anchors ?? [] {
      path.move(to: presenter.project(anchor.location))
      path.addLine(to: drag.point)
    }
    path.append(UIBezierPath(arcCenter: drag.point, radius: 5,
                            startAngle: 0, endAngle: 2 * .pi, clockwise: true))
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    preview.frame = presenter.view.bounds
    preview.path = path.cgPath
    CATransaction.commit()
  }

  private func emit(_ drag: Drag, phase: MapDragPhase) {
    guard let presenter else { return }
    onDrag?(MapDragEvent(
      phase: phase, coordinate: presenter.unproject(drag.point).mapCoordinate,
      point: MapPoint(x: drag.point.x, y: drag.point.y), routeId: drag.route?.id
    ))
  }

}

private func routeHits(
  routes: [MapRoute],
  near tap: CGPoint,
  forDrag: Bool = false,
  project: (CLLocationCoordinate2D) -> CGPoint
) -> [String] {
  var hits: [(id: String, index: Int, distance: CGFloat)] = []
  for (index, route) in routes.enumerated() {
    if forDrag && route.drag == nil { continue }
    let radius = route.hitSlop ?? (forDrag ? 20 : 0)
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
