#!/bin/zsh
# Build the local iOS Xcode app-bundle wrapper without signing.
# This verifies that xcodebuild can produce an app bundle from local sources; it
# does not install to a simulator/device, does not create an ipa, and does not
# contact Apple Developer services. iOS 26 SDK-backed adapters require a local
# Xcode/iPhoneOS 26 SDK capable of compiling those code paths.
set -euo pipefail

PROJECT_DIR="${0:a:h:h}"
PROJECT="$PROJECT_DIR/ios/MoongateiOSApp.xcodeproj"
SCHEME="MoongateiOSApp"
CONFIGURATION="${CONFIGURATION:-Debug}"
MOONGATE_IOS_BUNDLE_IDENTIFIER="${MOONGATE_IOS_BUNDLE_IDENTIFIER:-com.local.videodownloader.ios}"
DERIVED_DATA_ROOT="${MOONGATE_IOS_XCODE_DERIVED_DATA:-/private/tmp/moongate-ios-xcode-derived-data-$$}"
SOURCE_PACKAGES_ROOT="${MOONGATE_IOS_XCODE_SOURCE_PACKAGES:-/private/tmp/moongate-ios-xcode-source-packages-$$}"
MODE="${1:-simulator}"

echo "==> iOS Xcode app-bundle gate: unsigned local build only; no install, ipa export, signing, or provisioning."
echo "==> iOS 26 SDK-backed adapters require this gate to run with an Xcode/iPhoneOS 26 SDK."

build_for_destination() {
    local label="$1"
    local sdk="$2"
    local destination="$3"

    echo "==> xcodebuild $SCHEME for $label"
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -sdk "$sdk" \
        -destination "$destination" \
        -derivedDataPath "$DERIVED_DATA_ROOT/$label" \
        -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_ROOT/$label" \
        CODE_SIGNING_ALLOWED=NO \
        MOONGATE_IOS_BUNDLE_IDENTIFIER="$MOONGATE_IOS_BUNDLE_IDENTIFIER" \
        build
}

case "$MODE" in
    simulator)
        build_for_destination simulator iphonesimulator "generic/platform=iOS Simulator"
        ;;
    device)
        build_for_destination device iphoneos "generic/platform=iOS"
        ;;
    all)
        build_for_destination simulator iphonesimulator "generic/platform=iOS Simulator"
        build_for_destination device iphoneos "generic/platform=iOS"
        ;;
    *)
        echo "Usage: $0 [simulator|device|all]" >&2
        exit 64
        ;;
esac
