# Scripts README

Helper scripts for the `crusoe-spur-access` skill.

## Conventions

- Keep scripts deterministic.
- Prefer explicit error messages.
- Add usage examples for each script.
- **No secrets, no real hostnames.** Every script takes the cluster address as
  an argument. Nothing here hard-codes a site.
- Scripts are read-only against the cluster unless stated otherwise.

## `healthcheck.sh`

Diagnoses access end to end: DNS, TCP reachability, key-based login, whether the
host allows remote commands, scheduler type and version, partitions, QoS
priorities, storage headroom, and your open jobs.

It never submits a job, never writes to the cluster, and never handles a
password.

```bash
# Minimal: direct network path, user inferred from $USER
./healthcheck.sh --host <LOGIN_HOST>

# Explicit user
./healthcheck.sh --host <LOGIN_HOST> --user <USER>

# Workstation cannot reach the cluster directly — route via a jump host
./healthcheck.sh --host <LOGIN_HOST> --user <USER> --jump <JUMP_HOST>

# Also probe the rotating alias to confirm it refuses remote commands
./healthcheck.sh --host <LOGIN_HOST> --user <USER> --alias <LOGIN_ALIAS>
```

### Exit codes

| Code | Meaning | Next step |
|---|---|---|
| 0 | Usable: login works and remote commands are allowed | Submit jobs |
| 1 | Bad invocation | Fix arguments |
| 2 | Unreachable (DNS or TCP) | Check VPN/DNS, or re-run with `--jump` |
| 3 | Reachable, key-based login failed | Install the public key (SKILL.md Step 3) |
| 4 | Login works but remote commands refused | You targeted a restricted alias; find the fixed node |

Exit code 4 is the one worth internalizing: the connection is fine and your key
is fine, but that entry point will never run a scripted command. Log in
interactively, run `hostname -f`, and use the node it reports.

## Submitting jobs

There is deliberately no job-submission wrapper here — `srun` already does the
job in one line, and wrapping it would hide the flags you need to understand:

```bash
# Single GPU
srun -A <ACCOUNT> --qos=<QOS> --gres=gpu:<GPU_TYPE>:1 -c 1 -t 0:10:00 <command>

# Whole node
srun -A <ACCOUNT> --qos=<QOS> --gres=gpu:<GPU_TYPE>:8 -c 8 -t 1:00:00 <command>
```

Use `srun` or `sbatch` from scripts. Do not use `salloc`: without a TTY it
releases the allocation immediately. See SKILL.md for why.
