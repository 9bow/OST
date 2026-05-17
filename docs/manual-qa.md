# OST Manual QA Checklist

Run this checklist before tagging a release or after changing capture, speech,
translation, overlay, settings, or packaging behavior.

## Result Record

- Build or commit tested:
- App bundle tested:
- `OST.zip` SHA-256:
- Tester:
- Date:
- macOS version:
- Permission prompt results:
- Audio source tested:
- Source/target languages tested:
- Apple Translation language packs tested:
- Online fallback tested: Yes / No
- Network state for online fallback:
- Evidence captured: screenshots / logs / exported session / ZIP validation output
- Result: Pass / Fail
- Notes:

## Preflight

- Run `./test.sh` and confirm it passes.
- Run `./build.sh --clean` and confirm `build/OST.app` is created.
- For first-run permission checks, reset the relevant macOS privacy decisions
  before launching OST:
  - `tccutil reset ScreenCapture com.ost.on-screen-translator`
  - `tccutil reset SpeechRecognition com.ost.on-screen-translator`
- In System Settings, confirm OST is not already enabled under Screen & System
  Audio Recording or Speech Recognition before testing first-run prompts.
- Launch `build/OST.app` and confirm the OST menu bar icon appears.
- Run `pgrep -x OST` and confirm the app process is running.

## Screen Recording Permission

- With Screen Recording permission not yet granted, click **Start Capture**.
- If macOS prompts for Screen Recording, click **Allow** and confirm the same capture attempt continues instead of requiring a second click.
- If macOS prompts for System Audio Recording, click **Allow** and confirm the
  same capture attempt continues instead of requiring a second click.
- If permission is denied, confirm the menu shows a clear error and an action to
  open Screen & System Audio Recording settings.
- After granting permission in System Settings, quit and relaunch OST, then
  confirm capture can start.

## Speech Recognition Permission

- With Speech Recognition permission denied or unavailable, click **Start Capture**.
- If macOS prompts for Speech Recognition, click **Allow** and confirm the same
  capture attempt continues instead of requiring a second click.
- Confirm the menu shows a clear speech recognition error and an action to open
  Speech Recognition settings.
- Grant permission, relaunch OST, and confirm recognized text appears in the
  overlay while system audio is playing.

## Capture And Overlay

- Start capture with a supported audio source playing.
- Confirm original text appears in the overlay.
- Stop capture and confirm the overlay closes and the menu returns to Idle.
- Switch between **Combined** and **Split** display modes while capturing.
- Confirm split mode shows separate transcription and translation windows.
- Confirm visible entries with blank translations are retried after switching
  display modes.
- Lock and unlock the overlay, then confirm locked windows pass clicks through
  and unlocked windows can be moved or resized.
- Keep capture running for at least 70 seconds and confirm recognized text does
  not duplicate when the speech recognizer restarts.

## Translation

- Use a language pair with Apple Translation language packs installed and confirm
  translated text appears.
- Use a language pair without a ready Translation session and keep online
  fallback disabled. Confirm OST shows a translation status instead of silently
  sending text to an external service.
- Enable online fallback translation in Settings > Languages. Confirm the menu
  or overlay shows fallback status and translated text appears when network
  access is available.
- Enable online fallback after visible subtitle entries already exist with blank
  translations. Confirm those visible entries are retried and filled without
  starting a new capture session.
- Disable online fallback again and confirm stale fallback errors or status
  messages do not remain.

## Runtime Settings

- While capturing, change Max Lines and confirm old entries are trimmed.
- While capturing, change Subtitle Expiry and confirm entries expire using the
  new value.
- While capturing, change Speech Pause and confirm finalization timing changes.
- Change target language while capturing and confirm translation reconfigures
  without stopping capture.
- Change source language while capturing and confirm recognition restarts and
  new text appears.
- Confirm the language picker lists English, Chinese Simplified, Japanese, and
  Korean as selectable source/target languages.
- Switch between language pairs quickly while capturing and confirm old translations do not appear after the new pair is selected.
- After changing language pairs while recording a session, open Session History
  and confirm visible entries do not keep translations from the previous pair.
- Select the same source and target language and confirm Settings shows that no translation is needed.
- Select Auto source language and confirm Settings waits for detection instead of showing a language-pack download button.
- With Auto source language selected, play speech in a supported language and
  confirm the menu shows the detected source language and translations use it.
- Toggle On-device recognition while capturing and confirm recognition restarts
  with the new setting.
- With Auto source language already detected, toggle On-device recognition and
  confirm the detected source language remains visible.

## Session History And Diagnostics

- With **Settings > Debug > Save session history** enabled, capture a short session and stop.
- Start and stop without recognized text and confirm no empty session is added.
- While capturing, toggle **Settings > Debug > Save session history** off and on and confirm session recording stops and starts without restarting capture.
- Open Session History and confirm recognized and translated entries are present.
- With translation unavailable or online fallback disabled, confirm recognized
  entries are still saved even if translated text is blank.
- Click Clear All, cancel the confirmation, and confirm saved sessions remain.
- Click Clear All again, confirm deletion, and confirm saved sessions are
  removed.
