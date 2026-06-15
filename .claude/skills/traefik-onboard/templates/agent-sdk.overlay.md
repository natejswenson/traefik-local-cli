# Agent-SDK overlay (additive)

Apply this **on top of** `Dockerfile.python` (or `.node`) and the compose block when the app uses
the Claude Agent SDK (`claude-agent-sdk` / `@anthropic-ai/claude`). It adds the node + pinned
`claude` CLI the SDK shells out to, the runtime auth, and — most importantly — the **agent-isolation
checklist (I4)**, which is the load-bearing security control for an agent over PII.

## 1. Dockerfile additions (a python app now needs node + the claude CLI)

Insert after the base `apt-get` layer:
```dockerfile
# The Claude Agent SDK shells out to the `claude` CLI (published via npm).
RUN apt-get update \
    && apt-get install -y --no-install-recommends gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Pin the CLI to the version the SDK expects. Find <pinned-version>:
#  - Python SDK: read claude_agent_sdk/_cli_version.py → __cli_version__
#    (python -c "import claude_agent_sdk._cli_version as v; print(v.__cli_version__)")
#  - Node SDK: read the @anthropic-ai/claude-agent-sdk package's expected/peer CLI version
#    (npm view @anthropic-ai/claude-code version, reconciled against the SDK's pin).
# Bump in lockstep with the claude-agent-sdk dependency.
RUN npm install -g @anthropic-ai/claude-code@<pinned-version>
```
And pre-create the CLI's config dir in the mkdir layer:
```dockerfile
RUN mkdir -p /data /home/app/.claude && chown -R app:app /data /home/app/.claude
```
**Do NOT add `read_only` rootfs** — the claude/npm/uv caches need a writable HOME (budget tried it;
it crash-looped). `no-new-privileges` + `cap_drop: ALL` + non-root are the controls.

## 2. Compose additions
```yaml
    environment:
      - CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}   # long-lived subscription token
    volumes:
      - <app>-claude-config:/home/app/.claude                # caches CLI auth across restarts
```
Add `<app>-claude-config:` under the top-level `volumes:` key. Then in `.env` (gitignored):
```bash
printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$(claude setup-token)" >> ~/localrepo/traefik/.env
```
**Chat must degrade gracefully** if the token is unset/expired — the rest of the app keeps working.

## 3. Handoff (Phase 5)
One-time, after first `up`: `docker exec -it <app> claude` to log in interactively. **Chat is broken
until this runs** — say so explicitly in the handoff.

---

## 4. Agent-isolation checklist (I4) — the four mechanisms, all required

"The agent reads a sanitized projection" is NOT enough. Reproduce all four (this is exactly how
budget does it — `src/local_budget/agent/{chat,tools}.py` + `agent_db.py`):

**(a) Separate DB file — the agent never gets a handle to the PII store.**
The agent's tools read a *physically separate* `agent.db` containing only a sanitized projection
(e.g. a `txn` table with `account_last4`, never full account numbers). The agent code contains
**zero** references to the PII DB path. *Check:* `grep -r '<pii-db>.db' <agent-dir>/` returns nothing.

**(b) Read-only connection with a deny-ATTACH authorizer + table allow-list.**
Open `agent.db` `mode=ro` + `PRAGMA query_only`, with a `sqlite3` authorizer that **DENIES**
`ATTACH`/`DETACH`/writes/`PRAGMA` and allow-lists the readable tables. The ATTACH-deny is what stops
a prompt-injected agent from re-attaching the PII DB — it is the real control, not the keyword guard.

**(c) Fail-closed `can_use_tool` default-deny in the SDK options** (verbatim shape from `chat.py`):
```python
_ALLOWLIST_PREFIX = f"mcp__{SERVER_NAME}__"

async def _can_use_tool(tool_name, _input, _ctx):
    if tool_name.startswith(_ALLOWLIST_PREFIX):
        return PermissionResultAllow()
    return PermissionResultDeny(message="Only <app> tools are permitted.")

ClaudeAgentOptions(
    mcp_servers={SERVER_NAME: make_server()},
    allowed_tools=allowed_tool_names(),
    disallowed_tools=DENIED_BUILTIN_TOOLS,
    can_use_tool=_can_use_tool,        # fail-closed default-deny — survives the SDK adding builtins
    permission_mode="default",         # NEVER "bypassPermissions"
    setting_sources=[],                # do not inherit ambient settings/tools
    strict_mcp_config=True,
    max_turns=30,
)
```
Requires `ClaudeSDKClient` (streaming) — `can_use_tool` only fires in streaming mode.

**(d) Any raw-SQL tool is SELECT/WITH-only and scrubs error text.**
Reject anything not starting `select`/`with`; a secondary forbidden-keyword guard (`insert update
delete drop alter create attach detach pragma vacuum reindex`); on `sqlite3.Error` return a generic
message — **never** leak row/constraint values into the exception string.

**I4 gate (checkable) — set the REAL values; placeholders silently false-pass:**
```bash
agent_dir="<agent-dir>"          # the agent source dir, e.g. src/<app>/agent
pii_db="<pii-db-filename>"        # the app's REAL PII DB, e.g. budget.db — NOT a placeholder
[ "$pii_db" = "<pii-db-filename>" ] && echo "FAIL: substitute pii_db with the real filename first"
# (a) agent never references the PII store:
grep -rq "$pii_db" "$agent_dir"/ && echo "FAIL: agent references the PII DB ($pii_db)" || echo "PASS: no PII-DB ref"
# (c) NEVER bypassPermissions; can_use_tool must be CONFIGURED (kwarg), not just mentioned/commented.
#     Strip comments before grepping so a `# TODO add can_use_tool` can't pass.
src=$(grep -rhv '^\s*#' "$agent_dir"/*.py)
echo "$src" | grep -q 'bypassPermissions' && echo "FAIL: bypassPermissions present" || echo "PASS: no bypass"
echo "$src" | grep -Eq 'can_use_tool\s*=' && echo "PASS: can_use_tool configured" || echo "FAIL: no configured can_use_tool"
echo "$src" | grep -q 'PermissionResultDeny' && echo "PASS: default-deny branch present" || echo "FAIL: no deny branch"
echo "$src" | grep -q 'setting_sources=\[\]' && echo "PASS: ambient settings disabled" || echo "FAIL: setting_sources not empty"
# (b) read-only + deny-ATTACH authorizer on the agent DB (the real isolation control):
echo "$src" | grep -Eq 'mode=ro|query_only' && echo "PASS: read-only conn" || echo "FAIL: agent DB not opened read-only"
echo "$src" | grep -qi 'authorizer\|set_authorizer' && echo "PASS: authorizer present" || echo "FAIL: no deny-ATTACH authorizer"
# (d) raw-SQL tool is SELECT/WITH-only:
echo "$src" | grep -Eqi 'select|with' && echo "NOTE: confirm any raw-SQL tool rejects non-SELECT/WITH and scrubs errors"
```
Mechanisms (b) and (d) are app code you must WRITE from the spec above (budget's `agent_db.py`/`tools.py`
are the reference) — the grep only confirms the markers are present, not that the logic is correct. Read
the generated code.
