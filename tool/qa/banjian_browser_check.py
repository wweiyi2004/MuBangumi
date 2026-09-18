"""Real local service + browser integration checks; fixture data only."""
import json
import pathlib
import time
import uuid
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONFIG = json.loads((ROOT / '.dart_tool/banjian-fixture.json').read_text('utf-8'))
OUT = ROOT / 'docs/qa/banjian-implementation'
OUT.mkdir(parents=True, exist_ok=True)
base = CONFIG['base']
url = f"{base}/join/{CONFIG['id']}#invite={CONFIG['invite']}"

with sync_playwright() as p:
    try:
        browser = p.chromium.launch(headless=True)
    except Exception:
        browser = p.chromium.launch(channel='chrome', headless=True)
    admin_context = browser.new_context(viewport={'width': 1440, 'height': 1050})
    admin = admin_context.new_page()
    errors = []
    admin.on('pageerror', lambda e: errors.append(str(e)))
    admin.on('dialog', lambda d: d.accept('周五的番键会 · 核对测试' if d.type == 'prompt' else None))
    admin.goto(base + '/admin')
    admin.locator('#password').fill(CONFIG['password'])
    admin.get_by_role('button', name='进入管理', exact=True).click()
    admin.get_by_role('button',name='切换明暗主题',exact=True).click()
    assert admin.evaluate('document.documentElement.dataset.theme')=='light'
    admin.get_by_role('button',name='切换明暗主题',exact=True).click()
    assert admin.evaluate('document.documentElement.dataset.theme')=='dark'
    admin.get_by_role('button',name='切换明暗主题',exact=True).click()
    assert admin.evaluate("JSON.parse(localStorage.getItem('banjian:theme'))")=='system'
    admin.get_by_role('button', name='打开活动', exact=True).first.click()
    admin.get_by_role('heading', name='正在鉴赏', exact=True).wait_for()
    admin.screenshot(path=str(OUT / 'admin-live.png'), full_page=True)
    token = admin.evaluate("sessionStorage.getItem('banjian-admin')")
    def api(path, data=None):
        if data is None:
            r = admin_context.request.get(base + '/api/' + path, headers={'Authorization': 'Bearer ' + token})
        else:
            r = admin_context.request.post(base + '/api/' + path, data=data, headers={'Authorization': 'Bearer ' + token})
        assert r.ok, r.text()
        return r.json()

    participant_context = browser.new_context(viewport={'width': 390, 'height': 844})
    participant = participant_context.new_page()
    participant.on('pageerror', lambda e: errors.append(str(e)))
    # Ordinary browsers ignore the native fallback-address fragment and still
    # enter through the QR's normal HTTP URL.
    participant.goto(url + '&hosts=192.168.137.1')
    participant.get_by_role('heading', name='周五的番键会', exact=True).wait_for()
    participant.screenshot(path=str(OUT / 'web-join-live.png'), full_page=True)
    participant.locator('#name').fill('网页体验者')
    participant.get_by_role('button', name='加入番键会 →', exact=True).click()
    participant.get_by_role('button', name='提交评分', exact=True).wait_for()
    participant.locator('[data-action="score"][data-score="9"]').click()
    participant.get_by_role('button', name='提交评分', exact=True).click()
    participant.get_by_text('已确认评分：9 分', exact=False).wait_for()
    participant.get_by_role('button',name='统计',exact=True).click()
    participant.get_by_text('结果暂未公布，个人分数仅自己可见。',exact=True).wait_for()
    participant.locator('#modal [data-action="close-modal"]').click()
    participant.locator('#comment-draft').fill('细节很喜欢，想再看一次。')
    participant.get_by_role('button', name='匿名发送', exact=True).click()
    participant.get_by_role('button',name='评论墙',exact=True).click()
    participant.locator('.comment p').filter(has_text='细节很喜欢，想再看一次。').wait_for()
    admin.get_by_text('细节很喜欢，想再看一次。', exact=True).wait_for()
    participant.locator('#modal [data-action="close-modal"]').click()
    participant.screenshot(path=str(OUT / 'web-participation-live.png'), full_page=True)

    # Input survives live pushes and focus/caret stays in the editor.
    participant.locator('#comment-draft').fill('正在输入，不要丢失')
    admin.locator('[data-action="comments"]').click()
    assert participant.locator('#comment-draft').input_value() == '正在输入，不要丢失'
    assert participant.locator('#comment-draft').evaluate('(el)=>el===document.activeElement')
    participant.get_by_role('button',name='评论墙',exact=True).click()
    participant.get_by_text('节奏很舒服，细节值得再看一遍。', exact=True).wait_for()
    participant.locator('#modal [data-action="close-modal"]').click()
    admin.locator('[data-action="publish"]').click()
    participant.get_by_role('button',name='统计',exact=True).click()
    participant.get_by_text('平均评分', exact=True).wait_for()
    participant.locator('#modal [data-action="close-modal"]').click()
    admin.get_by_role('button', name='成员', exact=True).click()
    assert admin.get_by_text('网页体验者', exact=True).count() == 1
    assert admin.locator('.member').filter(has_text='网页体验者').inner_text().strip().endswith('已评分')
    admin.screenshot(path=str(OUT / 'members-live.png'), full_page=True)
    admin.locator('#modal [data-action="close-modal"]').click()
    admin.get_by_role('button', name='现场控制', exact=True).click()

    # Participant QR is served as a real image and must decode to this room.
    admin.get_by_role('button', name='邀请参与', exact=True).click()
    for _ in range(100):
        if admin.locator('#invite-qr').evaluate('(el)=>el.naturalWidth > 0'):
            break
        time.sleep(.05)
    assert admin.locator('#invite-qr').evaluate('(el)=>el.naturalWidth > 0')
    admin.locator('#invite-qr').screenshot(path=str(OUT / 'participant-qr.png'))
    assert admin.locator('#invite-link').input_value() == url
    admin.locator('#modal [data-action="close-modal"]').click()

    # Explicitly inspect exports: no participant identity or private score mapping.
    record = api('export?event=' + CONFIG['id'] + '&format=json')
    assert 'members' not in record and 'invite' not in record
    assert '网页体验者' not in json.dumps(record, ensure_ascii=False)
    assert 'scores' not in record['rounds'][0]

    # Offline durable score queue resumes without duplicating the participant.
    participant_context.set_offline(True)
    participant.locator('[data-action="score"][data-score="7"]').click()
    participant.get_by_role('button', name='更新我的评分', exact=True).click()
    for _ in range(100):
        if participant.evaluate("JSON.parse(localStorage.getItem('banjian:'+location.pathname.split('/')[2]+':pending')).length===1"):
            break
        time.sleep(.05)
    assert participant.evaluate("JSON.parse(localStorage.getItem('banjian:'+location.pathname.split('/')[2]+':pending')).length===1")
    participant_context.set_offline(False)
    participant.reload()
    participant.get_by_text('已确认评分：7 分', exact=False).wait_for(timeout=15000)

    # Native-style mobile web and small management screens don't overflow.
    responsive = []
    for page, widths in [(participant, [352, 390, 768]), (admin, [352, 768, 1440])]:
        for width in widths:
            page.set_viewport_size({'width': width, 'height': 900})
            for tab in (['control', 'playlist', 'results', 'members'] if page == admin else [None]):
                if page==admin and page.locator('#modal').evaluate('(el)=>el.open'):
                    page.locator('#modal [data-action="close-modal"]').click()
                if tab:
                    page.locator(f'[data-action="tab"][data-id="{tab}"]').click()
                assert page.evaluate('document.documentElement.scrollWidth <= innerWidth + 1'), (width, tab)
                responsive.append((width, tab))
    if admin.locator('#modal').evaluate('(el)=>el.open'):
        admin.locator('#modal [data-action="close-modal"]').click()
    admin.set_viewport_size({'width':1440,'height':900})
    admin.get_by_role('button', name='现场控制', exact=True).click()
    admin_context.set_offline(False)
    admin.emulate_media(color_scheme='dark')
    admin.screenshot(path=str(OUT / 'admin-live-dark.png'), full_page=True)

    # The server commits but the response is lost: reuse the durable operation
    # receipt rather than running the management command a second time.
    def lose_admin_response(route):
        response = route.fetch()
        assert response.ok
        route.abort('failed')
    admin.route('**/api/admin', lose_admin_response, times=1)
    admin.get_by_role('button', name='修改活动名称', exact=True).click()
    admin.get_by_role('button', name='核对未确认操作', exact=True).wait_for()
    version = api('state?event=' + CONFIG['id'])['version']
    admin.get_by_role('button', name='核对未确认操作', exact=True).click()
    for _ in range(100):
        if admin.get_by_role('button', name='核对未确认操作', exact=True).count() == 0:
            break
        time.sleep(.05)
    assert api('state?event=' + CONFIG['id'])['version'] == version
    assert admin.get_by_role('button', name='核对未确认操作', exact=True).count() == 0

    for width,height in [(390,844),(360,640),(352,700),(768,900)]:
        participant.set_viewport_size({'width':width,'height':height})
        participant.evaluate('()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))')
        assert participant.evaluate('document.documentElement.scrollHeight <= innerHeight + 1'), (width,height,participant.evaluate('({scroll:document.documentElement.scrollHeight,height:innerHeight,vv:visualViewport.height,body:document.body.clientHeight})'))
        assert participant.locator('.participant-well').evaluate('(el)=>el.scrollHeight <= el.clientHeight + 1'), (width,height)
        for action in ['submit-score','submit-comment']:
            rect=participant.locator('[data-action='+action+']').bounding_box()
            assert rect['y']+rect['height'] <= height, (width,height,action)
    for width,height in [(1440,900),(1280,720),(1100,800),(1280,640),(1024,640)]:
        admin.set_viewport_size({'width':width,'height':height})
        admin.evaluate('()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))')
        assert admin.evaluate('document.documentElement.scrollHeight <= innerHeight + 1'), (width,height)
        assert admin.locator('.arena-current').evaluate('(el)=>el.scrollHeight <= el.clientHeight + 1'), (width,height,'main controls')
    admin.set_viewport_size({'width':1440,'height':900})
    # Closed round locks native protocol as well as visible controls.
    admin.get_by_role('button', name='截止本轮', exact=True).click()
    participant.get_by_text('已截止，目前不能提交。', exact=False).wait_for()
    assert participant.get_by_role('button', name='更新我的评分', exact=True).is_disabled()
    assert participant.locator('#comment-draft').is_disabled()

    # End the old room from another admin while its QR is on screen. A fresh
    # activity with the same title must get a different, joinable invitation.
    admin.get_by_role('button', name='邀请参与', exact=True).click()
    admin.locator('#invite-link').wait_for()
    previous=api('state?event='+CONFIG['id'])
    api('admin',{'op':str(uuid.uuid4()),'event':CONFIG['id'],'version':previous['version'],'action':'end'})
    for _ in range(100):
        if not admin.locator('#modal').evaluate('(el)=>el.open'):
            break
        time.sleep(.05)
    assert not admin.locator('#modal').evaluate('(el)=>el.open')
    assert admin.get_by_role('button', name='邀请参与', exact=True).is_disabled()
    fresh=api('admin',{'op':str(uuid.uuid4()),'action':'create','title':previous['title']})
    admin.get_by_role('button', name='返回当前活动', exact=True).click()
    admin.get_by_role('button', name='邀请参与', exact=True).click()
    new_link=admin.locator('#modal[open] #invite-link').input_value()
    assert '/join/'+fresh['id']+'#' in new_link and new_link!=url
    newcomer_context=browser.new_context(viewport={'width':390,'height':844})
    newcomer=newcomer_context.new_page()
    newcomer.goto(url)
    newcomer.get_by_text('这张二维码对应的活动已结束',exact=True).wait_for()
    assert newcomer.get_by_role('button',name='活动已经结束',exact=True).is_disabled()
    newcomer.goto(new_link)
    newcomer.get_by_role('button',name='加入番键会 →',exact=True).wait_for()
    assert newcomer.get_by_text('这张二维码对应的活动已结束',exact=True).count()==0
    newcomer.locator('#name').fill('新场参与者')
    newcomer.get_by_role('button',name='加入番键会 →',exact=True).click()
    newcomer.get_by_text('主持人正在准备番单，请稍等…',exact=True).wait_for()
    newcomer_context.close()
    assert not errors, errors
    result={'browser_checks':'passed','responsive_cases':len(responsive),'single_screen_participant_sizes':['390x844','360x640','352x700','768x900'],'single_screen_admin_sizes':['1440x900','1280x720','1100x800','1280x640','1024x640'],'theme_switch':'passed','javascript_errors':errors}
    (OUT / 'browser-results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),'utf-8')
    print(json.dumps(result,ensure_ascii=False))
    browser.close()
