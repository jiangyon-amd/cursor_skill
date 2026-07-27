#!/usr/bin/env bash
set -euo pipefail

# Install the native Claude Code binary into
#   ~/.local/share/claude/versions/<version>
# and point ~/.local/bin/claude at it.
#
# Robust against the slow/blocked binary download we hit inside containers
# (the native binary is ~240MB; on throttled networks the official installer
# can stall or time out). When the download is impractical, "seed" the install
# from an existing native binary on the same OS/arch instead.
#
# Usage:
#   install_native.sh                     # official installer (with timeout), then guidance
#   install_native.sh --seed PATH         # copy an existing native binary from PATH
#   install_native.sh --timeout 600       # extend official-download timeout (seconds)
#   CLAUDE_NATIVE_SEED=PATH install_native.sh
#
# PATH (seed) may be either:
#   - a versioned native binary file, e.g. /some/where/claude/versions/2.1.178
#   - a directory containing one or more such version files (newest is used)
#
# Container note: to seed a container from a host install, first copy the
# binary in from outside, then run with --seed, e.g.:
#   docker cp ~/.local/share/claude/versions/<ver> <ctr>:/tmp/claude-seed
#   docker exec <ctr> bash -lc 'install_native.sh --seed /tmp/claude-seed'

TIMEOUT=300
SEED="${CLAUDE_NATIVE_SEED:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --seed) SEED="${2:-}"; shift 2 ;;
    --seed=*) SEED="${1#*=}"; shift ;;
    --timeout) TIMEOUT="${2:-300}"; shift 2 ;;
    --timeout=*) TIMEOUT="${1#*=}"; shift ;;
    -h|--help) sed -n '3,30p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

BIN_DIR="${HOME}/.local/bin"
VERSIONS_DIR="${HOME}/.local/share/claude/versions"
mkdir -p "${BIN_DIR}" "${VERSIONS_DIR}"

link_and_verify() {
  # $1 = absolute path to an installed version binary
  local target="$1"
  chmod +x "${target}" 2>/dev/null || true
  ln -sf "${target}" "${BIN_DIR}/claude"
  if "${BIN_DIR}/claude" --version >/dev/null 2>&1; then
    echo "native claude ready: $(${BIN_DIR}/claude --version)"
    echo "  binary : ${target}"
    echo "  link   : ${BIN_DIR}/claude"
    return 0
  fi
  echo "ERROR: installed binary did not run: ${target}" >&2
  return 1
}

resolve_seed_binary() {
  # Echo the binary path to copy from a seed file or directory.
  local seed="$1"
  if [ -f "${seed}" ]; then
    echo "${seed}"; return 0
  fi
  if [ -d "${seed}" ]; then
    # Pick the lexically newest entry that looks like a version (X.Y.Z) or any file.
    local pick
    pick="$(ls -1 "${seed}" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)"
    if [ -z "${pick}" ]; then
      pick="$(ls -1 "${seed}" 2>/dev/null | sort -V | tail -1)"
    fi
    [ -n "${pick}" ] && echo "${seed%/}/${pick}" && return 0
  fi
  return 1
}

# Path A: seed from an existing binary (fast, offline-friendly).
if [ -n "${SEED}" ]; then
  src="$(resolve_seed_binary "${SEED}")" || {
    echo "ERROR: no usable binary found under seed path: ${SEED}" >&2
    exit 1
  }
  ver="$("${src}" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  [ -n "${ver}" ] || ver="$(basename "${src}")"
  dest="${VERSIONS_DIR}/${ver}"
  if [ "$(readlink -f "${src}")" = "$(readlink -f "${dest}")" ]; then
    echo "native claude ${ver} already present at ${dest}; relinking"
  else
    echo "seeding native claude ${ver} from ${src}"
    cp -f "${src}" "${dest}"
  fi
  link_and_verify "${dest}"
  exit $?
fi

# Path B: official installer, but do not let a stalled download hang forever.
echo "attempting official install (timeout ${TIMEOUT}s)..."
if command -v curl >/dev/null 2>&1; then
  if timeout "${TIMEOUT}" bash -c 'curl -fsSL https://claude.ai/install.sh | bash' ; then
    [ -x "${BIN_DIR}/claude" ] && link_and_verify "$(readlink -f "${BIN_DIR}/claude")" && exit 0
  fi
fi

echo "" >&2
echo "official install did not complete (slow/blocked download is common in containers)." >&2
echo "Seed from an existing same-OS/arch install instead, e.g.:" >&2
echo "  install_native.sh --seed ~/.local/share/claude/versions" >&2
echo "  # or, into a container:" >&2
echo "  docker cp ~/.local/share/claude/versions/<ver> <ctr>:/tmp/claude-seed" >&2
echo "  docker exec <ctr> bash -lc 'install_native.sh --seed /tmp/claude-seed'" >&2
exit 1
