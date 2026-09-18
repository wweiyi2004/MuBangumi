"""Check the compiled standalone Windows bundle without using app data."""
import json
import os
import pathlib
import re
import subprocess
import tempfile
import urllib.request

root=pathlib.Path(__file__).resolve().parents[2]
bundle=root/'packages/banjian_server/build/bundle'
with tempfile.TemporaryDirectory(prefix='banjian-cli-') as directory:
    target=pathlib.Path(directory).resolve()
    assert target.parent==pathlib.Path(tempfile.gettempdir()).resolve() and target.name.startswith('banjian-cli-')
    env={**os.environ,'BANJIAN_ADMIN_PASSWORD':'isolated-cli-test-password','BANJIAN_DATA':directory,'BANJIAN_WEB':str(bundle/'web'),'BANJIAN_BIND':'127.0.0.1','PORT':'0'}
    def start():
        process=subprocess.Popen([str(bundle/'bin/server.exe')],cwd=bundle,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
        line=process.stdout.readline()
        match=re.search(r'listening on (\d+)',line)
        if not match:
            process.terminate()
            raise RuntimeError('Compiled server failed to become ready')
        return process,'http://127.0.0.1:'+match.group(1)
    def request(base,path,body=None,token=None):
        headers={'Content-Type':'application/json'}
        if token:headers['Authorization']='Bearer '+token
        req=urllib.request.Request(base+path,data=json.dumps(body).encode() if body is not None else None,headers=headers)
        with urllib.request.urlopen(req,timeout=10) as r:return r.read()
    process,base=start()
    try:
        assert b'app.js' in request(base,'/admin')
        assert b'function render' in request(base,'/app.js')
        token=json.loads(request(base,'/api/login',{'password':env['BANJIAN_ADMIN_PASSWORD']}))['token']
        event=json.loads(request(base,'/api/admin',{'op':'compiled-create-once','action':'create','title':'Compiled fixture'},token))['id']
    finally:
        process.terminate();process.wait(timeout=10)
    process,base=start()
    try:
        token=json.loads(request(base,'/api/login',{'password':env['BANJIAN_ADMIN_PASSWORD']}))['token']
        history=json.loads(request(base,'/api/history',token=token))['events']
        assert len(history)==1 and history[0]['id']==event
        result={'compiledWindowsBundle':'passed','staticAssets':'passed','processRestartPersistence':'passed'}
        (root/'docs/qa/banjian-implementation/cli-results.json').write_text(json.dumps(result,indent=2),'utf-8')
        print(json.dumps(result))
    finally:
        process.terminate();process.wait(timeout=10)
