#!/usr/bin/env python3
"""Preview-first removal of one Compose service, preserving other services and volumes."""

import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import time
import uuid

SPEC = importlib.util.spec_from_file_location("tk_operations", Path(__file__).with_name("tk-operations.py"))
operations = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(operations)
inspect = operations.inspect
Error = operations.OperationError


def source_file(root, compose):
    # Compose can obtain COMPOSE_FILE from .env. Inspect it in memory only.
    environment = inspect.run(compose + ["config", "--environment"], root)
    settings = dict(line.split("=", 1) for line in environment.splitlines() if "=" in line)
    configured = os.environ.get("DOCKER_COMPOSE_FILE") or settings.get("COMPOSE_FILE")
    if configured:
        separator = settings.get("COMPOSE_PATH_SEPARATOR") or os.pathsep
        files = configured.split(separator)
        if len(files) != 1 or files[0] == "-":
            raise Error("unsupported_compose_source", "Removal supports one local Compose file; edit multi-file configurations explicitly.")
        source = root / files[0]
    else:
        candidates = [root / name for name in ("compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml")
                      if (root / name).exists()]
        overrides = [root / name for name in ("compose.override.yaml", "compose.override.yml",
                                             "docker-compose.override.yaml", "docker-compose.override.yml")]
        if len(candidates) != 1 or any(path.exists() for path in overrides):
            raise Error("unsupported_compose_source", "Removal needs one unambiguous Compose file without automatic overrides.")
        source = candidates[0]
    if source.is_symlink() or not source.is_file() or root not in source.resolve().parents:
        raise Error("unsupported_compose_source", "The Compose source must be a regular file inside this checkout.")
    return source.resolve()


def remove_block(raw, service):
    """Conservative text edit; Compose subsequently proves the semantic change."""
    try:
        lines = raw.decode("utf-8").splitlines(keepends=True)
    except UnicodeDecodeError:
        raise Error("unsupported_yaml", "Compose source must be UTF-8 block-style YAML.") from None
    sections = [i for i, line in enumerate(lines) if re.fullmatch(r"services:[ \t]*(?:#[^\r\n]*)?\r?\n?", line)]
    if len(sections) != 1:
        raise Error("unsupported_yaml", "Removal needs a single top-level services mapping in block-style YAML.")
    begin = sections[0] + 1
    end = next((i for i in range(begin, len(lines)) if re.match(r"[^\s#]", lines[i])), len(lines))
    headers = []
    for i in range(begin, end):
        match = re.match(r"^( +)(['\"]?)([A-Za-z0-9][A-Za-z0-9_.-]*)\2:", lines[i])
        if match:
            headers.append((i, len(match[1]), match[3]))
    if not headers:
        raise Error("unsupported_yaml", "Cannot identify service blocks without rewriting the source.")
    indentation = min(item[1] for item in headers)
    targets = [item[0] for item in headers if item[1:] == (indentation, service)]
    if len(targets) != 1:
        raise Error("unsupported_yaml", "The selected service must have one explicit block in this Compose file.")
    start = targets[0]
    stop = next((i for i in range(start + 1, end)
                 if lines[i].strip() and not lines[i].lstrip().startswith("#")
                 and len(lines[i]) - len(lines[i].lstrip(" ")) <= indentation), end)
    # Keep separator comments/whitespace that may describe the following service.
    while stop > start + 1 and (not lines[stop - 1].strip() or lines[stop - 1].lstrip().startswith("#")):
        stop -= 1
    return "".join(lines[:start] + lines[stop:]).encode("utf-8")


def dependents(config, target):
    found = []
    for name, service in config["services"].items():
        if name == target:
            continue
        referenced = target in operations.dependencies(service)
        referenced |= any(service.get(key) == "service:" + target for key in ("network_mode", "ipc", "pid"))
        referenced |= any(item.split(":", 1)[0] == target for key in ("links", "volumes_from") for item in service.get(key, []))
        if referenced:
            found.append(name)
    return sorted(found)


def validate_change(original, candidate, target):
    expected = copy.deepcopy(original)
    del expected["services"][target]
    # Compose prunes unused resource definitions; permit only that pruning.
    for key in ("networks", "volumes", "secrets", "configs"):
        if key in expected:
            expected[key] = {name: value for name, value in expected[key].items() if name in candidate.get(key, {})}
            if not expected[key] and key not in candidate:
                del expected[key]
    if candidate != expected:
        raise Error("unexpected_config_change", "Candidate changes more than the selected service. Source was not edited.")


def explicit_compose(root, source):
    return ["docker", "compose", "--project-directory", str(root), "-f", str(source)]


def read_config(root, source):
    return inspect.parse_json(inspect.run(explicit_compose(root, source) + ["config", "--format", "json"], root))


def verify_current(root, source, raw, config):
    if source.read_bytes() != raw or inspect.load_config(root) != config:
        raise Error("config_changed", "Compose configuration changed during removal. Preserve the current file and plan again.")


