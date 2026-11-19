import copy
from datetime import datetime, timezone
import hashlib
import json
import unittest
from stage_sidestore_feed import stage, SOURCE, ASSET
from verify_release_ipa import Checks

class StageChecks(unittest.TestCase):
    def setUp(self):
        self.fixture = Checks()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.fixture.make()
        self.ipa = self.fixture.path
        self.digest = hashlib.sha256(self.ipa.read_bytes()).hexdigest()
        self.feed = {'identifier':'de.nicofroeba16.iosnext.source','sourceURL':SOURCE,'apps':[{'bundleIdentifier':'de.nicofroeba16.iosnext','versions':[{'version':'1.7.3','buildVersion':'31','other':'preserve'}]}]}
        self.release = {'tag_name':'v1.8.0','draft':False,'prerelease':False,'published_at':'2026-11-19T00:00:00Z','assets':[{'name':'IOSNext.ipa','state':'uploaded','browser_download_url':ASSET,'size':self.ipa.stat().st_size,'digest':'sha256:'+self.digest}]}
        self.now = datetime(2026,11,19,12,tzinfo=timezone.utc)
    def call(self, **changes):
        raw = json.dumps(self.feed).encode()
        args = dict(raw=raw,expected_feed_sha=hashlib.sha256(raw).hexdigest(),ipa=self.ipa,build='42',broker=self.fixture.broker,approved_digest=self.digest,release=self.release,notes='- Fixture only',now=self.now)
        args.update(changes)
        return stage(**args)
    def test_preserve_history(self):
        before = copy.deepcopy(self.feed)
        out = json.loads(self.call())
        self.assertEqual(out['apps'][0]['versions'][1:], before['apps'][0]['versions'])
        self.assertEqual(out['apps'][0]['versions'][0]['date'], self.release['published_at'])
        self.assertEqual(self.feed, before)
    def test_stale_feed(self):
        with self.assertRaises(ValueError): self.call(expected_feed_sha='0'*64)
    def test_wrong_digest(self):
        with self.assertRaises(ValueError): self.call(approved_digest='0'*64)
    def test_bad_release(self):
        for key,value in [('draft',True),('prerelease',True),('tag_name','v1.7.3'),('published_at','2026-11-20T00:00:00Z')]:
            with self.subTest(key=key), self.assertRaises(ValueError): self.call(release={**self.release,key:value})
    def test_wrong_asset(self):
        for key,value in [('size',1),('digest','sha256:'+'0'*64),('state','new'),('browser_download_url','https://example.invalid')]:
            with self.subTest(key=key), self.assertRaises(ValueError): self.call(release={**self.release,'assets':[{**self.release['assets'][0],key:value}]})
    def test_duplicate_version(self):
        self.feed['apps'][0]['versions'].append({'version':'1.8.0','buildVersion':'41'})
        with self.assertRaises(ValueError): self.call()
    def test_duplicate_build(self):
        self.feed['apps'][0]['versions'][0]['buildVersion']='42'
        with self.assertRaises(ValueError): self.call()
    def test_wrong_source(self):
        self.feed['sourceURL']='https://example.invalid'
        with self.assertRaises(ValueError): self.call()
    def test_missing_notes(self):
        with self.assertRaises(ValueError): self.call(notes='')

if __name__ == '__main__': unittest.main(verbosity=2)
