import AppKit

struct FileSignature: Sendable, Equatable {
    let size: UInt64
    let modificationDate: Date
}

enum DeviceWriteState: String, Sendable {
    case writable = "可写"
    case readOnly = "只读"
    case unknown = "待确认"
}

struct IPodDevice: Sendable, Equatable {
    let name: String
    let rootURL: URL
    let musicURL: URL
    let writeState: DeviceWriteState
    let isRockbox: Bool
    var volumeIdentifier: String? = nil

    var canImport: Bool { writeState == .writable }
}

struct MediaCheckResult: Sendable {
    let playable: Bool
    let bitrate: Int?
    let hasEmbeddedCover: Bool
    let codec: String?
}

struct IPodImportReport: Sendable {
    let deviceName: String
    let imported: Int
    let alreadyPresent: Int
    let skippedUnplayable: Int
    let missingSourceCovers: Int
    let missingDestinationCovers: Int
    let missingBitrates: Int
    let sourceFiles: Int
    let warningCount: Int
    let messages: [String]
}

/// Finds a mounted Rockbox/iPod volume, imports only files changed by the
/// current download, and verifies the media both before and after copying.
struct IPodImporter: Sendable {
    private let audioExtensions: Set<String> = ["m4a", "mp4", "mp3", "flac", "aac", "ogg", "opus", "wav"]

