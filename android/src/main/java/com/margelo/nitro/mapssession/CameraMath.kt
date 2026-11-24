package com.margelo.nitro.mapssession

import kotlin.math.PI
import kotlin.math.atan
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.log2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.tan

/**
 * North-up, flat Web Mercator camera math in display points, Google zoom levels, and 256-point
 * tiles. Mirrored by `ios/CameraMath.swift`; keep the formulas identical.
 */
internal object CameraMath {
  private const val TILE = 256.0
  private val NO_PADDING = EdgePadding(0.0, 0.0, 0.0, 0.0)

  /** East and west are unwrapped around the first coordinate, so an area across the antimeridian stays contiguous. */
  data class Bounds(val north: Double, val south: Double, val east: Double, val west: Double)

  sealed interface Reveal {
    data object None : Reveal
    data object Fit : Reveal
    data class Pan(val dx: Double, val dy: Double) : Reveal
  }

  fun bounds(coordinates: Array<Coordinate>): Bounds {
    require(coordinates.isNotEmpty()) { "Camera operations need at least one coordinate" }
    coordinates.forEach(::requireCoordinate)
    val first = coordinates[0]
    var north = first.latitude
    var south = first.latitude
    var east = first.longitude
    var west = first.longitude
    for (coordinate in coordinates) {
      north = max(north, coordinate.latitude)
      south = min(south, coordinate.latitude)
      val longitude = first.longitude + (coordinate.longitude - first.longitude + 540).mod(360.0) - 180
      east = max(east, longitude)
      west = min(west, longitude)
    }
    return Bounds(north, south, east, west)
  }

  /**
   * The camera that shows `bounds` centered in the area inside `padding` of a `width` by `height`
   * view, at the closest zoom that fits, never closer than `maxZoom`. A single point keeps
   * `currentZoom`, capped by `maxZoom`.
   */
  fun fit(bounds: Bounds, width: Double, height: Double, padding: EdgePadding?, maxZoom: Double?, currentZoom: Double): MapCamera {
    val inset = padding(padding)
    require(maxZoom == null || maxZoom.isFinite()) { "maxZoom must be finite" }
    val innerWidth = width - inset.left - inset.right
    val innerHeight = height - inset.top - inset.bottom
    require(innerWidth > 0 && innerHeight > 0) { "Padding leaves no visible area" }
    val northY = mercatorY(bounds.north)
    val southY = mercatorY(bounds.south)
    val fitted = min(fitZoom(innerWidth, (bounds.east - bounds.west) / 360), fitZoom(innerHeight, (northY - southY) / (2 * PI)))
    val zoom = min(if (fitted.isInfinite()) currentZoom else fitted, maxZoom ?: Double.POSITIVE_INFINITY)
    val center = Coordinate(fromMercatorY((northY + southY) / 2), wrapLongitude((bounds.east + bounds.west) / 2))
    return MapCamera(paddedCenter(center, zoom, inset), zoom)
  }

  /** The camera center that shows `center` at the middle of the area inside `padding`. */
  fun paddedCenter(center: Coordinate, zoom: Double, padding: EdgePadding?): Coordinate {
    val inset = padding(padding)
    return offset(center, zoom, (inset.right - inset.left) / 2, (inset.bottom - inset.top) / 2)
  }

  /** The coordinate `dx`, `dy` points from `center` at `zoom`; y grows downward. */
  fun offset(center: Coordinate, zoom: Double, dx: Double, dy: Double): Coordinate {
    val worldPoints = TILE * 2.0.pow(zoom)
    return Coordinate(
      fromMercatorY(mercatorY(center.latitude) - dy * 2 * PI / worldPoints),
      wrapLongitude(center.longitude + dx * 360 / worldPoints),
    )
  }

  /**
   * How to bring screen `points` inside `padding` of a `width` by `height` view: not at all, by
   * the smallest pan, or by a fit when they do not fit at the current zoom.
   */
  fun reveal(points: List<MapPoint>, width: Double, height: Double, padding: EdgePadding?): Reveal {
    val inset = padding(padding)
    if (points.isEmpty()) return Reveal.None
    val left = points.minOf { it.x }
    val right = points.maxOf { it.x }
    val top = points.minOf { it.y }
    val bottom = points.maxOf { it.y }
    if (right - left > width - inset.left - inset.right || bottom - top > height - inset.top - inset.bottom) {
      return Reveal.Fit
    }
    val dx = if (left < inset.left) left - inset.left else max(0.0, right - width + inset.right)
    val dy = if (top < inset.top) top - inset.top else max(0.0, bottom - height + inset.bottom)
    return if (dx == 0.0 && dy == 0.0) Reveal.None else Reveal.Pan(dx, dy)
  }

  fun padding(padding: EdgePadding?): EdgePadding {
    val inset = padding ?: return NO_PADDING
    require(listOf(inset.top, inset.right, inset.bottom, inset.left).all { it.isFinite() && it >= 0 }) {
      "Padding must be finite and nonnegative"
    }
    return inset
  }

  /** Milliseconds; zero moves at once. */
  fun duration(duration: Double?): Double {
    val value = duration ?: return 0.0
    require(value.isFinite() && value >= 0) { "Duration must be finite and nonnegative" }
    return value
  }

  fun requireCoordinate(coordinate: Coordinate) {
    require(kotlin.math.abs(coordinate.latitude) <= 90 && kotlin.math.abs(coordinate.longitude) <= 180) {
      "Map coordinate is out of range"
    }
  }

  fun requireZoom(zoom: Double) {
    require(zoom.isFinite()) { "Zoom must be finite" }
  }

  private fun fitZoom(points: Double, worldFraction: Double) =
    if (worldFraction > 0) log2(points / (TILE * worldFraction)) else Double.POSITIVE_INFINITY

  private fun mercatorY(latitude: Double) = ln(tan(PI / 4 + latitude * PI / 360))
  private fun fromMercatorY(y: Double) = atan(exp(y)) * 360 / PI - 90
  private fun wrapLongitude(longitude: Double) = (longitude + 540).mod(360.0) - 180
}
