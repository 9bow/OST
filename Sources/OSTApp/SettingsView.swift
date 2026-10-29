import AppKit
import OSTCore
import SwiftUI

private struct PresentedNotice: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

enum SettingsTab: Hashable {
    case general
    case models
    case appearance
    case overlay
    case privacy
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var presentedNotice: PresentedNotice?
    @State private var pendingInstall: ModelDescriptor?
    @State private var pendingDelete: ModelDescriptor?

    var body: some View {
        TabView(selection: $model.selectedSettingsTab) {
            generalTab
                .tabItem { Label(t("General"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            modelsTab
                .tabItem { Label(t("Models"), systemImage: "cpu") }
                .tag(SettingsTab.models)
            appearanceTab
                .tabItem { Label(t("Appearance"), systemImage: "paintpalette") }
                .tag(SettingsTab.appearance)
            overlayTab
                .tabItem { Label(t("Overlay"), systemImage: "rectangle.on.rectangle") }
                .tag(SettingsTab.overlay)
            privacyTab
                .tabItem { Label(t("Privacy"), systemImage: "hand.raised") }
                .tag(SettingsTab.privacy)
        }
        .frame(width: 660, height: 560)
        .scenePadding()
        .sheet(item: $presentedNotice) { notice in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(notice.title).font(.title2).bold()
                    Spacer()
                    Button(t("Close")) { presentedNotice = nil }
                        .keyboardShortcut(.cancelAction)
                }
                ScrollView {
                    Text(notice.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .frame(width: 720, height: 520)
        }
        .alert(
            t("Download Model"),
            isPresented: installConfirmationPresented,
            presenting: pendingInstall
        ) { descriptor in
            Button(t("Agree to License and Download")) {
                model.modelDownloader.install(descriptor)
                pendingInstall = nil
            }
            Button(t("Cancel"), role: .cancel) { pendingInstall = nil }
        } message: { descriptor in
            Text(installConfirmationMessage(for: descriptor))
        }
        .alert(
            t("Delete Downloaded Model"),
            isPresented: deleteConfirmationPresented,
            presenting: pendingDelete
        ) { descriptor in
            Button(t("Delete Downloaded Model"), role: .destructive) {
                model.modelDownloader.delete(descriptor)
                pendingDelete = nil
            }
            Button(t("Cancel"), role: .cancel) { pendingDelete = nil }
        } message: { descriptor in
            Text("\(descriptor.id)\n\(t("The model can be downloaded again later."))")
        }
    }

    private var generalTab: some View {
        Form {
            Picker(t("App language"), selection: appDisplayLanguageBinding) {
                ForEach(AppDisplayLanguage.allCases, id: \.self) { language in
                    Text(appLanguageName(language)).tag(language)
                }
            }
            Text(t("Changes to the app language are applied immediately."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(t("Input language"), selection: sourceModeBinding) {
                Text(t("Automatic detection (MLX ASR)"))
                    .tag(SourceLanguageMode.automatic)
                    .disabled(model.preferences.transcriptionProvider != .qwen3ASR)
                ForEach(SupportedLanguage.productPickerCases, id: \.self) { productLanguage in
                    let language = productLanguage.applyingChinesePreference(
                        model.preferences.chineseScriptPreference
                    )
                    Text(AppCopy.productLanguageName(productLanguage, displayLanguage: model.preferences.appDisplayLanguage))
                        .tag(SourceLanguageMode.fixed(language))
                        .disabled(
                            model.preferences.transcriptionProvider == .appleSpeech
                                && !model.appleSpeechSupportedLanguages.contains(language)
                        )
                }
            }
            Picker(t("Target language"), selection: targetBinding) {
                ForEach(SupportedLanguage.productPickerCases, id: \.self) { productLanguage in
                    let language = productLanguage.applyingChinesePreference(
                        model.preferences.chineseScriptPreference
                    )
                    Text(AppCopy.productLanguageName(productLanguage, displayLanguage: model.preferences.appDisplayLanguage)).tag(language)
                }
            }
            Picker(t("Chinese script"), selection: chineseBinding) {
                Text(t("Simplified")).tag(ChineseScriptPreference.simplified)
                Text(t("Traditional")).tag(ChineseScriptPreference.traditional)
            }
            Section(t("Endpoint detection (EPD)")) {
                LabeledContent(t("Silence interval")) {
                    HStack {
                        Slider(value: endpointSilenceBinding, in: 0.4...2, step: 0.1)
                            .frame(width: 220)
                        Text(String(format: t("%.1f sec"), model.preferences.endpointSilenceSeconds))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Text(t("A pause stabilizes the current segment for translation. A short pause does not force a new visible line. Restart capture after changing this value."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var modelsTab: some View {
        Form {
            Picker(t("Transcription provider"), selection: transcriptionProviderBinding) {
                Text("Apple Speech").tag(ProviderID.appleSpeech)
                Text("Qwen3 ASR (MLX)").tag(ProviderID.qwen3ASR)
            }
            Picker(t("Translation provider"), selection: translationProviderBinding) {
                Text("Apple Translation").tag(ProviderID.appleTranslation)
                Text("Qwen3 Translation (\(t("Experimental")))").tag(ProviderID.qwen3Translation)
            }
            Picker(t("MLX ASR model"), selection: selectedASRModelBinding) {
                ForEach(model.modelCatalog.models.filter { $0.task == .transcription }) { descriptor in
                    Text(descriptor.quantization).tag(descriptor.id)
                }
            }
            Picker(t("MLX translation model"), selection: selectedTranslationModelBinding) {
                ForEach(model.modelCatalog.models.filter { $0.task == .translation }) { descriptor in
                    Text(descriptor.quantization + (descriptor.estimatedPeakBytes > 2_000_000_000 ? " · \(t("High memory"))" : ""))
                        .tag(descriptor.id)
                }
            }
            Text(t("Provider and model changes apply when the next capture starts."))
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.preferences.translationProvider == .qwen3Translation {
                Section(t("MLX translation prompt")) {
                    TextEditor(text: mlxTranslationPromptBinding)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 110)
                        .accessibilityLabel("MLX 번역 프롬프트")
                    Text(t("{source_language} and {target_language} are replaced with the selected language names. Leave this empty to use the default prompt. Changes apply to the next translation."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("\(model.preferences.mlxTranslationPrompt.count)/4,000")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(t("Restore Default Prompt")) {
                            model.preferences.mlxTranslationPrompt = MLXPromptDefaults.translation
                        }
                    }
                }
            }

            Section(t("Available models")) {
                ForEach(model.modelCatalog.models) { descriptor in
                    modelRow(descriptor)
                }
            }
            Section(t("Copyright and notices")) {
                Button(t("View runtime and model third-party notices")) {
                    presentNotice(
                        title: "OST Third-Party Notices",
                        resource: ThirdPartyNotices.runtimeResource
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func modelRow(_ descriptor: ModelDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.id).font(.headline)
                    Text("\(descriptor.quantization) · \(descriptor.license.name) · \(bytes(descriptor.downloadBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(t("Estimated peak memory")) \(bytes(descriptor.estimatedPeakBytes)) · macOS 26+ Apple Silicon")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(t("Performance on base M1 has not been verified."))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if model.modelDownloader.isInstalled(descriptor) {
                    VStack(alignment: .trailing, spacing: 6) {
                        Button(t("Show in Finder")) { model.revealModel(descriptor) }
                        Button(t("Delete Downloaded Model"), role: .destructive) {
                            pendingDelete = descriptor
                        }
                    }
                } else if let status = model.modelDownloader.statusByModelID[descriptor.id],
                          ![.completed, .cancelled, .failed].contains(status.phase) {
                    Button(t("Cancel")) { model.modelDownloader.cancel(descriptor) }
                } else if model.modelDownloader.statusByModelID[descriptor.id]?.phase == .cancelled {
                    Button(t("Resume")) { model.modelDownloader.resume(descriptor) }
                } else {
                    Button(t("Download")) { pendingInstall = descriptor }
                }
            }
            HStack(spacing: 12) {
                Button(t("View license")) {
                    presentNotice(
                        title: "\(descriptor.id) — \(descriptor.license.name)",
                        resource: descriptor.license.noticeResource
                    )
                }
                .buttonStyle(.link)
                if let freeBytes = modelDiskFreeBytes {
                    Text("\(t("Available disk space")) \(bytes(freeBytes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(t("Disk space is checked when the signed app runs."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let status = model.modelDownloader.statusByModelID[descriptor.id] {
                ProgressView(
                    value: Double(status.completedBytes),
                    total: Double(max(status.totalBytes, 1))
                )
                Text(status.phase.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let error = model.modelDownloader.errorByModelID[descriptor.id] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var appearanceTab: some View {
        Form {
            Section(t("Source transcript")) {
                Text(t("Applies to confirmed transcript history and the two-line current transcription preview below it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(t("Text size")) {
                    HStack {
                        Slider(value: sourceFontSizeBinding, in: 12...72, step: 1)
                        Text("\(Int(model.preferences.sourceFontSize))pt").monospacedDigit()
                    }
                }
                ColorPicker(t("Text color"), selection: sourceColorBinding, supportsOpacity: true)
                stylePreview(
                    text: t("Transcription results appear here."),
                    fontSize: model.preferences.sourceFontSize,
                    weight: .regular,
                    foregroundColor: model.preferences.sourceColor
                )
            }
            Section(t("Confirmed translation")) {
                Text(t("Applies to translations added to history after a segment is confirmed."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(t("Text size")) {
                    HStack {
                        Slider(value: translationFontSizeBinding, in: 12...72, step: 1)
                        Text("\(Int(model.preferences.translationFontSize))pt").monospacedDigit()
                    }
                }
                ColorPicker(t("Text color"), selection: translationColorBinding, supportsOpacity: true)
                stylePreview(
                    text: t("Confirmed translation results appear here."),
                    fontSize: model.preferences.translationFontSize,
                    weight: .semibold,
                    foregroundColor: model.preferences.translationColor
                )
            }
            Section(t("Current translation preview")) {
                Text(t("Shows the latest unconfirmed translation in two reserved lines below confirmed history. New text replaces the previous preview without hiding confirmed results."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(t("Text size")) {
                    HStack {
                        Slider(value: previewFontSizeBinding, in: 12...72, step: 1)
                        Text("\(Int(model.preferences.previewFontSize))pt").monospacedDigit()
                    }
                }
                ColorPicker(t("Text color"), selection: previewColorBinding, supportsOpacity: true)
                stylePreview(
                    text: t("The current translation preview appears here."),
                    fontSize: model.preferences.previewFontSize,
                    weight: .semibold,
                    foregroundColor: model.preferences.previewColor
                )
            }
            Section(t("Background")) {
                ColorPicker(t("Background color"), selection: backgroundColorBinding, supportsOpacity: false)
                LabeledContent(t("Opacity")) {
                    Slider(value: backgroundOpacityBinding, in: 0...1, step: 0.05)
                }
                if hasLowContrast {
                    Label(t("One or more text colors have low contrast against the background."), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var overlayTab: some View {
        Form {
            Section(t("Layout")) {
                Picker(t("Displayed subtitles"), selection: subtitleDisplayModeBinding) {
                    Text(t("Transcript and translation")).tag(SubtitleDisplayMode.both)
                    Text(t("Transcript only")).tag(SubtitleDisplayMode.sourceOnly)
                    Text(t("Translation only")).tag(SubtitleDisplayMode.translationOnly)
                }
                Picker(t("Window arrangement"), selection: overlayLayoutBinding) {
                    Text(t("Combined window")).tag(OverlayLayout.combined)
                    Text(t("Separate transcript and translation")).tag(OverlayLayout.split)
                }
                Picker(t("Text alignment"), selection: subtitleAlignmentBinding) {
                    Text(t("Left")).tag(SubtitleAlignment.leading)
                    Text(t("Center")).tag(SubtitleAlignment.center)
                    Text(t("Right")).tag(SubtitleAlignment.trailing)
                }
                LabeledContent(t("Confirmed lines per area")) {
                    Stepper(value: overlayLineCountBinding, in: 2...10) {
                        Text("\(model.preferences.overlayLineCount) \(t("lines"))")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                Text(t("Choose 2–10 confirmed lines for each transcript and translation area. Each area also reserves two preview lines, so the combined window can show up to 20 confirmed lines plus 4 preview lines."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(t("Window controls")) {
                Toggle(t("Lock window and pass clicks through"), isOn: overlayLockedBinding)
                Text(t("Unlock the overlay to resize it from an edge or drag its background to move it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(t("Reset overlay position and size")) { model.resetOverlayFrames() }
            }
            Section(t("Overlay window preview")) {
                Text(t("This example follows the selected window arrangement, confirmed line count, alignment, text styles, background color, and opacity."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                OverlaySettingsPreview(preferences: model.preferences)
            }
        }
        .formStyle(.grouped)
    }

    private var privacyTab: some View {
        Form {
            LabeledContent(t("Permission")) { Text(permissionStatus) }
            Button(t("Open System Audio Permission Settings")) { model.openAudioPrivacySettings() }
            Section(t("Session files")) {
                Toggle(t("Save each session to text files"), isOn: sessionLoggingEnabledBinding)
                Text(t("A session starts when capture starts and ends when capture stops. Confirmed transcripts and translations are saved as separate text files. This setting is off by default."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(model.preferences.sessionLogDirectoryPath ?? t("No folder selected"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(t("Choose Folder…")) { model.chooseSessionLogDirectory() }
                    if model.preferences.sessionLogDirectoryPath != nil {
                        Button(t("Show in Finder")) { model.revealSessionLogDirectory() }
                    }
                }
                if let error = model.sessionLoggingError {
                    Text(t(error)).font(.caption).foregroundStyle(.red)
                }
            }
            Section(t("Data stays on this Mac")) {
                Text(t("OST processes audio, transcripts, and translations on this Mac. The app has no feature that uploads or sends your audio, transcript, translation, settings, or saved session files outside your computer."))
                Text(t("Internet access is used only when you choose to download a model. OST receives model files and does not send your content."))
                Text(t("When Apple Translation is used, macOS may send Apple non-content technical information such as the app identifier and selected language pair. Your audio, transcript, and translation text are not included."))
            }
        }
        .formStyle(.grouped)
    }

    private var permissionStatus: String {
        switch model.captureState {
        case .running: t("Allowed")
        case .failed(.permissionDenied), .failed(.permissionRevoked): t("Denied or revoked")
        default: t("Checked when capture starts")
        }
    }

    private var hasLowContrast: Bool {
        model.preferences.sourceColor.contrastRatio(against: model.preferences.backgroundColor) < 4.5
            || model.preferences.translationColor.contrastRatio(against: model.preferences.backgroundColor) < 4.5
            || model.preferences.previewColor.contrastRatio(against: model.preferences.backgroundColor) < 4.5
    }

    private func stylePreview(
        text: String,
        fontSize: Double,
        weight: Font.Weight,
        foregroundColor: RGBAColor
    ) -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: weight))
            .foregroundStyle(swiftUIColor(foregroundColor))
            .multilineTextAlignment(previewTextAlignment)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: previewFrameAlignment)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(swiftUIColor(
                model.preferences.backgroundColor,
                opacity: model.preferences.backgroundOpacity
            ))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .accessibilityLabel("\(t("Preview")): \(text)")
    }

    private var previewFrameAlignment: Alignment {
        switch model.preferences.subtitleAlignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private var previewTextAlignment: TextAlignment {
        switch model.preferences.subtitleAlignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func swiftUIColor(_ value: RGBAColor, opacity: Double = 1) -> Color {
        Color(
            red: value.red,
            green: value.green,
            blue: value.blue,
            opacity: value.alpha * opacity
        )
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private var modelDiskFreeBytes: Int64? {
        guard let container = ModelStoreLayout.containerURL(),
              let attributes = try? FileManager.default.attributesOfFileSystem(
                forPath: container.path
              ),
              let value = attributes[.systemFreeSize] as? NSNumber else {
            return nil
        }
        return value.int64Value
    }

    private func presentNotice(title: String, resource: String) {
        let text: String
        do {
            text = try ThirdPartyNotices.text(at: resource)
        } catch {
            text = t("The notice could not be loaded.")
        }
        presentedNotice = PresentedNotice(title: title, text: text)
    }

    private var installConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingInstall != nil },
            set: { if !$0 { pendingInstall = nil } }
        )
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func installConfirmationMessage(for descriptor: ModelDescriptor) -> String {
        let freeSpace = modelDiskFreeBytes.map(bytes) ?? t("Checked when the signed app runs")
        return """
        \(descriptor.id)
        라이선스: \(descriptor.license.name)
        다운로드: \(bytes(descriptor.downloadBytes))
        현재 디스크 여유: \(freeSpace)
        """
    }

    private var sourceModeBinding: Binding<SourceLanguageMode> {
        Binding(
            get: {
                guard case .fixed(let language) = model.preferences.sourceMode else {
                    return model.preferences.sourceMode
                }
                return .fixed(language.applyingChinesePreference(
                    model.preferences.chineseScriptPreference
                ))
            },
            set: { selection in
                guard case .fixed(let language) = selection else {
                    model.preferences.sourceMode = selection
                    return
                }
                model.preferences.sourceMode = .fixed(language.applyingChinesePreference(
                    model.preferences.chineseScriptPreference
                ))
            }
        )
    }
    private var appDisplayLanguageBinding: Binding<AppDisplayLanguage> {
        Binding(
            get: { model.preferences.appDisplayLanguage },
            set: { model.preferences.appDisplayLanguage = $0 }
        )
    }
    private var sessionLoggingEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.sessionLoggingEnabled },
            set: { enabled in
                if enabled, model.preferences.sessionLogDirectoryBookmark == nil {
                    model.chooseSessionLogDirectory()
                } else {
                    model.preferences.sessionLoggingEnabled = enabled
                }
            }
        )
    }
    private var targetBinding: Binding<SupportedLanguage> {
        Binding(
            get: {
                model.preferences.targetLanguage.applyingChinesePreference(
                    model.preferences.chineseScriptPreference
                )
            },
            set: {
                model.preferences.targetLanguage = $0.applyingChinesePreference(
                    model.preferences.chineseScriptPreference
                )
            }
        )
    }
    private var chineseBinding: Binding<ChineseScriptPreference> {
        Binding(
            get: { model.preferences.chineseScriptPreference },
            set: { preference in
                model.preferences.chineseScriptPreference = preference
                if case .fixed(let language) = model.preferences.sourceMode, language.isChinese {
                    model.preferences.sourceMode = .fixed(preference.language)
                }
                if model.preferences.targetLanguage.isChinese {
                    model.preferences.targetLanguage = preference.language
                }
            }
        )
    }
    private var transcriptionProviderBinding: Binding<ProviderID> {
        Binding(
            get: { model.preferences.transcriptionProvider },
            set: { model.preferences.selectTranscriptionProvider($0) }
        )
    }
    private var translationProviderBinding: Binding<ProviderID> {
        Binding(get: { model.preferences.translationProvider }, set: { model.preferences.translationProvider = $0 })
    }
    private var selectedASRModelBinding: Binding<String> {
        Binding(get: { model.preferences.selectedASRModelID }, set: { model.preferences.selectedASRModelID = $0 })
    }
    private var selectedTranslationModelBinding: Binding<String> {
        Binding(get: { model.preferences.selectedTranslationModelID }, set: { model.preferences.selectedTranslationModelID = $0 })
    }
    private var mlxTranslationPromptBinding: Binding<String> {
        Binding(get: { model.preferences.mlxTranslationPrompt }, set: { model.preferences.mlxTranslationPrompt = $0 })
    }
    private var sourceFontSizeBinding: Binding<Double> {
        Binding(get: { model.preferences.sourceFontSize }, set: { model.preferences.sourceFontSize = $0 })
    }
    private var translationFontSizeBinding: Binding<Double> {
        Binding(get: { model.preferences.translationFontSize }, set: { model.preferences.translationFontSize = $0 })
    }
    private var previewFontSizeBinding: Binding<Double> {
        Binding(get: { model.preferences.previewFontSize }, set: { model.preferences.previewFontSize = $0 })
    }
    private var backgroundOpacityBinding: Binding<Double> {
        Binding(get: { model.preferences.backgroundOpacity }, set: { model.preferences.backgroundOpacity = $0 })
    }
    private var endpointSilenceBinding: Binding<Double> {
        Binding(get: { model.preferences.endpointSilenceSeconds }, set: { model.preferences.endpointSilenceSeconds = $0 })
    }
    private var overlayLineCountBinding: Binding<Int> {
        Binding(get: { model.preferences.overlayLineCount }, set: { model.preferences.overlayLineCount = $0 })
    }
    private var overlayLayoutBinding: Binding<OverlayLayout> {
        Binding(get: { model.preferences.overlayLayout }, set: { model.preferences.overlayLayout = $0 })
    }
    private var subtitleDisplayModeBinding: Binding<SubtitleDisplayMode> {
        Binding(get: { model.preferences.subtitleDisplayMode }, set: { model.preferences.subtitleDisplayMode = $0 })
    }
    private var subtitleAlignmentBinding: Binding<SubtitleAlignment> {
        Binding(get: { model.preferences.subtitleAlignment }, set: { model.preferences.subtitleAlignment = $0 })
    }
    private var overlayLockedBinding: Binding<Bool> {
        Binding(get: { model.preferences.overlayLocked }, set: { model.preferences.overlayLocked = $0 })
    }
    private var sourceColorBinding: Binding<Color> {
        colorBinding(get: { model.preferences.sourceColor }, set: { model.preferences.sourceColor = $0 })
    }
    private var translationColorBinding: Binding<Color> {
        colorBinding(get: { model.preferences.translationColor }, set: { model.preferences.translationColor = $0 })
    }
    private var previewColorBinding: Binding<Color> {
        colorBinding(get: { model.preferences.previewColor }, set: { model.preferences.previewColor = $0 })
    }
    private var backgroundColorBinding: Binding<Color> {
        colorBinding(get: { model.preferences.backgroundColor }, set: { model.preferences.backgroundColor = $0 })
    }

    private func colorBinding(
        get: @escaping () -> RGBAColor,
        set: @escaping (RGBAColor) -> Void
    ) -> Binding<Color> {
        Binding(
            get: {
                let value = get()
                return Color(red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
            },
            set: { color in
                guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return }
                set(RGBAColor(
                    red: converted.redComponent,
                    green: converted.greenComponent,
                    blue: converted.blueComponent,
                    alpha: converted.alphaComponent
                ))
            }
        )
    }

    private func t(_ english: String) -> String {
        AppCopy.text(english, language: model.preferences.appDisplayLanguage)
    }

    private func appLanguageName(_ language: AppDisplayLanguage) -> String {
        switch language {
        case .english: t("English")
        case .chinese: t("Chinese")
        case .japanese: t("Japanese")
        case .korean: t("Korean")
        }
    }
}