    func mountedDevices() -> [IPodDevice] {
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey, .volumeIsRemovableKey, .volumeIsReadOnlyKey],
            options: [.skipHiddenVolumes]
        ) ?? []

        return volumes.compactMap { rootURL in
            let rockbox = rootURL.appendingPathComponent(".rockbox", isDirectory: true)
            let iPodControl = rootURL.appendingPathComponent("iPod_Control", isDirectory: true)
            let musicURL = rootURL.appendingPathComponent("Music", isDirectory: true)
            guard isDirectory(rockbox) || (isDirectory(iPodControl) && isDirectory(musicURL)) else { return nil }
            let values = try? rootURL.resourceValues(forKeys: [.volumeNameKey, .volumeIsReadOnlyKey, .volumeUUIDStringKey])
            let writeTarget = isDirectory(musicURL) ? musicURL : rootURL
            let access: DeviceWriteState
            if values?.volumeIsReadOnly == true {
                access = .readOnly
            } else if values?.volumeIsReadOnly == false {
                access = FileManager.default.isWritableFile(atPath: writeTarget.path) ? .writable : .readOnly
            } else {
                access = .unknown
            }
            let name = values?.volumeName
                ?? rootURL.lastPathComponent
            return IPodDevice(name: name, rootURL: rootURL, musicURL: musicURL,
                              writeState: access, isRockbox: isDirectory(rockbox), volumeIdentifier: values?.volumeUUIDString)
        }
    }

    func sourceRoots(in workingDirectory: URL) -> [URL] {
        var roots: [URL] = []
        let configURL = workingDirectory.appendingPathComponent("config.yaml")
        if let config = try? String(contentsOf: configURL, encoding: .utf8) {
            for key in ["alac-save-folder", "atmos-save-folder", "aac-save-folder", "mv-save-folder"] {
                if let value = yamlValue(config, key: key), !value.isEmpty {
                    let root = URL(fileURLWithPath: value, relativeTo: workingDirectory).standardizedFileURL
                    if isDirectory(root) { roots.append(root) }
                }
            }
        }

        if let entries = try? FileManager.default.contentsOfDirectory(
            at: workingDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            roots.append(contentsOf: entries.filter {
                $0.lastPathComponent.hasPrefix("AM-DL") && isDirectory($0)
            })
        }
        return uniqueURLs(roots)
    }

    func snapshotAudioFiles(in workingDirectory: URL) -> [URL: FileSignature] {
        var snapshot: [URL: FileSignature] = [:]
        for root in sourceRoots(in: workingDirectory) {
            for file in enumerateAudioFiles(in: root) {
                if let signature = signature(of: file) {
                    snapshot[file] = signature
                }
            }
        }
        return snapshot
    }

    func changedAudioFiles(
        in workingDirectory: URL,
        comparedTo previous: [URL: FileSignature]
    ) -> [(url: URL, root: URL)] {
        var changed: [(url: URL, root: URL)] = []
        for root in sourceRoots(in: workingDirectory) {
            for file in enumerateAudioFiles(in: root) {
                guard let current = signature(of: file) else { continue }
                if previous[file] != current {
                    changed.append((file, root))
                }
            }
        }
        return changed.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    /// Returns every downloaded audio file with its source root. The manual
    /// iPod action uses this full view so it can detect files imported during
    /// an earlier session as well as files from the current download.
    func audioFiles(in workingDirectory: URL) -> [(url: URL, root: URL)] {
        var files: [(url: URL, root: URL)] = []
        for root in sourceRoots(in: workingDirectory) {
            files.append(contentsOf: enumerateAudioFiles(in: root).map { (url: $0, root: root) })
        }
        return files.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    func importFiles(
        _ files: [(url: URL, root: URL)],
        to device: IPodDevice
    ) -> IPodImportReport {
        let fileManager = FileManager.default
        var imported = 0
        var alreadyPresent = 0
        var skippedUnplayable = 0
        var missingSourceCovers = 0
        var missingDestinationCovers = 0
        var missingBitrateFiles = Set<String>()
        var messages: [String] = []
        var copiedSourceDirectories = Set<String>()
        var copiedDestinations: [URL] = []

        for item in files {
            guard deviceAvailable(device) else {
                messages.append("设备已断开、已被替换或变为只读，已停止导入。")
                break
            }
            guard let destination = safeDestination(for: item.url, sourceRoot: item.root, device: device) else {
                messages.append("跳过超出来源或设备目录的文件。")
                continue
            }
            let sourceCheck = inspect(item.url)
            if !sourceCheck.playable {
                skippedUnplayable += 1
                messages.append("跳过无法播放：\(item.url.lastPathComponent)")
                continue
            }
            if !sourceCheck.hasEmbeddedCover {
                missingSourceCovers += 1
            }
            if sourceCheck.bitrate == nil {
                missingBitrateFiles.insert(item.url.path)
            }

            do {
                guard deviceAvailable(device) else { throw ImportError.deviceUnavailable }
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: destination.path) {
                    let sameSize = signature(of: destination)?.size == signature(of: item.url)?.size
                    if sameSize {
                        alreadyPresent += 1
                    } else {
                        messages.append("跳过同名但大小不同的设备文件：\(item.url.lastPathComponent)")
                        continue
                    }
                } else {
                    try copyAtomically(item.url, to: destination, device: device)
                    imported += 1
                }
                copiedDestinations.append(destination)
                copiedSourceDirectories.insert(item.url.deletingLastPathComponent().path)
            } catch {
                messages.append("导入失败：\(item.url.lastPathComponent)（\(error.localizedDescription)）")
            }
        }

        // Rockbox themes commonly use a folder-level cover.jpg. Preserve it
        // beside imported tracks when the download produced one.
        var copiedCoverDirectories = Set<String>()
        for item in files where copiedSourceDirectories.contains(item.url.deletingLastPathComponent().path) {
            guard deviceAvailable(device) else { break }
            let sourceCover = item.url.deletingLastPathComponent().appendingPathComponent("cover.jpg")
            guard fileManager.fileExists(atPath: sourceCover.path) else { continue }
            guard copiedCoverDirectories.insert(sourceCover.deletingLastPathComponent().path).inserted else { continue }
            guard let destinationCover = safeDestination(for: sourceCover, sourceRoot: item.root, device: device) else { continue }
            do {
                try fileManager.createDirectory(
                    at: destinationCover.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if !fileManager.fileExists(atPath: destinationCover.path) {
                    try copyAtomically(sourceCover, to: destinationCover, device: device)
                }
            } catch {
                messages.append("封面复制失败：\(sourceCover.lastPathComponent)")
            }
        }

        for destination in copiedDestinations {
            guard deviceAvailable(device) else { break }
            let check = inspect(destination)
            if !check.hasEmbeddedCover { missingDestinationCovers += 1 }
            if check.bitrate == nil { missingBitrateFiles.insert(destination.path) }
            if !check.playable {
                messages.append("设备文件校验失败：\(destination.lastPathComponent)")
            }
        }

        return IPodImportReport(
            deviceName: device.name,
            imported: imported,
            alreadyPresent: alreadyPresent,
            skippedUnplayable: skippedUnplayable,
            missingSourceCovers: missingSourceCovers,
            missingDestinationCovers: missingDestinationCovers,
            missingBitrates: missingBitrateFiles.count,
            sourceFiles: files.count,
            warningCount: messages.count,
            messages: Array(messages.prefix(20))
        )
    }

    /// Resolve both sides before writing; a symlink must never escape Music/.
    func safeDestination(for source: URL, sourceRoot: URL, device: IPodDevice) -> URL? {
        guard let root = canonicalURL(sourceRoot), let file = canonicalURL(source) else { return nil }
        guard file.path.hasPrefix(root.path + "/") else { return nil }
        let relative = relativePath(of: file, from: root)
        let music = device.musicURL.standardizedFileURL
        guard let volume = canonicalURL(device.rootURL), let resolvedMusic = canonicalURL(music) else { return nil }
        guard resolvedMusic.path.hasPrefix(volume.path + "/") else { return nil }
        guard let destination = canonicalURL(music.appendingPathComponent(relative)) else { return nil }
        guard destination.path.hasPrefix(resolvedMusic.path + "/") else { return nil }
        return destination
    }

    /// Foundation may leave an intermediate symlink unresolved when the final
    /// file does not exist yet. Resolve every existing prefix before copying.
    private func canonicalURL(_ url: URL) -> URL? {
        var remaining = Array(url.pathComponents.dropFirst())
        var resolved = URL(fileURLWithPath: "/", isDirectory: true)
        var links = 0
        while !remaining.isEmpty {
            let part = remaining.removeFirst()
            if part == "." { continue }
            if part == ".." { resolved.deleteLastPathComponent(); continue }
            resolved.appendPathComponent(part)
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: resolved.path) {
                links += 1
                guard links <= 32 else { return nil }
                let link = URL(fileURLWithPath: target, relativeTo: resolved.deletingLastPathComponent())
                remaining = Array(link.pathComponents.dropFirst()) + remaining
                resolved = URL(fileURLWithPath: "/", isDirectory: true)
            }
        }
        // Do not call standardizedFileURL here: on macOS it may rewrite
        // existing /private/var paths to /var but leave missing tails alone.
        return resolved
    }

    private func deviceAvailable(_ device: IPodDevice) -> Bool {
        guard device.canImport,
              let values = try? device.rootURL.resourceValues(forKeys: [.isVolumeKey, .volumeIsReadOnlyKey, .volumeUUIDStringKey]),
              values.isVolume == true, values.volumeIsReadOnly == false,
              device.volumeIdentifier == nil || values.volumeUUIDString == device.volumeIdentifier else { return false }
        return FileManager.default.isWritableFile(atPath: device.rootURL.path)
    }

    private func copyAtomically(_ source: URL, to destination: URL, device: IPodDevice) throws {
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".musicbridge-\(UUID().uuidString).partial")
        defer {
            // Only our own staging file, and only on the same still-mounted device.
            if deviceAvailable(device) { try? FileManager.default.removeItem(at: staging) }
        }
        guard let resolvedSource = canonicalURL(source) else { throw ImportError.deviceUnavailable }
        try FileManager.default.copyItem(at: resolvedSource, to: staging)
        guard deviceAvailable(device) else { throw ImportError.deviceUnavailable }
        try FileManager.default.moveItem(at: staging, to: destination)
    }

    private enum ImportError: LocalizedError {
        case deviceUnavailable
        var errorDescription: String? { "设备已断开或不可写，已停止复制。" }
    }

    private func inspect(_ url: URL) -> MediaCheckResult {
        guard let ffprobe = findFFProbe() else {
            return MediaCheckResult(playable: false, bitrate: nil, hasEmbeddedCover: false, codec: nil)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobe)
        process.arguments = [
            "-v", "error",
            "-show_entries", "stream=codec_type,codec_name,disposition:format=bit_rate",
            "-of", "json",
            url.path
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8, execute: timeout)
            defer { timeout.cancel() }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return MediaCheckResult(playable: false, bitrate: nil, hasEmbeddedCover: false, codec: nil)
            }
            let output = try JSONDecoder().decode(ProbeOutput.self, from: data)
            let audio = output.streams.first { $0.codecType == "audio" }
            let bitrate = Int(output.format?.bitRate ?? "") ?? audio?.bitRate.flatMap(Int.init)
            let hasCover = output.streams.contains {
                $0.codecType == "video" || $0.disposition?.attachedPic == 1
            }
            return MediaCheckResult(
                playable: audio != nil,
                bitrate: bitrate,
                hasEmbeddedCover: hasCover,
                codec: audio?.codecName
            )
        } catch {
            return MediaCheckResult(playable: false, bitrate: nil, hasEmbeddedCover: false, codec: nil)
        }
    }

    private func findFFProbe() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func enumerateAudioFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            guard
                  url.pathExtension.lowercased() != "",
                  audioExtensions.contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            files.append(url)
        }
        return files
    }

    private func signature(of url: URL) -> FileSignature? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let modificationDate = values.contentModificationDate else { return nil }
        return FileSignature(size: UInt64(size), modificationDate: modificationDate)
    }

    private func relativePath(of url: URL, from root: URL) -> String {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var relative = String(url.path.dropFirst(prefix.count))
        var components = relative.split(separator: "/").map(String.init)
        if components.first == "Apple Music" {
            components.removeFirst()
        }
        relative = components.joined(separator: "/")
        return relative.isEmpty ? url.lastPathComponent : relative
    }

    private func yamlValue(_ contents: String, key: String) -> String? {
        guard let line = contents.split(whereSeparator: \.isNewline).first(where: {
            String($0).trimmingCharacters(in: .whitespaces).hasPrefix("\(key):")
        }) else { return nil }
        let value = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .dropFirst()
            .joined(separator: ":")
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    }

    private func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}

private struct ProbeOutput: Decodable {
    let streams: [ProbeStream]
    let format: ProbeFormat?
}

private struct ProbeStream: Decodable {
    let codecType: String?
    let codecName: String?
    let bitRate: String?
    let disposition: ProbeDisposition?

    enum CodingKeys: String, CodingKey {
        case codecType = "codec_type"
        case codecName = "codec_name"
        case bitRate = "bit_rate"
        case disposition
    }
}

private struct ProbeDisposition: Decodable {
    let attachedPic: Int?

    enum CodingKeys: String, CodingKey {
        case attachedPic = "attached_pic"
    }
}

private struct ProbeFormat: Decodable {
    let bitRate: String?

    enum CodingKeys: String, CodingKey {
        case bitRate = "bit_rate"
    }
}
