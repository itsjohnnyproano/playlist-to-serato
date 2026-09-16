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

        var tracks: [LocalTrack] = []
        tracks.reserveCapacity(files.count)
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            if index == 0 || index.isMultiple(of: 10) || index == files.count - 1 {
                await progress(ScanUpdate(
                    phase: "Reading audio metadata",
                    completed: index,
                    total: files.count,
                    currentFileName: file.lastPathComponent
                ))
            }
            if let track = await readTrack(at: file, sourceFolders: folders) {
                tracks.append(track)
            }
        }

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
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey]
        var results: [URL] = []
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
                results.append(url)
            }
        }
        return FileCollection(files: results, skippedPaths: skippedPaths)
    }

    private static func readTrack(at url: URL, sourceFolders: [URL]) async -> LocalTrack? {
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
            sourceFolder: sourceFolder
        )
    }

    private static func metadataString(for item: AVMetadataItem?) async -> String? {
        guard let item else { return nil }
        return try? await item.load(.stringValue)
    }
}

private struct FileCollection: Sendable {
    var files: [URL]
    var skippedPaths: [String]
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
