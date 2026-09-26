import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from datetime import datetime, timezone

spec=importlib.util.spec_from_file_location('provenance',Path(__file__).resolve().parents[1]/'release_provenance.py')
provenance=importlib.util.module_from_spec(spec);spec.loader.exec_module(provenance)

class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='mubangumi-provenance-')
        self.root=Path(self.temp.name)
        (self.root/'tool').mkdir();(self.root/'tool/toolchain.json').write_text('{"flutter":"3.44.7"}')
        (self.root/'.gitignore').write_text('build/\nrelease-symbols/\nconfig/\n')
        (self.root/'pubspec.lock').write_text('locked fixture')
        self.sdk=self.root/'config/sdk.json';self.sdk.parent.mkdir()
        self.sdk.write_text('{"frameworkVersion":"3.44.7","engineRevision":"fixture"}')
        self.manifest=self.root/'release-symbols/fixture/provenance.json'
        self.git('init','--quiet');self.git('add','.');self.git('-c','user.name=Fixture','-c','user.email=fixture@example.test','commit','-qm','fixture')
    def tearDown(self): self.temp.cleanup()
    def git(self,*args): return subprocess.check_output(['git',*args],cwd=self.root,stderr=subprocess.DEVNULL)
    def create(self,**kwargs):
        return provenance.create(self.root,target='apk',kind=kwargs.pop('kind','build'),version='2.3.1+4029',sdk_metadata=self.sdk,**kwargs)
    def records(self):
        source=provenance.identity(self.root)
        verification=self.root/'config/verification.json'
        verification.write_text(json.dumps({'passed':True,'mode':'Full','createdUtc':datetime.now(timezone.utc).isoformat(),'source':source,'checks':[
          {'name':x,'status':'passed'} for x in ['flutter-analyze','flutter-tests','architecture','repository-privacy','provenance-tests','android-build']]}))
        acceptance=self.root/'config/acceptance.json'
        acceptance.write_text(json.dumps({'platform':'android','version':'2.3.1+4029','source_fingerprint':source['fingerprint'],
          'completedUtc':datetime.now(timezone.utc).isoformat(),'evidence':'synthetic fixture only','cases':dict.fromkeys(provenance.CASES,'passed')}))
        return verification,acceptance
    def test_dirty_source_is_rejected_and_local_override_is_explicit(self):
        (self.root/'new.dart').write_text('changed')
        with self.assertRaises(ValueError):self.create()
        self.assertTrue(self.create(allow_dirty=True)['source']['dirty'])
        with self.assertRaises(ValueError):self.create(kind='shorebird-release',allow_dirty=True)
    def test_publication_requires_matching_verification_and_manual_acceptance(self):
        with self.assertRaises(ValueError):self.create(kind='shorebird-release')
        verification,acceptance=self.records()
        record=self.create(kind='shorebird-release',verification=verification,acceptance=acceptance)
        self.assertIn('sha256',record['acceptance'])
        value=json.loads(acceptance.read_text());value['cases']['pm_delivery']='pending';acceptance.write_text(json.dumps(value))
        with self.assertRaises(ValueError):self.create(kind='shorebird-release',verification=verification,acceptance=acceptance)
    def test_stale_source_report_is_rejected(self):
        verification,acceptance=self.records()
        data=json.loads(verification.read_text());data['source']['fingerprint']='old';verification.write_text(json.dumps(data))
        with self.assertRaises(ValueError):self.create(kind='shorebird-release',verification=verification,acceptance=acceptance)
    def test_artifact_hashes_and_source_drift(self):
        provenance.write_json(self.manifest,self.create())
        artifact=self.root/'build/app.apk';artifact.parent.mkdir();artifact.write_bytes(b'fixture APK')
        provenance.finish(self.root,self.manifest,[artifact],[])
        data=provenance.read_json(self.manifest);self.assertEqual(data['status'],'built')
        self.assertEqual(data['artifacts'][0]['sha256'],provenance.digest(artifact))
        (self.root/'source.dart').write_text('changed during build')
        with self.assertRaises(ValueError):provenance.finish(self.root,self.manifest,[artifact],[])
        self.assertEqual(provenance.read_json(self.manifest)['status'],'source-changed')
    def test_credentials_cannot_be_listed_as_artifacts(self):
        secret=self.root/'config/oauth.local.json';secret.write_text('never record credentials')
        with self.assertRaises(ValueError):provenance.artifact_record(self.root,secret)
        self.assertNotIn('never record',json.dumps(self.create()))
    def test_sdk_version_is_checked(self):
        self.sdk.write_text('{"frameworkVersion":"3.44.0"}')
        with self.assertRaises(ValueError):self.create()
    def test_stale_acceptance_is_rejected(self):
        verification,acceptance=self.records()
        data=json.loads(acceptance.read_text());data['completedUtc']='2001-01-01T00:00:00Z';acceptance.write_text(json.dumps(data))
        with self.assertRaises(ValueError):self.create(kind='shorebird-release',verification=verification,acceptance=acceptance)
    def test_dotnet_round_trip_timestamp_is_accepted(self):
        text=datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')+'7Z'
        provenance.require_recent(text,'PowerShell fixture')
    def test_same_version_with_a_different_engine_is_rejected(self):
        (self.root/'tool/toolchain.json').write_text('{"flutter":"3.44.7","flutterEngineRevision":"official"}')
        with self.assertRaisesRegex(ValueError,'engine'):
            self.create(allow_dirty=True)

if __name__=='__main__':unittest.main()
