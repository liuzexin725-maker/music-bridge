import AppKit
import SwiftUI

enum PlaylistSource: Equatable {
    case apple, netease

    static func identify(_ text: String) -> PlaylistSource? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), url.user == nil, url.password == nil else { return nil }
        if host == "music.apple.com", url.path.contains("/playlist/"),
           url.pathComponents.contains(where: { $0.hasPrefix("pl.") && $0.count > 3 }) { return .apple }
        if host == "music.163.com", (url.path.contains("playlist") || (url.fragment ?? "").contains("playlist")) { return .netease }
        if host == "163cn.tv" { return .netease }
        return nil
    }
}

@MainActor
final class BridgeModel: ObservableObject {
    @Published var source = ""
    @Published var busy = false
    @Published var importing = false
    @Published var phase = "待开始"
    @Published var taskTitle = "没有活动任务"
    @Published var taskDetail = "下载完成后不会自动导入设备"
    @Published var percent = 0.0
    @Published var queue: Int?
    @Published var completed = 0
    @Published var skipped = 0
    @Published var failed = false
    @Published var settingsExpanded = false
    @Published var logsExpanded = false
    @Published var logs = ["Music Bridge 已就绪"]
    @Published var device: IPodDevice?
    @Published var wrapperReady = false
    @Published var checkingService = false
    @Published var connectionDetail = "尚未检查本地服务"
    @Published var originalCover: Bool {
        didSet { preferences.set(originalCover, forKey: "originalCover") }
    }
    @Published var quality: AudioQuality {
        didSet { preferences.set(quality.rawValue, forKey: "audioQuality") }
    }

    let root: URL
    private let runner = DownloaderRunner()
    private let importer = IPodImporter()
    private var workflow: Task<Void, Never>?
    private var observations: [NSObjectProtocol] = []
    private var generation = UUID()
    private var snapshot: [URL: FileSignature] = [:]
    private let preferences: UserDefaults
    private let deviceProvider: () -> [IPodDevice]
    private var deviceTimer: Timer?
    private var shutDown = false

