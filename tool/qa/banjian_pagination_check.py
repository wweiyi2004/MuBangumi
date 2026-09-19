"""Run against banjian_web_fixture.dart --many-comments (isolated local data)."""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

fixture=json.loads(Path('.dart_tool/banjian-fixture.json').read_text(encoding='utf-8-sig'))
base=fixture['base']
with sync_playwright() as p:
    browser=p.chromium.launch(channel='chrome',headless=True)
    context=browser.new_context(viewport={'width':1440,'height':900})
    errors=[]
    admin=context.new_page();admin.on('pageerror',lambda e:errors.append(str(e)))
    admin.goto(base+'/admin');admin.locator('#password').fill(fixture['password']);admin.locator('#login button[type=submit], #login button').last.click()
    admin.get_by_role('button',name='打开活动',exact=True).first.click()
    admin.get_by_role('button',name='查看全部 123 条短评',exact=True).click()
    admin.locator('#modal .comment').nth(49).wait_for()
    assert admin.locator('#modal .comment').count()==50
    admin.locator('#modal').get_by_role('button',name='下一页',exact=True).click()
    admin.locator('#modal').get_by_text('第 2 页',exact=True).wait_for()
    admin.locator('#modal').get_by_role('button',name='下一页',exact=True).click()
    admin.locator('#modal').get_by_text('第 3 页',exact=True).wait_for()
    assert admin.locator('#modal .comment').count()==23
    assert admin.locator('#modal').get_by_role('button',name='下一页',exact=True).is_disabled()
    participant=context.new_page();participant.on('pageerror',lambda e:errors.append(str(e)))
    participant.goto(base+'/join/'+fixture['id']+'#invite='+fixture['invite'])
    participant.locator('#name').fill('网页测试成员');participant.locator('#join button').click()
    participant.locator('#comment-draft').fill('留下自己的短评')
    participant.locator('[data-action="submit-comment"]').click()
    participant.get_by_text('匿名短评已确认',exact=True).wait_for()
    participant.locator('[data-action="participant-sheet"][data-id="comments"]').click()
    participant.get_by_role('button',name='查看全部 124 条短评',exact=True).click()
    participant.locator('#modal .comment').nth(49).wait_for()
    login=context.request.post(base+'/api/login',data={'password':fixture['password']}).json()
    headers={'Authorization':'Bearer '+login['token']}
    state=context.request.get(base+'/api/state?event='+fixture['id'],headers=headers).json()
    command={'op':'pagination-privacy-toggle','event':fixture['id'],'version':state['version'],'action':'comments','round':state['current'],'value':False}
    response=context.request.post(base+'/api/admin',headers=headers,data=command);assert response.ok,response.text()
    participant.locator('#modal').get_by_text('匿名短评 · 1 条',exact=True).wait_for()
    assert participant.locator('#modal .comment').count()==1
    assert '留下自己的短评' in participant.locator('#modal').inner_text()
    exported=context.request.get(base+'/api/export?event='+fixture['id']+'&format=json',headers=headers).json()
    assert len(exported['rounds'][0]['comments'])==124
    assert 'members' not in exported and 'invite' not in exported
    assert not errors,errors
    report={'comment_pages':[50,50,23],'participant_visibility_change':'only own comment remains','exported_comments':124,'javascript_errors':errors}
    Path('.dart_tool/banjian-pagination-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False));browser.close()
