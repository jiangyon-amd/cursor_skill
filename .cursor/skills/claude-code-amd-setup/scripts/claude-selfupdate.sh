#!/usr/bin/env bash
set -euo pipefail

# Scan for a newer native Claude Code build and install it.
#
# Why this exists instead of `claude update`:
#   - the AMD wrapper exports CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1, and in
#     that mode Claude Code skips its latest-version lookup entirely, so the
#     built-in updater never sees a new release
#   - the official installer runs `claude install`, which rewrites launcher and
#     shell integration and can put ~/.local/bin ahead of /usr/local/bin on PATH,
#     which would shadow the AMD wrapper
#
# This script talks only to Anthropic's release CDN. It needs no gateway key.
#
# Usage:
#   claude-selfupdate                  # scan and install if newer
#   claude-selfupdate --check          # report only; exit 10 if an update exists
#   claude-selfupdate --channel stable # follow the stable channel instead
#   claude-selfupdate --version 2.1.220
#   claude-selfupdate --force          # reinstall the target version
#   claude-selfupdate --allow-downgrade
#   claude-selfupdate --prune [N]      # keep only the newest N builds (default 3)
#   claude-selfupdate --rollback       # relink to the previous installed build
#
# Exit codes:
#   0  success (installed, or already up to date)
#   10 --check only: a newer build is available
#   1  failure

DOWNLOAD_BASE_URL="${CLAUDE_RELEASES_BASE_URL:-https://downloads.claude.ai/claude-code-releases}"
BIN_DIR="${HOME}/.local/bin"
VERSIONS_DIR="${HOME}/.local/share/claude/versions"
LOCK_DIR="${VERSIONS_DIR}/.selfupdate.lock"

CHANNEL="latest"
PIN_VERSION=""
CHECK_ONLY=0
FORCE=0
ALLOW_DOWNGRADE=0
DO_PRUNE=0
PRUNE_KEEP=3
DO_ROLLBACK=0

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    --channel) CHANNEL="${2:?--channel needs a value}"; shift 2 ;;
    --channel=*) CHANNEL="${1#*=}"; shift ;;
    --version) PIN_VERSION="${2:?--version needs a value}"; shift 2 ;;
    --version=*) PIN_VERSION="${1#*=}"; shift ;;
    --force) FORCE=1; shift ;;
    --allow-downgrade) ALLOW_DOWNGRADE=1; shift ;;
    --prune)
      DO_PRUNE=1; shift
      if [ $# -gt 0 ] && printf '%s' "$1" | grep -qE '^[0-9]+$'; then PRUNE_KEEP="$1"; shift; fi
      ;;
    --rollback) DO_ROLLBACK=1; shift ;;
    -h|--help) sed -n '4,32p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "${CHANNEL}" in
  latest|stable) ;;
  *) echo "ERROR: --channel must be 'latest' or 'stable' (got '${CHANNEL}')" >&2; exit 2 ;;
esac

log() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

http_get() {
  # http_get URL [OUTPUT]; prints to stdout when OUTPUT is omitted.
  local url="$1" out="${2:-}"
  if command -v curl >/dev/null 2>&1; then
    if [ -n "${out}" ]; then curl -fsSL --max-time 1800 -o "${out}" "${url}"
    else curl -fsSL --max-time 60 "${url}"; fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "${out}" ]; then wget -q -O "${out}" "${url}"
    else wget -q -O - "${url}"; fi
  else
    err "ERROR: need curl or wget"
    return 1
  fi
}

detect_platform() {
  local os arch
  case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    *) err "ERROR: unsupported operating system: $(uname -s)"; return 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) err "ERROR: unsupported architecture: $(uname -m)"; return 1 ;;
  esac
  # An x64 shell under Rosetta 2 should still fetch the native arm64 build.
  if [ "${os}" = "darwin" ] && [ "${arch}" = "x64" ] \
     && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
    arch="arm64"
  fi
  if [ "${os}" = "linux" ]; then
    if [ -f /lib/libc.musl-x86_64.so.1 ] || [ -f /lib/libc.musl-aarch64.so.1 ] \
       || ldd /bin/ls 2>&1 | grep -q musl; then
      echo "linux-${arch}-musl"; return 0
    fi
    echo "linux-${arch}"; return 0
  fi
  echo "${os}-${arch}"
}

