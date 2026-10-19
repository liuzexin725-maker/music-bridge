import Foundation

@main
struct BridgeChecks {
    @MainActor
    static func main() async throws {
        precondition(PlaylistSource.identify("https://music.apple.com/cn/playlist/example/pl.abc") == .apple)
        precondition(PlaylistSource.identify("https://music.163.com/#/playlist?id=123") == .netease)
        precondition(PlaylistSource.identify("https://music.163.com/playlist?id=123") == .netease)
        for value in ["https://music.apple.com.attacker.example/cn/playlist/x/pl.abc", "https://music.apple.com@attacker.example/playlist/pl.abc", "file:///tmp/playlist", "https://music.apple.com/cn/album/x/123", "https://example.com/playlist/123"] {
            precondition(PlaylistSource.identify(value) == nil)
        }
        let suite = "MusicBridgeChecks.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        var devices: [IPodDevice] = []
        let root = URL(fileURLWithPath: "/does-not-exist")
        let model = BridgeModel(root: root, preferences: preferences,
                                deviceProvider: { devices }, monitorDevices: false)
        defer { model.shutdown() }
        precondition(model.device == nil && !model.canImport && model.deviceStatus == "等待连接")
        precondition(model.quality == .hiRes)
        let wrapper = URL(string: "http://127.0.0.1:12340")!
        let urls = ["https://music.apple.com/cn/playlist/example/pl.abc"]
        let highArguments = DownloaderRunner.arguments(urls: urls, wrapperURL: wrapper, quality: model.quality)
        precondition(highArguments == ["--lite-server", wrapper.absoluteString, "--alac-max", "192000", "--json"] + urls)
        precondition(!highArguments.contains("--aac") && !highArguments.contains("--atmos"))
        model.quality = .lossless
        model.originalCover = false
        precondition(DownloaderRunner.arguments(urls: urls, wrapperURL: wrapper, quality: model.quality).contains("48000"))
        let restored = BridgeModel(root: root, preferences: preferences, deviceProvider: { [] }, monitorDevices: false)
        precondition(restored.quality == .lossless)
        precondition(!restored.originalCover)
        restored.shutdown()
        let volume = URL(fileURLWithPath: "/Volumes/Fixture", isDirectory: true)
        devices = [IPodDevice(name: "实际卷名", rootURL: volume, musicURL: volume.appendingPathComponent("Music"), writeState: .readOnly, isRockbox: true)]
        model.refreshDevice()
        precondition(model.device?.name == "实际卷名" && model.device?.rootURL == volume)
        precondition(model.deviceStatus == "设备只读" && !model.canImport)
        model.importMusic()
        precondition(!model.importing)
        devices = [IPodDevice(name: "实际卷名", rootURL: volume, musicURL: volume.appendingPathComponent("Music"), writeState: .unknown, isRockbox: true)]
        model.refreshDevice()
        precondition(model.deviceStatus == "权限待确认" && !model.canImport)
        devices = [IPodDevice(name: "实际卷名", rootURL: volume, musicURL: volume.appendingPathComponent("Music"), writeState: .writable, isRockbox: true)]
        model.refreshDevice()
        precondition(model.deviceStatus == "连接就绪" && model.canImport)
        let phaseBeforeImport = model.phase
        model.importing = true
        model.startOrStop()
        model.stop()
        precondition(model.importing && !model.busy && model.phase == phaseBeforeImport)
        model.importing = false
        devices = []
        model.refreshDevice()
        precondition(model.device == nil && model.deviceStatus == "等待连接" && !model.canImport)
        model.source = "https://music.apple.com/cn/playlist/example/pl.abc"
        model.startOrStop()
        precondition(model.busy)
        model.stop()
        try await Task.sleep(for: .milliseconds(400))
        precondition(!model.busy && model.completed == 0 && model.phase == "已停止")
        precondition(model.completed == 0 && model.percent == 0 && !model.importing)
        try testPointerAndConfiguration()
        try testImportDestinations()
        try await testReadinessCancellationAndOutput()
        print("PASS: device/import guards; quality/cover persistence; real launch arguments; cancellation; bounded motion/accessibility; config preservation; import path containment; stale readiness and EOF output")
    }

