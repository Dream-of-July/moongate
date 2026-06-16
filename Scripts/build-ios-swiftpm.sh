#!/bin/zsh
# Build the SwiftPM iOS shared-code host against local Apple SDKs.
# This verifies SwiftPM-resolvable shared/iOS source compatibility; it is not
# the native Xcode iOS app-bundle host, does not sign, does not install to a device,
# does not create an .ipa, and does not replace Xcode/device QA.
# iOS 26 SDK-backed adapters need Xcode/iPhoneOS 26 SDK validation, preferably
# through Scripts/build-ios-xcode.sh or a real Xcode/device gate.
set -euo pipefail

PROJECT_DIR="${0:a:h:h}"
PRODUCT="MoongateiOSApp"
MODE="${1:-all}"
SCRATCH_ROOT="${MOONGATE_IOS_SCRATCH_ROOT:-/private/tmp}"

echo "==> iOS SwiftPM gate: shared code / SwiftPM host only; not the native Xcode app-bundle host."
echo "==> iOS 26 SDK-backed adapters require Xcode/iPhoneOS 26 SDK validation."

build_for_sdk() {
    local label="$1"
    local sdk_name="$2"
    local triple="$3"
    local scratch="$SCRATCH_ROOT/moongate-ios-${label}-swiftpm-build"
    local sdk_path

    sdk_path="$(xcrun --sdk "$sdk_name" --show-sdk-path)"
    echo "==> swift build $PRODUCT for $label"
    swift build \
        --package-path "$PROJECT_DIR" \
        --sdk "$sdk_path" \
        --triple "$triple" \
        --product "$PRODUCT" \
        --scratch-path "$scratch"
}

case "$MODE" in
    simulator)
        build_for_sdk simulator iphonesimulator arm64-apple-ios17.0-simulator
        ;;
    device)
        build_for_sdk device iphoneos arm64-apple-ios17.0
        ;;
    all)
        build_for_sdk simulator iphonesimulator arm64-apple-ios17.0-simulator
        build_for_sdk device iphoneos arm64-apple-ios17.0
        ;;
    *)
        echo "Usage: $0 [all|simulator|device]" >&2
        exit 64
        ;;
esac
