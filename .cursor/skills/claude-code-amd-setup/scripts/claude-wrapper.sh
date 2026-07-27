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

if [ -z "${AMD_LLM_GATEWAY_KEY:-}" ]; then
  echo "ERROR: AMD_LLM_GATEWAY_KEY is not set" >&2
  echo "Set it in ~/.config/claude-amd/env (preferred) or above the interactive guard in ~/.bashrc." >&2
  exit 1
fi

# Returns "<real_model>\t<effort>"; normalizes/repairs settings.json as a side effect.
RESOLVED="$(python3 "${SCRIPT_DIR}/claude_amd_common.py" --ensure-settings)"
REAL_MODEL="${RESOLVED%%$'\t'*}"
EFFORT="${RESOLVED#*$'\t'}"

export ANTHROPIC_BASE_URL="https://llm-api.amd.com/Anthropic"
export ANTHROPIC_API_KEY="${AMD_LLM_GATEWAY_KEY}"
export ANTHROPIC_AUTH_TOKEN="${AMD_LLM_GATEWAY_KEY}"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# AMD LLM Gateway sits behind Azure APIM, which authenticates via a
# subscription key header rather than the Anthropic api key.
if [ -n "${AMD_LLM_GATEWAY_SUBSCRIPTION_KEY:-}" ]; then
  export ANTHROPIC_CUSTOM_HEADERS="Ocp-Apim-Subscription-Key: ${AMD_LLM_GATEWAY_SUBSCRIPTION_KEY}"
fi

NATIVE_CLAUDE="${HOME}/.local/bin/claude"
if [ ! -x "${NATIVE_CLAUDE}" ]; then
  echo "ERROR: native Claude Code binary not found at ${NATIVE_CLAUDE}" >&2
  echo "Install it first, e.g. curl -fsSL https://claude.ai/install.sh | bash" >&2
  exit 1
fi

REAL_CLAUDE="$(readlink -f "${NATIVE_CLAUDE}" 2>/dev/null || echo "${NATIVE_CLAUDE}")"
if [ "${REAL_CLAUDE}" = "$(readlink -f "$0" 2>/dev/null || echo /usr/local/bin/claude)" ]; then
  echo "ERROR: native Claude binary resolves to the wrapper itself" >&2
  exit 1
fi

# Inject the resolved real model and effort, unless the user passed their own.
USER_HAS_MODEL=0
USER_HAS_EFFORT=0
if [ -n "${CLAUDE_CODE_EFFORT_LEVEL:-}" ]; then
  USER_HAS_EFFORT=1
fi
for arg in "$@"; do
  case "${arg}" in
    --model|-m|--model=*) USER_HAS_MODEL=1 ;;
    --effort|--effort=*) USER_HAS_EFFORT=1 ;;
  esac
done

INJECT=()
if [ "${USER_HAS_MODEL}" -eq 0 ] && [ -n "${REAL_MODEL}" ]; then
  INJECT+=(--model "${REAL_MODEL}")
fi
if [ "${USER_HAS_EFFORT}" -eq 0 ] && [ -n "${EFFORT}" ]; then
  INJECT+=(--effort "${EFFORT}")
fi

exec "${NATIVE_CLAUDE}" "${INJECT[@]}" "$@"
