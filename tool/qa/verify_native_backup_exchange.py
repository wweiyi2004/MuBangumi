"""Verify the synthetic native exchange artifacts without an app session."""
import hashlib
import json
from pathlib import Path

root = Path('.dart_tool/m6-native')
paths = {
    'windows_native_saved': root / 'windows-native-save.json',
    'windows_native_reference': root / 'windows-native-save-reference.json',
    'android_native_saved': root / 'android/android-native-save.json',
    'android_native_reference': root / 'android/android-export.json',
    'android_roundtrip': root / 'android/android-roundtrip.json',
    'windows_roundtrip': root / 'windows/expected.json',
}
archives = {}
hashes = {}
for name, path in paths.items():
    raw = path.read_bytes()
    archive = json.loads(raw)
    payload = {key: value for key, value in archive.items() if key != 'checksum'}
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
    assert hashlib.sha256(encoded).hexdigest() == archive['checksum'], name
    assert archive['owner'] == {'id': 11, 'username': 'alice'}, name
    assert len(archive['data']) == 8, name
    for excluded in (b'OTHER-OWNER', b'CACHE-SECRET', b'CACHE-ITEM'):
        assert excluded not in raw, (name, excluded)
    archives[name] = archive
    hashes[name] = hashlib.sha256(raw).hexdigest()

for platform in ('windows', 'android'):
    assert hashes[f'{platform}_native_saved'] == hashes[f'{platform}_native_reference']

original = archives['windows_native_reference']['data']
assert archives['android_roundtrip']['data'] == original
assert archives['windows_roundtrip']['data'] == original

for report_path in (root / 'windows-android-import-report.json', root / 'windows-roundtrip-report.json',
                    root / 'android/android-report.json'):
    report = json.loads(report_path.read_text(encoding='utf-8'))
    assert report['cross_file_verified'] is True, report_path
    assert report['last_import']['changed'] is True, report_path
    assert report['bangumi_sync_calls'] == 0, report_path

result = {'native_save_bytes_equal': True, 'windows_android_windows_data_equal': True,
          'categories': 8, 'foreign_account_and_cache_markers_excluded': True, 'file_sha256': hashes}
(root / 'exchange-verification.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
