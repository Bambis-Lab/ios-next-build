"""Stage a new SideStore manifest offline; never publish or establish approval."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

from verify_release_ipa import verify as verify_ipa

SOURCE = 'https://raw.githubusercontent.com/Bambis-Lab/ios-next-releases/main/source.json'
ASSET = 'https://github.com/Bambis-Lab/ios-next-releases/releases/download/v1.8.0/IOSNext.ipa'


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def stage(raw, expected_feed_sha, ipa, build, broker, approved_digest, release, notes, now):
    require(hashlib.sha256(raw).hexdigest() == expected_feed_sha, 'feed baseline mismatch')
    report = verify_ipa(ipa, build, broker)
    require(re.fullmatch(r'[0-9a-f]{64}', approved_digest) and report['sha256'] == approved_digest, 'IPA digest mismatch')
    require(release.get('tag_name') == 'v1.8.0' and release.get('draft') is False
            and release.get('prerelease') is False, 'not a final published release')
    date = release.get('published_at', '')
    require(isinstance(date, str) and re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', date), 'publication timestamp missing')
    require(datetime.strptime(date, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc) <= now, 'future publication timestamp')
    assets = [a for a in release.get('assets', []) if a.get('name') == 'IOSNext.ipa']
    require(len(assets) == 1, 'missing or ambiguous release asset')
    asset = assets[0]
    require(asset.get('state') == 'uploaded' and asset.get('browser_download_url') == ASSET
            and type(asset.get('size')) is int and asset['size'] == ipa.stat().st_size
            and asset.get('digest') == 'sha256:' + approved_digest, 'release asset readback mismatch')
    require(isinstance(notes, str) and notes.strip() and any(line.startswith('- ') for line in notes.splitlines()), 'canonical release notes required')
    feed = json.loads(raw)
    require(feed.get('identifier') == 'de.nicofroeba16.iosnext.source' and feed.get('sourceURL') == SOURCE, 'wrong source identity')
    apps = [a for a in feed['apps'] if a.get('bundleIdentifier') == 'de.nicofroeba16.iosnext']
    require(len(apps) == 1, 'wrong app identity')
    versions = apps[0]['versions']
    require(bool(versions), 'missing history')
    require(all(v.get('version') != '1.8.0' for v in versions), 'version already present')
    builds = [str(v['buildVersion']) for v in versions if 'buildVersion' in v]
    require(all(re.fullmatch(r'[0-9]+', b) for b in builds) and int(build) > max(map(int, builds), default=0), 'build number not above published history')
    versions.insert(0, {'version': '1.8.0', 'date': date, 'localizedDescription': notes.strip(),
                        'downloadURL': ASSET, 'size': asset['size'], 'minOSVersion': '27.0', 'buildVersion': build})
    return (json.dumps(feed, ensure_ascii=False, indent=2) + '\n').encode()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ('feed', 'ipa', 'release-json', 'notes', 'output'):
        p.add_argument('--' + arg, type=Path, required=True)
    for arg in ('feed-sha256', 'build', 'approved-broker', 'approved-ipa-sha256'):
        p.add_argument('--' + arg, required=True)
    a = p.parse_args()
    require(a.output.resolve() != a.feed.resolve(), 'never modify original source')
    require(a.output.name != 'source.json', 'use a candidate filename, not live source.json')
    result = stage(a.feed.read_bytes(), a.feed_sha256, a.ipa, a.build, a.approved_broker,
                   a.approved_ipa_sha256, json.loads(a.release_json.read_text()),
                   a.notes.read_text(), datetime.now(timezone.utc))
    with a.output.open('xb') as f:
        f.write(result)
    print('CANDIDATE_ONLY: no publication or authorization performed')


if __name__ == '__main__':
    main()
