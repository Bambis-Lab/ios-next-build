"""Fail-closed evidence check for the shared native pilot, not a release gate."""
import json
import os
from pathlib import Path
import re
import sys
import unittest
import tempfile


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def read_one(root, name):
    matches = list(root.rglob(name))
    require(len(matches) == 1 and matches[0].is_file(), 'missing or duplicate ' + name)
    return matches[0].read_text()


def summary(root, name, uid, minimum):
    data = json.loads(read_one(root, name + '-summary.json'))
    for key in ('failedTests', 'skippedTests', 'expectedFailures'):
        require(type(data.get(key)) is int and data[key] == 0, name + ': ' + key)
    passed = data.get('passedTests')
    require(type(passed) is int and passed >= minimum and data.get('totalTestCount') == passed
            and data.get('result') == 'Passed', name + ': incomplete result')
    devices = data.get('devicesAndConfigurations')
    require(isinstance(devices, list) and len(devices) > 0, name + ': missing devices')
    require({d['device']['deviceId'].lower() for d in devices} == {uid.lower()}, name + ': wrong simulator')
    return passed


def verify(root, identity):
    pair = json.loads(read_one(root / 'V64-preflight-validation', 'handoff-validation.json'))
    require(pair.get('status') == 'PASS_OFFLINE_NATIVE_ROLE_HANDOFF_ONLY' and pair.get('g03') == 'BLOCKED',
            'offline roles not verified')
    roles = pair['clients']
    require(len(roles) == 2 and {r['role'] for r in roles} == {'A', 'B'}, 'wrong role pair')
    for r in roles:
        require(all(r.get(k) == v for k, v in identity.items()), 'foreign role identity')
        require(r.get('media_tested') is False and r.get('network_used') is False, 'wrong proof scope')
        require(all(r.get(k) is True for k in ('native_role_read', 'wrong_role_rejected', 'wrong_duration_rejected', 'transient_file_removed')), 'role proof incomplete')
    digest = roles[0]['build_sha256']
    require(re.fullmatch('[0-9a-f]{64}', digest) and roles[1]['build_sha256'] == digest, 'role product mismatch')
    hosts = [r['host_boot_sha256'] for r in roles]
    reports = {}
    for shard, minimum in (('AB', 22), ('CF', 9)):
        directory = root / ('R80-regression-' + shard)
        record = json.loads(read_one(directory, 'regression-binding.json'))
        require(all(record.get(k) == v for k, v in identity.items()) and record.get('shard') == shard, 'foreign regression identity')
        require(record.get('build_sha256') == digest, 'regression product mismatch')
        uid = record['simulator']
        require(re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', uid), 'invalid simulator')
        hosts.append(record['host_boot_sha256'])
        reports[shard] = {'unit_passed': summary(directory, 'OwnerNavigation', uid, minimum)}
        if shard == 'CF':
            clean = json.loads(read_one(directory, 'clean-install-destination.json'))
            require(all(clean.get(k) == v for k, v in identity.items()) and clean.get('simulator') == uid
                    and clean.get('newly_created') is True, 'wrong clean-install binding')
            reports[shard]['clean_install_passed'] = summary(directory, 'CleanInstall', uid, 1)
            reports[shard]['ui_passed'] = summary(directory, 'IndependentServices', uid, 3)
    require(all(re.fullmatch('[0-9a-f]{64}', h) for h in hosts) and len(set(hosts)) == 4, 'not four independent hosts')
    return {'status': 'PASS_NATIVE_PILOT_PREREQUISITE_ONLY', **identity, 'build_sha256': digest,
            'regression': reports, 'independent_hosts': 4, 'G01': 'OPEN', 'G02': 'OPEN',
            'G03': 'BLOCKED', 'G04': 'BLOCKED', 'G05': 'OPEN', 'G99': 'OPEN', 'release': False}


class Checks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.identity = {'source': 'a'*40, 'run': '1', 'attempt': '1'}
        self.uid = '11111111-2222-3333-4444-555555555555'
        self.digest = 'd'*64
        roles = [{'role': role, **self.identity, 'build_sha256': self.digest,
                  'host_boot_sha256': host*64, 'media_tested': False, 'network_used': False,
                  **dict.fromkeys(('native_role_read', 'wrong_role_rejected', 'wrong_duration_rejected', 'transient_file_removed'), True)}
                 for role, host in [('A', 'a'), ('B', 'b')]]
        self.put('V64-preflight-validation/handoff-validation.json', {'status': 'PASS_OFFLINE_NATIVE_ROLE_HANDOFF_ONLY', 'g03': 'BLOCKED', 'clients': roles})
        for shard, host, count in [('AB', 'c', 22), ('CF', 'e', 9)]:
            base = 'R80-regression-' + shard + '/'
            self.put(base+'regression-binding.json', {**self.identity, 'shard': shard, 'simulator': self.uid, 'build_sha256': self.digest, 'host_boot_sha256': host*64})
            self.put(base+'OwnerNavigation-summary.json', self.result(count))
        self.put('R80-regression-CF/clean-install-destination.json', {**self.identity, 'simulator': self.uid, 'newly_created': True})
        self.put('R80-regression-CF/CleanInstall-summary.json', self.result(1))
        self.put('R80-regression-CF/IndependentServices-summary.json', self.result(3))

    def put(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))

    def change(self, name, key, value):
        data = json.loads((self.root / name).read_text())
        data[key] = value
        self.put(name, data)

    def result(self, n):
        return {'result': 'Passed', 'passedTests': n, 'totalTestCount': n, 'failedTests': 0,
                'skippedTests': 0, 'expectedFailures': 0, 'devicesAndConfigurations': [{'device': {'deviceId': self.uid}}]}

    def denied(self, name, key, value):
        self.change(name, key, value)
        with self.assertRaises(ValueError):
            verify(self.root, self.identity)

    def test_valid(self):
        self.assertFalse(verify(self.root, self.identity)['release'])

    def test_skipped(self):
        self.denied('R80-regression-AB/OwnerNavigation-summary.json', 'skippedTests', 1)

    def test_expected_failure(self):
        self.denied('R80-regression-AB/OwnerNavigation-summary.json', 'expectedFailures', 1)

    def test_failed(self):
        self.denied('R80-regression-AB/OwnerNavigation-summary.json', 'failedTests', 1)

    def test_wrong_build(self):
        self.denied('R80-regression-CF/regression-binding.json', 'build_sha256', 'f'*64)

    def test_wrong_attempt(self):
        self.denied('R80-regression-CF/regression-binding.json', 'attempt', '2')

    def test_wrong_host(self):
        self.denied('R80-regression-CF/regression-binding.json', 'host_boot_sha256', 'c'*64)

    def test_wrong_device(self):
        self.denied('R80-regression-CF/CleanInstall-summary.json', 'devicesAndConfigurations', [{'device': {'deviceId': 'wrong'}}])

    def test_wrong_clean_state(self):
        self.denied('R80-regression-CF/clean-install-destination.json', 'newly_created', False)

    def test_duplicate(self):
        self.put('R80-regression-AB/duplicate/regression-binding.json', {})
        with self.assertRaises(ValueError):
            verify(self.root, self.identity)

    def test_missing(self):
        (self.root / 'R80-regression-CF/CleanInstall-summary.json').unlink()
        with self.assertRaises(ValueError):
            verify(self.root, self.identity)

    def test_empty(self):
        self.denied('R80-regression-CF/IndependentServices-summary.json', 'passedTests', 0)


if __name__ == '__main__':
    if sys.argv[1:] == ['self-test']:
        unittest.main(argv=[sys.argv[0]], verbosity=2)
    elif len(sys.argv) == 3:
        identity = {key: os.environ[env] for key, env in [('source', 'GITHUB_SHA'), ('run', 'GITHUB_RUN_ID'), ('attempt', 'GITHUB_RUN_ATTEMPT')]}
        report = verify(Path(sys.argv[1]), identity)
        Path(sys.argv[2]).write_text(json.dumps(report, indent=2)+'\n')
    else:
        raise SystemExit('self-test or ARTIFACT_ROOT OUTPUT_JSON')
