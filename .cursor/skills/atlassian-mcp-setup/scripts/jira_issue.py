#!/usr/bin/env python3
"""Read a Jira issue over REST, without the MCP layer.

Two reasons this exists:

1. MCP servers only load at agent-session start, so right after setup there is a
   window where the tools are registered but not callable. This covers it.
2. Cloud /rest/api/3 returns descriptions and comments as ADF (Atlassian
   Document Format) -- a nested JSON tree, not a string. Printing the raw field
   gives unreadable JSON. This flattens it to text.

Credentials come from ~/.atlassian.env (see setup_atlassian_mcp.sh). Nothing is
ever echoed back.

    python3 jira_issue.py QUARK-808
    python3 jira_issue.py QUARK-808 --comments
    python3 jira_issue.py --jql 'project = QUARK AND assignee = currentUser() AND statusCategory != Done'
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

DEFAULT_ENV = Path(os.environ.get("ATLASSIAN_ENV_FILE", Path.home() / ".atlassian.env"))

FIELDS = (
    "summary,status,issuetype,priority,assignee,reporter,created,updated,"
    "labels,components,description,parent,resolution,duedate,fixVersions"
)


def load_env(path: Path) -> dict[str, str]:
    if not path.exists():
        sys.exit(f"error: credentials file not found: {path}\n"
                 f"       run setup_atlassian_mcp.sh first")
    env: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def make_opener(env: dict[str, str]) -> tuple[str, int, dict[str, str]]:
    base = env.get("JIRA_URL", "").rstrip("/")
    if not base:
        sys.exit("error: JIRA_URL not set")
    cloud = ".atlassian.net" in base
    api = 3 if cloud else 2
    headers = {"Accept": "application/json"}
    if cloud:
        user, token = env.get("JIRA_USERNAME", ""), env.get("JIRA_API_TOKEN", "")
        if not user or not token:
            sys.exit("error: cloud site needs JIRA_USERNAME and JIRA_API_TOKEN")
        blob = base64.b64encode(f"{user}:{token}".encode()).decode()
        headers["Authorization"] = f"Basic {blob}"
    else:
        pat = env.get("JIRA_PERSONAL_TOKEN", "")
        if not pat:
            sys.exit("error: Server/DC site needs JIRA_PERSONAL_TOKEN")
        headers["Authorization"] = f"Bearer {pat}"
    return base, api, headers


def get(url: str, headers: dict[str, str]) -> dict:
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:300]
        if e.code == 401:
            reason = e.headers.get("x-seraph-loginreason", "")
            extra = (" (x-seraph-loginreason: %s -- credential pair rejected, "
                     "not a permissions problem)" % reason) if reason else ""
            sys.exit(f"error: HTTP 401{extra}\n       run healthcheck.sh to diagnose")
        if e.code == 404:
            sys.exit(f"error: HTTP 404 -- issue does not exist, or your account cannot see it")
        sys.exit(f"error: HTTP {e.code}: {detail}")
    except urllib.error.URLError as e:
        sys.exit(f"error: cannot reach Jira: {e.reason}")


def adf_to_text(node, out: list[str]) -> None:
    """Flatten an Atlassian Document Format tree into plain text."""
    if isinstance(node, list):
        for child in node:
            adf_to_text(child, out)
        return
    if not isinstance(node, dict):
        return
    kind = node.get("type")
    if kind == "text":
        out.append(node.get("text", ""))
    elif kind == "hardBreak":
        out.append("\n")
    elif kind in ("inlineCard", "blockCard"):
        out.append(node.get("attrs", {}).get("url", ""))
    elif kind == "mention":
        out.append("@" + node.get("attrs", {}).get("text", "").lstrip("@"))
    elif kind == "listItem":
        out.append("- ")
    for child in node.get("content", []) or []:
        adf_to_text(child, out)
    if kind in ("paragraph", "heading", "listItem", "tableRow", "codeBlock", "rule"):
        out.append("\n")


def render_body(value) -> str:
    if value is None:
        return "(empty)"
    if isinstance(value, str):          # /rest/api/2 returns wiki markup
        return value.strip() or "(empty)"
    out: list[str] = []
    adf_to_text(value, out)
    text = "".join(out)
    while "\n\n\n" in text:
        text = text.replace("\n\n\n", "\n\n")
    return text.strip() or "(empty)"


def name_of(field, key: str = "name") -> str:
    return (field or {}).get(key) or "-"


def print_issue(base: str, issue: dict, show_comments: bool, api: int,
                headers: dict[str, str]) -> None:
    f = issue["fields"]
    print(f"{issue['key']}  {f.get('summary', '')}")
    print(f"{base}/browse/{issue['key']}")
    print()
    print(f"type      : {name_of(f.get('issuetype'))}")
    print(f"status    : {name_of(f.get('status'))}"
          f"   resolution: {name_of(f.get('resolution'))}"
          f"   priority: {name_of(f.get('priority'))}")
    print(f"assignee  : {name_of(f.get('assignee'), 'displayName')}"
          f"   reporter: {name_of(f.get('reporter'), 'displayName')}")
    print(f"created   : {(f.get('created') or '')[:10]}"
          f"   updated: {(f.get('updated') or '')[:10]}"
          f"   due: {f.get('duedate') or '-'}")
    comps = [c["name"] for c in f.get("components") or []]
    print(f"components: {', '.join(comps) or '-'}"
          f"   labels: {', '.join(f.get('labels') or []) or '-'}")
    parent = f.get("parent")
    if parent:
        print(f"parent    : {parent['key']} - {parent['fields']['summary']}")
    print()
    print("--- description ---")
    print(render_body(f.get("description")))

    if show_comments:
        data = get(f"{base}/rest/api/{api}/issue/{issue['key']}/comment?maxResults=50", headers)
        comments = data.get("comments", [])
        print(f"\n--- comments ({len(comments)}) ---")
        for c in comments:
            who = (c.get("author") or {}).get("displayName", "?")
            print(f"\n[{c.get('created', '')[:16]}] {who}")
            print(render_body(c.get("body")))


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("key", nargs="?", help="issue key, e.g. QUARK-808")
    p.add_argument("--jql", help="run a JQL search instead of fetching one issue")
    p.add_argument("--max", type=int, default=25, help="max JQL results (default 25)")
    p.add_argument("--comments", action="store_true", help="also print comments")
    p.add_argument("--json", action="store_true", help="dump raw JSON instead")
    p.add_argument("--env-file", default=str(DEFAULT_ENV))
    args = p.parse_args()

    if not args.key and not args.jql:
        p.error("give an issue key or --jql")

    base, api, headers = make_opener(load_env(Path(args.env_file)))

    if args.jql:
        # Cloud retired GET /rest/api/3/search in 2025 (CHANGE-2046) in favour of
        # /search/jql, which is token-paginated and reports no total. Server/DC
        # still only has the old endpoint.
        path = "search/jql" if api == 3 else "search"
        url = (f"{base}/rest/api/{api}/{path}?jql={urllib.parse.quote(args.jql)}"
               f"&maxResults={args.max}&fields=summary,status,assignee,updated")
        data = get(url, headers)
        issues = data.get("issues", [])
        total = data.get("total")
        more = "" if data.get("isLast", True) else " (more available)"
        print(f"{total if total is not None else len(issues)} match(es){more}\n")
        for it in issues:
            f = it["fields"]
            print(f"{it['key']:<14} {name_of(f.get('status')):<14} "
                  f"{name_of(f.get('assignee'), 'displayName'):<20} {f.get('summary', '')}")
        return 0

    issue = get(f"{base}/rest/api/{api}/issue/{args.key}?fields={FIELDS}", headers)
    if args.json:
        json.dump(issue, sys.stdout, indent=2, ensure_ascii=False)
        print()
        return 0
    print_issue(base, issue, args.comments, api, headers)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
