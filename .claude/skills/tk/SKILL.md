---
name: tk
description: Run tk CLI commands (start, stop, restart, status, list, logs, setup, cleanup, sync-hosts, version, remove) against a tk-managed Traefik stack via natural language — "restart the api service", "show me logs for web", "what's running", "sync hosts", "clean up the stack". Also handles rebuilding an already-onboarded service after a code change. Does NOT onboard brand-new PII/api apps itself — for "add my X app to traefik" on an app that isn't already a service, this hands off to traefik-onboard's mandatory hardening gate instead of running a plain add.
---

# tk

Natural-language front end for the `tk` CLI (`scripts/tk`) and its sibling scripts. Every dispatch
below maps to a real command — nothing here reimplements `tk`'s logic. Re-present results as clean
markdown (table/list/checklist); never paste raw `tk` stdout (ANSI codes, box-drawing) into chat.

## Configure
```bash
TRAEFIK_DIR="${TRAEFIK_DIR:-$HOME/localrepo/traefik}"
TK="$TRAEFIK_DIR/scripts/tk"
```

## Install (use from any Claude session)
```bash
ln -s "$TRAEFIK_DIR/scripts/.claude/skills/tk" ~/.claude/skills/tk
```
Works from any cwd on a machine where `scripts/` is already checked out.

## Dispatch table

Always double-quote interpolated `<path>`/`[name]`/`[D]` values (`$TK add "<path>" "[name]"`, never bare).

| Intent | Dispatch | Notes |
|---|---|---|
| start/stop/restart service | `$TK start\|stop\|restart "<name>" --json` | Explicit `--all` for the whole configuration. `--dry-run` previews scope. |
| rebuild existing service | `$TK rebuild "<name>" --json` | Inspect build context first; waits for readiness. |
| wait for service | `$TK wait "<name>" --timeout 30 --json` | Read-only; nonzero exit on timeout. |
| logs / tail logs | `$TK logs [name] --tail 200` | Finite snapshot; add `--follow` only for requested streaming. |
| list services | `$TK list --json` | Resolved URLs, no Docker daemon required. |
| status / what's running | `$TK status --json` | Resolved URLs and container health. |
| set up the stack | `$TK setup` | Idempotent. Check `certs/cert.pem`/`mkcert -CAROOT` first — if the CA isn't already trusted, warn the user it may pop a system keychain dialog. |
| clean up / reset the stack | See **Cleanup** | Never run bare. |
| remove/delete service X | See **Remove** | Preview first; apply within the user-authorized scope. |
| sync hosts | `$TK sync-hosts` | Run **sudo pre-flight** first. Known bug: can write a bogus entry pulled from docker-compose.yml's commented template block, and only ever derives `.home.local`. Scan the output and strip anything template-looking before calling it a success. |
| version | `$TK version` | |
| add/connect a service | See **Add** | Mandatory PII/API gate. |
| anything unrecognized | `$TK help` | |

## Sudo pre-flight (add / sync-hosts)
These two write `/etc/hosts` via sudo. Before dispatching any of them:
```bash
sudo -n true 2>/dev/null
```
Succeeds → proceed. Fails → tell the user this needs sudo and neither command can run
non-interactively right now.

**Confirmed (not just a caveat): telling the user to "run `sudo -v` in a terminal first" does not
help.** The Bash tool's shell has no controlling tty (`tty` reports "not a tty"), and macOS's sudo
scopes cached credentials per-tty (`tty_tickets`, on by default) — a `sudo -v` run in the user's real
terminal warms a timestamp this check can never see, no matter how recently it was run. Don't tell
the user to retry after `sudo -v`; it won't change the outcome. The only way to make these two
commands work non-interactively is a narrowly-scoped `NOPASSWD` sudoers entry for the exact
`tee -a /etc/hosts` / `sed ... /etc/hosts` invocations — set that up once, outside this skill, if you
want `add`/`sync-hosts` to stop requiring a manual `/etc/hosts` edit.

Skip this check for `add --dry-run` and targeted `tk rebuild` —
neither touches `/etc/hosts`.

