---
name: atlassian-mcp-setup
description: Use when users want Claude Code or Cursor to read and write AMD Jira/Confluence via the mcp-atlassian MCP server, need Atlassian tokens kept out of committed config, cannot open a Jira URL such as https://amd.atlassian.net/browse/QUARK-808, or are debugging a 401 from the Atlassian REST API.
---

# Atlassian MCP Setup

## Purpose

Give an agent authenticated access to Atlassian (Jira + Confluence) through the
`mcp-atlassian` MCP server, without ever writing a token into repository files or
into the agent's own config. The intended end state is:

- `mcp-atlassian` registered in `~/.claude.json` (or Cursor's MCP config) with
  **no credentials in it**
- all secrets in `~/.atlassian.env`, mode `600`
- a thin launcher script that sources the env file and `exec`s `uvx mcp-atlassian`
- authentication proven with a real REST call **before** blaming the MCP layer

An agent cannot fetch a Jira page with a plain web-fetch tool. `https://amd.atlassian.net/browse/QUARK-808`
returns a login wall that renders to the single word "Jira". That is the symptom
this skill exists to fix.

## When to Use

- user pastes a Jira/Confluence URL and the agent cannot read it
- user asks to connect Jira, Confluence, or "the Atlassian MCP"
- user wants Jira issues read, searched, created, or commented on from the agent
- an existing `mcp-atlassian` connects but every call returns 401 / "authentication failed"
- user wants the token out of `~/.claude.json`

## Non-Negotiable Rules

1. **Never write a real token into repository files.** Only `~/.atlassian.env`.
2. **Never put the token in `~/.claude.json`.** Use the launcher-script indirection
   in this skill. Agent config files get shared, diffed, and pasted into bug reports.
3. **Never pass the token as a command-line argument.** It leaks through `ps` and
   shell history. Pass it on stdin or via an already-exported env var.
4. **Ask the user for their exact Atlassian account email. Do not guess it.**
   The Linux username is not the email local-part. Guessing burns a round trip
   per attempt and every failure looks identical (`401`), so guessing also
   destroys your ability to tell "wrong email" from "bad token".
5. **Prefer that the user writes the env file themselves**, in their own terminal.
   A token pasted into chat is in the transcript permanently. If it is pasted
   anyway, finish the job and then tell the user to rotate it.
6. Pick the right auth scheme for the deployment (see table). Cloud credentials
   against a Server URL always fail, and the error does not say why.
7. Prove auth with `rest/api/3/myself` before declaring success. A **connected**
   MCP server says nothing about whether the credentials work.
8. Tell the user to restart the agent session. MCP servers are launched at
   session start; a server registered mid-session is not callable in that session.

## Cloud vs Server: They Are Not Interchangeable

The single most common failure is applying on-premise instructions to a Cloud
site. AMD has both.

| | Cloud | Server / Data Center |
|---|---|---|
| Example host | `https://amd.atlassian.net` | `https://jira.xilinx.com` |
| Auth | email + API token (HTTP Basic) | Personal Access Token (Bearer) |
| Jira env vars | `JIRA_USERNAME` + `JIRA_API_TOKEN` | `JIRA_PERSONAL_TOKEN` |
| Confluence env vars | `CONFLUENCE_USERNAME` + `CONFLUENCE_API_TOKEN` | `CONFLUENCE_PERSONAL_TOKEN` |
| Token page | <https://id.atlassian.com/manage-profile/security/api-tokens> | Avatar → Profile → Personal Access Tokens |
| REST API version | `/rest/api/3` (ADF bodies) | `/rest/api/2` (wiki markup) |

Two more facts that matter:

- **One `mcp-atlassian` process serves exactly one `JIRA_URL`.** To reach both a
  Cloud site and an on-prem site, register two MCP servers with two env files.
- **On Cloud, one API token covers both Jira and Confluence.** Do not generate
  two. `CONFLUENCE_URL` needs the `/wiki` suffix; `JIRA_URL` does not.

## Scoped vs Classic API Tokens (Cloud)

Atlassian now offers two kinds of Cloud token, and they are not called out
clearly in the UI:

- **Classic** ("Create API token") — works with HTTP Basic against the site URL,
  `https://<site>.atlassian.net/rest/api/3/...`. This is what `mcp-atlassian`
  expects. Prefer it.
- **Scoped** ("Create API token with scopes") — rejected by the site URL. It only
  works as a Bearer token against `https://api.atlassian.com/ex/jira/<cloudId>/rest/api/3/...`.

A scoped token used the classic way returns a 401 that is byte-identical to a
wrong password. If auth fails and the user is confident in the email, have them
regenerate a **classic** token before debugging anything else.

Get the cloudId without credentials:

```bash
curl -s https://amd.atlassian.net/_edge/tenant_info
```

## Preferred Local Layout

- `~/.atlassian.env` — the only file holding secrets; `chmod 600`
- `~/.claude/mcp-atlassian-launch.sh` — sources the env file, `exec`s `uvx mcp-atlassian`
- `~/.claude.json` — registers only the launcher path, no `env` block
- `uvx` — from `pipx install uv`, if not already present

Why the launcher instead of `claude mcp add --env KEY=value`: the `--env` form
writes the literal token into `~/.claude.json`. With the launcher, rotating a
token is a one-line edit to a `600` file and no agent config changes at all.

## Interaction Flow

### Step 1: Determine the deployment and the email

Read the host out of the URL the user gave you. `*.atlassian.net` is Cloud;
anything else is almost certainly Server/DC.

Then **ask for the exact account email**. Do not derive it from `whoami`,
`git config user.email`, or the pattern of other AMD addresses. If those sources
happen to exist, offer them as a candidate to confirm — do not silently use one.

### Step 2: Ask for the token, on the user's terms

State plainly that a token pasted into chat lands in the transcript, and offer
the two paths:

- **Path A (preferred):** the user runs `setup_atlassian_mcp.sh` themselves, or
  hand-writes `~/.atlassian.env`, in their own terminal. You never see the token.
- **Path B:** the user pastes it and you write the file. Acceptable if they
  choose it — just say once, at the end, that it should be rotated.

Either way the file is `chmod 600` and never enters the repository.

### Step 3: Install

```bash
# Path A: token on stdin, never in argv
bash ".cursor/skills/atlassian-mcp-setup/scripts/setup_atlassian_mcp.sh" \
  --email "you@amd.com" \
  --site "https://amd.atlassian.net"
# (prompts for the token with echo off)
```

The script installs `uv` if missing, writes `~/.atlassian.env`, installs the
launcher, registers the MCP server, and runs the healthcheck.

### Step 4: Verify auth before claiming success

```bash
bash ".cursor/skills/atlassian-mcp-setup/scripts/healthcheck.sh"
```

A green healthcheck must show the resolved display name from `/myself`. Do not
substitute `claude mcp list` for this — see the failure modes below.

### Step 5: Tell the user to restart

MCP tools are loaded when the agent session starts. Say this explicitly, because
the setup otherwise looks broken:

> Restart `claude` (or reload the Cursor window). Until then the tools are
> registered but not callable in this session.

If the user needs an answer *now*, read the issue with the REST fallback script
instead of waiting for the restart:

```bash
python3 ".cursor/skills/atlassian-mcp-setup/scripts/jira_issue.py" QUARK-808
```

## Verification

Ground truth for Cloud, in order — stop at the first failure:

```bash
# 1. Is the site reachable at all? (no credentials needed)
curl -s -o /dev/null -w '%{http_code}\n' https://amd.atlassian.net/rest/api/3/serverInfo   # expect 200

# 2. Do the credentials work?
set -a; source ~/.atlassian.env; set +a
curl -s -u "$JIRA_USERNAME:$JIRA_API_TOKEN" \
  -H 'Accept: application/json' \
  https://amd.atlassian.net/rest/api/3/myself | python3 -m json.tool | head   # expect displayName

# 3. Is the MCP server registered and startable?
claude mcp list
```

Step 1 passing while step 2 fails isolates the problem to credentials and rules
out network, proxy, and VPN. That distinction is the whole point of running it.

## Reading Jira Descriptions (Cloud)

Cloud `/rest/api/3` returns descriptions and comments as **ADF** (Atlassian
Document Format) — a nested JSON tree, not a string. `fields.description` is an
object; printing it gives you unreadable JSON. Flatten it, or request
`/rest/api/2`, which returns wiki-markup text instead. `scripts/jira_issue.py`
handles the ADF walk.

## Common Failure Modes

1. **`401` with `x-seraph-loginreason: AUTHENTICATED_FAILED`**
   - the credential pair was rejected: wrong email, wrong/revoked token, or a
     scoped token used against the site URL
   - it is *not* a permissions problem; a permissions problem is `403` or a `404`
     on a specific issue
   - inspect the header with `curl -D - -o /dev/null ...`
2. **Every candidate email returns the same 401** — stop guessing. Have the user
   read their address off <https://id.atlassian.com/manage-profile/profile-and-visibility>.
3. **`claude mcp list` shows Connected but every tool call fails** — expected.
   The launcher starts successfully whether or not the credentials are valid;
   `mcp-atlassian` does not authenticate at startup. Only `/myself` proves auth.
4. **`Failed to connect — -32000: Connection closed`** — the launcher exited.
   Usually `~/.atlassian.env` is missing, or `uvx` is not on the launcher's `PATH`.
   Run the launcher directly to see its stderr.
5. **`uvx: command not found`** — `pipx install uv`. The launcher also prepends
   `~/.local/bin` to `PATH` because MCP servers inherit a minimal environment,
   not your interactive shell's.
6. **Tools are missing in the current session** — MCP servers load at session
   start. Restart. This is not a misconfiguration.
7. **Cloud instructions applied to `jira.xilinx.com`** (or the reverse) — the
   email+token pair is meaningless to a Server instance and vice versa. See the
   table above.
8. **Confluence 404 on every page** — `CONFLUENCE_URL` is missing the `/wiki`
   suffix.
9. **Anonymous `serverInfo` returns 200 and this is read as success** — many
   Atlassian sites allow anonymous access to a few endpoints. It proves
   reachability only.
10. **Issue description prints as a JSON blob** — that is ADF. See above.
11. **Token pasted into chat** — finish the setup, then tell the user to revoke
    and reissue it. Do not pretend it did not happen; do not re-print it.

## Supported Jira / Confluence Tools

Once loaded, `mcp-atlassian` exposes (among others):

| Tool | Purpose |
|---|---|
| `jira_get_issue` | read one issue by key |
| `jira_search` | JQL search |
| `jira_create_issue` | create a ticket |
| `jira_update_issue` | edit fields |
| `jira_transition_issue` | move through workflow |
| `jira_add_comment` | comment |
| `confluence_search` | CQL / text search |
| `confluence_get_page` | read a page |

Pass `--read-only` to `setup_atlassian_mcp.sh` to register the server with all
write tools disabled. Recommend this when the agent only needs to read tickets.

## Validation Checklist

- [ ] no token in any repository file
- [ ] no token in `~/.claude.json` — only the launcher path
- [ ] `~/.atlassian.env` exists and is mode `600`
- [ ] token was never passed as a command-line argument
- [ ] the account email was confirmed by the user, not inferred
- [ ] deployment type matches the auth scheme (Cloud vs Server)
- [ ] `rest/api/3/myself` returns 200 and a display name
- [ ] `claude mcp list` reports the server, and this was *not* treated as proof of auth
- [ ] the user was told to restart the session before the tools work
- [ ] if the token was pasted into chat, rotation was recommended
