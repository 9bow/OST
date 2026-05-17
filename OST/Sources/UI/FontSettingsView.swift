import SwiftUI

struct FontSettingsView: View {
    @ObservedObject var settings: UserSettings
    var onResetOverlay: (() -> Void)?
    var onResetOverlay2: (() -> Void)?
    var onToggleOverlayLock: ((Bool) -> Void)?
    var onToggleOverlay2Lock: ((Bool) -> Void)?
    var onSubtitleSettingsChanged: (() -> Void)?
    var onDisplayModeChanged: (() -> Void)?

    var body: some View {
        Form {
            Section("Original Text (Speech)") {
                HStack {
                    Text("Size")
                    Slider(value: fontSizeBinding, in: 12...72, step: 1)
                        .accessibilityLabel("Font size")
                        .accessibilityValue("\(Int(settings.safeFontSize)) points")
                    Text("\(Int(settings.safeFontSize))pt")
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
                    Slider(value: translatedFontSizeBinding, in: 12...72, step: 1)
                        .accessibilityLabel("Translated font size")
                        .accessibilityValue("\(Int(settings.safeTranslatedFontSize)) points")
                    Text("\(Int(settings.safeTranslatedFontSize))pt")
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
                    Slider(value: backgroundOpacityBinding, in: 0...1, step: 0.05)
                        .accessibilityLabel("Background opacity")
                        .accessibilityValue("\(Int(settings.safeBackgroundOpacity * 100)) percent")
                        .accessibilityHint("Drag to change background transparency")
                    Text("\(Int(settings.safeBackgroundOpacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            Section("Subtitle Display") {
                HStack {
                    Text("Max Lines")
                    Slider(value: maxSubtitleLinesBinding, in: 1...10, step: 1)
                        .accessibilityLabel("Maximum subtitle lines")
                        .accessibilityValue("\(Int(settings.safeMaxSubtitleLines)) lines")
                    Text("\(Int(settings.safeMaxSubtitleLines))")
                        .monospacedDigit()
                        .frame(width: 24, alignment: .trailing)
                }

                HStack {
                    Text("Expiry")
                    Slider(value: subtitleExpiryBinding, in: 3...60, step: 1)
                        .accessibilityLabel("Subtitle expiry time")
                        .accessibilityValue("\(Int(settings.safeSubtitleExpirySeconds)) seconds")
                    Text("\(Int(settings.safeSubtitleExpirySeconds))s")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }

                HStack {
                    Text("Speech Pause")
                    Slider(value: speechPauseBinding, in: 0.5...5, step: 0.5)
                        .accessibilityLabel("Speech pause detection time")
                        .accessibilityValue(String(format: "%.1f seconds", settings.safeSpeechPauseSeconds))
                    Text(String(format: "%.1fs", settings.safeSpeechPauseSeconds))
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                Text("Pause duration before finalizing speech for translation")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if settings.overlayDisplayMode == "combined" {
                Section("Visibility") {
                    Toggle("Show Original Text", isOn: showOriginalTextBinding)
                        .accessibilityLabel("Show original text toggle")
                        .accessibilityHint("Toggle display of recognized speech text")

                    Toggle("Show Translation", isOn: showTranslationBinding)
                        .accessibilityLabel("Show translation toggle")
                        .accessibilityHint("Toggle display of translated text")
                }
            }

            Section("Display Mode") {
                Picker("Mode", selection: Binding(
                    get: { settings.overlayDisplayMode },
                    set: { newValue in
                        settings.overlayDisplayMode = newValue
                        onDisplayModeChanged?()
                    }
                )) {
                    Text("Combined").tag("combined")
                    Text("Split (Transcription + Translation)").tag("split")
                }
                .pickerStyle(.menu)

                Text(settings.overlayDisplayMode == "split"
                    ? "Two separate windows: transcription and translation."
                    : "Single window showing both transcription and translation.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Reset All Overlay Windows") {
                    onResetOverlay?()
                }
                .accessibilityLabel("Reset all overlay windows to default position and size")
            }

            Section(settings.overlayDisplayMode == "split" ? "Transcription Window" : "Overlay Window") {
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

                Button(settings.overlayDisplayMode == "split" ? "Reset Both Windows" : "Reset Position & Size") {
                    onResetOverlay?()
                }
                .accessibilityLabel("Reset overlay window to default position and size")
            }

            if settings.overlayDisplayMode == "split" {
                Section("Translation Window") {
                    Toggle("Lock Overlay", isOn: Binding(
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

                    Button("Reset Both Windows") {
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
        Group {
            if settings.overlayDisplayMode == "split" {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transcription")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Hello, this is sample speech.")
                            .font(.system(size: settings.safeFontSize))
                            .foregroundColor(settings.fontColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(settings.backgroundColor.opacity(settings.safeBackgroundOpacity))
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Translation")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("안녕하세요, 샘플 음성입니다.")
                            .font(.system(size: settings.safeTranslatedFontSize))
                            .foregroundColor(settings.translatedFontColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(settings.backgroundColor.opacity(settings.safeBackgroundOpacity))
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if settings.showOriginalText {
                        Text("Hello, this is sample speech.")
                            .font(.system(size: settings.safeFontSize))
                            .foregroundColor(settings.fontColor)
                    }
                    if settings.showTranslation {
                        Text("안녕하세요, 샘플 음성입니다.")
                            .font(.system(size: settings.safeTranslatedFontSize))
                            .foregroundColor(settings.translatedFontColor)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(settings.backgroundColor.opacity(settings.safeBackgroundOpacity))
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live preview of subtitle appearance")
    }

    private var showOriginalTextBinding: Binding<Bool> {
        Binding(
            get: { settings.showOriginalText },
            set: { newValue in
                settings.showOriginalText = newValue
                if !settings.showOriginalText && !settings.showTranslation {
                    settings.showTranslation = true
                }
            }
        )
    }

    private var showTranslationBinding: Binding<Bool> {
        Binding(
            get: { settings.showTranslation },
            set: { newValue in
                settings.showTranslation = newValue
                if !settings.showOriginalText && !settings.showTranslation {
                    settings.showOriginalText = true
                }
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { settings.safeFontSize },
            set: { settings.fontSize = $0 }
        )
    }

    private var translatedFontSizeBinding: Binding<Double> {
        Binding(
            get: { settings.safeTranslatedFontSize },
            set: { settings.translatedFontSize = $0 }
        )
    }

    private var backgroundOpacityBinding: Binding<Double> {
        Binding(
            get: { settings.safeBackgroundOpacity },
            set: { settings.backgroundOpacity = $0 }
        )
    }

    private var maxSubtitleLinesBinding: Binding<Double> {
        Binding(
            get: { settings.safeMaxSubtitleLines },
            set: { newValue in
                settings.maxSubtitleLines = newValue
                onSubtitleSettingsChanged?()
            }
        )
    }

    private var subtitleExpiryBinding: Binding<Double> {
        Binding(
            get: { settings.safeSubtitleExpirySeconds },
            set: { newValue in
                settings.subtitleExpirySeconds = newValue
                onSubtitleSettingsChanged?()
            }
        )
    }

    private var speechPauseBinding: Binding<Double> {
        Binding(
            get: { settings.safeSpeechPauseSeconds },
            set: { newValue in
                settings.speechPauseSeconds = newValue
                onSubtitleSettingsChanged?()
            }
        )
    }
}