- Export a session and confirm the saved text file contains timestamps and text.
- With **Settings > Debug > Session window always on top** enabled, export a session and confirm the save panel appears in front of the session window.
- While capturing with recognized text present, choose Quit OST and relaunch.
  Confirm the interrupted session is saved instead of being lost.
- With Session History open, toggle **Settings > Debug > Session window always on top** and confirm the existing window level changes immediately.
- Open Debug Console and confirm audio, speech, translation, and error messages
  are visible when those paths are exercised.
- Scroll up in Debug Console while new logs are arriving and confirm it does not
  jump to the newest log until you return to the bottom.

## Packaging Smoke Test

- Run `codesign --verify --deep --strict build/OST.app`.
- Run `codesign -d --entitlements :- build/OST.app` and confirm the output is
  valid XML.
- Run `codesign -d --entitlements :- build/OST.app > build/codesign-entitlements.plist 2>/dev/null`,
  then run `test "$(plutil -convert json -o - build/codesign-entitlements.plist)" = "$(plutil -convert json -o - OST/Resources/OST.entitlements)"`.
- Run `plutil -lint build/OST.app/Contents/Info.plist`.
- Run `test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' build/OST.app/Contents/Info.plist)" = "On-Screen Translator"`.
- Run `test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/OST.app/Contents/Info.plist)" = "com.ost.on-screen-translator"`.
- Run `test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' build/OST.app/Contents/Info.plist)" = "true"`.
- Run `/usr/libexec/PlistBuddy -c 'Print :NSSpeechRecognitionUsageDescription' build/OST.app/Contents/Info.plist`.
- Run `/usr/libexec/PlistBuddy -c 'Print :NSAudioCaptureUsageDescription' build/OST.app/Contents/Info.plist`.
- Run `/usr/libexec/PlistBuddy -c 'Print :NSSystemAudioRecordingUsageDescription' build/OST.app/Contents/Info.plist`.
- Create `OST.zip` with
  `(cd build && zip -r -X ../OST.zip OST.app -x '*/.DS_Store' -x '__MACOSX/*' -x '*/._*')`,
  then run `unzip -t OST.zip`.
- Run `shasum -a 256 OST.zip` and record the hash in the Result Record.
- Run `! unzip -Z1 OST.zip | grep -Eq '(^__MACOSX/|(^|/)\._|(^|/)\.DS_Store$)'`
  to confirm the archive does not include macOS metadata entries.
- Extract the ZIP with `rm -rf build/ost-zip-check && unzip -q OST.zip -d build/ost-zip-check`.
- Run `test -x build/ost-zip-check/OST.app/Contents/MacOS/OST`.
- Run `codesign --verify --deep --strict build/ost-zip-check/OST.app`.
- Run `codesign -d --entitlements :- build/ost-zip-check/OST.app > build/ost-zip-check/codesign-entitlements.plist 2>/dev/null`,
  then run `test "$(plutil -convert json -o - build/ost-zip-check/codesign-entitlements.plist)" = "$(plutil -convert json -o - OST/Resources/OST.entitlements)"`.
- Run `plutil -lint build/ost-zip-check/OST.app/Contents/Info.plist`.
- Run `test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' build/ost-zip-check/OST.app/Contents/Info.plist)" = "On-Screen Translator"`.
- Run `test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/ost-zip-check/OST.app/Contents/Info.plist)" = "com.ost.on-screen-translator"`.
- Run `test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' build/ost-zip-check/OST.app/Contents/Info.plist)" = "true"`.
- Run `/usr/libexec/PlistBuddy -c 'Print :NSSpeechRecognitionUsageDescription' build/ost-zip-check/OST.app/Contents/Info.plist`.
- Run `/usr/libexec/PlistBuddy -c 'Print :NSAudioCaptureUsageDescription' build/ost-zip-check/OST.app/Contents/Info.plist`.
- Run `/usr/libexec/PlistBuddy -c 'Print :NSSystemAudioRecordingUsageDescription' build/ost-zip-check/OST.app/Contents/Info.plist`.
- Remove `OST.zip`, `build/codesign-entitlements.plist`, and
  `build/ost-zip-check` after validation.

## Developer ID Signing And Notarization Checklist

Do not run this checklist from automation until the release owner has supplied
Apple Developer credentials. The current `build.sh` creates an ad-hoc signed app
for local testing; public distribution must be signed and notarized by a human
release owner.

- Confirm the release owner has an Apple Developer Program team and a Developer ID Application certificate available in the signing keychain.
- Confirm notarization credentials are available through either an App Store
  Connect API key or a notarytool keychain profile. Do not commit credentials.
- Re-sign the release candidate with Developer ID, hardened runtime, timestamp,
  and the checked-in entitlements file.
- Submit the signed ZIP or app bundle with `xcrun notarytool submit` and wait
  for an accepted notarization result.
- Staple the accepted ticket with `xcrun stapler staple build/OST.app`.
- Re-run the Packaging Smoke Test after stapling.
- On a clean macOS machine or clean user account, open the stapled app and
  confirm Gatekeeper allows launch without quarantine override commands.

## Cleanup

- Quit OST from the menu bar.
- Run `! pgrep -x OST` and confirm no OST process remains.
