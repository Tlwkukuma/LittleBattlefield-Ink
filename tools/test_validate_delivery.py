"""Fast isolated tests, no Godot, network, repository initialization or gameplay."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('validate_delivery', Path(__file__).with_name('validate_delivery.py'))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class DeliveryTests(unittest.TestCase):
    def test_source_and_licenses_are_included(self):
        for name in ('README.md', 'AGENTS.md', 'START.bat', 'tools/check.py',
                     'qa/check.gd', 'art/model.blend', '.character-iterations/reference.png',
                     'assets/audio/combat/README.md', 'assets/audio/free-firearms/LICENSE.md'):
            self.assertTrue(MODULE.included(Path(name)), name)

    def test_generated_state_and_secrets_are_excluded(self):
        for name in ('.godot/imported/a.ctex', 'build/run.exe', 'exports/run.zip',
                     'tools/__pycache__/a.pyc', 'qa/trace.log', '.git/config', '.env', '.env.local'):
            self.assertFalse(MODULE.included(Path(name)), name)
        self.assertTrue(MODULE.included(Path('.env.example')))

    def make_project(self, root):
        for name in MODULE.REQUIRED:
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('', encoding='utf-8')
        (root / 'scripts/proving_ground.gd').write_text('const BUILD_VERSION: String = "test-1"\n', encoding='utf-8')

    def test_manifest_roundtrip_and_tampering(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_project(root)
            report, errors = MODULE.inspect(root)
            self.assertEqual(errors, [])
            self.assertEqual(MODULE.verify_manifest(report, report), [])
            (root / 'README.md').write_text('changed', encoding='utf-8')
            changed, _ = MODULE.inspect(root)
            self.assertEqual(MODULE.verify_manifest(changed, report), ['Changed source file: README.md'])
            (root / 'README.md').unlink()
            changed, errors = MODULE.inspect(root)
            self.assertIn('Missing required file: README.md', errors)
            self.assertIn('Missing manifest file: README.md', MODULE.verify_manifest(changed, report))

    def test_resource_resolution_and_dynamic_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_project(root)
            script = root / 'scripts/test.gd'
            script.write_text('var path="res://assets/"+name\nvar a=preload("res://missing.gd")\n', encoding='utf-8')
            _, errors = MODULE.inspect(root)
            self.assertEqual(errors, ['Missing literal resource in scripts/test.gd: res://missing.gd'])
            script.write_text('var a=load("res://../escape.gd")\n', encoding='utf-8')
            self.assertEqual(len(MODULE.inspect(root)[1]), 1)

    def test_invalid_json_and_cache_pruning(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_project(root)
            (root / '.godot').mkdir()
            (root / '.godot/invalid.json').write_text('{', encoding='utf-8')
            self.assertEqual(MODULE.inspect(root)[1], [])
            (root / 'bad.json').write_text('{', encoding='utf-8')
            self.assertTrue(MODULE.inspect(root)[1][0].startswith('Invalid JSON bad.json:'))
            (root / 'bad.json').write_text('{"x": NaN}', encoding='utf-8')
            self.assertIn('Non-standard JSON numeric constant', MODULE.inspect(root)[1][0])

    def test_gitignore_has_no_delivery_blacklist(self):
        rules = (Path(__file__).parents[1] / '.gitignore').read_text().splitlines()
        for rule in ('qa/', 'docs/', 'art/', 'tools/', '*.md', '*.bat', 'assets/audio/combat/'):
            self.assertNotIn(rule, rules)


if __name__ == '__main__':
    unittest.main()
