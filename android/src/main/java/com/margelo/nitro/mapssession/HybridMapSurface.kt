package com.margelo.nitro.mapssession

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Canvas
import android.graphics.Point
import android.graphics.PointF
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.Keep
import com.facebook.react.bridge.LifecycleEventListener
import com.facebook.react.common.LifecycleState
import com.facebook.react.uimanager.ThemedReactContext
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.MapView
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.Marker
import com.google.android.gms.maps.model.MarkerOptions
import com.google.android.gms.maps.model.Polyline
import com.google.android.gms.maps.model.PolylineOptions
import com.margelo.nitro.core.Promise
import java.io.File
import java.lang.ref.WeakReference
import java.util.concurrent.Executors
import kotlin.math.roundToInt

@Keep
class HybridMapSurface @JvmOverloads constructor(
  private val reactContext: ThemedReactContext? = null,
) : HybridMapSurfaceSpec(), LifecycleEventListener {
  private val main = Handler(Looper.getMainLooper())
  private var host: SurfaceHost? = null
  private var nativeMapView: MapView? = null
  private var map: GoogleMap? = null
  private var attached = false
  private var resumed = false
  private var dropped = false
  private var signalledReady = false
  private var rendered = false
  private var signalledRendered = false
  private var featuresDirty = true
  private var hasFeatures = false
  private val markers = mutableMapOf<String, Marker>()
  private class IconRequest(val source: MarkerImage)
  private val markerIcons = mutableMapOf<String, IconRequest>()
  private val routes = mutableMapOf<String, Polyline>()
  private var appliedRoutes: Map<String, MapRoute> = emptyMap()
  private val snapshots = mutableSetOf<Promise<String>>()

  override var features = MapFeatures(emptyArray(), emptyArray())
    set(value) {
      field = value
      featuresDirty = true
    }
  override var provider: MapProvider = MapProvider.GOOGLE
  override var onReady: (() -> Unit)? = null
  override var onRendered: (() -> Unit)? = null
  override var onTap: ((event: MapTap) -> Unit)? = null
  override var pinDragEnabled: Boolean? = null
  override var onDrag: ((event: MapDragEvent) -> Unit)? = null

  override val view: View
    get() {
      host?.let { return it }
      val context = checkNotNull(reactContext) { "MapSurface must be mounted by React Native" }
      return SurfaceHost(context).also { host = it }
    }

  override fun afterUpdate() {
    if (!attached || dropped) return
    if (provider != MapProvider.GOOGLE) {
      releaseMap()
      return
    }
    host?.drag?.pinEnabled = pinDragEnabled == true
    ensureMap()
    applyFeatures()
    signalReady()
  }

  private fun ensureMap() {
    if (nativeMapView != null || provider != MapProvider.GOOGLE) return
    val context = checkNotNull(reactContext)
    val view = MapView(context)
    nativeMapView = view
    checkNotNull(host).addView(
      view,
      FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT),
    )
    view.onCreate(null)
    view.onStart()
    if (context.lifecycleState == LifecycleState.RESUMED) resumeMap()
    view.getMapAsync { liveMap ->
      if (nativeMapView !== view || dropped) return@getMapAsync
      map = liveMap
      liveMap.setOnMapLoadedCallback {
        if (map === liveMap && attached && !dropped) {
          rendered = true
          signalReady()
        }
      }
      liveMap.setOnCameraMoveStartedListener {
        if (map === liveMap) host?.drag?.cameraMoving = true
      }
      liveMap.setOnCameraIdleListener {
        if (map === liveMap) host?.drag?.cameraMoving = false
      }
      liveMap.setOnMapClickListener { coordinate -> reportTap(liveMap, coordinate, null) }
      liveMap.setOnMarkerClickListener { marker ->
        reportTap(liveMap, marker.position, marker.tag as? String)
        false
      }
      applyFeatures()
      signalReady()
    }
  }

  private fun signalReady() {
    if (!attached || map == null || !hasFeatures) return
    if (!signalledReady) onReady?.let {
      signalledReady = true
      it()
    }
    if (rendered && !signalledRendered) onRendered?.let {
      signalledRendered = true
      it()
    }
  }

  private fun clearFeatures() {
    host?.drag?.cancel()
    markers.values.forEach(Marker::remove)
    routes.values.forEach(Polyline::remove)
    markers.clear()
    markerIcons.clear()
    routes.clear()
    appliedRoutes = emptyMap()
    host?.drag?.updateRoutes(appliedRoutes)
  }

  private fun applyFeatures() {
    val liveMap = map ?: return
    if (!featuresDirty) return
    featuresDirty = false
    val markerIds = features.markers.mapTo(HashSet()) { it.id }
    markers.entries.removeAll { (id, marker) ->
      if (id in markerIds) false else {
        markerIcons.remove(id)
        marker.remove()
        true
      }
    }
    val context = checkNotNull(reactContext)
    for (marker in features.markers) {
      val position = marker.coordinate.toLatLng()
      val native = markers[marker.id] ?: liveMap.addMarker(
        MarkerOptions().position(position).title(marker.title),
      )?.also {
        it.tag = marker.id
        markers[marker.id] = it
      } ?: continue
      if (native.position != position) native.position = position
      if (native.title != marker.title) native.title = marker.title
      updateMarkerIcon(context, marker.id, native, marker.image)
    }

    val routeIds = features.routes.mapTo(HashSet()) { it.id }
    routes.entries.removeAll { (id, line) ->
      if (id in routeIds) false else {
        line.remove()
        true
      }
    }
    val orderedRoutes = features.routes.sortedBy { it.zIndex ?: 0.0 }
    for ((index, route) in orderedRoutes.withIndex()) {
      val existing = routes[route.id]
      val order = index.toFloat()
      val width = ((route.strokeWidth ?: 4.0) * context.resources.displayMetrics.density)
        .coerceAtMost(Float.MAX_VALUE.toDouble()).toFloat()
      val color = route.strokeColor?.let { hex ->
        val rgb = if (hex.length == 9) hex.substring(1, 7) else hex.substring(1)
        val alpha = if (hex.length == 9) hex.substring(7) else "FF"
        Color.parseColor("#$alpha$rgb")
      } ?: Color.rgb(0, 122, 255)
      if (existing == null) {
        routes[route.id] = liveMap.addPolyline(
          PolylineOptions()
            .addAll(route.coordinates.map { it.toLatLng() })
            .width(width)
            .color(color)
            .zIndex(order),
        )
      } else {
        if (!route.coordinates.contentEquals(appliedRoutes[route.id]?.coordinates)) {
          existing.points = route.coordinates.map { it.toLatLng() }
        }
        if (existing.zIndex != order) existing.zIndex = order
        if (existing.width != width) existing.width = width
        if (existing.color != color) existing.color = color
      }
    }
    appliedRoutes = features.routes.associateBy { it.id }
    host?.drag?.updateRoutes(appliedRoutes)
    hasFeatures = true
    signalReady()
  }

  private fun updateMarkerIcon(context: Context, id: String, marker: Marker, source: MarkerImage?) {
    if (markerIcons[id]?.source == source) return
    marker.setIcon(null)
    if (source == null) {
      markerIcons.remove(id)
      return
    }
    val request = IconRequest(source)
    markerIcons[id] = request
    val owner = WeakReference(this)
    MarkerImages.load(context, source) { result ->
      val current = owner.get() ?: return@load
      if (current.markerIcons[id] !== request) return@load
      val bitmap = result.getOrNull() ?: return@load
      current.markers[id]?.setIcon(BitmapDescriptorFactory.fromBitmap(bitmap))
    }
  }

  private fun reportTap(liveMap: GoogleMap, coordinate: LatLng, markerId: String?) {
    if (!attached || map !== liveMap || dropped || onTap == null) return
    host?.drag?.mapTapped(coordinate.toCoordinate(), markerId)
  }

  private fun <T> withMap(action: (GoogleMap) -> T): Promise<T> {
    val promise = Promise<T>()
    main.post {
      try {
        promise.resolve(action(requireLiveMap()))
      } catch (error: Exception) {
        promise.reject(error)
      }
    }
    return promise
  }

  private fun requireLiveMap(): GoogleMap {
    check(provider == MapProvider.GOOGLE) { "Apple Maps is unavailable on Android" }
    check(attached && !dropped) { "MapSurface is detached" }
    return checkNotNull(map) { "MapSurface is not ready" }
  }

  override fun setCamera(center: Coordinate, zoom: Double, animated: Boolean) = withMap { liveMap ->
    host?.drag?.cancel()
    val update = CameraUpdateFactory.newLatLngZoom(center.toLatLng(), zoom.toFloat())
    if (animated) liveMap.animateCamera(update) else liveMap.moveCamera(update)
  }

  override fun project(coordinate: Coordinate) = withMap { liveMap ->
    val point = liveMap.projection.toScreenLocation(coordinate.toLatLng())
    val density = checkNotNull(reactContext).resources.displayMetrics.density.toDouble()
    MapPoint(point.x / density, point.y / density)
  }

  override fun unproject(point: MapPoint) = withMap { liveMap ->
    val density = checkNotNull(reactContext).resources.displayMetrics.density
    liveMap.projection.fromScreenLocation(Point((point.x * density).roundToInt(), (point.y * density).roundToInt())).toCoordinate()
  }

  override fun cancelDrag() = withMap { host?.drag?.cancel(); Unit }

  override fun takeSnapshot(): Promise<String> {
    val promise = Promise<String>()
    main.post {
      try {
        val liveMap = requireLiveMap()
        val view = checkNotNull(nativeMapView)
        check(resumed && rendered && view.width > 0 && view.height > 0) {
          "MapSurface must render a frame in the foreground before taking a snapshot"
        }
        val destination = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        snapshots.add(promise)
        liveMap.snapshot({ bitmap ->
          if (!snapshots.contains(promise)) return@snapshot
          if (bitmap == null) {
            snapshots.remove(promise)
            promise.reject(IllegalStateException("The map returned an empty snapshot"))
          } else {
            writeSnapshot(bitmap, promise)
          }
        }, destination)
      } catch (error: Exception) {
        snapshots.remove(promise)
        promise.reject(error)
      }
    }
    return promise
  }

  private fun writeSnapshot(bitmap: Bitmap, promise: Promise<String>) {
    val directory = checkNotNull(reactContext).cacheDir
    snapshotWriter.execute {
      var file: File? = null
      val result = runCatching {
        val destination = File.createTempFile("nitro-map-", ".png", directory)
        file = destination
        destination.outputStream().use {
          check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) { "Map snapshot encoding failed" }
        }
        destination.toURI().toString()
      }
      main.post {
        if (!snapshots.remove(promise)) {
          file?.delete()
          return@post
        }
        result.fold(promise::resolve) {
          file?.delete()
          promise.reject(it)
        }
      }
    }
  }

  private fun rejectSnapshots() {
    val pending = snapshots.toList()
    snapshots.clear()
    pending.forEach { it.reject(IllegalStateException("MapSurface detached during snapshot")) }
  }

  private fun resumeMap() {
    if (resumed) return
    val view = nativeMapView ?: return
    view.onResume()
    resumed = true
  }

  override fun onHostResume() {
    if (attached && !dropped) resumeMap()
  }

  override fun onHostPause() {
    host?.drag?.cancel()
    if (!resumed) return
    nativeMapView?.onPause()
    resumed = false
  }

  override fun onHostDestroy() {
    releaseMap()
  }

  private fun releaseMap() {
    featuresDirty = true
    hasFeatures = false
    rejectSnapshots()
    clearFeatures()
    onHostPause()
    nativeMapView?.let { view ->
      view.onStop()
      view.onDestroy()
      host?.removeView(view)
    }
    nativeMapView = null
    map = null
    host?.drag?.cameraMoving = false
    signalledReady = false
    rendered = false
    signalledRendered = false
  }

  override fun onDropView() {
    if (dropped) return
    dropped = true
    reactContext?.removeLifecycleEventListener(this)
    releaseMap()
    onReady = null
    onRendered = null
    onTap = null
    onDrag = null
    features = MapFeatures(emptyArray(), emptyArray())
  }

  private inner class SurfaceHost(context: Context) : FrameLayout(context) {
    val drag = SurfaceDrag(
      this,
      project = { coordinate ->
        map?.projection?.toScreenLocation(coordinate.toLatLng())?.let { PointF(it.x.toFloat(), it.y.toFloat()) }
      },
      unproject = { point ->
        map?.projection?.fromScreenLocation(Point(point.x.roundToInt(), point.y.roundToInt()))?.toCoordinate()
      },
      dispatchToMap = { event -> super.dispatchTouchEvent(event) },
      emitDrag = { event -> onDrag?.invoke(event) },
      emitTap = { event -> onTap?.invoke(event) },
    )

    override fun dispatchTouchEvent(event: MotionEvent): Boolean =
      drag.dispatchTouch(event)

    override fun dispatchDraw(canvas: Canvas) {
      super.dispatchDraw(canvas)
      drag.draw(canvas)
    }

    override fun onAttachedToWindow() {
      super.onAttachedToWindow()
      if (dropped) return
      attached = true
      reactContext?.addLifecycleEventListener(this@HybridMapSurface)
      afterUpdate()
    }

    override fun onDetachedFromWindow() {
      attached = false
      reactContext?.removeLifecycleEventListener(this@HybridMapSurface)
      releaseMap()
      super.onDetachedFromWindow()
    }
  }

  private fun Coordinate.toLatLng() = LatLng(latitude, longitude)
  private fun LatLng.toCoordinate() = Coordinate(latitude, longitude)

  private companion object {
    val snapshotWriter = Executors.newSingleThreadExecutor()
  }
}
