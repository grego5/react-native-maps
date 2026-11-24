import NitroModules
import UIKit

final class HybridMapSurface: HybridMapSurfaceSpec {
  private final class Host: UIView {
    var windowChanged: (() -> Void)?
    var layoutChanged: (() -> Void)?

    override func layoutSubviews() {
      super.layoutSubviews()
      layoutChanged?()
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      windowChanged?()
    }
  }

  private let host = Host()
  private var presenter: (any MapPresenter)?
  private var drag: MapDragGesture?
  private var currentProvider: MapProvider?
  private var optionsDirty = true
  private var markersDirty = true
  private var routesDirty = true
  private var hasFeatures = false
  /// The initial camera read at presenter creation, until the first nonempty layout applies it.
  private var pendingInitialCamera: InitialCameraRequest?
  private var signalledReady = false
  private var rendered = false
  private var signalledRendered = false
  private var dropped = false
  private var pendingSnapshots: [UUID: Promise<String>] = [:]

  var markers: [MapMarker] = [] {
    didSet { markersDirty = true }
  }
  var routes: [MapRoute] = [] {
    didSet { routesDirty = true }
  }
  var provider: MapProvider = .apple
  var options: MapOptions? {
    didSet { optionsDirty = true }
  }
  var initialCamera: MapCamera?
  var initialFit: InitialFit?
  var onCameraMove: ((MapCameraEvent) -> Void)?
  var onReady: (() -> Void)?
  var onRendered: (() -> Void)?
  var onTap: ((MapTap) -> Void)?
  var onPoiTap: ((MapPoiTap) -> Void)?
  var pinDragEnabled: Bool?
  var pinDragPreview: DragPreview?
  var dropRadius: Double?
  var onDrag: ((MapDragEvent) -> Void)?
  var view: UIView { host }

  override init() {
    super.init()
    host.windowChanged = { [weak self] in self?.updatePresentation() }
    host.layoutChanged = { [weak self] in
      self?.applyInitialCamera()
      self?.signalReady()
    }
  }

  func afterUpdate() { updatePresentation() }

  private func updatePresentation() {
    guard !dropped, host.window != nil else {
      releasePresenter()
      return
    }

    if currentProvider != provider {
      releasePresenter()
      currentProvider = provider
      presenter = makePresenter()
      if let presenter {
        let drag = MapDragGesture(presenter: presenter)
        self.drag = drag
        drag.onDrag = { [weak self] event in self?.onDrag?(event) }
        drag.onCamera = { [weak self, weak presenter] phase in
          guard let self, let presenter, self.presenter === presenter, self.host.window != nil else { return }
          self.onCameraMove?(MapCameraEvent(phase: phase, camera: presenter.camera))
        }
        if let initialFit {
          pendingInitialCamera = .fit(initialFit)
        } else if let initialCamera {
          pendingInitialCamera = .camera(initialCamera)
        }
        presenter.onRendered = { [weak self, weak presenter] in
          guard let self, self.presenter === presenter else { return }
          self.rendered = true
          self.signalReady()
        }
        presenter.onPOITap = { [weak self, weak presenter] event in
          guard let self, self.presenter === presenter, self.host.window != nil, self.drag?.isActive != true else { return }
          self.onPoiTap?(event)
        }
        drag.onTap = { [weak self, weak presenter] event in
          guard let self, self.presenter === presenter, self.host.window != nil else { return }
          self.onTap?(event)
        }
        let view = presenter.view
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
          view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
          view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
          view.topAnchor.constraint(equalTo: host.topAnchor),
          view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
      }
    }

    drag?.pinEnabled = pinDragEnabled == true
    drag?.pinPreview = pinDragPreview
    drag?.dropRadius = dropRadius ?? 0
    presenter?.setPOITapsEnabled(onPoiTap != nil)
    applyInitialCamera()
    if let presenter {
      if optionsDirty {
        optionsDirty = false
        presenter.apply(options)
      }
      if markersDirty {
        markersDirty = false
        presenter.applyMarkers(markers)
        drag?.updateMarkers(markers)
      }
      if routesDirty {
        routesDirty = false
        drag?.updateRoutes(routes)
        presenter.applyRoutes(routes)
      }
      hasFeatures = true
    }
    signalReady()
  }

  private func makePresenter() -> (any MapPresenter)? {
    if provider == .apple { return AppleMapPresenter() }
    #if REACT_NATIVE_MAPS_GOOGLE && canImport(GoogleMaps)
    return GoogleMapPresenter()
    #else
    return nil
    #endif
  }

