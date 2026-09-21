"""Offline behavior tests for the agent-facing CLI (no Docker daemon needed)."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("tk_inspect", SCRIPTS / "lib/tk-inspect.py")
inspect = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inspect)


class InspectTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tk-inspect-")
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        self.config = {"name": "fixture", "services": {
            "api": {"environment": {"SECRET": "never-print-this-secret"}, "labels": {
                "traefik.enable": "true",
                "traefik.http.routers.different-name.rule": 'Host(`custom.internal`) || Host("custom.home.local")',
                "traefik.http.routers.different-name.entrypoints": "websecure"}},
            "database": {"labels": {"traefik.enable": "false"}},
        }}
        self.containers = [{"Service": "api", "Name": "api-1", "State": "running", "Health": "healthy"},
                           {"Service": "database", "Name": "db-1", "State": "running", "Health": ""}]
        docker = self.root / "docker"
        docker.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
args=sys.argv[1:]
with Path(os.environ['CALLS']).open('a') as f: f.write(json.dumps(args)+'\\n')
if 'config' in args:
    if os.environ.get('CONFIG_FAIL'):
        print('never-print-this-secret',file=sys.stderr);sys.exit(1)
    print(os.environ['CONFIG'])
elif 'ps' in args:
    if os.environ.get('DAEMON_FAIL'): sys.exit(1)
    print(os.environ['CONTAINERS'])
elif 'logs' in args: print('bounded log snapshot')
elif args[:2] == ['network','inspect']: print('traefik')
else: sys.exit(9)
''')
        docker.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ["PATH"],
                        TK_TEST_MODE="true", CALLS=str(self.root / "calls"))

    def cli(self, *args, extra=None, executable=None):
        env = dict(self.env, CONFIG=json.dumps(self.config), CONTAINERS=json.dumps(self.containers))
        env.update(extra or {})
        return subprocess.run([str(executable or SCRIPTS / "tk"), *args], cwd=self.root,
                              env=env, text=True, capture_output=True, timeout=10)

    def test_list_resolves_custom_router_and_excludes_secrets_and_unrouted_database(self):
        result = self.cli("list", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["services"][0]["urls"], ["https://custom.internal", "https://custom.home.local"])
        self.assertEqual(data["services"][1]["urls"], [])
        self.assertNotIn("SECRET", result.stdout)
        self.assertNotIn("never-print-this-secret", result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")

    def test_status_retains_missing_services_and_orphans(self):
        self.containers = [{"Service": "old", "Name": "old", "State": "restarting"}]
        result = self.cli("status", "--json")
        data = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(data["orphans"], ["old"])
        self.assertFalse(data["services"][0]["ready"])
        self.assertEqual(data["services"][0]["containers"], [])
        self.assertEqual(self.cli("doctor", "--json").returncode, 1)

    def test_unhealthy_replica_cannot_pass_doctor(self):
        self.containers.append({"Service": "api", "Name": "api-2", "State": "running", "Health": "unhealthy"})
        result = self.cli("doctor", "--json")
        self.assertEqual(result.returncode, 1)
        self.assertFalse(json.loads(result.stdout)["services"][0]["ready"])

    def test_daemon_unavailable_keeps_inventory_and_exits_nonzero(self):
        result = self.cli("status", "--json", extra={"DAEMON_FAIL": "1"})
        data = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(data["services"]), 2)
        self.assertFalse(data["ok"])
        self.assertNotIn("containers", data["services"][0])

    def test_failed_config_does_not_leak_stderr(self):
        result = self.cli("list", "--json", extra={"CONFIG_FAIL": "1"})
        self.assertEqual(result.returncode, 1)
        self.assertFalse(json.loads(result.stdout)["ok"])
        self.assertNotIn("never-print-this-secret", result.stdout + result.stderr)

    def test_inspection_never_executes_tkrc(self):
        (self.root / ".tkrc").write_text("touch unexpected-side-effect\necho corrupt-json\n")
        result = self.cli("list", "--json")
        self.assertTrue(json.loads(result.stdout)["ok"])
        self.assertFalse((self.root / "unexpected-side-effect").exists())

    def test_invalid_arguments_return_json_without_echoing_input_or_using_docker(self):
        for args in [("list", "--unexpected", "never-print-this-secret"), ("status", "--probe"),
                     ("doctor", "--probe", "--resolve-address", "never-print-this-secret")]:
            result = self.cli(*args, "--json")
            self.assertEqual(result.returncode, 2)
            self.assertEqual(json.loads(result.stdout)["error"]["code"], "invalid_arguments")
            self.assertEqual(result.stderr, "")
            self.assertNotIn("never-print-this-secret", result.stdout)
        self.assertFalse((self.root / "calls").exists())

    def test_targeted_doctor_checks_only_used_networks_and_requires_selected_profile(self):
        self.config["networks"] = {"unused": {"external": True}}
        self.config["services"]["optional"] = {"profiles": ["demo"]}
        result = self.cli("doctor", "optional", "--json")
        self.assertEqual(result.returncode, 1)
        checks = json.loads(result.stdout)["checks"]
        self.assertFalse(any(check["check"].startswith("network:") for check in checks))
        self.assertTrue(any(check["check"] == "service:optional" and check["status"] == "fail" for check in checks))

    def test_optional_profile_is_skipped_but_started_profile_is_checked(self):
        self.config["services"]["optional"] = {"profiles": ["demo"]}
        result = self.cli("doctor", "--json")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("skip", [item["status"] for item in json.loads(result.stdout)["checks"]])
        self.containers.append({"Service": "optional", "State": "exited"})
        self.assertEqual(self.cli("doctor", "--json").returncode, 1)

    def test_json_array_object_and_json_lines_compose_versions(self):
        for text in (json.dumps(self.containers), "\n".join(json.dumps(row) for row in self.containers)):
            self.assertEqual(inspect.parse_containers(text), self.containers)
        self.assertEqual(inspect.parse_containers(json.dumps(self.containers[0])), [self.containers[0]])
        self.assertEqual(inspect.parse_containers(""), [])
        with self.assertRaises(inspect.InspectionError):
            inspect.parse_containers("[]\nnot-json")

    def test_logs_are_bounded_and_follow_is_explicit(self):
        self.assertEqual(self.cli("logs", "api", "--tail", "25").returncode, 0)
        args = json.loads((self.root / "calls").read_text().splitlines()[-1])
        self.assertEqual(args, ["compose", "logs", "--no-color", "--tail", "200", "api", "--tail", "25"])
        self.assertNotIn("-f", args)
        self.cli("logs", "api", "--follow")
        self.assertIn("--follow", json.loads((self.root / "calls").read_text().splitlines()[-1]))

    def test_symlink_finds_libraries(self):
        link = self.root / "tk-link"
        link.symlink_to(SCRIPTS / "tk")
        self.assertEqual(self.cli("list", "--json", executable=link).returncode, 0)

    def test_missing_mount_and_build_are_actionable(self):
        self.config["services"]["api"].update(build={"context": str(self.root / "missing")},
                                               volumes=[{"type": "bind", "source": str(self.root / "token"), "target": "/run/secrets/token"}])
        result = self.cli("doctor", "--json")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Bind source is missing", result.stdout)
        self.assertIn("Build context is missing", result.stdout)

    def test_timeout_does_not_echo_command_or_secret_output(self):
        with patch.object(inspect.subprocess, "run", side_effect=subprocess.TimeoutExpired("secret-argument", 15, output="secret-output")):
            with self.assertRaisesRegex(inspect.InspectionError, "timed out") as caught:
                inspect.run(["docker", "secret-argument"], self.root)
            self.assertNotIn("secret", str(caught.exception))

    def test_probes_verify_tls_and_discard_response_bodies(self):
        with patch.object(inspect, "run", return_value="401") as run:
            self.assertEqual(inspect.probe("https://api.internal", self.root)["status"], "ok")
            command = run.call_args.args[0]
            self.assertNotIn("-k", command)
            self.assertIn("--max-time", command)
            self.assertIn(os.devnull, command)
        with patch.object(inspect, "run", return_value="502"):
            self.assertEqual(inspect.probe("https://api.internal", self.root)["status"], "fail")

    def test_negated_host_and_disabled_routes_do_not_invent_urls(self):
        self.assertEqual(inspect.service_urls({"labels": {
            "traefik.enable": "true", "traefik.http.routers.a.rule": "! Host(`excluded.internal`) && HostRegexp(`.+`)"}}), [])
        self.config["services"]["api"]["labels"]["traefik.enable"] = "false"
        self.assertEqual(inspect.service_urls(self.config["services"]["api"]), [])

    def test_explicit_ip_preserves_host_and_tls(self):
        with patch.object(inspect, "run", return_value="200") as run:
            result = inspect.probe("https://custom.internal", self.root, resolve_address="127.0.0.1")
            command = run.call_args.args[0]
            self.assertIn("custom.internal:443:127.0.0.1", command)
            self.assertEqual(command[-1], "https://custom.internal/")
            self.assertNotIn("-k", command)
            self.assertIn("DNS bypassed", result["message"])
        self.assertEqual(self.cli("doctor", "--probe", "--resolve-address", "bad-host").returncode, 2)

    def test_memory_doctor_requires_live_codex_readiness(self):
        hub = self.root / "hub/bin"
        hub.mkdir(parents=True)
        doctor = hub / "memory-hub"
        doctor.write_text('#!/bin/sh\nprintf \'%s\\n\' \'{"ready":true,"mode":"synthetic","codex_enabled":true}\'\n')
        doctor.chmod(0o755)
        result = self.cli("doctor", "--json", "--memory-hub", str(hub.parent))
        self.assertEqual(result.returncode, 1)
        self.assertIn("not ready for live Codex memory", result.stdout)
        doctor.write_text(doctor.read_text().replace('"synthetic"', '"live"'))
        self.assertEqual(self.cli("doctor", "--json", "--memory-hub", str(hub.parent)).returncode, 0)

    def refresh(self, fail=False):
        mkcert = self.root / "mkcert"
        mkcert.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
Path(os.environ['CERT_ARGS']).write_text(json.dumps(sys.argv[1:]))
if os.environ.get('CERT_FAIL'): sys.exit(1)
Path(sys.argv[sys.argv.index('-key-file')+1]).write_text('new-key')
Path(sys.argv[sys.argv.index('-cert-file')+1]).write_text('new-cert')
''')
        mkcert.chmod(0o755)
        env = dict(self.env, CONFIG=json.dumps(self.config), TRAEFIK_DIR=str(self.root),
                   CERT_ARGS=str(self.root / "cert-args"))
        if fail:
            env["CERT_FAIL"] = "1"
        return subprocess.run(["bash", str(SCRIPTS / "refresh-certs.sh")], env=env,
                              cwd=self.root, capture_output=True, text=True, timeout=10)

    def test_cert_refresh_adds_concrete_hosts_and_preserves_prior_pair(self):
        certs = self.root / "certs"
        certs.mkdir()
        (certs / "key.pem").write_text("old-key")
        (certs / "cert.pem").write_text("old-cert")
        result = self.refresh()
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads((self.root / "cert-args").read_text())
        self.assertIn("*.internal", args)
        self.assertIn("custom.internal", args)
        self.assertIn("custom.home.local", args)
        self.assertEqual((certs / "key.pem.previous").read_text(), "old-key")
        self.assertEqual((certs / "cert.pem").read_text(), "new-cert")
        self.assertEqual((certs / "key.pem").stat().st_mode & 0o777, 0o600)
        self.assertFalse(list(certs.glob(".renew.*")))

    def test_failed_cert_generation_leaves_existing_pair_intact(self):
        certs = self.root / "certs"
        certs.mkdir()
        (certs / "key.pem").write_text("old-key")
        (certs / "cert.pem").write_text("old-cert")
        self.assertNotEqual(self.refresh(fail=True).returncode, 0)
        self.assertEqual((certs / "key.pem").read_text(), "old-key")
        self.assertEqual((certs / "cert.pem").read_text(), "old-cert")
        self.assertFalse(list(certs.glob(".renew.*")))

    def test_dns_apply_fails_before_mutation_without_sudo_authorization(self):
        etc = self.root / "etc"
        etc.mkdir()
        (etc / "dnsmasq.conf").write_text("address=/internal/127.0.0.1\naddress=/home.local/127.0.0.1\n")
        for name, body in {
            "uname": "echo Darwin",
            "brew": 'echo "$FAKE_PREFIX"',
            "sudo": 'printf \'%s\\n\' "$*" >> "$SUDO_CALLS"; exit 1',
            "dig": "exit 1",
        }.items():
            binary = self.root / name
            binary.write_text("#!/bin/sh\n" + body + "\n")
            binary.chmod(0o755)
        env = dict(self.env, FAKE_PREFIX=str(self.root), SUDO_CALLS=str(self.root / "sudo-calls"))
        result = subprocess.run(["bash", str(SCRIPTS / "setup-dns.sh"), "--apply"],
                                env=env, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn("local Terminal", result.stderr)
        self.assertEqual((self.root / "sudo-calls").read_text(), "-n true\n")
        (self.root / "sudo-calls").unlink()
        (self.root / "dig").write_text('#!/bin/sh\ncase "$*" in *AAAA*) echo "status: SERVFAIL";; *) echo 127.0.0.1;; esac\n')
        result = subprocess.run(["bash", str(SCRIPTS / "setup-dns.sh"), "--check"],
                                env=env, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL dnsmasq AAAA", result.stdout)
        self.assertFalse((self.root / "sudo-calls").exists())


if __name__ == "__main__":
    unittest.main()
