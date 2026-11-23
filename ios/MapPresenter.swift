import CoreLocation
import UIKit

protocol MapPresenter: AnyObject {
  var view: UIView { get }
  var onRendered: (() -> Void)? { get set }
  var onSDKTap: ((CLLocationCoordinate2D, String?) -> Void)? { get set }
  var needsMapTapRecognizer: Bool { get }
  func marker(at point: CGPoint) -> (id: String, coordinate: CLLocationCoordinate2D)?
  func suspendCameraGestures() -> () -> Void
  var onCameraMoving: ((Bool) -> Void)? { get set }

  func apply(_ features: MapFeatures)
  func clearFeatures()
  func setCamera(_ center: CLLocationCoordinate2D, zoom: Double, animated: Bool)
  func project(_ coordinate: CLLocationCoordinate2D) -> CGPoint
  func unproject(_ point: CGPoint) -> CLLocationCoordinate2D
  func snapshot(_ complete: @escaping (Result<UIImage, Error>) -> Void) throws
  func close()
}

extension MapPresenter {
  var needsMapTapRecognizer: Bool { false }

  func marker(at point: CGPoint) -> (id: String, coordinate: CLLocationCoordinate2D)? { nil }
}

enum MapSurfaceError: LocalizedError {
  case detached
  case notReady
  case providerUnavailable
  case snapshotFailed

  var errorDescription: String? {
    switch self {
    case .detached: return "MapSurface is detached"
    case .notReady: return "MapSurface is not ready"
    case .providerUnavailable: return "This map provider is unavailable in the current build"
    case .snapshotFailed: return "The map snapshot could not be created"
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

extension MapRoute {
  var lineColor: UIColor {
    guard let strokeColor, let rgba = UInt32(strokeColor.dropFirst(), radix: 16) else {
      return UIColor(red: 0, green: 122 / 255, blue: 1, alpha: 1)
    }
    let value = strokeColor.count == 7 ? (rgba << 8) | 255 : rgba
    return UIColor(
      red: CGFloat((value >> 24) & 255) / 255,
      green: CGFloat((value >> 16) & 255) / 255,
      blue: CGFloat((value >> 8) & 255) / 255,
      alpha: CGFloat(value & 255) / 255
    )
  }

  var lineWidth: CGFloat { strokeWidth ?? 4 }
}

func sameRouteGeometry(_ a: [Coordinate], _ b: [Coordinate]) -> Bool {
  a.count == b.count && zip(a, b).allSatisfy {
    $0.0.latitude == $0.1.latitude && $0.0.longitude == $0.1.longitude
  }
}
