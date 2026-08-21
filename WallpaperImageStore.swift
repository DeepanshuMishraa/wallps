import AppKit
import Foundation

enum WallpaperImageStore {
    private static let cache = NSCache<NSString, NSImage>()
    private static let lock = NSLock()
    private static var inflight: [String: [(NSImage?) -> Void]] = [:]

    static func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    static func load(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        let key = url.path
        if let image = cachedImage(for: url) {
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

        DispatchQueue.global(qos: .userInitiated).async {
            let image = NSImage(contentsOf: url)
            if let image {
                cache.setObject(image, forKey: key as NSString)
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
}