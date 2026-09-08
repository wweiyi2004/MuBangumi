"""Call the debug-only QA extension in our locally launched native probe."""
import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import ProxyHandler, build_opener

parser = argparse.ArgumentParser()
parser.add_argument('--log', type=Path, required=True)
parser.add_argument('--action', choices=['report', 'save', 'pick', 'open', 'screenshot'], default='report')
args = parser.parse_args()
sys.stdout.reconfigure(encoding='utf-8')
log = args.log.read_text(encoding='utf-8-sig', errors='replace')
urls = re.findall(r'A Dart VM Service on .+? is available at: (http://127\.0\.0\.1:\d+/[\w=/+-]+)', log)
if not urls:
    raise SystemExit('The native QA VM service is not ready in the supplied run log.')
base = urls[-1].rstrip('/') + '/'
opener = build_opener(ProxyHandler({}))

def call(method, **params):
    url = base + method + ('?' + urlencode(params) if params else '')
    with opener.open(url, timeout=15) as response:
        result = json.load(response)
    if 'error' in result:
        raise RuntimeError(result['error'].get('message', 'QA extension failed'))
    return result.get('result', result)

vm = call('getVM')
main = next(item for item in vm['isolates'] if item['name'] == 'main')
isolate = call('getIsolate', isolateId=main['id'])
if 'ext.mubangumi.qa' not in isolate.get('extensionRPCs', []):
    raise SystemExit('The connected app is not the native backup QA probe.')
result = call('ext.mubangumi.qa', isolateId=main['id'], action=args.action)
print(json.dumps({'pid': vm['pid'], 'result': result}, ensure_ascii=False, indent=2))
