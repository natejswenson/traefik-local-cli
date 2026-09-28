# Traefik Local CLI (`tk`)

## Agent inspection and diagnostics

`tk capabilities --json` reports the agent protocol, commands and feature flags
without reading Compose, contacting Docker or sourcing `.tkrc`. Separately
installed skills can check compatibility before operating a stack.

The shared Codex/Claude operations skill is maintained in
[claude-skills/traefik](https://github.com/natejswenson/claude-skills/tree/main/skills/traefik)
and installed as `traefik@claude-skills`. It uses this CLI as an external dependency;
updating a skill never copies or updates the CLI, Compose files or private state.
The bundled `.claude/skills/tk` is a legacy entrypoint for existing installations;
prefer the shared plugin for new installations. The stack-specific
`traefik-onboard` workflow remains here.

`tk list --json` reports resolved routes; `tk status --json` adds container health.
`tk doctor --probe --json` verifies readiness and HTTPS. Use
`tk doctor --memory-hub /path/to/local-memory --json` for optional live hub readiness.
`tk logs SERVICE --tail 100` returns a bounded snapshot; pass `--follow` to stream.
Inspection is read-only, does not source `.tkrc`, redacts Compose errors and has
bounded command timeouts. Export `COMPOSE_FILE` or `DOCKER_COMPOSE_FILE` when needed.
`status` exit 0 means inspection succeeded; `doctor` exits 1 on failed checks.

`refresh-certs.sh` preserves wildcard names and adds concrete routed hosts for
macOS TLS clients. Reload Traefik afterward. `setup-dns.sh --check` inspects DNS;
`--apply` repairs macOS resolver files with administrator authentication.
The parent stack provides Codex's `.agents/skills/traefik` and `AGENTS.md`.
Run `./run-tests.sh` for Python regression tests plus the existing Bats suites.

## Agent service operations

Use exact Compose service names, available from `tk list --json`:

```bash
tk inspect my-api --json                     # build context, dependencies and URLs
tk rebuild my-api --dry-run --json           # preview scope; no daemon changes
tk rebuild my-api --json                     # build, recreate and wait for readiness
tk wait my-api --timeout 30 --json            # read-only, bounded readiness check
tk doctor my-api --probe --json              # verify the affected HTTPS routes
tk start --all --json                        # explicitly start the whole configuration
```

`start`, `stop`, `restart`, `rebuild`, `inspect` and `wait` require a service or
`--all`; missing/extra targets are errors. Lifecycle commands support `--dry-run`
and return structured errors with `--json`. Start/rebuild exclude dependencies
and verify them before applying; `--with-deps` explicitly permits dependency startup.
Restart does not install a rebuilt image. Operations wait for running/healthy
containers (stopped for `stop`); configured replica counts must be met. Use doctor
for separate DNS/TLS verification. Timeouts default to 120 seconds, rebuild 600.
Exit codes: 0 success, 1 runtime failure, 2 usage, 3 readiness deadline.

A preview returns `state: planned` and `changed: false`. After successful Compose
execution, `changed: true` means the action was accepted. On a failed/timed-out
action, `changed: null` means partial effects are possible: inspect status before
retrying. No automatic action retry or rollback occurs. Structured lifecycle
commands, like inspection, do not execute `.tkrc`; use exported Compose settings.

## Scoped removal

`tk remove SERVICE --json` previews by default. Add `--apply` for an authorized
removal of only that service's containers and Compose block. Other containers,
volumes and app source remain; data stored only inside the removed container is
lost. The CLI validates the candidate configuration, blocks referenced services,
and saves a mode-600 source backup in ignored `.tk/backups/`. It does not use sudo
or change DNS/hosts. Multi-file/override configurations require explicit manual edits.
On partial failure, inspect `state`, `config_changed`, `error` and `backup` before retrying.

Structured lifecycle/removal mutations hold a per-checkout lock. Concurrent writes
return `operation_in_progress`; read-only commands and previews remain available.
The lock is released automatically on process exit. Raw Docker and older onboarding
scripts do not participate. Never delete an active lock file to bypass another command.

Optional live test: `python3 tests/smoke_agent_operations.py` from this scripts
checkout. It uses cached `traefik:3.6.5` and a unique disposable Docker project,
verifies the neighboring service and retained volume, then cleans its fixture only.



[![CI](https://github.com/natejswenson/traefik-local-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/natejswenson/traefik-local-cli/actions/workflows/ci.yml)
[![Shell: Bash](https://img.shields.io/badge/shell-bash-89e051.svg)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](#license)

Onboard any local app to a Traefik reverse proxy at `https://<app>.internal` — with production
hardening — by telling Claude **"add my X app to traefik"**.

The headline feature is the bundled [Claude Code](https://claude.com/claude-code) skill
**`traefik-onboard`**, which drives the whole onboarding as a deterministic procedure with hard
pass/fail gates. `tk` is the underlying CLI it (and you) call.

## Features

- **`traefik-onboard` skill** — gated, hardened onboarding: containerize → wire → deploy → verify
- **Production hardening** — non-root, data kept out of the image, `cap_drop`/`no-new-privileges`, a wired API token
- **App-side security the skill adds** — bearer-token gate, non-loopback bind-refusal, Claude-Agent-SDK isolation
- **Auto-detection** — language, framework, port, and dependencies (Python, Node, static)
- **Local HTTPS** — wildcard DNS plus explicit certificate names for macOS client compatibility

## Installation

```bash
# Clone
git clone https://github.com/natejswenson/traefik-local-cli.git
cd traefik-local-cli

# Add `tk` to your PATH
./install.sh && source ~/.zshrc

# One-time stack setup: certs, Docker network, compose up
tk setup

# Make the Claude skills available outside this repo (optional)
ln -s "$PWD/.claude/skills/traefik-onboard" ~/.claude/skills/traefik-onboard
ln -s "$PWD/.claude/skills/tk" ~/.claude/skills/tk
```

## Usage

### With the Claude skill (recommended)

Just tell Claude:

```
add my ~/projects/notes app to traefik
```

It runs the `traefik-onboard` procedure: detects the stack, asks only the two questions a repo
can't answer (does it hold PII? any routes to keep off the LAN?), writes a hardened container,
installs the app-side token gate, wires it into Traefik, and verifies every gate before declaring
it done. Configure your stack once in `.claude/skills/traefik-onboard/SKILL.md` → *Configure*
(`TRAEFIK_DIR`, `STACK_DNS_IP`).

The **`tk`** skill (`.claude/skills/tk/`) is the general-purpose companion to `traefik-onboard`: it
gives natural-language access to every other `tk` command — `setup`, `status`, `list`, `logs`,
`start`/`stop`/`restart`, `remove`, `cleanup`, `sync-hosts`, `version` — plus rebuilding an
already-onboarded service. It never onboards a brand-new PII/API app itself; that always redirects
to `traefik-onboard`'s mandatory hardening gate.

### With the CLI directly

```bash
tk setup                                # one-time: certs, network, compose up (idempotent)

tk connect ~/projects/my-api --harden   # production-hardened service (non-root, token-wired, no data in image)
tk connect ~/projects/my-api            # dev mode (hot-reload; not for real data)
tk connect ~/projects/my-api --dry-run  # preview without changing anything

tk status                               # service status
tk logs my-api                          # tail logs
tk start my-api --json                  # targeted start and readiness
tk stop my-api --json                   # targeted stop
tk restart my-api --json                # targeted restart
```

> **Note:** `--harden` wires an API token but **cannot enforce it** — a generator can't add auth
> middleware to your app. The `traefik-onboard` skill installs that enforcement for you; if you use
> `tk connect --harden` directly, your app must reject `/api/*` without the bearer token and refuse a
> non-loopback bind without it.

## Example

```bash
$ tk connect ~/projects/notes --harden

  Service Name: notes
  Language:     python
  Framework:    fastapi
  Port:         8000
  Domain:       https://notes.internal
  Mode:         hardened (production)

  🐳 Generating Dockerfile...        ✓  (non-root, data excluded, no --reload)
  📦 Generating compose config...    ✓  (cap_drop ALL, no-new-privileges, wired token)
  🔐 API token — add to .env:
     NOTES_API_TOKEN=ab12…           ⚠ your app must enforce this on /api
  🚀 Starting service...             ✓

  https://notes.internal
```

## Development

```bash
./run-tests.sh            # unit + integration (bats)
./run-tests.sh --unit     # unit only
```

## Project Structure

```
traefik-local-cli/
├── tk                       # main CLI entry point
├── connect-service.sh       # detect → generate → wire → deploy
├── setup.sh                 # one-time stack setup: certs, network, compose up (idempotent)
├── cleanup.sh               # stop stack, optionally remove certs/.env
├── setup-dns.sh             # dnsmasq + resolver setup for *.internal
├── install.sh / uninstall.sh
├── lib/
│   ├── service-detector.sh  # language / framework / port / deps
│   ├── docker-generator.sh  # Dockerfile + compose (dev and --harden)
│   ├── tk-common.sh         # config, dry-run, helpers
│   ├── tk-docker.sh         # compose lifecycle
│   ├── tk-validation.sh     # input validation
│   └── tk-logging.sh        # logging
├── .claude/skills/
│   ├── traefik-onboard/     # hardened per-app onboarding skill
│   └── tk/                  # general-purpose tk command skill
└── tests/                   # bats unit + integration
```

## License

MIT
# Local Kubernetes platform commands

`tk dev`, `tk kube`, `tk app`, `tk service`, `tk agent`, and `tk platform`
delegate to the selected immutable `local-k8s` release. Install that package
with its `scripts/install-platform.py --apply` after reviewing the local plan.
The frontend checks the selector, release inventory, entrypoint hash, and
versioned frontend contract before dispatch. The known 0.2.1 release remains
compatible; future protocol versions require a frontend update. For a source
checkout during development, `TK_PLATFORM_ROOT` explicitly bypasses installed
release verification.

`tk platform frontend-capabilities --json` reports the adapter's supported
package protocol without reading the selected package. The local-k8s deployer
uses it before selecting a candidate release.
