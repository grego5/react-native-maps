package com.margelo.nitro.mapssession

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PointF
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import kotlin.math.hypot

internal class SurfaceDrag(
  private val host: View,
  private val project: (Coordinate) -> PointF?,
  private val unproject: (PointF) -> Coordinate?,
  private val dispatchToMap: (MotionEvent) -> Boolean,
  private val emitDrag: (MapDragEvent) -> Unit,
  private val emitTap: (MapTap) -> Unit,
) {
  var pinEnabled = false
    set(value) {
      field = value
      if (!value && active?.let { it.route == null } == true) cancel()
    }
  var cameraMoving = false
    set(value) {
      field = value
      if (value) cancel()
    }

  private data class Drag(val route: MapRoute?, var point: PointF)
  private val main = Handler(Looper.getMainLooper())
  private val density = host.resources.displayMetrics.density
  private val slop = ViewConfiguration.get(host.context).scaledTouchSlop
  private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = 0xFF007AFF.toInt()
    strokeWidth = density * 3
    strokeCap = Paint.Cap.ROUND
  }
  private var routes: Map<String, MapRoute> = emptyMap()
  private var active: Drag? = null
  private var captured = false
  private var downTime = 0L
  private var origin = PointF()
  private val start = Runnable { begin() }

  fun dispatchTouch(event: MotionEvent): Boolean {
    if (event.actionMasked == MotionEvent.ACTION_DOWN) {
      cancel()
      captured = false
      val handled = dispatchToMap(event)
      if (handled && !cameraMoving) {
        origin = PointF(event.x, event.y)
        downTime = event.downTime
        main.postDelayed(start, 400)
      }
      return handled
    }

    when (event.actionMasked) {
      MotionEvent.ACTION_MOVE -> {
        val point = PointF(event.x, event.y)
        val drag = active
        if (drag != null) {
          drag.point = point.lifted()
          host.invalidate()
          dispatch(drag, MapDragPhase.MOVE)
        } else if (hypot(point.x - origin.x, point.y - origin.y) > slop) {
          main.removeCallbacks(start)
        }
      }
      MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_CANCEL -> cancel()
      MotionEvent.ACTION_UP -> {
        main.removeCallbacks(start)
        active?.let { drag ->
          drag.point = PointF(event.x, event.y).lifted()
          finish(MapDragPhase.END)
        }
      }
    }
    val consume = captured
    if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
      captured = false
    }
    return consume || dispatchToMap(event)
  }

  private fun begin() {
    if (cameraMoving) return
    val route = routeIdsAt(origin, forDrag = true).firstOrNull()?.let(routes::get)
    if (route == null && !pinEnabled) return
    val drag = Drag(route, origin.lifted())
    if (unproject(drag.point) == null) return
    val event = MotionEvent.obtain(
      downTime, SystemClock.uptimeMillis(), MotionEvent.ACTION_CANCEL, origin.x, origin.y, 0,
    )
    captured = true
    try {
      dispatchToMap(event)
    } finally {
      event.recycle()
    }
    if (cameraMoving) return
    active = drag
    host.parent?.requestDisallowInterceptTouchEvent(true)
    host.invalidate()
    dispatch(drag, MapDragPhase.START)
  }

  fun updateRoutes(routes: Map<String, MapRoute>) {
    this.routes = routes
    val route = active?.route ?: return
    if (!route.drag?.anchors.contentEquals(routes[route.id]?.drag?.anchors)) cancel()
  }

  fun mapTapped(coordinate: Coordinate, markerId: String?) {
    if (captured) return
    val point = project(coordinate) ?: return
    val ids = if (markerId == null) routeIdsAt(point) else emptyArray()
    emitTap(MapTap(coordinate, point.toMapPoint(), markerId, ids))
  }

  private fun routeIdsAt(point: PointF, forDrag: Boolean = false): Array<String> {
    val candidates = routes.values.mapNotNull { route ->
      if (forDrag && route.drag == null) return@mapNotNull null
      val radius = route.hitSlop ?: if (forDrag) 20.0 else return@mapNotNull null
      if (radius == 0.0) return@mapNotNull null
      val projected = FloatArray(route.coordinates.size * 2)
      for ((index, coordinate) in route.coordinates.withIndex()) {
        val pixel = project(coordinate) ?: return@mapNotNull null
        projected[index * 2] = pixel.x
        projected[index * 2 + 1] = pixel.y
      }
      PolylineHits.Candidate(route.id, projected, (radius * density).toFloat())
    }
    return PolylineHits.find(candidates, point.x, point.y).toTypedArray()
  }

  fun cancel() {
    main.removeCallbacks(start)
    finish(MapDragPhase.CANCEL)
  }

  private fun finish(phase: MapDragPhase) {
    val drag = active ?: return
    active = null
    host.parent?.requestDisallowInterceptTouchEvent(false)
    host.invalidate()
    dispatch(drag, phase)
  }

  fun draw(canvas: Canvas) {
    val drag = active ?: return
    val point = drag.point
    drag.route?.drag?.anchors?.forEach { anchor ->
      project(anchor)?.let { canvas.drawLine(it.x, it.y, point.x, point.y, paint) }
    }
    canvas.drawCircle(point.x, point.y, density * 6, paint)
  }

  private fun dispatch(drag: Drag, phase: MapDragPhase) {
    val coordinate = unproject(drag.point) ?: return
    emitDrag(MapDragEvent(phase, coordinate, drag.point.toMapPoint(), drag.route?.id))
  }

  private fun PointF.toMapPoint() = MapPoint(x.toDouble() / density, y.toDouble() / density)

  private fun PointF.lifted() = PointF(x, y - density * 32)
}
