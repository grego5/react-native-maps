package com.margelo.nitro.mapssession

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/** Expected values come from the route planner's `getFittedCamera` and `getPaddedCenter`. */
class CameraMathTest {
  private val points = arrayOf(Coordinate(38.5, -120.2), Coordinate(40.7, -120.95))
  private val padding = EdgePadding(top = 40.0, right = 20.0, bottom = 200.0, left = 20.0)

  private fun assertCamera(latitude: Double, longitude: Double, zoom: Double, camera: MapCamera) {
    assertEquals(latitude, camera.center.latitude, 1e-9)
    assertEquals(longitude, camera.center.longitude, 1e-9)
    assertEquals(zoom, camera.zoom, 1e-9)
  }

  @Test
  fun fitMatchesPlanner() {
    val camera = CameraMath.fit(CameraMath.bounds(points), 400.0, 800.0, padding, 15.0, 3.0)
    assertCamera(39.293732619494165, -120.575, 8.107314269950695, camera)
  }

  @Test
  fun maxZoomCapsFit() {
    val camera = CameraMath.fit(CameraMath.bounds(points), 400.0, 800.0, padding, 6.0, 3.0)
    assertCamera(38.24128854292019, -120.575, 6.0, camera)
  }

  @Test
  fun singlePointKeepsCurrentZoomUnderMaxZoom() {
    val bounds = CameraMath.bounds(arrayOf(Coordinate(10.0, 20.0)))
    assertEquals(12.0, CameraMath.fit(bounds, 400.0, 800.0, null, 15.0, 12.0).zoom, 0.0)
    assertEquals(15.0, CameraMath.fit(bounds, 400.0, 800.0, null, 15.0, 18.0).zoom, 0.0)
  }

  @Test
  fun boundsCrossTheAntimeridian() {
    val bounds = CameraMath.bounds(arrayOf(Coordinate(0.0, 170.0), Coordinate(10.0, -170.0)))
    assertEquals(20.0, bounds.east - bounds.west, 1e-9)
    val camera = CameraMath.fit(bounds, 400.0, 800.0, null, 20.0, 3.0)
    assertCamera(5.019148099025145, -180.0, 4.813781191217037, camera)
  }

  @Test
  fun paddedCenterShiftsTowardThePaddedArea() {
    val center = Coordinate(38.5, -120.2)
    val shifted = CameraMath.paddedCenter(center, 14.0, EdgePadding(0.0, 0.0, 300.0, 0.0))
    // `center` sits 150 points above the camera center, so the camera center is south of it.
    val back = CameraMath.offset(shifted, 14.0, 0.0, -150.0)
    assertEquals(center.latitude, back.latitude, 1e-9)
    assertEquals(center.longitude, back.longitude, 1e-9)
    assert(shifted.latitude < center.latitude)
  }

  @Test
  fun revealCases() {
    fun reveal(vararg xy: Double) =
      CameraMath.reveal(xy.toList().chunked(2).map { MapPoint(it[0], it[1]) }, 400.0, 800.0, padding)
    assertEquals(CameraMath.Reveal.None, reveal(100.0, 100.0, 300.0, 500.0))
    assertEquals(CameraMath.Reveal.Pan(-10.0, 0.0), reveal(10.0, 100.0))
    assertEquals(CameraMath.Reveal.Pan(10.0, 0.0), reveal(390.0, 100.0))
    assertEquals(CameraMath.Reveal.Pan(0.0, -10.0), reveal(100.0, 30.0))
    assertEquals(CameraMath.Reveal.Pan(0.0, 10.0), reveal(100.0, 610.0))
    assertEquals(CameraMath.Reveal.Fit, reveal(0.0, 0.0, 400.0, 0.0))
  }

  @Test
  fun invalidInputRejects() {
    assertThrows(IllegalArgumentException::class.java) { CameraMath.bounds(emptyArray()) }
    assertThrows(IllegalArgumentException::class.java) { CameraMath.bounds(arrayOf(Coordinate(91.0, 0.0))) }
    assertThrows(IllegalArgumentException::class.java) { CameraMath.padding(EdgePadding(-1.0, 0.0, 0.0, 0.0)) }
    assertThrows(IllegalArgumentException::class.java) { CameraMath.padding(EdgePadding(Double.NaN, 0.0, 0.0, 0.0)) }
    assertThrows(IllegalArgumentException::class.java) { CameraMath.duration(-1.0) }
    assertThrows(IllegalArgumentException::class.java) {
      CameraMath.fit(CameraMath.bounds(points), 400.0, 800.0, null, Double.POSITIVE_INFINITY, 3.0)
    }
    assertThrows(IllegalArgumentException::class.java) {
      CameraMath.fit(CameraMath.bounds(points), 400.0, 800.0, EdgePadding(0.0, 200.0, 0.0, 200.0), null, 3.0)
    }
  }
}
