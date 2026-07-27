# shellcheck shell=bash
# Robustly load AMD_LLM_GATEWAY_KEY (and optional subscription key) into the
# environment. Source this file; do not execute it.
#
# Lookup order (first hit that yields a key wins):
#   1. already-set AMD_LLM_GATEWAY_KEY in the current environment
#   2. ${CLAUDE_AMD_ENV_FILE} if set
#   3. ~/.config/claude-amd/env        (preferred: a dedicated secret file)
#   4. ~/.bashrc                       (legacy fallback)
#
# WHY A DEDICATED FILE:
# The default ~/.bashrc on Debian/Ubuntu starts with an interactive guard such
# as `[ -z "$PS1" ] && return` (or `case $- in *i*) ;; *) return;; esac`).
# Wrappers source ~/.bashrc non-interactively, so any `export` placed AFTER
# that guard is never seen. The dedicated env file has no such guard and always
# loads. If you must use ~/.bashrc, keep the gateway exports ABOVE the guard.
#
# This loader sets PS1 before sourcing so that, even when falling back to
# ~/.bashrc, exports placed before the guard still apply and the guard itself
# does not abort sourcing.

if [ -z "${AMD_LLM_GATEWAY_KEY:-}" ]; then
  : "${PS1:=claude-amd$ }"
  export PS1
  for _claude_amd_envf in \
    "${CLAUDE_AMD_ENV_FILE:-}" \
    "${HOME}/.config/claude-amd/env" \
    "${HOME}/.bashrc"; do
    [ -n "${_claude_amd_envf}" ] && [ -f "${_claude_amd_envf}" ] || continue
    set +u
    # shellcheck disable=SC1090
    . "${_claude_amd_envf}"
    set -u
    [ -n "${AMD_LLM_GATEWAY_KEY:-}" ] && break
  done
  unset _claude_amd_envf
fi
