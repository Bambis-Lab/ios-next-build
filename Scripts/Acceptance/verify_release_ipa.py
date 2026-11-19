"""Offline IPA metadata preflight only; never certifies signing or release."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import tempfile
import unittest
from urllib.parse import urlsplit
import zipfile


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def valid_broker(value):
    if not isinstance(value, str) or not value or any(c.isspace() or ord(c) < 32 for c in value) or '$(' in value:
        return False
    try:
        u = urlsplit(value)
        return (u.scheme == 'https' and bool(u.hostname) and u.username is None
                and u.password is None and not u.query and not u.fragment
                and (u.port is None or 1 <= u.port <= 65535))
    except ValueError:
        return False


def verify(path, build, broker):
    require(re.fullmatch(r'[1-9][0-9]*', build), 'invalid expected build number')
    require(valid_broker(broker), 'approved broker URL missing or invalid')
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        require(len(names) == len(set(names)), 'duplicate ZIP member')
        require(all(not n.startswith('/') and '\\' not in n and '..' not in PurePosixPath(n).parts for n in names), 'unsafe ZIP member')
        roots = [n for n in names if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
        require(len(roots) == 1, 'missing or multiple app manifests')
        manifest = z.getinfo(roots[0])
        require(manifest.file_size <= 1024*1024 and not stat.S_ISLNK(manifest.external_attr >> 16), 'invalid manifest entry')
        info = plistlib.loads(z.read(manifest))
        require(info.get('CFBundleIdentifier') == 'de.nicofroeba16.iosnext', 'bundle identifier mismatch')
        require(info.get('CFBundleShortVersionString') == '1.8.0', 'marketing version mismatch')
        require(info.get('CFBundleVersion') == build, 'build number mismatch')
        require(info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'], 'not an iOS device product')
        require(info.get('MinimumOSVersion') == '27.0', 'deployment target mismatch')
        require(info.get('IOSNextFamilyBrokerURL') == broker, 'approved family broker mismatch')
        executable = info.get('CFBundleExecutable')
        require(isinstance(executable, str) and re.fullmatch(r'[A-Za-z0-9_.-]+', executable) and executable not in ('.', '..'), 'invalid executable name')
        entry = z.getinfo(roots[0].rsplit('/', 1)[0] + '/' + executable)
        require(entry.file_size > 0 and not entry.is_dir() and not stat.S_ISLNK(entry.external_attr >> 16), 'invalid executable entry')
        require(z.testzip() is None, 'ZIP integrity failure')
    with open(path, 'rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    return {'status': 'PASS_IPA_METADATA_ONLY', 'version': '1.8.0', 'build': build,
            'sha256': digest, 'broker_matches_approved': True,
            'signature_verified': False, 'build_number_uniqueness_verified': False,
            'native_install_verified': False, 'release_authorized': False}


class Checks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'fixture.ipa'
        self.broker = 'https://family.example.invalid'
        self.info = {'CFBundleIdentifier': 'de.nicofroeba16.iosnext', 'CFBundleShortVersionString': '1.8.0',
                     'CFBundleVersion': '42', 'CFBundleSupportedPlatforms': ['iPhoneOS'],
                     'MinimumOSVersion': '27.0', 'IOSNextFamilyBrokerURL': self.broker, 'CFBundleExecutable': 'IOSNext'}

    def make(self):
        with zipfile.ZipFile(self.path, 'w') as z:
            z.writestr('Payload/IOSNext.app/Info.plist', plistlib.dumps(self.info))
            z.writestr('Payload/IOSNext.app/IOSNext', b'not a real executable; metadata fixture')

    def test_valid_metadata_not_release(self):
        self.make()
        result = verify(self.path, '42', self.broker)
        self.assertEqual(result['status'], 'PASS_IPA_METADATA_ONLY')
        self.assertFalse(result['signature_verified'])
        self.assertFalse(result['release_authorized'])

    def test_invalid_metadata(self):
        for key, value in [('CFBundleIdentifier', 'foreign.app'), ('CFBundleShortVersionString', '1.7.3'),
                           ('CFBundleVersion', '41'), ('CFBundleSupportedPlatforms', ['iPhoneSimulator']),
                           ('MinimumOSVersion', '26.0'), ('IOSNextFamilyBrokerURL', ''),
                           ('IOSNextFamilyBrokerURL', 'https://other.example.invalid'), ('CFBundleExecutable', '../bad')]:
            with self.subTest(key=key, value=value):
                original = self.info[key]
                self.info[key] = value
                self.make()
                with self.assertRaises(ValueError):
                    verify(self.path, '42', self.broker)
                self.info[key] = original

    def test_invalid_approved_url(self):
        self.make()
        for url in ('', 'http://family.example.invalid', 'https://user:pass@example.invalid',
                    'https://example.invalid?token=x', 'https://example.invalid#x', '$(BROKER)', 'https://example.invalid:99999'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                verify(self.path, '42', url)

    def test_unsafe_member(self):
        self.make()
        with zipfile.ZipFile(self.path, 'a') as z:
            z.writestr('../outside', b'fixture')
        with self.assertRaises(ValueError):
            verify(self.path, '42', self.broker)


if __name__ == '__main__':
    import sys
    if sys.argv[1:] == ['self-test']:
        unittest.main(argv=[sys.argv[0]], verbosity=2)
    else:
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument('ipa', type=Path)
        parser.add_argument('--build', required=True)
        parser.add_argument('--approved-broker', required=True)
        args = parser.parse_args()
        try:
            print(json.dumps(verify(args.ipa, args.build, args.approved_broker), indent=2))
        except (ValueError, OSError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException):
            raise SystemExit('IPA_METADATA_PREFLIGHT_FAILED') from None
