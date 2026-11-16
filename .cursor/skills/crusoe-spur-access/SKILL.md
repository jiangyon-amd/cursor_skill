---
name: crusoe-spur-access
description: Get onto an AMD Crusoe/SPUR Slurm cluster and run GPU jobs. Use when SSH key install fails with 'Remote commands are not allowed on this SSH-only host', host key errors recur on every login, salloc/srun rejects a partition, or a login host is unreachable from your workstation.
---

# Crusoe SPUR Cluster Access

## Purpose

Take a user from "no access" to "running a verified GPU job" on an AMD
Crusoe/SPUR Slurm cluster, and diagnose the failures that show up along the way.

The preferred end state is:

- key-based login works unattended, with no password prompt
- a **fixed** login node is used for anything scripted, not the rotating alias
- jobs are submitted with `srun`/`sbatch`, with the partition resolved from the
  scheduler rather than copied from stale documentation
- the user knows the real free space on shared storage before staging data

## When to Use

- user cannot log in, or gets a different host key error on every login attempt
- `ssh-copy-id` fails against the cluster
- `ssh <host> '<command>'` returns `Remote commands are not allowed on this SSH-only host`
- `salloc`/`srun` fails with `partition '<name>' not found`
- the cluster resolves in DNS from the user's workstation but port 22 is unreachable
- an agent needs to run cluster commands non-interactively and `salloc` keeps
  releasing the allocation immediately
- user asks how many GPUs/CPUs a node has, or whether there is room to stage a
  large model

## Placeholders Used In This Skill

This skill is deliberately site-agnostic. Substitute your own values; do not
commit real ones back into this repository.

| Placeholder | Meaning | How to find it |
|---|---|---|
| `<LOGIN_ALIAS>` | Rotating/round-robin login alias | Your cluster onboarding doc |
| `<LOGIN_HOST>` | A single, fixed login node | `hostname -f` after logging in via the alias |
| `<USER>` | Your cluster account name | Your corporate ID |
| `<JUMP_HOST>` | A machine that *can* reach the cluster | Any host of yours already on the internal network |
| `<ACCOUNT>` | Slurm account | `sacctmgr show account` |
| `<QOS>` | Slurm QoS | `sacctmgr show qos format=Name,Priority` |
| `<GPU_PARTITION>` | GPU partition | `sinfo` — the one marked `*` is the default |
| `<GPU_TYPE>` | GRES GPU type | `scontrol show node <node> \| grep Gres` |

## Non-Negotiable Rules

1. Never write a real cluster hostname, internal IP, user ID, or public key into
   repository files. Placeholders only.
2. Never put a password in a command line, a script, or a file.
3. Determine the partition from `sinfo` before submitting. Do not copy a
   partition name out of a wiki page.
4. Do not claim a job "works" from an allocation message alone. Verify on the
   compute node that the GPUs are actually visible.
5. Check free space on shared filesystems **before** staging large data. Shared
   `/home` and NFS volumes on busy clusters are routinely near full, and filling
   them affects every other user.
6. Release allocations you are done with. Check `squeue -u "$USER"` before
   declaring the task finished.

## The Two Login Entry Points Are Not Equivalent

This is the single most important fact in this skill, and the root cause of
three separate failure modes.

| Entry point | Nature | Remote commands |
|---|---|---|
| `<LOGIN_ALIAS>` | Round-robin alias in front of several login nodes | ❌ Often restricted: `Remote commands are not allowed on this SSH-only host. Open an interactive SSH session.` |
| `<LOGIN_HOST>` | One specific login node | ✅ Usually allowed — this is what automation must use |

Consequences:

- **`ssh-copy-id` cannot work against a restricted alias.** It is implemented as
  a remote command, so it is rejected before it can append anything.
- **Host key errors recur on every login against an alias**, because each
  connection may land on a different backing node with a different key. This is
  not a stale cache and not an attack; re-running `ssh-keygen -R` only papers
  over it until the next time you land elsewhere.
- **Any agent or script must target `<LOGIN_HOST>`.** Tooling that shells out as
  `ssh <host> '<command>'` will fail 100% of the time against the alias.

Find the fixed node by logging in interactively via the alias once and running
`hostname -f`.

## Instructions

### Step 1: Determine reachability from this machine

```bash
getent hosts <LOGIN_HOST>                 # does it resolve?
timeout 5 bash -c '</dev/tcp/<LOGIN_HOST>/22' && echo reachable || echo unreachable
```

Resolving but unreachable means network segmentation, not a cluster problem.
Go to Step 2. Reachable means go to Step 3.

### Step 2: Route through a jump host (only if unreachable)

