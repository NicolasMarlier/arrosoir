import Foundation

/// Photos de référence d'une espèce, pour vérifier une identification.
struct SpeciesPhotos: Equatable {
    var urls: [URL]
    var credit: String
}

/// iNaturalist (plusieurs photos par espèce, gère les synonymes), Wikipédia en secours.
@MainActor
final class SpeciesPhotoService {
    static let shared = SpeciesPhotoService()
    private var cache: [String: SpeciesPhotos?] = [:]

    func photos(scientificName: String, commonName: String) async -> SpeciesPhotos? {
        let key = scientificName.lowercased()
        if let cached = cache[key] { return cached }
        var result = await iNaturalist(scientificName)
        if result == nil { result = await wikipedia(title: scientificName, lang: "en") }
        if result == nil { result = await wikipedia(title: commonName, lang: "fr") }
        cache[key] = result
        return result
    }

    private func json(_ url: URL) async -> [String: Any]? {
        var r = URLRequest(url: url)
        r.setValue("Arrosoir/0.1 (app perso iOS)", forHTTPHeaderField: "User-Agent")
        r.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func iNaturalist(_ name: String) async -> SpeciesPhotos? {
        var c = URLComponents(string: "https://api.inaturalist.org/v1/taxa")!
        c.queryItems = [URLQueryItem(name: "q", value: name), URLQueryItem(name: "per_page", value: "1"), URLQueryItem(name: "is_active", value: "true")]
        guard let url = c.url, let search = await json(url),
              let first = (search["results"] as? [[String: Any]])?.first,
              let id = first["id"] as? Int else { return nil }

        var urls: [URL] = []
        if let detail = await json(URL(string: "https://api.inaturalist.org/v1/taxa/\(id)")!),
           let taxon = (detail["results"] as? [[String: Any]])?.first,
           let photos = taxon["taxon_photos"] as? [[String: Any]] {
            urls = photos.prefix(6).compactMap { tp in
                let p = tp["photo"] as? [String: Any]
                return (p?["medium_url"] as? String).flatMap(URL.init(string:))
            }
        }
        if urls.isEmpty, let p = first["default_photo"] as? [String: Any], let s = p["medium_url"] as? String, let u = URL(string: s) {
            urls = [u]
        }
        return urls.isEmpty ? nil : SpeciesPhotos(urls: urls, credit: "Photos iNaturalist (CC)")
    }

    private func wikipedia(title: String, lang: String) async -> SpeciesPhotos? {
        let t = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(t)"),
              let obj = await json(url) else { return nil }
        let src = (obj["originalimage"] as? [String: Any])?["source"] as? String ?? (obj["thumbnail"] as? [String: Any])?["source"] as? String
        guard let src, let u = URL(string: src) else { return nil }
        return SpeciesPhotos(urls: [u], credit: "Photo Wikipédia")
    }
}
