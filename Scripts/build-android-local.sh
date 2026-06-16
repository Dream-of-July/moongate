#!/bin/zsh
# Run the local Android build gate only when Gradle is already available.
# This script intentionally does not download Gradle, generate a wrapper, install
# SDK components, resolve dependencies online, or contact external services.
set -euo pipefail

PROJECT_DIR="${0:a:h:h}"
ANDROID_DIR="$PROJECT_DIR/android"

if [[ -x "$ANDROID_DIR/gradlew" ]]; then
    GRADLE_CMD=("$ANDROID_DIR/gradlew")
elif command -v gradle >/dev/null 2>&1; then
    GRADLE_CMD=("gradle")
else
    echo "Android build gate blocked: no android/gradlew and no gradle command on PATH." >&2
    echo "No wrapper download, dependency install, SDK install, or global tool install was attempted." >&2
    exit 66
fi

cd "$ANDROID_DIR"

TASKS=(
    ":core:domain:test"
    ":core:data:test"
    ":core:worker:test"
    ":app:assembleDebug"
)

echo "==> Android local build gate: ${TASKS[*]}"
echo "==> Running Gradle with --offline; cached Gradle dependencies and Android SDK components must already be available."

set +e
"${GRADLE_CMD[@]}" --offline --no-daemon "${TASKS[@]}"
gradle_status=$?
set -e

if (( gradle_status != 0 )); then
    echo "Android offline build gate failed with exit $gradle_status." >&2
    echo "Gradle was run with --offline, so missing cached dependencies, plugin metadata, or Android SDK components were not downloaded." >&2
    echo "Prepare the required Gradle and Android SDK caches outside this local no-download gate, then rerun this script." >&2
    exit "$gradle_status"
fi
