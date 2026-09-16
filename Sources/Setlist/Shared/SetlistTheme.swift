import SwiftUI

enum SetlistTheme {
    static let accent = Color(red: 0.15, green: 0.43, blue: 0.93)
    static let previewActive = Color(red: 0.91, green: 0.25, blue: 0.30)
    static let contentPadding: CGFloat = 48
    static let contentWidth: CGFloat = 920
}

extension Color {
    static let setlistBlue = SetlistTheme.accent
    static let setlistPreviewActive = SetlistTheme.previewActive
}
