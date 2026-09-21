#!/usr/bin/env python3
"""Bounded, service-scoped Compose operations with machine-readable outcomes."""

import argparse
import importlib.util
import json
from pathlib import Path
import sys
import time

SPEC = importlib.util.spec_from_file_location("tk_inspect", Path(__file__).with_name("tk-inspect.py"))
inspect = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inspect)


class OperationError(Exception):
    def __init__(self, code, message, exit_code=1):
        super().__init__(message)
        self.code = code
        self.exit_code = exit_code


class Parser(argparse.ArgumentParser):
    def error(self, message):
        # Parser errors may contain arbitrary argument values. Keep them out of JSON.
        raise OperationError("invalid_arguments", "Invalid arguments; use tk COMMAND --help.", 2)


def positive_int(value):
    number = int(value)
    if not 1 <= number <= 3600:
        raise ValueError("Timeout must be between 1 and 3600 seconds")
    return number


def dependencies(service):
    deps = service.get("depends_on") or {}
    if isinstance(deps, list):
        return {name: {"condition": "service_started"} for name in deps}
    return deps


def affected_services(config, targets, include_dependencies):
    found = set(targets)
    pending = list(targets) if include_dependencies else []
    while pending:
        for name in dependencies(config["services"][pending.pop()]):
            if name not in found and name in config["services"]:
                found.add(name)
                pending.append(name)
    return sorted(found)


def dependency_failures(config, targets, containers):
    failures = set()
    for target in targets:
        for name, options in dependencies(config["services"][target]).items():
            if name in targets or options.get("required") is False:
                continue
            matches = [row for row in containers if row.get("Service") == name]
            condition = options.get("condition", "service_started")
            if condition == "service_completed_successfully":
                ready = bool(matches) and all(row.get("State") == "exited" and row.get("ExitCode") == 0 for row in matches)
            elif condition == "service_healthy":
                ready = bool(matches) and all(row.get("State") == "running" and row.get("Health") == "healthy" for row in matches)
            else:
                ready = bool(matches) and all(row.get("State") == "running" for row in matches)
            if not ready:
                failures.add(name)
    return sorted(failures)


def snapshot(config, compose, root, timeout):
    containers = inspect.parse_containers(inspect.run(compose + ["ps", "--all", "--format", "json"], root, timeout=timeout))
    return inspect.service_rows(config, containers), containers


