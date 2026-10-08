import Foundation

struct CatalogTrackQuery: Sendable {
    let title: String
    let artist: String

    var displayName: String {
        artist.isEmpty ? title : "\(title) · \(artist)"
    }
}

struct CatalogMatchResult: Sendable {
    let urls: [String]
    let matched: Int
    let skipped: [CatalogTrackQuery]
}

enum AppleMusicCatalogError: LocalizedError {
    case tokenUnavailable
    case invalidResponse
    case serviceUnavailable(Int)
    case noMatches

    var errorDescription: String? {
        switch self {
        case .tokenUnavailable:
            return "无法取得 Apple Music 搜索凭证。"
        case .invalidResponse:
            return "Apple Music 搜索返回了无法识别的数据。"
        case .serviceUnavailable(let status):
            return "Apple Music 搜索暂时不可用（HTTP \(status)）。"
        case .noMatches:
            return "没有找到可下载的 Apple Music 单曲。"
        }
    }
}

/// Resolves the title/artist lines exported by GoMusic into public Apple Music
/// song URLs. Only high-confidence matches are returned, so an ambiguous
/// version is skipped instead of being downloaded silently.
struct AppleMusicCatalogClient: Sendable {
    private let storefront = "cn"
    private let language = "zh-CN"

    func match(
        export: PlaylistExport,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> CatalogMatchResult {
        let queries = parseQueries(export.text)
        guard !queries.isEmpty else { throw AppleMusicCatalogError.noMatches }

        let token = try await fetchDeveloperToken()
        var urls: [String] = []
        var skipped: [CatalogTrackQuery] = []
        var seen = Set<String>()
        var lastSearchError: Error?

        for (index, query) in queries.enumerated() {
            try Task.checkCancellation()
            do {
                let match = try await search(query: query, token: token)
                if let url = match?.url, seen.insert(url).inserted {
                    urls.append(url)
                } else {
                    skipped.append(query)
                }
            } catch {
                lastSearchError = error
                skipped.append(query)
            }
            await progress(index + 1, queries.count)
        }

        if urls.isEmpty {
            throw lastSearchError ?? AppleMusicCatalogError.noMatches
        }
        return CatalogMatchResult(urls: urls, matched: urls.count, skipped: skipped)
    }

    private func fetchDeveloperToken() async throws -> String {
        var homeRequest = URLRequest(url: URL(string: "https://music.apple.com/\(storefront)")!)
        homeRequest.setValue("Music Bridge/1.0", forHTTPHeaderField: "User-Agent")
        let (homeData, homeResponse) = try await URLSession.shared.data(for: homeRequest)
        guard let homeHTTP = homeResponse as? HTTPURLResponse,
              (200..<400).contains(homeHTTP.statusCode) else {
            throw AppleMusicCatalogError.invalidResponse
        }
        guard let home = String(data: homeData, encoding: .utf8),
              let scriptPath = home.range(of: "/assets/index~[^\"']+\\.js", options: .regularExpression).map({ String(home[$0]) }) else {
            throw AppleMusicCatalogError.tokenUnavailable
        }

        var scriptRequest = URLRequest(url: URL(string: "https://music.apple.com\(scriptPath)")!)
        scriptRequest.setValue("Music Bridge/1.0", forHTTPHeaderField: "User-Agent")
        let (scriptData, scriptResponse) = try await URLSession.shared.data(for: scriptRequest)
        guard let scriptHTTP = scriptResponse as? HTTPURLResponse,
              (200..<400).contains(scriptHTTP.statusCode),
              let script = String(data: scriptData, encoding: .utf8),
              let token = script.range(of: "eyJ[A-Za-z0-9-_=]+\\.[A-Za-z0-9-_=]+\\.[A-Za-z0-9-_=]+", options: .regularExpression).map({ String(script[$0]) }) else {
            throw AppleMusicCatalogError.tokenUnavailable
        }
        return token
    }

    private func search(query: CatalogTrackQuery, token: String) async throws -> CatalogSong? {
        var components = URLComponents(string: "https://amp-api.music.apple.com/v1/catalog/\(storefront)/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(query.title) \(query.artist)".trimmingCharacters(in: .whitespaces)),
            URLQueryItem(name: "types", value: "songs"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "l", value: language)
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("Music Bridge/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppleMusicCatalogError.invalidResponse }
        guard http.statusCode == 200 else { throw AppleMusicCatalogError.serviceUnavailable(http.statusCode) }
        let envelope = try JSONDecoder().decode(CatalogSearchEnvelope.self, from: data)
        let candidates = envelope.results.songs?.data ?? []
        return candidates
            .compactMap { candidate in
                guard let url = candidate.attributes.url else { return nil }
                let titleScore = similarity(query.title, candidate.attributes.name)
                let artistScore = artistSimilarity(query.artist, candidate.attributes.artistName)
                guard titleScore >= 0.70,
                      query.artist.isEmpty || artistScore >= 0.45 else { return nil }
                let score = score(query: query, candidate: candidate)
                return CatalogSong(
                    title: candidate.attributes.name,
                    artist: candidate.attributes.artistName,
                    url: url,
                    score: score
                )
            }
            .filter { $0.score >= 0.72 }
            .max { $0.score < $1.score }
    }

    private func score(query: CatalogTrackQuery, candidate: CatalogSearchSong) -> Double {
        let title = similarity(query.title, candidate.attributes.name)
        let artist = artistSimilarity(query.artist, candidate.attributes.artistName)
        let exactBonus = normalize(query.title) == normalize(candidate.attributes.name) ? 0.12 : 0
        let variantPenalty = versionMismatch(query.title, candidate.attributes.name) ? 0.35 : 0
        return min(1, max(0, title * 0.68 + artist * 0.32 + exactBonus - variantPenalty))
    }

    private func versionMismatch(_ lhs: String, _ rhs: String) -> Bool {
        let markers = ["live", "remix", "remaster", "acoustic", "demo", "karaoke", "instrumental", "sped up", "现场", "混音", "重制"]
        let left = lhs.lowercased()
        let right = rhs.lowercased()
        return markers.contains { marker in
            left.contains(marker) != right.contains(marker)
        }
    }

    private func artistSimilarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty else { return 0.68 }
        let full = similarity(lhs, rhs)
        let queryParts = lhs.split(whereSeparator: { "&,、/".contains($0) }).map(String.init)
        let candidateParts = rhs.split(whereSeparator: { "&,、/".contains($0) }).map(String.init)
        let partBest = queryParts.map { part in
            candidateParts.map { similarity(part, $0) }.max() ?? 0
        }.reduce(0, +) / Double(max(1, queryParts.count))
        return max(full, partBest)
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(normalize(lhs))
        let right = Array(normalize(rhs))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let maxLength = max(left.count, right.count)
        var previous = Array(0...right.count)
        for (row, leftCharacter) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = row + 1
            for (column, rightCharacter) in right.enumerated() {
                let cost = leftCharacter == rightCharacter ? 0 : 1
                current[column + 1] = min(
                    previous[column + 1] + 1,
                    current[column] + 1,
                    previous[column] + cost
                )
            }
            previous = current
        }
        return 1 - Double(previous[right.count]) / Double(maxLength)
    }

