import SwiftUI
import CryptoKit

/// Caché de imágenes en memoria + disco con **clave estable** (la ruta de la URL).
///
/// Necesario porque MangaDex sirve las páginas desde hosts que ROTAN
/// (`/at-home/server` devuelve baseUrls distintas), así que cachear por URL completa
/// (como hace URLCache) falla siempre. Aquí la clave es `url.path`
/// (p. ej. `/data/{hash}/{archivo}`), que es estable. Base para descargas futuras.
final class ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private let session: URLSession

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("MangaImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 120
        session = URLSession(configuration: .default)
    }

    /// Clave estable: hash de la ruta (ignora el host rotatorio).
    private func key(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Descarga perezosa: precarga en caché varias URLs en segundo plano (sin bloquear).
    func prefetch(_ urls: [URL]) {
        for url in urls {
            let k = key(for: url)
            if memory.object(forKey: k as NSString) != nil { continue }
            Task.detached(priority: .utility) { [weak self] in _ = await self?.image(for: url) }
        }
    }

    func image(for url: URL) async -> UIImage? {
        // Páginas descargadas: archivo local en disco (lectura offline).
        if url.isFileURL {
            return UIImage(contentsOfFile: url.path)
        }
        let k = key(for: url)
        if let cached = memory.object(forKey: k as NSString) { return cached }

        let fileURL = directory.appendingPathComponent(k)
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            memory.setObject(image, forKey: k as NSString)
            return image
        }

        guard let data = try? await Self.fetchData(for: url, session: session), let image = UIImage(data: data) else {
            return nil
        }
        memory.setObject(image, forKey: k as NSString)
        try? data.write(to: fileURL, options: .atomic)
        return image
    }

    // MARK: - Descarga compartida (páginas + portadas)

    private static let desktopUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36"

    /// UA de Safari iOS: coincide con la huella TLS de NSURLSession (necesario para el CDN de
    /// Comick, tras Cloudflare, que reta si TLS y UA no concuerdan).
    private static let safariUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

    /// Descarga los bytes de una URL de imagen, añadiendo cabeceras de MANGA Plus cuando
    /// el host lo requiere y descifrando (XOR) si la URL trae la clave en el fragmento `#hex`.
    /// Compartido por el lector, el prefetch y las descargas para que todos descifren igual.
    nonisolated static func fetchData(for url: URL, session: URLSession) async throws -> Data {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let key = comps?.fragment           // clave de cifrado de MANGA Plus, si la hay
        comps?.fragment = nil
        let cleanURL = comps?.url ?? url

        var req = URLRequest(url: cleanURL)
        let host = cleanURL.host ?? ""
        if host.contains("mangaplus") || host.contains("tokyo-cdn") || host.contains("shueisha") {
            req.setValue("https://mangaplus.shueisha.co.jp", forHTTPHeaderField: "Origin")
            req.setValue("https://mangaplus.shueisha.co.jp/", forHTTPHeaderField: "Referer")
            req.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        } else if host.contains("comick") {
            // El CDN de Comick (comicknew.pictures) va tras Cloudflare: exige Referer y un UA de
            // Safari coherente con la huella TLS de NSURLSession (si no, 403 / reto).
            req.setValue("https://comick.live/", forHTTPHeaderField: "Referer")
            req.setValue(safariUA, forHTTPHeaderField: "User-Agent")
        } else if host.contains("mfcdn") || host.contains("mangafire") {
            // CDN de MangaFire: exige Referer.
            req.setValue("https://mangafire.to/", forHTTPHeaderField: "Referer")
            req.setValue(safariUA, forHTTPHeaderField: "User-Agent")
        }
        let (data, _) = try await session.data(for: req)
        guard let key, !key.isEmpty else { return data }
        // MangaFire baraja algunas imágenes (#scrambled_<offset>); el resto = XOR de MANGA Plus.
        if key.hasPrefix("scrambled_") {
            let offset = Int(String(key.dropFirst("scrambled_".count))) ?? 0
            return offset > 0 ? descramble(data, offset: offset) : data
        }
        return xorDecrypt(data, keyHex: key)
    }

    /// Des-baraja una imagen de MangaFire: rejilla de bloques rotada por `offset` (réplica del
    /// algoritmo de la extensión: piezas de 200px, mínimo 5 divisiones).
    private static func descramble(_ data: Data, offset: Int) -> Data {
        guard let src = UIImage(data: data), let cg = src.cgImage else { return data }
        let width = cg.width, height = cg.height
        func ceilDiv(_ a: Int, _ b: Int) -> Int { (a + b - 1) / b }
        let pieceW = min(200, ceilDiv(width, 5))
        let pieceH = min(200, ceilDiv(height, 5))
        let xMax = ceilDiv(width, pieceW) - 1
        let yMax = ceilDiv(height, pieceH) - 1
        guard xMax > 0, yMax > 0 else { return data }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return data }
        // Origen arriba-izquierda (como las coordenadas de la imagen).
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        for y in 0...yMax {
            for x in 0...xMax {
                let xDst = pieceW * x, yDst = pieceH * y
                let w = min(pieceW, width - xDst), h = min(pieceH, height - yDst)
                if w <= 0 || h <= 0 { continue }
                let xSrc = pieceW * (x == xMax ? x : ((xMax - x + offset) % xMax))
                let ySrc = pieceH * (y == yMax ? y : ((yMax - y + offset) % yMax))
                let srcRect = CGRect(x: xSrc, y: ySrc, width: w, height: h)
                    .intersection(CGRect(x: 0, y: 0, width: width, height: height))
                guard !srcRect.isNull, let piece = cg.cropping(to: srcRect) else { continue }
                ctx.draw(piece, in: CGRect(x: CGFloat(xDst), y: CGFloat(yDst), width: srcRect.width, height: srcRect.height))
            }
        }
        guard let out = ctx.makeImage() else { return data }
        return UIImage(cgImage: out).jpegData(compressionQuality: 0.9) ?? data
    }

    /// Descifrado XOR de MANGA Plus: byte[i] ^ clave[i % len], con la clave en hex.
    private static func xorDecrypt(_ data: Data, keyHex: String) -> Data {
        let chars = Array(keyHex)
        var keyStream = [UInt8]()
        keyStream.reserveCapacity(chars.count / 2)
        var i = 0
        while i + 1 < chars.count {
            if let b = UInt8(String(chars[i...i + 1]), radix: 16) { keyStream.append(b) }
            i += 2
        }
        guard !keyStream.isEmpty else { return data }
        var bytes = [UInt8](data)
        for idx in bytes.indices { bytes[idx] ^= keyStream[idx % keyStream.count] }
        return Data(bytes)
    }
}

/// Vista de imagen cacheada (reemplaza a AsyncImage donde queremos persistencia).
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let loaded = await ImageCache.shared.image(for: url) {
                image = loaded
            }
        }
    }
}