    static func testPointerAndConfiguration() throws {
        let zero = SurfacePointer.normalized(location: CGPoint(x: CGFloat.nan, y: 10), size: CGSize(width: 100, height: 100))
        precondition(zero == SurfacePointer())
        precondition(SurfacePointer.normalized(location: .zero, size: .zero) == SurfacePointer())
        let pointer = SurfacePointer.normalized(location: CGPoint(x: 900, y: -900), size: CGSize(width: 100, height: 100))
        precondition(pointer == SurfacePointer(x: 1, y: -1))
        let offset = pointer.offset(hovered: true, reducedMotion: false, active: true, editing: false)
        precondition(abs(offset.width) <= 1.4 && abs(offset.height) <= 3)
        precondition(pointer.offset(hovered: true, reducedMotion: true, active: true, editing: false) == .zero)
        precondition(pointer.offset(hovered: true, reducedMotion: false, active: false, editing: false) == .zero)
        precondition(pointer.offset(hovered: true, reducedMotion: false, active: true, editing: true) == .zero)
        let configuration = "name: unchanged\nembed-cover: true\nnext-option: unchanged\n"
        precondition(DownloadConfiguration.settingCover(false, in: configuration) == "name: unchanged\nembed-cover: false\nnext-option: unchanged\n")
        precondition(DownloadConfiguration.settingCover(true, in: "name: unchanged") == "name: unchanged\nembed-cover: true\n")
        var buffer = OutputLineBuffer()
        precondition(buffer.append(Data("one\r\ntwo\rpar".utf8)) == ["one", "two"])
        precondition(buffer.append(Data("tial".utf8), endOfFile: true) == ["partial"])
        precondition(buffer.append(Data(), endOfFile: true).isEmpty)
        var longLine = OutputLineBuffer()
        precondition(longLine.append(Data(repeating: 65, count: 100_000)).isEmpty)
        precondition(longLine.append(Data(), endOfFile: true).first?.count == 65_536)
    }

    static func testImportDestinations() throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("MusicBridgeImportChecks-\(UUID())")
        defer { try? manager.removeItem(at: base) }
        let source = base.appendingPathComponent("Downloads")
        let volume = base.appendingPathComponent("Device")
        let music = volume.appendingPathComponent("Music")
        let outside = base.appendingPathComponent("Outside")
        for directory in [source, music, outside] { try manager.createDirectory(at: directory, withIntermediateDirectories: true) }
        let device = IPodDevice(name: "Fixture", rootURL: volume, musicURL: music, writeState: .writable, isRockbox: true)
        let service = IPodImporter()
        precondition(service.safeDestination(for: source.appendingPathComponent("album/song.m4a"), sourceRoot: source, device: device) != nil)
        precondition(service.safeDestination(for: outside.appendingPathComponent("song.m4a"), sourceRoot: source, device: device) == nil)
        try manager.createSymbolicLink(at: music.appendingPathComponent("escaped"), withDestinationURL: outside)
        precondition(service.safeDestination(for: source.appendingPathComponent("escaped/song.m4a"), sourceRoot: source, device: device) == nil)
        try manager.createSymbolicLink(at: music.appendingPathComponent("dangling"), withDestinationURL: outside.appendingPathComponent("missing"))
        precondition(service.safeDestination(for: source.appendingPathComponent("dangling/song.m4a"), sourceRoot: source, device: device) == nil)
        try manager.createSymbolicLink(atPath: music.appendingPathComponent("loop").path, withDestinationPath: "loop")
        precondition(service.safeDestination(for: source.appendingPathComponent("loop/song.m4a"), sourceRoot: source, device: device) == nil)
        try manager.createSymbolicLink(at: source.appendingPathComponent("outside-source"), withDestinationURL: outside)
        precondition(service.safeDestination(for: source.appendingPathComponent("outside-source/song.m4a"), sourceRoot: source, device: device) == nil)
        let report = service.importFiles([(source.appendingPathComponent("song.m4a"), source)], to: device)
        precondition(report.imported == 0 && !report.messages.isEmpty)
        precondition(!manager.fileExists(atPath: music.appendingPathComponent("song.m4a").path))
    }

    @MainActor
    static func testReadinessCancellationAndOutput() async throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("MusicBridgeRunnerChecks-\(UUID())")
        try manager.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: base) }
        try "embed-cover: true\n".write(to: base.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        let first = base.appendingPathComponent("first")
        let second = base.appendingPathComponent("second")
        try "#!/bin/sh\nprintf first-launched > first-marker\n".write(to: first, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nprintf 'second-output-without-newline'\n".write(to: second, atomically: true, encoding: .utf8)
        for url in [first, second] { try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path) }
        var probes: [(Result<Void, Error>) -> Void] = []
        let runner = DownloaderRunner(statusProbe: { _, completion in probes.append(completion) })
        defer { runner.stop() }
        var output: [String] = []
        runner.onOutput = { output.append($0) }
        let wrapper = URL(string: "http://127.0.0.1:12340")!
        runner.start(binaryPath: first.path, workingDirectory: base.path, urls: [], wrapperLauncherPath: nil,
                     wrapperURL: wrapper, quality: .hiRes, completion: { _ in })
        precondition(probes.count == 1)
        runner.stop()
        runner.start(binaryPath: second.path, workingDirectory: base.path, urls: [], wrapperLauncherPath: nil,
                     wrapperURL: wrapper, quality: .hiRes, completion: { _ in })
        precondition(probes.count == 2)
        probes[0](.success(()))
        probes[1](.success(()))
        try await Task.sleep(for: .milliseconds(400))
        precondition(!manager.fileExists(atPath: base.appendingPathComponent("first-marker").path))
        precondition(output.contains("second-output-without-newline"))
    }
}