    private func normalize(_ value: String) -> String {
        var text = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        text = text.replacingOccurrences(of: "feat.", with: " ")
        text = text.replacingOccurrences(of: "featuring", with: " ")
        text = text.replacingOccurrences(of: "\\([^)]*\\)|\\[[^]]*\\]|（[^）]*）|【[^】]*】", with: " ", options: .regularExpression)
        return text.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(whereSeparator: { $0 == " " })
            .joined()
    }

    private func parseQueries(_ text: String) -> [CatalogTrackQuery] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            if let separator = line.range(of: " - ") {
                let title = String(line[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
                let artist = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { return nil }
                return CatalogTrackQuery(title: title, artist: artist)
            }
            return CatalogTrackQuery(title: line, artist: "")
        }
    }
}

private struct CatalogSearchEnvelope: Decodable {
    let results: CatalogSearchResults
}

private struct CatalogSearchResults: Decodable {
    let songs: CatalogSongResults?
}

private struct CatalogSongResults: Decodable {
    let data: [CatalogSearchSong]
}

private struct CatalogSearchSong: Decodable {
    let attributes: CatalogSearchAttributes
}

private struct CatalogSearchAttributes: Decodable {
    let name: String
    let artistName: String
    let url: String?
}

private struct CatalogSong: Sendable {
    let title: String
    let artist: String
    let url: String
    let score: Double
}
