import AppKit
import Foundation
import ImageIO

enum WallpaperImageStore {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 256 * 1024 * 1024 // 256 MB
        return cache
    }()

    private static let lock = NSLock()
    private static var inflight: [String: [(NSImage?) -> Void]] = [:]

    static func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    static func load(_ url: URL, maxPixelSize: Int = 1800, completion: @escaping (NSImage?) -> Void) {
        let key = "\(url.path)@\(maxPixelSize)"
        if let image = cache.object(forKey: key as NSString) {
            completion(image)
            return
        }

        lock.lock()
        if var waiters = inflight[key] {
            waiters.append(completion)
            inflight[key] = waiters
            lock.unlock()
            return
        }
        inflight[key] = [completion]
        lock.unlock()

        DispatchQueue.global(qos: .userInteractive).async {
            let image = decodeDownsampledImage(from: url, maxPixelSize: maxPixelSize)
            if let image {
                let cost = Int(image.size.width * image.size.height * 4)
                cache.setObject(image, forKey: key as NSString, cost: cost)
                cache.setObject(image, forKey: url.path as NSString, cost: cost)
            }
            lock.lock()
            let waiters = inflight.removeValue(forKey: key) ?? []
            lock.unlock()
            DispatchQueue.main.async {
                for waiter in waiters {
                    waiter(image)
                }
            }
        }
    }

    /// High-performance hardware-accelerated downsampled image decoding
    static func decodeDownsampledImage(from url: URL, maxPixelSize: Int) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        return NSImage(contentsOf: url)
    }
}
