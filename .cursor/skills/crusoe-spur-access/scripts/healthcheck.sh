#!/usr/bin/env bash
# Diagnose access to a Crusoe/SPUR Slurm cluster, from DNS up to job submission.
#
# Read-only: it never submits a job, never writes to the cluster, and never
# prompts for or handles a password.
#
# Usage:
#   ./healthcheck.sh --host <LOGIN_HOST> [--user <USER>] [--jump <JUMP_HOST>] [--alias <LOGIN_ALIAS>]
#
# Exit codes:
#   0  usable: key-based login works and remote commands are allowed
#   1  bad invocation
#   2  unreachable (DNS or TCP)
#   3  reachable but key-based login failed
#   4  logged in, but remote commands are refused on that host

set -uo pipefail

HOST=""
USER_NAME="${USER:-}"
JUMP=""
ALIAS=""
SSH_TIMEOUT=15

die() { printf 'error: %s\n' "$1" >&2; exit 1; }
hdr() { printf '\n== %s ==\n' "$1"; }
ok()  { printf '  [ ok ] %s\n' "$1"; }
no()  { printf '  [FAIL] %s\n' "$1"; }
inf() { printf '  [info] %s\n' "$1"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --host)  HOST="${2:-}"; shift 2 ;;
    --user)  USER_NAME="${2:-}"; shift 2 ;;
    --jump)  JUMP="${2:-}"; shift 2 ;;
    --alias) ALIAS="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$HOST" ] || die "--host is required (a FIXED login node, not a rotating alias)"
[ -n "$USER_NAME" ] || die "--user is required (could not infer from \$USER)"

TARGET="${USER_NAME}@${HOST}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT" -o StrictHostKeyChecking=accept-new)
[ -n "$JUMP" ] && SSH_OPTS+=(-o "ProxyJump=${JUMP}")

# ---------------------------------------------------------------- reachability
hdr "Reachability: $HOST"

IP="$(getent hosts "$HOST" 2>/dev/null | head -1 | awk '{print $1}')"
if [ -z "$IP" ]; then
  no "DNS does not resolve $HOST"
  inf "check VPN / corporate DNS, or the hostname itself"
  exit 2
fi
ok "resolves"

if [ -n "$JUMP" ]; then
  inf "port 22 check skipped (routing through jump host $JUMP)"
elif timeout 5 bash -c "</dev/tcp/${IP}/22" 2>/dev/null; then
  ok "port 22 reachable directly"
else
  no "resolves but port 22 is unreachable from here"
  inf "this is network segmentation, not a cluster fault"
  inf "re-run with --jump <JUMP_HOST> using a machine on the internal network"
  exit 2
fi

# ------------------------------------------------------------------- key login
hdr "Key-based login"

OUT="$(timeout $((SSH_TIMEOUT * 3)) ssh "${SSH_OPTS[@]}" "$TARGET" 'hostname -f' 2>&1)"
RC=$?

if printf '%s' "$OUT" | grep -qi 'Remote commands are not allowed'; then
  no "logged in, but this host refuses remote commands"
  inf "this is a restricted/SSH-only entry point — automation cannot use it"
  inf "log in interactively, run 'hostname -f', and re-run with that fixed node"
  exit 4
fi

if [ $RC -ne 0 ]; then
  no "key-based login failed"
  printf '%s\n' "$OUT" | sed 's/^/         /' | tail -5
  if printf '%s' "$OUT" | grep -qi 'Too many authentication failures'; then
    inf "client offered too many keys; retry with -o IdentitiesOnly=yes -i <key>"
  fi
  if printf '%s' "$OUT" | grep -qi 'Permission denied'; then
    inf "public key is not installed yet — see Step 3 in SKILL.md"
    inf "note: ssh-copy-id cannot work against a restricted alias"
  fi
  exit 3
fi

ok "login works, remote commands allowed"
inf "remote reports: $(printf '%s' "$OUT" | tail -1)"

if [ -n "$ALIAS" ]; then
  hdr "Alias behaviour: $ALIAS"
  AOUT="$(timeout $((SSH_TIMEOUT * 2)) ssh "${SSH_OPTS[@]}" "${USER_NAME}@${ALIAS}" 'hostname -f' 2>&1)"
  if printf '%s' "$AOUT" | grep -qi 'Remote commands are not allowed'; then
    inf "alias refuses remote commands (expected) — keep automation on $HOST"
  else
    inf "alias answered: $(printf '%s' "$AOUT" | tail -1)"
    inf "note: an alias may still land on a different node next time"
  fi
fi

# ------------------------------------------------------------------- scheduler
hdr "Scheduler"

ssh "${SSH_OPTS[@]}" "$TARGET" '
  if command -v sinfo >/dev/null 2>&1; then
    echo "  [info] version: $(sinfo --version 2>&1)"
  else
    echo "  [FAIL] sinfo not found — this may not be a Slurm-compatible cluster"
  fi
  printf "  [info] tools:"
  for t in salloc sbatch srun squeue spur; do
    command -v "$t" >/dev/null 2>&1 && printf " %s" "$t"
  done
  echo
  echo "  [info] partitions (* = default):"
  sinfo -o "%20P %10a %12l %8D %10t" 2>/dev/null | head -12 | sed "s/^/         /"
  echo "  [info] QoS by priority:"
  sacctmgr -nP show qos format=Name,Priority 2>/dev/null | sort -t"|" -k2 -rn | head -8 | sed "s/^/         /"
' 2>&1

# --------------------------------------------------------------------- storage
hdr "Storage (check Avail, not percentage)"

ssh "${SSH_OPTS[@]}" "$TARGET" '
  df -h "$HOME" /shared_nfs 2>/dev/null | sed "s/^/  /"
  echo "  [info] node-local scratch is only visible from compute nodes"
' 2>&1

# ------------------------------------------------------------------ open jobs
hdr "Your jobs"

ssh "${SSH_OPTS[@]}" "$TARGET" 'squeue -u "$USER" 2>/dev/null | sed "s/^/  /"' 2>&1

printf '\nhealthcheck: ok — %s is usable for automation\n' "$HOST"
exit 0
