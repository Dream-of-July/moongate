#!/bin/zsh
# Build, install, launch, optionally screenshot, and terminate the local unsigned iOS simulator app.
# This proves a simulator launch gate from local sources only; optional screenshots are
# local-only evidence for manual visual review. It does not run UI automation.
# It does not contact Apple Developer services, does not create or erase simulators,
# does not install to a physical device, and does not create an ipa. Set
# MOONGATE_IOS_SIMULATOR_BOOT_IF_NEEDED=1 to boot an existing available simulator. Set
# MOONGATE_IOS_SIMULATOR_CAPTURE_SCREENSHOT=1 to save a screenshot under
# artifacts/ios-simulator-smoke/. Set MOONGATE_IOS_SIMULATOR_SCREENSHOT_MATRIX=1
# to capture local light/dark, Dynamic Type, and high-contrast variants. Set
# MOONGATE_IOS_SIMULATOR_ADD_STATE=candidates to seed the Add tab with local candidate
# rows for screenshot review.
set -euo pipefail

PROJECT_DIR="${0:a:h:h}"
PROJECT="$PROJECT_DIR/ios/MoongateiOSApp.xcodeproj"
SCHEME="MoongateiOSApp"
CONFIGURATION="${CONFIGURATION:-Debug}"
MOONGATE_IOS_BUNDLE_IDENTIFIER="${MOONGATE_IOS_BUNDLE_IDENTIFIER:-com.local.videodownloader.ios}"
BUNDLE_IDENTIFIER="$MOONGATE_IOS_BUNDLE_IDENTIFIER"
DERIVED_DATA_ROOT="${MOONGATE_IOS_SIMULATOR_DERIVED_DATA:-/private/tmp/moongate-ios-simulator-smoke-derived-data-$$}"
SOURCE_PACKAGES_ROOT="${MOONGATE_IOS_SIMULATOR_SOURCE_PACKAGES:-/private/tmp/moongate-ios-simulator-smoke-source-packages-$$}"
IOS_SIMULATOR_UDID="${IOS_SIMULATOR_UDID:-}"
MOONGATE_IOS_SIMULATOR_BOOT_IF_NEEDED="${MOONGATE_IOS_SIMULATOR_BOOT_IF_NEEDED:-0}"
MOONGATE_IOS_SIMULATOR_CAPTURE_SCREENSHOT="${MOONGATE_IOS_SIMULATOR_CAPTURE_SCREENSHOT:-0}"
MOONGATE_IOS_SIMULATOR_SCREENSHOT_MATRIX="${MOONGATE_IOS_SIMULATOR_SCREENSHOT_MATRIX:-0}"
MOONGATE_IOS_SIMULATOR_SCREENSHOT_TABS="${MOONGATE_IOS_SIMULATOR_SCREENSHOT_TABS:-add}"
MOONGATE_IOS_SIMULATOR_SCREENSHOT_VARIANTS="${MOONGATE_IOS_SIMULATOR_SCREENSHOT_VARIANTS:-light-large,dark-large,light-accessibility-extra-extra-large,dark-accessibility-extra-extra-large,dark-high-contrast}"
MOONGATE_IOS_SIMULATOR_ADD_STATE="${MOONGATE_IOS_SIMULATOR_ADD_STATE:-}"
SCREENSHOT_DIR="${MOONGATE_IOS_SIMULATOR_SCREENSHOT_DIR:-$PROJECT_DIR/artifacts/ios-simulator-smoke}"
SCREENSHOT_DELAY_SECONDS="${MOONGATE_IOS_SIMULATOR_SCREENSHOT_DELAY_SECONDS:-8}"

capture_screenshot_variant() {
    local variant_name="$1"
    mkdir -p "$SCREENSHOT_DIR"
    SCREENSHOT_PATH="$SCREENSHOT_DIR/ios-simulator-${variant_name}-$(date +%Y%m%d-%H%M%S).png"
    sleep "$SCREENSHOT_DELAY_SECONDS"
    echo "==> xcrun simctl io $IOS_SIMULATOR_UDID screenshot $SCREENSHOT_PATH"
    xcrun simctl io "$IOS_SIMULATOR_UDID" screenshot "$SCREENSHOT_PATH"
    echo "Screenshot saved: $SCREENSHOT_PATH"
}

launch_for_screenshot_variant() {
    local variant_name="$1"
    local tab_name="${2:-add}"
    echo "==> xcrun simctl terminate $BUNDLE_IDENTIFIER before $variant_name"
    if ! xcrun simctl terminate "$IOS_SIMULATOR_UDID" "$BUNDLE_IDENTIFIER"; then
        echo "Warning: app was not running before $variant_name." >&2
    fi
    echo "==> xcrun simctl launch $BUNDLE_IDENTIFIER for $variant_name tab $tab_name"
    local launch_args=(--moongate-ios-initial-tab "$tab_name")
    if [[ "$tab_name" == "add" && "$MOONGATE_IOS_SIMULATOR_ADD_STATE" == "candidates" ]]; then
        launch_args+=(--moongate-ios-smoke-add-candidates)
    fi
    xcrun simctl launch "$IOS_SIMULATOR_UDID" "$BUNDLE_IDENTIFIER" --args "${launch_args[@]}"
}

