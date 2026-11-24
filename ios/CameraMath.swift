import Foundation

/// North-up, flat Web Mercator camera math in display points, Google zoom levels, and 256-point
/// tiles. Mirrors `android/.../CameraMath.kt`; keep the formulas identical.
enum CameraMath {
  private static let tile = 256.0
  private static let noPadding = EdgePadding(top: 0, right: 0, bottom: 0, left: 0)

  /// East and west are unwrapped around the first coordinate, so an area across the antimeridian stays contiguous.
  struct Bounds {
    var north: Double
    var south: Double
    var east: Double
    var west: Double
  }

  enum Reveal: Equatable {
    case none
    case fit
    case pan(dx: Double, dy: Double)
  }

  static func bounds(_ coordinates: [Coordinate]) throws -> Bounds {
    guard let first = coordinates.first else {
      throw MapSurfaceError.invalidArgument("Camera operations need at least one coordinate")
    }
    var bounds = Bounds(north: first.latitude, south: first.latitude, east: first.longitude, west: first.longitude)
    for coordinate in coordinates {
      try requireCoordinate(coordinate)
      bounds.north = max(bounds.north, coordinate.latitude)
      bounds.south = min(bounds.south, coordinate.latitude)
      let longitude = first.longitude + positiveMod(coordinate.longitude - first.longitude + 540, 360) - 180
      bounds.east = max(bounds.east, longitude)
      bounds.west = min(bounds.west, longitude)
    }
    return bounds
  }

  /// The camera that shows `bounds` centered in the area inside `padding` of a `width` by `height`
  /// view, at the closest zoom that fits, never closer than `maxZoom`. A single point keeps
  /// `currentZoom`, capped by `maxZoom`.
  static func fit(
    _ bounds: Bounds, width: Double, height: Double, padding: EdgePadding?, maxZoom: Double?, currentZoom: Double
  ) throws -> MapCamera {
    let inset = try self.padding(padding)
    if let maxZoom, !maxZoom.isFinite { throw MapSurfaceError.invalidArgument("maxZoom must be finite") }
    let innerWidth = width - inset.left - inset.right
    let innerHeight = height - inset.top - inset.bottom
    guard innerWidth > 0, innerHeight > 0 else {
      throw MapSurfaceError.invalidArgument("Padding leaves no visible area")
    }
    let northY = mercatorY(bounds.north)
    let southY = mercatorY(bounds.south)
    let fitted = min(
      fitZoom(innerWidth, (bounds.east - bounds.west) / 360),
      fitZoom(innerHeight, (northY - southY) / (2 * .pi))
    )
    let zoom = min(fitted.isInfinite ? currentZoom : fitted, maxZoom ?? .infinity)
    let center = Coordinate(
      latitude: fromMercatorY((northY + southY) / 2),
      longitude: wrapLongitude((bounds.east + bounds.west) / 2)
    )
    return MapCamera(center: try paddedCenter(center, zoom: zoom, padding: inset), zoom: zoom)
  }

  /// The camera center that shows `center` at the middle of the area inside `padding`.
  static func paddedCenter(_ center: Coordinate, zoom: Double, padding: EdgePadding?) throws -> Coordinate {
    let inset = try self.padding(padding)
    return offset(center, zoom: zoom, dx: (inset.right - inset.left) / 2, dy: (inset.bottom - inset.top) / 2)
  }

  /// The coordinate `dx`, `dy` points from `center` at `zoom`; y grows downward.
  static func offset(_ center: Coordinate, zoom: Double, dx: Double, dy: Double) -> Coordinate {
    let worldPoints = tile * pow(2, zoom)
    return Coordinate(
      latitude: fromMercatorY(mercatorY(center.latitude) - dy * 2 * .pi / worldPoints),
      longitude: wrapLongitude(center.longitude + dx * 360 / worldPoints)
    )
  }

  /// How to bring screen `points` inside `padding` of a `width` by `height` view: not at all, by
  /// the smallest pan, or by a fit when they do not fit at the current zoom.
  static func reveal(_ points: [MapPoint], width: Double, height: Double, padding: EdgePadding?) throws -> Reveal {
    let inset = try self.padding(padding)
    guard !points.isEmpty else { return .none }
    let left = points.map(\.x).min()!
    let right = points.map(\.x).max()!
    let top = points.map(\.y).min()!
    let bottom = points.map(\.y).max()!
    if right - left > width - inset.left - inset.right || bottom - top > height - inset.top - inset.bottom {
      return .fit
    }
    let dx = left < inset.left ? left - inset.left : max(0, right - width + inset.right)
    let dy = top < inset.top ? top - inset.top : max(0, bottom - height + inset.bottom)
    return dx == 0 && dy == 0 ? .none : .pan(dx: dx, dy: dy)
  }

  static func padding(_ padding: EdgePadding?) throws -> EdgePadding {
    guard let padding else { return noPadding }
    guard [padding.top, padding.right, padding.bottom, padding.left].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
      throw MapSurfaceError.invalidArgument("Padding must be finite and nonnegative")
    }
    return padding
  }

  /// Milliseconds; zero moves at once.
  static func duration(_ duration: Double?) throws -> Double {
    guard let duration else { return 0 }
    guard duration.isFinite, duration >= 0 else {
      throw MapSurfaceError.invalidArgument("Duration must be finite and nonnegative")
    }
    return duration
  }

  static func requireCoordinate(_ coordinate: Coordinate) throws {
    guard abs(coordinate.latitude) <= 90, abs(coordinate.longitude) <= 180 else {
      throw MapSurfaceError.invalidArgument("Map coordinate is out of range")
    }
  }

  static func requireZoom(_ zoom: Double) throws {
    guard zoom.isFinite else { throw MapSurfaceError.invalidArgument("Zoom must be finite") }
  }

  private static func fitZoom(_ points: Double, _ worldFraction: Double) -> Double {
    worldFraction > 0 ? log2(points / (tile * worldFraction)) : .infinity
  }

  private static func mercatorY(_ latitude: Double) -> Double { log(tan(.pi / 4 + latitude * .pi / 360)) }
  private static func fromMercatorY(_ y: Double) -> Double { atan(exp(y)) * 360 / .pi - 90 }
  private static func wrapLongitude(_ longitude: Double) -> Double { positiveMod(longitude + 540, 360) - 180 }

  private static func positiveMod(_ value: Double, _ modulus: Double) -> Double {
    let remainder = value.truncatingRemainder(dividingBy: modulus)
    return remainder < 0 ? remainder + modulus : remainder
  }
}
