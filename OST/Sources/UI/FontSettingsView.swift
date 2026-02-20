import SwiftUI

struct FontSettingsView: View {
    @ObservedObject var settings: UserSettings
    var onResetOverlay: (() -> Void)?
    var onResetOverlay2: (() -> Void)?
    var onToggleOverlayLock: ((Bool) -> Void)?
    var onToggleOverlay2Lock: ((Bool) -> Void)?

    var body: some View {
        Form {
            Section("Original Text (Speech)") {
                HStack {
                    Text("Size")
                    Slider(value: $settings.fontSize, in: 12...72, step: 1)
                        .accessibilityLabel("Font size")
                        .accessibilityValue("\(Int(settings.fontSize)) points")
                    Text("\(Int(settings.fontSize))pt")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }

                ColorPicker("Color", selection: Binding(
                    get: { settings.fontColor },
                    set: { settings.fontColor = $0 }
                ))
            }

            Section("Translated Text") {
                HStack {
                    Text("Size")
                    Slider(value: $settings.translatedFontSize, in: 12...72, step: 1)
                        .accessibilityLabel("Translated font size")
                        .accessibilityValue("\(Int(settings.translatedFontSize)) points")
                    Text("\(Int(settings.translatedFontSize))pt")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }

                ColorPicker("Color", selection: Binding(
                    get: { settings.translatedFontColor },
                    set: { settings.translatedFontColor = $0 }
                ))
            }

            Section("Background") {
                ColorPicker("Background Color", selection: Binding(
                    get: { settings.backgroundColor },
                    set: { settings.backgroundColor = $0 }
                ))
                .accessibilityLabel("Background color picker")
                .accessibilityHint("Choose the subtitle background color")

                HStack {
                    Text("Opacity")
                    Slider(value: $settings.backgroundOpacity, in: 0...1, step: 0.05)
                        .accessibilityLabel("Background opacity")
                        .accessibilityValue("\(Int(settings.backgroundOpacity * 100)) percent")
                        .accessibilityHint("Drag to change background transparency")
                    Text("\(Int(settings.backgroundOpacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            Section("Subtitle Display") {
                HStack {
                    Text("Max Lines")
                    Slider(value: $settings.maxSubtitleLines, in: 1...10, step: 1)
                        .accessibilityLabel("Maximum subtitle lines")
                        .accessibilityValue("\(Int(settings.maxSubtitleLines)) lines")
                    Text("\(Int(settings.maxSubtitleLines))")
                        .monospacedDigit()
                        .frame(width: 24, alignment: .trailing)
                }

                HStack {
                    Text("Expiry")
                    Slider(value: $settings.subtitleExpirySeconds, in: 3...60, step: 1)
                        .accessibilityLabel("Subtitle expiry time")
                        .accessibilityValue("\(Int(settings.subtitleExpirySeconds)) seconds")
                    Text("\(Int(settings.subtitleExpirySeconds))s")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }

                HStack {
                    Text("Speech Pause")
                    Slider(value: $settings.speechPauseSeconds, in: 0.5...5, step: 0.5)
                        .accessibilityLabel("Speech pause detection time")
                        .accessibilityValue(String(format: "%.1f seconds", settings.speechPauseSeconds))
                    Text(String(format: "%.1fs", settings.speechPauseSeconds))
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                Text("Pause duration before finalizing speech for translation")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Visibility") {
                Toggle("Show Original Text", isOn: $settings.showOriginalText)
                    .accessibilityLabel("Show original text toggle")
                    .accessibilityHint("Toggle display of recognized speech text")

                Toggle("Show Translation", isOn: $settings.showTranslation)
                    .accessibilityLabel("Show translation toggle")
                    .accessibilityHint("Toggle display of translated text")
            }

            Section("Display Mode") {
                Picker("Mode", selection: $settings.overlayDisplayMode) {
                    Text("Combined").tag("combined")
                    Text("Split (Recognition + Translation)").tag("split")
                }
                .pickerStyle(.menu)

                Text(settings.overlayDisplayMode == "split"
                    ? "Two separate windows: recognition text and translated text."
                    : "Single window showing both recognition and translation.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Reset All Overlay Windows") {
                    onResetOverlay?()
                    if settings.overlayDisplayMode == "split" {
                        onResetOverlay2?()
                    }
                }
                .accessibilityLabel("Reset all overlay windows to default position and size")
            }

            Section("Overlay Window") {
                Toggle("Lock Overlay", isOn: Binding(
                    get: { settings.overlayLocked },
                    set: { newValue in
                        settings.overlayLocked = newValue
                        onToggleOverlayLock?(newValue)
                    }
                ))
                .accessibilityLabel("Lock overlay position")
                Text(settings.overlayLocked
                    ? "Locked: clicks pass through to windows below."
                    : "Unlocked: drag to move or resize the overlay.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Reset Overlay Position & Size") {
                    onResetOverlay?()
                }
                .accessibilityLabel("Reset overlay window to default position and size")
            }

            if settings.overlayDisplayMode == "split" {
                Section("Translation Window") {
                    Toggle("Lock Translation Window", isOn: Binding(
                        get: { settings.overlay2Locked },
                        set: { newValue in
                            settings.overlay2Locked = newValue
                            onToggleOverlay2Lock?(newValue)
                        }
                    ))
                    .accessibilityLabel("Lock translation window position")
                    Text(settings.overlay2Locked
                        ? "Locked: clicks pass through to windows below."
                        : "Unlocked: drag to move or resize the translation window.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Reset Translation Window Position & Size") {
                        onResetOverlay2?()
                    }
                    .accessibilityLabel("Reset translation window to default position and size")
                }
            }

            Section("Live Preview") {
                previewSection
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if settings.showOriginalText {
                Text("Hello, this is sample speech.")
                    .font(.system(size: settings.fontSize))
                    .foregroundColor(settings.fontColor)
                    .accessibilityLabel("Preview original text sample")
            }
            if settings.showTranslation {
                Text("안녕하세요, 샘플 음성입니다.")
                    .font(.system(size: settings.translatedFontSize))
                    .foregroundColor(settings.translatedFontColor)
                    .accessibilityLabel("Preview translated text sample")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(settings.backgroundColor.opacity(settings.backgroundOpacity))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live preview of subtitle appearance")
    }
}
