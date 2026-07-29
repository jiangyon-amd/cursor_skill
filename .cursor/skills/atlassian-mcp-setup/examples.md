# Examples

## Example 1: Agent Cannot Open a Jira URL

User request:

```text
https://amd.atlassian.net/browse/QUARK-808  can you access this?
```

Expected behavior:

1. Try once and report honestly. A plain web fetch returns a login wall that
   renders to the single word "Jira" — say that, rather than guessing at the
   ticket contents.
2. Recognize `*.atlassian.net` as **Cloud**, so the auth scheme is email + API
   token, not a Personal Access Token.
3. Offer to set up `mcp-atlassian`, and check what is already present:

```bash
command -v uvx claude
claude mcp list
```

4. Ask for the account email. **Do not guess it from the Linux username** — the
   two are frequently unrelated, and every wrong guess returns an identical 401
   that tells you nothing.
5. Offer the two token paths (see Example 2 and Example 3).
6. After setup, read the issue immediately with the REST fallback rather than
   making the user restart first:

```bash
python3 ".cursor/skills/atlassian-mcp-setup/scripts/jira_issue.py" QUARK-808
```

7. Then tell them to restart the session so the MCP tools become callable.

## Example 2: User Does Not Want the Token in Chat

User request:

```text
Set it up, but I do not want to paste my token into the conversation.
```

Expected behavior:

1. Confirm that is the better path and give them a command to run in their own
   terminal:

```bash
bash ".cursor/skills/atlassian-mcp-setup/scripts/setup_atlassian_mcp.sh" \
  --site "https://amd.atlassian.net" \
  --email "you@amd.com"
```

2. Point at <https://id.atlassian.com/manage-profile/security/api-tokens> and say
   explicitly to use **"Create API token"**, not "Create API token with scopes" —
   scoped tokens do not work against the site URL and fail with the same 401 as
   a wrong password.
3. Do not invent a placeholder token or write a partial credential file.
4. Give them the verification command to run afterwards:

```bash
bash ".cursor/skills/atlassian-mcp-setup/scripts/healthcheck.sh"
```

5. Ask them to report back the healthcheck output, which is safe to paste — it
   never contains the token.

## Example 3: User Pastes the Token Anyway

User request:

```text
you@amd.com  ATATT3xFf...
```

Expected behavior:

1. Use it. The user made an informed choice; do not lecture or re-ask.
2. Write `~/.atlassian.env` with mode 600. Never echo the token back, and never
   copy it into `~/.claude.json`.
3. Verify before claiming success:

```bash
bash ".cursor/skills/atlassian-mcp-setup/scripts/healthcheck.sh"
```

4. Once at the end, in one line: the token is in the transcript, so it should be
   rotated when convenient, and rotating it means editing two lines in
   `~/.atlassian.env` with no agent config changes.

## Example 4: Debugging a 401

User request:

```text
It says connected but every Jira call fails.
```

Expected behavior:

1. Do not trust `claude mcp list`. "Connected" only means the launcher process
   started; `mcp-atlassian` does not authenticate at startup, so it connects
   happily with garbage credentials.
2. Run the checks in dependency order — this is what `healthcheck.sh` does:

```bash
# reachability, no credentials
curl -s -o /dev/null -w '%{http_code}\n' https://amd.atlassian.net/rest/api/3/serverInfo

# credentials
set -a; source ~/.atlassian.env; set +a
curl -s -D - -o /dev/null -u "$JIRA_USERNAME:$JIRA_API_TOKEN" \
  https://amd.atlassian.net/rest/api/3/myself | grep -iE '^HTTP|x-seraph'
```

3. Read the result:
   - `serverInfo` 200 + `myself` 401 → credentials, not network. Stop looking at
     proxies and VPN.
   - `x-seraph-loginreason: AUTHENTICATED_FAILED` → the pair was **rejected**.
     Not a permissions issue; permissions failures are 403, or 404 on a specific
     issue.
4. Narrow it down, in this order:
   - **email** — have the user read it off
     <https://id.atlassian.com/manage-profile/profile-and-visibility>. Do not
     try variants; every wrong one returns the same 401, so brute force yields
     no information and costs a round trip each.
   - **token kind** — a "with scopes" token cannot be used with Basic auth
     against the site URL. Have them create a classic one.
   - **token validity** — check it still exists on the API tokens page.
5. Confirm the fix with `myself` returning a display name, not by re-running
   `claude mcp list`.

## Example 5: Both Cloud and On-Prem

User request:

```text
I need both amd.atlassian.net and jira.xilinx.com.
```

Expected behavior:

1. Explain the constraint: one `mcp-atlassian` process serves exactly one
   `JIRA_URL`, so this needs two registered servers with two credential files.
2. The credentials are also different in kind — Cloud takes email + API token,
   Server/DC takes a Personal Access Token from the Jira profile page. One will
   not work for the other.

```bash
# Cloud
bash setup_atlassian_mcp.sh \
  --site https://amd.atlassian.net --email you@amd.com \
  --server-name mcp-atlassian-cloud --env-file ~/.atlassian-cloud.env

# On-prem (prompts for a PAT, not an API token)
bash setup_atlassian_mcp.sh \
  --site https://jira.xilinx.com --deployment server \
  --server-name mcp-atlassian-onprem --env-file ~/.atlassian-onprem.env
```

3. Verify each independently:

```bash
ATLASSIAN_ENV_FILE=~/.atlassian-cloud.env  bash healthcheck.sh
ATLASSIAN_ENV_FILE=~/.atlassian-onprem.env bash healthcheck.sh
```

## Example 6: Read-Only Access

User request:

```text
Connect Jira, but I do not want the agent creating or editing tickets.
```

Expected behavior:

1. Use `--read-only`, which registers the launcher with the flag that disables
   every write tool in `mcp-atlassian`:

```bash
bash setup_atlassian_mcp.sh --site https://amd.atlassian.net \
  --email you@amd.com --read-only
```

2. Note that this is enforced by the MCP server, not by agent discretion — the
   write tools are not exposed at all.
3. To lift it later, re-run without `--read-only`; the credential file is reused
   and the token does not need to be re-entered if it is already in place.
