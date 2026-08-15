#!/usr/bin/env bash
# Host-only launch/relaunch stress harness for #1711.
#
# The app runs with --visibility-harness, which uses isolated defaults and disables provider
# background work and Keychain access. Artifacts are always retained under /private/tmp.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/CodexBar.app"
CYCLES=30
DELAY_SECONDS=3
KEEP_RUNNING=0
BUILD_FIRST=0

usage() {
  cat <<'EOF'
Usage: ./Scripts/repro_menu_bar_visibility.sh [options]

Options:
  --build             Package CodexBar.app before running.
  --cycles N          Number of launch/relaunch cycles (default: 30).
  --delay SECONDS     Time to wait for each startup check (default: 3).
  --keep-running      Leave the final harness instance running.
  --help              Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build) BUILD_FIRST=1 ;;
    --cycles) CYCLES="${2:?missing value for --cycles}"; shift ;;
    --delay) DELAY_SECONDS="${2:?missing value for --delay}"; shift ;;
    --keep-running) KEEP_RUNNING=1 ;;
    --help) usage; exit 0 ;;
    *) printf 'ERROR: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if ! [[ "$CYCLES" =~ ^[1-9][0-9]*$ ]]; then
  printf 'ERROR: --cycles must be a positive integer.\n' >&2
  exit 2
fi
if ! [[ "$DELAY_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  printf 'ERROR: --delay must be a non-negative number.\n' >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  printf 'ERROR: jq is required to inspect harness JSONL results.\n' >&2
  exit 1
fi

if [[ "$BUILD_FIRST" == 1 ]]; then
  "$SCRIPT_DIR/package_app.sh"
fi
if [[ ! -x "$APP_BUNDLE/Contents/MacOS/CodexBar" ]]; then
  printf 'ERROR: %s is missing. Run with --build or package the app first.\n' "$APP_BUNDLE" >&2
  exit 1
fi

ARTIFACT_DIR="$(mktemp -d /private/tmp/codexbar-menu-visibility.XXXXXX)"
APP_COPY="$ARTIFACT_DIR/CodexBar.app"
cp -R "$APP_BUNDLE" "$APP_COPY"
APP_BINARY="$APP_COPY/Contents/MacOS/CodexBar"

printf 'Artifacts: %s\n' "$ARTIFACT_DIR"
printf 'Running %s visibility-harness launch cycles.\n' "$CYCLES"

failures=0
recovery_attempts=0
for cycle in $(seq 1 "$CYCLES"); do
  result="$ARTIFACT_DIR/cycle-$cycle.jsonl"
  stdout="$ARTIFACT_DIR/cycle-$cycle.stdout.log"
  CODEXBAR_VISIBILITY_HARNESS_RESULT_PATH="$result" "$APP_BINARY" --visibility-harness >"$stdout" 2>&1 &
  pid=$!
  sleep "$DELAY_SECONDS"

  if ! kill -0 "$pid" 2>/dev/null; then
    printf 'FAIL cycle %s: process exited before the startup check.\n' "$cycle" >&2
    failures=$((failures + 1))
    continue
  fi
  if [[ ! -s "$result" ]]; then
    printf 'FAIL cycle %s: no visibility evidence was written.\n' "$cycle" >&2
    failures=$((failures + 1))
  else
    terminal_event="$(jq -r 'select(.event == "startup_healthy" or .event == "startup_recovered" or .event == "startup_still_blocked") | .event' "$result" | tail -1)"
    attempts="$(jq -r 'select(.event == "startup_recovery_attempt") | .event' "$result" | wc -l | tr -d ' ')"
    recovery_attempts=$((recovery_attempts + attempts))
    case "$terminal_event" in
      startup_healthy|startup_recovered)
        printf 'PASS cycle %s: %s\n' "$cycle" "$terminal_event"
        ;;
      startup_still_blocked)
        printf 'FAIL cycle %s: status item remained blocked after recovery.\n' "$cycle" >&2
        failures=$((failures + 1))
        ;;
      *)
        printf 'FAIL cycle %s: no terminal startup result.\n' "$cycle" >&2
        failures=$((failures + 1))
        ;;
    esac
  fi

  if [[ "$KEEP_RUNNING" == 1 && "$cycle" == "$CYCLES" ]]; then
    printf 'Final harness PID left running: %s\n' "$pid"
  else
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
done

printf 'Summary: cycles=%s failures=%s recovery_attempts=%s artifacts=%s\n' \
  "$CYCLES" "$failures" "$recovery_attempts" "$ARTIFACT_DIR"
[[ "$failures" == 0 ]]
