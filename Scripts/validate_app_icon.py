#!/usr/bin/env python3
import json
import struct
import sys
import zlib
from pathlib import Path

ICON = Path('Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png')
CONTENTS = ICON.with_name('Contents.json')
PNG_SIG = b'\x89PNG\r\n\x1a\n'


def fail(message: str) -> None:
    raise SystemExit(f'APP_ICON_VALIDATION_FAIL: {message}')


def validate_png(path: Path) -> None:
    data = path.read_bytes()
    if not data.startswith(PNG_SIG):
        fail('missing PNG signature')
    pos = len(PNG_SIG)
    saw_ihdr = False
    saw_iend = False
    while pos < len(data):
        if pos + 12 > len(data):
            fail(f'truncated chunk header at byte {pos}')
        length = struct.unpack('>I', data[pos:pos + 4])[0]
        chunk_type = data[pos + 4:pos + 8]
        end = pos + 12 + length
        if end > len(data):
            fail(f'truncated {chunk_type!r} chunk at byte {pos}')
        payload = data[pos + 8:pos + 8 + length]
        expected_crc = struct.unpack('>I', data[pos + 8 + length:end])[0]
        actual_crc = zlib.crc32(chunk_type)
        actual_crc = zlib.crc32(payload, actual_crc) & 0xffffffff
        if actual_crc != expected_crc:
            fail(f'CRC mismatch in {chunk_type.decode("ascii", "replace")} chunk at byte {pos}')
        if chunk_type == b'IHDR':
            if saw_ihdr or length != 13:
                fail('invalid IHDR')
            saw_ihdr = True
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack('>IIBBBBB', payload)
            if (width, height) != (1024, 1024):
                fail(f'expected 1024x1024, got {width}x{height}')
            if bit_depth != 8 or color_type != 2:
                fail(f'expected 8-bit RGB PNG without alpha, got bit_depth={bit_depth}, color_type={color_type}')
            if (compression, filtering, interlace) != (0, 0, 0):
                fail('unsupported PNG IHDR flags')
        elif chunk_type == b'IEND':
            if length != 0:
                fail('invalid IEND')
            saw_iend = True
            if end != len(data):
                fail('trailing bytes after IEND')
            break
        pos = end
    if not saw_ihdr or not saw_iend:
        fail('missing required IHDR/IEND chunks')


def validate_contents(path: Path) -> None:
    data = json.loads(path.read_text())
    matches = [
        item for item in data.get('images', [])
        if item.get('filename') == ICON.name
        and item.get('idiom') == 'universal'
        and item.get('platform') == 'ios'
        and item.get('size') == '1024x1024'
    ]
    if len(matches) != 1:
        fail('Contents.json does not contain exactly one universal iOS 1024x1024 AppIcon entry')


if not ICON.is_file():
    fail(f'missing {ICON}')
if not CONTENTS.is_file():
    fail(f'missing {CONTENTS}')
validate_png(ICON)
validate_contents(CONTENTS)
print('APP_ICON_VALIDATION=PASS')
