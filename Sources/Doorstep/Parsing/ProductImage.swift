import AppKit
import CryptoKit
import Foundation

/// Picks the product photo out of an order email: the image a store shows next to
/// the item, not its logo, social icons, progress-step glyphs or tracking pixels.
enum ProductImage {
    /// Hosts that serve catalog photos. An image here is almost certainly a product.
    private static let productHosts = [
        "m.media-amazon.com/images/i/", "images-na.ssl-images-amazon.com/images/i/",
        "i5.walmartimages.com", "cdn.shopify.com/s/files", "target.scene7.com",
        "slimages.macysassets.com", "images.costco-static.com", "pisces.bbystatic.com",
        "assets.wsimgs.com", "images.lululemon.com", "s7d", "scene7.com/is/image",
        "/dw/image/", "cloudinary.com", "imgix.net", "images.ctfassets.net",
    ]

    private static let junk = "logo|icon|spacer|pixel|track|beacon|open\\.|badge|banner|header|footer|social|facebook|instagram|twitter|youtube|pinterest|tiktok|linkedin|app-?store|google-?play|arrow|chevron|star|rating|divider|button|btn|progress|status|check|completed|pending|signature|1x1|blank|transparent|hero|promo|survey|qr"

    struct Candidate {
        let src: String
        let alt: String
        let width: Int?
        let height: Int?
    }

    static func best(in html: String, itemNames: [String]) -> String? {
        let words = Set(itemNames.joined(separator: " ").lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 })

        var bestScore = 0
        var best: String?
        for c in candidates(in: html) {
            let src = c.src.lowercased()
            let alt = c.alt.lowercased()
            if src.hasPrefix("data:") || !src.hasPrefix("http") { continue }
            if let w = c.width, w <= 40 { continue }
            if let h = c.height, h <= 40 { continue }
            if src.range(of: junk, options: .regularExpression) != nil || alt.range(of: junk, options: .regularExpression) != nil { continue }
            if src.hasSuffix(".gif") || src.contains(".gif?") { continue }

            var score = 0
            if productHosts.contains(where: { src.contains($0) }) { score += 5 }
            let altWords = Set(alt.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 })
            let shared = altWords.intersection(words).count
            if shared >= 2 { score += 4 } else if shared == 1 { score += 1 }
            if let w = c.width, let h = c.height, w >= 60, h >= 60, Double(max(w, h)) / Double(min(w, h)) < 2.2 { score += 2 }

            // Needs real evidence: a catalog host, or an alt text naming the item.
            if score >= 4, score > bestScore {
                bestScore = score
                best = c.src.replacingOccurrences(of: "&amp;", with: "&")
            }
        }
        return best
    }

    static func candidates(in html: String) -> [Candidate] {
        guard let tagRe = try? NSRegularExpression(pattern: "<img\\b[^>]*>", options: .caseInsensitive) else { return [] }
        let ns = html as NSString
        return tagRe.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let tag = ns.substring(with: m.range)
            guard let src = attribute("src", in: tag) else { return nil }
            let style = attribute("style", in: tag) ?? ""
            return Candidate(
                src: src,
                alt: attribute("alt", in: tag) ?? attribute("title", in: tag) ?? "",
                width: number(attribute("width", in: tag)) ?? number(styleValue("width", in: style)),
                height: number(attribute("height", in: tag)) ?? number(styleValue("height", in: style))
            )
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = tag as NSString
        guard let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for g in 1...3 where m.range(at: g).location != NSNotFound { return ns.substring(with: m.range(at: g)) }
        return nil
    }

    private static func styleValue(_ name: String, in style: String) -> String? {
        guard let r = style.range(of: "(?<![-a-z])\(name)\\s*:\\s*\\d+", options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(style[r])
    }

    private static func number(_ s: String?) -> Int? {
        guard let s else { return nil }
        let digits = s.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }
}

/// Downloads product photos once and keeps them on disk, so opening the panel
/// never touches the network.
enum ImageStore {
    static var directory: URL {
        let dir = AppPaths.supportDirectory.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func localFile(for remote: String) -> URL {
        let hash = SHA256.hash(data: Data(remote.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash)
    }

    /// Returns true if anything new was saved.
    static func prefetch(_ urls: [String]) async -> Bool {
        let missing = Set(urls).filter { !FileManager.default.fileExists(atPath: localFile(for: $0).path) }
        guard !missing.isEmpty else { return false }
        return await withTaskGroup(of: Bool.self) { group in
            for remote in missing {
                group.addTask {
                    guard let url = URL(string: remote),
                          let (data, response) = try? await URLSession.shared.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200,
                          data.count > 500, data.count < 5_000_000 else { return false }
                    return (try? data.write(to: localFile(for: remote), options: .atomic)) != nil
                }
            }
            return await group.reduce(false) { $0 || $1 }
        }
    }
}

/// Store and carrier logos, fetched once per website and kept on disk.
/// An empty file records "no usable logo" so it isn't retried every sync.
enum LogoStore {
    static func file(for domain: String) -> URL {
        ImageStore.directory.appendingPathComponent("logo-" + domain.replacingOccurrences(of: "/", with: "_") + ".png")
    }

    static func image(for domain: String?) -> NSImage? {
        guard let domain else { return nil }
        let url = file(for: domain)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 0 else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Returns true if any new logo was saved.
    static func prefetch(_ domains: [String]) async -> Bool {
        let missing = Set(domains).filter { !FileManager.default.fileExists(atPath: file(for: $0).path) }
        guard !missing.isEmpty else { return false }
        return await withTaskGroup(of: Bool.self) { group in
            for domain in missing {
                group.addTask {
                    // The site's own app icon is sharpest when offered; otherwise a favicon service.
                    let sources = ["https://www.\(domain)/apple-touch-icon.png", "https://icons.duckduckgo.com/ip3/\(domain).ico"]
                    for source in sources {
                        if let png = await fetch(source, minimumPixels: 32) {
                            return (try? png.write(to: file(for: domain), options: .atomic)) != nil
                        }
                    }
                    FileManager.default.createFile(atPath: file(for: domain).path, contents: Data())
                    return false
                }
            }
            return await group.reduce(false) { $0 || $1 }
        }
    }

    private static func fetch(_ source: String, minimumPixels: Int) async -> Data? {
        guard let url = URL(string: source) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Mozilla/5.0 (Macintosh) Doorstep", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data) else { return nil }
        // .ico files hold several sizes; use the largest.
        let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
        guard let rep = reps.max(by: { $0.pixelsWide < $1.pixelsWide }) ?? NSBitmapImageRep(data: data),
              rep.pixelsWide >= minimumPixels, rep.pixelsHigh >= minimumPixels else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
