import AVFoundation
import Foundation

struct ScanUpdate: Sendable {
    var phase: String
    var completed: Int
    var total: Int
    var currentFileName: String?
}

struct LibraryScanResult: Sendable {
    var tracks: [LocalTrack]
    var skippedPaths: [String]
}

enum LibraryScanner {
    static let audioExtensions: Set<String> = ["aac", "aif", "aiff", "alac", "flac", "m4a", "mp3", "wav"]
    static let excludedFolderNames: Set<String> = ["_serato_", "_serato_backup", "serato studio"]

    static func isExcludedFolder(named name: String) -> Bool {
        excludedFolderNames.contains(name.lowercased())
    }

    static func isSupportedAudioFile(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    static func scan(
        locations: [MusicLocation],
        existingTracks: [LocalTrack],
        progress: @escaping @Sendable (ScanUpdate) async -> Void
    ) async throws -> LibraryScanResult {
        let resolvedLocations = try resolve(locations)
        defer { resolvedLocations.forEach { $0.stopAccessing() } }
        let folders = resolvedLocations.map(\.url)
        await progress(ScanUpdate(phase: "Finding supported audio files", completed: 0, total: 0, currentFileName: nil))
        let fileCollectionTask = Task.detached(priority: .userInitiated) {
            try collectAudioFiles(in: folders)
        }
        let collection = try await withTaskCancellationHandler(operation: {
            try await fileCollectionTask.value
        }, onCancel: {
            fileCollectionTask.cancel()
        })
        let files = collection.files
        let existingByPath = Dictionary(uniqueKeysWithValues: existingTracks.map { ($0.path, $0) })
        let reusableTracks = files.compactMap { file -> LocalTrack? in
            guard let track = existingByPath[file.url.path], track.matches(file) else { return nil }
            return track
        }
        let filesToRead = files.filter { file in
            guard let track = existingByPath[file.url.path] else { return true }
            return !track.matches(file)
        }

        await progress(ScanUpdate(
            phase: filesToRead.isEmpty ? "Library is up to date" : "Reading changed audio metadata",
            completed: reusableTracks.count,
            total: files.count,
            currentFileName: nil
        ))
        let scannedTracks = try await readTracks(
            filesToRead,
            sourceFolders: folders,
            completedBeforeReading: reusableTracks.count,
            total: files.count,
            progress: progress
        )
        let tracksByPath = Dictionary(uniqueKeysWithValues: (reusableTracks + scannedTracks).map { ($0.path, $0) })
        let tracks = files.compactMap { tracksByPath[$0.url.path] }

        await progress(ScanUpdate(phase: "Finishing index", completed: files.count, total: files.count, currentFileName: nil))
        return LibraryScanResult(tracks: tracks, skippedPaths: collection.skippedPaths)
    }

    private static func resolve(_ locations: [MusicLocation]) throws -> [ResolvedLocation] {
        try locations.map { location in
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: location.bookmarkData,
                options: location.usesSecurityScope ? [.withSecurityScope] : [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard !isStale else {
                throw LibraryScannerError.reapproveLocation(location.displayName)
            }
            if location.usesSecurityScope {
                guard url.startAccessingSecurityScopedResource() else {
                    throw LibraryScannerError.reapproveLocation(location.displayName)
                }
            }
            return ResolvedLocation(url: url, usesSecurityScope: location.usesSecurityScope)
        }
    }

    private static func collectAudioFiles(in folders: [URL]) throws -> FileCollection {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey, .fileSizeKey, .contentModificationDateKey]
        var results: [AudioFileDescriptor] = []
        var skippedPaths: [String] = []

        for folder in folders {
            try Task.checkCancellation()
            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, _ in
                    skippedPaths.append(url.path)
                    return true
                }
            ) else {
                skippedPaths.append(folder.path)
                continue
            }

            for case let url as URL in enumerator {
                try Task.checkCancellation()
                let values = try? url.resourceValues(forKeys: keys)
                if values?.isDirectory == true {
                    if isExcludedFolder(named: url.lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard values?.isRegularFile == true, isSupportedAudioFile(url) else { continue }
                results.append(AudioFileDescriptor(
                    url: url,
                    fileSize: values?.fileSize.map(Int64.init),
                    modificationDate: values?.contentModificationDate,
                    modificationTimeNanoseconds: values?.contentModificationDate.map { Int64(($0.timeIntervalSince1970 * 1_000_000_000).rounded()) }
                ))
            }
        }
        return FileCollection(files: results, skippedPaths: skippedPaths)
    }

    private static func readTracks(
        _ files: [AudioFileDescriptor],
        sourceFolders: [URL],
        completedBeforeReading: Int,
        total: Int,
        progress: @escaping @Sendable (ScanUpdate) async -> Void
    ) async throws -> [LocalTrack] {
        guard !files.isEmpty else { return [] }
        let concurrency = min(6, ProcessInfo.processInfo.activeProcessorCount)
        var iterator = files.makeIterator()
        var completed = 0
        var tracks: [LocalTrack] = []
        tracks.reserveCapacity(files.count)

        try await withThrowingTaskGroup(of: LocalTrack?.self) { group in
            for _ in 0..<concurrency {
                guard let file = iterator.next() else { break }
                group.addTask { await readTrack(at: file, sourceFolders: sourceFolders) }
            }

            while let track = try await group.next() {
                try Task.checkCancellation()
                completed += 1
                if let track { tracks.append(track) }
                if completed.isMultiple(of: 100) || completed == files.count {
                    await progress(ScanUpdate(
                        phase: "Reading changed audio metadata",
                        completed: completedBeforeReading + completed,
                        total: total,
                        currentFileName: track.map { URL(fileURLWithPath: $0.path).lastPathComponent }
                    ))
                }
                if let file = iterator.next() {
                    group.addTask { await readTrack(at: file, sourceFolders: sourceFolders) }
                }
            }
        }
        return tracks
    }

    private static func readTrack(at file: AudioFileDescriptor, sourceFolders: [URL]) async -> LocalTrack? {
        let url = file.url
        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        let duration = try? await asset.load(.duration)
        let audioTracks = try? await asset.loadTracks(withMediaType: .audio)
        let dataRate: Float?
        if let audioTrack = audioTracks?.first {
            dataRate = try? await audioTrack.load(.estimatedDataRate)
        } else {
            dataRate = nil
        }
        let title = await metadataString(for: metadata.first(where: { $0.commonKey?.rawValue == "title" }))
            ?? url.deletingPathExtension().lastPathComponent
        let artist = await metadataString(for: metadata.first(where: { $0.commonKey?.rawValue == "artist" })) ?? ""
        let sourceFolder = sourceFolders.first(where: { url.path.hasPrefix($0.path) })?.lastPathComponent ?? "Music"

        return LocalTrack(
            path: url.path,
            artist: artist,
            title: title,
            fileType: url.pathExtension.uppercased(),
            duration: duration?.seconds.isFinite == true ? duration?.seconds : nil,
            bitrateKbps: dataRate.map { Int(($0 / 1_000).rounded()) },
            sourceFolder: sourceFolder,
            fileSize: file.fileSize,
            modificationDate: file.modificationDate,
            modificationTimeNanoseconds: file.modificationTimeNanoseconds
        )
    }

    private static func metadataString(for item: AVMetadataItem?) async -> String? {
        guard let item else { return nil }
        return try? await item.load(.stringValue)
    }
}

private struct FileCollection: Sendable {
    var files: [AudioFileDescriptor]
    var skippedPaths: [String]
}

private struct AudioFileDescriptor: Sendable {
    let url: URL
    let fileSize: Int64?
    let modificationDate: Date?
    let modificationTimeNanoseconds: Int64?
}

private extension LocalTrack {
    func matches(_ file: AudioFileDescriptor) -> Bool {
        guard let fileSize, let storedFingerprint = modificationTimeNanoseconds, let currentFingerprint = file.modificationTimeNanoseconds else { return false }
        return self.fileSize == fileSize
            && storedFingerprint == currentFingerprint
    }
}

private struct ResolvedLocation {
    let url: URL
    let usesSecurityScope: Bool

    func stopAccessing() {
        if usesSecurityScope {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

private enum LibraryScannerError: LocalizedError {
    case reapproveLocation(String)

    var errorDescription: String? {
        switch self {
        case let .reapproveLocation(name): "Setlist needs you to approve \(name) again before scanning it."
        }
    }
}