  private enum InitialCameraRequest {
    case camera(MapCamera)
    case fit(InitialFit)
  }

  /// Applies `initialFit` or `initialCamera` once the provider view has a size; `signalReady` waits for it.
  private func applyInitialCamera() {
    guard let request = pendingInitialCamera, let presenter, !presenter.view.bounds.isEmpty else { return }
    pendingInitialCamera = nil
    switch request {
    case .camera(let camera):
      presenter.moveCamera(camera.center.location, zoom: camera.zoom, duration: 0)
    case .fit(let fit):
      do {
        let camera = try fitCamera(presenter, coordinates: fit.coordinates, padding: fit.padding, maxZoom: fit.maxZoom)
        presenter.moveCamera(camera.center.location, zoom: camera.zoom, duration: 0)
      } catch {
        NSLog("MapSurface initialFit ignored: %@", error.localizedDescription)
      }
    }
  }

  private func fitCamera(
    _ presenter: any MapPresenter, coordinates: [Coordinate], padding: EdgePadding?, maxZoom: Double?
  ) throws -> MapCamera {
    let size = presenter.view.bounds.size
    return try CameraMath.fit(
      CameraMath.bounds(coordinates), width: Double(size.width), height: Double(size.height),
      padding: padding, maxZoom: maxZoom, currentZoom: presenter.camera.zoom
    )
  }

  private func signalReady() {
    guard hasFeatures, pendingInitialCamera == nil, let presenter, presenter.view.window != nil,
          !presenter.view.bounds.isEmpty else { return }
    if !signalledReady, let onReady {
      signalledReady = true
      onReady()
    }
    if rendered, !signalledRendered, let onRendered {
      signalledRendered = true
      onRendered()
    }
  }

  private func releasePresenter() {
    drag?.close()
    drag = nil
    optionsDirty = true
    markersDirty = true
    routesDirty = true
    hasFeatures = false
    pendingInitialCamera = nil
    let snapshots = pendingSnapshots.values
    pendingSnapshots.removeAll()
    snapshots.forEach { $0.reject(withError: MapSurfaceError.detached) }
    presenter?.close()
    presenter?.view.removeFromSuperview()
    presenter = nil
    currentProvider = nil
    signalledReady = false
    rendered = false
    signalledRendered = false
  }

  func onDropView() {
    if Thread.isMainThread {
      drop()
    } else {
      DispatchQueue.main.async { self.drop() }
    }
  }

  private func drop() {
    dropped = true
    releasePresenter()
    host.windowChanged = nil
    host.layoutChanged = nil
    onReady = nil
    onRendered = nil
    onTap = nil
    onPoiTap = nil
    onDrag = nil
    onCameraMove = nil
    markers = []
    routes = []
  }

  private func requirePresenter() throws -> any MapPresenter {
    guard host.window != nil, !dropped else { throw MapSurfaceError.detached }
    guard let presenter else { throw MapSurfaceError.providerUnavailable }
    guard hasFeatures, !presenter.view.bounds.isEmpty else { throw MapSurfaceError.notReady }
    return presenter
  }

  private func withPresenter<Result>(_ operation: @escaping (any MapPresenter) throws -> Result) -> Promise<Result> {
    let promise = Promise<Result>()
    DispatchQueue.main.async { [weak self] in
      do {
        guard let self else { throw MapSurfaceError.detached }
        promise.resolve(withResult: try operation(self.requirePresenter()))
      } catch {
        promise.reject(withError: error)
      }
    }
    return promise
  }

  func setCamera(center: Coordinate, zoom: Double, move: CameraMove?) -> Promise<Void> {
    withPresenter { [weak self] presenter in
      try CameraMath.requireCoordinate(center)
      try CameraMath.requireZoom(zoom)
      let duration = try CameraMath.duration(move?.duration)
      let target = try CameraMath.paddedCenter(center, zoom: zoom, padding: move?.padding)
      self?.drag?.cancel()
      presenter.moveCamera(target.location, zoom: zoom, duration: duration)
    }
  }

  func getCamera() -> Promise<MapCamera> {
    withPresenter { $0.camera }
  }