## Add
1. **Rebuild check first.** Normalize the candidate name like `connect-service.sh` does (lowercase,
   non-`[a-z0-9-]` → `-`) and check if it already exists in `docker-compose.yml`.

   | Case | Then |
   |---|---|
   | Name exists AND resolved `build.context` (`build_context` from `$TK inspect "<name>" --json`) matches the supplied `<path>` | Confirmed rebuild — skip the PII/API gate. Preview `$TK rebuild "<name>" --dry-run --json`, then apply `$TK rebuild "<name>" --json`. This builds and recreates the target, excludes dependencies by default, and waits for readiness. Never pass `--port`/`--domain`/`--harden` on this branch. |
   | Name exists, build context does NOT match | Name conflict, not a rebuild — a name match alone proves nothing. Ask for a different name, then treat as new app (row below). |
   | No name match | New app — go to step 2. |

2. **PII/API gate (mandatory, hard stop).** Ask: does it hold PII or expose any `/api`/data route?
   - Verified "no" → dispatch `$TK add "<path>" "[name]" [--port P] [--domain D] [--no-docker] [--harden] [--dry-run]` (sudo pre-flight first, skip only for `--dry-run`). Recommend `--dry-run` first if unpreviewed.
   - Yes, or unknown → **do not dispatch anything this turn.** Tell the user this needs `traefik-onboard`'s hardening gate; they should re-invoke with that skill's trigger phrase, carrying the same `<path>`.

## Remove
Preview with `$TK remove "<name>" --json`. Inspect the affected service, dependencies
and data-retention note, then use `$TK remove "<name>" --apply --json` within the
user's authorized scope. Removal defaults to preview and never prompts on stdin.
It removes only the selected containers and Compose block; other services, volumes
and app source remain. Container-only data is lost. No sudo or hosts edit is used.
The source must be one supported Compose file; validation failures make no changes.
A private backup path is returned after apply begins. On partial failure, inspect
Docker and the current source before retrying; preserve concurrent user edits.
Structured mutations share a checkout lock; `operation_in_progress` means wait for
the other command to finish. Read-only status and previews remain available.

## Cleanup
`cleanup.sh` prompts interactively with no non-interactive override. Ask the user in chat which of
certs/`.env` to remove (default both to `n` if unclear), then:
```bash
cd "$TRAEFIK_DIR" && printf '%s%s' "<certs-answer:y|n>" "<env-answer:y|n>" | "$TRAEFIK_DIR/scripts/cleanup.sh"
```
No newline between the two answers — a newline-separated pipe drops the second one.

## URL derivation (status / list / setup)

Use `tk list --json` or `tk status --json`; the CLI reads resolved router labels and
prefers `.internal` hosts. Do not invent URLs from service names or print full
Compose config, which contains secrets. For readiness use `tk doctor --probe --json`.
An access failure means Docker is unavailable to this shell, not that services are stopped.

## Output presentation

| Command | Present as |
|---|---|
| status | Table: `Service \| Running \| URL`. |
| list | Bullet list, one service + URL per line. |
| add | Service/Language/Framework/Port/Domain/Mode summary + resulting URL; bold-warn on `--harden` that the app must still enforce the token. Rebuild's raw-bypass branch emits a full build transcript — condense to a pass/fail summary. |
| logs | Fenced code block, ANSI stripped; call out `error`/traceback lines above it. |
| remove | Report preview/applied state, exact service, preserved volumes, backup path and any partial failure. |
| cleanup | Before/after summary of what changed. |
| setup | Checklist (`✓ certs`, `✓ network`, `✓ stack up`) + URL list. |
| errors | Plain-language failure + one concrete next step. |
| everything else | Strip ANSI/box-drawing, show the rest plain. |

## Non-goals
Doesn't reimplement `tk`. Doesn't cover maintenance scripts (`install.sh`, `run-tests.sh`,
`merge-to-main.sh`, etc.) or machine-level DNS setup. Never onboards a brand-new PII/API app
itself — that's `traefik-onboard`'s job. No bundled code beyond this file.
