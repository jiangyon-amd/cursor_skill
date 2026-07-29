# Scripts README

Every script here follows one rule: **the token exists in exactly one place,
`~/.atlassian.env`, mode 600.** Not in `~/.claude.json`, not in argv, not in the
repository, not in any output.

## Credential File

`~/.atlassian.env` (override with `$ATLASSIAN_ENV_FILE`).

Cloud (`*.atlassian.net`) — HTTP Basic, email + API token, one token for both
products:

```bash
JIRA_URL=https://amd.atlassian.net
JIRA_USERNAME=you@amd.com
JIRA_API_TOKEN=<classic API token>

CONFLUENCE_URL=https://amd.atlassian.net/wiki   # note the /wiki suffix
CONFLUENCE_USERNAME=you@amd.com
CONFLUENCE_API_TOKEN=<same token>
```

Server / Data Center (e.g. `jira.xilinx.com`) — Bearer PAT, no email:

```bash
JIRA_URL=https://jira.xilinx.com
JIRA_PERSONAL_TOKEN=<personal access token>
```

## Included Scripts

### `setup_atlassian_mcp.sh`

Installs `uv` if needed, writes the credential file, installs the launcher,
registers the MCP server, and runs the healthcheck.

```bash
bash setup_atlassian_mcp.sh --site https://amd.atlassian.net --email you@amd.com
# prompts for the token with echo disabled

# or feed it from a password manager:
pass show atlassian/api-token | \
  bash setup_atlassian_mcp.sh --site https://amd.atlassian.net --email you@amd.com
```

Options: `--deployment cloud|server` (inferred from the host), `--confluence-url`,
`--server-name`, `--scope user|local|project`, `--read-only`, `--env-file`,
`--no-register`.

The token is read from `$ATLASSIAN_API_TOKEN`, an echo-off prompt, or stdin.
Passing `--token` is a hard error, on purpose: command-line arguments are visible
in `ps` output to every user on the box and land in shell history.

`--read-only` registers the server with all write tools disabled. Recommend it
whenever the agent only needs to read tickets.

### `mcp-atlassian-launch.sh`

Installed to `~/.claude/mcp-atlassian-launch.sh`; the MCP config points at this
path and carries no `env` block.

It sources the credential file, prepends `~/.local/bin` to `PATH` (MCP servers
inherit a minimal environment, not your interactive shell's, so `uvx` from
`pipx install uv` is otherwise missing), then `exec`s `uvx mcp-atlassian "$@"`.

Registering it by hand:

```bash
claude mcp add mcp-atlassian --scope user -- ~/.claude/mcp-atlassian-launch.sh
```

For Cursor, point the MCP server's `command` at the same path with empty `args`.

### `healthcheck.sh`

Checks in the order that isolates faults, stopping at the first hard failure:

1. credential file exists, is mode 600, and has the right variables **for the
   detected deployment** (warns if you mixed Cloud and Server vars)
2. **reachability** — unauthenticated `serverInfo`. Distinguishes network / proxy
   / VPN problems from credential problems. Skipping this step is how people end
   up debugging a token when the real problem is a firewall.
3. **credentials** — `rest/api/N/myself`, prints the resolved display name. On
   401 it reads `x-seraph-loginreason` and explains what that actually means.
4. Confluence reachability (warn-only; Jira can be fine on its own)
5. `uvx` present, launcher executable, server registered
6. greps `~/.claude.json` for a leaked token and fails if one is there

```bash
bash healthcheck.sh
```

```text
ok:   env file: /home/you/.atlassian.env
ok:   deployment: cloud (https://amd.atlassian.net, /rest/api/3)
ok:   account email: you@amd.com
ok:   site reachable (serverInfo -> HTTP 200)
ok:   jira auth: HTTP 200 — Doe, Jane <you@amd.com>
ok:   confluence auth: HTTP 200 (https://amd.atlassian.net/wiki)
ok:   uvx: found
ok:   launcher: /home/you/.claude/mcp-atlassian-launch.sh
ok:   mcp server registered (note: 'Connected' does NOT imply valid credentials)

healthcheck passed
```

### `jira_issue.py`

Reads Jira over REST, bypassing MCP entirely.

```bash
python3 jira_issue.py QUARK-808
python3 jira_issue.py QUARK-808 --comments
python3 jira_issue.py QUARK-808 --json
python3 jira_issue.py --jql 'project = QUARK AND assignee = currentUser() AND statusCategory != Done'
```

It exists for two reasons:

- MCP servers load at agent-session start, so immediately after setup there is a
  window where the tools are registered but not yet callable. This covers it
  without making the user wait for a restart.
- Cloud `/rest/api/3` returns descriptions and comments as **ADF** (Atlassian
  Document Format), a nested JSON tree rather than a string. Dumping the field
  raw is unreadable; this walks the tree into text. Server `/rest/api/2` returns
  wiki markup, which the same code path passes through untouched.

Standard library only — no `pip install` needed.

## Conventions

- Never print a token, not even partially, not even on error.
- Never accept a token in argv.
- Diagnose in dependency order: reachability, then credentials, then MCP. Each
  step rules out a class of cause; reordering them wastes the user's time.
- `Connected` from `claude mcp list` is not evidence of working auth. The
  launcher starts fine with garbage credentials because `mcp-atlassian` does not
  authenticate at startup. Only `/myself` proves it.
- Prefer failing loudly with the actual HTTP status over a silent fallback.