def atomic_write(source, candidate):
    descriptor, name = tempfile.mkstemp(prefix=".tk-remove-", suffix=".tmp", dir=source.parent)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(candidate)
            handle.flush()
            os.fsync(handle.fileno())
            os.fchmod(handle.fileno(), stat.S_IMODE(source.stat().st_mode))
        os.replace(name, source)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    report = {"schema_version": 1, "command": "remove", "ok": False, "state": "not_started",
              "changed": False, "config_changed": False, "services": []}
    project_lock = None
    mutation_started = False
    exit_code = 0
    try:
        parser = operations.Parser(prog="tk remove", description=__doc__)
        parser.add_argument("--project-directory", type=Path, required=True, help=argparse.SUPPRESS)
        parser.add_argument("command", choices=["remove", "rm"])
        parser.add_argument("service", help="One exact Compose service name")
        parser.add_argument("--json", action="store_true")
        mode = parser.add_mutually_exclusive_group()
        mode.add_argument("--dry-run", action="store_true", help="Preview only (the default)")
        mode.add_argument("--apply", action="store_true", help="Remove selected containers and edit Compose after validation")
        parser.add_argument("--timeout", type=operations.positive_int, default=120, help="Container removal deadline in seconds (default 120)")
        args = parser.parse_args(argv)
        root = args.project_directory.resolve()
        compose = inspect.compose_command(root)
        config = inspect.load_config(root)
        selected = inspect.select_config(config, args.service)
        report.update(project=config.get("name", root.name), targets=[args.service], affected_services=[args.service],
                      services=inspect.service_rows(selected))
        blocked = dependents(config, args.service)
        if blocked:
            report["dependent_services"] = blocked
            raise Error("dependent_services", "Other services reference this service. Update those dependencies before removal.")
        if len(config["services"]) == 1:
            raise Error("last_service", "Use stop for the final service; removing the entire configuration requires an explicit manual edit.")
        source = source_file(root, compose)
        if read_config(root, source) != config:
            raise Error("unsupported_compose_source", "The selected file does not reproduce the active Compose configuration.")
        raw = source.read_bytes()
        candidate = remove_block(raw, args.service)
        with tempfile.TemporaryDirectory(prefix="tk-remove-plan-") as directory:
            temporary = Path(directory) / "compose.yaml"
            temporary.touch(mode=0o600)
            temporary.write_bytes(candidate)
            validate_change(config, read_config(root, temporary), args.service)
            action = explicit_compose(root, source) + ["rm", "--stop", "--force", args.service]
            report["plan"] = {"argv": action, "compose_file": str(source), "remove_service": args.service,
                              "preserve_volumes": True, "preserve_source_directory": True, "hosts_file_changed": False,
                              "container_writable_layer_removed": True}
            report["note"] = "Removes the selected containers and Compose block. Volumes and app source remain; container-only data is lost. Host entries remain for manual review."
            if args.apply:
                project_lock = inspect.acquire_project_lock(root)
                verify_current(root, source, raw, config)
                validate_change(config, read_config(root, temporary), args.service)
                # Check daemon access before creating a backup or attempting removal.
                inspect.run(compose + ["ps", "--all", "--format", "json"], root)
                backups = root / ".tk" / "backups"
                backups.mkdir(mode=0o700, exist_ok=True)
                backup = backups / (uuid.uuid4().hex + "-" + source.name)
                with backup.open("xb") as handle:
                    os.fchmod(handle.fileno(), 0o600)
                    handle.write(raw)
                report["backup"] = str(backup)
                mutation_started = True
                report["changed"] = None
                deadline = time.monotonic() + args.timeout
                inspect.run(action, root, timeout=args.timeout)
                containers = inspect.parse_containers(inspect.run(compose + ["ps", "--all", "--format", "json"], root,
                                                                  timeout=max(0.01, min(15, deadline - time.monotonic()))))
                if any(row.get("Service") == args.service for row in containers):
                    raise Error("removal_incomplete", "Selected containers remain. Compose source has been retained; inspect status before retrying.")
                report["changed"] = True
                report["state"] = "containers_removed"
                verify_current(root, source, raw, config)
                atomic_write(source, candidate)
                report.update(config_changed=True, state="removed", ok=True)
            else:
                report.update(ok=True, state="planned")
    except (Error, inspect.InspectionError, OSError) as exc:
        report["error"] = {"code": getattr(exc, "code", "io_error"),
                           "message": "Cannot access a required project file or executable." if isinstance(exc, OSError) else str(exc)}
        if mutation_started:
            report["error"]["next_action"] = "Inspect Docker and the current Compose file before retrying. No automatic rollback occurred; the backup preserves the original source."
        if report["state"] == "not_started":
            report["state"] = "unknown" if mutation_started else "failed"
        exit_code = getattr(exc, "exit_code", 1)
    finally:
        if project_lock is not None:
            project_lock.close()
    if "--json" in argv:
        print(json.dumps(report, indent=2))
    else:
        print("remove: " + report["state"])
        if report.get("targets"):
            print("  Service: " + report["targets"][0])
        if report.get("note"):
            print("  " + report["note"])
        if report["state"] == "planned":
            print("  Preview only. Use --apply to execute this removal.")
        if report.get("backup"):
            print("  Backup: " + report["backup"])
        if report.get("error"):
            print("  " + report["error"]["code"] + ": " + report["error"]["message"])
            if report["error"].get("next_action"):
                print("  " + report["error"]["next_action"])
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
