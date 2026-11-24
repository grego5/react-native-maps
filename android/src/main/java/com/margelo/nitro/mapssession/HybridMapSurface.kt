package com.margelo.nitro.mapssession

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Canvas
import android.graphics.Point
import android.graphics.PointF
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.Keep
import com.facebook.react.bridge.LifecycleEventListener
import com.facebook.react.common.LifecycleState
import com.facebook.react.uimanager.ThemedReactContext
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.GoogleMapOptions
import com.google.android.gms.maps.MapView
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.Dash
import com.google.android.gms.maps.model.Gap
import com.google.android.gms.maps.model.PatternItem
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.MapStyleOptions
import com.google.android.gms.maps.model.Marker
import com.google.android.gms.maps.model.MarkerOptions
import com.google.android.gms.maps.model.PointOfInterest
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
  private var optionsDirty = true
  private var markersDirty = true
  private var routesDirty = true
  private var hasFeatures = false
  private var cameraMoving = false
  /** The `initialFit` read at map creation, until the first nonempty layout applies it. */
  private var pendingFit: InitialFit? = null
  private val markerHandles = mutableMapOf<String, Marker>()
  private val markerAnchors = mutableMapOf<String, MapPoint>()
  private class IconRequest(val source: MarkerImage)
  private val markerIcons = mutableMapOf<String, IconRequest>()
  private val routeHandles = mutableMapOf<String, Polyline>()
  private var appliedRoutes: Map<String, MapRoute> = emptyMap()
  private val snapshots = mutableSetOf<Promise<String>>()

  override var markers: Array<MapMarker> = emptyArray()
    set(value) {
      field = value
      markersDirty = true
    }
  override var routes: Array<MapRoute> = emptyArray()
    set(value) {
      field = value
      routesDirty = true
    }
  override var provider: MapProvider = MapProvider.GOOGLE
  override var options: MapOptions? = null
    set(value) {
      field = value
      optionsDirty = true
    }
  override var initialCamera: MapCamera? = null
  override var initialFit: InitialFit? = null
  override var onCameraMove: ((event: MapCameraEvent) -> Unit)? = null
  override var onReady: (() -> Unit)? = null
  override var onRendered: (() -> Unit)? = null
  override var onTap: ((event: MapTap) -> Unit)? = null
  override var onPoiTap: ((event: MapPoiTap) -> Unit)? = null
  override var pinDragEnabled: Boolean? = null
  override var pinDragPreview: DragPreview? = null
  override var dropRadius: Double? = null
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
    host?.drag?.pinPreview = pinDragPreview
    host?.drag?.dropRadius = dropRadius ?: 0.0
    ensureMap()
    applyFeatures()
  }

  private fun ensureMap() {
    if (nativeMapView != null || provider != MapProvider.GOOGLE) return
    val context = checkNotNull(reactContext)
    pendingFit = initialFit
    val view = initialCamera?.takeIf { pendingFit == null }?.let {
      MapView(context, GoogleMapOptions().camera(CameraPosition.fromLatLngZoom(it.center.toLatLng(), it.zoom.toFloat())))
    } ?: MapView(context)
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
        if (map === liveMap) cameraPhase(liveMap, MapCameraPhase.START)
      }
      liveMap.setOnCameraIdleListener {
        if (map === liveMap) cameraPhase(liveMap, MapCameraPhase.IDLE)
      }
      liveMap.uiSettings.isMapToolbarEnabled = false
      applyInitialFit()
      liveMap.setOnMapClickListener { coordinate -> reportTap(liveMap, coordinate, null) }
      liveMap.setOnPoiClickListener { poi -> reportPoi(liveMap, poi) }
      liveMap.setOnMarkerClickListener { marker ->
        reportTap(liveMap, marker.position, marker.tag as? String)
        if (marker.title != null) marker.showInfoWindow()
        // Consumed so the SDK does not move the camera; the info window is opened above instead.
        true
      }
      applyFeatures()
    }
  }

  /** The SDK can report several move starts during one animation; emit one START per IDLE. */
  private fun cameraPhase(liveMap: GoogleMap, phase: MapCameraPhase) {
    val moving = phase == MapCameraPhase.START
    host?.drag?.cameraMoving = moving
    if (cameraMoving == moving) return
    cameraMoving = moving
    if (attached && !dropped) onCameraMove?.invoke(MapCameraEvent(phase, liveMap.camera()))
  }

  /** Fits once the map exists and the host has a size; `signalReady` waits for it. */
  private fun applyInitialFit() {
    val fit = pendingFit ?: return
    val liveMap = map ?: return
    val (width, height) = viewSize() ?: return
    pendingFit = null
    try {
      val camera = CameraMath.fit(CameraMath.bounds(fit.coordinates), width, height, fit.padding, fit.maxZoom, liveMap.cameraPosition.zoom.toDouble())
      moveCamera(liveMap, camera, 0.0)
    } catch (error: IllegalArgumentException) {
      Log.w("MapSurface", "initialFit ignored: ${error.message}")
    }
    signalReady()
  }

  /** The host size in display points, or null before layout. */
  private fun viewSize(): Pair<Double, Double>? {
    val view = host ?: return null
    if (view.width == 0 || view.height == 0) return null
    val density = view.resources.displayMetrics.density.toDouble()
    return view.width / density to view.height / density
  }

  private fun moveCamera(liveMap: GoogleMap, camera: MapCamera, duration: Double) {
    val update = CameraUpdateFactory.newCameraPosition(CameraPosition(camera.center.toLatLng(), camera.zoom.toFloat(), 0f, 0f))
    if (duration > 0) liveMap.animateCamera(update, duration.roundToInt().coerceAtLeast(1), null) else liveMap.moveCamera(update)
  }

  private fun fitCamera(liveMap: GoogleMap, coordinates: Array<Coordinate>, fit: CameraFit?): MapCamera {
    val (width, height) = checkNotNull(viewSize()) { "MapSurface is not ready" }
    return CameraMath.fit(CameraMath.bounds(coordinates), width, height, fit?.padding, fit?.maxZoom, liveMap.cameraPosition.zoom.toDouble())
  }

  private fun signalReady() {
    if (!attached || map == null || !hasFeatures || pendingFit != null) return
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
    host?.drag?.updateMarkers(emptyList())
    markerHandles.values.forEach(Marker::remove)
    routeHandles.values.forEach(Polyline::remove)
    markerHandles.clear()
    markerIcons.clear()
    markerAnchors.clear()
    routeHandles.clear()
    appliedRoutes = emptyMap()
    host?.drag?.updateRoutes(appliedRoutes)
  }

  private fun applyFeatures() {
    val liveMap = map ?: return
    val context = checkNotNull(reactContext)
    applyOptions(liveMap)
    applyMarkers(liveMap, context)
    applyRoutes(liveMap, context)
    hasFeatures = true
    signalReady()
  }

  private fun applyOptions(liveMap: GoogleMap) {
    if (!optionsDirty) return
    optionsDirty = false
    val options = options
    val style = options?.mapStyle?.let(::MapStyleOptions)
    if (!liveMap.setMapStyle(style)) android.util.Log.w("MapSurface", "Google Maps rejected mapStyle")
    liveMap.mapType = if (options?.mapType == MapType.NONE) GoogleMap.MAP_TYPE_NONE else GoogleMap.MAP_TYPE_NORMAL
    liveMap.isBuildingsEnabled = options?.showsBuildings ?: true
    liveMap.isIndoorEnabled = options?.showsIndoors ?: true
    with(liveMap.uiSettings) {
      isScrollGesturesEnabled = options?.scrollEnabled ?: true
      isZoomGesturesEnabled = options?.zoomEnabled ?: true
      isRotateGesturesEnabled = options?.rotateEnabled ?: true
      isTiltGesturesEnabled = options?.pitchEnabled ?: true
    }
  }

  private fun applyMarkers(liveMap: GoogleMap, context: Context) {
    if (!markersDirty) return
    markersDirty = false
    val markerIds = markers.mapTo(HashSet()) { it.id }
    markerHandles.entries.removeAll { (id, marker) ->
      if (id in markerIds) false else {
        markerIcons.remove(id)
        markerAnchors.remove(id)
        marker.remove()
        true
      }
    }
    // Ranks keep equal zIndex values in input order, which the SDK does not guarantee for equal floats.
    val ordered = markers.sortedBy { it.zIndex ?: 0.0 }
    host?.drag?.updateMarkers(markers.asList())
    for ((rank, marker) in ordered.withIndex()) {
      val position = marker.coordinate.toLatLng()
      val native = markerHandles[marker.id] ?: liveMap.addMarker(
        MarkerOptions().position(position).title(marker.title).snippet(marker.description),
      )?.also {
        it.tag = marker.id
        markerHandles[marker.id] = it
      } ?: continue
      if (native.position != position) native.position = position
      if (native.title != marker.title) native.title = marker.title
      if (native.snippet != marker.description) native.snippet = marker.description
      val anchor = marker.anchor ?: DEFAULT_ANCHOR
      if (markerAnchors[marker.id] != anchor) {
        native.setAnchor(anchor.x.toFloat(), anchor.y.toFloat())
        markerAnchors[marker.id] = anchor
      }
      if (native.zIndex != rank.toFloat()) native.zIndex = rank.toFloat()
      updateMarkerIcon(context, marker.id, native, marker.image)
    }
  }

  private fun applyRoutes(liveMap: GoogleMap, context: Context) {
    if (!routesDirty) return
    routesDirty = false
    val routeIds = routes.mapTo(HashSet()) { it.id }
    routeHandles.entries.removeAll { (id, line) ->
      if (id in routeIds) false else {
        line.remove()
        true
      }
    }
    val orderedRoutes = routes.sortedBy { it.zIndex ?: 0.0 }
    for ((index, route) in orderedRoutes.withIndex()) {
      val existing = routeHandles[route.id]
      val order = index.toFloat()
      val width = ((route.strokeWidth ?: 4.0) * context.resources.displayMetrics.density)
        .coerceAtMost(Float.MAX_VALUE.toDouble()).toFloat()
      val color = parseHexColor(route.strokeColor) ?: Color.rgb(0, 122, 255)
      val density = context.resources.displayMetrics.density
      if (existing == null) {
        routeHandles[route.id] = liveMap.addPolyline(
          PolylineOptions()
            .addAll(route.coordinates.map { it.toLatLng() })
            .width(width)
            .color(color)
            .pattern(route.dashPattern?.let { dashPattern(it, density) })
            .zIndex(order),
        )
      } else {
        if (!route.coordinates.contentEquals(appliedRoutes[route.id]?.coordinates)) {
          existing.points = route.coordinates.map { it.toLatLng() }
        }
        if (existing.zIndex != order) existing.zIndex = order
        if (existing.width != width) existing.width = width
        if (existing.color != color) existing.color = color
        if (!route.dashPattern.contentEquals(appliedRoutes[route.id]?.dashPattern)) {
          existing.pattern = route.dashPattern?.let { dashPattern(it, density) }
        }
      }
    }
    appliedRoutes = routes.associateBy { it.id }
    host?.drag?.updateRoutes(appliedRoutes)
  }

  /** Alternating dash and gap lengths, from display points to pixels. */
  private fun dashPattern(lengths: DoubleArray, density: Float): List<PatternItem> =
    lengths.mapIndexed { index, points ->
      val pixels = (points * density).toFloat()
      if (index % 2 == 0) Dash(pixels) else Gap(pixels)
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
      current.markerHandles[id]?.setIcon(BitmapDescriptorFactory.fromBitmap(bitmap))
    }
  }

  private fun reportTap(liveMap: GoogleMap, coordinate: LatLng, markerId: String?) {
    if (!attached || map !== liveMap || dropped || onTap == null) return
    host?.drag?.mapTapped(coordinate.toCoordinate(), markerId)
  }

  private fun reportPoi(liveMap: GoogleMap, poi: PointOfInterest) {
    val emit = onPoiTap ?: return
    if (!attached || map !== liveMap || dropped || host?.drag?.isCapturing == true) return
    emit(MapPoiTap(poi.placeId, poi.name, poi.latLng.toCoordinate()))
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

  override fun setCamera(center: Coordinate, zoom: Double, move: CameraMove?) = withMap { liveMap ->
    CameraMath.requireCoordinate(center)
    CameraMath.requireZoom(zoom)
    val duration = CameraMath.duration(move?.duration)
    val target = CameraMath.paddedCenter(center, zoom, move?.padding)
    host?.drag?.cancel()
    moveCamera(liveMap, MapCamera(target, zoom), duration)
  }

  override fun getCamera() = withMap { it.camera() }

  override fun fitCoordinates(coordinates: Array<Coordinate>, fit: CameraFit?) = withMap { liveMap ->
    val duration = CameraMath.duration(fit?.duration)
    val camera = fitCamera(liveMap, coordinates, fit)
    host?.drag?.cancel()
    moveCamera(liveMap, camera, duration)
  }

  override fun cameraFor(coordinates: Array<Coordinate>, fit: CameraFit?) = withMap { fitCamera(it, coordinates, fit) }

  override fun revealCoordinates(coordinates: Array<Coordinate>, fit: CameraFit?) = withMap { liveMap ->
    val duration = CameraMath.duration(fit?.duration)
    // Computed first so invalid input rejects before anything moves.
    val target = fitCamera(liveMap, coordinates, fit)
    val (width, height) = checkNotNull(viewSize())
    val density = checkNotNull(host).resources.displayMetrics.density.toDouble()
    val points = coordinates.map { coordinate ->
      val point = liveMap.projection.toScreenLocation(coordinate.toLatLng())
      MapPoint(point.x / density, point.y / density)
    }
    when (val reveal = CameraMath.reveal(points, width, height, fit?.padding)) {
      CameraMath.Reveal.None -> CameraReveal.NONE
      CameraMath.Reveal.Fit -> {
        host?.drag?.cancel()
        moveCamera(liveMap, target, duration)
        CameraReveal.FIT
      }
      is CameraMath.Reveal.Pan -> {
        val current = liveMap.camera()
        host?.drag?.cancel()
        moveCamera(liveMap, MapCamera(CameraMath.offset(current.center, current.zoom, reveal.dx, reveal.dy), current.zoom), duration)
        CameraReveal.PAN
      }
    }
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

  override fun showCallout(markerId: String) = withMap {
    requireNotNull(markerHandles[markerId]) { "Unknown marker" }.showInfoWindow()
  }

  override fun hideCallout() = withMap {
    markerHandles.values.firstOrNull { it.isInfoWindowShown }?.hideInfoWindow()
    Unit
  }

  override fun queryFeatures(point: MapPoint, radius: Double) = withMap {
    checkNotNull(host).drag.queryFeatures(point, radius)
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
    optionsDirty = true
    markersDirty = true
    routesDirty = true
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
    cameraMoving = false
    pendingFit = null
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
    onPoiTap = null
    onDrag = null
    onCameraMove = null
    markers = emptyArray()
    routes = emptyArray()
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

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
      super.onLayout(changed, left, top, right, bottom)
      applyInitialFit()
    }

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
  private fun GoogleMap.camera() = cameraPosition.let { MapCamera(it.target.toCoordinate(), it.zoom.toDouble()) }

  private companion object {
    val snapshotWriter = Executors.newSingleThreadExecutor()
    val DEFAULT_ANCHOR = MapPoint(0.5, 1.0)
  }
}
