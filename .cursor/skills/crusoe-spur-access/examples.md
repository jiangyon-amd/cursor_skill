# Examples

Representative requests this skill should handle, and the behavior expected of
the assistant. All hostnames below are placeholders.

---

## 1. "I can't log in — it asks for the host key every single time"

**User:**
> Every time I open a new terminal and ssh to the cluster I get a host key
> error. I have to run `ssh-keygen -R` before every single login. What's wrong
> with my known_hosts?

**Expected behavior:**

Do not treat this as a `known_hosts` corruption problem. Recognize the pattern:
repeated host key failures against a login *alias* mean round-robin DNS putting
you on a different backing node each time, each with its own key.

Explain that `ssh-keygen -R` works exactly once and then the problem returns,
then give the permanent fix:

1. log in interactively once via the alias
2. run `hostname -f` to learn the fixed node name
3. use that fixed node from then on

Do not suggest `StrictHostKeyChecking=no` — it disables a real protection for a
problem that has a correct fix.

---

## 2. "ssh-copy-id fails"

**User:**
> `ssh-copy-id` on the cluster gives me
> `Remote commands are not allowed on this SSH-only host.`

**Expected behavior:**

Explain the cause: `ssh-copy-id` is implemented as a remote command, and that
entry point only permits interactive shells. It cannot be made to work there.

Give the manual path (SKILL.md Step 3): log in interactively, paste one line
appending the public key to `~/.ssh/authorized_keys`, with correct permissions.

Also note that because `/home` is usually NFS-shared, installing once covers all
login and compute nodes.

If the user has no `.pub` file, show them how to derive it with
`ssh-keygen -y -f`.

**Do not** ask the user for their password, and do not offer to run the
interactive step for them — hand it back explicitly.

---

## 3. "A colleague says to remove `-p` — is that safe?"

**User:**
> Someone on the team says their job only works if they delete `-p` from the
> salloc command. They're not sure what that breaks. Is it safe?

**Expected behavior:**

Answer the actual question — yes, it is safe — and explain *why*, rather than
just confirming.

- `-p` omitted resolves to the scheduler's default partition
- the flag itself is fully supported (`salloc --help` lists `-p, --partition`)
- the real bug was almost certainly a **stale partition name**; retired names
  fail with `partition '<name>' not found`
- there is **no silent fallback** — a wrong partition fails loudly, so nobody
  can silently land on the wrong hardware

Then show them how to confirm the current name from `sinfo` (the entry marked
`*` is the default) instead of trusting a wiki page.

If you earlier stated something about the flag that turns out to be wrong after
reading `--help`, correct it plainly and move on.

---

## 4. "Run a benchmark on 8 GPUs for me"

**User:**
> Can you run this benchmark on a full 8-GPU node?

**Expected behavior:**

1. Run `healthcheck.sh` first, or confirm the fixed login node answers remote
   commands. If exit code is 4, stop and explain the alias problem.
2. Read the partition and QoS from the scheduler rather than assuming.
3. Submit with `srun` (not `salloc`, which releases immediately without a TTY).
4. **Verify on the compute node** that 8 GPUs are actually present, using at
   least two signals (`rocm-smi` card count and `/dev/dri/renderD*`).
5. Report anything that could not be observed as unverified — for example, if
   `rocminfo` is absent, do not state a GPU architecture.
6. Check `squeue -u "$USER"` afterwards and confirm nothing is left holding
   resources.

Do not report success from the `Granted job allocation` line alone.

---

## 5. "Copy this 600GB model to the cluster"

**User:**
> Stage this 600GB checkpoint on the cluster so we can run it there.

**Expected behavior:**

Check `df -h` **before** copying anything, and read the **Avail** column rather
than the percentage.

Report concretely: if `/home` has ~600GB free and the dataset is ~600GB, say
plainly that this would take the shared volume to effectively full and affect
every other user on the cluster. Surface that **before** starting, and ask where
it should go.

Offer the alternatives you can see: a larger shared volume if one has room,
node-local scratch for transient data (noting it is invisible from the login
node), or downloading directly on a compute node rather than staging through
`/home`.

Do not start a multi-hundred-GB copy to a shared filesystem without asking.

---

## 6. "Set this up on my machine — I get connection refused"

**User:**
> The cluster hostname resolves but ssh just hangs. Works fine from my laptop.

**Expected behavior:**

Distinguish "DNS resolves" from "port 22 reachable" and test them separately.
Resolving-but-unreachable is network segmentation, not a cluster fault — say so
rather than debugging the cluster.

Then find a machine the user already has access to that *is* on the internal
network, verify from it that the cluster is reachable, and configure
`ProxyJump`.

Explain that with `ProxyJump` authentication happens locally and the jump host
only forwards TCP — so the key that matters is the one on the local machine, not
one on the jump host.

Finally, note the fragility: if that hop goes down, everything downstream breaks,
so it is the first thing to check when automation that worked yesterday fails
today.

---

## 7. "My script's allocation keeps disappearing"

**User:**
> My script does `salloc ... --no-shell` and gets `unexpected argument`. Without
> that flag it says "Granted job allocation" then immediately relinquishes it.

**Expected behavior:**

Explain both halves:

- SPUR's `salloc` is a reduced implementation and does not have `--no-shell`
- without a TTY, `salloc` has no interactive shell to attach to, so it releases
  the allocation immediately — this is expected, not a bug

Give the fix: use `srun` (allocate and execute in one step) or `sbatch`
(detached). Reserve `salloc` for a human holding a node at a real terminal.

While there, mention the related trap: inside the job, `SLURM_JOB_GPUS` may be
empty even when GPUs are assigned correctly — read `ROCR_VISIBLE_DEVICES`, and
note it carries physical card indices, so a single-GPU job can legitimately show
`7` rather than `0`.
