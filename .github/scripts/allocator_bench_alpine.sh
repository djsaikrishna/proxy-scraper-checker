#!/usr/bin/env bash
set -euo pipefail

TOKIO_FEATURE=""
if [[ "${TOKIO_MULTI_THREAD:-false}" == "true" ]]; then
  TOKIO_FEATURE="tokio-multi-thread"
fi

ALPINE_SCRIPT=$(cat <<'INNER_EOF'
set -eu
apk add --no-cache build-base pkgconfig time rust cargo

build_features() {
  allocator="$1"
  features=""
  if [ "$allocator" != "system" ]; then
    features="$allocator"
  fi
  if [ -n "$TOKIO_FEATURE" ]; then
    if [ -n "$features" ]; then
      features="$features,$TOKIO_FEATURE"
    else
      features="$TOKIO_FEATURE"
    fi
  fi
  echo "$features"
}

: > /work/alpine-results.tsv
for allocator in system jemalloc mimalloc_v2 mimalloc_v3; do
  features="$(build_features "$allocator")"
  if [ -n "$features" ]; then
    cargo build --release --locked --features "$features"
  else
    cargo build --release --locked
  fi

  output="$(/usr/bin/time -v /work/target/release/proxy-scraper-checker 2>&1 >/dev/null)"

  peak="$(echo "$output" | awk -F': ' '/Maximum resident set size/ {print $2; exit}')"
  major="$(echo "$output" | awk -F': ' '/Major \(requiring I\/O\) page faults/ {print $2; exit}')"
  minor="$(echo "$output" | awk -F': ' '/Minor \(reclaiming a frame\) page faults/ {print $2; exit}')"

  if [ -z "$peak" ]; then
    echo "Failed to parse peak memory for $allocator" >&2
    exit 1
  fi
  major="${major:-0}"
  minor="${minor:-0}"

  printf "%s\t%s\t%s\t%s\n" "$allocator" "$peak" "$major" "$minor" >> /work/alpine-results.tsv
done
INNER_EOF
)

docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  -e TOKIO_FEATURE="$TOKIO_FEATURE" \
  -e PLATFORM_LABEL="${PLATFORM_LABEL:-unknown}" \
  rust:alpine sh -lc "$ALPINE_SCRIPT"

{
  echo "### ${PLATFORM_LABEL:-unknown} (tokio-multi-thread=${TOKIO_MULTI_THREAD:-false})"
  echo ""
  echo "| Allocator | Peak KB | Major PF | Minor PF |"
  echo "| --- | ---: | ---: | ---: |"
  while IFS=$'\t' read -r allocator peak major minor; do
    echo "| $allocator | $peak | $major | $minor |"
  done < alpine-results.tsv
  echo ""
} >> "$GITHUB_STEP_SUMMARY"