installed_version() {
  [ -x "${BIN_DIR}/claude" ] || return 0
  "${BIN_DIR}/claude" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true
}

# Newest-first list of installed builds that look like versions.
installed_builds() {
  [ -d "${VERSIONS_DIR}" ] || return 0
  ls -1 "${VERSIONS_DIR}" 2>/dev/null \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -Vr || true
}

# read_builds ARRAY_NAME-free helper: fills the global BUILDS array.
read_builds() {
  BUILDS=()
  local line
  while IFS= read -r line; do
    [ -n "${line}" ] && BUILDS+=("${line}")
  done < <(installed_builds)
}

# 0 if $1 is strictly newer than $2.
is_newer() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else err "ERROR: need sha256sum or shasum"; return 1; fi
}

checksum_for_platform() {
  # checksum_for_platform MANIFEST_JSON PLATFORM
  printf '%s' "$1" | PLATFORM="$2" python3 -c '
import json, os, sys
try:
    data = json.load(sys.stdin)
except Exception as exc:
    sys.exit(f"manifest is not valid JSON: {exc}")
entry = (data.get("platforms") or {}).get(os.environ["PLATFORM"]) or {}
checksum = entry.get("checksum") or ""
if not checksum:
    sys.exit(f"platform {os.environ['PLATFORM']} not present in manifest")
print(checksum)
'
}

# Keep only the newest PRUNE_KEEP builds. Never removes the build in use.
prune_builds() {
  [ "${DO_PRUNE}" -eq 1 ] || return 0
  local keep_safe="$1" b
  read_builds
  if [ "${#BUILDS[@]}" -le "${PRUNE_KEEP}" ]; then
    log "prune: ${#BUILDS[@]} build(s) installed, keeping up to ${PRUNE_KEEP}"
    return 0
  fi
  for b in "${BUILDS[@]:${PRUNE_KEEP}}"; do
    [ "${b}" = "${keep_safe}" ] && continue
    rm -f "${VERSIONS_DIR}/${b}" && log "pruned old build ${b}"
  done
}

relink() {
  # Atomic swap, so a concurrent `claude` launch never sees a missing symlink.
  local target="$1" tmp="${BIN_DIR}/.claude.selfupdate.$$"
  mkdir -p "${BIN_DIR}"
  ln -sfn "${target}" "${tmp}"
  mv -Tf "${tmp}" "${BIN_DIR}/claude" 2>/dev/null || mv -f "${tmp}" "${BIN_DIR}/claude"
}

# Advisory: report whether this build's bundled model registry knows the model
# the AMD setup is configured to use. A build can lag a just-released gateway
# model, which is why /model may not offer it even when routing works.
report_registry_support() {
  local binary="$1" model=""
  local common="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/claude_amd_common.py"
  [ -f "${common}" ] || return 0
  model="$(python3 "${common}" --resolve 2>/dev/null | cut -f1 || true)"
  [ -n "${model}" ] || return 0
  if grep -qaF "id:\"${model}\"" "${binary}" 2>/dev/null; then
    log "model registry: this build knows ${model}, so /model can offer it"
  else
    log "model registry: this build does NOT list ${model} yet"
    log "  /model will not offer it, but the wrapper passes --model ${model}"
    log "  explicitly, so direct calls still route correctly."
  fi
}

if [ "${DO_ROLLBACK}" -eq 1 ]; then
  read_builds
  if [ "${#BUILDS[@]}" -lt 2 ]; then
    err "ERROR: need at least two installed builds to roll back; found ${#BUILDS[@]}"
    exit 1
  fi
  current="$(installed_version)"
  previous=""
  for b in "${BUILDS[@]}"; do
    if [ "${b}" != "${current}" ]; then previous="${b}"; break; fi
  done
  [ -n "${previous}" ] || { err "ERROR: no other build to roll back to"; exit 1; }
  relink "${VERSIONS_DIR}/${previous}"
  log "rolled back: ${current:-unknown} -> $(installed_version)"
  exit 0
fi

CURRENT="$(installed_version)"
PLATFORM="$(detect_platform)"

if [ -n "${PIN_VERSION}" ]; then
  TARGET="${PIN_VERSION}"
  log "target: ${TARGET} (pinned)"
