import SwiftUI

struct FontSettingsView: View {
    @ObservedObject var settings: UserSettings

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
