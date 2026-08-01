#!/usr/bin/env bash
#
# Fills in the machine-generated platform files that are not kept in source
# control (Xcode project, Gradle wrapper jar, launcher icons, storyboards).
#
# Hand-written platform configuration in this repository is never overwritten:
# only files that do not already exist are copied across.
#
# Usage: tool/bootstrap.sh [--skip-pub-get]

set -euo pipefail

SKIP_PUB_GET=0
if [[ "${1:-}" == "--skip-pub-get" ]]; then
  SKIP_PUB_GET=1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter was not found on PATH. Install the Flutter SDK first:" >&2
  echo "  https://docs.flutter.dev/get-started/install" >&2
  exit 1
fi

TEMPLATE="$(mktemp -d)"
trap 'rm -rf "$TEMPLATE"' EXIT

echo "Generating platform template in $TEMPLATE ..."
flutter create --platforms=android,ios --org com.voicereminder --project-name voice_reminder "$TEMPLATE"

copied=0
skipped=0
rejected=0

# Files the template generates that would CONFLICT with this project's curated
# configuration rather than merely duplicate it. Current Flutter templates emit
# Kotlin-DSL Gradle files; this project uses the Groovy DSL, and Gradle picking
# whichever it finds first would silently discard the desugaring, signing and
# SDK settings. The template's MainActivity also lands in the wrong package.
conflicts=(
  "android/build.gradle.kts"
  "android/settings.gradle.kts"
  "android/app/build.gradle.kts"
  "android/app/src/main/kotlin/com/voicereminder/voice_reminder/MainActivity.kt"
)

for folder in android ios; do
  [[ -d "$TEMPLATE/$folder" ]] || continue

  while IFS= read -r -d '' source; do
    relative="${source#"$TEMPLATE"/}"
    destination="$PROJECT_ROOT/$relative"

    is_conflict=0
    for c in "${conflicts[@]}"; do
      [[ "$relative" == "$c" ]] && is_conflict=1 && break
    done
    if [[ "$is_conflict" -eq 1 || "$relative" == *.iml ]]; then
      rejected=$((rejected + 1))
      continue
    fi

    if [[ -e "$destination" ]]; then
      skipped=$((skipped + 1))
      continue
    fi

    mkdir -p "$(dirname "$destination")"
    cp "$source" "$destination"
    copied=$((copied + 1))
    echo "  + $relative"
  done < <(find "$TEMPLATE/$folder" -type f -print0)
done

echo "Bootstrap complete: $copied added, $skipped preserved, $rejected rejected as conflicting."

if [[ "$SKIP_PUB_GET" -eq 0 ]]; then
  cd "$PROJECT_ROOT"
  echo "Running flutter pub get ..."
  flutter pub get
  echo "Running build_runner (Drift + Riverpod code generation) ..."
  dart run build_runner build --delete-conflicting-outputs
fi

echo "Ready. Run \`flutter run\` to launch the app."
