import Foundation
import SwiftUI

// MARK: - Favicon Cache

/// Thread-safe favicon cache. NSCache is already thread-safe, and URLSession is Sendable.
final class FaviconService: @unchecked Sendable {
    private let cache = NSCache<NSURL, NSImage>()

    init() {
        cache.countLimit = 200
    }

    /// Returns a cached or fetched favicon for the given domain
    func favicon(for domain: String, size: Int = 32) async -> NSImage? {
        let urlString = "https://www.google.com/s2/favicons?domain=\(domain)&sz=\(size)"
        guard let url = URL(string: urlString) else { return nil }

        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data) else {
            return nil
        }

        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
