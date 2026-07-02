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
| start/stop/restart [service] | `$TK start\|stop\|restart [name]` | No confirmation needed. |
| logs / tail logs | `docker compose --project-directory "$TRAEFIK_DIR" logs --tail=200 [name]` | Not `tk logs` — it has no `--tail` and dumps full history before following. |
| list services | `$TK list` | See **URL derivation**. |
| status / what's running | `$TK status` | See **URL derivation**. |
| set up the stack | `$TK setup` | Idempotent. Check `certs/cert.pem`/`mkcert -CAROOT` first — if the CA isn't already trusted, warn the user it may pop a system keychain dialog. |
| clean up / reset the stack | See **Cleanup** | Never run bare. |
| remove/delete service X | See **Remove** | Destructive — chat-confirm first. |
| sync hosts | `$TK sync-hosts` | Run **sudo pre-flight** first. Known bug: can write a bogus entry pulled from docker-compose.yml's commented template block, and only ever derives `.home.local`. Scan the output and strip anything template-looking before calling it a success. |
| version | `$TK version` | |
| add/connect a service | See **Add** | Mandatory PII/API gate. |
| anything unrecognized | `$TK help` | |

## Sudo pre-flight (add / remove / sync-hosts)
These three write `/etc/hosts` via sudo. Before dispatching any of them:
```bash
sudo -n true 2>/dev/null
```
Succeeds → proceed. Fails → tell the user this needs sudo and none of the three commands can run
non-interactively right now.

**Confirmed (not just a caveat): telling the user to "run `sudo -v` in a terminal first" does not
help.** The Bash tool's shell has no controlling tty (`tty` reports "not a tty"), and macOS's sudo
scopes cached credentials per-tty (`tty_tickets`, on by default) — a `sudo -v` run in the user's real
terminal warms a timestamp this check can never see, no matter how recently it was run. Don't tell
the user to retry after `sudo -v`; it won't change the outcome. The only way to make these three
commands work non-interactively is a narrowly-scoped `NOPASSWD` sudoers entry for the exact
`tee -a /etc/hosts` / `sed ... /etc/hosts` invocations — set that up once, outside this skill, if you
want `add`/`remove`/`sync-hosts` to stop requiring a manual `/etc/hosts` edit.

Skip this check for `add --dry-run` and add's rebuild raw-bypass (`docker compose up -d --build`) —
neither touches `/etc/hosts`.

## Add
1. **Rebuild check first.** Normalize the candidate name like `connect-service.sh` does (lowercase,
   non-`[a-z0-9-]` → `-`) and check if it already exists in `docker-compose.yml`.

   | Case | Then |
   |---|---|
   | Name exists AND resolved `build.context` (via `docker compose --project-directory "$TRAEFIK_DIR" config`) matches the supplied `<path>` | Confirmed rebuild — skip the PII/API gate. If `<path>` known: `$TK add "<path>" "[name]"`. If not: `docker compose --project-directory "$TRAEFIK_DIR" up -d --build "<name>"` (one command — never a separate `build` + `$TK restart`, which only restarts in place and won't pick up the new image). Never pass `--port`/`--domain`/`--harden` on either branch. |
   | Name exists, build context does NOT match | Name conflict, not a rebuild — a name match alone proves nothing. Ask for a different name, then treat as new app (row below). |
   | No name match | New app — go to step 2. |

2. **PII/API gate (mandatory, hard stop).** Ask: does it hold PII or expose any `/api`/data route?
   - Verified "no" → dispatch `$TK add "<path>" "[name]" [--port P] [--domain D] [--no-docker] [--harden] [--dry-run]` (sudo pre-flight first, skip only for `--dry-run`). Recommend `--dry-run` first if unpreviewed.
   - Yes, or unknown → **do not dispatch anything this turn.** Tell the user this needs `traefik-onboard`'s hardening gate; they should re-invoke with that skill's trigger phrase, carrying the same `<path>`.

## Remove
Chat-confirm first (state what happens: removed from compose, full `down`/`up -d`, an *attempt* at
an `/etc/hosts` removal). Run sudo pre-flight, then:
```bash
CONFIRM_DESTRUCTIVE=false $TK remove <name>
```
`CONFIRM_DESTRUCTIVE=false` is required — without it, `tk`'s own confirm prompt reads from stdin,
hits EOF, and silently no-ops. Hosts-cleanup isn't reliable (`tk`'s domain lookup misses or picks
the wrong domain for real services) — tell the user to double-check `/etc/hosts` manually, don't
state it as done.

## Cleanup
`cleanup.sh` prompts interactively with no non-interactive override. Ask the user in chat which of
certs/`.env` to remove (default both to `n` if unclear), then:
```bash
cd "$TRAEFIK_DIR" && printf '%s%s' "<certs-answer:y|n>" "<env-answer:y|n>" | "$TRAEFIK_DIR/scripts/cleanup.sh"
```
No newline between the two answers — a newline-separated pipe drops the second one.

## URL derivation (status / list / setup)
`tk status`/`tk list` synthesize `https://<service>.internal` from the service name, which is wrong
for a custom `--domain`. Derive the real URL instead: run
`docker compose --project-directory "$TRAEFIK_DIR" config` and read each service's resolved
`traefik.http.routers.*.rule` (never grep raw `docker-compose.yml` — its labels have unresolved
`${VAR}` interpolation). Prefer the `.internal` host when a rule has more than one; match any router
key under the service's own labels, don't assume it equals the service name (e.g. `traefik`'s own
router is `dashboard`); skip services with no router (e.g. `traefik.enable: "false"`). `tk setup`
should list URLs for every service this same way, not a hardcoded subset.

## Output presentation

| Command | Present as |
|---|---|
| status | Table: `Service \| Running \| URL`. |
| list | Bullet list, one service + URL per line. |
| add | Service/Language/Framework/Port/Domain/Mode summary + resulting URL; bold-warn on `--harden` that the app must still enforce the token. Rebuild's raw-bypass branch emits a full build transcript — condense to a pass/fail summary. |
| logs | Fenced code block, ANSI stripped; call out `error`/traceback lines above it. |
| remove / cleanup | Before/after summary of what changed; phrase hosts-cleanup as "attempted, not guaranteed." |
| setup | Checklist (`✓ certs`, `✓ network`, `✓ stack up`) + URL list. |
| errors | Plain-language failure + one concrete next step. |
| everything else | Strip ANSI/box-drawing, show the rest plain. |

## Non-goals
Doesn't reimplement `tk`. Doesn't cover maintenance scripts (`install.sh`, `run-tests.sh`,
`merge-to-main.sh`, etc.) or machine-level DNS setup. Never onboards a brand-new PII/API app
itself — that's `traefik-onboard`'s job. No bundled code beyond this file.