Find a machine you already have access to that *is* on the internal network, and
verify it can reach the cluster:

```bash
ssh <JUMP_HOST> 'timeout 5 bash -c "</dev/tcp/<LOGIN_HOST>/22" && echo reachable'
```

Then add to `~/.ssh/config`:

```sshconfig
Host cluster
    HostName <LOGIN_HOST>
    User <USER>
    ProxyJump <JUMP_HOST>
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60
```

`ProxyJump` authenticates **locally** — the jump host only forwards TCP — so the
key that matters is the one on this machine, not one on `<JUMP_HOST>`.

### Step 3: Install your public key

If `ssh <LOGIN_HOST>` already works without a password, skip this step.

Try the normal path first; it works whenever the target is not a restricted
alias:

```bash
ssh-copy-id -i ~/.ssh/id_rsa.pub <USER>@<LOGIN_HOST>
```

If that is rejected (see the table above), you must install the key by hand.
**Open an interactive session** — this cannot be scripted, and an agent must
hand this step back to the user:

```bash
ssh <USER>@<LOGIN_ALIAS>
```

Then, in that interactive shell, paste one line:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
  echo 'ssh-rsa PASTE_YOUR_PUBLIC_KEY_HERE' >> ~/.ssh/authorized_keys && \
  chmod 600 ~/.ssh/authorized_keys && echo INSTALLED
```

Because `/home` is normally shared over NFS, installing once covers every login
and compute node.

If you have only a private key locally, derive the public one:

```bash
ssh-keygen -y -f ~/.ssh/id_rsa > ~/.ssh/id_rsa.pub
ssh-keygen -lf ~/.ssh/id_rsa.pub          # record the fingerprint
```

### Step 4: Confirm which entry points allow remote commands

```bash
ssh -o BatchMode=yes <USER>@<LOGIN_ALIAS> 'hostname -f'   # may be refused
ssh -o BatchMode=yes <USER>@<LOGIN_HOST>  'hostname -f'   # should print a hostname
```

Use whichever host answered for everything that follows.

### Step 5: Discover the scheduler, do not assume it

Cluster schedulers get replaced. SPUR has shipped both a non-Slurm CLI and, in
later versions, a Slurm-compatible one. Check instead of guessing:

```bash
sinfo --version                 # e.g. "slurm 23.11.0 (spur 0.15.0)"
which salloc sbatch squeue srun spur
```

### Step 6: Resolve the partition from the scheduler

```bash
sinfo -o "%20P %10a %12l %8D %10t"      # the partition marked '*' is the default
sacctmgr -nP show qos format=Name,Priority
```

Note the QoS priorities. A low-priority "burst"-style QoS often needs no special
approval but queues behind everything else, while team QoS entries carry much
higher priority. Picking the open one is usually the fastest way to get a first
job running.

### Step 7: Submit and verify a GPU job

Use `srun` — it allocates and executes in one step:

```bash
srun -A <ACCOUNT> --qos=<QOS> --gres=gpu:<GPU_TYPE>:1 -c 1 -t 0:10:00 \
  bash -c 'hostname -s; rocm-smi --showproductname'
```

For a whole node, and to confirm what the job actually received:

```bash
srun -A <ACCOUNT> --qos=<QOS> --gres=gpu:<GPU_TYPE>:8 -c 8 -t 0:10:00 bash -c '
  echo "cards: $(rocm-smi --showproductname 2>/dev/null | grep -c "Card Series")"
  echo "renderD: $(ls /dev/dri/renderD* | wc -l)"
  echo "ROCR_VISIBLE_DEVICES=$ROCR_VISIBLE_DEVICES"
  cat /opt/rocm/.info/version'
