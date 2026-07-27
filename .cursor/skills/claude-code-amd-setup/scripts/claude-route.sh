#!/usr/bin/env bash
set -euo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${SELF}")" && pwd)"

if [ -f "${SCRIPT_DIR}/load_gateway_env.sh" ]; then
  # shellcheck source=/dev/null
  . "${SCRIPT_DIR}/load_gateway_env.sh"
elif [ -z "${AMD_LLM_GATEWAY_KEY:-}" ] && [ -f "${HOME}/.bashrc" ]; then
  set +u
  # shellcheck disable=SC1090
  . "${HOME}/.bashrc"
  set -u
fi

python3 "${SCRIPT_DIR}/claude_amd_common.py" --route
