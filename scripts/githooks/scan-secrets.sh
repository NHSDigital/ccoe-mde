#!/usr/bin/env bash

set -euo pipefail

root=$(git rev-parse --show-toplevel)
config="$root/scripts/config/gitleaks.toml"
check=${check:-staged-changes}
image=${GITLEAKS_IMAGE:-ghcr.io/gitleaks/gitleaks:v8.24.2}

if [[ "${ALL_FILES:-false}" =~ ^(true|yes|y|on|1|TRUE|YES|Y|ON)$ ]] && [[ "$check" == "staged-changes" ]]; then
  check=whole-history
fi

case "$check" in
  whole-history)
    args=(detect --source "$root" --config "$config" --verbose --redact)
    ;;
  last-commit)
    args=(detect --source "$root" --config "$config" --verbose --redact --log-opts=-1)
    ;;
  staged-changes)
    args=(protect --source "$root" --config "$config" --verbose --redact --staged)
    ;;
  *)
    printf 'Unsupported check: %s\n' "$check" >&2
    exit 126
    ;;
esac

if command -v gitleaks >/dev/null 2>&1 && [[ "${FORCE_USE_DOCKER:-false}" != "true" ]]; then
  gitleaks "${args[@]}"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker run --rm --platform linux/amd64 \
    --volume "$root:/repo:ro" \
    --workdir /repo \
    "$image" \
    "${args[@]/$root//repo}"
else
  printf 'Gitleaks is not installed and Docker is unavailable. Install Gitleaks or Docker.\n' >&2
  exit 1
fi