else
  TARGET="$(http_get "${DOWNLOAD_BASE_URL}/${CHANNEL}" || true)"
  TARGET="$(printf '%s' "${TARGET}" | tr -d '[:space:]')"
  if ! printf '%s' "${TARGET}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
    err "ERROR: could not read a version from ${DOWNLOAD_BASE_URL}/${CHANNEL}"
    err "The release CDN may be unreachable or blocked in this region."
    exit 1
  fi
  log "channel ${CHANNEL}: ${TARGET}"
fi

log "installed: ${CURRENT:-none}"
log "platform : ${PLATFORM}"

if [ -n "${CURRENT}" ] && [ "${CURRENT}" = "${TARGET}" ] && [ "${FORCE}" -eq 0 ]; then
  log "already up to date"
  [ -x "${BIN_DIR}/claude" ] && report_registry_support "$(readlink -f "${BIN_DIR}/claude")"
  prune_builds "${CURRENT}"
  exit 0
fi

if [ -n "${CURRENT}" ] && ! is_newer "${TARGET}" "${CURRENT}" && [ "${FORCE}" -eq 0 ]; then
  if [ "${ALLOW_DOWNGRADE}" -eq 0 ]; then
    log "installed ${CURRENT} is newer than ${CHANNEL} (${TARGET}); nothing to do"
    log "  pass --allow-downgrade to move down to ${TARGET} anyway"
    exit 0
  fi
  log "downgrading ${CURRENT} -> ${TARGET} (--allow-downgrade)"
fi

if [ "${CHECK_ONLY}" -eq 1 ]; then
  log "update available: ${CURRENT:-none} -> ${TARGET}"
  exit 10
fi

mkdir -p "${VERSIONS_DIR}"
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  err "ERROR: another claude-selfupdate run holds ${LOCK_DIR}"
  err "If no other run is active, remove that directory and retry."
  exit 1
fi
TMP_BIN=""
cleanup() {
  # Must not fail: a non-zero last command here would leak into the exit status.
  rmdir "${LOCK_DIR}" 2>/dev/null || true
  [ -n "${TMP_BIN}" ] && rm -f "${TMP_BIN}"
  return 0
}
trap cleanup EXIT INT TERM

log "fetching manifest for ${TARGET}..."
MANIFEST="$(http_get "${DOWNLOAD_BASE_URL}/${TARGET}/manifest.json")" || {
  err "ERROR: could not download the manifest for ${TARGET}"
  exit 1
}
EXPECTED_SUM="$(checksum_for_platform "${MANIFEST}" "${PLATFORM}")" || exit 1

TMP_BIN="${VERSIONS_DIR}/.download.${TARGET}.$$"
log "downloading ${TARGET} for ${PLATFORM} (this is a ~250MB binary)..."
if ! http_get "${DOWNLOAD_BASE_URL}/${TARGET}/${PLATFORM}/claude" "${TMP_BIN}"; then
  err "ERROR: download failed"
  err "On a throttled or offline network, seed from an existing same-OS/arch"
  err "install instead: install_native.sh --seed <path>"
  exit 1
fi

ACTUAL_SUM="$(sha256_of "${TMP_BIN}")"
if [ "${ACTUAL_SUM}" != "${EXPECTED_SUM}" ]; then
  err "ERROR: checksum mismatch for ${TARGET}"
  err "  expected ${EXPECTED_SUM}"
  err "  actual   ${ACTUAL_SUM}"
  exit 1
fi
log "checksum verified"

chmod +x "${TMP_BIN}"
if ! "${TMP_BIN}" --version >/dev/null 2>&1; then
  err "ERROR: downloaded binary does not run; keeping ${CURRENT:-current} install"
  exit 1
fi

DEST="${VERSIONS_DIR}/${TARGET}"
mv -f "${TMP_BIN}" "${DEST}"
TMP_BIN=""
relink "${DEST}"

NEW="$(installed_version)"
if [ "${NEW}" != "${TARGET}" ]; then
  err "ERROR: after relinking, claude reports '${NEW:-none}' instead of ${TARGET}"
  exit 1
fi
log "updated: ${CURRENT:-none} -> ${NEW}"
log "  binary: ${DEST}"
log "  link  : ${BIN_DIR}/claude"
report_registry_support "${DEST}"

prune_builds "${NEW}"

log ""
log "Restart any open interactive Claude session to pick up the new build."
