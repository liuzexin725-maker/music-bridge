import Foundation

struct OutputLineBuffer {
    private var pending = Data()
    private let limit = 65_536

    mutating func append(_ bytes: Data, endOfFile: Bool = false) -> [String] {
        pending.append(bytes)
        var lines: [String] = []
        while let end = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            if let line = String(data: pending[..<end].suffix(limit), encoding: .utf8), !line.isEmpty { lines.append(line) }
            pending.removeSubrange(...end)
        }
        if pending.count > limit { pending = Data(pending.suffix(limit)) }
        if endOfFile {
            if let line = String(data: pending, encoding: .utf8), !line.isEmpty { lines.append(line) }
            pending.removeAll(keepingCapacity: false)
        }
        return lines
    }
}

enum DownloadConfiguration {
    static func settingCover(_ enabled: Bool, in configuration: String) -> String {
        let replacement = "embed-cover: \(enabled ? "true" : "false")"
        if let range = configuration.range(of: "(?m)^embed-cover:[^\\n]*", options: .regularExpression) {
            var result = configuration
            result.replaceSubrange(range, with: replacement)
            return result
        }
        return configuration + (configuration.hasSuffix("\n") ? "" : "\n") + replacement + "\n"
    }
}

enum AudioQuality: String, CaseIterable, Identifiable {
    case hiRes = "alac-192000"
    case lossless = "alac-48000"

    var id: String { rawValue }
    var maximumSampleRate: Int { self == .hiRes ? 192000 : 48000 }
    var title: String {
        self == .hiRes ? "高解析度无损 · ALAC（最高 192 kHz）" : "无损 · ALAC（最高 48 kHz）"
    }
    var summary: String { self == .hiRes ? "ALAC · 最高无损" : "ALAC · 无损" }
}

struct PlaylistExport: Sendable {
    let text: String
    let count: Int
}

enum WorkflowStep: Int, CaseIterable, Identifiable, Hashable {
    case source = 1
    case migrate = 2
    case download = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .source: return "导出网易云歌单"
        case .migrate: return "迁移到 Apple Music"
        case .download: return "下载 Apple Music 歌单"
        }
    }
}
