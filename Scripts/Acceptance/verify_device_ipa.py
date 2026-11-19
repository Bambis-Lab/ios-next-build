"""Structural iPhoneOS executable verification, not code-signing acceptance."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import struct
import unittest
import zipfile

from verify_release_ipa import verify as verify_metadata


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def inspect_executable(stream, size):
    require(size >= 32, 'truncated executable')
    header = stream.read(32)
    require(len(header) == 32, 'truncated Mach-O header')
    magic, cpu, subtype, kind, count, length, flags, reserved = struct.unpack('<8I', header)
    require(magic == 0xfeedfacf and cpu == 0x0100000c and kind == 2, 'expected thin ARM64 Mach-O executable')
    require(0 < count <= 4096 and 8 * count <= length <= min(size - 32, 4 * 1024 * 1024), 'invalid load command bounds')
    data = stream.read(length)
    require(len(data) == length, 'truncated load commands')
    pos = 0
    platforms = []
    entries = []
    signatures = []
    for _ in range(count):
        require(pos + 8 <= length, 'truncated command header')
        cmd, n = struct.unpack_from('<2I', data, pos)
        require(n >= 8 and n % 8 == 0 and pos + n <= length, 'invalid command size')
        if cmd == 0x32:  # LC_BUILD_VERSION
            require(n >= 24, 'truncated build version')
            platform, minimum, sdk, tools = struct.unpack_from('<4I', data, pos + 8)
            require(n == 24 + 8 * tools, 'invalid build tool list')
            platforms.append((platform, minimum, sdk))
        elif cmd == 0x80000028:  # LC_MAIN
            require(n == 24, 'invalid entry command')
            entries.append(struct.unpack_from('<Q', data, pos + 8)[0])
        elif cmd == 0x1d:  # LC_CODE_SIGNATURE
            require(n == 16, 'invalid signature command')
            off, amount = struct.unpack_from('<2I', data, pos + 8)
            require(amount > 0 and off >= 32 + length and off + amount <= size, 'invalid signature bounds')
            signatures.append(True)
        pos += n
    require(pos == length, 'unparsed command bytes')
    require(len(platforms) == 1, 'missing or duplicate platform')
    platform, minimum, sdk = platforms[0]
    require(platform == 2 and minimum == 0x001b0000 and sdk >= minimum, 'not an iOS 27 device executable')
    require(len(entries) == 1 and 32 + length <= entries[0] < size, 'missing or invalid entry point')
    require(len(signatures) <= 1, 'duplicate signature command')
    return {'architecture': 'arm64', 'platform': 'iPhoneOS', 'minimum_os': '27.0',
            'code_signature_command_present': bool(signatures), 'signature_verified': False}


def verify(path, build, broker):
    report = verify_metadata(path, build, broker)
    with zipfile.ZipFile(path) as z:
        roots = [n for n in z.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
        info = plistlib.loads(z.read(roots[0]))
        executable = roots[0].rsplit('/', 1)[0] + '/' + info['CFBundleExecutable']
        item = z.getinfo(executable)
        require((item.external_attr >> 16) & 0o111 != 0, 'executable permission missing')
        with z.open(item) as stream:
            report.update(inspect_executable(stream, item.file_size))
    report['status'] = 'PASS_DEVICE_STRUCTURE_ONLY'
    return report


class DeviceChecks(unittest.TestCase):
    @staticmethod
    def image(cpu=0x0100000c, platform=2, minimum=0x001b0000, entry=80, command_size=24):
        commands = struct.pack('<6I', 0x32, command_size, platform, minimum, 0x001b0000, 0)
        commands += struct.pack('<IIQQ', 0x80000028, 24, entry, 0)
        return struct.pack('<8I', 0xfeedfacf, cpu, 0, 2, 2, len(commands), 0, 0) + commands + bytes(128)

    def inspect(self, data):
        import io
        return inspect_executable(io.BytesIO(data), len(data))

    def test_device(self):
        r = self.inspect(self.image())
        self.assertEqual(r['architecture'], 'arm64')
        self.assertFalse(r['signature_verified'])

    def test_simulator(self):
        with self.assertRaises(ValueError): self.inspect(self.image(platform=7))

    def test_wrong_cpu(self):
        with self.assertRaises(ValueError): self.inspect(self.image(cpu=0x01000007))

    def test_wrong_minimum(self):
        with self.assertRaises(ValueError): self.inspect(self.image(minimum=0x001a0000))

    def test_bad_entry(self):
        with self.assertRaises(ValueError): self.inspect(self.image(entry=9999))

    def test_bad_command(self):
        with self.assertRaises(ValueError): self.inspect(self.image(command_size=0))

    def test_short(self):
        with self.assertRaises(ValueError): self.inspect(b'not a binary')

    def test_package(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory) / 'fixture.ipa'
            broker = 'https://family.example.invalid'
            info = {'CFBundleIdentifier': 'de.nicofroeba16.iosnext', 'CFBundleShortVersionString': '1.8.0',
                    'CFBundleVersion': '42', 'CFBundleSupportedPlatforms': ['iPhoneOS'],
                    'MinimumOSVersion': '27.0', 'IOSNextFamilyBrokerURL': broker, 'CFBundleExecutable': 'IOSNext'}
            for binary, valid in ((self.image(), True), (b'fake', False), (self.image(platform=7), False)):
                with zipfile.ZipFile(p, 'w') as z:
                    z.writestr('Payload/IOSNext.app/Info.plist', plistlib.dumps(info))
                    member = zipfile.ZipInfo('Payload/IOSNext.app/IOSNext')
                    member.create_system = 3
                    member.external_attr = 0o100755 << 16
                    z.writestr(member, binary)
                if valid:
                    self.assertEqual(verify(p, '42', broker)['status'], 'PASS_DEVICE_STRUCTURE_ONLY')
                    self.assertFalse(verify(p, '42', broker)['release_authorized'])
                else:
                    with self.assertRaises(ValueError): verify(p, '42', broker)


if __name__ == '__main__':
    import sys
    if sys.argv[1:] == ['self-test']:
        unittest.main(argv=[sys.argv[0]], verbosity=2)
    else:
        p = argparse.ArgumentParser(description=__doc__)
        p.add_argument('ipa', type=Path)
        p.add_argument('--build', required=True)
        p.add_argument('--approved-broker', required=True)
        args = p.parse_args()
        try:
            print(json.dumps(verify(args.ipa, args.build, args.approved_broker), indent=2))
        except (ValueError, OSError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException, struct.error):
            raise SystemExit('DEVICE_STRUCTURE_CHECK_FAILED') from None
