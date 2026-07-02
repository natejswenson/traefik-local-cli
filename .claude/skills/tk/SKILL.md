---
name: tk
description: Run tk CLI commands (start, stop, restart, status, list, logs, setup, cleanup, sync-hosts, version, remove) against a tk-managed Traefik stack via natural language — "restart the api service", "show me logs for web", "what's running", "sync hosts", "clean up the stack". Also handles rebuilding an already-onboarded service after a code change. Does NOT onboard brand-new PII/api apps itself — for "add my X app to traefik" / "expose my app at <name>.internal" on an app that isn't already a service, this skill hands off to traefik-onboard's mandatory hardening gate instead of running a plain add.
---

# tk

A thin, natural-language front end for the existing `tk` CLI (`scripts/tk`) and its sibling scripts
(`connect-service.sh`, `cleanup.sh`, `setup.sh`). It never reimplements `tk`'s logic — every command
below maps to a real `tk`/`docker compose` invocation. Its two jobs are (1) dispatch the right
command safely, and (2) re-present the result as clean chat-native markdown instead of raw
terminal output.

## Configure (set once, same convention as traefik-onboard)
```bash
TRAEFIK_DIR="${TRAEFIK_DIR:-$HOME/localrepo/traefik}"
TK="$TRAEFIK_DIR/scripts/tk"
```
`TRAEFIK_DIR` is an absolute path by default — this skill resolves the stack the same way
regardless of the invoking session's working directory. If your stack lives elsewhere, set
`TRAEFIK_DIR` once in your shell profile.

