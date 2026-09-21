#!/usr/bin/env python3
"""Read-only, bounded Compose inspection. Never emit resolved environments."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import fcntl
import json
import ipaddress
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import urlsplit


class InspectionError(Exception):
    def __init__(self, message, code="command_failed"):
        super().__init__(message)
        self.code = code


class Parser(argparse.ArgumentParser):
    def error(self, message):
        if self.json_errors:
            print(json.dumps({"schema_version": 1, "ok": False, "services": [], "checks": [],
                              "error": {"code": "invalid_arguments", "message": "Invalid arguments; use tk COMMAND --help."}}))
            self.exit(2)
        super().error(message)


def acquire_project_lock(root):
    """Keep the descriptor open until the entire mutation/readiness phase ends."""
    directory = root / ".tk"
    directory.mkdir(mode=0o700, exist_ok=True)
    descriptor = os.open(directory / "operation.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    handle = os.fdopen(descriptor, "a")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        raise InspectionError("Another tk mutation is in progress for this checkout. Inspect status and retry after it finishes.",
                              "operation_in_progress") from None
    return handle


def run(command, cwd, timeout=15):
    try:
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                                timeout=timeout, stdin=subprocess.DEVNULL)
    except FileNotFoundError:
        raise InspectionError(f"Required executable not found: {Path(command[0]).name}", "executable_missing") from None
    except subprocess.TimeoutExpired:
        raise InspectionError(f"{Path(command[0]).name} timed out after {timeout}s", "command_timeout") from None
    if result.returncode:
        # Compose errors can contain interpolated secrets. Do not relay stderr.
        raise InspectionError(f"{Path(command[0]).name} command failed (exit {result.returncode})")
    return result.stdout


def parse_json(text):
    try:
        return json.loads(text)
    except (ValueError, TypeError):
        raise InspectionError("Command returned invalid JSON", "invalid_response") from None


def compose_command(root):
    command = ["docker", "compose", "--project-directory", str(root)]
    if os.environ.get("DOCKER_COMPOSE_FILE"):
        command += ["-f", os.environ["DOCKER_COMPOSE_FILE"]]
    return command


def load_config(root):
    config = parse_json(run(compose_command(root) + ["config", "--format", "json"], root))
    if not isinstance(config, dict) or not isinstance(config.get("services"), dict):
        raise InspectionError("Compose configuration has no services mapping", "invalid_config")
    return config


def select_config(config, service):
    if not service:
        return config
    if service not in config["services"]:
        # Only echo known configuration names, never arbitrary input.
        aliases = [name for name, item in config["services"].items() if item.get("container_name") == service]
        hint = f" Use Compose service: {', '.join(aliases)}." if aliases else " Use tk list --json for valid service names."
        raise InspectionError("Unknown Compose service." + hint, "unknown_service")
    selected = config["services"][service]
    networks = selected.get("networks", {})
    return dict(config, services={service: selected},
                networks={name: network for name, network in config.get("networks", {}).items() if name in networks})


def parse_containers(text):
    if not text.strip():
        return []
    try:
        rows = json.loads(text)
    except ValueError:
        rows = [parse_json(line) for line in text.splitlines() if line.strip()]
    if isinstance(rows, dict):
        rows = [rows]
    if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
        raise InspectionError("Unexpected Compose status format")
    return rows


def labels_of(service):
    labels = service.get("labels") or {}
    if isinstance(labels, list):
        return dict(item.split("=", 1) for item in labels if "=" in item)
    return labels


def service_urls(service):
    labels = labels_of(service)
    if str(labels.get("traefik.enable", "false")).lower() != "true":
        return []
    urls = set()
    for key, rule in labels.items():
        if not key.startswith("traefik.http.routers.") or not key.endswith(".rule"):
            continue
        prefix = key[:-len("rule")]
        tls = str(labels.get(prefix + "tls", "")).lower() == "true"
        secure_entrypoint = "websecure" in str(labels.get(prefix + "entrypoints", "")).split(",")
        scheme = "https" if tls or secure_entrypoint else "http"
        # Ignore HostRegexp and negated Host matches: neither supplies a URL.
        for match in re.finditer(r"(?<![\w!])\bHost\s*\(([^)]*)\)", str(rule)):
            if str(rule)[:match.start()].rstrip().endswith("!"):
                continue
            for _, host in re.findall(r'([`"])([^`"]+)\1', match.group(1)):
                if re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?", host):
                    urls.add(f"{scheme}://{host.lower()}")
    return sorted(urls, key=lambda url: (not url.endswith(".internal"), url))


def service_rows(config, containers=None):
    rows = []
    for name, service in sorted(config.get("services", {}).items()):
        row = {"service": name, "urls": service_urls(service)}
        if containers is not None:
            matches = [item for item in containers if item.get("Service") == name]
            row["containers"] = [
                {"name": item.get("Name", ""), "state": item.get("State", "unknown"),
                 "health": item.get("Health", "")}
                for item in matches
            ]
            row["expected_replicas"] = service.get("scale", service.get("deploy", {}).get("replicas", 1))
            row["ready"] = len(matches) >= row["expected_replicas"] and all(
                item.get("State") == "running" and item.get("Health", "") in ("", "healthy")
                for item in matches
            )
            row["profiles"] = service.get("profiles", [])
        rows.append(row)
    return rows


def check(name, state, message):
    return {"check": name, "status": state, "message": message}


def probe(url, root, ca_file=None, resolve_address=None):
    command = ["curl", "--silent", "--noproxy", "*", "--connect-timeout", "3",
               "--max-time", "8", "--output", os.devnull, "--write-out", "%{http_code}"]
    if ca_file:
        command += ["--cacert", str(ca_file)]
    if resolve_address:
        parsed = urlsplit(url)
        address = f"[{resolve_address}]" if ":" in resolve_address else resolve_address
        command += ["--resolve", f"{parsed.hostname}:{parsed.port or (443 if parsed.scheme == 'https' else 80)}:{address}"]
    try:
        code = run(command + [url + "/"], root, timeout=10).strip()
        good = code.isdigit() and (200 <= int(code) < 400 or code in ("401", "403"))
        detail = "; DNS bypassed by explicit --resolve-address" if resolve_address else ""
        return check(url, "ok" if good else "fail", f"HTTP {code}; TLS verified for HTTPS{detail}")
    except InspectionError as exc:
        return check(url, "fail", f"{exc}; check DNS, TLS trust and route availability")


def doctor_checks(config, services, containers, root, args):
    checks = [check("compose", "ok", "Compose configuration is valid")]
    for row in services:
        inactive_profile = row["profiles"] and not row["containers"] and not args.service
        state = "skip" if inactive_profile else "ok" if row["ready"] else "fail"
        message = "Inactive optional profile" if inactive_profile else "Running" if row["ready"] else "Missing, stopped, starting or unhealthy"
        checks.append(check("service:" + row["service"], state, message))
    for name, network in config.get("networks", {}).items():
        if network.get("external"):
            try:
                run(["docker", "network", "inspect", network.get("name", name), "--format", "{{.Name}}"], root)
                checks.append(check("network:" + name, "ok", "External network exists"))
            except InspectionError as exc:
                checks.append(check("network:" + name, "fail", str(exc)))
    for name, service in config.get("services", {}).items():
        build = service.get("build", {})
        context = build.get("context", "") if isinstance(build, dict) else build
        if context and not re.match(r"[a-z]+://|git@", context):
            exists = (root / context).is_dir()
            checks.append(check("build:" + name, "ok" if exists else "fail", "Build context exists" if exists else "Build context is missing"))
        # Check mount existence without reading data, keys or tokens.
        for mount in service.get("volumes", []):
            if isinstance(mount, dict) and mount.get("type") == "bind":
                target = mount.get("target", "")
                if target == "/var/run/docker.sock":
                    continue  # Docker Desktop resolves this inside its VM.
                exists = (root / mount["source"]).exists()
                checks.append(check(f"mount:{name}:{target}", "ok" if exists else "fail",
                                    "Bind source exists" if exists else "Bind source is missing"))
        image = service.get("image", "")
        if image and (image.endswith(":latest") or (":" not in image.rsplit("/", 1)[-1] and "@" not in image)):
            checks.append(check("image:" + name, "warn", "Floating image tag; pin a tested version before pulling"))
    for container in containers:
        if container.get("Service") not in config.get("services", {}):
            checks.append(check("orphan:" + container.get("Service", "unknown"), "warn",
                                "Container is outside current Compose configuration; review separately"))
    if args.probe:
        urls = sorted({url for row in services for url in row["urls"]})
        if not urls:
            checks.append(check("routes", "warn", "No literal Host routes to probe"))
        with ThreadPoolExecutor(max_workers=4) as pool:
            checks.extend(pool.map(lambda url: probe(url, root, args.ca_file, args.resolve_address), urls))
    if args.memory_hub:
        try:
            state = parse_json(run([str(args.memory_hub.resolve() / "bin/memory-hub"), "doctor"], root))
            ready = state.get("ready") is True and state.get("mode") == "live" and state.get("codex_enabled") is True
            checks.append(check("local-memory", "ok" if ready else "fail",
                                "Live hub ready; Codex enabled" if ready else "Hub is not ready for live Codex memory"))
        except InspectionError as exc:
            checks.append(check("local-memory", "fail", str(exc)))
    return checks


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    parser = Parser(description=__doc__)
    parser.json_errors = "--json" in argv
    parser.add_argument("--project-directory", type=Path, required=True)
    parser.add_argument("command", choices=["list", "ls", "status", "ps", "doctor"])
    parser.add_argument("service", nargs="?", help="Limit inspection to one exact Compose service name")
    parser.add_argument("--json", action="store_true", help="Emit one JSON document without secrets or ANSI")
    parser.add_argument("--probe", action="store_true", help="Doctor: GET each routed origin with TLS verification")
    parser.add_argument("--ca-file", type=Path, help="Doctor: explicit CA bundle for route probes")
    parser.add_argument("--resolve-address", help="Doctor: probe a specific IP while retaining Host, SNI and TLS checks (bypasses DNS)")
    parser.add_argument("--memory-hub", type=Path, help="Doctor: also check this local-memory checkout")
    args = parser.parse_args(argv)
    if args.command != "doctor" and (args.probe or args.ca_file or args.memory_hub or args.resolve_address):
        parser.error("Probe and memory options require doctor")
    if (args.ca_file or args.resolve_address) and not args.probe:
        parser.error("--ca-file and --resolve-address require --probe")
    if args.resolve_address:
        try:
            args.resolve_address = str(ipaddress.ip_address(args.resolve_address))
        except ValueError:
            parser.error("--resolve-address must be an IPv4 or IPv6 address")
    root = args.project_directory.resolve()
    report = {"schema_version": 1, "command": args.command, "ok": False, "services": [], "checks": []}
    try:
        # Respect Compose's normal .env, override files and COMPOSE_FILE behavior.
        compose = compose_command(root)
        full_config = load_config(root)
        config = select_config(full_config, args.service)
        report["services"] = service_rows(config)
        report["project"] = config.get("name", root.name)
        if args.command in ("list", "ls"):
            report["ok"] = True
        else:
            containers = parse_containers(run(compose + ["ps", "--all", "--format", "json"], root))
            report["services"] = service_rows(config, containers)
            report["orphans"] = sorted({row.get("Service", "unknown") for row in containers
                                         if row.get("Service") not in full_config["services"]})
            report["ok"] = True  # status success means inspection succeeded, not that all services are healthy.
            if args.command == "doctor":
                checked_containers = [c for c in containers if c.get("Service") == args.service] if args.service else containers
                report["checks"] = doctor_checks(config, report["services"], checked_containers, root, args)
                report["ok"] = not any(item["status"] == "fail" for item in report["checks"])
    except (InspectionError, OSError) as exc:
        message = str(exc) if isinstance(exc, InspectionError) else "Cannot access the requested project or executable"
        report["error"] = {"code": getattr(exc, "code", "io_error"), "message": message}
        report["checks"].append(check("inspection", "fail", message + "; verify Docker access and run docker compose config --quiet locally"))
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print("Traefik Services" if args.command in ("list", "ls") else "Service Status" if args.command in ("status", "ps") else "Traefik Doctor")
        for row in report["services"]:
            states = ", ".join(item["state"] + ("/" + item["health"] if item["health"] else "") for item in row.get("containers", []))
            if "containers" in row:
                states = states or "not created"
            print(f"  {row['service']:<20} {states:<24} {', '.join(row['urls']) or '(no HTTP route)'}")
        for item in report["checks"]:
            print(f"  {item['status'].upper():<5} {item['check']}: {item['message']}")
        if report.get("orphans"):
            print("  Containers outside Compose: " + ", ".join(report["orphans"]))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
