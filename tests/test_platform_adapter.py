import json
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

class PlatformAdapterTests(unittest.TestCase):
    def test_frontend_capabilities_need_no_selected_package(self):
        with tempfile.TemporaryDirectory() as temp:
            env={k:v for k,v in os.environ.items() if k!='TK_PLATFORM_ROOT'}
            env['TK_PLATFORM_CONFIG']=temp+'/missing.json'
            proc=subprocess.run([str(ROOT/'tk'),'platform','frontend-capabilities','--json'],
                                env=env,text=True,capture_output=True)
            self.assertEqual(proc.returncode,0)
            payload=json.loads(proc.stdout)
            self.assertEqual(payload['frontend_protocol_version'],1)
            self.assertEqual(payload['verification'],'selector-inventory-entry-contract')

    def installed(self, base, version='0.2.1', protocol=None):
        base=base.resolve()
        root=base/'release';(root/'src').mkdir(parents=True,exist_ok=True)
        entry=root/'src/tk-platform.py'
        entry.write_text('import json; print(json.dumps({"forwarded": True}))\n')
        files={'src/tk-platform.py':hashlib.sha256(entry.read_bytes()).hexdigest()}
        if protocol is not None:
            contract=root/'schemas/frontend-package-v1.json';contract.parent.mkdir(exist_ok=True)
            contract.write_text(json.dumps({'schema_version':1,'frontend_protocol_version':protocol}))
            files['schemas/frontend-package-v1.json']=hashlib.sha256(contract.read_bytes()).hexdigest()
        sha=hashlib.sha256(json.dumps(files,sort_keys=True).encode()).hexdigest()
        (root/'release.json').write_text(json.dumps({'schema_version':1,'version':version,'sha256':sha,'files':files}))
        selector=base/'platform.json'
        selector.write_text(json.dumps({'schema_version':1,'root':str(root),'version':version,'sha256':sha}))
        return root,selector

    def invoke(self, selector):
        env={k:v for k,v in os.environ.items() if k!='TK_PLATFORM_ROOT'}
        env['TK_PLATFORM_CONFIG']=str(selector)
        return subprocess.run([str(ROOT/'tk'),'agent','capabilities','--json'],env=env,text=True,capture_output=True)

    def test_known_legacy_and_new_package(self):
        for version,protocol in [('0.2.1',None),('0.3.0',1)]:
            with self.subTest(version=version),tempfile.TemporaryDirectory() as temp:
                _,selector=self.installed(Path(temp),version,protocol)
                proc=self.invoke(selector)
                self.assertEqual(proc.returncode,0,proc.stdout+proc.stderr)
                self.assertTrue(json.loads(proc.stdout)['forwarded'])

    def test_future_or_malformed_contract_never_executes(self):
        for protocol,code in [(2,'platform_protocol_incompatible'),(0,'platform_package_unavailable'),
                              (-1,'platform_package_unavailable'),(True,'platform_package_unavailable')]:
            with self.subTest(protocol=protocol),tempfile.TemporaryDirectory() as temp:
                _,selector=self.installed(Path(temp),'0.3.0',protocol)
                proc=self.invoke(selector)
                self.assertEqual(proc.returncode,30)
                self.assertEqual(json.loads(proc.stdout)['error']['code'],code)

    def test_missing_contract_on_new_release_and_digest_mismatch(self):
        with tempfile.TemporaryDirectory() as temp:
            root,selector=self.installed(Path(temp),'0.3.0')
            self.assertEqual(self.invoke(selector).returncode,30)
            _,selector=self.installed(Path(temp),'0.3.0',1)
            (root/'src/tk-platform.py').write_text('raise SystemExit(99)')
            self.assertEqual(self.invoke(selector).returncode,30)

    def test_symlinks_and_invalid_json_are_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            base=Path(temp).resolve();root,selector=self.installed(base,'0.3.0',1)
            linked=base/'linked';linked.symlink_to(root, target_is_directory=True)
            value=json.loads(selector.read_text());value['root']=str(linked);selector.write_text(json.dumps(value))
            self.assertEqual(self.invoke(selector).returncode,30)
            value['root']=str(root);selector.write_text(json.dumps(value))
            linked_selector=base/'linked-selector.json';linked_selector.symlink_to(selector)
            self.assertEqual(self.invoke(linked_selector).returncode,30)
            selector.write_text('{')
            self.assertEqual(self.invoke(selector).returncode,30)

    def test_linked_release_metadata_and_entry_are_refused(self):
        for name in ('release.json','src/tk-platform.py'):
            with self.subTest(name=name),tempfile.TemporaryDirectory() as temp:
                base=Path(temp).resolve();root,selector=self.installed(base,'0.3.0',1)
                path=root/name;other=base/'other';other.write_bytes(path.read_bytes())
                path.unlink();path.symlink_to(other)
                self.assertEqual(self.invoke(selector).returncode,30)

    def test_structured_commands_forward_without_sourcing_local_config(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'src').mkdir()
            for name in ('tk-dev.py','tk-kube.py','tk-app.py','tk-platform.py'):
                (root/'src'/name).write_text('import json,sys; print(json.dumps({"argv":sys.argv[1:]}))')
            for group in ('dev','kube','app','service','agent','platform'):
                proc=subprocess.run([str(ROOT/'tk'),group,'capabilities','--json'],env={**os.environ,'TK_PLATFORM_ROOT':str(root)},text=True,capture_output=True)
                self.assertEqual(proc.returncode,0,proc.stderr)
                self.assertEqual(json.loads(proc.stdout)['argv'],[group,'capabilities','--json'])

    def test_missing_package_has_actionable_json(self):
        with tempfile.TemporaryDirectory() as temp:
            env={k:v for k,v in os.environ.items() if k!='TK_PLATFORM_ROOT'}
            env['TK_PLATFORM_CONFIG']=temp+'/absent.json'
            proc=subprocess.run([str(ROOT/'tk'),'dev','capabilities','--json'],env=env,text=True,capture_output=True)
            self.assertEqual(proc.returncode,30)
            self.assertEqual(json.loads(proc.stdout)['error']['code'],'platform_package_unavailable')
