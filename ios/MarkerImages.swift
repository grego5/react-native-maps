import ImageIO
import UIKit

final class MarkerImages {
  struct Key: Hashable {
    let uri: String
    let scale: Double

    init(_ source: MarkerImage) {
      uri = source.uri
      scale = source.scale ?? 1
    }
  }

  private enum ImageError: LocalizedError {
    case invalidSource
    case response
    case size
    case decoding

    var errorDescription: String? {
      switch self {
      case .invalidSource: return "Invalid or unsupported marker image URI or scale"
      case .response: return "Marker image request failed"
      case .size: return "Marker image exceeds 8 MiB"
      case .decoding: return "Cannot decode marker image"
      }
    }
  }

  static let shared = MarkerImages()

  private typealias Completion = (Result<UIImage, Error>) -> Void
  private let cache = NSCache<NSString, UIImage>()
  private let worker = DispatchQueue(label: "ReactNativeMaps.MarkerImages", qos: .userInitiated)
  private var loading = [Key: [Completion]]()

  private init() {
    cache.totalCostLimit = 32 * 1024 * 1024
  }

  func load(_ key: Key, complete: @escaping (Result<UIImage, Error>) -> Void) {
    guard key.scale.isFinite, key.scale > 0, let url = URL(string: key.uri),
          let scheme = url.scheme, ["https", "http", "file"].contains(scheme) else {
      complete(.failure(ImageError.invalidSource))
      return
    }
    let cacheKey = "\(key.scale):\(key.uri)" as NSString
    if let cached = cache.object(forKey: cacheKey) {
      complete(.success(cached))
      return
    }
    if loading[key] != nil {
      loading[key]?.append(complete)
      return
    }
    loading[key] = [complete]
    let finish: Completion = { result in
      DispatchQueue.main.async {
        let callbacks = self.loading.removeValue(forKey: key) ?? []
        if case .success(let image) = result, let pixels = image.cgImage {
          self.cache.setObject(image, forKey: cacheKey, cost: pixels.bytesPerRow * pixels.height)
        }
        callbacks.forEach { $0(result) }
      }
    }
    if url.isFileURL {
      worker.async { finish(Result { try Self.decode(url, scale: key.scale) }) }
    } else {
      URLSession.shared.downloadTask(with: url) { file, response, error in
        if let error {
          finish(.failure(error))
        } else if let file, let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) {
          finish(Result { try Self.decode(file, scale: key.scale) })
        } else {
          finish(.failure(ImageError.response))
        }
      }.resume()
    }
  }

  private static func decode(_ url: URL, scale: Double) throws -> UIImage {
    let properties = try url.resourceValues(forKeys: [.fileSizeKey])
    guard let size = properties.fileSize, size <= 8 * 1024 * 1024 else { throw ImageError.size }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: min(1024, max(1, 512 * scale)),
    ]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw ImageError.decoding
    }
    let safeScale = max(scale, Double(max(image.width, image.height)) / 512)
    return UIImage(cgImage: image, scale: safeScale, orientation: .up)
  }
}
