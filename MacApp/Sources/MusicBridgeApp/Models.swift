import Foundation

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