def wait_for_state(report, config, compose, root, deadline, stopped=False):
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise OperationError("readiness_timeout", "Deadline reached before the requested service state. Inspect tk status and bounded logs.", 3)
        report["services"], _ = snapshot(config, compose, root, min(15, remaining))
        if stopped:
            ready = all(all(c["state"] in ("exited", "dead") for c in row["containers"]) for row in report["services"])
        else:
            ready = all(row["ready"] for row in report["services"])
        if ready:
            report["state"] = "stopped" if stopped else "ready"
            return
        time.sleep(min(1, max(0, deadline - time.monotonic())))


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    json_output = "--json" in argv
    report = {"schema_version": 1, "ok": False, "state": "not_started", "changed": False, "services": []}
    exit_code = 0
    mutation_started = False
    project_lock = None
    try:
        parser = Parser(prog="tk", description=__doc__)
        parser.add_argument("--project-directory", type=Path, required=True, help=argparse.SUPPRESS)
        parser.add_argument("command", choices=["inspect", "wait", "start", "up", "stop", "down", "restart", "rebuild"])
        parser.add_argument("service", nargs="?", help="Exact Compose service name")
        parser.add_argument("--all", action="store_true", help="Explicitly target every service in the resolved configuration")
        parser.add_argument("--json", action="store_true", help="Emit one JSON result, including failures")
        parser.add_argument("--dry-run", action="store_true", help="Show the action and its scope without contacting the daemon")
        parser.add_argument("--with-deps", action="store_true", help="Start/rebuild: also permit Compose to start dependencies")
        parser.add_argument("--timeout", type=positive_int, help="Action plus readiness deadline in seconds; default 120 (rebuild: 600)")
        args = parser.parse_args(argv)
        command = {"up": "start", "down": "stop"}.get(args.command, args.command)
        report["command"] = command
        if bool(args.service) == args.all:
            raise OperationError("target_required", "Specify one Compose service, or explicitly use --all.", 2)
        if args.with_deps and command not in ("start", "rebuild"):
            raise OperationError("invalid_arguments", "--with-deps requires start or rebuild.", 2)
        if args.dry_run and command in ("inspect", "wait"):
            raise OperationError("invalid_arguments", "--dry-run applies only to start, stop, restart or rebuild.", 2)
        root = args.project_directory.resolve()
        compose = inspect.compose_command(root)
        config = inspect.load_config(root)
        selected = inspect.select_config(config, args.service)
        targets = sorted(selected["services"])
        if not targets:
            raise OperationError("no_services", "No services are selected.", 2)
        report.update(project=config.get("name", root.name), targets=targets, services=inspect.service_rows(selected))
        if command == "inspect":
            for row in report["services"]:
                svc = selected["services"][row["service"]]
                build = svc.get("build") or {}
                row.update(container_name=svc.get("container_name"), image=svc.get("image"),
                           build_context=build.get("context") if isinstance(build, dict) else build,
                           profiles=svc.get("profiles", []),
                           depends_on=[{"service": name, "condition": options.get("condition", "service_started"),
                                        "required": options.get("required", True)}
                                       for name, options in sorted(dependencies(svc).items())])
            report.update(ok=True, state="inspected")
        else:
            timeout = args.timeout or (600 if command == "rebuild" else 120)
            report["timeout_seconds"] = timeout
            affected = affected_services(config, targets, args.with_deps)
            report["affected_services"] = affected
            if command == "rebuild" and any(not selected["services"][name].get("build") for name in targets):
                raise OperationError("no_build_context", "Rebuild requires a configured build context for every selected service.")
            if command in ("start", "rebuild"):
                action = ["up", "--detach"] + (["--build"] if command == "rebuild" else [])
                if not args.with_deps:
                    action += ["--no-deps"]
            elif command == "restart":
                action = ["restart", "--no-deps"]
            else:
                action = ["stop"]
            if command != "wait":
                report["plan"] = {"argv": compose + action + targets,
                                  "readiness": "stopped" if command == "stop" else "running_or_healthy"}
            if args.dry_run:
                report.update(ok=True, state="planned")
                report["note"] = "Preview only; dependency and runtime readiness will be checked when applied."
            else:
                deadline = time.monotonic() + timeout
                if command != "wait":
                    project_lock = inspect.acquire_project_lock(root)
                    if inspect.load_config(root) != config:
                        raise OperationError("config_changed", "Compose configuration changed during planning. Inspect and plan again.")
                    deadline = time.monotonic() + timeout
                    report["services"], containers = snapshot(selected, compose, root, min(15, timeout))
                    if command in ("start", "rebuild") and not args.with_deps:
                        missing = dependency_failures(config, targets, containers)
                        if missing:
                            raise OperationError("dependency_not_ready", "Dependencies are not ready: " + ", ".join(missing) + ". Start them first or use --with-deps.")
                    if command == "restart" and any(not row["containers"] for row in report["services"]):
                        raise OperationError("service_not_created", "A selected service has no container. Use start instead.")
                    mutation_started = True
                    report["changed"] = None  # A timeout/failure may still have changed Docker state.
                    inspect.run(compose + action + targets, root, timeout=max(0.01, deadline - time.monotonic()))
                    report["changed"] = True
                    report["state"] = "applied"
                wait_for_state(report, selected, compose, root, deadline, stopped=command == "stop")
                report["ok"] = True
    except (OperationError, inspect.InspectionError, OSError) as exc:
        code = getattr(exc, "code", "io_error")
        message = str(exc) if not isinstance(exc, OSError) else "Cannot access the project or executable."
        report["error"] = {"code": code, "message": message}
        if mutation_started:
            report["error"]["next_action"] = "Inspect status before retrying; a failed or timed-out action is not rolled back."
        if report["state"] == "not_started":
            report["state"] = "unknown" if mutation_started else "failed"
        exit_code = getattr(exc, "exit_code", 1)
    finally:
        if project_lock is not None:
            project_lock.close()
    if json_output:
        print(json.dumps(report, indent=2))
    else:
        print(f"{report.get('command', 'operation')}: {report['state']}")
        for row in report["services"]:
            print(f"  {row['service']}: {', '.join(row['urls']) or '(no HTTP route)'}")
        if report.get("plan") and report["state"] == "planned":
            print("  Targets: " + ", ".join(report["affected_services"]))
            print("  " + report["note"])
        if report.get("error"):
            print(f"  {report['error']['code']}: {report['error']['message']}")
            if report["error"].get("next_action"):
                print("  " + report["error"]["next_action"])
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
