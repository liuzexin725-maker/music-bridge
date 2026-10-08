import Foundation

enum GoMusicError: LocalizedError {
    case invalidResponse
    case serviceUnavailable(Int)
    case apiFailure(String)
    case emptyPlaylist

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GoMusic 返回的数据格式无法识别。"
        case .serviceUnavailable(let status):
            return "GoMusic 服务暂时不可用（HTTP \(status)）。稍后重试即可。"
        case .apiFailure(let message):
            return message.isEmpty ? "GoMusic 未能解析这个歌单。" : message
        case .emptyPlaylist:
            return "歌单没有可导出的歌曲，或歌单未公开。"
        }
    }
}

struct GoMusicClient {
    private let endpoint = URL(string: "https://sss.unmeta.cn/songlist")!

    func exportPlaylist(url: String) async throws -> PlaylistExport {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "detailed", value: "false"),
            URLQueryItem(name: "format", value: "song-singer"),
            URLQueryItem(name: "order", value: "normal")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Music Bridge/1.0", forHTTPHeaderField: "User-Agent")
        let formAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+="))
        let encodedURL = url.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? url
        request.httpBody = "url=\(encodedURL)".data(using: .utf8)

        var data: Data?
        for attempt in 0..<3 {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GoMusicError.invalidResponse }
            if (200..<300).contains(http.statusCode) {
                data = responseData
                break
            }
            let isTransient = [502, 503, 504].contains(http.statusCode)
            guard isTransient, attempt < 2 else {
                throw GoMusicError.serviceUnavailable(http.statusCode)
            }
            try await Task.sleep(for: .seconds(attempt == 0 ? 1 : 2))
        }

        guard let data else { throw GoMusicError.invalidResponse }
        let envelope = try JSONDecoder().decode(GoMusicEnvelope.self, from: data)
        guard envelope.code == 1 else { throw GoMusicError.apiFailure(envelope.messageText ?? "") }
        guard let songs = envelope.data?.songs, !songs.isEmpty else { throw GoMusicError.emptyPlaylist }
        return PlaylistExport(text: songs.joined(separator: "\n"), count: envelope.data?.songsCount ?? songs.count)
    }
}

private struct GoMusicEnvelope: Decodable {
    let code: Int
    let message: String?
    let msg: String?
    let data: GoMusicData?

    var messageText: String? { message ?? msg }
}

private struct GoMusicData: Decodable {
    let songs: [String]?
    let songsCount: Int?

    enum CodingKeys: String, CodingKey {
        case songs
        case songsCount = "songs_count"
    }
}
