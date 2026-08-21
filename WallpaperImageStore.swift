import AppKit
import Foundation

enum WallpaperImageStore {
    private static let cache = NSCache<NSString, NSImage>()
    private static let lock = NSLock()
    private static var inflight: Set<String> = []

    static func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    static func load(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        if let image = cachedImage(for: url) {
            completion(image)
            return
        }
        let key = url.path
        lock.lock()
        if inflight.contains(key) {
            lock.unlock()
            return
        }
        inflight.insert(key)
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async {
            let image = NSImage(contentsOf: url)
            if let image {
                cache.setObject(image, forKey: key as NSString)
            }
            lock.lock()
            inflight.remove(key)
            lock.unlock()
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
}