import AppKit
import SwiftUI

enum AccessibilityManager {

    // MARK: - VoiceOver Announcements

    /// Posts a VoiceOver announcement with the given message.
    static func announce(_ message: String) {
        let userInfo: [NSAccessibility.NotificationUserInfoKey: Any] = [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ]
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: userInfo
        )
    }

    /// Posts a layout-changed notification to inform VoiceOver of UI updates.
    static func postLayoutChanged(for element: AnyObject = NSApp) {
        NSAccessibility.post(element: element, notification: .layoutChanged, userInfo: nil)
    }

    // MARK: - High Contrast Detection

    /// Returns true when the system high-contrast accessibility setting is enabled.
    static var isHighContrastEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    /// Returns the recommended minimum font size respecting accessibility preferences.
    static func effectiveFontSize(base: CGFloat) -> CGFloat {
        isHighContrastEnabled ? max(base, 18) : base
    }

    // MARK: - Focus Management

    /// Moves VoiceOver focus to the given NSView element.
    static func moveFocus(to element: NSView) {
        NSAccessibility.post(element: element, notification: .focusedUIElementChanged, userInfo: nil)
    }
}

// MARK: - SwiftUI View Modifier Helpers

extension View {
    /// Adds a combined accessibility element with label and hint.
    func accessibilityDescribe(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityElement(children: .combine)
    }
}
