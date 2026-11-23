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
  private var featuresDirty = true
  private var hasFeatures = false
  private var signalledReady = false
  private var rendered = false
  private var signalledRendered = false
  private var dropped = false
  private var pendingSnapshots: [UUID: Promise<String>] = [:]

  var features = MapFeatures(markers: [], routes: []) {
    didSet { featuresDirty = true }
  }
  var provider: MapProvider = .apple
  var onReady: (() -> Void)?
  var onRendered: (() -> Void)?
  var onTap: ((MapTap) -> Void)?
  var pinDragEnabled: Bool?
  var onDrag: ((MapDragEvent) -> Void)?
  var view: UIView { host }

  override init() {
    super.init()
    host.windowChanged = { [weak self] in self?.updatePresentation() }
    host.layoutChanged = { [weak self] in self?.signalReady() }
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
        presenter.onRendered = { [weak self, weak presenter] in
          guard let self, self.presenter === presenter else { return }
          self.rendered = true
          self.signalReady()
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
    if featuresDirty, let presenter {
      featuresDirty = false
      drag?.updateRoutes(features.routes)
      presenter.apply(features)
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

  private func signalReady() {
    guard hasFeatures, let presenter, presenter.view.window != nil,
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
    featuresDirty = true
    hasFeatures = false
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
    onDrag = nil
    features = MapFeatures(markers: [], routes: [])
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

  func setCamera(center: Coordinate, zoom: Double, animated: Bool) -> Promise<Void> {
    withPresenter { [weak self] presenter in
      self?.drag?.cancel()
      presenter.setCamera(center.location, zoom: zoom, animated: animated)
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
