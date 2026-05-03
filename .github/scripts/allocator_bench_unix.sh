#!/usr/bin/env bash
set -euo pipefail

TOKIO_FEATURE=""
if [[ "${TOKIO_MULTI_THREAD:-false}" == "true" ]]; then
  TOKIO_FEATURE="tokio-multi-thread"
fi

if [[ "$RUNNER_OS" == "Linux" ]]; then
  time_cmd=(/usr/bin/time -v)
else
  time_cmd=(/usr/bin/time -l)
fi

allocator="$ALLOCATOR"
features=""
if [[ "$allocator" != "system" ]]; then
  features="$allocator"
fi
if [[ -n "$TOKIO_FEATURE" ]]; then
  if [[ -n "$features" ]]; then
    features="$features,$TOKIO_FEATURE"
  else
    features="$TOKIO_FEATURE"
  fi
fi

feature_args=()
if [[ -n "$features" ]]; then
  feature_args=(--features "$features")
fi

cargo build --no-default-features --release --locked "${feature_args[@]}"

exe="target/release/proxy-scraper-checker"
if [[ "$RUNNER_OS" == "Windows" ]]; then
  exe="target/release/proxy-scraper-checker.exe"
fi

output="$(${time_cmd[@]} "$exe" 2>&1 >/dev/null)"

if [[ "$RUNNER_OS" == "Linux" ]]; then
  peak="$(echo "$output" | awk -F': ' '/Maximum resident set size/ {print $2; exit}')"
  major="$(echo "$output" | awk -F': ' '/Major \(requiring I\/O\) page faults/ {print $2; exit}')"
  minor="$(echo "$output" | awk -F': ' '/Minor \(reclaiming a frame\) page faults/ {print $2; exit}')"
else
  peak="$(echo "$output" | awk '/maximum resident set size/ {print $1; exit}')"
  major="$(echo "$output" | awk '/page faults/ {print $1; exit}')"
  minor="$(echo "$output" | awk '/page reclaims/ {print $1; exit}')"
fi

if [[ -z "$peak" ]]; then
  echo "Failed to parse peak memory for $allocator" >&2
  exit 1
fi
major="${major:-0}"
minor="${minor:-0}"

if [[ "$RUNNER_OS" != "Linux" ]]; then
  peak=$((peak / 1024))
fi

: > results.tsv
printf "%s\t%s\t%s\t%s\n" "$allocator" "$peak" "$major" "$minor" >> results.tsv

{
  echo "### ${PLATFORM_LABEL:-unknown} (tokio-multi-thread=${TOKIO_MULTI_THREAD:-false}, allocator=${ALLOCATOR})"
  if [[ "$RUNNER_OS" == "Linux" ]]; then
    echo "Threads: $(nproc --all)"
  elif [[ "$RUNNER_OS" == "macOS" ]]; then
    echo "Threads: $(sysctl -n hw.logicalcpu)"
  elif [[ "$RUNNER_OS" == "Windows" ]]; then
    echo "Threads: $NUMBER_OF_PROCESSORS"
  fi
  echo ""
  echo "| Allocator | Peak KB | Major PF | Minor PF |"
  echo "| --- | ---: | ---: | ---: |"
  while IFS=$'\t' read -r allocator peak major minor; do
    echo "| $allocator | $peak | $major | $minor |"
  done < results.tsv
  echo ""
} >> "$GITHUB_STEP_SUMMARY"
