#!/bin/bash
set -euo pipefail

# OST project checks. Keep this free of project/package dependencies so it
# works with the command-line build workflow documented in AGENTS.md.

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

fail() {
    echo "test.sh: $*" >&2
    exit 1
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

require_build_plist_key() {
    grep -q "<key>$1</key>" build.sh || fail "build.sh generated Info.plist is missing $1"
}

tmp_dir=".test-tmp"
mkdir -p "$tmp_dir"
tmp_actual="$(mktemp "$tmp_dir/actual.XXXXXX")"
tmp_listed="$(mktemp "$tmp_dir/listed.XXXXXX")"
tmp_commands_actual="$(mktemp "$tmp_dir/commands-actual.XXXXXX")"
tmp_commands_listed="$(mktemp "$tmp_dir/commands-listed.XXXXXX")"
tmp_code_blocks_actual="$(mktemp "$tmp_dir/code-blocks-actual.XXXXXX")"
tmp_code_blocks_listed="$(mktemp "$tmp_dir/code-blocks-listed.XXXXXX")"
tmp_urls_listed="$(mktemp "$tmp_dir/urls-listed.XXXXXX")"
tmp_build_arg="$(mktemp "$tmp_dir/build-arg.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

echo "== Shell syntax =="
[[ -x build.sh ]] || fail "build.sh must be executable"
[[ -x test.sh ]] || fail "test.sh must be executable because CI runs ./test.sh"
command -v ruby >/dev/null || fail "ruby is required for YAML syntax checks"
command -v xcrun >/dev/null || fail "xcrun is required for Swift type-checks"
xcrun -f swiftc >/dev/null || fail "swiftc is required for Swift type-checks"
ruby -e 'require "yaml"' || fail "ruby yaml support is required for YAML syntax checks"
command -v plutil >/dev/null || fail "plutil is required for plist validation"
command -v git >/dev/null || fail "git is required for repository hygiene checks"
[[ -x /usr/libexec/PlistBuddy ]] || fail "PlistBuddy is required for plist value checks"
git check-ignore -q OST.xcodeproj \
    || fail "generated OST.xcodeproj must stay ignored; build.sh is the supported build path"
for ignored_path in .test-tmp/ OST.zip release-zip-check ref-project/ DerivedData/ xcuserdata/ OST.xcworkspace/ .omc/; do
    git check-ignore -q "$ignored_path" \
        || fail "generated test/release artifact must stay ignored: $ignored_path"
done
grep -qxF '.DS_Store' .gitignore \
    || fail "macOS Finder metadata must stay ignored in the project .gitignore"
for untracked_artifact in .DS_Store .omc .test-tmp OST.zip release-zip-check build OST.xcodeproj OST.xcworkspace xcuserdata DerivedData ref-project; do
    if git ls-files -- "$untracked_artifact" | grep -q .; then
        fail "generated or local-only artifact must not be tracked: $untracked_artifact"
    fi
done
bash -n build.sh
bash -n test.sh
ruby -e 'require "yaml"; ARGV.each { |path| YAML.load_file(path) }' \
    .github/ISSUE_TEMPLATE/*.yml \
    .github/workflows/*.yml \
    || fail "GitHub issue template and workflow YAML files must parse"
if find . \
    -path './.git' -prune -o \
    -path './.omc' -prune -o \
    -path './.test-tmp' -prune -o \
    -path './build' -prune -o \
    -path './assets' -prune -o \
    -path './OST.xcodeproj' -prune -o \
    -path './OST.xcworkspace' -prune -o \
    -path './xcuserdata' -prune -o \
    -path './DerivedData' -prune -o \
    -path './ref-project' -prune -o \
    -type f -print0 \
    | xargs -0 grep -nI '[[:blank:]]$'; then
    fail "project text files must not contain trailing whitespace"
fi
if find . \
    -path './.git' -prune -o \
    -path './.omc' -prune -o \
    -path './.test-tmp' -prune -o \
    -path './build' -prune -o \
    -path './assets' -prune -o \
    -path './OST.xcodeproj' -prune -o \
    -path './OST.xcworkspace' -prune -o \
    -path './xcuserdata' -prune -o \
    -path './DerivedData' -prune -o \
    -path './ref-project' -prune -o \
    -type f -print0 \
    | xargs -0 grep -nIE '^(<<<<<<<|=======|>>>>>>>)($| )'; then
    fail "project text files must not contain unresolved merge conflict markers"
fi
if ./build.sh --definitely-invalid >"$tmp_build_arg" 2>&1; then
    fail "build.sh must reject unknown options"
fi
grep -q 'Unknown option: --definitely-invalid' "$tmp_build_arg" \
    || fail "build.sh must explain unknown options"
./build.sh --help >"$tmp_build_arg"
grep -q 'Usage: ./build.sh \[OPTIONS\]' "$tmp_build_arg" \
    || fail "build.sh --help must print usage"
if grep -q '=== OST Build ===' "$tmp_build_arg"; then
    fail "build.sh --help must exit before build setup"
fi
awk '
    /^done$/ && !doneLine { doneLine = NR }
    /^SDK_PATH=\$\(xcrun --show-sdk-path\)$/ { sdkLine = NR }
    END { if (!(doneLine && sdkLine && sdkLine > doneLine)) exit 1 }
' build.sh || fail "build.sh must parse arguments before querying the SDK"

echo "== Source list =="
find OST/Sources -name '*.swift' | sort > "$tmp_actual"
source_count="$(wc -l < "$tmp_actual" | tr -d ' ')"
grep -qF "compiles all ${source_count} Swift source files" AGENTS.md \
    || fail "AGENTS.md Swift source count must match OST/Sources ($source_count files)"
sed -n '/^SOURCES=(/,/^)$/p' build.sh \
    | sed -n 's/^[[:space:]]*\(OST\/Sources\/.*\.swift\)$/\1/p' \
    | sort > "$tmp_listed"
diff -u "$tmp_actual" "$tmp_listed" || fail "build.sh SOURCES does not match OST/Sources"

echo "== Resource list =="
find OST/Resources -type f | sort > "$tmp_actual"
printf '%s\n' OST/Resources/Info.plist OST/Resources/OST.entitlements | sort > "$tmp_listed"
diff -u "$tmp_actual" "$tmp_listed" || fail "OST/Resources contains files that build.sh does not package"

echo "== Version consistency =="
plutil -lint OST/Resources/Info.plist OST/Resources/OST.entitlements >/dev/null
build_version="$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' build.sh)"
build_number="$(sed -n 's/^BUILD_VERSION="\([^"]*\)"/\1/p' build.sh)"
build_app_name="$(sed -n 's/^APP_NAME="\([^"]*\)"/\1/p' build.sh)"
build_bundle_id="$(sed -n 's/^BUNDLE_ID="\([^"]*\)"/\1/p' build.sh)"
build_deploy_target="$(sed -n 's/^DEPLOY_TARGET="\([^"]*\)"/\1/p' build.sh)"
build_swift_version="$(sed -n 's/^SWIFT_VERSION="\([^"]*\)"/\1/p' build.sh)"
build_entitlements="$(sed -n 's/^ENTITLEMENTS="\([^"]*\)"/\1/p' build.sh)"
plist_version="$(plist_value OST/Resources/Info.plist CFBundleShortVersionString)"
plist_build_number="$(plist_value OST/Resources/Info.plist CFBundleVersion)"
plist_name="$(plist_value OST/Resources/Info.plist CFBundleName)"
plist_executable="$(plist_value OST/Resources/Info.plist CFBundleExecutable)"
plist_package_type="$(plist_value OST/Resources/Info.plist CFBundlePackageType)"
plist_bundle_id="$(plist_value OST/Resources/Info.plist CFBundleIdentifier)"
plist_deploy_target="$(plist_value OST/Resources/Info.plist LSMinimumSystemVersion)"
plist_display_name="$(plist_value OST/Resources/Info.plist CFBundleDisplayName)"
plist_speech_usage="$(plist_value OST/Resources/Info.plist NSSpeechRecognitionUsageDescription)"
plist_audio_capture_usage="$(plist_value OST/Resources/Info.plist NSAudioCaptureUsageDescription)"
plist_audio_usage="$(plist_value OST/Resources/Info.plist NSSystemAudioRecordingUsageDescription)"
project_version="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)"
project_build_number="$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' project.yml)"
project_bundle_id="$(awk '/PRODUCT_BUNDLE_IDENTIFIER:/ { print $2; exit }' project.yml)"
project_bundle_prefix="$(awk '/bundleIdPrefix:/ { print $2; exit }' project.yml)"
project_options_deploy_target="$(awk -F'"' '/^[[:space:]]*macOS:/ { print $2; exit }' project.yml)"
project_deploy_target="$(awk -F'"' '/MACOSX_DEPLOYMENT_TARGET:/ { print $2; exit }' project.yml)"
project_swift_version="$(awk -F'"' '/SWIFT_VERSION:/ { print $2; exit }' project.yml)"
project_entitlements="$(awk '/CODE_SIGN_ENTITLEMENTS:/ { print $2; exit }' project.yml)"
project_sources_path="$(awk '/^[[:space:]]*sources:/ { inSources = 1; next } inSources && /^[[:space:]]*- path:/ { print $3; exit }' project.yml)"
project_resources_path="$(awk '/^[[:space:]]*resources:/ { inResources = 1; next } inResources && /^[[:space:]]*- path:/ { print $3; exit }' project.yml)"
project_infoplist="$(awk '/INFOPLIST_FILE:/ { print $2; exit }' project.yml)"
project_product_name="$(awk '/PRODUCT_NAME:/ { print $2; exit }' project.yml)"
project_target_type="$(awk '/^[[:space:]]*type:/ { print $2; exit }' project.yml)"
project_target_platform="$(awk '/^[[:space:]]*platform:/ { print $2; exit }' project.yml)"
project_generate_infoplist="$(awk '/GENERATE_INFOPLIST_FILE:/ { print $2; exit }' project.yml)"
[[ -n "$build_version" ]] || fail "build.sh VERSION is missing"
[[ -n "$build_number" ]] || fail "build.sh BUILD_VERSION is missing"
[[ -n "$build_app_name" ]] || fail "build.sh APP_NAME is missing"
[[ -n "$build_bundle_id" ]] || fail "build.sh BUNDLE_ID is missing"
[[ -n "$build_deploy_target" ]] || fail "build.sh DEPLOY_TARGET is missing"
[[ -n "$build_swift_version" ]] || fail "build.sh SWIFT_VERSION is missing"
[[ -n "$build_entitlements" ]] || fail "build.sh ENTITLEMENTS is missing"
[[ "$project_target_type" == "application" ]] || fail "project.yml target type ($project_target_type) must stay application"
[[ "$project_target_platform" == "macOS" ]] || fail "project.yml target platform ($project_target_platform) must stay macOS"
[[ "$project_bundle_prefix" == "${build_bundle_id%.*}" ]] || fail "project.yml bundleIdPrefix ($project_bundle_prefix) differs from build.sh prefix (${build_bundle_id%.*})"
[[ "$project_options_deploy_target" == "$build_deploy_target" ]] || fail "project.yml options deployment target ($project_options_deploy_target) differs from build.sh ($build_deploy_target)"
[[ "$project_sources_path" == "OST/Sources" ]] || fail "project.yml sources path ($project_sources_path) differs from OST/Sources"
[[ "$project_resources_path" == "OST/Resources" ]] || fail "project.yml resources path ($project_resources_path) differs from OST/Resources"
[[ "$project_infoplist" == "OST/Resources/Info.plist" ]] || fail "project.yml INFOPLIST_FILE ($project_infoplist) differs from OST/Resources/Info.plist"
[[ "$project_product_name" == "$build_app_name" ]] || fail "project.yml PRODUCT_NAME ($project_product_name) differs from build.sh ($build_app_name)"
[[ "$project_generate_infoplist" == "false" ]] || fail "project.yml must not generate a second Info.plist"
[[ "$plist_name" == "$build_app_name" ]] || fail "Info.plist app name ($plist_name) differs from build.sh ($build_app_name)"
[[ "$plist_executable" == "\$(EXECUTABLE_NAME)" ]] || fail "Info.plist executable must use EXECUTABLE_NAME"
[[ "$plist_package_type" == "APPL" ]] || fail "Info.plist package type must be APPL"
[[ "$plist_version" == "$build_version" ]] || fail "Info.plist version ($plist_version) differs from build.sh ($build_version)"
[[ "$project_version" == "$build_version" ]] || fail "project.yml MARKETING_VERSION ($project_version) differs from build.sh ($build_version)"
[[ "$plist_build_number" == "$build_number" ]] || fail "Info.plist build number ($plist_build_number) differs from build.sh ($build_number)"
[[ "$project_build_number" == "$build_number" ]] || fail "project.yml CURRENT_PROJECT_VERSION ($project_build_number) differs from build.sh ($build_number)"
[[ "$plist_bundle_id" == "\$(PRODUCT_BUNDLE_IDENTIFIER)" ]] || fail "Info.plist bundle identifier must use PRODUCT_BUNDLE_IDENTIFIER"
[[ "$project_bundle_id" == "$build_bundle_id" ]] || fail "project.yml PRODUCT_BUNDLE_IDENTIFIER ($project_bundle_id) differs from build.sh ($build_bundle_id)"
[[ "$plist_deploy_target" == "\$(MACOSX_DEPLOYMENT_TARGET)" ]] || fail "Info.plist deployment target must use MACOSX_DEPLOYMENT_TARGET"
[[ "$project_deploy_target" == "$build_deploy_target" ]] || fail "project.yml MACOSX_DEPLOYMENT_TARGET ($project_deploy_target) differs from build.sh ($build_deploy_target)"
[[ "$project_swift_version" == "$build_swift_version" ]] || fail "project.yml SWIFT_VERSION ($project_swift_version) differs from build.sh ($build_swift_version)"
[[ "$project_entitlements" == "$build_entitlements" ]] || fail "project.yml CODE_SIGN_ENTITLEMENTS ($project_entitlements) differs from build.sh ($build_entitlements)"

echo "== App metadata =="
[[ "$(plist_value OST/Resources/Info.plist LSUIElement)" == "true" ]] || fail "Info.plist must keep LSUIElement=true"
[[ -n "$(plist_value OST/Resources/Info.plist CFBundleDisplayName)" ]] || fail "Info.plist is missing display name"
[[ -n "$(plist_value OST/Resources/Info.plist NSSpeechRecognitionUsageDescription)" ]] || fail "Info.plist is missing speech usage description"
[[ -n "$(plist_value OST/Resources/Info.plist NSAudioCaptureUsageDescription)" ]] || fail "Info.plist is missing system audio capture usage description"
[[ -n "$(plist_value OST/Resources/Info.plist NSSystemAudioRecordingUsageDescription)" ]] || fail "Info.plist is missing system audio usage description"
grep -qF "<string>${plist_display_name}</string>" build.sh \
    || fail "build.sh generated Info.plist display name differs from OST/Resources/Info.plist"
grep -qF "<string>${plist_speech_usage}</string>" build.sh \
    || fail "build.sh generated speech usage description differs from OST/Resources/Info.plist"
grep -qF "<string>${plist_audio_capture_usage}</string>" build.sh \
    || fail "build.sh generated system audio capture usage description differs from OST/Resources/Info.plist"
grep -qF "<string>${plist_audio_usage}</string>" build.sh \
    || fail "build.sh generated system audio usage description differs from OST/Resources/Info.plist"
for generated_plist_variable in APP_NAME BUNDLE_ID BUILD_VERSION VERSION DEPLOY_TARGET; do
    grep -qF "<string>\${${generated_plist_variable}}</string>" build.sh \
        || fail "build.sh generated Info.plist must use $generated_plist_variable"
done
for key in \
    CFBundleName \
    CFBundleDisplayName \
    CFBundleExecutable \
    CFBundleIdentifier \
    CFBundlePackageType \
    CFBundleVersion \
    CFBundleShortVersionString \
    LSMinimumSystemVersion \
    LSUIElement \
    NSSpeechRecognitionUsageDescription \
    NSAudioCaptureUsageDescription \
    NSSystemAudioRecordingUsageDescription; do
    require_build_plist_key "$key"
done

echo "== Documentation links =="
readmes=(README.md README.ko.md README.zh.md README.ja.md)
for local_doc in LICENSE docs/manual-qa.md README.md README.ko.md README.zh.md README.ja.md; do
    [[ -f "$local_doc" ]] || fail "README local link target is missing: $local_doc"
done
if grep -R 'OST\.git/releases/latest' "${readmes[@]}" >/dev/null; then
    fail "README release links should not include .git"
fi
grep -hoE 'assets/[^)]+' README.md | sort -u > "$tmp_listed"
for expected_asset in \
    assets/menubar.png \
    assets/overlay-demo.png \
    assets/overlay-demo-split-mode.png \
    assets/settings-display.png \
    assets/settings-languages.png \
    assets/settings-setup.png \
    assets/session-history.png; do
    grep -qFx "$expected_asset" "$tmp_listed" \
        || fail "README.md is missing expected screenshot asset: $expected_asset"
done
awk '
    /^>? ?```/ {
        line = $0
        sub(/^> /, "", line)
        print line
        inBlock = !inBlock
        next
    }
    inBlock {
        line = $0
        sub(/^> /, "", line)
        print line
    }
' README.md > "$tmp_code_blocks_listed"
for readme in "${readmes[@]}"; do
    grep -hoE 'assets/[^)]+' "$readme" | sort -u > "$tmp_actual"
    diff -u "$tmp_listed" "$tmp_actual" \
        || fail "$readme asset references differ from README.md"
    grep -hoE 'https?://[^) >]+' "$readme" | sort -u > "$tmp_actual"
    grep -hoE 'https?://[^) >]+' README.md | sort -u > "$tmp_urls_listed"
    diff -u "$tmp_urls_listed" "$tmp_actual" \
        || fail "$readme URL references differ from README.md"
    awk '
        /^>? ?```/ {
            line = $0
            sub(/^> /, "", line)
            print line
            inBlock = !inBlock
            next
        }
        inBlock {
            line = $0
            sub(/^> /, "", line)
            print line
        }
    ' "$readme" > "$tmp_code_blocks_actual"
    diff -u "$tmp_code_blocks_listed" "$tmp_code_blocks_actual" \
        || fail "$readme code blocks differ from README.md"
    for linked in README.md README.ko.md README.zh.md README.ja.md; do
        if [[ "$readme" != "$linked" ]]; then
            grep -qF "$linked" "$readme" || fail "$readme language selector is missing $linked"
        fi
    done
    grep -qF 'https://github.com/9bow/OST/releases/latest' "$readme" \
        || fail "$readme is missing the canonical release link"
    grep -qF 'Google Translate' "$readme" \
        || fail "$readme is missing online fallback privacy guidance"
    grep -qF 'docs/manual-qa.md' "$readme" \
        || fail "$readme is missing the manual QA link"
    grep -qF 'test.sh' "$readme" \
        || fail "$readme is missing the project checks command"
    grep -qF 'LICENSE' "$readme" \
        || fail "$readme is missing the LICENSE link"
    grep -qF '"Reset All Overlay Windows"' "$readme" \
        || fail "$readme troubleshooting must use the actual global overlay reset button label"
    grep -qF 'xattr -dr com.apple.quarantine /Applications/OST.app' "$readme" \
        || fail "$readme must document quarantine removal for installed apps"
    grep -qF 'xattr -dr com.apple.quarantine build/OST.app' "$readme" \
        || fail "$readme must document quarantine removal for local builds"
    grep -nFx \
        -e 'git clone https://github.com/9bow/OST.git' \
        -e 'cd OST' \
        -e './build.sh' \
        -e './build.sh --typecheck' \
        -e './test.sh' \
        -e './build.sh --clean' \
        -e 'open build/OST.app' \
        "$readme" \
        | sed 's/^[0-9]*://' > "$tmp_commands_actual"
    printf '%s\n' \
        'git clone https://github.com/9bow/OST.git' \
        'cd OST' \
        './build.sh' \
        './build.sh --typecheck' \
        './test.sh' \
        './build.sh --clean' \
        'open build/OST.app' > "$tmp_commands_listed"
    diff -u "$tmp_commands_listed" "$tmp_commands_actual" \
        || fail "$readme build command sequence differs from README.md"
    while IFS= read -r asset; do
        [[ -f "$asset" ]] || fail "$readme references missing asset: $asset"
    done < <(grep -hoE 'assets/[^)]+' "$readme")
    if grep -qE 'default 10s|기본값 10초|默认 10 秒|デフォルト10秒' "$readme"; then
        fail "$readme has the wrong subtitle expiry default"
    fi
    for command in './build.sh' './build.sh --typecheck' './test.sh' './build.sh --clean' 'open build/OST.app'; do
        grep -qF "$command" "$readme" || fail "$readme is missing command: $command"
    done
    for stale_disclaimer in \
        'entirely written by [Claude]' \
        '전적으로 작성' \
        '完全由 [Claude]' \
        'によって全て作成'; do
        if grep -qF "$stale_disclaimer" "$readme"; then
            fail "$readme must not claim the project was entirely written by one assistant"
        fi
    done
    grep -qF 'Start Capture' "$readme" \
        || fail "$readme usage must match the actual menu button label"
    case "$readme" in
        README.md)
            grep -qF 'This project was created and maintained through AI-assisted development.' "$readme" \
                || fail "$readme disclaimer must describe current AI-assisted maintenance accurately"
            grep -qF 'default 20s' "$readme" \
                || fail "$readme is missing the subtitle expiry default"
            grep -qF 'default 3s' "$readme" \
                || fail "$readme is missing the speech pause default"
            grep -qF 'Max Lines**: Control how many subtitle entries are visible at once (default 3)' "$readme" \
                || fail "$readme is missing the max lines default"
            grep -qF 'Online fallback translation**: Disabled by default' "$readme" \
                || fail "$readme must document online fallback as disabled by default"
            grep -qF 'Session History**: Enabled by default' "$readme" \
                || fail "$readme must document session history as enabled by default"
            grep -qF 'disable saving in Settings > Debug' "$readme" \
                || fail "$readme must point session history saving to the actual Debug settings tab"
            grep -qF 'On-device recognition**: Enabled by default' "$readme" \
                || fail "$readme must document on-device recognition as enabled by default"
            grep -qF 'confirm **"On-device recognition"** remains enabled' "$readme" \
                || fail "$readme on-device setup must match the enabled-by-default setting"
            grep -qF 'System Audio Recording' "$readme" \
                || fail "$readme must document System Audio Recording permission"
            grep -qF 'System Settings > Privacy & Security > Screen & System Audio Recording > Enable OST' "$readme" \
                || fail "$readme must point both audio capture permissions to Screen & System Audio Recording"
            grep -qF 'Menu bar Lock/Unlock applies to both windows simultaneously; Settings can lock each window independently' "$readme" \
                || fail "$readme must document split-mode lock behavior accurately"
            grep -qF 'Split**: Default mode' "$readme" \
                || fail "$readme must document split as the default display mode"
            grep -qF 'If you enable permissions manually in System Settings, restart OST for changes to take effect.' "$readme" \
                || fail "$readme setup guide must only require restart for manually changed permissions"
            grep -qF 'macOS may prompt for the following permissions' "$readme" \
                || fail "$readme setup guide must not guarantee all permission prompts appear"
            grep -qF 'permissions, audio capture, Apple Translation language packs, or online fallback network behavior' "$readme" \
                || fail "$readme must document the full manual QA scope"
            grep -qF 'documentation, workflow, regression, behavioral, and type-check gates' "$readme" \
                || fail "$readme must describe the project checks covered by ./test.sh"
            grep -qF 'Translation not appearing | Download the translation language pack, or enable online fallback' "$readme" \
                || fail "$readme troubleshooting must mention online fallback for missing translations"
            grep -qF 'No audio captured | Grant Screen Recording and System Audio Recording permissions. If you changed them in System Settings, restart OST' "$readme" \
                || fail "$readme troubleshooting must mention both audio capture permissions"
            ;;
        README.ko.md)
            grep -qF '이 프로젝트는 AI 지원 개발을 통해 생성 및 유지관리되었습니다.' "$readme" \
                || fail "$readme disclaimer must describe current AI-assisted maintenance accurately"
            grep -qF '기본값 20초' "$readme" \
                || fail "$readme is missing the subtitle expiry default"
            grep -qF '기본값 3초' "$readme" \
                || fail "$readme is missing the speech pause default"
            grep -qF '최대 줄 수**: 동시에 표시되는 자막 항목 수를 조절 (기본값 3)' "$readme" \
                || fail "$readme is missing the max lines default"
            grep -qF '온라인 대체 번역**: 기본적으로 비활성화' "$readme" \
                || fail "$readme must document online fallback as disabled by default"
            grep -qF '세션 기록**: 기본적으로 활성화' "$readme" \
                || fail "$readme must document session history as enabled by default"
            grep -qF '설정 > 디버그에서 저장을 비활성화' "$readme" \
                || fail "$readme must point session history saving to the actual Debug settings tab"
            grep -qF '온디바이스 인식**: 기본적으로 활성화' "$readme" \
                || fail "$readme must document on-device recognition as enabled by default"
            grep -qF '온디바이스 인식"** 이 켜져 있는지 확인' "$readme" \
                || fail "$readme on-device setup must match the enabled-by-default setting"
            grep -qF '시스템 오디오 녹음' "$readme" \
                || fail "$readme must document System Audio Recording permission"
            grep -qF '시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 녹음 > OST 활성화' "$readme" \
                || fail "$readme must point both audio capture permissions to Screen & System Audio Recording"
            grep -qF '메뉴 바 잠금/잠금 해제는 두 창에 동시에 적용되며, 설정에서는 각 창을 독립적으로 잠글 수 있음' "$readme" \
                || fail "$readme must document split-mode lock behavior accurately"
            grep -qF '분할**: 기본 모드' "$readme" \
                || fail "$readme must document split as the default display mode"
            grep -qF '시스템 설정에서 권한을 수동으로 활성화했다면 변경 사항 적용을 위해 OST를 재시작하세요.' "$readme" \
                || fail "$readme setup guide must only require restart for manually changed permissions"
            grep -qF 'macOS가 다음 권한을 요청할 수 있습니다' "$readme" \
                || fail "$readme setup guide must not guarantee all permission prompts appear"
            grep -qF '권한, 오디오 캡처, Apple Translation 언어 팩 또는 온라인 대체 번역 네트워크 동작' "$readme" \
                || fail "$readme must document the full manual QA scope"
            grep -qF '문서, 워크플로, 회귀, 동작, 타입 체크 게이트' "$readme" \
                || fail "$readme must describe the project checks covered by ./test.sh"
            grep -qF '번역이 나타나지 않음 | 번역 언어 팩을 다운로드하거나' "$readme" \
                || fail "$readme troubleshooting must mention online fallback for missing translations"
            grep -qF '오디오가 캡처되지 않음 | 화면 기록 및 시스템 오디오 녹음 권한을 허용하세요. 시스템 설정에서 변경했다면 OST를 재시작하세요' "$readme" \
                || fail "$readme troubleshooting must mention both audio capture permissions"
            ;;
        README.zh.md)
            grep -qF '本项目通过 AI 辅助开发创建并维护。' "$readme" \
                || fail "$readme disclaimer must describe current AI-assisted maintenance accurately"
            grep -qF '默认 20 秒' "$readme" \
                || fail "$readme is missing the subtitle expiry default"
            grep -qF '默认 3 秒' "$readme" \
                || fail "$readme is missing the speech pause default"
            grep -qF '最大行数**：控制同时显示的字幕条目数（默认 3）' "$readme" \
                || fail "$readme is missing the max lines default"
            grep -qF '在线备用翻译**：默认关闭' "$readme" \
                || fail "$readme must document online fallback as disabled by default"
            grep -qF '会话历史**：默认开启' "$readme" \
                || fail "$readme must document session history as enabled by default"
            grep -qF '设置 > 调试 中关闭保存' "$readme" \
                || fail "$readme must point session history saving to the actual Debug settings tab"
            grep -qF '设备端识别**：默认开启' "$readme" \
                || fail "$readme must document on-device recognition as enabled by default"
            grep -qF '确认 **"设备端识别"** 仍保持开启' "$readme" \
                || fail "$readme on-device setup must match the enabled-by-default setting"
            grep -qF '系统音频录制' "$readme" \
                || fail "$readme must document System Audio Recording permission"
            grep -qF '系统设置 > 隐私与安全性 > 屏幕与系统音频录制 > 启用 OST' "$readme" \
                || fail "$readme must point both audio capture permissions to Screen & System Audio Recording"
            grep -qF '菜单栏锁定/解锁会同时应用于两个窗口；设置中可单独锁定每个窗口' "$readme" \
                || fail "$readme must document split-mode lock behavior accurately"
            grep -qF '分离**：默认模式' "$readme" \
                || fail "$readme must document split as the default display mode"
            grep -qF '如果是在系统设置中手动启用权限，请重新启动 OST 以使更改生效。' "$readme" \
                || fail "$readme setup guide must only require restart for manually changed permissions"
            grep -qF 'macOS 可能会提示授予以下权限' "$readme" \
                || fail "$readme setup guide must not guarantee all permission prompts appear"
            grep -qF '权限、音频捕获、Apple Translation 语言包或在线备用翻译网络行为' "$readme" \
                || fail "$readme must document the full manual QA scope"
            grep -qF '文档、工作流、回归、行为和类型检查关卡' "$readme" \
                || fail "$readme must describe the project checks covered by ./test.sh"
            grep -qF '翻译未显示 | 下载翻译语言包' "$readme" \
                || fail "$readme troubleshooting must mention online fallback for missing translations"
            grep -qF '未捕获到音频 | 授予屏幕录制和系统音频录制权限。如果是在系统设置中更改的权限，请重新启动 OST' "$readme" \
                || fail "$readme troubleshooting must mention both audio capture permissions"
            ;;
        README.ja.md)
            grep -qF 'このプロジェクトはAI支援開発によって作成・保守されています。' "$readme" \
                || fail "$readme disclaimer must describe current AI-assisted maintenance accurately"
            grep -qF 'デフォルト20秒' "$readme" \
                || fail "$readme is missing the subtitle expiry default"
            grep -qF 'デフォルト3秒' "$readme" \
                || fail "$readme is missing the speech pause default"
            grep -qF '最大行数**：同時に表示される字幕エントリの数を制御（デフォルト3）' "$readme" \
                || fail "$readme is missing the max lines default"
            grep -qF 'オンライン代替翻訳**：デフォルトでは無効' "$readme" \
                || fail "$readme must document online fallback as disabled by default"
            grep -qF 'セッション履歴**：デフォルトで有効' "$readme" \
                || fail "$readme must document session history as enabled by default"
            grep -qF '設定 > デバッグで保存を無効化' "$readme" \
                || fail "$readme must point session history saving to the actual Debug settings tab"
            grep -qF 'オンデバイス認識**：デフォルトで有効' "$readme" \
                || fail "$readme must document on-device recognition as enabled by default"
            grep -qF '「オンデバイス認識」** が有効になっていることを確認' "$readme" \
                || fail "$readme on-device setup must match the enabled-by-default setting"
            grep -qF 'システムオーディオ録音' "$readme" \
                || fail "$readme must document System Audio Recording permission"
            grep -qF 'システム設定 > プライバシーとセキュリティ > 画面とシステムオーディオ録音 > OSTを有効化' "$readme" \
                || fail "$readme must point both audio capture permissions to Screen & System Audio Recording"
            grep -qF 'メニューバーのロック/アンロックは両方のウィンドウに同時に適用され、設定では各ウィンドウを個別にロック可能' "$readme" \
                || fail "$readme must document split-mode lock behavior accurately"
            grep -qF '分割**：デフォルトモード' "$readme" \
                || fail "$readme must document split as the default display mode"
            grep -qF 'システム設定で権限を手動で有効化した場合は、変更を反映するためにOSTを再起動してください。' "$readme" \
                || fail "$readme setup guide must only require restart for manually changed permissions"
            grep -qF 'macOSが以下の権限を要求する場合があります' "$readme" \
                || fail "$readme setup guide must not guarantee all permission prompts appear"
            grep -qF '権限、音声キャプチャ、Apple Translation言語パック、またはオンライン代替翻訳のネットワーク動作' "$readme" \
                || fail "$readme must document the full manual QA scope"
            grep -qF 'ドキュメント、ワークフロー、リグレッション、動作、タイプチェックのゲート' "$readme" \
                || fail "$readme must describe the project checks covered by ./test.sh"
            grep -qF '翻訳が表示されない | 翻訳言語パックをダウンロードするか' "$readme" \
                || fail "$readme troubleshooting must mention online fallback for missing translations"
            grep -qF 'オーディオがキャプチャされない | 画面収録とシステムオーディオ録音の権限を許可してください。システム設定で変更した場合はOSTを再起動してください' "$readme" \
                || fail "$readme troubleshooting must mention both audio capture permissions"
            ;;
    esac
done
for agent_doc in AGENTS.md CLAUDE.md; do
    [[ -f "$agent_doc" ]] || fail "$agent_doc is missing"
    grep -qF './test.sh' "$agent_doc" || fail "$agent_doc is missing ./test.sh"
    grep -qF 'uses system command-line tools only' "$agent_doc" \
        || fail "$agent_doc must describe test.sh as using system command-line tools only"
    grep -qF 'behavioral, and type-check gates' "$agent_doc" \
        || fail "$agent_doc must describe the behavioral checks covered by ./test.sh"
    grep -qF "compiles all ${source_count} Swift source files" "$agent_doc" \
        || fail "$agent_doc Swift source count must match OST/Sources"
    grep -qF 'docs/manual-qa.md' "$agent_doc" \
        || fail "$agent_doc must point release validation to the manual QA checklist"
    grep -qF 'System Audio Recording' "$agent_doc" \
        || fail "$agent_doc must document the system audio recording permission"
    grep -qF 'TranslationService → Overlay Views' "$agent_doc" \
        || fail "$agent_doc data pipeline must account for combined and split overlay hosts"
    grep -qF 'TranslationOverlayView' "$agent_doc" \
        || fail "$agent_doc must document the split-mode translation overlay as a .translationTask host"
    grep -qF 'strict concurrency diagnostics treated as failures' "$agent_doc" \
        || fail "$agent_doc must document the strict Swift concurrency build gate"
    grep -qF 'AsyncStream<AudioSampleBuffer>' "$agent_doc" \
        || fail "$agent_doc must document the Sendable audio buffer stream wrapper"
    if grep -qF 'AsyncStream<CMSampleBuffer>' "$agent_doc"; then
        fail "$agent_doc must not document the stale non-Sendable CMSampleBuffer stream type"
    fi
    if grep -qF 'There is no test suite' "$agent_doc"; then
        fail "$agent_doc must not claim there is no test suite"
    fi
    if grep -qF 'default 2s' "$agent_doc"; then
        fail "$agent_doc has the wrong speech pause default"
    fi
done
diff -u <(tail -n +4 AGENTS.md) <(tail -n +4 CLAUDE.md) >/dev/null \
    || fail "AGENTS.md and CLAUDE.md must stay in sync except title and tool-specific intro"
grep -qF 'System Audio Recording' OST/Sources/UI/SettingsView.swift \
    || fail "settings setup tab must document System Audio Recording permission"
grep -qF 'Required for system audio capture on macOS 15 or later.' OST/Sources/UI/SettingsView.swift \
    || fail "settings setup tab must explain why System Audio Recording is required"
grep -qF 'Screen Recording, System Audio Recording, and Speech Recognition permissions' OST/Sources/UI/SettingsView.swift \
    || fail "settings setup tab first-launch note must include all runtime permissions"

echo "== Manual QA checklist =="
manual_qa="docs/manual-qa.md"
[[ -f "$manual_qa" ]] || fail "manual QA checklist is missing"
for phrase in \
    "Result Record" \
    "Build or commit tested" \
    "App bundle tested" \
    "SHA-256" \
    "Tester:" \
    "Date:" \
    "macOS version" \
    "Permission prompt results" \
    "Audio source tested" \
    "Source/target languages tested" \
    "Apple Translation language packs tested" \
    "Online fallback tested" \
    "Network state for online fallback" \
    "Evidence captured" \
    "Result: Pass / Fail" \
    "Notes:" \
    "Run \`./test.sh\` and confirm it passes." \
    "Run \`./build.sh --clean\` and confirm \`build/OST.app\` is created." \
    "tccutil reset ScreenCapture com.ost.on-screen-translator" \
    "tccutil reset SpeechRecognition com.ost.on-screen-translator" \
    "confirm OST is not already enabled under Screen & System" \
    "pgrep -x OST" \
    "! pgrep -x OST" \
    "Screen Recording Permission" \
    "same capture attempt continues instead of requiring a second click" \
    "System Audio Recording" \
    "Screen & System Audio Recording settings" \
    "Speech Recognition Permission" \
    "If macOS prompts for Speech Recognition" \
    "recognized text appears" \
    "Capture And Overlay" \
    "locked windows pass clicks through" \
    "speech recognizer restarts" \
    "Translation" \
    "translated text appears" \
    "external service" \
    "stale fallback errors or status" \
    "Runtime Settings" \
    "Session History And Diagnostics" \
    "Packaging Smoke Test" \
    "codesign -d --entitlements :- build/OST.app" \
    "build/codesign-entitlements.plist" \
    "plutil -convert json -o - build/codesign-entitlements.plist" \
    "plutil -convert json -o - OST/Resources/OST.entitlements" \
    "Print :CFBundleDisplayName' build/OST.app/Contents/Info.plist" \
    "Print :CFBundleIdentifier' build/OST.app/Contents/Info.plist" \
    "Print :LSUIElement' build/OST.app/Contents/Info.plist" \
    "Print :NSSpeechRecognitionUsageDescription' build/OST.app/Contents/Info.plist" \
    "Print :NSAudioCaptureUsageDescription' build/OST.app/Contents/Info.plist" \
    "Print :NSSystemAudioRecordingUsageDescription' build/OST.app/Contents/Info.plist" \
    "LSUIElement" \
    "NSAudioCaptureUsageDescription" \
    "build/ost-zip-check" \
    "unzip -t OST.zip" \
    "shasum -a 256 OST.zip" \
    "zip -r -X ../OST.zip OST.app" \
    "unzip -q OST.zip -d build/ost-zip-check" \
    "test -x build/ost-zip-check/OST.app/Contents/MacOS/OST" \
    "codesign --verify --deep --strict build/ost-zip-check/OST.app" \
    "codesign -d --entitlements :- build/ost-zip-check/OST.app" \
    "plutil -convert json -o - build/ost-zip-check/codesign-entitlements.plist" \
    "plutil -lint build/ost-zip-check/OST.app/Contents/Info.plist" \
    "Print :CFBundleDisplayName' build/ost-zip-check/OST.app/Contents/Info.plist" \
    "Print :CFBundleIdentifier' build/ost-zip-check/OST.app/Contents/Info.plist" \
    "Print :LSUIElement' build/ost-zip-check/OST.app/Contents/Info.plist" \
    "Print :NSSpeechRecognitionUsageDescription' build/ost-zip-check/OST.app/Contents/Info.plist" \
    "Print :NSAudioCaptureUsageDescription' build/ost-zip-check/OST.app/Contents/Info.plist" \
    "Print :NSSystemAudioRecordingUsageDescription' build/ost-zip-check/OST.app/Contents/Info.plist" \
    "Remove \`OST.zip\`, \`build/codesign-entitlements.plist\`, and" \
    "\`build/ost-zip-check\` after validation." \
    "(^__MACOSX/|(^|/)\._|(^|/)\.DS_Store$)" \
    "online fallback" \
    "visible entries are retried" \
    "On-device recognition while capturing" \
    "translated text is blank" \
    "old translations do not appear" \
    "do not keep translations from the previous pair" \
    "English, Chinese Simplified, Japanese, and" \
    "no translation is needed" \
    "waits for detection" \
    "detected source language" \
    "detected source language remains visible" \
    "Settings > Debug > Save session history" \
    "no empty session is added" \
    "session recording stops and starts" \
    "cancel the confirmation" \
    "confirm deletion" \
    "Settings > Debug > Session window always on top" \
    "save panel appears in front" \
    "interrupted session is saved" \
    "window level changes immediately" \
    "Developer ID Signing And Notarization Checklist" \
    "Apple Developer Program team" \
    "Developer ID Application certificate" \
    "notarytool keychain profile" \
    "Do not commit credentials" \
    "hardened runtime" \
    "xcrun notarytool submit" \
    "xcrun stapler staple build/OST.app" \
    "Gatekeeper allows launch without quarantine override commands"; do
    grep -qF "$phrase" "$manual_qa" || fail "manual QA checklist is missing: $phrase"
done
same_attempt_prompt_count="$(grep -cF 'capture attempt continues instead of requiring a second click' "$manual_qa")"
[[ "$same_attempt_prompt_count" -ge 3 ]] \
    || fail "manual QA checklist must verify first-approval continuation for screen, system audio, and speech prompts"

echo "== Regression checks =="
for workflow in .github/workflows/build.yml .github/workflows/claude-code-review.yml .github/workflows/claude.yml; do
    grep -qx 'on:' "$workflow" \
        || fail "$workflow must define a top-level on trigger block"
    grep -qx 'jobs:' "$workflow" \
        || fail "$workflow must define a top-level jobs block"
done
grep -qx '  pull_request:' .github/workflows/build.yml \
    || fail "build workflow pull_request trigger must stay in the top-level on block"
grep -qx '  workflow_dispatch:' .github/workflows/build.yml \
    || fail "build workflow manual trigger must stay in the top-level on block"
grep -qx '  pull_request:' .github/workflows/claude-code-review.yml \
    || fail "Claude review workflow pull_request trigger must stay in the top-level on block"
for claude_event in issue_comment pull_request_review_comment issues pull_request_review; do
    grep -qx "  ${claude_event}:" .github/workflows/claude.yml \
        || fail "Claude mention workflow ${claude_event} trigger must stay in the top-level on block"
done
grep -q 'pull_request:' .github/workflows/build.yml \
    || fail "build workflow must run on pull requests"
grep -q 'runs-on: macos-15' .github/workflows/build.yml \
    || fail "build workflow must use a macOS 15 runner for Translation and ScreenCaptureKit"
grep -q "      - 'v\\*'" .github/workflows/build.yml \
    || fail "build workflow must publish releases from version tags"
grep -q "if: startsWith(github.ref, 'refs/tags/')" .github/workflows/build.yml \
    || fail "release job must only run for tags"
grep -q 'run: ./test.sh' .github/workflows/build.yml \
    || fail "build workflow must run ./test.sh"
grep -q 'contents: read' .github/workflows/build.yml \
    || fail "build job should use read-only contents permission"
grep -q 'needs: build' .github/workflows/build.yml \
    || fail "release job should depend on the build job"
grep -q 'contents: write' .github/workflows/build.yml \
    || fail "release job needs contents write permission"
awk '
    /^  build:/ { inBuild = 1; inRelease = 0; next }
    /^  release:/ { inBuild = 0; inRelease = 1; next }
    /^  [A-Za-z0-9_-]+:/ { inBuild = 0; inRelease = 0 }
    inBuild && /runs-on: macos-15/ { buildUsesMacOS15 = 1 }
    inBuild && /run: \.\/test\.sh/ { buildRunsTests = 1 }
    inRelease && index($0, "if: startsWith(github.ref, " q "refs/tags/" q ")") { releaseTagOnly = 1 }
    END { if (!buildUsesMacOS15 || !buildRunsTests || !releaseTagOnly) exit 1 }
' q="'" .github/workflows/build.yml \
    || fail "build workflow must use macos-15 and run tests in the build job, then gate the release job to version tags"
awk '
    /^  build:/ { inBuild = 1; inRelease = 0 }
    /^  release:/ { inBuild = 0; inRelease = 1 }
    inBuild && /contents: read/ { buildRead = 1 }
    inBuild && /contents: write/ { buildWrite = 1 }
    inRelease && /contents: write/ { releaseWrite = 1 }
    END { if (!buildRead || buildWrite || !releaseWrite) exit 1 }
' .github/workflows/build.yml \
    || fail "workflow permissions must keep build read-only and release write-scoped"
grep -q 'actions/download-artifact@v4' .github/workflows/build.yml \
    || fail "release job should download the built artifact"
artifact_name_count="$(grep -c 'name: OST.zip' .github/workflows/build.yml)"
[[ "$artifact_name_count" -ge 2 ]] \
    || fail "workflow upload/download artifact names should match the OST.zip release file"
if grep -q 'name: OST\.app' .github/workflows/build.yml; then
    fail "workflow artifacts must use OST.zip, not an unsigned app bundle name"
fi
grep -q 'path: OST.zip' .github/workflows/build.yml \
    || fail "workflow upload artifact path must be OST.zip"
grep -q 'files: OST.zip' .github/workflows/build.yml \
    || fail "release upload must publish OST.zip"
awk '
    /- name: Upload artifact/ {
        inUpload = 1
        sawAction = 0
        sawName = 0
        sawPath = 0
        next
    }
    inUpload && /uses: actions\/upload-artifact@v4/ { sawAction = 1 }
    inUpload && /name: OST\.zip/ { sawName = 1 }
    inUpload && /path: OST\.zip/ { sawPath = 1 }
    inUpload && /^      - name:/ {
        if (sawAction && sawName && sawPath) { found = 1 }
        inUpload = 0
    }
    END {
        if (inUpload && sawAction && sawName && sawPath) { found = 1 }
        if (!found) exit 1
    }
' .github/workflows/build.yml \
    || fail "workflow Upload artifact step must upload OST.zip"
awk '
    /- name: Create Release/ {
        inReleaseStep = 1
        sawAction = 0
        sawFiles = 0
        next
    }
    inReleaseStep && /uses: softprops\/action-gh-release@v2/ { sawAction = 1 }
    inReleaseStep && /files: OST\.zip/ { sawFiles = 1 }
    inReleaseStep && /^      - name:/ {
        if (sawAction && sawFiles) { found = 1 }
        inReleaseStep = 0
    }
    END {
        if (inReleaseStep && sawAction && sawFiles) { found = 1 }
        if (!found) exit 1
    }
' .github/workflows/build.yml \
    || fail "workflow Create Release step must publish OST.zip"
grep -q 'blank_issues_enabled: false' .github/ISSUE_TEMPLATE/config.yml \
    || fail "blank issues must be disabled so issue templates collect required diagnostics"
for issue_field in \
    'Permissions / Setup' \
    'OST Version or Commit' \
    'Click Start Capture with' \
    'Permissions and Language Setup' \
    'System Audio Recording: granted / denied / not prompted / not shown' \
    'On-device recognition: enabled / disabled' \
    'Source language: English / Korean / Japanese / Chinese Simplified / Auto' \
    'Target language: English / Korean / Japanese / Chinese Simplified' \
    'Apple Translation language pack' \
    'Online fallback translation' \
    'Debug Logs' \
    'OST > Debug Console'; do
    grep -qF "$issue_field" .github/ISSUE_TEMPLATE/bug_report.yml \
        || fail "bug report template is missing diagnostic field: $issue_field"
done
duplicate_issue_ids="$(awk '/^[[:space:]]+id:/ { print $2 }' .github/ISSUE_TEMPLATE/bug_report.yml | sort | uniq -d)"
[[ -z "$duplicate_issue_ids" ]] \
    || fail "bug report template has duplicate field ids: $duplicate_issue_ids"
for required_issue_id in description steps area; do
    awk -v field="$required_issue_id" '
        $0 ~ "id: " field { inField = 1; sawValidations = 0; sawRequired = 0; next }
        inField && /validations:/ { sawValidations = 1 }
        inField && sawValidations && /required: true/ { sawRequired = 1 }
        inField && /^  - type:/ {
            if (sawRequired) { found = 1 }
            inField = 0
        }
        END {
            if (inField && sawRequired) { found = 1 }
            if (!found) exit 1
        }
    ' .github/ISSUE_TEMPLATE/bug_report.yml \
        || fail "bug report template must require field: $required_issue_id"
done
awk '
    /id: ost-version/ { inVersion = 1; sawValidations = 0; sawRequired = 0; next }
    inVersion && /validations:/ { sawValidations = 1 }
    inVersion && sawValidations && /required: true/ { sawRequired = 1 }
    inVersion && /^  - type:/ {
        if (sawRequired) { found = 1 }
        inVersion = 0
    }
    END {
        if (inVersion && sawRequired) { found = 1 }
        if (!found) exit 1
    }
' .github/ISSUE_TEMPLATE/bug_report.yml \
    || fail "bug report template must require the OST version or commit"
awk '
    /id: macos-version/ { inMacOS = 1; sawValidations = 0; sawRequired = 0; next }
    inMacOS && /validations:/ { sawValidations = 1 }
    inMacOS && sawValidations && /required: true/ { sawRequired = 1 }
    inMacOS && /^  - type:/ {
        if (sawRequired) { found = 1 }
        inMacOS = 0
    }
    END {
        if (inMacOS && sawRequired) { found = 1 }
        if (!found) exit 1
    }
' .github/ISSUE_TEMPLATE/bug_report.yml \
    || fail "bug report template must require the macOS version"
awk '
    /id: setup/ { inSetup = 1; sawValidations = 0; sawRequired = 0; next }
    inSetup && /validations:/ { sawValidations = 1 }
    inSetup && sawValidations && /required: true/ { sawRequired = 1 }
    inSetup && /^  - type:/ {
        if (sawRequired) { found = 1 }
        inSetup = 0
    }
    END {
        if (inSetup && sawRequired) { found = 1 }
        if (!found) exit 1
    }
' .github/ISSUE_TEMPLATE/bug_report.yml \
    || fail "bug report template must require permissions and language setup details"
for feature_field in \
    'Feature Request' \
    'Suggest a new feature or improvement' \
    'labels: ["enhancement"]' \
    'Problem' \
    'Affected Area' \
    'Permissions / Setup' \
    'Audio Capture' \
    'Speech Recognition' \
    'Translation' \
    'Overlay Display' \
    'Session History / Logs' \
    'Settings' \
    'Proposed Solution' \
    'Alternatives Considered' \
    'Additional Context'; do
    grep -qF "$feature_field" .github/ISSUE_TEMPLATE/feature_request.yml \
        || fail "feature request template is missing field: $feature_field"
done
duplicate_feature_ids="$(awk '/^[[:space:]]+id:/ { print $2 }' .github/ISSUE_TEMPLATE/feature_request.yml | sort | uniq -d)"
[[ -z "$duplicate_feature_ids" ]] \
    || fail "feature request template has duplicate field ids: $duplicate_feature_ids"
awk '
    /id: area/ { inArea = 1; sawValidations = 0; sawRequired = 0; next }
    inArea && /validations:/ { sawValidations = 1 }
    inArea && sawValidations && /required: true/ { sawRequired = 1 }
    inArea && /^  - type:/ {
        if (sawRequired) { found = 1 }
        inArea = 0
    }
    END {
        if (inArea && sawRequired) { found = 1 }
        if (!found) exit 1
    }
' .github/ISSUE_TEMPLATE/feature_request.yml \
    || fail "feature request template must require the affected area"
awk '
    /id: problem/ { inProblem = 1; sawValidations = 0; sawRequired = 0; next }
    inProblem && /validations:/ { sawValidations = 1 }
    inProblem && sawValidations && /required: true/ { sawRequired = 1 }
    inProblem && /^  - type:/ {
        if (sawRequired) { found = 1 }
        inProblem = 0
    }
    END {
        if (inProblem && sawRequired) { found = 1 }
        if (!found) exit 1
    }
' .github/ISSUE_TEMPLATE/feature_request.yml \
    || fail "feature request template must require the problem"
awk '
    /id: solution/ { inSolution = 1; sawValidations = 0; sawRequired = 0; next }
    inSolution && /validations:/ { sawValidations = 1 }
    inSolution && sawValidations && /required: true/ { sawRequired = 1 }
    inSolution && /^  - type:/ {
        if (sawRequired) { found = 1 }
        inSolution = 0
    }
    END {
        if (inSolution && sawRequired) { found = 1 }
        if (!found) exit 1
    }
' .github/ISSUE_TEMPLATE/feature_request.yml \
    || fail "feature request template must require the proposed solution"
[[ -f .github/pull_request_template.md ]] \
    || fail "pull request template is missing"
for pr_template_field in \
    './test.sh' \
    './build.sh --clean' \
    'OST.zip` SHA-256 recorded' \
    'docs/manual-qa.md' \
    'Manual QA evidence attached or linked' \
    'capture, speech, translation, overlay, settings, session history, packaging, or permissions' \
    'Privacy / Data Flow' \
    'online fallback or other external data transfer changes'; do
    grep -qF "$pr_template_field" .github/pull_request_template.md \
        || fail "pull request template is missing validation field: $pr_template_field"
done
awk '
    /- name: Verify release artifact/ {
        inVerify = 1
        sawSize = 0
        sawHash = 0
        sawUnzip = 0
        sawExecutablePath = 0
        sawExecutablePermission = 0
        sawPlistParser = 0
        sawPlistParse = 0
        sawDisplayName = 0
        sawBundleIdentifier = 0
        sawLSUIElement = 0
        sawSpeechUsage = 0
        sawAudioCaptureUsage = 0
        sawSystemAudioUsage = 0
    }
    inVerify && /test -s OST\.zip/ { sawSize = 1 }
    inVerify && /sha256sum OST\.zip/ { sawHash = 1 }
    inVerify && /unzip -t OST\.zip/ { sawUnzip = 1 }
    inVerify && /grep -Fxq '\''OST\.app\/Contents\/MacOS\/OST'\''/ { sawExecutablePath = 1 }
    inVerify && /test -x release-zip-check\/OST\.app\/Contents\/MacOS\/OST/ { sawExecutablePermission = 1 }
    inVerify && /python3 - <<'\''PY'\''/ { sawPlistParser = 1 }
    inVerify && /plistlib\.loads/ { sawPlistParse = 1 }
    inVerify && /plist\.get\("CFBundleDisplayName"\) == "On-Screen Translator"/ { sawDisplayName = 1 }
    inVerify && /plist\.get\("CFBundleIdentifier"\) == "com\.ost\.on-screen-translator"/ { sawBundleIdentifier = 1 }
    inVerify && /plist\.get\("LSUIElement"\) is True/ { sawLSUIElement = 1 }
    inVerify && /NSSpeechRecognitionUsageDescription/ { sawSpeechUsage = 1 }
    inVerify && /NSAudioCaptureUsageDescription/ { sawAudioCaptureUsage = 1 }
    inVerify && /NSSystemAudioRecordingUsageDescription/ { sawSystemAudioUsage = 1 }
    inVerify && /^      - name:/ && !/- name: Verify release artifact/ {
        if (sawSize && sawHash && sawUnzip && sawExecutablePath && sawExecutablePermission &&
            sawPlistParser && sawPlistParse && sawDisplayName && sawBundleIdentifier && sawLSUIElement &&
            sawSpeechUsage && sawAudioCaptureUsage && sawSystemAudioUsage) { found = 1 }
        inVerify = 0
    }
    END {
        if (inVerify && sawSize && sawHash && sawUnzip && sawExecutablePath && sawExecutablePermission &&
            sawPlistParser && sawPlistParse && sawDisplayName && sawBundleIdentifier && sawLSUIElement &&
            sawSpeechUsage && sawAudioCaptureUsage && sawSystemAudioUsage) { found = 1 }
        if (!found) exit 1
    }
' .github/workflows/build.yml \
    || fail "release job must verify downloaded OST.zip size, structure, executable permissions, identity, and parsed app metadata before publishing"
grep -q 'unzip -t OST.zip' .github/workflows/build.yml \
    || fail "build workflow must validate the release ZIP"
grep -q 'shasum -a 256 OST.zip' .github/workflows/build.yml \
    || fail "macOS build workflow must print the OST.zip SHA-256"
grep -q 'sha256sum OST.zip' .github/workflows/build.yml \
    || fail "Ubuntu release workflow must print the OST.zip SHA-256"
awk '
    /- name: Validate ZIP/ {
        inValidate = 1
        sawSize = 0
        sawHash = 0
        sawUnzip = 0
        sawEntitlements = 0
        sawDisplayName = 0
        sawBundleIdentifier = 0
    }
    inValidate && /test -s OST\.zip/ { sawSize = 1 }
    inValidate && /shasum -a 256 OST\.zip/ { sawHash = 1 }
    inValidate && /unzip -t OST\.zip/ { sawUnzip = 1 }
    inValidate && /plutil -convert json -o - build\/ost-zip-check\/codesign-entitlements\.plist/ { sawEntitlements = 1 }
    inValidate && /Print :CFBundleDisplayName/ { sawDisplayName = 1 }
    inValidate && /Print :CFBundleIdentifier/ { sawBundleIdentifier = 1 }
    inValidate && /^      - name:/ && !/- name: Validate ZIP/ {
        if (sawSize && sawHash && sawUnzip && sawEntitlements && sawDisplayName && sawBundleIdentifier) { found = 1 }
        inValidate = 0
    }
    END {
        if (inValidate && sawSize && sawHash && sawUnzip && sawEntitlements && sawDisplayName && sawBundleIdentifier) { found = 1 }
        if (!found) exit 1
    }
' .github/workflows/build.yml \
    || fail "build workflow Validate ZIP step must print the OST.zip SHA-256 and verify app identity and entitlement metadata"
awk '
    /^      - name: / {
        if (inStep && required && !sawStrict) {
            exit 1
        }
        inStep = 1
        required = /- name: (Create ZIP|Validate ZIP|Verify release artifact)/
        sawRun = 0
        sawStrict = 0
        next
    }
    inStep && /^        run: \|/ {
        sawRun = 1
        next
    }
    inStep && required && sawRun && /set -euo pipefail/ {
        sawStrict = 1
    }
    END {
        if (inStep && required && !sawStrict) {
            exit 1
        }
    }
' .github/workflows/build.yml \
    || fail "workflow ZIP creation and validation scripts must each use strict shell settings"
grep -q "zip -r -X ../OST.zip OST.app" .github/workflows/build.yml \
    || fail "build workflow must omit platform-specific metadata from the release ZIP"
grep -q "grep -Fxq 'OST.app/Contents/MacOS/OST'" .github/workflows/build.yml \
    || fail "build workflow must verify the release ZIP contains the app executable"
metadata_guard_count="$(grep -F -c "grep -Eq '(^__MACOSX/|(^|/)\\._|(^|/)\\.DS_Store$)'" .github/workflows/build.yml)"
[[ "$metadata_guard_count" -ge 2 ]] \
    || fail "build and release jobs must reject macOS metadata entries in OST.zip"
grep -q 'codesign --verify --deep --strict build/ost-zip-check/OST.app' .github/workflows/build.yml \
    || fail "build workflow must verify the app signature after extracting the release ZIP"
grep -q 'codesign -d --entitlements :- build/ost-zip-check/OST.app' .github/workflows/build.yml \
    || fail "build workflow must dump extracted release app entitlements"
grep -q 'plutil -convert json -o - build/ost-zip-check/codesign-entitlements.plist' .github/workflows/build.yml \
    || fail "build workflow must compare extracted release app entitlements"
grep -q 'plutil -convert json -o - OST/Resources/OST.entitlements' .github/workflows/build.yml \
    || fail "build workflow must compare extracted app entitlements against configured entitlements"
grep -q 'plutil -lint build/ost-zip-check/OST.app/Contents/Info.plist' .github/workflows/build.yml \
    || fail "build workflow must lint the extracted release app Info.plist"
grep -q "Print :LSUIElement.*build/ost-zip-check/OST.app/Contents/Info.plist" .github/workflows/build.yml \
    || fail "build workflow must verify the extracted release app stays a menu bar app"
grep -q "Print :NSAudioCaptureUsageDescription.*build/ost-zip-check/OST.app/Contents/Info.plist" .github/workflows/build.yml \
    || fail "build workflow must verify the extracted release app system audio capture usage description"
grep -q "Print :NSSpeechRecognitionUsageDescription.*build/ost-zip-check/OST.app/Contents/Info.plist" .github/workflows/build.yml \
    || fail "build workflow must verify the extracted release app speech recognition usage description"
grep -q "Print :NSSystemAudioRecordingUsageDescription.*build/ost-zip-check/OST.app/Contents/Info.plist" .github/workflows/build.yml \
    || fail "build workflow must verify the extracted release app system audio recording usage description"
if grep -q '/tmp/ost-zip-check' .github/workflows/build.yml; then
    fail "build workflow ZIP validation must stay within the repository workspace"
fi
if grep -R 'src/\*\*/.*\.\(ts\|tsx\|js\|jsx\)' .github/workflows >/dev/null; then
    fail "GitHub workflow comments should use this Swift project's paths, not JS/TS examples"
fi
for review_path in \
    '#   - "OST/Sources/**/*.swift"' \
    '#   - "OST/Resources/**"' \
    '#   - "build.sh"' \
    '#   - "project.yml"'; do
    grep -qF "$review_path" .github/workflows/claude-code-review.yml \
        || fail "Claude review workflow path examples must match this Swift project: $review_path"
done
grep -q 'uses: anthropics/claude-code-action@v1' .github/workflows/claude-code-review.yml \
    || fail "Claude review workflow must run the Claude Code action"
grep -q "plugins: 'code-review@claude-code-plugins'" .github/workflows/claude-code-review.yml \
    || fail "Claude review workflow must use the code-review plugin"
[[ -f .github/workflows/claude.yml ]] \
    || fail "Claude mention workflow is missing"
for claude_trigger in \
    'issue_comment:' \
    'pull_request_review_comment:' \
    'issues:' \
    'pull_request_review:' \
    "contains(github.event.comment.body, '@claude')" \
    "contains(github.event.review.body, '@claude')" \
    "contains(github.event.issue.body, '@claude')" \
    "contains(github.event.issue.title, '@claude')"; do
    grep -qF "$claude_trigger" .github/workflows/claude.yml \
        || fail "Claude mention workflow is missing trigger or guard: $claude_trigger"
done
grep -q 'uses: anthropics/claude-code-action@v1' .github/workflows/claude.yml \
    || fail "Claude mention workflow must run the Claude Code action"
grep -q 'claude_code_oauth_token: \${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}' .github/workflows/claude.yml \
    || fail "Claude mention workflow must use the configured OAuth secret"
awk '
    /^    permissions:/ { inPermissions = 1; next }
    inPermissions && /^    steps:/ { inPermissions = 0 }
    inPermissions && /contents: read/ { contentsRead = 1 }
    inPermissions && /pull-requests: read/ { pullRequestsRead = 1 }
    inPermissions && /issues: read/ { issuesRead = 1 }
    inPermissions && /actions: read/ { actionsRead = 1 }
    inPermissions && /id-token: write/ { idTokenWrite = 1 }
    inPermissions && /: write/ && !/id-token: write/ { extraWrite = 1 }
    END {
        if (!(contentsRead && pullRequestsRead && issuesRead && actionsRead && idTokenWrite) || extraWrite) exit 1
    }
' .github/workflows/claude.yml \
    || fail "Claude mention workflow permissions must stay scoped to read-only repo context, CI read access, and OIDC"
awk '
    /additional_permissions: \|/ { inAdditional = 1; next }
    inAdditional && /actions: read/ { actionsRead = 1 }
    inAdditional && /^          [[:alnum:]_]+:/ { inAdditional = 0 }
    END { if (!actionsRead) exit 1 }
' .github/workflows/claude.yml \
    || fail "Claude mention workflow must pass actions: read to the Claude action for CI result inspection"
awk '
    /^    permissions:/ { inPermissions = 1; next }
    inPermissions && /^    steps:/ { inPermissions = 0 }
    inPermissions && /contents: read/ { contentsRead = 1 }
    inPermissions && /pull-requests: read/ { pullRequestsRead = 1 }
    inPermissions && /issues: read/ { issuesRead = 1 }
    inPermissions && /id-token: write/ { idTokenWrite = 1 }
    inPermissions && /(contents|pull-requests|issues): write/ { extraWrite = 1 }
    END {
        if (!(contentsRead && pullRequestsRead && issuesRead && idTokenWrite) || extraWrite) exit 1
    }
' .github/workflows/claude-code-review.yml \
    || fail "Claude review workflow permissions must stay scoped for read-only PR review context and OIDC"
if grep -q 'codesign .*|| true' build.sh; then
    fail "build.sh must not ignore codesign failures"
fi
grep -q 'plutil -lint "$CONTENTS/Info.plist"' build.sh \
    || fail "build.sh must lint the generated Info.plist"
grep -q 'plutil -lint "$ENTITLEMENTS"' build.sh \
    || fail "build.sh must lint the configured entitlements"
grep -q 'test -x "$MACOS_DIR/$APP_NAME"' build.sh \
    || fail "build.sh must verify the built executable exists and is executable"
grep -q 'otool -L "$MACOS_DIR/$APP_NAME"' build.sh \
    || fail "build.sh must verify linked frameworks in the built binary"
for framework in AppKit SwiftUI Speech ScreenCaptureKit CoreMedia Translation NaturalLanguage; do
    grep -q -- "-framework $framework" build.sh \
        || fail "build.sh must explicitly link framework: $framework"
    grep -q "/\${framework}.framework/" build.sh \
        || fail "build.sh must verify linked framework: $framework"
done
if grep -q 'import AVFoundation' OST/Sources/Audio/SystemAudioCapture.swift; then
    fail "SystemAudioCapture must not import unused AVFoundation"
fi
grep -q 'Print :CFBundleExecutable' build.sh \
    || fail "build.sh must verify generated CFBundleExecutable"
grep -q 'Print :CFBundlePackageType' build.sh \
    || fail "build.sh must verify generated CFBundlePackageType"
grep -q 'cat "$CONTENTS/PkgInfo"' build.sh \
    || fail "build.sh must verify generated PkgInfo"
grep -q "Print :CFBundleName" build.sh \
    || fail "build.sh must verify generated CFBundleName"
grep -q "Print :CFBundleDisplayName" build.sh \
    || fail "build.sh must verify generated CFBundleDisplayName"
grep -q "Print :CFBundleIdentifier" build.sh \
    || fail "build.sh must verify generated CFBundleIdentifier"
grep -q "Print :CFBundleVersion" build.sh \
    || fail "build.sh must verify generated CFBundleVersion"
grep -q "Print :CFBundleShortVersionString" build.sh \
    || fail "build.sh must verify generated CFBundleShortVersionString"
grep -q "Print :LSMinimumSystemVersion" build.sh \
    || fail "build.sh must verify generated LSMinimumSystemVersion"
grep -q "Print :LSUIElement" build.sh \
    || fail "build.sh must verify generated LSUIElement"
grep -q "Print :NSSpeechRecognitionUsageDescription" build.sh \
    || fail "build.sh must verify generated speech usage description"
grep -q "Print :NSAudioCaptureUsageDescription" build.sh \
    || fail "build.sh must verify generated system audio capture usage description"
grep -q "Print :NSSystemAudioRecordingUsageDescription" build.sh \
    || fail "build.sh must verify generated system audio usage description"
grep -q 'codesign --verify --deep --strict "$APP_BUNDLE"' build.sh \
    || fail "build.sh must verify the signed app bundle"
grep -q 'codesign -d --entitlements :- "$APP_BUNDLE"' build.sh \
    || fail "build.sh must dump signed app entitlements for validation"
grep -q 'plutil -lint "$BUILD_DIR/codesign-entitlements.plist"' build.sh \
    || fail "build.sh must validate dumped signed app entitlements"
grep -q 'plutil -convert json -o - "$BUILD_DIR/codesign-entitlements.plist"' build.sh \
    || fail "build.sh must compare dumped signed entitlements against configured entitlements"
grep -q 'plutil -convert json -o - "$ENTITLEMENTS"' build.sh \
    || fail "build.sh must compare configured entitlements against the signed app"
grep -q 'rm -f "$BUILD_DIR/codesign-entitlements.plist"' build.sh \
    || fail "build.sh must remove the temporary dumped entitlements file"
grep -q 'codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"' build.sh \
    || fail "build.sh must sign the app bundle with the configured entitlements"
grep -q "unzip -Z1 OST.zip | grep -Fxq 'OST.app/Contents/MacOS/OST'" .github/workflows/build.yml \
    || fail "build workflow must verify ZIP contents without pipefail-prone unzip -l output"
grep -q 'test -x build/ost-zip-check/OST.app/Contents/MacOS/OST' .github/workflows/build.yml \
    || fail "build workflow must verify extracted ZIP executable permissions"
grep -q "Print :CFBundleDisplayName' build/ost-zip-check/OST.app/Contents/Info.plist" .github/workflows/build.yml \
    || fail "build workflow must verify extracted ZIP display name"
grep -q "Print :CFBundleIdentifier' build/ost-zip-check/OST.app/Contents/Info.plist" .github/workflows/build.yml \
    || fail "build workflow must verify extracted ZIP bundle identifier"
grep -q 'assert plist.get("CFBundleDisplayName") == "On-Screen Translator"' .github/workflows/build.yml \
    || fail "release workflow must verify release ZIP display name"
grep -q 'assert plist.get("CFBundleIdentifier") == "com.ost.on-screen-translator"' .github/workflows/build.yml \
    || fail "release workflow must verify release ZIP bundle identifier"
grep -q -- '-warnings-as-errors' build.sh \
    || fail "build.sh must fail on Swift warnings"
grep -q -- '-warn-concurrency' build.sh \
    || fail "build.sh must enable Swift concurrency warnings"
grep -q -- '-strict-concurrency=complete' build.sh \
    || fail "build.sh must type-check with complete Swift concurrency checking"
awk '
    /^xcrun swiftc \\/ {
        inSwiftc = 1
        sawWarnConcurrency = 0
        sawStrictConcurrency = 0
        next
    }
    inSwiftc && /-warn-concurrency/ { sawWarnConcurrency = 1 }
    inSwiftc && /-strict-concurrency=complete/ { sawStrictConcurrency = 1 }
    inSwiftc && /^[^[:space:]]/ {
        if (!(sawWarnConcurrency && sawStrictConcurrency)) exit 1
        inSwiftc = 0
    }
    END {
        if (inSwiftc && !(sawWarnConcurrency && sawStrictConcurrency)) exit 1
    }
' test.sh \
    || fail "all test.sh Swift smoke compiles must use strict Swift concurrency checking"
grep -q 'rm -rf "$APP_BUNDLE"' build.sh \
    || fail "build.sh must remove the previous app bundle to avoid stale release contents"
if grep -q '_ = CGRequestScreenCaptureAccess()' OST/Sources/Audio/SystemAudioCapture.swift; then
    fail "screen recording request result must not be ignored"
fi
grep -q 'guard CGRequestScreenCaptureAccess() else' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "screen recording request must continue when the user grants access"
grep -q 'Screen recording permission not yet granted; requesting access", category: \.audio' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "first-run permission prompts must be logged as an audio setup step, not a failure"
if grep -q 'Screen recording permission not granted", category: \.error' OST/Sources/Audio/SystemAudioCapture.swift; then
    fail "first-run permission prompts must not appear in the error log before the user responds"
fi
awk '
    /func startCapture\(\)/ { inStart = 1 }
    inStart && /if !CGPreflightScreenCaptureAccess\(\)/ { sawPreflight = 1 }
    inStart && /guard CGRequestScreenCaptureAccess\(\) else/ { sawRequestGuard = 1 }
    inStart && sawRequestGuard && /throw AudioCaptureError\.permissionDenied/ { sawDeniedInGuard = 1 }
    inStart && sawDeniedInGuard && /SCShareableContent\.current/ { sawCaptureAfterGrant = 1 }
    END {
        if (!(sawPreflight && sawRequestGuard && sawDeniedInGuard && sawCaptureAfterGrant)) exit 1
    }
' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "screen recording request must only fail on denial and continue to capture setup after approval"
grep -q 'Screen Recording and System Audio Recording permissions are required' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio capture permission errors must mention Screen Recording and System Audio Recording"
grep -q 'Speech recognition permission was denied' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech recognition permission errors must mention Speech Recognition"
grep -q 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture' OST/Sources/App/OSTApp.swift \
    || fail "menu recovery must open Screen Recording privacy settings"
grep -q 'x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition' OST/Sources/App/OSTApp.swift \
    || fail "menu recovery must open Speech Recognition privacy settings"
grep -q 'Open Screen & System Audio Recording Settings' OST/Sources/UI/MenuBarView.swift \
    || fail "menu must expose a Screen and System Audio Recording recovery action"
grep -q 'Open Speech Recognition Settings' OST/Sources/UI/MenuBarView.swift \
    || fail "menu must expose a Speech Recognition recovery action"
grep -q 'message.contains("screen recording")' OST/Sources/UI/MenuBarView.swift \
    || fail "menu recovery must detect screen recording errors"
grep -q 'message.contains("system audio recording")' OST/Sources/UI/MenuBarView.swift \
    || fail "menu recovery must detect system audio recording errors"
grep -q 'message.contains("speech recognition")' OST/Sources/UI/MenuBarView.swift \
    || fail "menu recovery must detect speech recognition errors"
awk '
    /Button\(recovery\.title\)/ { inButton = 1; sawScreenCase = 0; sawScreenAction = 0; sawSpeechCase = 0; sawSpeechAction = 0 }
    inButton && /case \.screenRecording:/ { sawScreenCase = 1 }
    inButton && sawScreenCase && /onOpenScreenRecordingSettings\(\)/ { sawScreenAction = 1 }
    inButton && /case \.speechRecognition:/ { sawSpeechCase = 1 }
    inButton && sawSpeechCase && /onOpenSpeechRecognitionSettings\(\)/ { sawSpeechAction = 1 }
    inButton && /^                    \}/ {
        if (sawScreenAction && sawSpeechAction) { found = 1 }
        inButton = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/UI/MenuBarView.swift \
    || fail "menu recovery actions must open the matching privacy settings panes"
awk '
    /SCStream start failed/ { inFailure = 1 }
    inFailure && /try\? await newStream\.stopCapture\(\)/ { sawStop = 1 }
    inFailure && /finishBufferStreamIfCurrent\(newStream\)/ { sawGuardedCleanup = 1 }
    inFailure && /stream = nil/ { sawUnconditionalStreamNil = 1 }
    inFailure && /finishBufferStream\(\)/ { sawUnconditionalFinish = 1 }
    inFailure && /throw AudioCaptureError\.streamSetupFailed/ {
        if (sawStop && sawGuardedCleanup && !sawUnconditionalStreamNil && !sawUnconditionalFinish) { found = 1 }
        inFailure = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio stream start failure must only clear buffers for the failed current stream"
awk '
    /SCStream start failed/ { inFailure = 1; sawCleanup = 0; sawPermissionCheck = 0 }
    inFailure && /finishBufferStreamIfCurrent\(newStream\)/ { sawCleanup = 1 }
    inFailure && /isPermissionError\(error\)/ { sawPermissionCheck = 1 }
    inFailure && /throw AudioCaptureError\.permissionDenied/ {
        if (sawCleanup && sawPermissionCheck) { found = 1 }
    }
    inFailure && /throw AudioCaptureError\.streamSetupFailed/ { inFailure = 0 }
    END { if (!found) exit 1 }
' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio stream start permission failures must surface Screen Recording recovery"
awk '
    /private func isPermissionError/ { inPermission = 1 }
    inPermission && /message\.contains\("permission"\)/ { sawPermission = 1 }
    inPermission && /message\.contains\("recording"\)/ { sawRecording = 1 }
    inPermission && /message\.contains\("privacy"\)/ { sawPrivacy = 1 }
    inPermission && /message\.contains\("denied"\)/ { sawDenied = 1 }
    inPermission && /message\.contains\("not authorized"\)/ { sawNotAuthorized = 1 }
    inPermission && /^    \}/ {
        if (sawPermission && sawRecording && sawPrivacy && sawDenied && sawNotAuthorized) { found = 1 }
        inPermission = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio permission error detection must recognize common macOS privacy denial wording"
awk '
    /let newStream = SCStream/ { inStart = 1; sawSetCurrent = 0 }
    inStart && /stream = newStream/ { sawSetCurrent = 1 }
    inStart && /try await newStream\.startCapture\(\)/ {
        if (sawSetCurrent) { found = 1 }
        inStart = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio capture must mark the new SCStream current before buffers can arrive"
grep -q 'private func isCurrentStream(_ candidate: SCStream) -> Bool' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio capture start must be able to detect stale streams after async start"
grep -q 'return current === candidate' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio capture stale stream detection must use SCStream identity"
awk '
    /try await newStream\.startCapture\(\)/ { inStartResult = 1; sawGuard = 0; sawThrow = 0 }
    inStartResult && /guard isCurrentStream\(newStream\) else/ { sawGuard = 1 }
    inStartResult && sawGuard && /throw CancellationError\(\)/ { sawThrow = 1 }
    inStartResult && /SCStream capture started successfully/ {
        if (sawGuard && sawThrow) { found = 1 }
        inStartResult = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio capture must detect streams that finish starting after cancellation"
awk '
    /catch is CancellationError/ { inCancel = 1; sawLog = 0; sawStop = 0; sawCleanup = 0; sawFinish = 0; sawThrow = 0 }
    inCancel && /SCStream start cancelled/ { sawLog = 1 }
    inCancel && /try\? await newStream\.stopCapture\(\)/ { sawStop = 1 }
    inCancel && /finishBufferStreamIfCurrent\(newStream\)/ { sawCleanup = 1 }
    inCancel && /capturedContinuation\?\.finish\(\)/ { sawFinish = 1 }
    inCancel && /throw CancellationError\(\)/ { sawThrow = 1 }
    inCancel && /\} catch \{/ {
        if (sawLog && sawStop && sawCleanup && sawFinish && sawThrow) { found = 1 }
        inCancel = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio capture cancellation must clean up stale streams and preserve CancellationError"
awk '
    /catch is CancellationError/ { sawCancelCatch = 1 }
    /throw AudioCaptureError\.streamSetupFailed/ {
        if (sawCancelCatch) { found = 1 }
    }
    END { if (!found) exit 1 }
' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio capture cancellation must not be wrapped as stream setup failure"
grep -q 'private func finishBufferStream()' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio buffer stream cleanup must be centralized"
awk '
    /func stopCapture\(\) async/ { inStop = 1; sawNilStreamCleanup = 0; sawActiveCleanup = 0 }
    inStop && /guard let current = stream else/ { inNilStream = 1 }
    inNilStream && /finishBufferStream\(\)/ { sawNilStreamCleanup = 1 }
    inStop && /stream = nil/ { sawStreamNil = 1 }
    sawStreamNil && /finishBufferStream\(\)/ { sawActiveCleanup = 1 }
    inStop && /try await current\.stopCapture/ {
        if (sawNilStreamCleanup && sawActiveCleanup) { found = 1 }
        inStop = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio stop cleanup must finish stale streams even when SCStream is already nil"
grep -q '_audioBuffers = nil' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio capture cleanup must clear stale audio buffer streams"
grep -q 'private func finishBufferStreamIfCurrent(_ stoppedStream: SCStream)' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "SCStream delegate cleanup must be guarded by stream identity"
grep -q 'current === stoppedStream' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "SCStream delegate cleanup must ignore stale stopped streams"
grep -q 'struct AudioSampleBuffer: @unchecked Sendable' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio sample buffers must cross concurrency boundaries through an explicit Sendable wrapper"
grep -q 'private func continuationIfCurrent(_ outputStream: SCStream) -> AsyncStream<AudioSampleBuffer>.Continuation?' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "SCStream output must capture the current continuation under the stream identity lock"
grep -q 'guard let current = _stream, current === outputStream else { return nil }' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "SCStream output must ignore buffers from stale streams"
grep -q 'guard let streamContinuation = continuationIfCurrent(stream) else { return }' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "SCStream output must not read continuation separately after the stale-stream guard"
grep -q 'streamContinuation.yield(AudioSampleBuffer(sampleBuffer: sampleBuffer))' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "SCStream output must yield through the captured continuation"
awk '
    /func stream\(_ stream: SCStream, didStopWithError error: Error\)/ { inDelegate = 1; sawGuardedFinish = 0; sawUnconditionalFinish = 0; sawStreamNil = 0 }
    inDelegate && /finishBufferStreamIfCurrent\(stream\)/ { sawGuardedFinish = 1 }
    inDelegate && /finishBufferStream\(\)/ { sawUnconditionalFinish = 1 }
    inDelegate && /self\.stream = nil/ { sawStreamNil = 1 }
    inDelegate && /^    \}/ {
        if (sawGuardedFinish && !sawUnconditionalFinish && !sawStreamNil) { found = 1 }
        inDelegate = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "SCStream delegate stop must not clear a newer active stream"
awk '
    /didOutputSampleBuffer sampleBuffer/ { inOutput = 1; sawGuard = 0; sawIncrement = 0; sawYield = 0 }
    inOutput && /guard let streamContinuation = continuationIfCurrent\(stream\) else/ { sawGuard = 1 }
    inOutput && /incrementBufferCount\(\)/ { sawIncrement = 1 }
    inOutput && /streamContinuation\.yield\(AudioSampleBuffer\(sampleBuffer: sampleBuffer\)\)/ { sawYield = 1 }
    inOutput && /^    \}/ {
        if (sawGuard && sawIncrement && sawYield) { found = 1 }
        inOutput = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "SCStream output must capture the current continuation before yielding buffers"
awk '
    /private func finishBufferStream/ { inFinish = 1; sawLock = 0; sawContinuationNil = 0; sawBuffersNil = 0; sawFinish = 0 }
    inFinish && /stateLock\.withLock/ { sawLock = 1 }
    inFinish && /_continuation = nil/ { sawContinuationNil = 1 }
    inFinish && /_audioBuffers = nil/ { sawBuffersNil = 1 }
    inFinish && /streamContinuation\?\.finish\(\)/ { sawFinish = 1 }
    inFinish && /^    \}/ {
        if (sawLock && sawContinuationNil && sawBuffersNil && sawFinish) { found = 1 }
        inFinish = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio buffer stream cleanup must atomically detach continuation before finishing it"
grep -q 'private func incrementBufferCount() -> Int' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio buffer count increments must be protected by one lock operation"
if grep -q '[^_]bufferCount +=' OST/Sources/Audio/SystemAudioCapture.swift; then
    fail "audio buffer count must not use non-atomic computed-property increments"
fi
grep -q 'config.capturesAudio = true' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "system audio capture must keep audio enabled"
grep -q 'config.excludesCurrentProcessAudio = true' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "system audio capture must exclude OST audio"
grep -q 'config.sampleRate = 16000' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "system audio capture must use 16kHz audio for SFSpeechRecognizer"
grep -q 'config.channelCount = 1' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "system audio capture must use mono audio for SFSpeechRecognizer"
grep -q 'config.width = 2' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "system audio capture must keep video dimensions minimal"
grep -q 'config.height = 2' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "system audio capture must keep video dimensions minimal"
grep -q 'config.minimumFrameInterval = CMTime(value: 1, timescale: 1)' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "system audio capture must keep video frame rate minimal"
grep -q 'config.showsCursor = false' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "system audio capture must not capture the cursor"
awk '
    /guard !content\.displays\.isEmpty else/ { sawGuard = 1 }
    /let display = content\.displays\[0\]/ {
        if (sawGuard) { found = 1 }
    }
    END { if (!found) exit 1 }
' OST/Sources/Audio/SystemAudioCapture.swift \
    || fail "audio capture must verify a display exists before indexing the display list"
grep -q 'self.restartRetryCount = 0' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech recognition start must reset restart retry count"
grep -q 'self.finalizedText = text' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech final results must publish the finalized text"
grep -q 'let retryGeneration = taskGeneration' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech recognition delayed retries must capture task generation"
grep -q 'self.taskGeneration == retryGeneration' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech recognition delayed retries must ignore stale generations"
grep -q 'let wasActive = isActive' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech language changes must preserve active recognition intent"
awk '
    /func startRecognition\(useOnDevice: Bool = true\) async throws/ { inStart = 1; sawAuthorization = 0; sawActive = 0 }
    inStart && /try await requestAuthorization\(\)/ { sawAuthorization = 1 }
    inStart && sawAuthorization && /isActive = true/ { sawActive = 1 }
    inStart && /try beginRecognitionTask\(\)/ {
        if (sawAuthorization && sawActive) { found = 1 }
        inStart = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech recognition must continue into recognition startup after authorization succeeds"
awk '
    /private func requestAuthorization\(\) async throws/ { inAuth = 1; sawRequest = 0; sawAuthorizedGuard = 0 }
    inAuth && /SFSpeechRecognizer\.requestAuthorization/ { sawRequest = 1 }
    inAuth && /guard status == \.authorized else/ { sawAuthorizedGuard = 1 }
    inAuth && /throw SpeechRecognizerError\.notAuthorized\(status\)/ {
        if (sawRequest && sawAuthorizedGuard) { found = 1 }
        inAuth = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech recognition authorization must only fail for non-authorized statuses"
awk '
    /func startRecognition\(useOnDevice: Bool = true\) async throws/ { inStart = 1; sawBegin = 0; sawCatch = 0; sawInactive = 0; sawGeneration = 0; sawEnd = 0; sawCancel = 0; sawRequestNil = 0; sawTaskNil = 0; sawClear = 0 }
    inStart && /try beginRecognitionTask\(\)/ { sawBegin = 1 }
    inStart && sawBegin && /} catch \{/ { sawCatch = 1 }
    inStart && sawCatch && /isActive = false/ { sawInactive = 1 }
    inStart && sawCatch && /taskGeneration \+= 1/ { sawGeneration = 1 }
    inStart && sawCatch && /recognitionRequest\?\.endAudio\(\)/ { sawEnd = 1 }
    inStart && sawCatch && /recognitionTask\?\.cancel\(\)/ { sawCancel = 1 }
    inStart && sawCatch && /recognitionRequest = nil/ { sawRequestNil = 1 }
    inStart && sawCatch && /recognitionTask = nil/ { sawTaskNil = 1 }
    inStart && sawCatch && /currentText = ""/ { sawClear = 1 }
    inStart && sawCatch && /throw error/ {
        if (sawInactive && sawGeneration && sawEnd && sawCancel && sawRequestNil && sawTaskNil && sawClear) { found = 1 }
        inStart = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech recognition start failures must deactivate and clear volatile task state before rethrowing"
awk '
    /guard let recognizer, recognizer\.isAvailable else/ { inUnavailable = 1; sawGeneration = 0; sawEnd = 0; sawCancel = 0; sawRequestNil = 0; sawTaskNil = 0 }
    inUnavailable && /taskGeneration \+= 1/ { sawGeneration = 1 }
    inUnavailable && /recognitionRequest\?\.endAudio\(\)/ { sawEnd = 1 }
    inUnavailable && /recognitionTask\?\.cancel\(\)/ { sawCancel = 1 }
    inUnavailable && /recognitionRequest = nil/ { sawRequestNil = 1 }
    inUnavailable && /recognitionTask = nil/ { sawTaskNil = 1 }
    inUnavailable && /throw SpeechRecognizerError\.recognizerUnavailable/ {
        if (sawGeneration && sawEnd && sawCancel && sawRequestNil && sawTaskNil) { found = 1 }
        inUnavailable = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech recognizer unavailable failures must invalidate stale callbacks and clear stale requests"
grep -q 'let supportsOnDeviceRecognition = recognizer.supportsOnDeviceRecognition' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech recognition must log whether the selected recognizer supports on-device mode"
grep -q 'let usesOnDeviceRecognition = useOnDevice && supportsOnDeviceRecognition' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech recognition logs must report the effective on-device mode"
grep -q 'On-device recognition unavailable' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech recognition must log when it falls back from requested on-device mode"
grep -q 'Starting recognition task (onDevice: \\(usesOnDeviceRecognition), supportsOnDevice: \\(supportsOnDeviceRecognition)' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech recognition start logs must include effective and supported on-device state"
awk '
    /Partial result with error, restarting/ { inPartialError = 1; sawClear = 0 }
    inPartialError && /self\.currentText = ""/ { sawClear = 1 }
    inPartialError && /self\.restartRecognition\(\)/ {
        if (sawClear) { found = 1 }
        inPartialError = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "speech partial-result error restarts must clear currentText so AppState consumes remaining live text"
awk '
    /Restart failed after/ { inTerminal = 1; sawInactive = 0; sawEnd = 0; sawCancel = 0; sawRequestNil = 0; sawTaskNil = 0; sawClear = 0 }
    inTerminal && /isActive = false/ { sawInactive = 1 }
    inTerminal && /recognitionRequest\?\.endAudio\(\)/ { sawEnd = 1 }
    inTerminal && /recognitionTask\?\.cancel\(\)/ { sawCancel = 1 }
    inTerminal && /recognitionRequest = nil/ { sawRequestNil = 1 }
    inTerminal && /recognitionTask = nil/ { sawTaskNil = 1 }
    inTerminal && /currentText = ""/ { sawClear = 1 }
    inTerminal && /recognitionError = error/ {
        if (sawInactive && sawEnd && sawCancel && sawRequestNil && sawTaskNil && sawClear) { found = 1 }
        inTerminal = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Speech/SpeechRecognizer.swift \
    || fail "terminal speech restart failures must deactivate recognition before publishing the error"
grep -q 'beginStartingCapture()' OST/Sources/App/OSTApp.swift \
    || fail "OSTApp.startCapture must mark the full preflight as starting"
grep -q '@State private var captureLifecycleGeneration: Int = 0' OST/Sources/App/OSTApp.swift \
    || fail "OSTApp must track capture start/stop generations"
grep -q 'private func isCurrentCaptureStart(_ generation: Int) -> Bool' OST/Sources/App/OSTApp.swift \
    || fail "OSTApp must expose a capture-start freshness guard"
awk '
    /private func startCapture\(\) async/ { inStart = 1; sawIncrement = 0; sawLet = 0; sawLanguageGuard = 0; sawPrepareGuard = 0; sawAppStart = 0; sawPostStartGuard = 0; sawStopOnStale = 0 }
    inStart && /captureLifecycleGeneration \+= 1/ { sawIncrement = 1 }
    inStart && /let startGeneration = captureLifecycleGeneration/ { sawLet = 1 }
    inStart && /await appState\.changeSourceLanguage/ { sawAfterLanguage = 1 }
    inStart && sawAfterLanguage && /guard isCurrentCaptureStart\(startGeneration\) else/ { sawLanguageGuard = 1 }
    inStart && /await prepareTranslationForCurrentSettings/ { sawAfterPrepare = 1 }
    inStart && sawAfterPrepare && /guard isCurrentCaptureStart\(startGeneration\) else/ { sawPrepareGuard = 1 }
    inStart && /await appState\.startCapture/ { sawAppStart = 1 }
    inStart && sawAppStart && /guard isCurrentCaptureStart\(startGeneration\) else/ { sawPostStartGuard = 1 }
    inStart && sawPostStartGuard && /await appState\.stopCapture\(\)/ { sawStopOnStale = 1 }
    inStart && /if appState\.errorMessage != nil/ {
        if (sawIncrement && sawLet && sawLanguageGuard && sawPrepareGuard && sawAppStart && sawPostStartGuard && sawStopOnStale) { found = 1 }
        inStart = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "stale async capture starts must be cancelled and cleaned up after stop/quit"
awk '
    /await appState\.changeSourceLanguage/ { inLanguageStart = 1; sawErrorGuard = 0; sawInvalidate = 0; sawHide = 0 }
    inLanguageStart && /guard appState\.errorMessage == nil else/ { sawErrorGuard = 1 }
    inLanguageStart && sawErrorGuard && /appState\.translationService\.invalidateSession\(\)/ { sawInvalidate = 1 }
    inLanguageStart && sawErrorGuard && /windowManager\.hideOverlay\(\)/ { sawHide = 1 }
    inLanguageStart && sawErrorGuard && /^        \}/ {
        if (sawInvalidate && sawHide) { found = 1 }
        inLanguageStart = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "capture start language failures must clear stale translation state and overlay"
awk '
    /private func startCapture\(\) async/ { inStart = 1; sawOverlay = 0; sawPrepare = 0; sawAppStart = 0 }
    inStart && /windowManager\.showOverlay\(appState: appState, settings: settings\)/ { sawOverlay = 1 }
    inStart && /await prepareTranslationForCurrentSettings\(waitForOverlayRender: true\)/ {
        if (!sawOverlay) exit 1
        sawPrepare = 1
    }
    inStart && /await appState\.startCapture/ {
        if (!sawPrepare) exit 1
        sawAppStart = 1
    }
    inStart && /if appState\.errorMessage != nil/ {
        if (sawOverlay && sawPrepare && sawAppStart) { found = 1 }
        inStart = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "OSTApp.startCapture must show the overlay before preparing translation and starting capture"
awk '
    /private func prepareTranslationForCurrentSettings/ { inPrepare = 1; sawWaitBlock = 0; sawSleep = 0; sawConfigure = 0; sawReadyWait = 0 }
    inPrepare && /if waitForOverlayRender/ { sawWaitBlock = 1 }
    inPrepare && sawWaitBlock && /Task\.sleep\(for: \.milliseconds\(200\)\)/ { sawSleep = 1 }
    inPrepare && /appState\.translationService\.configure/ {
        if (!sawSleep) exit 1
        sawConfigure = 1
    }
    inPrepare && /translationService\.waitForSessionReady\(timeout: 1\.0\)/ {
        if (!sawConfigure) exit 1
        sawReadyWait = 1
    }
    inPrepare && /^    \}/ {
        if (sawWaitBlock && sawSleep && sawConfigure && sawReadyWait) { found = 1 }
        inPrepare = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "translation setup must wait for overlay render before configuring the TranslationSession"
awk '
    /private func stopCapture\(\) async/ { inStop = 1; sawCapture = 0; sawLanguage = 0 }
    inStop && /captureLifecycleGeneration \+= 1/ { sawCapture = 1 }
    inStop && /languageSettingsChangeGeneration \+= 1/ { sawLanguage = 1 }
    inStop && /await appState\.stopCapture\(\)/ {
        if (sawCapture && sawLanguage) { found = 1 }
        inStop = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "stop capture must invalidate in-flight async capture starts"
grep -q 'var onCaptureStoppedWithError: (() -> Void)?' OST/Sources/App/AppState.swift \
    || fail "AppState must expose a reliable internal failure cleanup callback"
grep -q 'appState.onCaptureStoppedWithError = handleCaptureStoppedWithError' OST/Sources/App/OSTApp.swift \
    || fail "OSTApp must register cleanup for AppState-owned capture stops"
grep -q 'private func handleCaptureStoppedWithError()' OST/Sources/App/OSTApp.swift \
    || fail "OSTApp must centralize cleanup for AppState-owned capture stops"
awk '
    /private func handleCaptureStoppedWithError/ { inHandler = 1; sawErrorGuard = 0; sawCaptureGeneration = 0; sawGeneration = 0; sawInvalidate = 0; sawHide = 0 }
    inHandler && /appState\.errorMessage != nil/ { sawErrorGuard = 1 }
    inHandler && /captureLifecycleGeneration \+= 1/ { sawCaptureGeneration = 1 }
    inHandler && /languageSettingsChangeGeneration \+= 1/ { sawGeneration = 1 }
    inHandler && /invalidateSession\(preservingPendingTranslations: true\)/ { sawInvalidate = 1 }
    inHandler && /windowManager\.hideOverlay\(\)/ { sawHide = 1 }
    inHandler && /^    \}/ {
        if (sawErrorGuard && sawCaptureGeneration && sawGeneration && sawInvalidate && sawHide) { found = 1 }
        inHandler = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "AppState-owned capture failures must hide stale overlays and preserve queued translations"
awk '
    /Audio capture stopped unexpectedly/ { inAudioFailure = 1; sawStop = 0 }
    inAudioFailure && /await self\.stopCapture\(\)/ { sawStop = 1 }
    inAudioFailure && /self\.onCaptureStoppedWithError\?\(\)/ {
        if (sawStop) { found = 1 }
        inAudioFailure = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "unexpected audio stream stops must notify OSTApp after the pipeline is stopped"
awk '
    /Recognition stopped after retries/ { inRecognitionFailure = 1; sawStop = 0 }
    inRecognitionFailure && /await self\.stopCapture\(\)/ { sawStop = 1 }
    inRecognitionFailure && /self\.onCaptureStoppedWithError\?\(\)/ {
        if (sawStop) { found = 1 }
        inRecognitionFailure = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "recognition retry exhaustion must notify OSTApp after the pipeline is stopped"
awk '
    /await changeSourceLanguage\(to: target\.speechLocale/ { inAutoDetectChange = 1; sawError = 0; sawNotify = 0; sawReturn = 0 }
    inAutoDetectChange && /if self\.errorMessage != nil/ { sawError = 1 }
    inAutoDetectChange && sawError && /self\.onCaptureStoppedWithError\?\(\)/ { sawNotify = 1 }
    inAutoDetectChange && sawNotify && /return/ { sawReturn = 1 }
    inAutoDetectChange && /Reconfigure translation source language/ {
        if (sawError && sawNotify && sawReturn) { found = 1 }
        inAutoDetectChange = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "auto-detected language change failures must notify OSTApp before translation refresh exits"
grep -q 'func beginStartingCapture() -> Bool' OST/Sources/App/AppState.swift \
    || fail "AppState must expose a guarded start marker"
grep -q 'guard !isCapturing else { return }' OST/Sources/App/AppState.swift \
    || fail "AppState.startCapture must reject duplicate capture starts"
awk '
    /func startCapture\(saveSession:/ { inStart = 1; sawDuplicateGuard = 0; sawPreflightGuard = 0 }
    inStart && /guard !isCapturing else \{ return \}/ { sawDuplicateGuard = 1 }
    inStart && sawDuplicateGuard && /guard isStartingCapture else \{ return \}/ { sawPreflightGuard = 1 }
    inStart && /Requesting speech recognition authorization/ {
        if (sawDuplicateGuard && sawPreflightGuard) { found = 1 }
        inStart = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "AppState.startCapture must not request speech authorization without a start preflight"
awk '
    /func startCapture\(saveSession:/ { inStart = 1; sawSpeechStart = 0; sawSpeechGuard = 0; sawSpeechStop = 0; sawSpeechFinish = 0; sawAudioStart = 0; sawAudioGuard = 0; sawAudioStop = 0; sawAudioFinish = 0 }
    inStart && /try await speechRecognizer\.startRecognition/ { sawSpeechStart = 1 }
    inStart && sawSpeechStart && /guard isStartingCapture else/ { sawSpeechGuard = 1 }
    inStart && sawSpeechGuard && /speechRecognizer\.stopRecognition\(\)/ { sawSpeechStop = 1 }
    inStart && sawSpeechStop && /finishStartingCapture\(\)/ { sawSpeechFinish = 1 }
    inStart && /let buffers = try await audioCapture\.startCapture\(\)/ { sawAudioStart = 1 }
    inStart && sawAudioStart && /guard isStartingCapture else/ { sawAudioGuard = 1 }
    inStart && sawAudioGuard && /await audioCapture\.stopCapture\(\)/ { sawAudioStop = 1 }
    inStart && sawAudioStop && /finishStartingCapture\(\)/ { sawAudioFinish = 1 }
    inStart && /isCapturing = true/ {
        if (sawSpeechStart && sawSpeechGuard && sawSpeechStop && sawSpeechFinish && sawAudioStart && sawAudioGuard && sawAudioStop && sawAudioFinish) { found = 1 }
        inStart = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "AppState.startCapture must clean up and clear starting state if stop occurs while capture is still starting"
awk '
    /func startCapture\(saveSession:/ { inStart = 1; sawCapturing = 0; sawFinishAfterSuccess = 0; sawFailureLog = 0; sawFinishAfterFailure = 0 }
    inStart && /isCapturing = true/ { sawCapturing = 1 }
    inStart && sawCapturing && /finishStartingCapture\(\)/ { sawFinishAfterSuccess = 1 }
    inStart && /AppLogger\.shared\.log\("Capture failed:/ { sawFailureLog = 1 }
    inStart && sawFailureLog && /finishStartingCapture\(\)/ { sawFinishAfterFailure = 1 }
    inStart && /^    \}/ {
        if (sawFinishAfterSuccess && sawFinishAfterFailure) { found = 1 }
        inStart = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "AppState.startCapture must clear starting state after successful or failed starts"
awk '
    /\} catch \{/ { inCatch = 1; sawCancelledGuard = 0; sawCancellationError = 0; sawCancelledLog = 0; sawStopSpeech = 0; sawStopAudio = 0; sawFinish = 0; sawReturn = 0 }
    inCatch && /if !isStartingCapture/ { sawCancelledGuard = 1 }
    inCatch && /error is CancellationError/ { sawCancellationError = 1 }
    inCatch && /Capture start cancelled/ { sawCancelledLog = 1 }
    inCatch && /speechRecognizer\.stopRecognition\(\)/ { sawStopSpeech = 1 }
    inCatch && /await audioCapture\.stopCapture\(\)/ { sawStopAudio = 1 }
    inCatch && /finishStartingCapture\(\)/ { sawFinish = 1 }
    inCatch && /return/ { sawReturn = 1 }
    inCatch && /AppLogger\.shared\.log\("Capture failed:/ {
        if (sawCancelledGuard && sawCancellationError && sawCancelledLog && sawStopSpeech && sawStopAudio && sawFinish && sawReturn) { found = 1 }
        inCatch = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "cancelled capture starts must not publish user-visible capture errors"
awk '
    /func startCapture\(saveSession:/ { inStart = 1; sawReset = 0 }
    inStart && /resetDisplayStateForNewCapture\(\)/ { sawReset = 1 }
    inStart && /AppLogger\.shared\.log\("Starting capture/ {
        if (sawReset) { found = 1 }
        inStart = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "AppState.startCapture must clear stale subtitle display state before async capture setup"
grep -q 'lastSinkCurrentText = ""' OST/Sources/App/AppState.swift \
    || fail "new capture display reset must clear stale speech sink tracking"
grep -q 'Date().addingTimeInterval(-2.0)' OST/Sources/App/AppState.swift \
    || fail "duplicate subtitle suppression must only cover a short 2-second window"
grep -q 'subtitleEntries.suffix(2)' OST/Sources/App/AppState.swift \
    || fail "duplicate subtitle suppression must only inspect the two most recent entries"
if grep -q 'Date().addingTimeInterval(-5.0)\|subtitleEntries.suffix(4)' OST/Sources/App/AppState.swift; then
    fail "duplicate subtitle suppression must not hide legitimate repeated speech with a broad window"
fi
grep -q 'private func splitLongToken' OST/Sources/App/AppState.swift \
    || fail "subtitle chunking must split long no-space tokens for CJK and URL-like text"
grep -q 'limitedBy: text.endIndex' OST/Sources/App/AppState.swift \
    || fail "long-token subtitle chunking must use safe String index bounds"
grep -q 'chunks.append(contentsOf: splitLongToken(word, maxChars: maxChars))' OST/Sources/App/AppState.swift \
    || fail "sentence chunking must apply long-token splitting before appending chunks"
grep -q 'private func stripCharacterOverlap' OST/Sources/App/AppState.swift \
    || fail "recognizer restart overlap stripping must handle CJK and URL-like no-space text"
grep -q 'tail.suffix(overlapLength)' OST/Sources/App/AppState.swift \
    || fail "character overlap stripping must compare suffixes of the previous consumed tail"
grep -q 'newText.hasPrefix(suffix)' OST/Sources/App/AppState.swift \
    || fail "character overlap stripping must compare the new text prefix"
grep -q 'guard suffix.count >= 4 else { continue }' OST/Sources/App/AppState.swift \
    || fail "word overlap stripping must ignore very short overlaps that can remove valid new text"
grep -q 'while overlapLength >= 4' OST/Sources/App/AppState.swift \
    || fail "character overlap stripping must require a meaningful minimum overlap"
grep -q 'return stripCharacterOverlap(newText: newText, tail: tail)' OST/Sources/App/AppState.swift \
    || fail "word overlap stripping must fall back to character overlap stripping"
awk '
    /let stripped = self\.stripOverlap/ { inOverlap = 1; sawFound = 0; sawClearFound = 0; sawLongEnough = 0; sawClearLongEnough = 0; sawUnconditionalClear = 0 }
    inOverlap && /if stripped != currentText/ { sawFound = 1 }
    inOverlap && sawFound && /self\.lastConsumedTail = ""/ { sawClearFound = 1 }
    inOverlap && /\} else if currentText\.count >= self\.lastConsumedTail\.count/ { sawLongEnough = 1 }
    inOverlap && sawLongEnough && /self\.lastConsumedTail = ""/ { sawClearLongEnough = 1 }
    inOverlap && /\/\/ Clear tail after first use in new session/ { sawUnconditionalClear = 1 }
    inOverlap && /^[[:space:]]*\} else \{/ {
        if (sawClearFound && sawLongEnough && sawClearLongEnough && !sawUnconditionalClear) { found = 1 }
        inOverlap = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "recognizer restart overlap tail must survive short undecidable partial results"
grep -q 'activeUseOnDeviceRecognition' OST/Sources/App/OSTApp.swift \
    || fail "OSTApp must track the active on-device recognition setting"
grep -q 'activeTargetLanguageSetting' OST/Sources/App/OSTApp.swift \
    || fail "OSTApp must track the active target language setting"
grep -q 'let requestedSourceLanguage = settings.sourceLanguage' OST/Sources/App/OSTApp.swift \
    || fail "runtime language changes must snapshot source language settings before launching async work"
grep -q 'let requestedTargetLanguage = settings.targetLanguage' OST/Sources/App/OSTApp.swift \
    || fail "runtime language changes must snapshot target language settings before launching async work"
grep -q 'let requestedUseOnDeviceRecognition = settings.useOnDeviceRecognition' OST/Sources/App/OSTApp.swift \
    || fail "runtime language changes must snapshot recognition settings before launching async work"
grep -q 'languageSettingsChangeGeneration += 1' OST/Sources/App/OSTApp.swift \
    || fail "runtime language changes must advance a generation token"
grep -q 'let changeGeneration = languageSettingsChangeGeneration' OST/Sources/App/OSTApp.swift \
    || fail "runtime language changes must capture the generation for async work"
grep -q 'private func isCurrentLanguageSettingsChange(_ generation: Int) -> Bool' OST/Sources/App/OSTApp.swift \
    || fail "runtime language changes must reject stale async work"
grep -q 'generation == languageSettingsChangeGeneration' OST/Sources/App/OSTApp.swift \
    || fail "runtime language change generation checks must compare against the current token"
awk '
    /private func applyLanguageSettingsWhileCapturing/ { inApply = 1; sawSourceChanged = 0; sawDisable = 0 }
    inApply && /let sourceSettingChanged = requestedSourceLanguage != activeSourceLanguageSetting/ { sawSourceChanged = 1 }
    inApply && /if sourceSettingChanged && !isAuto/ { inManualSwitch = 1 }
    inManualSwitch && /appState\.disableAutoDetect\(\)/ { sawDisable = 1 }
    inApply && /await appState\.changeSourceLanguage/ {
        if (sawSourceChanged && sawDisable) { found = 1 }
        inApply = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "switching from Auto to a manual source must invalidate auto-detection before awaiting language changes"
grep -q 'let switchedToAutoSource = sourceSettingChanged && isAuto' OST/Sources/App/OSTApp.swift \
    || fail "runtime language changes must distinguish switching to Auto from on-device-only changes"
awk '
    /private func applyLanguageSettingsWhileCapturing/ { inApply = 1; sawSwitchFlag = 0; sawGuard = 0 }
    inApply && /let switchedToAutoSource = sourceSettingChanged && isAuto/ { sawSwitchFlag = 1 }
    inApply && /if switchedToAutoSource/ { sawGuard = 1 }
    inApply && /appState\.enableAutoDetect\(\)/ {
        if (sawSwitchFlag && sawGuard) { found = 1 }
        inApply = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "on-device-only changes while Auto is active must not reset detected language state"
awk '
    /private func applyLanguageSettingsWhileCapturing/ { inApply = 1; depth = 0; sawChanged = 0; sawInvalidate = 0; sawClear = 0; sawPrepare = 0; sawRefresh = 0 }
    inApply {
        depth += gsub(/\{/, "{")
        if (/let translationSettingChanged/) { sawChanged = 1 }
        if (sawChanged && /appState\.translationService\.invalidateSession\(\)/) { sawInvalidate = 1 }
        if (sawInvalidate && /appState\.clearVisibleTranslationsForLanguageChange\(\)/) { sawClear = 1 }
        if (sawClear && /sourceLanguageSetting: requestedSourceLanguage/) { sawSource = 1 }
        if (sawSource && /targetLanguageSetting: requestedTargetLanguage/) { sawTarget = 1 }
        if (sawTarget && /waitForOverlayRender: false/) { sawPrepare = 1 }
        if (sawPrepare && /appState\.refreshVisibleTranslationsForLanguageChange\(\)/) { sawRefresh = 1 }
        depth -= gsub(/\}/, "}")
        if (inApply && depth == 0) {
            if (sawRefresh) { found = 1 }
            inApply = 0
        }
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "language changes while capturing must reconfigure translation and refresh visible translations"
awk '
    /private func applyLanguageSettingsWhileCapturing/ { inApply = 1; sawChange = 0; sawStale = 0; sawReapply = 0 }
    inApply && /await appState\.changeSourceLanguage/ { sawChange = 1 }
    inApply && /guard isCurrentLanguageSettingsChange\(changeGeneration\) else/ { sawStale = 1 }
    inApply && /applyLanguageSettingsWhileCapturing\(\)/ {
        if (sawChange && sawStale) { sawReapply = 1 }
    }
    inApply && /^    \}/ {
        if (sawReapply) { found = 1 }
        inApply = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "stale runtime language change tasks must reapply the latest settings"
awk '
    /private func applyLanguageSettingsWhileCapturing/ { inApply = 1; sawChange = 0; sawErrorCleanup = 0 }
    inApply && /await appState\.changeSourceLanguage/ { sawChange = 1 }
    inApply && /guard isCurrentLanguageSettingsChange\(changeGeneration\) else/ {
        if (sawChange && !sawErrorCleanup) { bad = 1 }
    }
    inApply && /guard appState\.errorMessage == nil else/ { sawErrorCleanup = 1 }
    inApply && /^    \}/ {
        if (sawChange && sawErrorCleanup && !bad) { found = 1 }
        inApply = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "runtime language change failures must clean up overlay before stale-generation reapply checks"
awk '
    /private func applyLanguageSettingsWhileCapturing/ { inApply = 1; depth = 0; inTranslationChanged = 0; sawPrepareOutside = 0 }
    inApply {
        depth += gsub(/\{/, "{")
        if (/if translationSettingChanged/) { inTranslationChanged = 1 }
        if (/await prepareTranslationForCurrentSettings\(waitForOverlayRender: false\)/ && !inTranslationChanged) { sawPrepareOutside = 1 }
        depth -= gsub(/\}/, "}")
        if (inTranslationChanged && depth == 2) { inTranslationChanged = 0 }
        if (inApply && depth == 0) {
            if (!sawPrepareOutside) { found = 1 }
            inApply = 0
        }
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "on-device-only changes while capturing must not reconfigure translation"
grep -q 'refreshTranslationAfterOverlayChange' OST/Sources/App/OSTApp.swift \
    || fail "display mode changes must refresh translation after rehosting the overlay"
awk '
    /private func refreshTranslationAfterOverlayChange/ { inRefresh = 1; sawGeneration = 0; sawPrepare = 0; sawGuard = 0; sawRefresh = 0 }
    inRefresh && /let changeGeneration = languageSettingsChangeGeneration/ { sawGeneration = 1 }
    inRefresh && /await prepareTranslationForCurrentSettings\(waitForOverlayRender: true\)/ { sawPrepare = 1 }
    inRefresh && /guard isCurrentLanguageSettingsChange\(changeGeneration\) else/ { sawGuard = 1 }
    inRefresh && /appState\.refreshVisibleTranslationsForLanguageChange\(\)/ { sawRefresh = 1 }
    inRefresh && /^    \}/ {
        if (sawGeneration && sawPrepare && sawGuard && sawRefresh) { found = 1 }
        inRefresh = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "display mode changes must retry visible translations after the rehosted translation session is ready"
awk '
    /onDisplayModeChanged:/ { inDisplay = 1; sawInvalidate = 0; sawShow = 0 }
    inDisplay && /appState\.translationService\.invalidateSession\(\)/ { sawInvalidate = 1 }
    inDisplay && /windowManager\.showOverlay/ {
        sawShow = 1
        if (sawInvalidate) { found = 1 }
    }
    inDisplay && /refreshTranslationAfterOverlayChange/ { inDisplay = 0 }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "display mode changes must invalidate stale translation sessions before rehosting"
awk '
    /if appState.errorMessage != nil/ { inFailure = 1 }
    inFailure && /appState\.translationService\.invalidateSession\(\)/ { found = 1 }
    inFailure && /windowManager\.hideOverlay\(\)/ { exit found ? 0 : 1 }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "start failure cleanup must invalidate translation session before hiding overlay"
awk '
    /guard appState.errorMessage == nil else/ { inFailure = 1; foundInvalidate = 0; foundHide = 0 }
    inFailure && /appState\.translationService\.invalidateSession\(\)/ { foundInvalidate = 1 }
    inFailure && /windowManager\.hideOverlay\(\)/ { foundHide = 1 }
    inFailure && /return/ {
        if (foundInvalidate && foundHide) { found = 1 }
        inFailure = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "runtime language change failure must clean up translation and overlay"
grep -q 'useOnDeviceBinding' OST/Sources/UI/LanguagePickerView.swift \
    || fail "on-device recognition toggle must notify the running app"
grep -q 'when the selected language model is available' OST/Sources/UI/LanguagePickerView.swift \
    || fail "on-device recognition settings must not promise local-only recognition without an available model"
for language_case in \
    'case english = "en-US"' \
    'case chineseSimplified = "zh-Hans"' \
    'case japanese = "ja-JP"' \
    'case korean = "ko-KR"'; do
    grep -qF "$language_case" OST/Sources/Speech/SupportedLanguages.swift \
        || fail "SupportedLanguages is missing: $language_case"
done
for speech_locale in \
    'Locale(identifier: "en-US")' \
    'Locale(identifier: "zh-CN")' \
    'Locale(identifier: "ja-JP")' \
    'Locale(identifier: "ko-KR")'; do
    grep -qF "$speech_locale" OST/Sources/Speech/SupportedLanguages.swift \
        || fail "SupportedLanguages speech locale is missing: $speech_locale"
done
for translation_locale in \
    'Locale.Language(identifier: "en")' \
    'Locale.Language(identifier: "zh-Hans")' \
    'Locale.Language(identifier: "ja")' \
    'Locale.Language(identifier: "ko")'; do
    grep -qF "$translation_locale" OST/Sources/Speech/SupportedLanguages.swift \
        || fail "SupportedLanguages translation locale is missing: $translation_locale"
done
grep -q 'case \.simplifiedChinese, \.traditionalChinese: matched = \.chineseSimplified' OST/Sources/App/AppState.swift \
    || fail "auto language detection must map Chinese speech to the supported Simplified Chinese option"
grep -q 'private var autoDetectGeneration: Int = 0' OST/Sources/App/AppState.swift \
    || fail "auto language detection must track async generation"
grep -q '@Published private(set) var detectedLanguage: SupportedLanguage?' OST/Sources/App/AppState.swift \
    || fail "auto language detection must retain the detected language as a typed value"
if grep -R 'detectedLanguageDisplay' OST/Sources >/dev/null; then
    fail "auto language detection must not keep duplicate display-string state"
fi
grep -q 'let detectionGeneration = autoDetectGeneration' OST/Sources/App/AppState.swift \
    || fail "auto language detection tasks must capture the active generation"
grep -q 'detectedLanguage = target' OST/Sources/App/AppState.swift \
    || fail "auto language detection must store the matched supported language"
awk '
    /func enableAutoDetect\(\)/ { inEnable = 1 }
    inEnable && /autoDetectGeneration \+= 1/ { sawEnable = 1; inEnable = 0 }
    /func disableAutoDetect\(\)/ { inDisable = 1 }
    inDisable && /autoDetectGeneration \+= 1/ { sawDisable = 1; inDisable = 0 }
    END { if (!(sawEnable && sawDisable)) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "auto language detection must invalidate stale tasks when toggled"
awk '
    /Task \{/ { inTask = 1; sawEnabled = 0; sawGeneration = 0; sawWait = 0; sawPostWaitEnabled = 0; sawPostWaitGeneration = 0 }
    inTask && /self\.autoDetectEnabled/ { sawEnabled = 1 }
    inTask && /self\.autoDetectGeneration == detectionGeneration/ { sawGeneration = 1 }
    inTask && /await changeSourceLanguage/ {
        if (sawEnabled && sawGeneration) { foundBefore = 1 }
    }
    inTask && /translationService\.waitForSessionReady\(timeout: 1\.0\)/ { sawWait = 1 }
    inTask && sawWait && /self\.autoDetectEnabled/ { sawPostWaitEnabled = 1 }
    inTask && sawWait && /self\.autoDetectGeneration == detectionGeneration/ { sawPostWaitGeneration = 1 }
    inTask && /refreshVisibleTranslationsForLanguageChange\(\)/ {
        if (sawEnabled && sawGeneration && foundBefore && sawWait && sawPostWaitEnabled && sawPostWaitGeneration) { foundAfter = 1 }
        inTask = 0
    }
    END { if (!(foundBefore && foundAfter)) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "stale auto-detection tasks must not change recognition or refresh translation after Auto is disabled"
grep -q '@AppStorage("sourceLanguage") var sourceLanguage: String = "en-US"' OST/Sources/Settings/UserSettings.swift \
    || fail "default source language must stay in the supported language list"
grep -q '@AppStorage("targetLanguage") var targetLanguage: String = "ko-KR"' OST/Sources/Settings/UserSettings.swift \
    || fail "default target language must stay in the supported language list"
grep -q 'private func sanitizeStoredSettings()' OST/Sources/Settings/UserSettings.swift \
    || fail "stored settings must sanitize stale language and display-mode values on launch"
grep -q 'sourceLanguage != "auto", SupportedLanguage(rawValue: sourceLanguage) == nil' OST/Sources/Settings/UserSettings.swift \
    || fail "stored source language must reset stale unsupported values but preserve Auto"
grep -q 'SupportedLanguage(rawValue: targetLanguage) == nil' OST/Sources/Settings/UserSettings.swift \
    || fail "stored target language must reset stale unsupported values"
grep -q 'overlayDisplayMode != "combined", overlayDisplayMode != "split"' OST/Sources/Settings/UserSettings.swift \
    || fail "stored display mode must reset stale unsupported values"
awk '
    /private func sanitizeStoredSettings\(\)/ { inSanitize = 1 }
    inSanitize && /if !showOriginalText && !showTranslation/ { sawBothHidden = 1 }
    inSanitize && sawBothHidden && /showTranslation = true/ { found = 1 }
    inSanitize && /^    \}/ { inSanitize = 0 }
    END { if (!found) exit 1 }
' OST/Sources/Settings/UserSettings.swift \
    || fail "stored visibility settings must not allow both original and translation text to stay hidden"
grep -q '@AppStorage("allowOnlineTranslationFallback") var allowOnlineTranslationFallback: Bool = false' \
    OST/Sources/Settings/UserSettings.swift \
    || fail "online translation fallback must default to disabled"
grep -q 'bypassesTranslationForSameLanguage' OST/Sources/Translation/TranslationService.swift \
    || fail "same-language translation must bypass Apple Translation and online fallback"
grep -q 'request.timeoutInterval = 8.0' OST/Sources/Translation/TranslationService.swift \
    || fail "online fallback translation must use a bounded timeout"
grep -q 'private(set) var targetLanguage: Locale.Language?' OST/Sources/Translation/TranslationService.swift \
    || fail "translation service must retain target language outside TranslationSession configuration"
grep -q 'translationService.targetLanguage' OST/Sources/App/AppState.swift \
    || fail "auto-detection must reconfigure translation using retained target language"
grep -q 'clearVisibleTranslationsForLanguageChange()' OST/Sources/App/AppState.swift \
    || fail "auto-detection must clear visible translations from the previous source language"
grep -q 'refreshVisibleTranslationsForLanguageChange()' OST/Sources/App/AppState.swift \
    || fail "auto-detection must refresh visible translations after source language detection"
awk '
    /translationService\.configure\(source: target\.translationLocale, target: currentTarget\)/ { inAutoConfigure = 1; sawWait = 0 }
    inAutoConfigure && /translationService\.waitForSessionReady\(timeout: 1\.0\)/ { sawWait = 1 }
    inAutoConfigure && /refreshVisibleTranslationsForLanguageChange\(\)/ {
        if (sawWait) { found = 1 }
        inAutoConfigure = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "auto-detection must wait briefly for the new translation session before refreshing visible translations"
grep -q 'subtitleEntries\[index\]\.translated = ""' OST/Sources/App/AppState.swift \
    || fail "language changes must remove old translated text from visible subtitle entries"
grep -q 'sessionRecorder.clearCurrentTranslations(ids: visibleEntryIDs)' OST/Sources/App/AppState.swift \
    || fail "language changes must clear matching translations from the active session history"
grep -q 'let entriesToTranslate = subtitleEntries.map' OST/Sources/App/AppState.swift \
    || fail "visible subtitle retranslation must snapshot entries before starting async work"
grep -q 'recordSessionEntry: false' OST/Sources/App/AppState.swift \
    || fail "visible subtitle retranslation must not record duplicate session entries"
grep -q 'let shouldUpdateSessionHistory = sessionRecorder.currentSession != nil' OST/Sources/App/AppState.swift \
    || fail "visible subtitle retranslation must not mutate already-ended past sessions"
grep -q 'updateSessionHistory: shouldUpdateSessionHistory' OST/Sources/App/AppState.swift \
    || fail "visible subtitle retranslation must only update active session history"
grep -q 'updateCurrentSessionOnly: true' OST/Sources/App/AppState.swift \
    || fail "visible subtitle retranslation must not update past sessions after capture stops"
awk '
    /func refreshVisibleTranslationsForLanguageChange/ { inRefresh = 1; sawSnapshot = 0; sawSessionGate = 0; sawEntries = 0; sawCurrentOnly = 0; sawLive = 0 }
    inRefresh && /let entriesToTranslate = subtitleEntries\.map/ { sawSnapshot = 1 }
    inRefresh && /let shouldUpdateSessionHistory = sessionRecorder\.currentSession != nil/ { sawSessionGate = 1 }
    inRefresh && /updateSessionHistory: shouldUpdateSessionHistory/ { sawEntries = 1 }
    inRefresh && /updateCurrentSessionOnly: true/ { sawCurrentOnly = 1 }
    inRefresh && /debounceLiveTranslation\(\)/ { sawLive = 1 }
    inRefresh && /^    \}/ {
        if (sawSnapshot && sawSessionGate && sawEntries && sawCurrentOnly && sawLive) { found = 1 }
        inRefresh = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "language and fallback refreshes must retry both visible entries and live text"
grep -q 'recordSessionEntry && saveSessionHistory' OST/Sources/App/AppState.swift \
    || fail "session history recording must be opt-in for translation refreshes"
grep -q 'fallbackLanguageCode(for: sourceLanguage)' OST/Sources/Translation/TranslationService.swift \
    || fail "online fallback must use retained source language"
grep -q 'return "zh-CN"' OST/Sources/Translation/TranslationService.swift \
    || fail "online fallback must preserve Simplified Chinese as zh-CN"
grep -q 'case configurationUnavailable' OST/Sources/Translation/TranslationService.swift \
    || fail "translation service must reject fallback without a retained configuration"
grep -q 'case staleConfiguration' OST/Sources/Translation/TranslationService.swift \
    || fail "translation service must reject stale translation completions"
grep -q 'generation != configurationGeneration' OST/Sources/Translation/TranslationService.swift \
    || fail "translation service must compare request and current generations"
awk '
    /func waitForSessionReady/ { inWait = 1; sawExpected = 0; sawLoop = 0; sawGuard = 0 }
    inWait && /let expectedGeneration = configurationGeneration/ { sawExpected = 1 }
    inWait && /while expectedGeneration == configurationGeneration/ { sawLoop = 1 }
    inWait && /guard expectedGeneration == configurationGeneration/ { sawGuard = 1 }
    inWait && /statusMessage = allowsOnlineFallback/ {
        if (sawExpected && sawLoop && sawGuard) { found = 1 }
        inWait = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Translation/TranslationService.swift \
    || fail "translation session readiness wait must not publish stale status after configuration changes"
grep -q 'fallbackPolicyGeneration += 1' OST/Sources/Translation/TranslationService.swift \
    || fail "online fallback setting changes must advance a fallback policy generation"
grep -q 'validateFallbackPolicyGeneration' OST/Sources/Translation/TranslationService.swift \
    || fail "online fallback results must be discarded after fallback policy changes"
grep -q 'private func isCancellation(_ error: Error) -> Bool' OST/Sources/Translation/TranslationService.swift \
    || fail "translation service must identify cancellation errors"
grep -q 'error is CancellationError' OST/Sources/Translation/TranslationService.swift \
    || fail "translation service must treat CancellationError as cancellation"
grep -q 'urlError.code == .cancelled' OST/Sources/Translation/TranslationService.swift \
    || fail "translation service must treat cancelled URLSession fallback requests as cancellation"
awk '
    /onOnlineFallbackChanged:/ { inFallback = 1; sawSet = 0; sawReport = 0; sawEnabledGuard = 0; sawRefresh = 0 }
    inFallback && /setOnlineFallbackEnabled\(/ { sawSet = 1 }
    inFallback && /reportPendingStatus: appState\.isCapturing/ { sawReport = 1 }
    inFallback && /if appState\.isCapturing, settings\.allowOnlineTranslationFallback/ { sawEnabledGuard = 1 }
    inFallback && /appState\.refreshVisibleTranslationsForLanguageChange\(\)/ { sawRefresh = 1 }
    inFallback && /^            \},/ {
        if (sawSet && sawReport && sawEnabledGuard && sawRefresh) { found = 1 }
        inFallback = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "online fallback changes must suppress idle status while still retrying visible untranslated subtitles during capture"
grep -q 'catch TranslationServiceError.staleConfiguration' OST/Sources/Translation/TranslationService.swift \
    || fail "stale translation completions must not overwrite user-visible translation errors"
awk '
    /if let session/ { inSession = 1 }
    inSession && /\} catch \{/ { inCatch = 1; sawCancel = 0; sawValidate = 0 }
    inCatch && /isCancellation\(error\)/ { sawCancel = 1 }
    inCatch && /try validateGeneration\(generation\)/ { sawValidate = 1 }
    inCatch && /lastErrorMessage = "Translation failed:/ {
        if (sawCancel && sawValidate) { found = 1 }
        inCatch = 0
        inSession = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Translation/TranslationService.swift \
    || fail "Apple Translation failures must ignore cancellation and re-check generation before updating user-visible errors"
awk '
    /let expectedFallbackGeneration = fallbackPolicyGeneration/ { inFallback = 1 }
    inFallback && /\} catch \{/ { inCatch = 1; sawCancel = 0; sawClearStatus = 0; sawThrowCancel = 0; sawGeneration = 0; sawPolicy = 0 }
    inCatch && /isCancellation\(error\)/ { sawCancel = 1 }
    inCatch && sawCancel && /statusMessage = nil/ { sawClearStatus = 1 }
    inCatch && sawCancel && /throw CancellationError\(\)/ { sawThrowCancel = 1 }
    inCatch && /try validateGeneration\(generation\)/ { sawGeneration = 1 }
    inCatch && /try validateFallbackPolicyGeneration\(expectedFallbackGeneration\)/ { sawPolicy = 1 }
    inCatch && /lastErrorMessage = error\.localizedDescription/ {
        if (sawCancel && sawClearStatus && sawThrowCancel && sawGeneration && sawPolicy) { found = 1 }
        inCatch = 0
        inFallback = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/Translation/TranslationService.swift \
    || fail "online fallback failures must ignore cancellation and re-check generation and fallback policy before updating user-visible errors"
grep -q 'translate(textToTranslate, generation: generation)' OST/Sources/App/AppState.swift \
    || fail "live translations must bind to the configuration generation they started with"
grep -q 'translate(text, generation: generation)' OST/Sources/App/AppState.swift \
    || fail "subtitle entry translations must bind to the configuration generation they started with"
grep -q 'catch TranslationServiceError.staleConfiguration' OST/Sources/App/AppState.swift \
    || fail "AppState must ignore stale translation completions without logging them as errors"
grep -q 'catch is CancellationError' OST/Sources/App/AppState.swift \
    || fail "AppState must ignore cancelled translation tasks without logging them as errors"
awk '
    /translate\(textToTranslate, generation: generation\)/ { inLive = 1; sawStale = 0; sawCancel = 0 }
    inLive && /catch TranslationServiceError\.staleConfiguration/ { sawStale = 1 }
    inLive && /catch is CancellationError/ { sawCancel = 1 }
    inLive && /Live translation failed/ {
        if (sawStale && sawCancel) { found = 1 }
        inLive = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "live translation cancellations must be ignored before logging failures"
awk '
    /translate\(text, generation: generation\)/ { inEntry = 1; sawStale = 0; sawCancel = 0 }
    inEntry && /catch TranslationServiceError\.staleConfiguration/ { sawStale = 1 }
    inEntry && /catch is CancellationError/ { sawCancel = 1 }
    inEntry && /Translation failed:/ {
        if (sawStale && sawCancel) { found = 1 }
        inEntry = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "entry translation cancellations must be ignored before logging failures"
awk '
    /if currentText\.isEmpty/ { inReset = 1; sawPrevious = 0; sawConsume = 0; sawAssign = 0 }
    inReset && /let previousText = self\.lastSinkCurrentText/ { sawPrevious = 1 }
    inReset && /self\.consumeRemainingText\(\)/ { sawConsume = 1 }
    inReset && /self\.lastConsumedPartial = previousText/ { sawAssign = 1 }
    inReset && /self\.lastConsumedTail = String\(self\.lastConsumedPartial\.suffix\(60\)\)/ {
        if (sawPrevious && sawConsume && sawAssign) { found = 1 }
        inReset = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "recognizer restarts must include the just-consumed live text in overlap detection"
awk '
    /if currentText\.isEmpty/ { inReset = 1; sawConsume = 0; sawTail = 0; sawSinkClear = 0; bad = 0 }
    inReset && /self\.consumeRemainingText\(\)/ { sawConsume = 1 }
    inReset && /if !self\.lastConsumedPartial\.isEmpty/ { sawPartialGuard = 1 }
    inReset && /self\.lastConsumedTail = String\(self\.lastConsumedPartial\.suffix\(60\)\)/ {
        if (!sawConsume) { bad = 1 }
        sawTail = 1
    }
    inReset && /self\.lastSinkCurrentText = ""/ { sawSinkClear = 1 }
    inReset && /return/ {
        if (sawPartialGuard && sawTail && sawSinkClear && !bad) { found = 1 }
        inReset = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "repeated empty speech updates must not erase the preserved overlap tail"
grep -q 'if !self.lastConsumedPartial.isEmpty' OST/Sources/App/AppState.swift \
    || fail "recognizer restarts must preserve already-consumed sentence tails even when liveText is empty"
grep -q 'guard let sourceLang = fallbackLanguageCode(for: sourceLanguage)' OST/Sources/Translation/TranslationService.swift \
    || fail "online fallback must not use default source language after invalidation"
if grep -q '?? "en"\|?? "ko"' OST/Sources/Translation/TranslationService.swift; then
    fail "online fallback must not use default languages after invalidation"
fi
grep -q 'Ignoring stale translation session' OST/Sources/Translation/TranslationService.swift \
    || fail "translation service must ignore stale sessions after invalidation or same-language bypass"
grep -q 'configurationGeneration += 1' OST/Sources/Translation/TranslationService.swift \
    || fail "translation configuration changes must advance a generation token"
grep -q 'generation == configurationGeneration' OST/Sources/Translation/TranslationService.swift \
    || fail "translation sessions must match the current generation"
grep -q 'handleSession(session, generation: generation)' OST/Sources/UI/SubtitleView.swift \
    || fail "combined overlay must pass translation generation to session handler"
grep -q 'handleSession(session, generation: generation)' OST/Sources/UI/TranslationOverlayView.swift \
    || fail "split translation overlay must pass translation generation to session handler"
if grep -q 'render SubtitleView' OST/Sources/App/OSTApp.swift; then
    fail "translation setup comments must account for split-mode TranslationOverlayView"
fi
grep -q 'configuration = nil' OST/Sources/Translation/TranslationService.swift \
    || fail "translation invalidation must clear configuration"
grep -q 'preservingPendingTranslations: true' OST/Sources/App/OSTApp.swift \
    || fail "stop capture must preserve translation context for queued final subtitles"
awk '
    /private func quitApp\(\)/ { inQuit = 1; sawTask = 0; sawStop = 0 }
    inQuit && /Task \{/ { sawTask = 1 }
    inQuit && /await stopCapture\(\)/ { sawStop = 1 }
    inQuit && /NSApplication\.shared\.terminate\(nil\)/ {
        if (sawTask && sawStop) { found = 1 }
        inQuit = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "Quit must stop capture before terminating so active sessions are saved"
grep -q 'if preservingPendingTranslations' OST/Sources/Translation/TranslationService.swift \
    || fail "translation invalidation must support pending translation preservation"
grep -q 'static func isSameLanguagePair' OST/Sources/Translation/TranslationConfig.swift \
    || fail "same-language translation availability must use a shared helper"
grep -q 'source.script?.identifier' OST/Sources/Translation/TranslationConfig.swift \
    || fail "same-language translation availability must preserve Chinese script differences"
grep -q 'TranslationConfig.isSameLanguagePair' OST/Sources/Translation/TranslationService.swift \
    || fail "translation service must use the shared same-language helper"
grep -q 'TranslationConfig.isSameLanguagePair' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language settings must use the shared same-language helper"
grep -q 'No translation needed' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language settings must explain same-language pairs"
grep -q 'Checked after language is detected' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language settings must not show fixed language-pack availability for Auto source"
grep -q 'enum TranslationAvailabilityState' OST/Sources/Translation/TranslationConfig.swift \
    || fail "translation availability checks must preserve installed/supported/unsupported states"
grep -q 'enum TranslationConfig' OST/Sources/Translation/TranslationConfig.swift \
    || fail "TranslationConfig should be a static namespace, not a stale Bool-backed value type"
if grep -q 'let isAvailable: Bool' OST/Sources/Translation/TranslationConfig.swift; then
    fail "translation availability must not keep the old Bool-backed availability model"
fi
if grep -q 'static func checkAvailability' OST/Sources/Translation/TranslationConfig.swift; then
    fail "translation availability must not keep the old Bool-returning checkAvailability API"
fi
grep -q 'case \.supported:' OST/Sources/Translation/TranslationConfig.swift \
    || fail "translation availability checks must distinguish supported downloadable packs"
grep -q 'entry.translated.isEmpty ? "..." : entry.translated' OST/Sources/UI/SubtitleView.swift \
    || fail "combined subtitle overlay must show a placeholder while entry translations are pending"
if grep -q 'settings.showTranslation && !entry.translated.isEmpty' OST/Sources/UI/SubtitleView.swift; then
    fail "combined subtitle overlay must not hide pending entry translations without a placeholder"
fi
for overlay_view in SubtitleView RecognitionOverlayView TranslationOverlayView; do
    grep -q '.onChange(of: appState.subtitleEntries.map(\\.id))' "OST/Sources/UI/${overlay_view}.swift" \
        || fail "${overlay_view} must auto-scroll when subtitle entry identity changes, even after trimming"
    grep -q '.animation(.easeInOut(duration: 0.2), value: appState.subtitleEntries.map(\\.id))' "OST/Sources/UI/${overlay_view}.swift" \
        || fail "${overlay_view} must animate subtitle entry identity changes, even after trimming"
    if grep -q '.onChange(of: appState.subtitleEntries.count)' "OST/Sources/UI/${overlay_view}.swift"; then
        fail "${overlay_view} must not rely on subtitle entry count for auto-scroll after trimming"
    fi
    if grep -q '.animation(.easeInOut(duration: 0.2), value: appState.subtitleEntries.count)' "OST/Sources/UI/${overlay_view}.swift"; then
        fail "${overlay_view} must not rely on subtitle entry count for animations after trimming"
    fi
    if grep -q '.onChange(of: appState.subtitleEntries.last?.id)' "OST/Sources/UI/${overlay_view}.swift"; then
        fail "${overlay_view} must track the full subtitle identity list so removals animate too"
    fi
done
for translation_overlay_view in SubtitleView TranslationOverlayView; do
    grep -q '.onChange(of: appState.subtitleEntries.map(\\.translated))' "OST/Sources/UI/${translation_overlay_view}.swift" \
        || fail "${translation_overlay_view} must auto-scroll when pending entry translations are filled"
done
grep -q 'Apple Translation installed' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language settings must distinguish installed translation packs"
grep -q 'Download required' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language settings must show downloadable translation packs"
grep -q 'Apple Translation unsupported' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language settings must distinguish unsupported translation pairs"
grep -q 'Translation pack can be downloaded' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language settings accessibility must explain downloadable translation packs"
grep -q 'Checking translation availability' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language settings accessibility must distinguish availability checks from unavailable packs"
if grep -q 'Translation pack installed' OST/Sources/UI/LanguagePickerView.swift; then
    fail "language settings must not claim supported translation packs are installed"
fi
grep -q 'guard !isAutoSource else { return }' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language settings availability check must skip Auto source"
grep -qF '.task(id: "\(settings.sourceLanguage)-\(settings.targetLanguage)")' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language availability checks must rerun when source or target language changes"
awk '
    /\.task\(id:/ { inTask = 1; sawTask = 1 }
    inTask && /await checkAvailability\(\)/ { found = 1; inTask = 0 }
    END { if (!(sawTask && found)) exit 1 }
' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language availability task must call checkAvailability"
awk '
    /private func checkAvailability\(\) async/ { inCheck = 1; sawKey = 0; sawCancel = 0 }
    inCheck && /let key = pairKey/ { sawKey = 1 }
    inCheck && /guard !Task\.isCancelled else \{ return \}/ { sawCancel = 1 }
    inCheck && /translationAvailability\[key\] = availability/ {
        if (sawKey && sawCancel) { found = 1 }
        inCheck = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language availability checks must not publish stale results under the current pair"
grep -q 'if !isAutoSource && !isSameLanguagePair && availability == \.supported' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language settings must not show translation download action for Auto source"
grep -q 'When enabled, text may be sent to Google Translate.' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language settings must visibly disclose online fallback privacy impact"
awk '
    /@MainActor/ { sawMainActor = 1; next }
    sawMainActor && /enum AccessibilityManager/ { found = 1 }
    END { if (!found) exit 1 }
' OST/Sources/Accessibility/AccessibilityManager.swift \
    || fail "AccessibilityManager must stay MainActor-isolated because it uses NSApp and AppKit accessibility APIs"
for language_binding in \
    'sourceLanguageBinding:settings.sourceLanguage:onLanguageSettingsChanged' \
    'targetLanguageBinding:settings.targetLanguage:onLanguageSettingsChanged' \
    'useOnDeviceBinding:settings.useOnDeviceRecognition:onLanguageSettingsChanged' \
    'onlineFallbackBinding:settings.allowOnlineTranslationFallback:onOnlineFallbackChanged'; do
    binding_name="${language_binding%%:*}"
    rest="${language_binding#*:}"
    binding_assignment="${rest%%:*}"
    binding_callback="${rest#*:}"
    awk -v binding="$binding_name" -v assignment="$binding_assignment" -v callback="$binding_callback" '
        $0 ~ "private var " binding { inBinding = 1; sawAssignment = 0; sawCallback = 0; next }
        inBinding && index($0, assignment) { sawAssignment = 1 }
        inBinding && index($0, callback "?()") { sawCallback = 1 }
        inBinding && /^    \}/ {
            if (sawAssignment && sawCallback) { found = 1 }
            inBinding = 0
        }
        END { if (!found) exit 1 }
    ' OST/Sources/UI/LanguagePickerView.swift \
        || fail "language settings binding must notify the running app: $binding_name"
done
awk '
    /private func swapLanguages\(\)/ { inSwap = 1; sawGuard = 0; sawSource = 0; sawTarget = 0; sawCallback = 0; sawAnnounce = 0 }
    inSwap && /guard settings\.sourceLanguage != "auto" else \{ return \}/ { sawGuard = 1 }
    inSwap && /settings\.sourceLanguage = settings\.targetLanguage/ { sawSource = 1 }
    inSwap && /settings\.targetLanguage = previous/ { sawTarget = 1 }
    inSwap && /onLanguageSettingsChanged\?\(\)/ { sawCallback = 1 }
    inSwap && /AccessibilityManager\.announce/ { sawAnnounce = 1 }
    inSwap && /^    \}/ {
        if (sawGuard && sawSource && sawTarget && sawCallback && sawAnnounce) { found = 1 }
        inSwap = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/UI/LanguagePickerView.swift \
    || fail "language swap must update settings, notify the running app, and announce the change"
grep -q 'func record(id: UUID, recognized: String, translated: String)' OST/Sources/App/SessionRecorder.swift \
    || fail "session history must record subtitle entries by stable id"
grep -q 'SessionEntry(id: id, recognizedText: recognized, translatedText: translated)' OST/Sources/App/SessionRecorder.swift \
    || fail "session history must preserve subtitle entry ids"
grep -q 'Session discarded (0 entries)' OST/Sources/App/SessionRecorder.swift \
    || fail "session recorder must not persist empty sessions"
grep -q 'pastSessions = Array(pastSessions.prefix(20))' OST/Sources/App/SessionRecorder.swift \
    || fail "session recorder must keep the in-memory session list bounded"
grep -q 'pastSessions = Array(sessions.prefix(20))' OST/Sources/App/SessionRecorder.swift \
    || fail "session recorder must trim previously saved sessions on load"
awk '
    /pastSessions = Array\(sessions\.prefix\(20\)\)/ { sawTrim = 1 }
    sawTrim && /if sessions\.count > pastSessions\.count/ { sawCheck = 1 }
    sawCheck && /saveSessions\(\)/ { found = 1; exit 0 }
    END { if (!found) exit 1 }
' OST/Sources/App/SessionRecorder.swift \
    || fail "session recorder must persist trimmed session history after load"
grep -q 'func updateTranslation(id: UUID, translated: String)' OST/Sources/App/SessionRecorder.swift \
    || fail "session history must update translations that finish after recording"
grep -q 'func updateCurrentTranslation(id: UUID, translated: String)' OST/Sources/App/SessionRecorder.swift \
    || fail "session history must support current-session-only translation updates"
grep -q 'func clearCurrentTranslations(ids: \[UUID\])' OST/Sources/App/SessionRecorder.swift \
    || fail "session history must clear stale current-session translations after language changes"
grep -q 'guard var session = currentSession else { return }' OST/Sources/App/SessionRecorder.swift \
    || fail "translation clearing must not rewrite past sessions"
grep -q 'self.sessionRecorder.updateTranslation(id: id, translated: result)' OST/Sources/App/AppState.swift \
    || fail "translation completion must update session history independently"
grep -q 'self.sessionRecorder.updateCurrentTranslation(id: id, translated: result)' OST/Sources/App/AppState.swift \
    || fail "language-change retranslation must only update active session history"
awk '
    /if self.saveSessionHistory/ { inSave = 1; depth = 0 }
    inSave {
        depth += gsub(/\{/, "{")
        if (/updateTranslation/) { bad = 1 }
        depth -= gsub(/\}/, "}")
        if (depth <= 0) { inSave = 0 }
    }
    END { if (bad) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "translation completion must not depend on current saveSessionHistory setting"
grep -q 'currentSession = session' OST/Sources/App/SessionRecorder.swift \
    || fail "session recorder must republish current session value changes"
grep -q 'pastSessions = sessions' OST/Sources/App/SessionRecorder.swift \
    || fail "session recorder must republish past session value changes"
grep -q 'Session save failed' OST/Sources/App/SessionRecorder.swift \
    || fail "session persistence failures must be logged"
grep -q 'Session load failed' OST/Sources/App/SessionRecorder.swift \
    || fail "session load failures must be logged"
if grep -q 'first!' OST/Sources/App/SessionRecorder.swift; then
    fail "session storage path must not force unwrap application support directory"
fi
grep -q 'ensureStorageDirectory()' OST/Sources/App/SessionRecorder.swift \
    || fail "session save must create its storage directory through the logged save path"
grep -q 'displayedSession' OST/Sources/UI/SessionHistoryView.swift \
    || fail "session detail must resolve the latest recorder value for selected sessions"
if grep -q '?? selectedSession' OST/Sources/UI/SessionHistoryView.swift; then
    fail "session detail must not display stale sessions that no longer exist"
fi
grep -q '@State private var showClearHistoryConfirmation = false' OST/Sources/UI/SessionHistoryView.swift \
    || fail "session history clear-all must be gated by confirmation state"
awk '
    /Button\("Clear All"\)/ { inClearButton = 1; sawPrompt = 0; sawImmediateClear = 0 }
    inClearButton && /showClearHistoryConfirmation = true/ { sawPrompt = 1 }
    inClearButton && /recorder\.clearHistory\(\)/ { sawImmediateClear = 1 }
    inClearButton && /\.disabled\(recorder\.pastSessions\.isEmpty\)/ {
        if (sawPrompt && !sawImmediateClear) { found = 1 }
        inClearButton = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/UI/SessionHistoryView.swift \
    || fail "session history Clear All must ask for confirmation before deleting sessions"
awk '
    /\.alert\("Clear Session History\?"/ { inAlert = 1; sawDestructive = 0; sawClear = 0; sawCancel = 0 }
    inAlert && /Button\("Clear All", role: \.destructive\)/ { sawDestructive = 1 }
    inAlert && sawDestructive && /recorder\.clearHistory\(\)/ { sawClear = 1 }
    inAlert && /Button\("Cancel", role: \.cancel\)/ { sawCancel = 1 }
    inAlert && /message:/ {
        if (sawDestructive && sawClear && sawCancel) { found = 1 }
        inAlert = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/UI/SessionHistoryView.swift \
    || fail "session history confirmation must offer cancel and destructive clear actions"
grep -q 'private func latestSession(id: UUID)' OST/Sources/UI/SessionHistoryView.swift \
    || fail "session export must resolve the latest session value when the save panel completes"
grep -q 'let sessionToExport = latestSession(id: session.id) ?? session' OST/Sources/UI/SessionHistoryView.swift \
    || fail "session export must not rely only on the session snapshot captured before the save panel"
grep -q 'sessionText(sessionToExport)' OST/Sources/UI/SessionHistoryView.swift \
    || fail "session export must write the latest resolved session text"
grep -q '@State private var isAtBottom = true' OST/Sources/UI/LogViewerView.swift \
    || fail "log viewer must track whether the user is reading the latest logs"
grep -q '.onScrollGeometryChange(for: Bool.self)' OST/Sources/UI/LogViewerView.swift \
    || fail "log viewer must detect when the user scrolls away from the bottom"
grep -q '.onChange(of: filteredEntries.last?.id)' OST/Sources/UI/LogViewerView.swift \
    || fail "log viewer must auto-scroll when the newest visible log changes, even after log trimming"
if grep -q '.onChange(of: filteredEntries.count)' OST/Sources/UI/LogViewerView.swift; then
    fail "log viewer must not rely on entry count for auto-scroll after the log list reaches its cap"
fi
grep -q 'if isAtBottom, let last = filteredEntries.last' OST/Sources/UI/LogViewerView.swift \
    || fail "log viewer must not force-scroll while the user is reading older logs"
grep -qF 'Text("All").tag(LogEntry.LogCategory?.none)' OST/Sources/UI/LogViewerView.swift \
    || fail "log viewer must keep an All filter"
for log_filter in \
    'app:App:primary' \
    'audio:Audio:blue' \
    'speech:Speech:green' \
    'translation:Translation:orange' \
    'error:Error:red'; do
    category="${log_filter%%:*}"
    rest="${log_filter#*:}"
    label="${rest%%:*}"
    color="${rest#*:}"
    grep -qF "Text(\"${label}\").tag(LogEntry.LogCategory?.some(.${category}))" OST/Sources/UI/LogViewerView.swift \
        || fail "log viewer filter is missing category: $label"
    grep -q "case \\.${category}:.*return \\.${color}" OST/Sources/UI/LogViewerView.swift \
        || fail "log viewer color mapping is missing category: $label"
done
awk '
    /Button\("Clear"\)/ { inClear = 1; sawClear = 0; sawBottom = 0 }
    inClear && /logger\.clear\(\)/ { sawClear = 1 }
    inClear && /isAtBottom = true/ { sawBottom = 1 }
    inClear && /^            \}/ {
        if (sawClear && sawBottom) { found = 1 }
        inClear = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/UI/LogViewerView.swift \
    || fail "clearing logs must restore bottom-scroll state for new log entries"
grep -q 'panel.allowedContentTypes = \[.plainText\]' OST/Sources/UI/SessionHistoryView.swift \
    || fail "session export must constrain the save panel to plain text"
awk '
    /private func exportSession/ { inExport = 1; sawHost = 0; sawOriginal = 0; sawLower = 0; sawRestore = 0 }
    inExport && /let hostWindow = NSApp\.keyWindow/ { sawHost = 1 }
    inExport && /let originalLevel = hostWindow\?\.level/ { sawOriginal = 1 }
    inExport && /hostWindow\?\.level = \.normal/ { sawLower = 1 }
    inExport && /hostWindow\?\.level = originalLevel \?\? \.normal/ { sawRestore = 1 }
    inExport && /guard response == \.OK/ {
        if (sawHost && sawOriginal && sawLower && sawRestore) { found = 1 }
        inExport = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/UI/SessionHistoryView.swift \
    || fail "session export must lower and restore floating window level around the save panel"
grep -q 'Session export failed' OST/Sources/UI/SessionHistoryView.swift \
    || fail "session export failures must be logged"
grep -q 'Session export failed: .*category: \.error' OST/Sources/UI/SessionHistoryView.swift \
    || fail "session export failures must appear under the Debug Console Error filter"
grep -q 'settings.overlayWidth = defaultFrame.width' OST/Sources/App/WindowManager.swift \
    || fail "primary overlay reset must restore persisted width"
grep -q 'settings.overlay2Width = defaultFrame.width' OST/Sources/App/WindowManager.swift \
    || fail "translation overlay reset must restore persisted width"
grep -q 'settings.overlayFrameSaved = true' OST/Sources/App/WindowManager.swift \
    || fail "split overlay reset must persist the reset primary frame"
grep -q 'settings.overlay2FrameSaved = true' OST/Sources/App/WindowManager.swift \
    || fail "split overlay reset must persist the reset translation frame"
grep -q 'private func clampedDefaultFrame' OST/Sources/App/WindowManager.swift \
    || fail "overlay reset must clamp default frames to the visible screen"
grep -q 'let defaultFrame = clampedDefaultFrame(x: 200, y: 200, width: 600, height: 200)' OST/Sources/App/WindowManager.swift \
    || fail "primary overlay reset must not use an unclamped fixed default frame"
grep -q 'let defaultFrame = clampedDefaultFrame(x: 200, y: 450, width: 600, height: 200)' OST/Sources/App/WindowManager.swift \
    || fail "translation overlay reset must not use an unclamped fixed default frame"
for clamp_expr in \
    'let frameWidth = max(CGFloat(1), min(width, screen.width))' \
    'let frameHeight = max(CGFloat(1), min(height, screen.height))' \
    'let frameX = max(screen.minX, min(x, screen.maxX - frameWidth))' \
    'let frameY = max(screen.minY, min(y, screen.maxY - frameHeight))'; do
    grep -q "$clamp_expr" OST/Sources/App/WindowManager.swift \
        || fail "overlay reset default frame clamp is missing: $clamp_expr"
done
awk '
    /Button\("Reset All Overlay Windows"\)/ { inButton = 1; sawPrimary = 0; sawSecondary = 0 }
    inButton && /onResetOverlay\?\(\)/ { sawPrimary = 1 }
    inButton && /onResetOverlay2\?\(\)/ { sawSecondary = 1 }
    inButton && /\.accessibilityLabel\("Reset all overlay windows/ {
        if (sawPrimary && !sawSecondary) { found = 1 }
        inButton = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/UI/FontSettingsView.swift \
    || fail "reset-all overlay button must not invoke duplicate split reset callbacks"
grep -q 'Button(settings.overlayDisplayMode == "split" ? "Reset Both Windows" : "Reset Position & Size")' OST/Sources/UI/FontSettingsView.swift \
    || fail "primary overlay reset button must describe split-mode reset behavior"
grep -q 'Button("Reset Both Windows")' OST/Sources/UI/FontSettingsView.swift \
    || fail "translation overlay reset button must describe split-mode reset behavior"
awk '
    /Picker\("Mode", selection: Binding/ { inPicker = 1; sawAssignment = 0; sawCallback = 0 }
    inPicker && /settings\.overlayDisplayMode = newValue/ { sawAssignment = 1 }
    inPicker && /onDisplayModeChanged\?\(\)/ { sawCallback = 1 }
    inPicker && /\.pickerStyle\(\.menu\)/ {
        if (sawAssignment && sawCallback) { found = 1 }
        inPicker = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/UI/FontSettingsView.swift \
    || fail "display mode picker must notify the running app after changing mode"
awk '
    /onToggleOverlayLock: \{ locked in/ { inToggle = 1; sawPrimary = 0; sawSplitGuard = 0; sawSecondarySetting = 0; sawSecondaryUpdate = 0 }
    inToggle && /windowManager\.updateOverlayLock\(locked: locked\)/ { sawPrimary = 1 }
    inToggle && /if settings\.overlayDisplayMode == "split"/ { sawSplitGuard = 1 }
    inToggle && /settings\.overlay2Locked = locked/ { sawSecondarySetting = 1 }
    inToggle && /windowManager\.updateOverlay2Lock\(locked: locked\)/ { sawSecondaryUpdate = 1 }
    inToggle && /^                \},/ {
        if (sawPrimary && sawSplitGuard && sawSecondarySetting && sawSecondaryUpdate) { found = 1 }
        inToggle = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/OSTApp.swift \
    || fail "menu bar overlay lock must keep split overlay windows in sync"
grep -q 'onToggleOverlay2Lock: { \[weak self\] locked in self?.updateOverlay2Lock(locked: locked) }' OST/Sources/App/WindowManager.swift \
    || fail "settings translation overlay lock toggle must update the second overlay window"
awk '
    /FontSettingsView\(/ { inFont = 1; sawPrimary = 0; sawSecondary = 0 }
    inFont && /onToggleOverlayLock: onToggleOverlayLock/ { sawPrimary = 1 }
    inFont && /onToggleOverlay2Lock: onToggleOverlay2Lock/ { sawSecondary = 1 }
    inFont && /onSubtitleSettingsChanged:/ {
        if (sawPrimary && sawSecondary) { found = 1 }
        inFont = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/UI/SettingsView.swift \
    || fail "settings display tab must forward both overlay lock callbacks"
awk '
    /func showOverlay\(appState:/ { inShow = 1; sawModeGuard = 0; sawHide = 0; sawModeSet = 0 }
    inShow && /activeOverlayDisplayMode != nil && activeOverlayDisplayMode != settings\.overlayDisplayMode/ { sawModeGuard = 1 }
    inShow && sawModeGuard && /hideOverlay\(\)/ { sawHide = 1 }
    inShow && /activeOverlayDisplayMode = settings\.overlayDisplayMode/ { sawModeSet = 1 }
    inShow && /^    \}/ {
        if (sawModeGuard && sawHide && sawModeSet) { found = 1 }
        inShow = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/WindowManager.swift \
    || fail "display mode changes must discard stale overlay windows before creating the new overlay host"
awk '
    /private func showCombinedOverlay/ { inCombined = 1; sawHideSplit = 0 }
    inCombined && /hideOverlayWindow2\(\)/ { sawHideSplit = 1 }
    inCombined && /^    \}/ {
        if (sawHideSplit) { found = 1 }
        inCombined = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/WindowManager.swift \
    || fail "combined overlay mode must hide the split translation window"
awk '
    /func hideOverlay\(\)/ { inHide = 1; sawPrimaryOut = 0; sawPrimaryNil = 0; sawModeNil = 0; sawSecondaryHide = 0 }
    inHide && /overlayWindow\?\.orderOut\(nil\)/ { sawPrimaryOut = 1 }
    inHide && /overlayWindow = nil/ { sawPrimaryNil = 1 }
    inHide && /activeOverlayDisplayMode = nil/ { sawModeNil = 1 }
    inHide && /hideOverlayWindow2\(\)/ { sawSecondaryHide = 1 }
    inHide && /^    \}/ {
        if (sawPrimaryOut && sawPrimaryNil && sawModeNil && sawSecondaryHide) { found = 1 }
        inHide = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/WindowManager.swift \
    || fail "hiding overlays must clear primary, secondary, and active display-mode state"
awk '
    /func showSettings\(/ { inSettings = 1; sawRelease = 0 }
    inSettings && /window\.isReleasedWhenClosed = false/ { sawRelease = 1 }
    inSettings && /window\.title = "OST Settings"/ {
        if (sawRelease) { foundSettings = 1 }
        inSettings = 0
    }
    /func showLogViewer\(\)/ { inLogs = 1; sawRelease = 0 }
    inLogs && /window\.isReleasedWhenClosed = false/ { sawRelease = 1 }
    inLogs && /window\.title = "OST Logs"/ {
        if (sawRelease) { foundLogs = 1 }
        inLogs = 0
    }
    /func showSessionHistory\(recorder:/ { inSessions = 1; sawRelease = 0 }
    inSessions && /window\.isReleasedWhenClosed = false/ { sawRelease = 1 }
    inSessions && /window\.title = "OST Session History"/ {
        if (sawRelease) { foundSessions = 1 }
        inSessions = 0
    }
    END { if (!(foundSettings && foundLogs && foundSessions)) exit 1 }
' OST/Sources/App/WindowManager.swift \
    || fail "reused AppKit windows must not be released when closed"
grep -q 'let gap = min(CGFloat(20), screen.width / 20)' OST/Sources/App/WindowManager.swift \
    || fail "split overlay reset must scale the gap on narrow screens"
grep -q 'let windowWidth = max(CGFloat(1), min(CGFloat(500), (screen.width - gap) / 2))' OST/Sources/App/WindowManager.swift \
    || fail "split overlay reset must fit both windows within the visible screen width"
grep -q 'let baseY = max(screen.minY, min(screen.minY + 200, screen.maxY - windowHeight))' OST/Sources/App/WindowManager.swift \
    || fail "split overlay reset must keep both windows within the visible screen height"
grep -q 'private static func finite' OST/Sources/UI/OverlayWindow.swift \
    || fail "overlay frame restore must sanitize non-finite persisted values"
grep -q 'minSize = NSSize(width: min(200, initialFrame.width), height: min(100, initialFrame.height))' OST/Sources/UI/OverlayWindow.swift \
    || fail "overlay windows must enforce the same minimum live resize size used for persisted frame sanitization"
grep -q 'f.size.width = finite(f.size.width, fallback: 600)' OST/Sources/UI/OverlayWindow.swift \
    || fail "overlay frame restore must fallback invalid persisted width"
grep -q 'f.size.width = min(max(f.size.width, minWidth), screen.width)' OST/Sources/UI/OverlayWindow.swift \
    || fail "overlay frame restore must not reopen wider than the visible screen"
grep -q 'f.size.height = min(max(f.size.height, minHeight), screen.height)' OST/Sources/UI/OverlayWindow.swift \
    || fail "overlay frame restore must not reopen taller than the visible screen"
grep -q 'f.origin.x = max(screen.minX, min(f.origin.x, screen.maxX - f.width))' OST/Sources/UI/OverlayWindow.swift \
    || fail "overlay frame restore must keep the full window horizontally visible"
grep -q 'f.origin.y = max(screen.minY, min(f.origin.y, screen.maxY - f.height))' OST/Sources/UI/OverlayWindow.swift \
    || fail "overlay frame restore must keep the full window vertically visible"
grep -q 'func updateSessionWindowAlwaysOnTop' OST/Sources/App/WindowManager.swift \
    || fail "session window always-on-top changes must update existing windows"
grep -q 'sessionWindow?.level = alwaysOnTop ? .floating : .normal' OST/Sources/App/WindowManager.swift \
    || fail "session window always-on-top changes must update the visible session window level"
awk '
    /func showSessionHistory\(recorder:/ { inShow = 1; inExisting = 0; sawExistingLevel = 0; sawNewLevel = 0 }
    inShow && /if let existing = sessionWindow, existing\.isVisible/ { inExisting = 1 }
    inExisting && /existing\.level = alwaysOnTop \? \.floating : \.normal/ { sawExistingLevel = 1 }
    inExisting && /return/ { inExisting = 0 }
    inShow && /window\.level = alwaysOnTop \? \.floating : \.normal/ { sawNewLevel = 1 }
    inShow && /sessionWindow = window/ {
        if (sawExistingLevel && sawNewLevel) { found = 1 }
        inShow = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/WindowManager.swift \
    || fail "opening Session History must apply always-on-top to existing and new windows"
grep -q 'sessionWindowAlwaysOnTopBinding' OST/Sources/UI/SettingsView.swift \
    || fail "session window always-on-top toggle must notify the running app"
awk '
    /func stopCapture\(\) async/ { inStop = 1; sawWasStarting = 0; sawGuard = 0 }
    inStop && /let wasStartingCapture = isStartingCapture/ { sawWasStarting = 1 }
    inStop && /guard isCapturing \|\| wasStartingCapture else/ { sawGuard = 1 }
    inStop && /consumeRemainingText\(\)/ { consumed = 1 }
    inStop && /isCapturing = false/ { exit (sawWasStarting && sawGuard && consumed) ? 0 : 1 }
    END { if (!sawWasStarting || !sawGuard || !consumed) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "stopCapture must clean up both active capture and in-flight capture starts"
awk '
    /func changeSourceLanguage/ { inChange = 1; depth = 0; sawGuard = 0; sawStop = 0 }
    inChange {
        depth += gsub(/\{/, "{")
        depth -= gsub(/\}/, "}")
        if (/if isCapturing/) { sawGuard = 1 }
        if (/await stopCapture\(\)/) { sawStop = 1 }
        if (depth == 0) {
            if (sawGuard && sawStop) { found = 1 }
            inChange = 0
        }
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "language change failures while capturing must stop the pipeline"
grep -q 'Audio capture stopped unexpectedly' OST/Sources/App/AppState.swift \
    || fail "unexpected audio stream termination must surface an error"
grep -q 'var subtitleExpirySeconds: Double = 20' OST/Sources/App/AppState.swift \
    || fail "AppState subtitle expiry default must match UserSettings"
grep -q 'var speechPauseSeconds: Double = 3.0' OST/Sources/App/AppState.swift \
    || fail "AppState speech pause default must match UserSettings"
grep -q 'clampedInt(maxLines, min: 1, max: 10, fallback: 3)' OST/Sources/App/AppState.swift \
    || fail "AppState must clamp max subtitle lines from persisted settings"
grep -q 'clampedDouble(expirySeconds, min: 3, max: 60, fallback: 20)' OST/Sources/App/AppState.swift \
    || fail "AppState must clamp subtitle expiry from persisted settings"
grep -q 'clampedDouble(pauseSeconds, min: 0.5, max: 5, fallback: 3)' OST/Sources/App/AppState.swift \
    || fail "AppState must clamp speech pause from persisted settings"
grep -q 'guard value.isFinite else { return fallback }' OST/Sources/App/AppState.swift \
    || fail "AppState persisted numeric setting clamps must reject NaN and infinity"
awk '
    /func updateSubtitleSettings/ { inUpdate = 1; sawExpiry = 0; sawRemoveExpired = 0; sawTrim = 0 }
    inUpdate && /subtitleExpirySeconds = clampedDouble/ { sawExpiry = 1 }
    inUpdate && sawExpiry && /removeExpiredEntries\(\)/ { sawRemoveExpired = 1 }
    inUpdate && sawRemoveExpired && /trimEntries\(\)/ { sawTrim = 1 }
    inUpdate && /^    \}/ {
        if (sawExpiry && sawRemoveExpired && sawTrim) { found = 1 }
        inUpdate = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "subtitle expiry setting changes must remove newly expired entries immediately before trimming"
grep -q 'private static func scheduledCommonTimer' OST/Sources/App/AppState.swift \
    || fail "AppState timers must use a common-mode helper"
grep -q 'RunLoop.main.add(timer, forMode: .common)' OST/Sources/App/AppState.swift \
    || fail "AppState timers must run during menu, scroll, and window-tracking interactions"
if grep -q 'Timer.scheduledTimer' OST/Sources/App/AppState.swift; then
    fail "AppState timers must not be scheduled only in the default run loop mode"
fi
for property in \
    safeFontSize \
    safeTranslatedFontSize \
    safeBackgroundOpacity \
    safeMaxSubtitleLines \
    safeSubtitleExpirySeconds \
    safeSpeechPauseSeconds; do
    grep -q "var $property" OST/Sources/Settings/UserSettings.swift \
        || fail "UserSettings is missing sanitized numeric setting: $property"
done
grep -q 'private static func clamped(_ value: Double' OST/Sources/Settings/UserSettings.swift \
    || fail "UserSettings must centralize sanitized numeric setting clamps"
grep -q 'guard value.isFinite else { return fallback }' OST/Sources/Settings/UserSettings.swift \
    || fail "UserSettings sanitized numeric setting clamps must reject NaN and infinity"
for assignment in \
    'fontSize = safeFontSize' \
    'translatedFontSize = safeTranslatedFontSize' \
    'backgroundOpacity = safeBackgroundOpacity' \
    'maxSubtitleLines = safeMaxSubtitleLines' \
    'subtitleExpirySeconds = safeSubtitleExpirySeconds' \
    'speechPauseSeconds = safeSpeechPauseSeconds' \
    'sanitizeOverlayFrameValues()'; do
    grep -q "$assignment" OST/Sources/Settings/UserSettings.swift \
        || fail "UserSettings must persist sanitized numeric setting on launch: $assignment"
done
grep -q 'private func sanitizeOverlayFrameValues()' OST/Sources/Settings/UserSettings.swift \
    || fail "UserSettings must sanitize persisted overlay frames on launch"
awk '
    /private var showOriginalTextBinding/ { inBinding = 1; sawSet = 0; sawGuard = 0; sawFallback = 0 }
    inBinding && /settings\.showOriginalText = newValue/ { sawSet = 1 }
    inBinding && /if !settings\.showOriginalText && !settings\.showTranslation/ { sawGuard = 1 }
    inBinding && sawGuard && /settings\.showTranslation = true/ { sawFallback = 1 }
    inBinding && /^    \}/ {
        if (sawSet && sawGuard && sawFallback) { found = 1 }
        inBinding = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/UI/FontSettingsView.swift \
    || fail "original-text visibility toggle must keep at least one subtitle text column visible"
awk '
    /private var showTranslationBinding/ { inBinding = 1; sawSet = 0; sawGuard = 0; sawFallback = 0 }
    inBinding && /settings\.showTranslation = newValue/ { sawSet = 1 }
    inBinding && /if !settings\.showOriginalText && !settings\.showTranslation/ { sawGuard = 1 }
    inBinding && sawGuard && /settings\.showOriginalText = true/ { sawFallback = 1 }
    inBinding && /^    \}/ {
        if (sawSet && sawGuard && sawFallback) { found = 1 }
        inBinding = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/UI/FontSettingsView.swift \
    || fail "translation visibility toggle must keep at least one subtitle text column visible"
for overlay_assignment in \
    'overlayFrameX = Self.finite(overlayFrameX, fallback: 200)' \
    'overlayFrameY = Self.finite(overlayFrameY, fallback: 200)' \
    'overlayWidth = Self.clamped(overlayWidth, min: 200, max: 3000, fallback: 600)' \
    'overlayHeight = Self.clamped(overlayHeight, min: 100, max: 2000, fallback: 200)' \
    'overlay2FrameX = Self.finite(overlay2FrameX, fallback: 200)' \
    'overlay2FrameY = Self.finite(overlay2FrameY, fallback: 450)' \
    'overlay2Width = Self.clamped(overlay2Width, min: 200, max: 3000, fallback: 600)' \
    'overlay2Height = Self.clamped(overlay2Height, min: 100, max: 2000, fallback: 200)'; do
    grep -qF "$overlay_assignment" OST/Sources/Settings/UserSettings.swift \
        || fail "UserSettings must sanitize persisted overlay frame value: $overlay_assignment"
done
if grep -RE 'Int\(settings\.(fontSize|translatedFontSize|backgroundOpacity|maxSubtitleLines|subtitleExpirySeconds|speechPauseSeconds)' OST/Sources/UI >/dev/null; then
    fail "UI labels must not convert raw persisted numeric settings to Int"
fi
if grep -RE '\.font\(\.system\(size: settings\.(fontSize|translatedFontSize)\)' OST/Sources/UI >/dev/null; then
    fail "overlay fonts must use sanitized persisted font sizes"
fi
if grep -RE '\.opacity\(settings\.backgroundOpacity\)' OST/Sources/UI >/dev/null; then
    fail "overlay backgrounds must use sanitized persisted opacity"
fi
for subtitle_binding in \
    'maxSubtitleLinesBinding:settings.maxSubtitleLines' \
    'subtitleExpiryBinding:settings.subtitleExpirySeconds' \
    'speechPauseBinding:settings.speechPauseSeconds'; do
    binding_name="${subtitle_binding%%:*}"
    binding_assignment="${subtitle_binding#*:}"
    awk -v binding="$binding_name" -v assignment="$binding_assignment" '
        $0 ~ "private var " binding { inBinding = 1; sawAssignment = 0; sawCallback = 0; next }
        inBinding && index($0, assignment) { sawAssignment = 1 }
        inBinding && /onSubtitleSettingsChanged\?\(\)/ { sawCallback = 1 }
        inBinding && /^    \}/ {
            if (sawAssignment && sawCallback) { found = 1 }
            inBinding = 0
        }
        END { if (!found) exit 1 }
    ' OST/Sources/UI/FontSettingsView.swift \
        || fail "subtitle settings binding must notify AppState: $binding_name"
done
grep -q 'settings.safeMaxSubtitleLines' OST/Sources/App/OSTApp.swift \
    || fail "OSTApp must pass sanitized subtitle line settings into AppState"
grep -q 'func updateSessionHistoryRecording(enabled: Bool)' OST/Sources/App/AppState.swift \
    || fail "save-session setting changes must update the active capture session"
awk '
    /func updateSessionHistoryRecording\(enabled: Bool\)/ {
        inUpdate = 1
        sawFlag = 0
        sawCaptureGuard = 0
        sawEnabledBranch = 0
        sawNilGuard = 0
        sawStart = 0
        sawDisabledCurrent = 0
        sawEnd = 0
        next
    }
    inUpdate && /saveSessionHistory = enabled/ { sawFlag = 1 }
    inUpdate && /guard isCapturing else \{ return \}/ { sawCaptureGuard = 1 }
    inUpdate && /if enabled/ { sawEnabledBranch = 1 }
    inUpdate && sawEnabledBranch && /sessionRecorder\.currentSession == nil/ { sawNilGuard = 1 }
    inUpdate && sawNilGuard && /sessionRecorder\.startSession\(\)/ { sawStart = 1 }
    inUpdate && /else if sessionRecorder\.currentSession != nil/ { sawDisabledCurrent = 1 }
    inUpdate && sawDisabledCurrent && /sessionRecorder\.endSession\(\)/ { sawEnd = 1 }
    inUpdate && /^    \}/ {
        if (sawFlag && sawCaptureGuard && sawStart && sawDisabledCurrent && sawEnd) { found = 1 }
        inUpdate = 0
    }
    END { if (!found) exit 1 }
' OST/Sources/App/AppState.swift \
    || fail "save-session setting changes must start or end session recording during active capture"
grep -q 'if sessionRecorder.currentSession != nil' OST/Sources/App/AppState.swift \
    || fail "stopCapture must close any active session recorder session"
grep -q 'saveSessionHistoryBinding' OST/Sources/UI/SettingsView.swift \
    || fail "save-session toggle must notify the running app"
for debug_binding in \
    'saveSessionHistoryBinding:settings.saveSessionHistory:onSaveSessionHistoryChanged' \
    'sessionWindowAlwaysOnTopBinding:settings.sessionWindowAlwaysOnTop:onSessionWindowAlwaysOnTopChanged'; do
    binding_name="${debug_binding%%:*}"
    rest="${debug_binding#*:}"
    binding_assignment="${rest%%:*}"
    binding_callback="${rest#*:}"
    awk -v binding="$binding_name" -v assignment="$binding_assignment" -v callback="$binding_callback" '
        $0 ~ "private var " binding { inBinding = 1; sawAssignment = 0; sawCallback = 0; next }
        inBinding && index($0, assignment) { sawAssignment = 1 }
        inBinding && index($0, callback "?()") { sawCallback = 1 }
        inBinding && /^    \}/ {
            if (sawAssignment && sawCallback) { found = 1 }
            inBinding = 0
        }
        END { if (!found) exit 1 }
    ' OST/Sources/UI/SettingsView.swift \
        || fail "debug settings binding must notify the running app: $binding_name"
done

echo "== Behavioral checks =="
session_recorder_test_src="$tmp_dir/session-recorder-test.swift"
session_recorder_test_bin="$tmp_dir/session-recorder-test"
session_recorder_store="$tmp_dir/session-recorder-store/sessions.json"
cat > "$session_recorder_test_src" <<'SWIFT'
import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(message)
    }
}

@main
struct Runner {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw TestFailure("expected a storage path argument")
        }

        let storageURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let storageDir = storageURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: storageDir.path) {
            try fileManager.removeItem(at: storageDir)
        }

        let recorder = SessionRecorder(storageURL: storageURL)
        try expect(recorder.pastSessions.isEmpty, "new test store should start empty")
        recorder.record(id: UUID(), recognized: "orphan", translated: "orphan translation")
        try expect(recorder.currentSession == nil, "recording without an active session must not create one")
        try expect(recorder.pastSessions.isEmpty, "recording without an active session must not add history")

        let entryID = UUID()
        recorder.startSession()
        recorder.record(id: entryID, recognized: "hello", translated: "")
        recorder.startSession()
        try expect(recorder.currentSession?.entries.count == 1, "starting an already-active session must not discard entries")
        recorder.record(id: entryID, recognized: "duplicate", translated: "")
        try expect(recorder.currentSession?.entries.count == 1, "duplicate entry ids must be ignored")
        try expect(recorder.currentSession?.entries.first?.recognizedText == "hello", "duplicate entry must not replace original text")
        let otherEntryID = UUID()
        recorder.record(id: otherEntryID, recognized: "keep me", translated: "keep translation")
        try expect(recorder.currentSession?.entries.count == 2, "distinct entry ids must append to the active session")

        recorder.updateTranslation(id: entryID, translated: "translated")
        try expect(recorder.currentSession?.entries.first?.translatedText == "translated", "current-session translations must update by entry id")
        recorder.updateCurrentTranslation(id: entryID, translated: "current only")
        try expect(recorder.currentSession?.entries.first?.translatedText == "current only", "current-session-only translations must update active entries")

        recorder.clearCurrentTranslations(ids: [entryID])
        try expect(recorder.currentSession?.entries.first?.translatedText == "", "current-session translations must clear by entry id")
        try expect(recorder.currentSession?.entries.last?.translatedText == "keep translation", "translation clearing must preserve entries whose ids were not requested")

        recorder.endSession()
        try expect(recorder.currentSession == nil, "ending a session must clear currentSession")
        try expect(recorder.pastSessions.count == 1, "non-empty sessions must move into history")

        let reloaded = SessionRecorder(storageURL: storageURL)
        try expect(reloaded.pastSessions.count == 1, "saved sessions must reload from disk")
        try expect(reloaded.pastSessions.first?.entries.first?.translatedText == "", "cleared translations must persist when the session ends")

        reloaded.updateTranslation(id: entryID, translated: "late translation")
        let reloadedAgain = SessionRecorder(storageURL: storageURL)
        try expect(reloadedAgain.pastSessions.first?.entries.first?.translatedText == "late translation", "late translation updates for past sessions must persist")
        reloadedAgain.updateTranslation(id: UUID(), translated: "ghost translation")
        let reloadedAfterUnknown = SessionRecorder(storageURL: storageURL)
        try expect(reloadedAfterUnknown.pastSessions.count == 1, "unknown translation ids must not create sessions")
        try expect(reloadedAfterUnknown.pastSessions.first?.entries.count == 2, "unknown translation ids must not create entries")
        try expect(reloadedAfterUnknown.pastSessions.first?.entries.first?.translatedText == "late translation", "unknown translation ids must not change existing translations")
        reloadedAgain.updateCurrentTranslation(id: entryID, translated: "wrong language")
        let reloadedAfterCurrentOnly = SessionRecorder(storageURL: storageURL)
        try expect(reloadedAfterCurrentOnly.pastSessions.first?.entries.first?.translatedText == "late translation", "current-session-only updates must not rewrite past sessions")

        let emptyRecorder = SessionRecorder(storageURL: storageURL)
        let existingCount = emptyRecorder.pastSessions.count
        emptyRecorder.startSession()
        emptyRecorder.endSession()
        try expect(emptyRecorder.pastSessions.count == existingCount, "empty sessions must be discarded")

        let trimRecorder = SessionRecorder(storageURL: storageURL)
        for index in 0..<22 {
            trimRecorder.startSession()
            trimRecorder.record(id: UUID(), recognized: "item \(index)", translated: "")
            trimRecorder.endSession()
        }
        try expect(trimRecorder.pastSessions.count == 20, "in-memory history must stay bounded")

        let trimmedReload = SessionRecorder(storageURL: storageURL)
        try expect(trimmedReload.pastSessions.count == 20, "persisted history must stay bounded")
        try expect(trimmedReload.pastSessions.first?.entries.first?.recognizedText == "item 21", "newest sessions must remain first after trimming")

        trimmedReload.clearHistory()
        try expect(trimmedReload.pastSessions.isEmpty, "clearHistory must clear in-memory sessions")
        let clearedReload = SessionRecorder(storageURL: storageURL)
        try expect(clearedReload.pastSessions.isEmpty, "clearHistory must persist an empty session list")
    }
}
SWIFT
xcrun swiftc \
    -parse-as-library \
    -sdk "$(xcrun --show-sdk-path)" \
    -target arm64-apple-macosx15.0 \
    -swift-version 5 \
    -warnings-as-errors \
    -warn-concurrency \
    -strict-concurrency=complete \
    OST/Sources/App/Logger.swift \
    OST/Sources/App/SessionRecorder.swift \
    "$session_recorder_test_src" \
    -o "$session_recorder_test_bin"
"$session_recorder_test_bin" "$session_recorder_store"

user_settings_test_src="$tmp_dir/user-settings-test.swift"
user_settings_test_bin="$tmp_dir/user-settings-test"
user_settings_home="$tmp_dir/user-settings-home"
cat > "$user_settings_test_src" <<'SWIFT'
import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(message)
    }
}

@main
struct Runner {
    @MainActor
    static func main() throws {
        let defaults = UserDefaults.standard
        let languages = SupportedLanguage.allCases
        try expect(
            languages.map(\.rawValue) == ["en-US", "zh-Hans", "ja-JP", "ko-KR"],
            "supported languages must stay in the documented picker order"
        )
        try expect(SupportedLanguage.english.speechLocale.identifier == "en-US", "English speech locale must target US English")
        try expect(SupportedLanguage.chineseSimplified.speechLocale.identifier == "zh-CN", "Simplified Chinese speech locale must target Mainland Chinese")
        try expect(SupportedLanguage.japanese.speechLocale.identifier == "ja-JP", "Japanese speech locale must target Japan")
        try expect(SupportedLanguage.korean.speechLocale.identifier == "ko-KR", "Korean speech locale must target Korea")
        try expect(SupportedLanguage.english.translationLocale.languageCode?.identifier == "en", "English translation language must be en")
        try expect(SupportedLanguage.chineseSimplified.translationLocale.languageCode?.identifier == "zh", "Simplified Chinese translation language must be zh")
        try expect(SupportedLanguage.chineseSimplified.translationLocale.script?.identifier == "Hans", "Simplified Chinese translation language must preserve Hans script")
        try expect(SupportedLanguage.japanese.translationLocale.languageCode?.identifier == "ja", "Japanese translation language must be ja")
        try expect(SupportedLanguage.korean.translationLocale.languageCode?.identifier == "ko", "Korean translation language must be ko")

        let keys = [
            "sourceLanguage",
            "targetLanguage",
            "fontSize",
            "backgroundOpacity",
            "showOriginalText",
            "showTranslation",
            "saveSessionHistory",
            "sessionWindowAlwaysOnTop",
            "useOnDeviceRecognition",
            "allowOnlineTranslationFallback",
            "overlayLocked",
            "overlayFrameX",
            "overlayFrameY",
            "overlayWidth",
            "overlayHeight",
            "maxSubtitleLines",
            "subtitleExpirySeconds",
            "speechPauseSeconds",
            "translatedFontSize",
            "overlayDisplayMode",
            "overlay2FrameX",
            "overlay2FrameY",
            "overlay2Width",
            "overlay2Height",
            "overlay2Locked"
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }

        do {
            let defaultSettings = UserSettings()
            try expect(defaultSettings.sourceLanguage == "en-US", "source language must default to English")
            try expect(defaultSettings.targetLanguage == "ko-KR", "target language must default to Korean")
            try expect(defaultSettings.fontSize == 20, "original font size must default to 20")
            try expect(defaultSettings.translatedFontSize == 20, "translated font size must default to 20")
            try expect(defaultSettings.backgroundOpacity == 0.5, "background opacity must default to 50 percent")
            try expect(defaultSettings.showOriginalText, "original text must default to visible")
            try expect(defaultSettings.showTranslation, "translation text must default to visible")
            try expect(defaultSettings.maxSubtitleLines == 3, "max subtitle lines must default to 3")
            try expect(defaultSettings.subtitleExpirySeconds == 20, "subtitle expiry must default to 20 seconds")
            try expect(defaultSettings.speechPauseSeconds == 3, "speech pause must default to 3 seconds")
            try expect(defaultSettings.overlayDisplayMode == "split", "overlay display mode must default to split")
            try expect(defaultSettings.saveSessionHistory, "session history must default to enabled")
            try expect(!defaultSettings.sessionWindowAlwaysOnTop, "session history window must not default to always on top")
            try expect(defaultSettings.useOnDeviceRecognition, "on-device recognition must default to enabled")
            try expect(!defaultSettings.allowOnlineTranslationFallback, "online translation fallback must default to disabled")
            try expect(defaultSettings.overlayLocked, "primary overlay must default to locked")
            try expect(defaultSettings.overlay2Locked, "translation overlay must default to locked")
        }

        defaults.set("bad-source", forKey: "sourceLanguage")
        defaults.set("bad-target", forKey: "targetLanguage")
        defaults.set(1.0, forKey: "fontSize")
        defaults.set(2.0, forKey: "backgroundOpacity")
        defaults.set(false, forKey: "showOriginalText")
        defaults.set(false, forKey: "showTranslation")
        defaults.set(Double.nan, forKey: "overlayFrameX")
        defaults.set(Double.infinity, forKey: "overlayFrameY")
        defaults.set(10.0, forKey: "overlayWidth")
        defaults.set(9_999.0, forKey: "overlayHeight")
        defaults.set(99.0, forKey: "maxSubtitleLines")
        defaults.set(1.0, forKey: "subtitleExpirySeconds")
        defaults.set(99.0, forKey: "speechPauseSeconds")
        defaults.set(9_999.0, forKey: "translatedFontSize")
        defaults.set("stacked", forKey: "overlayDisplayMode")
        defaults.set(-Double.infinity, forKey: "overlay2FrameX")
        defaults.set(Double.nan, forKey: "overlay2FrameY")
        defaults.set(9_999.0, forKey: "overlay2Width")
        defaults.set(1.0, forKey: "overlay2Height")

        let settings = UserSettings()
        try expect(settings.sourceLanguage == "en-US", "invalid source language must reset")
        try expect(settings.targetLanguage == "ko-KR", "invalid target language must reset")
        try expect(settings.fontSize == 12, "font size must clamp to lower bound")
        try expect(settings.backgroundOpacity == 1, "background opacity must clamp to upper bound")
        try expect(settings.showOriginalText == false, "original text setting should preserve explicit false")
        try expect(settings.showTranslation == true, "both text columns hidden must re-enable translation")
        try expect(settings.overlayFrameX == 200, "primary overlay x must reset non-finite values")
        try expect(settings.overlayFrameY == 200, "primary overlay y must reset non-finite values")
        try expect(settings.overlayWidth == 200, "primary overlay width must clamp to lower bound")
        try expect(settings.overlayHeight == 2000, "primary overlay height must clamp to upper bound")
        try expect(settings.maxSubtitleLines == 10, "max subtitle lines must clamp to upper bound")
        try expect(settings.subtitleExpirySeconds == 3, "subtitle expiry must clamp to lower bound")
        try expect(settings.speechPauseSeconds == 5, "speech pause must clamp to upper bound")
        try expect(settings.translatedFontSize == 72, "translated font size must clamp to upper bound")
        try expect(settings.overlayDisplayMode == "split", "invalid display mode must reset")
        try expect(settings.overlay2FrameX == 200, "secondary overlay x must reset non-finite values")
        try expect(settings.overlay2FrameY == 450, "secondary overlay y must reset non-finite values")
        try expect(settings.overlay2Width == 3000, "secondary overlay width must clamp to upper bound")
        try expect(settings.overlay2Height == 100, "secondary overlay height must clamp to lower bound")

        for key in keys {
            defaults.removeObject(forKey: key)
        }
        defaults.set("auto", forKey: "sourceLanguage")
        defaults.set("ja-JP", forKey: "targetLanguage")
        let autoSettings = UserSettings()
        try expect(autoSettings.sourceLanguage == "auto", "Auto source language must survive launch sanitization")
        try expect(autoSettings.targetLanguage == "ja-JP", "valid target language must survive launch sanitization")

        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}
SWIFT
mkdir -p "$user_settings_home"
xcrun swiftc \
    -parse-as-library \
    -sdk "$(xcrun --show-sdk-path)" \
    -target arm64-apple-macosx15.0 \
    -swift-version 5 \
    -warnings-as-errors \
    -warn-concurrency \
    -strict-concurrency=complete \
    -framework AppKit \
    -framework SwiftUI \
    OST/Sources/Speech/SupportedLanguages.swift \
    OST/Sources/Settings/UserSettings.swift \
    "$user_settings_test_src" \
    -o "$user_settings_test_bin"
HOME="$user_settings_home" "$user_settings_test_bin"

app_state_test_src="$tmp_dir/app-state-test.swift"
app_state_test_bin="$tmp_dir/app-state-test"
app_state_session_store="$tmp_dir/app-state-session-store/sessions.json"
cat > "$app_state_test_src" <<'SWIFT'
import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(message)
    }
}

@main
struct Runner {
    @MainActor
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw TestFailure("expected a storage path argument")
        }

        let storageURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let state = AppState(sessionRecorder: SessionRecorder(storageURL: storageURL))

        try expect(!state.isCapturing, "new AppState must start idle")
        try expect(!state.isStartingCapture, "new AppState must not start in capture preflight")
        try expect(state.subtitleEntries.isEmpty, "new AppState must start without subtitle entries")
        try expect(state.liveText.isEmpty, "new AppState must start without live recognized text")
        try expect(state.liveTranslatedText.isEmpty, "new AppState must start without live translated text")
        try expect(state.errorMessage == nil, "new AppState must start without an error")
        try expect(state.maxSubtitleLines == 3, "AppState max subtitle lines must default to 3")
        try expect(state.subtitleExpirySeconds == 20, "AppState subtitle expiry must default to 20 seconds")
        try expect(state.speechPauseSeconds == 3, "AppState speech pause must default to 3 seconds")
        state.errorMessage = "temporary error"
        state.clearError()
        try expect(state.errorMessage == nil, "clearError must remove user-visible capture errors")

        AppLogger.shared.clear()
        for index in 0..<505 {
            AppLogger.shared.log("entry \(index)", category: .app)
        }
        try expect(AppLogger.shared.entries.count == 500, "logger must retain only the newest 500 entries")
        try expect(AppLogger.shared.entries.first?.message == "entry 5", "logger must discard the oldest entries first")
        try expect(AppLogger.shared.entries.last?.message == "entry 504", "logger must keep the newest entry")
        AppLogger.shared.clear()
        try expect(AppLogger.shared.entries.isEmpty, "logger clear must remove all entries")

        state.updateSubtitleSettings(maxLines: 99, expirySeconds: -1, pauseSeconds: 0.1)
        try expect(state.maxSubtitleLines == 10, "max subtitle lines must clamp to upper bound")
        try expect(state.subtitleExpirySeconds == 3, "subtitle expiry must clamp to lower bound")
        try expect(state.speechPauseSeconds == 0.5, "speech pause must clamp to lower bound")

        state.updateSubtitleSettings(maxLines: 0, expirySeconds: 999, pauseSeconds: 99)
        try expect(state.maxSubtitleLines == 1, "max subtitle lines must clamp to lower bound")
        try expect(state.subtitleExpirySeconds == 60, "subtitle expiry must clamp to upper bound")
        try expect(state.speechPauseSeconds == 5, "speech pause must clamp to upper bound")

        state.updateSubtitleSettings(maxLines: .nan, expirySeconds: .infinity, pauseSeconds: -.infinity)
        try expect(state.maxSubtitleLines == 3, "non-finite max subtitle lines must fall back")
        try expect(state.subtitleExpirySeconds == 20, "non-finite subtitle expiry must fall back")
        try expect(state.speechPauseSeconds == 3, "non-finite speech pause must fall back")

        state.updateSessionHistoryRecording(enabled: true)
        try expect(state.sessionRecorder.currentSession == nil, "enabling session history while idle must not start a session")
        state.updateSessionHistoryRecording(enabled: false)
        try expect(state.sessionRecorder.currentSession == nil, "disabling session history while idle must not create a session")
        try expect(state.detectedLanguage == nil, "new AppState must not start with a detected language")
        state.enableAutoDetect()
        try expect(state.detectedLanguage == nil, "enabling auto-detect must clear any previous detected language")
        state.disableAutoDetect()
        try expect(state.detectedLanguage == nil, "disabling auto-detect must clear detected language state")

        try expect(state.beginStartingCapture(), "first capture preflight should enter starting state")
        try expect(state.isStartingCapture, "capture preflight should publish starting state")
        try expect(!state.beginStartingCapture(), "capture preflight must reject duplicate starts")
        state.finishStartingCapture()
        try expect(!state.isStartingCapture, "finishStartingCapture must clear starting state")
        try expect(state.beginStartingCapture(), "capture preflight should enter starting state before stop")
        await state.stopCapture()
        try expect(!state.isStartingCapture, "stopCapture must clear an in-flight capture start")
        try expect(!state.isCapturing, "stopCapture must leave cancelled in-flight starts idle")
    }
}
SWIFT
xcrun swiftc \
    -parse-as-library \
    -sdk "$(xcrun --show-sdk-path)" \
    -target arm64-apple-macosx15.0 \
    -swift-version 5 \
    -warnings-as-errors \
    -warn-concurrency \
    -strict-concurrency=complete \
    OST/Sources/App/Logger.swift \
    OST/Sources/App/SessionRecorder.swift \
    OST/Sources/App/AppState.swift \
    OST/Sources/Audio/SystemAudioCapture.swift \
    OST/Sources/Speech/SpeechRecognizer.swift \
    OST/Sources/Speech/SupportedLanguages.swift \
    OST/Sources/Translation/TranslationConfig.swift \
    OST/Sources/Translation/TranslationService.swift \
    "$app_state_test_src" \
    -o "$app_state_test_bin"
"$app_state_test_bin" "$app_state_session_store"

translation_service_test_src="$tmp_dir/translation-service-test.swift"
translation_service_test_bin="$tmp_dir/translation-service-test"
cat > "$translation_service_test_src" <<'SWIFT'
import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(message)
    }
}

@main
struct Runner {
    @MainActor
    static func main() async throws {
        let service = TranslationService()
        let english = Locale.Language(identifier: "en")
        let japanese = Locale.Language(identifier: "ja")
        let korean = Locale.Language(identifier: "ko")
        let simplifiedChinese = Locale.Language(identifier: "zh-Hans")
        let traditionalChinese = Locale.Language(identifier: "zh-Hant")

        try expect(!service.allowsOnlineFallback, "online fallback must default to disabled")
        try expect(service.configuration == nil, "new translation service must not start configured")
        try expect(service.statusMessage == nil, "new translation service must not start with status text")
        try expect(service.lastErrorMessage == nil, "new translation service must not start with an error")
        try expect(service.sourceLanguage == nil, "new translation service must not start with a source language")
        try expect(service.targetLanguage == nil, "new translation service must not start with a target language")
        try expect(service.configurationGeneration == 0, "new translation service generation must start at zero")
        let emptyTranslation = try await service.translate("   ", generation: service.configurationGeneration)
        try expect(emptyTranslation == "", "blank translation input must return an empty result")
        try expect(service.lastErrorMessage == nil, "blank translation input must not publish an error")

        let sameLanguageAvailability = await TranslationConfig.availabilityState(source: english, target: english)
        try expect(sameLanguageAvailability == .installed, "same-language availability must not require a language pack")
        try expect(
            TranslationConfig.isSameLanguagePair(source: simplifiedChinese, target: simplifiedChinese),
            "matching Chinese scripts must count as the same translation language"
        )
        try expect(
            !TranslationConfig.isSameLanguagePair(source: simplifiedChinese, target: traditionalChinese),
            "different Chinese scripts must not bypass translation"
        )

        service.configure(source: english, target: english)
        let sameLanguageGeneration = service.configurationGeneration
        try expect(service.configuration == nil, "same-language pairs must not create an Apple Translation configuration")
        try expect(service.statusMessage == nil, "same-language pairs must not show a preparing status")
        service.setOnlineFallbackEnabled(true)
        try expect(service.allowsOnlineFallback, "online fallback setting must be observable after enabling")
        try expect(service.statusMessage == nil, "same-language pairs must not show fallback status")
        let sameLanguageText = try await service.translate("  hello  ", generation: sameLanguageGeneration)
        try expect(sameLanguageText == "hello", "same-language translation must return trimmed input")
        try expect(service.lastErrorMessage == nil, "same-language translation must not report fallback errors")
        let sameLanguageReady = await service.waitForSessionReady(timeout: 0.01)
        try expect(sameLanguageReady, "same-language pairs must be immediately ready")
        service.setOnlineFallbackEnabled(false)
        try expect(!service.allowsOnlineFallback, "online fallback setting must be observable after disabling")

        service.configure(source: english, target: korean)
        let pendingGeneration = service.configurationGeneration
        try expect(service.configuration != nil, "different-language pairs must create a translation configuration")
        let pendingReady = await service.waitForSessionReady(timeout: 0.01)
        try expect(!pendingReady, "missing Apple Translation session must not report ready")
        try expect(
            service.statusMessage == "Translation is still preparing. Open Settings > Languages if translation stays blank.",
            "missing Apple Translation session with fallback disabled must show non-fallback status"
        )
        service.setOnlineFallbackEnabled(true)
        try expect(
            service.statusMessage == "Online fallback enabled until Apple Translation is ready.",
            "enabling fallback while Translation is pending must show fallback status"
        )
        service.setOnlineFallbackEnabled(false)
        try expect(
            service.statusMessage == "Translation is not ready. Open Settings > Languages if translation stays blank.",
            "disabling fallback while Translation is pending must clear stale fallback status"
        )
        service.setOnlineFallbackEnabled(true, reportPendingStatus: false)
        try expect(service.statusMessage == nil, "idle fallback changes must not show stale pending translation status")
        service.setOnlineFallbackEnabled(false, reportPendingStatus: false)
        try expect(service.statusMessage == nil, "idle fallback disable must keep translation status clear")

        service.configure(source: english, target: english)
        let sameLanguageAfterPendingGeneration = service.configurationGeneration
        try expect(sameLanguageAfterPendingGeneration == pendingGeneration + 1, "same-language reconfiguration must advance generation after a pending pair")
        try expect(service.configuration == nil, "same-language reconfiguration must clear a pending Apple Translation configuration")
        try expect(service.statusMessage == nil, "same-language reconfiguration must clear pending status")
        try expect(service.sourceLanguage?.languageCode?.identifier == "en", "same-language reconfiguration must retain source language")
        try expect(service.targetLanguage?.languageCode?.identifier == "en", "same-language reconfiguration must retain target language")
        let sameLanguageAfterPendingText = try await service.translate("  still local  ", generation: sameLanguageAfterPendingGeneration)
        try expect(sameLanguageAfterPendingText == "still local", "same-language reconfiguration must bypass fallback and return trimmed input")

        service.configure(source: simplifiedChinese, target: traditionalChinese)
        let chineseScriptGeneration = service.configurationGeneration
        try expect(
            service.configuration != nil,
            "different Chinese scripts must create an Apple Translation configuration"
        )
        try expect(
            service.statusMessage == "Preparing translation...",
            "different Chinese scripts must not use same-language bypass status"
        )

        service.configure(source: english, target: korean)
        let pendingGenerationAfterSameLanguage = service.configurationGeneration
        try expect(
            pendingGenerationAfterSameLanguage == chineseScriptGeneration + 1,
            "different-language reconfiguration after same-language bypass must advance generation"
        )
        try expect(service.configuration != nil, "different-language reconfiguration after same-language bypass must create a configuration")
        try expect(service.statusMessage == "Preparing translation...", "different-language reconfiguration after same-language bypass must show preparing status")
        service.invalidateSession(preservingPendingTranslations: true)
        try expect(
            service.configurationGeneration == pendingGenerationAfterSameLanguage,
            "preserving pending translations must not advance the translation generation"
        )
        try expect(service.configuration != nil, "preserving pending translations must keep the active configuration")
        try expect(
            service.sourceLanguage?.languageCode?.identifier == "en",
            "preserving pending translations must retain the source language"
        )
        try expect(
            service.targetLanguage?.languageCode?.identifier == "ko",
            "preserving pending translations must retain the target language"
        )
        try expect(service.statusMessage == nil, "preserving pending translations must clear visible status")
        try expect(service.lastErrorMessage == nil, "preserving pending translations must clear visible errors")
        do {
            _ = try await service.translate("hello", generation: pendingGenerationAfterSameLanguage)
            throw TestFailure("translation without a session and fallback disabled must fail")
        } catch TranslationServiceError.sessionUnavailable {
            try expect(service.lastErrorMessage != nil, "session-unavailable errors must be user-visible")
        }

        service.configure(source: japanese, target: korean)
        try expect(service.lastErrorMessage == nil, "new translation configuration must clear previous visible errors")
        try expect(service.statusMessage == "Preparing translation...", "new translation configuration must show preparing status")
        try expect(service.sourceLanguage?.languageCode?.identifier == "ja", "new translation configuration must retain source language")
        try expect(service.targetLanguage?.languageCode?.identifier == "ko", "new translation configuration must retain target language")
        do {
            _ = try await service.translate("hello", generation: pendingGenerationAfterSameLanguage)
            throw TestFailure("stale translation generation must fail")
        } catch TranslationServiceError.staleConfiguration {
            try expect(service.lastErrorMessage == nil, "stale translations must not overwrite user-visible errors")
        }

        let generationBeforeInvalidate = service.configurationGeneration
        service.invalidateSession()
        try expect(
            service.configurationGeneration == generationBeforeInvalidate + 1,
            "full invalidation must advance the translation generation"
        )
        try expect(service.configuration == nil, "full invalidation must clear the Apple Translation configuration")
        try expect(service.sourceLanguage == nil, "full invalidation must clear the source language")
        try expect(service.targetLanguage == nil, "full invalidation must clear the target language")
        try expect(service.statusMessage == nil, "full invalidation must clear visible status")
        try expect(service.lastErrorMessage == nil, "full invalidation must clear visible errors")
        service.setOnlineFallbackEnabled(true)
        do {
            _ = try await service.translate("hello", generation: service.configurationGeneration)
            throw TestFailure("fallback without retained source/target languages must fail before network access")
        } catch TranslationServiceError.configurationUnavailable {
            try expect(service.lastErrorMessage != nil, "fallback configuration errors must be user-visible")
            try expect(service.statusMessage == nil, "failed fallback attempts must clear in-progress fallback status")
        }
    }
}
SWIFT
xcrun swiftc \
    -parse-as-library \
    -sdk "$(xcrun --show-sdk-path)" \
    -target arm64-apple-macosx15.0 \
    -swift-version 5 \
    -warnings-as-errors \
    -warn-concurrency \
    -strict-concurrency=complete \
    OST/Sources/App/Logger.swift \
    OST/Sources/Translation/TranslationConfig.swift \
    OST/Sources/Translation/TranslationService.swift \
    "$translation_service_test_src" \
    -o "$translation_service_test_bin"
"$translation_service_test_bin"

echo "== Type check =="
./build.sh --typecheck

echo "All checks passed."
