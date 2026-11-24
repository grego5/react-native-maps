import CoreLocation
import UIKit

protocol MapPresenter: AnyObject {
  var view: UIView { get }
  var onRendered: (() -> Void)? { get set }
  var onSDKTap: ((CLLocationCoordinate2D, String?) -> Void)? { get set }
  var needsMapTapRecognizer: Bool { get }
  var onPOITap: ((MapPoiTap) -> Void)? { get set }
  func setPOITapsEnabled(_ enabled: Bool)
  /// True once, shortly after the SDK selected a point of interest, so the tap recognizer skips that touch.
  func consumePOITap() -> Bool
  func marker(at point: CGPoint) -> (id: String, coordinate: CLLocationCoordinate2D)?
  func suspendCameraGestures() -> () -> Void
  /// Called by the SDK; `MapDragGesture` owns it and forwards one `.start` per `.idle`.
  var onCamera: ((MapCameraPhase) -> Void)? { get set }
  var camera: MapCamera { get }

  func apply(_ options: MapOptions?)
  func applyMarkers(_ specs: [MapMarker])
  func applyRoutes(_ specs: [MapRoute])
  func clearFeatures()
  /// Opens the marker's callout through the SDK selection, closing any other. Throws `unknownMarker`.
  func showCallout(_ id: String) throws
  func hideCallout()
  /// The single camera move every surface method uses: north-up, flat, `duration` in milliseconds.
  func moveCamera(_ center: CLLocationCoordinate2D, zoom: Double, duration: Double)
  func project(_ coordinate: CLLocationCoordinate2D) -> CGPoint
  func unproject(_ point: CGPoint) -> CLLocationCoordinate2D
  func snapshot(_ complete: @escaping (Result<UIImage, Error>) -> Void) throws
  func close()
}

extension MapPresenter {
  var needsMapTapRecognizer: Bool { false }

  func consumePOITap() -> Bool { false }

  func marker(at point: CGPoint) -> (id: String, coordinate: CLLocationCoordinate2D)? { nil }
}

enum MapSurfaceError: LocalizedError {
  case detached
  case notReady
  case providerUnavailable
  case snapshotFailed
  case invalidArgument(String)
  case unknownMarker

  var errorDescription: String? {
    switch self {
    case .detached: return "MapSurface is detached"
    case .notReady: return "MapSurface is not ready"
    case .providerUnavailable: return "This map provider is unavailable in the current build"
    case .snapshotFailed: return "The map snapshot could not be created"
    case .invalidArgument(let message): return message
    case .unknownMarker: return "Unknown marker"
    }
  }
}

extension Coordinate {
  var location: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}

extension CLLocationCoordinate2D {
  var mapCoordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

func orderedRoutes(_ specs: [MapRoute]) -> [MapRoute] {
  specs.enumerated().sorted {
    let lhs = $0.element.zIndex ?? 0
    let rhs = $1.element.zIndex ?? 0
    return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
  }.map(\.element)
}

/// Markers sorted by `zIndex`; input order breaks ties, as for routes.
func orderedMarkers(_ specs: [MapMarker]) -> [MapMarker] {
  specs.enumerated().sorted {
    let lhs = $0.element.zIndex ?? 0
    let rhs = $1.element.zIndex ?? 0
    return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
  }.map(\.element)
}

extension MapMarker {
  /// The image point placed on the coordinate, as fractions of the image size.
  var anchorPoint: CGPoint {
    guard let anchor else { return CGPoint(x: 0.5, y: 1) }
    return CGPoint(x: anchor.x, y: anchor.y)
  }
}

/// `#RRGGBB` or `#RRGGBBAA` to a color; blue when malformed.
func parseHexColor(_ hex: String) -> UIColor {
  guard let rgba = UInt32(hex.dropFirst(), radix: 16) else {
    return UIColor(red: 0, green: 122 / 255, blue: 1, alpha: 1)
  }
  let value = hex.count == 7 ? (rgba << 8) | 255 : rgba
  return UIColor(
    red: CGFloat((value >> 24) & 255) / 255,
    green: CGFloat((value >> 16) & 255) / 255,
    blue: CGFloat((value >> 8) & 255) / 255,
    alpha: CGFloat(value & 255) / 255
  )
}

extension MapRoute {
  var lineColor: UIColor {
    parseHexColor(strokeColor ?? "#007AFF")
  }

  var lineWidth: CGFloat { strokeWidth ?? 4 }

  /// Dash and gap lengths in display points, or nil for a solid line.
  var lineDash: [CGFloat]? { dashPattern.map { $0.map { CGFloat($0) } } }
}

func sameRouteGeometry(_ a: [Coordinate], _ b: [Coordinate]) -> Bool {
  a.count == b.count && zip(a, b).allSatisfy {
    $0.0.latitude == $0.1.latitude && $0.0.longitude == $0.1.longitude
  }
}
