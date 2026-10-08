import Foundation

/// Owns the two local processes used by the macOS front end.
///
/// The wrapper is deliberately treated as a readiness dependency. A 200 from
/// `/status` is not enough: wrapper-lite returns an envelope and `code == 0`
/// is the success signal. Keeping that check here prevents the UI from
/// starting amdl and then presenting a misleading download failure.
final class DownloaderRunner: NSObject {
    var onOutput: ((String) -> Void)?
    var onStarted: (() -> Void)?
    var onFinished: ((Int32) -> Void)?

    private var process: Process?
    private var wrapperProcess: Process?
    private let ioQueue = DispatchQueue(label: "cn.unmeta.musicbridge.downloader-io")

    func start(binaryPath: String,
               workingDirectory: String,
               urls: [String],
               wrapperLauncherPath: String?,
               wrapperURL: URL,
               completion: @escaping (Result<Void, Error>) -> Void) {
        stopDownloader()

        let binaryURL = URL(fileURLWithPath: binaryPath)
        let directoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            complete(completion, with: .failure(RunnerError.invalidBinary(binaryPath)))
            return
        }
        guard FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("config.yaml").path) else {
            complete(completion, with: .failure(RunnerError.missingConfig(directoryURL.path)))
            return
        }

        let launchDownloader = { [weak self] in
            guard let self else { return }
            self.launchDownloader(binaryURL: binaryURL,
                                  directoryURL: directoryURL,
                                  urls: urls,
                                  wrapperURL: wrapperURL,
                                  completion: completion)
        }

        waitForWrapper(orStartAt: wrapperLauncherPath,
                       wrapperURL: wrapperURL,
                       then: launchDownloader,
                       failure: { [weak self] error in
                           self?.complete(completion, with: .failure(error))
                       })
    }

    private func launchDownloader(binaryURL: URL,
                                  directoryURL: URL,
                                  urls: [String],
                                  wrapperURL: URL,
                                  completion: @escaping (Result<Void, Error>) -> Void) {
        let process = Process()
        process.executableURL = binaryURL
        process.currentDirectoryURL = directoryURL
        // Use the exact endpoint that passed the readiness check. This keeps
        // amdl from silently reading a different lite-server from config.yaml.
        // Keep the argument list aligned with the installed amdl build. The
        // current binary already returns a non-zero exit status on failure;
        // older builds accepted --exit-on-error, but current amdl rejects it
        // before it can inspect the playlist URL.
        process.arguments = ["--lite-server", wrapperURL.absoluteString, "--json"] + urls

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        attachOutput(pipe, prefix: nil)

        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self else { return }
                // stopDownloader() clears this reference before terminating a
                // user-stopped process, so an intentional stop does not look
                // like a failed download in the UI.
                guard self.process === process else { return }
                self.process = nil
                self.onFinished?(process.terminationStatus)
            }
        }

        do {
            try process.run()
            self.process = process
            DispatchQueue.main.async { [weak self] in self?.onStarted?() }
            complete(completion, with: .success(()))
        } catch {
            complete(completion, with: .failure(RunnerError.launchFailed(error.localizedDescription)))
        }
    }

    private func waitForWrapper(orStartAt launcherPath: String?,
                                wrapperURL: URL,
                                attempts: Int = 30,
                                then action: @escaping () -> Void,
                                failure: @escaping (Error) -> Void) {
        checkWrapper(wrapperURL: wrapperURL) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.emit("wrapper-lite 已就绪")
                action()
            case .failure:
                if self.wrapperProcess?.isRunning != true {
                    guard let launcherPath, FileManager.default.isExecutableFile(atPath: launcherPath) else {
                        failure(RunnerError.wrapperNotReady("未找到 wrapper-lite 启动脚本。请确认 work/wrapper-lite-macos 已存在。"))
                        return
                    }
                    do {
                        try self.startWrapper(at: launcherPath)
                        self.emit("正在启动 wrapper-lite…")
                    } catch {
                        failure(RunnerError.wrapperLaunchFailed(error.localizedDescription))
                        return
                    }
                }
                self.waitUntilWrapperReady(wrapperURL: wrapperURL,
                                           attempts: attempts,
                                           then: action,
                                           failure: failure)
            }
        }
    }

    private func startWrapper(at launcherPath: String) throws {
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/zsh")
        launcher.arguments = [launcherPath]

        // One combined pipe is continuously consumed. Leaving either child
        // stream unread can fill its buffer and make wrapper-lite hang while
        // the app is waiting for /status.
        let pipe = Pipe()
        launcher.standardOutput = pipe
        launcher.standardError = pipe
        attachOutput(pipe, prefix: "wrapper-lite")

        launcher.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self, self.wrapperProcess === process else { return }
                self.wrapperProcess = nil
                if process.terminationStatus != 0 {
                    self.emit("wrapper-lite 已退出（代码 \(process.terminationStatus)）")
                }
            }
        }

        try launcher.run()
        wrapperProcess = launcher
    }

    private func waitUntilWrapperReady(wrapperURL: URL,
                                       attempts: Int,
                                       then action: @escaping () -> Void,
                                       failure: @escaping (Error) -> Void) {
        checkWrapper(wrapperURL: wrapperURL) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.emit("wrapper-lite 已就绪")
                action()
            case .failure(let error):
                guard attempts > 1 else {
                    let detail = error.localizedDescription
                    failure(RunnerError.wrapperNotReady(
                        "wrapper-lite 未就绪（\(detail)）。首次使用请在 Terminal 运行 work/wrapper-lite-macos/login-local.sh 完成一次登录。"))
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.waitUntilWrapperReady(wrapperURL: wrapperURL,
                                               attempts: attempts - 1,
                                               then: action,
                                               failure: failure)
                }
            }
        }
    }

    private func checkWrapper(wrapperURL: URL,
                              completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: wrapperURL.appendingPathComponent("status"))
        request.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async {
                    completion(.failure(RunnerError.wrapperUnavailable(error.localizedDescription)))
                }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(RunnerError.wrapperUnavailable("没有收到有效响应")))
                }
                return
            }
            guard http.statusCode == 200 else {
                DispatchQueue.main.async {
                    completion(.failure(RunnerError.wrapperUnavailable("HTTP \(http.statusCode)")))
                }
                return
            }
            guard let data, !data.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(RunnerError.wrapperUnavailable("响应为空")))
                }
                return
            }
            do {
                let envelope = try JSONDecoder().decode(WrapperStatusEnvelope.self, from: data)
                guard envelope.code == 0 else {
                    let message = envelope.msg?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "服务返回错误"
                    DispatchQueue.main.async {
                        completion(.failure(RunnerError.wrapperUnavailable("code=\(envelope.code) \(message)")))
                    }
                    return
                }
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(RunnerError.wrapperUnavailable("响应不是有效的 JSON：\(error.localizedDescription)")))
                }
            }
        }.resume()
    }

    /// Read every chunk from a child process and forward complete lines to the
    /// main queue. This is intentionally shared by amdl and wrapper-lite.
    private func attachOutput(_ pipe: Pipe, prefix: String?) {
        var pending = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.ioQueue.async {
                pending.append(data)
                while let separator = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                    let lineData = pending[..<separator]
                    pending.removeSubrange(...separator)
                    // Progress bars commonly use CR in place of LF. Treat a
                    // CRLF pair as one separator so the UI receives clean
                    // progress updates without duplicate empty lines.
                    while let next = pending.first, next == 0x0A || next == 0x0D {
                        pending.removeFirst()
                    }
                    guard var line = String(data: lineData, encoding: .utf8), !line.isEmpty else { continue }
                    if let prefix { line = "[\(prefix)] \(line)" }
                    self?.emit(line)
                }
            }
        }
    }

    private func emit(_ line: String) {
        DispatchQueue.main.async { [weak self] in self?.onOutput?(line) }
    }

    private func complete(_ completion: @escaping (Result<Void, Error>) -> Void,
                          with result: Result<Void, Error>) {
        DispatchQueue.main.async { completion(result) }
    }

    /// Stop only amdl. Keeping wrapper-lite alive makes subsequent retries
    /// fast and avoids starting a second emulator process for every playlist.
    private func stopDownloader() {
        process?.terminate()
        process = nil
    }

    /// Stop both children, used when the user explicitly presses Stop.
    func stop() {
        stopDownloader()
        wrapperProcess?.terminate()
        wrapperProcess = nil
    }
}

private struct WrapperStatusEnvelope: Decodable {
    let code: Int
    let msg: String?
}

enum RunnerError: LocalizedError {
    case invalidBinary(String)
    case missingConfig(String)
    case launchFailed(String)
    case wrapperUnavailable(String)
    case wrapperLaunchFailed(String)
    case wrapperNotReady(String)

    var errorDescription: String? {
        switch self {
        case .invalidBinary(let path): return "找不到可执行的 amdl：\(path)"
        case .missingConfig(let path): return "下载器目录缺少 config.yaml：\(path)"
        case .launchFailed(let message): return "启动下载器失败：\(message)"
        case .wrapperUnavailable(let message): return "wrapper-lite 不可用：\(message)"
        case .wrapperLaunchFailed(let message): return "启动 wrapper-lite 失败：\(message)"
        case .wrapperNotReady(let message): return message
        }
    }
}