```

### Step 8: Check storage before staging data

```bash
df -h "$HOME" /shared_nfs /tmp
```

Read the **Avail** column, not the percentage. A 99%-full 400T volume still has
usable terabytes; a 94%-full 10T `/home` may have only a few hundred GB. Compare
against your dataset size and say so explicitly before copying anything.

### Step 9: Clean up

```bash
squeue -u "$USER"
scancel <jobid>      # if anything is still held
```

## `salloc` vs `srun`: Why Automation Must Use `srun`

`salloc` allocates resources and attaches an **interactive shell**. Under SPUR it
is a reduced implementation and notably **does not support `--no-shell`**.

When invoked without a TTY — from a script, a CI job, or an AI agent shelling out
over SSH — it prints `Granted job allocation` and then immediately
`Relinquishing job allocation`, because there is no interactive shell to attach
to. The allocation is gone before you can use it.

- **Humans at a terminal**: `salloc` is fine for holding a node while you work.
- **Scripts and agents**: use `srun` (allocate + execute in one step) or
  `sbatch` (detached batch job). Never `salloc`.

## Reading GPU Assignment Inside a Job

Do not rely on `SLURM_JOB_GPUS` — on SPUR it can be empty even when GPUs are
correctly assigned. `ROCR_VISIBLE_DEVICES` is the reliable one, and it carries
**physical** card indices:

```bash
echo "$ROCR_VISIBLE_DEVICES"   # single-GPU job may show e.g. "7", not "0"
```

Scripts that assume the first assigned GPU is index `0` will target the wrong
card. Enumerate `/dev/dri/renderD*` or parse `ROCR_VISIBLE_DEVICES` instead.

## Partition Names Go Stale — This Is The Most Common Failure

Cluster generations rename partitions. Documentation lags. The symptom is:

```
partition '<old-name>' not found
```

Verified behavior:

| Invocation | Result |
|---|---|
| `-p <GPU_PARTITION>` (current name) | works |
| `-A`, `--qos`, `-p` **all omitted** | works — filled from your user profile |
| `-p <retired-name>` | fails immediately with `not found` |

Two things follow:

1. **Omitting `-p` is safe.** It resolves to the scheduler's default partition.
   If dropping `-p` "fixed" a submission, the real bug was a wrong partition
   name, not the flag. The flag itself is fully supported.
2. **There is no silent fallback.** A wrong partition fails loudly and
   immediately. You will never silently land on the wrong hardware, so it is
   safe to just try.

Always confirm against `sinfo` rather than reusing a name from a wiki.

## Common Failure Modes

1. `Remote commands are not allowed on this SSH-only host`
   - you targeted the restricted alias; use the fixed `<LOGIN_HOST>`
   - if you must use the alias, open an interactive session instead
2. `ssh-copy-id` fails with the message above
   - install the key by hand from an interactive shell (Step 3)
3. Host key verification fails on *every* login, `ssh-keygen -R` only helps once
   - you are connecting to a round-robin alias and landing on different nodes
   - connect to a fixed login node instead; this removes the problem permanently
4. `Too many authentication failures` before you can type a password
   - the client offered too many keys and the server hit `MaxAuthTries`
   - force the password path: `ssh -o PubkeyAuthentication=no <USER>@<host>`
   - or offer exactly one key: `ssh -o IdentitiesOnly=yes -i <key> ...`
5. Host resolves in DNS but port 22 is unreachable
   - network segmentation, not a cluster fault; use `ProxyJump` (Step 2)
6. `partition '<name>' not found`
   - stale partition name; read `sinfo` and use the default (or drop `-p`)
7. `salloc` grants then immediately relinquishes the allocation
   - no TTY; this is expected. Use `srun` or `sbatch` for anything scripted
8. `salloc: unexpected argument '--no-shell'`
   - SPUR's `salloc` does not implement it; use `srun`/`sbatch`
9. `SLURM_JOB_GPUS` is empty inside a running job
   - expected on SPUR; read `ROCR_VISIBLE_DEVICES` instead
10. `rocminfo` produces no output on a compute node
    - it may not be installed in that environment; fall back to `rocm-smi` and
      `/dev/dri/renderD*` for card count, and do not report a GPU architecture
      you could not actually read
11. Job pends for a long time
    - check QoS priority (`sacctmgr show qos format=Name,Priority`); a burst-tier
      QoS queues behind team QoS entries
12. Copying a large model fills the shared filesystem
    - check `df -h` **first**; prefer node-local scratch for temporary data, and
      remember node-local paths are invisible from the login node
13. Automation worked yesterday, fails today with a connection error
    - if you reach the cluster through your own tunnel or jump host, verify that
      hop is still up before debugging the cluster

## Validation Checklist

- [ ] no real hostname, internal IP, user ID, or public key written to the repository
- [ ] `ssh -o BatchMode=yes <LOGIN_HOST> 'hostname -f'` succeeds without a password
- [ ] the entry point used for automation is a fixed login node, not the alias
- [ ] scheduler type and version were read from `sinfo --version`, not assumed
- [ ] partition was taken from `sinfo`, not from documentation
- [ ] a GPU job ran and the GPUs were confirmed *on the compute node*
- [ ] GPU count verified by at least two independent signals (e.g. `rocm-smi` and `/dev/dri/renderD*`)
- [ ] anything not actually observed (e.g. GPU architecture when `rocminfo` was absent) is reported as unverified
- [ ] free space checked with `df -h` before any large staging was proposed
- [ ] `squeue -u "$USER"` is clean, or remaining jobs are intentional