## Install (global availability)
This skill lives in `scripts/.claude/skills/tk/` (versioned with the CLI it wraps). To use it from
any Claude session on this machine, not just inside this repo checkout:
```bash
ln -s "$TRAEFIK_DIR/scripts/.claude/skills/tk" ~/.claude/skills/tk
```
This works on any cwd where `scripts/` is already checked out on this machine — it is not a
"works after a fresh clone" guarantee (the outer repo currently has no `.gitmodules` registration
for the `scripts` submodule, a separate pre-existing gap outside this skill's scope).

---

## Command dispatch table

**Quoting discipline.** Any interpolated `<path>`, `[name]`, or `[--domain D]` value is always
double-quoted in the constructed command (e.g. `$TK add "<path>" "[name]" --domain "[D]"`) — never
bare. Real paths (iCloud/Dropbox-synced dirs, names with spaces) commonly contain spaces.

| User intent | Dispatch | Notes |
|---|---|---|
| "start [service]" / "stop [service]" / "restart [service]" | `$TK start\|stop\|restart [name]` | No confirmation needed — reversible, no data loss. |
| "show logs for X" / "tail logs" | `docker compose --project-directory "$TRAEFIK_DIR" logs --tail=200 [name]` | Deliberately **not** `$TK logs` — `tk logs` has no `--tail` and dumps full history before following, a flood/dangling-process risk. `--project-directory` makes this resolve correctly no matter the invoking cwd. Read-bounded, doesn't block the conversation indefinitely. |
| "list services" | `$TK list` | Read-only. See **URL derivation** below — don't trust `tk`'s own printed URL. |
| "status" / "what's running" | `$TK status` | Read-only. See **URL derivation** below. |
| "set up the stack" / "initial setup" | `$TK setup` | Runs `scripts/setup.sh`. Idempotent — safe to re-run. Before dispatching, do a cheap best-effort check for whether the CA already looks trusted (`certs/cert.pem`/`certs/key.pem` already exist and are non-empty, or `mkcert -CAROOT` already has an installed root); if you can't confirm it, warn the user up front: "this may pop up a system keychain-trust dialog outside this chat — please approve it if it appears." |
| "clean up / reset the stack" | See **Cleanup handling** below | Never run bare — always chat-confirm scope first. |
| "remove/delete service X" | See **Remove handling** below | Destructive — always chat-confirm first. |
| "sync hosts" | `$TK sync-hosts` | Writes `/etc/hosts` via `sudo tee -a`. Run the **sudo pre-flight** first. **Known defect:** `cmd_sync_hosts`'s regex has no comment-line exclusion, so it can pull a bogus `service-name.home.local` entry straight from `docker-compose.yml`'s commented-out template block, and it only ever derives `.home.local` domains, never `.internal`. Before presenting the result as success, scan the output and flag/strip any entry that looks template-derived (literally `service-name.home.local`). |
| "what version" | `$TK version` | Read-only. |
| "add/connect this service", "expose ~/path as X" | See **Add handling** below | Mandatory PII/API gate — see below. |
| anything unrecognized | `$TK help` | Matches `tk`'s own fallback. |

---

## Add handling (rebuild check, then mandatory PII/API gate)

`traefik-onboard` is the mandatory hardened-onboarding path for any genuinely new PII/api app. This
skill's `add` trigger phrases overlap with `traefik-onboard`'s own triggers, so before doing
anything else, work out whether this is really a **rebuild of an already-onboarded service** or a
**new exposure**.

**Step 1 — Rebuild check (before any PII/API question).**
1. Normalize the candidate name the same way `connect-service.sh` does: lowercase, replace any
   character outside `[a-z0-9-]` with `-` (`connect-service.sh:145`). Use the normalized form, not
   the raw user string, for the existence check below.
2. Check whether that normalized name already exists as a service in `docker-compose.yml`:
   `grep -q "^  ${name}:" "$TRAEFIK_DIR/docker-compose.yml"`.
3. **A name match alone is not proof of rebuild.** If it matches, resolve the existing service's
   `build.context` — prefer `docker compose --project-directory "$TRAEFIK_DIR" config` (fully
   resolves `${VAR}` interpolation) over a targeted grep of that service's block — and compare it,
   normalized to an absolute path, against the normalized absolute form of the supplied `<path>`.
   - **Both match** → this is a confirmed rebuild. Skip the PII/API gate entirely, go to Step 2.
   - **Name matches, build context does not** → **name conflict**, not a rebuild: tell the user the
     name is already in use by a different, unrelated service, ask for a different name, then treat
     the request as brand-new under that different name (Step 3, PII/API gate applies).
   - **No name match** → brand-new app. Go to Step 3.

**Step 2 — Dispatch the confirmed rebuild.**
- If `<path>` is known: prefer `$TK add "<path>" "[name]"` (the existing rebuild path `tk add`
  itself provides). This path currently has zero test coverage in `scripts/tests/` — treat it with
  the same manual scrutiny you'd give any untested script change; verify the container actually
  picks up the newly built image afterward.
- If `<path>` is NOT known (a name-only rebuild trigger, e.g. "the api service changed, redeploy
  it"): dispatch `docker compose --project-directory "$TRAEFIK_DIR" up -d --build "<name>"` directly
  — a single command, never a separate `build` followed by `$TK restart` (`tk`'s `restart` only
  restarts the existing container in place; it does not recreate it from a freshly built image, so
  that sequence would silently leave the rebuild unapplied).
- **Never pass `--port`/`--domain`/`--harden` on either rebuild branch** — `connect-service.sh`
  silently ignores them for an already-existing service name and proceeds straight to build/up using
  the stale existing compose block. A real config change requires `tk remove` then a fresh `tk add`,
  not a rebuild.
- Sudo pre-flight: the raw `docker compose up -d --build` bypass never touches `/etc/hosts`, skip
  the pre-flight for it. The `$TK add <path> [name]` branch does touch `/etc/hosts` like any other
  `tk add` call — run the sudo pre-flight for it as usual.

**Step 3 — New-app PII/API gate (mandatory, hard stop).**
Ask the user (or infer from the repo, mirroring `traefik-onboard`'s own Phase 0):
- Does the app hold PII or sensitive data?
- Does it expose any `/api`/data route?

- **Verified "no" to both** → clear to dispatch `$TK add "<path>" "[name]" [--port P] [--domain D] [--no-docker] [--harden] [--dry-run]` directly. Recommend `--dry-run` first if the user hasn't previewed this before. Run the sudo pre-flight first (skip it only if `--dry-run` is present — `connect-service.sh`'s `/etc/hosts` write is guarded by `if [ "$DRY_RUN" = false ]`, so a dry run never touches sudo).
- **Yes, or unknown/unverified** → **do not dispatch `tk add`, `connect-service.sh`, or anything else this turn.** Tell the user in chat that this needs `traefik-onboard`'s mandatory hardening/token gate and won't proceed here; they should re-invoke with `traefik-onboard`'s own trigger phrase (e.g. "add my X app to traefik"), carrying forward the `<path>` already identified so its own detection isn't repeated from scratch.

---

## Remove handling

`remove` is destructive: it takes down and restarts the whole stack.
1. **Chat-confirm first.** State exactly what will happen: the service is removed from
   `docker-compose.yml`, the full stack does `docker compose down` then `up -d`, and there's an
   *attempt* to remove the corresponding `/etc/hosts` entry — get an explicit go-ahead before running
   anything.
2. Run the sudo pre-flight (below) — `remove` writes `/etc/hosts`.
3. Dispatch: `CONFIRM_DESTRUCTIVE=false $TK remove <name>`. The `CONFIRM_DESTRUCTIVE=false` is
   required — without it, `tk`'s own internal `confirm_destructive` prompt reads from stdin, hits EOF
   under a non-interactive shell, and `cmd_remove` silently exits 0 having removed nothing. The chat
   confirmation in step 1 is the only gate that should apply here.
4. **Don't claim hosts-cleanup succeeded.** `cmd_remove`'s domain lookup (`get_service_domain`,
   `scripts/lib/tk-docker.sh:48-57`) greps a fixed 20-line window past the service block and returns
   the *first* `Host()` match — this is empty for services whose rule line falls outside that
   window, and returns the wrong (secondary `.home.local`) domain when a rule has two OR'd `Host()`
   clauses. After running, tell the user hosts-cleanup isn't guaranteed and they may want to manually
   check/clean `/etc/hosts` for the removed service's domain(s) — don't state "`/etc/hosts` entry
   removed" as a confirmed fact.

---

## Cleanup handling

`cleanup.sh` unconditionally asks two `read -p ... -n 1 -r` questions (remove certs? remove `.env`?)
with no non-interactive override. Dispatching blindly hangs waiting on stdin.

1. Ask the user directly in chat: "This stops all containers, removes the `traefik` network and
   volumes (data loss), and optionally deletes `certs/` and `.env` — which of those two do you want
   removed, if any?"
2. If the user declines to answer or intent is ambiguous, default both to `n` (least destructive).
3. Pipe the corresponding y/n pair into the script's stdin **with no newline between the two
   answers**, and **always `cd` into `$TRAEFIK_DIR` first** (`cleanup.sh` has no `cd` of its own and
   uses relative paths):
   ```bash
   cd "$TRAEFIK_DIR" && printf '%s%s' "<certs-answer:y|n>" "<env-answer:y|n>" | "$TRAEFIK_DIR/scripts/cleanup.sh"
   ```
   The script reads both prompts with `read -p "..." -n 1 -r`, which consumes exactly one byte and
   does *not* consume a trailing newline — piping `'%s\n%s\n'` leaves the first answer's `\n`
   unconsumed, so the second `read` eats that leftover newline instead of the second answer (verified
   empirically: the second response comes back empty). `'%s%s'` with no separator avoids this.

---

## Sudo pre-flight (add / remove / sync-hosts)

`add`, `remove`, and `sync-hosts` all shell out to `sudo tee`/`sudo sed` against `/etc/hosts`. Before
dispatching any of these three, run:
```bash
sudo -n true 2>/dev/null
```
- Succeeds (exit 0) → sudo timestamp is warm, proceed with the dispatch normally.
- Fails → do not run the real command blind. Tell the user: "this needs your sudo password — run
  `sudo -v` in a terminal first, then ask me again."

**Exceptions (skip the pre-flight entirely):** `add --dry-run` (never touches sudo — guarded by
`if [ "$DRY_RUN" = false ]` in `connect-service.sh`), and `add`'s rebuild raw-bypass branch
(`docker compose ... up -d --build "<name>"` — read/build-only, never touches `/etc/hosts`).

**Caveat:** this assumes `sudo -n true` reads the same sudo timestamp the user's own `sudo -v` (run
in their terminal) warms up. `sudo`'s `tty_tickets` setting can scope timestamps per-tty — if that
turns out not to hold in practice, fall back to a narrowly-scoped `NOPASSWD` sudoers entry limited to
the exact `tee`/`sed` invocations these three commands need (never a blanket `NOPASSWD: ALL`).

---

## URL derivation (status / list / setup)

`cmd_status`/`cmd_list` don't print the real `Host(...)` rule — they synthesize
`https://<service>.internal` textually from the service name, which is wrong for a service connected
with a custom `--domain`. Instead, derive URLs by running
`docker compose --project-directory "$TRAEFIK_DIR" config` and reading each service's resolved
`traefik.http.routers.*.rule` label from that output — **never grep the raw `docker-compose.yml`**,
since real labels there look like `` Host(`${PYTHON_SERVICE_DOMAIN:-api.internal}`) || Host(`api.home.local`) ``
(unresolved `${VAR:-default}` plus two OR'd `Host()` clauses); `docker compose config` fully resolves
this server-side.

- **Tie-break:** when a resolved rule has multiple `Host()` clauses, present the `.internal` one as
  the primary URL and any `.home.local` (or other) alternative as a secondary alias.
- **Router-key rule:** match the router nested under each service's own `.labels` block — don't
  assume the router name equals the service name (e.g. the `traefik` service's own router is named
  `dashboard`, not `traefik`).
- A service with `traefik.enable: "false"` and no router label (e.g. `mongodb`) has no URL — skip it
  silently rather than showing an error.

`tk setup`'s final URL listing should use this same derivation, for **all** currently-configured
services, not a hardcoded subset.

---

## Output presentation

`tk`'s own output is built for a terminal — ANSI color codes, `╔═╗`-box headers, emoji bullets. Piped
into a chat transcript, none of that renders as intended. **Re-present results as clean markdown; do
not paste raw `tk` stdout into chat.** The user should never see a `\033[` or a `═` in the
conversation. If a raw dump is genuinely useful (the user explicitly asks "show me exactly what tk
printed"), that's a deliberate exception, not the default.

| Command | Present as |
|---|---|
| `status` | A markdown table: `Service \| Running \| URL` (URLs per **URL derivation** above). |
| `list` | A markdown bullet list, one service per line, each with its derived URL. |
| `add` | A short summary block: Service, Language, Framework, Port, Domain, Mode — then the resulting URL, and if `--harden`, the token line called out with a **bold warning** that the app must still enforce it. For the rebuild raw-bypass branch (a full Docker BuildKit transcript), strip ANSI and condense to a short pass/fail summary (image built, container recreated, new status) — never a full build-log dump. |
| `logs` | A fenced code block with ANSI stripped. If it contains `error`/`ERROR`/traceback markers, call them out above the block before showing it. |
| `remove` / `cleanup` | A before/after summary: what was confirmed, what actually changed. For `remove`, phrase hosts-cleanup as "attempted (accuracy not guaranteed — see a manual `/etc/hosts` check if the domain still resolves)", never as a confirmed fact. |
| `setup` | A checklist summary (`✓ certs generated`, `✓ network ready`, `✓ stack up`) plus the final URL list — condensed, not replayed line-by-line. |
| errors (any command) | Plain-language restatement of the failure + one concrete next step, not the raw stderr dump. |
| `start`/`stop`/`restart`/`sync-hosts`/`version`/`help` | Strip ANSI/box-drawing and present the remaining plain text directly. For `sync-hosts`, additionally sanity-check for template-derived entries per the dispatch table note above. |

Presentation-only ANSI stripping may use an inline shell pipe within a dispatch command (e.g.
`sed -E 's/\x1b\[[0-9;]*m//g'`) — this is not business logic and not a bundled file, so it doesn't
violate this skill's zero-code-files rule below.

---

## Non-goals

- Not a rewrite of `tk` itself beyond restoring `setup.sh`.
- Not covering `add-service.sh` (dead code), `merge-to-main.sh`, `run-tests.sh`,
  `install.sh`/`uninstall.sh`, `setup-commit-signing.sh`, or `scripts/setup-dns.sh` (machine-level
  DNS is a one-time, out-of-repo concern).
- Not `traefik-onboard`'s job — that skill owns hardened per-app onboarding end to end. This skill
  is the general-purpose front door to every other `tk` command, plus rebuilds of already-onboarded
  services.
- This package contains no bundled code — no `.sh` files, no templates, nothing beyond this
  `SKILL.md`. Every dispatch above calls the existing, tested `tk`/`connect-service.sh`/
  `cleanup.sh`/`setup.sh`/`docker compose` directly.
