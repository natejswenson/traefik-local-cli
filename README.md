# Traefik Local CLI (`tk`)

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
- **Wildcard `*.internal`** — new apps need no cert or DNS change once the stack is set up

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
tk start | stop | restart [service]     # lifecycle
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
