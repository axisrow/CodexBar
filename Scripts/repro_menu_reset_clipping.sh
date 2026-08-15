#!/usr/bin/env bash
# Deterministic visual harness for localized reset-text layout.
# It uses no account credentials, provider requests, Keychain reads, or live defaults.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/CodexBar.app"
LANGUAGE="ru"
RESET_STYLE="countdown"
SCREENSHOT_PATH=""
ALL_LANGUAGES=0
BUILD_FIRST=0
KEEP_RUNNING=0

# Populated from the binary's own AppLanguage.allCases (see --list-languages) once the app
# bundle is resolved, so adding a language cannot silently skip a locale in the matrix.
LANGUAGES=()

usage() {
  cat <<'EOF'
Usage: ./Scripts/repro_menu_reset_clipping.sh [options]

Options:
  --build                 Package CodexBar.app before launching the harness.
  --language CODE         Language to test (default: ru).
  --reset-style STYLE     countdown or absolute (default: countdown).
  --screenshot PATH       Save one menu-window PNG at PATH.
  --all-languages         Capture countdown and absolute PNGs for every app locale.
  --keep-running          Leave the single harness instance running after capture.
  --help                  Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build) BUILD_FIRST=1 ;;
    --language) LANGUAGE="${2:?missing value for --language}"; shift ;;
    --reset-style) RESET_STYLE="${2:?missing value for --reset-style}"; shift ;;
    --screenshot) SCREENSHOT_PATH="${2:?missing value for --screenshot}"; shift ;;
    --all-languages) ALL_LANGUAGES=1 ;;
    --keep-running) KEEP_RUNNING=1 ;;
    --help) usage; exit 0 ;;
    *) printf 'ERROR: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ "$RESET_STYLE" != "countdown" && "$RESET_STYLE" != "absolute" ]]; then
  printf 'ERROR: --reset-style must be countdown or absolute.\n' >&2
  exit 2
fi
if [[ "$ALL_LANGUAGES" == 1 && -n "$SCREENSHOT_PATH" ]]; then
  printf 'ERROR: --all-languages cannot be combined with --screenshot.\n' >&2
  exit 2
fi

if [[ "$BUILD_FIRST" == 1 ]]; then
  "$SCRIPT_DIR/package_app.sh" debug
fi
if [[ ! -x "$APP_BUNDLE/Contents/MacOS/CodexBar" ]]; then
  printf 'ERROR: %s is missing. Run with --build or package the app first.\n' "$APP_BUNDLE" >&2
  exit 1
fi

ARTIFACT_DIR="$(mktemp -d /private/tmp/codexbar-reset-layout.XXXXXX)"
APP_COPY="$ARTIFACT_DIR/CodexBar.app"
cp -R "$APP_BUNDLE" "$APP_COPY"
APP_BINARY="$APP_COPY/Contents/MacOS/CodexBar"
printf 'Artifacts: %s\n' "$ARTIFACT_DIR"

# Compile the capture tool once: interpreting it per capture cost ~2.7s each, which dominated
# a full --all-languages run (46 captures).
CAPTURE_BINARY="$ARTIFACT_DIR/capture_menu_window"
swiftc -Onone -Xfrontend -disable-availability-checking \
  -o "$CAPTURE_BINARY" "$SCRIPT_DIR/capture_menu_window.swift"

if [[ "$ALL_LANGUAGES" == 1 ]]; then
  while IFS= read -r code; do
    [[ -n "$code" ]] && LANGUAGES+=("$code")
  done < <("$APP_BINARY" --list-languages)
  if [[ "${#LANGUAGES[@]}" == 0 ]]; then
    printf 'ERROR: could not read the language list from %s (debug build required).\n' "$APP_BINARY" >&2
    exit 1
  fi
  printf 'Languages: %s\n' "${#LANGUAGES[@]}"
fi

click_menu() {
  local pid="$1"
  osascript \
    -e 'on run argv' \
    -e 'set harnessPID to (item 1 of argv) as integer' \
    -e 'tell application "System Events"' \
    -e 'tell first application process whose unix id is harnessPID' \
    -e 'click menu bar item "CodexBar Debug" of menu bar 2' \
    -e 'end tell' \
    -e 'end tell' \
    -e 'end run' \
    "$pid"
}

wait_for_menu() {
  local pid="$1"
  for _ in {1..50}; do
    if kill -0 "$pid" 2>/dev/null \
      && osascript \
        -e 'on run argv' \
        -e 'set harnessPID to (item 1 of argv) as integer' \
        -e 'tell application "System Events"' \
        -e 'tell first application process whose unix id is harnessPID' \
        -e 'return exists menu bar item "CodexBar Debug" of menu bar 2' \
        -e 'end tell' \
        -e 'end tell' \
        -e 'end run' \
        "$pid" 2>/dev/null | rg -q '^true$'
    then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

capture_one() {
  local language="$1"
  local style="$2"
  local output="$3"
  local stdout="$ARTIFACT_DIR/${language}-${style}.stdout.log"

  "$APP_BINARY" \
    --repro-menu-reset-clipping \
    --language "$language" \
    --reset-style "$style" >"$stdout" 2>&1 &
  local pid=$!

  if ! wait_for_menu "$pid"; then
    printf 'ERROR: %s/%s harness did not expose its menu. Log: %s\n' \
      "$language" "$style" "$stdout" >&2
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi

  click_menu "$pid" >/dev/null
  "$CAPTURE_BINARY" --pid "$pid" --output "$output"
  printf 'Screenshot: %s\n' "$output"

  if [[ "$KEEP_RUNNING" == 1 && "$ALL_LANGUAGES" == 0 ]]; then
    printf 'Harness PID left running: %s\n' "$pid"
  else
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}

if [[ "$ALL_LANGUAGES" == 1 ]]; then
  HTML_PATH="$ARTIFACT_DIR/index.html"
  printf '<!doctype html><meta charset="utf-8"><title>CodexBar reset layout matrix</title><style>body{font:14px sans-serif;background:#222;color:#eee}main{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}figure{margin:0}img{max-width:100%%;background:#000}figcaption{padding:4px 0}</style><main>\n' >"$HTML_PATH"
  for language in "${LANGUAGES[@]}"; do
    for style in countdown absolute; do
      output="$ARTIFACT_DIR/${language}-${style}.png"
      capture_one "$language" "$style" "$output"
      printf '<figure><img src="%s"><figcaption>%s / %s</figcaption></figure>\n' \
        "$(basename "$output")" "$language" "$style" >>"$HTML_PATH"
    done
  done
  printf '</main>\n' >>"$HTML_PATH"
  printf 'Matrix: %s\n' "$HTML_PATH"
else
  if [[ -z "$SCREENSHOT_PATH" ]]; then
    SCREENSHOT_PATH="$ARTIFACT_DIR/${LANGUAGE}-${RESET_STYLE}.png"
  fi
  capture_one "$LANGUAGE" "$RESET_STYLE" "$SCREENSHOT_PATH"
fi
