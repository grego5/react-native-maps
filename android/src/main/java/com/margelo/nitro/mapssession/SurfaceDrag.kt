package com.margelo.nitro.mapssession

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
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

  /** Styles a standalone pin drag; route drags use their route's `drag.preview`. */
  var pinPreview: DragPreview? = null
    set(value) {
      field = value
      loadPreviewImages()
    }

  /** The preview chosen at drag start, with paints built once per drag. */
  private class Drag(
    val route: MapRoute?,
    /** Every draggable route under the press, nearest first, fixed for the whole drag. */
    val routeIds: Array<String>,
    var point: PointF,
    val preview: DragPreview?,
    density: Float,
  ) {
    val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      style = Paint.Style.STROKE
      color = parseHexColor(preview?.strokeColor) ?: DEFAULT_COLOR
      strokeWidth = density * (preview?.strokeWidth ?: 3.0).toFloat()
      strokeCap = Paint.Cap.ROUND
      preview?.dashPattern?.let { lengths ->
        pathEffect = DashPathEffect(FloatArray(lengths.size) { (lengths[it] * density).toFloat() }, 0f)
      }
    }
    val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = stroke.color }
    val path = Path()
  }
  private val main = Handler(Looper.getMainLooper())
  private val density = host.resources.displayMetrics.density
  private val slop = ViewConfiguration.get(host.context).scaledTouchSlop
  /** Preview images, loaded when previews change so a drag never waits on I/O. Null while loading or failed. */
  private var previewImages: Map<MarkerImage, Bitmap?> = emptyMap()
  private var routes: Map<String, MapRoute> = emptyMap()
  /** Markers in input order, for drop and query hits. */
  private var markers: List<MapMarker> = emptyList()
  /** Display points around the drop point searched for markers on END. */
  var dropRadius = 0.0
  private var active: Drag? = null
  private var captured = false
  /** True while a drag owns the current touch. */
  val isCapturing: Boolean get() = captured
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
    val routeIds = routeIdsAt(origin, forDrag = true)
    val route = routeIds.firstOrNull()?.let(routes::get)
    if (route == null && !pinEnabled) return
    val preview = if (route != null) route.drag?.preview else pinPreview
    val drag = Drag(route, routeIds, origin.lifted(), preview, density)
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
    loadPreviewImages()
    val route = active?.route ?: return
    if (!route.drag?.anchors.contentEquals(routes[route.id]?.drag?.anchors)) cancel()
  }

  fun updateMarkers(markers: List<MapMarker>) {
    this.markers = markers
  }

  /** Markers and routes near `point` in display points, nearest first. */
  fun queryFeatures(point: MapPoint, radius: Double): MapFeatureHits {
    require(radius.isFinite() && radius >= 0) { "Radius must be finite and nonnegative" }
    val pixel = PointF((point.x * density).toFloat(), (point.y * density).toFloat())
    return MapFeatureHits(markersNear(pixel, radius), routeIdsAt(pixel, minRadius = radius))
  }

  /** Markers whose coordinate projects within `radius` points of `point`, nearest first, then input order. */
  private fun markersNear(point: PointF, radius: Double): Array<String> {
    if (radius <= 0) return emptyArray()
    val limit = radius * density
    return markers.mapIndexedNotNull { index, marker ->
      val projected = project(marker.coordinate) ?: return@mapIndexedNotNull null
      val distance = hypot((projected.x - point.x).toDouble(), (projected.y - point.y).toDouble())
      if (distance <= limit) Triple(marker.id, distance, index) else null
    }.sortedWith(compareBy({ it.second }, { it.third })).map { it.first }.toTypedArray()
  }

  fun mapTapped(coordinate: Coordinate, markerId: String?) {
    if (captured) return
    val point = project(coordinate) ?: return
    val ids = if (markerId == null) routeIdsAt(point) else emptyArray()
    emitTap(MapTap(coordinate, point.toMapPoint(), markerId, ids))
  }

  /** Routes within the larger of `minRadius` and their slop: `hitSlop`, or 20 points for drags. */
  private fun routeIdsAt(point: PointF, forDrag: Boolean = false, minRadius: Double = 0.0): Array<String> {
    val candidates = routes.values.mapNotNull { route ->
      if (forDrag && route.drag == null) return@mapNotNull null
      val radius = maxOf(route.hitSlop ?: if (forDrag) 20.0 else 0.0, minRadius)
      if (radius <= 0.0) return@mapNotNull null
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

  /** Requests every image the current previews use and drops the ones no longer used. */
  private fun loadPreviewImages() {
    val wanted = routes.values.mapNotNullTo(HashSet()) { it.drag?.preview?.image }
    pinPreview?.image?.let(wanted::add)
    if (wanted == previewImages.keys) return
    previewImages = wanted.associateWith { previewImages[it] }
    for (image in wanted) {
      if (previewImages[image] != null) continue
      MarkerImages.load(host.context, image) { result ->
        val bitmap = result.getOrNull() ?: return@load
        if (image in previewImages) {
          previewImages = previewImages + (image to bitmap)
          if (active != null) host.invalidate()
        }
      }
    }
  }

  fun draw(canvas: Canvas) {
    val drag = active ?: return
    val point = drag.point
    val anchors = drag.route?.drag?.anchors
    if (!anchors.isNullOrEmpty()) {
      drag.path.rewind()
      for (anchor in anchors) {
        val start = project(anchor) ?: continue
        drag.path.moveTo(start.x, start.y)
        drag.path.lineTo(point.x, point.y)
      }
      canvas.drawPath(drag.path, drag.stroke)
    }
    val image = drag.preview?.image
    val bitmap = image?.let { previewImages[it] }
    if (bitmap == null) {
      canvas.drawCircle(point.x, point.y, density * 6, drag.fill)
    } else {
      val anchor = drag.preview?.anchor
      val left = point.x - (anchor?.x ?: 0.5).toFloat() * bitmap.width
      val top = point.y - (anchor?.y ?: 1.0).toFloat() * bitmap.height
      canvas.drawBitmap(bitmap, left, top, null)
    }
  }

  private fun dispatch(drag: Drag, phase: MapDragPhase) {
    val coordinate = unproject(drag.point) ?: return
    val markerIds = if (phase == MapDragPhase.END) markersNear(drag.point, dropRadius) else emptyArray()
    emitDrag(MapDragEvent(phase, coordinate, drag.point.toMapPoint(), drag.route?.id, drag.routeIds, markerIds))
  }

  private fun PointF.toMapPoint() = MapPoint(x.toDouble() / density, y.toDouble() / density)

  private fun PointF.lifted() = PointF(x, y - density * 32)

  private companion object {
    const val DEFAULT_COLOR = 0xFF007AFF.toInt()
  }
}

/** `#RRGGBB` or `#RRGGBBAA` to an Android color, or null when absent. */
internal fun parseHexColor(hex: String?): Int? {
  if (hex == null) return null
  val rgb = if (hex.length == 9) hex.substring(1, 7) else hex.substring(1)
  val alpha = if (hex.length == 9) hex.substring(7) else "FF"
  return Color.parseColor("#$alpha$rgb")
}