capture_screenshot_matrix_tabs() {
    local variant_name="$1"
    local tab_name
    local tabs=("${(@s:,:)MOONGATE_IOS_SIMULATOR_SCREENSHOT_TABS}")
    for tab_name in "${tabs[@]}"; do
        launch_for_screenshot_variant "$variant_name-$tab_name" "$tab_name"
        capture_screenshot_variant "$variant_name-$tab_name"
    done
}

matrix_should_capture_variant() {
    local variant_name="$1"
    local requested_variants=("${(@s:,:)MOONGATE_IOS_SIMULATOR_SCREENSHOT_VARIANTS}")
    local requested_variant
    for requested_variant in "${requested_variants[@]}"; do
        if [[ "$requested_variant" == "$variant_name" ]]; then
            return 0
        fi
    done
    return 1
}

if [[ -z "$IOS_SIMULATOR_UDID" ]]; then
    IOS_SIMULATOR_UDID="$(xcrun simctl list devices booted | awk -F '[()]' '/Booted/ { print $2; exit }')"
fi

if [[ -z "$IOS_SIMULATOR_UDID" && "$MOONGATE_IOS_SIMULATOR_BOOT_IF_NEEDED" == "1" ]]; then
    IOS_SIMULATOR_UDID="$(xcrun simctl list devices available | awk -F '[()]' '/Shutdown/ { print $2; exit }')"
    if [[ -n "$IOS_SIMULATOR_UDID" ]]; then
        echo "==> xcrun simctl boot $IOS_SIMULATOR_UDID"
        xcrun simctl boot "$IOS_SIMULATOR_UDID"
    fi
fi

if [[ -z "$IOS_SIMULATOR_UDID" ]]; then
    echo "No booted simulator found. Start one in Simulator.app, set IOS_SIMULATOR_UDID, or set MOONGATE_IOS_SIMULATOR_BOOT_IF_NEEDED=1 to boot an existing simulator." >&2
    exit 66
fi

echo "==> xcodebuild $SCHEME for simulator $IOS_SIMULATOR_UDID"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphonesimulator \
    -destination "id=$IOS_SIMULATOR_UDID" \
    -derivedDataPath "$DERIVED_DATA_ROOT" \
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_ROOT" \
    CODE_SIGNING_ALLOWED=NO \
    MOONGATE_IOS_BUNDLE_IDENTIFIER="$MOONGATE_IOS_BUNDLE_IDENTIFIER" \
    build

APP_BUNDLE="$DERIVED_DATA_ROOT/Build/Products/$CONFIGURATION-iphonesimulator/MoongateiOSApp.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Expected app bundle was not produced: $APP_BUNDLE" >&2
    exit 65
fi

echo "==> xcrun simctl bootstatus $IOS_SIMULATOR_UDID"
xcrun simctl bootstatus "$IOS_SIMULATOR_UDID"

echo "==> xcrun simctl install $APP_BUNDLE"
xcrun simctl install "$IOS_SIMULATOR_UDID" "$APP_BUNDLE"

echo "==> xcrun simctl launch $BUNDLE_IDENTIFIER"
xcrun simctl launch "$IOS_SIMULATOR_UDID" "$BUNDLE_IDENTIFIER"

if [[ "$MOONGATE_IOS_SIMULATOR_CAPTURE_SCREENSHOT" == "1" ]]; then
    capture_screenshot_variant "smoke"
fi

if [[ "$MOONGATE_IOS_SIMULATOR_SCREENSHOT_MATRIX" == "1" ]]; then
    if matrix_should_capture_variant "light-large"; then
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID appearance light"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" appearance light
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID content_size large"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" content_size large
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID increase_contrast disabled"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" increase_contrast disabled
        capture_screenshot_matrix_tabs "light-large"
    fi

    if matrix_should_capture_variant "dark-large"; then
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID appearance dark"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" appearance dark
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID content_size large"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" content_size large
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID increase_contrast disabled"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" increase_contrast disabled
        capture_screenshot_matrix_tabs "dark-large"
    fi

    if matrix_should_capture_variant "light-accessibility-extra-extra-large"; then
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID appearance light"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" appearance light
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID content_size accessibility-extra-extra-large"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" content_size accessibility-extra-extra-large
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID increase_contrast disabled"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" increase_contrast disabled
        capture_screenshot_matrix_tabs "light-accessibility-extra-extra-large"
    fi

    if matrix_should_capture_variant "dark-accessibility-extra-extra-large"; then
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID appearance dark"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" appearance dark
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID content_size accessibility-extra-extra-large"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" content_size accessibility-extra-extra-large
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID increase_contrast disabled"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" increase_contrast disabled
        capture_screenshot_matrix_tabs "dark-accessibility-extra-extra-large"
    fi

    if matrix_should_capture_variant "dark-high-contrast"; then
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID appearance dark"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" appearance dark
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID content_size large"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" content_size large
        echo "==> xcrun simctl ui $IOS_SIMULATOR_UDID increase_contrast enabled"
        xcrun simctl ui "$IOS_SIMULATOR_UDID" increase_contrast enabled
        capture_screenshot_matrix_tabs "dark-high-contrast"
    fi
fi

echo "==> xcrun simctl terminate $BUNDLE_IDENTIFIER"
if ! xcrun simctl terminate "$IOS_SIMULATOR_UDID" "$BUNDLE_IDENTIFIER"; then
    echo "Warning: app was already terminated before cleanup." >&2
fi
