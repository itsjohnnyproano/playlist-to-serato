# Setlist

A local-first native macOS app that helps DJs turn client requests into carefully chosen Serato crates.

## Current slice

The current build supports persistent events, pasted-text requests, and an explicit, read-only local-music scan. It does not modify music files, Serato data, or crates.

Folder access is sandboxed and limited to folders the user selects. Serato data folders are excluded from the scan.

## Open and run

Open `Setlist.xcodeproj` in Xcode 26, select the Setlist scheme and My Mac, then run it. The minimum deployment target is macOS 14.

The older `Package.swift` remains for command-line unit tests. Run `swift test` from the repository root.