    init(root: URL, preferences: UserDefaults = .standard,
         deviceProvider: @escaping () -> [IPodDevice] = { IPodImporter().mountedDevices() },
         monitorDevices: Bool = true) {
        self.root = root
        self.preferences = preferences
        self.deviceProvider = deviceProvider
        originalCover = preferences.object(forKey: "originalCover") as? Bool ?? true
        quality = AudioQuality(rawValue: preferences.string(forKey: "audioQuality") ?? "") ?? .hiRes
        runner.onOutput = { [weak self] line in self?.receive(line) }
        runner.onStarted = { [weak self] in
            self?.phase = "正在下载"
            self?.taskTitle = "正在下载音乐"
        }
        runner.onFinished = { [weak self] status in self?.finished(status) }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshDevice() }
            })
        }
        refreshDevice()
        if monitorDevices {
            deviceTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshDevice() }
            }
        }
    }

    var canImport: Bool { device?.canImport == true && !busy && !importing && !shutDown }

    var deviceStatus: String {
        guard let device else { return "等待连接" }
        if importing { return "正在导入" }
        switch device.writeState {
        case .writable: return "连接就绪"
        case .readOnly: return "设备只读"
        case .unknown: return "权限待确认"
        }
    }

    func refreshDevice() {
        guard !shutDown else { return }
        let devices = deviceProvider()
        let detected = devices.first(where: { $0.canImport }) ?? devices.first
        if device != detected { device = detected }
    }

    func checkService() async {
        guard !checkingService, !shutDown else { return }
        checkingService = true
        defer { checkingService = false }
        do {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:12340/status")!)
            request.timeoutInterval = 2
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !shutDown else { return }
            let status = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            wrapperReady = (response as? HTTPURLResponse)?.statusCode == 200 && (status?["code"] as? Int) == 0
            connectionDetail = wrapperReady ? "本地下载服务已就绪" : "服务响应异常；点击开始后将重试"
        } catch {
            guard !shutDown else { return }
            wrapperReady = false
            connectionDetail = "服务尚未启动；点击开始后自动启动"
        }
    }

    func startOrStop() {
        guard !importing, !shutDown else { return }
        if busy { stop(); return }
        guard let platform = PlaylistSource.identify(source) else {
            fail("链接格式不正确", "请粘贴 music.163.com 或 music.apple.com 的公开歌单链接。")
            return
        }
        busy = true; failed = false; percent = 0; completed = 0; skipped = 0; queue = nil
        generation = UUID()
        let session = generation
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = "正在准备"; taskTitle = "正在读取歌单"; taskDetail = "准备下载，完成后由你决定何时导入"
        workflow = Task { [self] in
            do {
                var urls = [text]
                if platform == .netease {
                    let export = try await GoMusicClient().exportPlaylist(url: text)
                    try Task.checkCancellation()
                    guard session == generation else { return }
                    queue = export.count; phase = "正在匹配"; taskTitle = "正在匹配 Apple Music"
                    let result = try await AppleMusicCatalogClient().match(export: export) { [weak self] current, total in
                        guard let self, self.generation == session else { return }
                        self.taskDetail = "正在匹配 · \(current) / \(total)"
                    }
                    try Task.checkCancellation()
                    guard session == generation else { return }
                    urls = result.urls; skipped = result.skipped.count
                    if !result.skipped.isEmpty { log("跳过 \(result.skipped.count) 首未确认版本的歌曲。") }
                }
                try Task.checkCancellation()
                guard session == generation else { return }
                try applyDownloadSettings()
                let service = importer
                let directory = root
                let scan = Task.detached(priority: .utility) { service.snapshotAudioFiles(in: directory) }
                let files = await withTaskCancellationHandler(operation: { await scan.value }, onCancel: { scan.cancel() })
                try Task.checkCancellation()
                guard session == generation else { return }
                snapshot = files
                phase = "正在连接"; taskTitle = "正在准备下载"
                taskDetail = "正在检查本地下载服务和登录状态"
                log("正在准备本地下载服务。")
                log("音质：\(quality.title)；实际规格以曲目提供的音源为准。")
                runner.start(binaryPath: root.appendingPathComponent("amdl").path,
                             workingDirectory: root.path, urls: urls,
                             wrapperLauncherPath: root.appendingPathComponent("work/wrapper-lite-macos/start-local.sh").path,
                             wrapperURL: URL(string: "http://127.0.0.1:12340")!, quality: quality) { [weak self] result in
                    guard let self, self.generation == session else { return }
                    if case .failure(let error) = result { self.fail("下载服务未就绪", error.localizedDescription) }
                }
            } catch {
                guard !Task.isCancelled, session == generation else { return }
                fail("下载没有完成", error.localizedDescription)
            }
        }
    }

    func stop() {
        guard !importing, !shutDown else { return }
        generation = UUID(); workflow?.cancel(); runner.stop()
        busy = false; phase = "已停止"; taskTitle = "任务已停止"
        taskDetail = "已下载文件保留在电脑中"; log("任务已停止。")
    }

    private func applyDownloadSettings() throws {
        let configURL = root.appendingPathComponent("config.yaml")
        let config = try String(contentsOf: configURL, encoding: .utf8)
        try DownloadConfiguration.settingCover(originalCover, in: config).write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func receive(_ line: String) {
        guard busy else { return }
        // Do not surface raw subprocess output: it may contain account/session values.
        if let range = line.range(of: "Queue \\d+ of \\d+", options: .regularExpression) {
            let words = line[range].split(separator: " ")
            if let current = Int(words[1]), let total = Int(words[3]) {
                queue = total; taskDetail = "正在处理 · \(current) / \(total)"
            }
        }
        if let range = line.range(of: "(?<![0-9])\\d{1,3}%", options: .regularExpression),
           let value = Double(line[range].dropLast()) { percent = min(100, max(0, value)) }
        if line.localizedCaseInsensitiveContains("decrypting") { taskDetail = "正在封装音频" }
    }

    private func finished(_ status: Int32) {
        guard busy else { return }
        if status != 0 { fail("下载没有完成", "下载器退出代码 \(status)，请检查服务和歌单后重试。"); return }
        let session = generation
        let service = importer
        let directory = root
        let previous = snapshot
        phase = "正在核对文件"
        workflow = Task {
            let scan = Task.detached(priority: .utility) { service.changedAudioFiles(in: directory, comparedTo: previous) }
            let changed = await withTaskCancellationHandler(operation: { await scan.value }, onCancel: { scan.cancel() })
            guard !Task.isCancelled, session == generation, !shutDown else { return }
            snapshot.removeAll()
            busy = false
            completed = changed.count; percent = 100; phase = "下载完成"
            taskTitle = changed.isEmpty ? "下载任务已结束" : "已下载 \(changed.count) 首歌曲"
            taskDetail = "下载完成后不会自动导入设备"
            log("下载器完成；发现 \(changed.count) 个新增或更新的音频文件。")
            refreshDevice()
        }
    }

    func importMusic() {
        guard !busy, !importing, !shutDown else { return }
        refreshDevice()
        guard let target = device else { return }
        guard target.canImport else {
            fail("设备暂时无法导入", "请确认 iPod 已以可写方式挂载后重试。")
            return
        }
        importing = true; phase = "正在导入"; taskTitle = "正在扫描下载目录"
        let directory = root
        workflow = Task {
            let report = await Task.detached(priority: .userInitiated) {
                let service = IPodImporter()
                return service.importFiles(service.audioFiles(in: directory), to: target)
            }.value
            importing = false; phase = "导入完成"
            taskTitle = "已导入 \(report.imported) 首歌曲"
            taskDetail = "已有 \(report.alreadyPresent) 首 · 跳过 \(report.skippedUnplayable) 首"
            log("导入结束：\(report.imported) 首新增，\(report.alreadyPresent) 首已存在，\(report.skippedUnplayable) 首跳过。")
            if report.warningCount > 0 {
                phase = "导入结束 · 有提示"
                taskDetail = "\(report.warningCount) 项需要检查；已有设备文件不会被覆盖"
                log("有 \(report.warningCount) 项导入或音频检查提示；同名但大小不同的文件会保留。")
            }
        }
    }

    func fail(_ title: String, _ detail: String) {
        busy = false; failed = true; phase = "需要检查"; taskTitle = title; taskDetail = detail
        log(title)
    }

    func log(_ message: String) {
        logs.append(message)
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
    }

    func shutdown() {
        shutDown = true
        generation = UUID()
        deviceTimer?.invalidate()
        deviceTimer = nil
        workflow?.cancel(); runner.stop()
        observations.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observations.removeAll()
    }
}