  func fitCoordinates(coordinates: [Coordinate], fit: CameraFit?) -> Promise<Void> {
    withPresenter { [weak self] presenter in
      guard let self else { throw MapSurfaceError.detached }
      let duration = try CameraMath.duration(fit?.duration)
      let camera = try self.fitCamera(presenter, coordinates: coordinates, padding: fit?.padding, maxZoom: fit?.maxZoom)
      self.drag?.cancel()
      presenter.moveCamera(camera.center.location, zoom: camera.zoom, duration: duration)
    }
  }

  func cameraFor(coordinates: [Coordinate], fit: CameraFit?) -> Promise<MapCamera> {
    withPresenter { [weak self] presenter -> MapCamera in
      guard let self else { throw MapSurfaceError.detached }
      return try self.fitCamera(presenter, coordinates: coordinates, padding: fit?.padding, maxZoom: fit?.maxZoom)
    }
  }

  func revealCoordinates(coordinates: [Coordinate], fit: CameraFit?) -> Promise<CameraReveal> {
    withPresenter { [weak self] presenter -> CameraReveal in
      guard let self else { throw MapSurfaceError.detached }
      let duration = try CameraMath.duration(fit?.duration)
      // Computed first so invalid input rejects before anything moves.
      let target = try self.fitCamera(presenter, coordinates: coordinates, padding: fit?.padding, maxZoom: fit?.maxZoom)
      let size = presenter.view.bounds.size
      let points = coordinates.map { coordinate -> MapPoint in
        let point = presenter.project(coordinate.location)
        return MapPoint(x: Double(point.x), y: Double(point.y))
      }
      switch try CameraMath.reveal(points, width: Double(size.width), height: Double(size.height), padding: fit?.padding) {
      case .none:
        return .none
      case .fit:
        self.drag?.cancel()
        presenter.moveCamera(target.center.location, zoom: target.zoom, duration: duration)
        return .fit
      case .pan(let dx, let dy):
        let current = presenter.camera
        let center = CameraMath.offset(current.center, zoom: current.zoom, dx: dx, dy: dy)
        self.drag?.cancel()
        presenter.moveCamera(center.location, zoom: current.zoom, duration: duration)
        return .pan
      }
    }
  }

  func project(coordinate: Coordinate) -> Promise<MapPoint> {
    withPresenter {
      let point = $0.project(coordinate.location)
      return MapPoint(x: point.x, y: point.y)
    }
  }

  func unproject(point: MapPoint) -> Promise<Coordinate> {
    withPresenter { $0.unproject(CGPoint(x: point.x, y: point.y)).mapCoordinate }
  }

  func showCallout(markerId: String) -> Promise<Void> {
    withPresenter { try $0.showCallout(markerId) }
  }

  func hideCallout() -> Promise<Void> {
    withPresenter { $0.hideCallout() }
  }

  func queryFeatures(point: MapPoint, radius: Double) -> Promise<MapFeatureHits> {
    withPresenter { [weak self] _ in
      guard let drag = self?.drag else { throw MapSurfaceError.detached }
      return try drag.queryFeatures(CGPoint(x: point.x, y: point.y), radius: radius)
    }
  }

  func cancelDrag() -> Promise<Void> {
    withPresenter { [weak self] _ in
      self?.drag?.cancel()
      return ()
    }
  }

  func takeSnapshot() -> Promise<String> {
    let promise = Promise<String>()
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        promise.reject(withError: MapSurfaceError.detached)
        return
      }
      let id = UUID()
      do {
        let presenter = try self.requirePresenter()
        self.pendingSnapshots[id] = promise
        try presenter.snapshot { [weak self] result in
          guard let self, self.pendingSnapshots[id] != nil else { return }
          switch result {
          case .failure(let error):
            self.pendingSnapshots.removeValue(forKey: id)?.reject(withError: error)
          case .success(let image):
            self.writeSnapshot(image, id: id)
          }
        }
      } catch {
        self.pendingSnapshots.removeValue(forKey: id)
        promise.reject(withError: error)
      }
    }
    return promise
  }

  private func writeSnapshot(_ image: UIImage, id: UUID) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("nitro-map-\(id).png")
      let result = Result {
        guard let data = image.pngData() else { throw MapSurfaceError.snapshotFailed }
        try data.write(to: url, options: .atomic)
        return url.absoluteString
      }
      DispatchQueue.main.async { [weak self] in
        guard let promise = self?.pendingSnapshots.removeValue(forKey: id) else {
          try? FileManager.default.removeItem(at: url)
          return
        }
        switch result {
        case .success(let uri): promise.resolve(withResult: uri)
        case .failure(let error): promise.reject(withError: error)
        }
      }
    }
  }
}
