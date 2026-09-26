"""Local release provenance and publication gates. Never reads credentials."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess

CASES = ('oauth_login', 'saved_session', 'session_expiry', 'website_challenge',
         'network_recovery', 'foreground_resume', 'account_switch', 'pm_delivery', 'group_write')

def git(root: Path, *args: str) -> bytes:
    return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL)

def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''): h.update(chunk)
    return h.hexdigest()

def identity(root: Path) -> dict:
    root = root.resolve()
    commit = git(root, 'rev-parse', 'HEAD').decode().strip()
    dirty = bool(git(root, 'status', '--porcelain', '--untracked-files=normal').strip())
    names = sorted(set(git(root, 'ls-files', '-co', '--exclude-standard', '-z').decode('utf-8').split('\0')) - {''})
    h = hashlib.sha256()
    for name in names:
        file = root / name
        h.update(name.encode('utf-8') + b'\0')
        if file.is_symlink():
            h.update(str(file.readlink()).encode('utf-8'))
        elif file.is_file():
            # Store only a combined fingerprint, never file contents or names.
            h.update(bytes.fromhex(digest(file)))
        else:
            h.update(b'deleted')
        h.update(b'\0')
    return {'commit': commit, 'dirty': dirty, 'fingerprint': h.hexdigest()}

def read_json(path: Path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def write_json(path: Path, value: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temporary.replace(path)

def require_recent(value, label: str):
    try:
        text = str(value).replace('Z', '+00:00')
        # PowerShell's round-trip format emits seven fractional digits;
        # Python 3.10 accepts only millisecond/microsecond precision.
        text = re.sub(r'\.(\d+)(?=[+-]\d\d:\d\d$)', lambda m: '.' + m[1][:6].ljust(6, '0'), text)
        when = datetime.fromisoformat(text)
        if when.tzinfo is None: raise ValueError('timezone required')
        seconds = (datetime.now(timezone.utc) - when).total_seconds()
        if seconds < -300 or seconds > 7 * 24 * 3600: raise ValueError('stale/future')
    except (TypeError, ValueError):
        raise ValueError(f'{label} must have a valid timestamp within the last 7 days') from None

def validate_verification(path: Path, source: dict, target: str) -> dict:
    report = read_json(path)
    if report.get('passed') is not True or report.get('mode') != 'Full':
        raise ValueError('Publication requires a passed Full verification report')
    require_recent(report.get('createdUtc'), 'Verification')
    if report.get('source', {}).get('fingerprint') != source['fingerprint']:
        raise ValueError('Verification report belongs to different source content')
    required = {'flutter-analyze', 'flutter-tests', 'architecture', 'repository-privacy',
                'provenance-tests', 'windows-build' if target == 'windows' else 'android-build'}
    passed = {c['name'] for c in report.get('checks', []) if c.get('status') == 'passed'}
    if not required <= passed: raise ValueError('Verification report is missing required platform checks')
    return {'sha256': digest(path), 'createdUtc': report.get('createdUtc'), 'checks': sorted(passed)}

def validate_acceptance(path: Path, source: dict, target: str, version: str) -> dict:
    report = read_json(path)
    platform = 'windows' if target == 'windows' else 'android'
    if report.get('platform') != platform or report.get('version') != version:
        raise ValueError('Device acceptance does not match the platform/version')
    if report.get('source_fingerprint') != source['fingerprint']:
        raise ValueError('Device acceptance belongs to different source content')
    cases = report.get('cases', {})
    if any(cases.get(case) != 'passed' for case in CASES):
        raise ValueError('Device acceptance has incomplete or failed cases')
    if not report.get('completedUtc') or not report.get('evidence'):
        raise ValueError('Device acceptance requires a completion time and evidence reference')
    require_recent(report['completedUtc'], 'Device acceptance')
    return {'sha256': digest(path), 'platform': platform, 'version': version,
            'completedUtc': report['completedUtc'], 'cases': list(CASES)}

def create(root: Path, *, target: str, kind: str, sdk_metadata: Path,
           version: str, baseline: str = '', allow_dirty: bool = False,
           verification: Path | None = None, acceptance: Path | None = None) -> dict:
    source = identity(root)
    if source['dirty'] and not allow_dirty:
        raise ValueError('Release source is dirty; commit reviewed changes or use --allow-dirty for a local non-publication build')
    sdk = read_json(sdk_metadata)
    toolchain = read_json(root / 'tool/toolchain.json')
    required = toolchain['flutter']
    if sdk.get('frameworkVersion') != required:
        raise ValueError(f'Release requires Flutter {required}')
    for expected,actual in [('flutterFrameworkRevision','frameworkRevision'),('flutterEngineRevision','engineRevision')]:
        if toolchain.get(expected) and sdk.get(actual) != toolchain[expected]:
            raise ValueError('Local Flutter framework/engine does not match the pinned official SDK')
    publication = kind in ('shorebird-release', 'shorebird-patch')
    if publication and source['dirty']:
        raise ValueError('Shorebird publication requires committed, clean source')
    if publication and (verification is None or acceptance is None):
        raise ValueError('Publication requires --verification and --acceptance records')
    return {
        'schema': 1, 'createdUtc': datetime.now(timezone.utc).isoformat(), 'status': 'building',
        'target': target, 'kind': kind, 'version': version, 'baseline': baseline or None,
        'source': source,
        'compilerSelection': 'Shorebird CLI/baseline; local SDK metadata below is not proof of the Shorebird engine' if kind.startswith('shorebird-') else 'pinned Flutter SDK',
        'sdk': {k: sdk.get(k) for k in ('frameworkVersion','dartSdkVersion','frameworkRevision','engineRevision','channel')},
        'locks': {str(p): digest(root / p) for p in (Path('pubspec.lock'), Path('packages/banjian_server/pubspec.lock'), Path('tool/toolchain.json')) if (root / p).is_file()},
        'verification': validate_verification(verification, source, target) if verification else None,
        'acceptance': validate_acceptance(acceptance, source, target, baseline or version) if acceptance else None,
        'artifacts': [], 'symbols': [], 'publication': None,
    }

def artifact_record(root: Path, file: Path) -> dict:
    full = file.resolve()
    relative = full.relative_to(root.resolve())
    if relative.parts[0] not in ('build','dist','release-symbols') or full.suffix.lower() not in ('.apk','.aab','.exe','.so','.dll','.zip','.symbols','.pdb'):
        raise ValueError('Only build artifacts/symbols under build, dist or release-symbols can enter release records')
    if not full.is_file() or full.stat().st_size <= 0: raise ValueError('Artifact missing or empty')
    return {'path': relative.as_posix(), 'bytes': full.stat().st_size, 'sha256': digest(full)}

def finish(root: Path, manifest: Path, artifacts: list[Path], symbols: list[Path], *, failed=False):
    data = read_json(manifest)
    if failed:
        if data['status'] != 'source-changed': data['status'] = 'failed'
    elif identity(root)['fingerprint'] != data['source']['fingerprint']:
        data['status'] = 'source-changed'
        write_json(manifest, data)
        raise ValueError('Source changed during build; receipt cannot establish reproducibility')
    else:
        data['artifacts'] = [artifact_record(root, p) for p in artifacts]
        data['symbols'] = [artifact_record(root, p) for p in symbols]
        data['status'] = 'awaiting-patch-receipt' if data['kind'] == 'shorebird-patch' else 'dry-run-passed' if data['kind'] == 'dry-run' else 'built'
    data['finishedUtc'] = datetime.now(timezone.utc).isoformat()
    write_json(manifest, data)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    identify = sub.add_parser('identity'); identify.add_argument('--root',type=Path,default=Path.cwd())
    make = sub.add_parser('create')
    make.add_argument('--root',type=Path,default=Path.cwd()); make.add_argument('--out',type=Path,required=True)
    make.add_argument('--sdk-metadata',type=Path,required=True); make.add_argument('--target',choices=['windows','apk','appbundle'],required=True)
    make.add_argument('--kind',choices=['build','dry-run','shorebird-release','shorebird-patch'],required=True)
    make.add_argument('--version',required=True); make.add_argument('--baseline',default=''); make.add_argument('--allow-dirty',action='store_true')
    make.add_argument('--verification',type=Path); make.add_argument('--acceptance',type=Path)
    done = sub.add_parser('finish'); done.add_argument('--root',type=Path,default=Path.cwd()); done.add_argument('--manifest',type=Path,required=True)
    done.add_argument('--artifact',type=Path,action='append',default=[]); done.add_argument('--symbol',type=Path,action='append',default=[]); done.add_argument('--failed',action='store_true')
    receipt = sub.add_parser('patch-receipt'); receipt.add_argument('--manifest',type=Path,required=True)
    receipt.add_argument('--root',type=Path,default=Path.cwd()); receipt.add_argument('--artifact',type=Path,action='append',required=True)
    receipt.add_argument('--patch-number',type=int,required=True); receipt.add_argument('--server-id',required=True); receipt.add_argument('--channel',choices=['staging','stable'],required=True)
    args = parser.parse_args()
    if args.action == 'identity': print(json.dumps(identity(args.root))); return
    if args.action == 'create':
        value=create(args.root,target=args.target,kind=args.kind,sdk_metadata=args.sdk_metadata,version=args.version,
          baseline=args.baseline,allow_dirty=args.allow_dirty,verification=args.verification,acceptance=args.acceptance)
        write_json(args.out,value); return
    if args.action == 'finish': finish(args.root,args.manifest,args.artifact,args.symbol,failed=args.failed); return
    data=read_json(args.manifest)
    if data['kind']!='shorebird-patch' or data['status']!='awaiting-patch-receipt' or args.patch_number<=0 or not re.fullmatch(r'\d+',args.server_id):
        raise ValueError('Patch receipt does not describe a completed pending patch upload')
    if identity(args.root)['fingerprint'] != data['source']['fingerprint']: raise ValueError('Patch source content has changed')
    data['artifacts']=[artifact_record(args.root,p) for p in args.artifact]
    data['publication']={'patchNumber':args.patch_number,'serverId':args.server_id,'channel':args.channel,'evidence':'operator-verified CLI receipt'}
    data['status']='receipt-recorded';write_json(args.manifest,data)

if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
