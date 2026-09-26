"""Check shared tool-version declarations without importing optional packages."""
import json
from pathlib import Path
import sys
import re

root = Path(__file__).resolve().parents[1]
versions = json.loads((root / 'tool/toolchain.json').read_text(encoding='utf-8-sig'))
errors = []
if json.loads((root / '.fvmrc').read_text())['flutter'] != versions['flutter']:
    errors.append('.fvmrc does not match tool/toolchain.json')
if (root / 'website/.node-version').read_text().strip() != versions['node']:
    errors.append('website/.node-version does not match tool/toolchain.json')
package = json.loads((root / 'website/package.json').read_text())
if package['engines']['node'] != versions['node'].split('.')[0] + '.x':
    errors.append('website/package.json permits an unverified Node major')
app_version = re.search(r'^version:\s*(\S+)', (root / 'pubspec.yaml').read_text(), re.M).group(1)
if f'当前版本：**v{app_version}**' not in (root / 'README.md').read_text(encoding='utf-8'):
    errors.append('README current version does not match pubspec.yaml')
for workflow in (root / '.github/workflows').glob('*.yml'):
    for action in re.findall(r'uses:\s*([^\s#]+)', workflow.read_text(encoding='utf-8')):
        if not action.startswith('./') and not re.fullmatch(r'[\w./-]+@[0-9a-f]{40}', action):
            errors.append(f'{workflow.name}: Action must use a full commit SHA: {action}')
for file in ('tool/recommend_dataset/requirements.txt', 'tool/semantic_retrieval/requirements.txt', 'tool/requirements-mirror.txt'):
    if '--hash=sha256:' not in (root / file).read_text():
        errors.append(file + ' is not a hashed dependency lock')
if errors:
    print('\n'.join(errors))
    sys.exit(1)
print('Toolchain declarations and Python dependency locks are consistent.')
