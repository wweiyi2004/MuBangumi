import json
import pathlib
import urllib.parse
import urllib.request

root=pathlib.Path(__file__).resolve().parents[2]
c=json.loads((root/'.dart_tool/banjian-fixture.json').read_text('utf-8'))
def request(path, body=None, token=None):
    headers={'Content-Type':'application/json'}
    if token: headers['Authorization']='Bearer '+token
    req=urllib.request.Request(c['base']+'/api/'+path,data=json.dumps(body).encode() if body is not None else None,headers=headers)
    with urllib.request.urlopen(req,timeout=45) as response: return json.load(response)
token=request('login',{'password':c['password']})['token']
found=request('search?q='+urllib.parse.quote('芙莉莲'),token=token)['subjects']
assert found
subject=request('subject?id=400602',token=token)
assert subject['id']==400602 and subject['title'] and subject['cover']
result={'publicBangumiSearch':'passed','subjectId':subject['id'],'offlineCoverCached':True}
(root/'docs/qa/banjian-implementation/search-results.json').write_text(json.dumps(result,indent=2),'utf-8')
print(json.dumps(result))
