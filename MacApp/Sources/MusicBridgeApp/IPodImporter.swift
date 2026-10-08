import AppKit

struct FileSignature: Sendable, Equatable {
    let size: UInt64
    let modificationDate: Date
}

struct IPodDevice: Sendable {
    let name: String
    let rootURL: URL
    let musicURL: URL
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
            guard isDirectory(musicURL) else { return nil }
            guard FileManager.default.isWritableFile(atPath: musicURL.path) else { return nil }

            let name = (try? rootURL.resourceValues(forKeys: [.volumeNameKey]).volumeName)
                ?? rootURL.lastPathComponent
            return IPodDevice(name: name, rootURL: rootURL, musicURL: musicURL)
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

            let relative = relativePath(of: item.url, from: item.root)
            let destination = device.musicURL.appendingPathComponent(relative)
            do {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: destination.path) {
                    let sameSize = signature(of: destination)?.size == signature(of: item.url)?.size
                    if sameSize {
                        alreadyPresent += 1
                    } else {
                        try fileManager.removeItem(at: destination)
                        try fileManager.copyItem(at: item.url, to: destination)
                        imported += 1
                    }
                } else {
                    try fileManager.copyItem(at: item.url, to: destination)
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
            let sourceCover = item.url.deletingLastPathComponent().appendingPathComponent("cover.jpg")
            guard fileManager.fileExists(atPath: sourceCover.path) else { continue }
            guard copiedCoverDirectories.insert(sourceCover.deletingLastPathComponent().path).inserted else { continue }
            let relativeDirectory = relativePath(of: sourceCover.deletingLastPathComponent(), from: item.root)
            let destinationCover = device.musicURL
                .appendingPathComponent(relativeDirectory, isDirectory: true)
                .appendingPathComponent("cover.jpg")
            do {
                try fileManager.createDirectory(
                    at: destinationCover.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if !fileManager.fileExists(atPath: destinationCover.path) {
                    try fileManager.copyItem(at: sourceCover, to: destinationCover)
                }
            } catch {
                messages.append("封面复制失败：\(sourceCover.lastPathComponent)")
            }
        }

        for destination in copiedDestinations {
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
            messages: Array(messages.prefix(20))
        )
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
        process.standardError = Pipe()
        do {
            try process.run()
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
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  url.pathExtension.lowercased() != "",
                  audioExtensions.contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return url
        }
    }

    private func signature(of url: URL) -> FileSignature? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let modificationDate = values.contentModificationDate else { return nil }
        return FileSignature(size: UInt64(size), modificationDate: modificationDate)
    }

    private func relativePath(of url: URL, from root: URL) -> String {
        let prefix = root.standardizedFileURL.path.hasSuffix("/")
            ? root.standardizedFileURL.path
            : root.standardizedFileURL.path + "/"
        var relative = String(url.standardizedFileURL.path.dropFirst(prefix.count))
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
