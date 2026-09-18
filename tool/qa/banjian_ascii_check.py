"""Exercise the real web loading banner and touch pull without writing votes."""
import json,pathlib,time
from playwright.sync_api import sync_playwright
root=pathlib.Path(__file__).resolve().parents[2]
c=json.loads((root/'.dart_tool/banjian-fixture.json').read_text('utf-8'))
with sync_playwright() as p:
    browser=p.chromium.launch(channel='chrome',headless=True)
    page=browser.new_page(viewport={'width':390,'height':844},has_touch=True)
    errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
    held=[];requests=[]
    page.route('**/api/preview',lambda route:held.append(route))
    page.on('request',lambda r:requests.append(r.url) if r.url.endswith('/api/preview') else None)
    page.goto(f"{c['base']}/join/{c['id']}#invite={c['invite']}")
    page.locator('#ascii-loading.visible').wait_for()
    first=page.locator('#ascii-loading pre').inner_text()
    page.wait_for_timeout(260)
    assert page.locator('#ascii-loading pre').inner_text()!=first
    page.screenshot(path=str(root/'docs/qa/banjian-implementation/web-ascii-loading.png'))
    for route in held[:]: route.continue_()
    page.unroute('**/api/preview')
    page.locator('#ascii-loading').wait_for(state='hidden')
    def pull(distance):
        page.evaluate('''distance=>{const el=document.querySelector('.join h1');const rect=el.getBoundingClientRect();const x=rect.left+10,y=rect.top+5;
          const touch=(dy)=>new Touch({identifier:1,target:el,clientX:x,clientY:y+dy});
          el.dispatchEvent(new TouchEvent('touchstart',{bubbles:true,cancelable:true,touches:[touch(0)]}));
          el.dispatchEvent(new TouchEvent('touchmove',{bubbles:true,cancelable:true,touches:[touch(distance)]}));
          el.dispatchEvent(new TouchEvent('touchend',{bubbles:true,cancelable:true,touches:[]}));}''',distance)
    baseline=len(requests);pull(25);page.wait_for_timeout(300);assert len(requests)==baseline
    pull(140);page.locator('#ascii-loading.visible').wait_for();page.locator('#ascii-loading').wait_for(state='hidden');assert len(requests)==baseline+1
    assert not errors,errors
    result={'first_load_slides_in':True,'character_frames_loop':True,'short_pull_cancels':True,'released_pull_refreshes_once':True,'banner_retracts':True,'javascript_errors':errors}
    (root/'docs/qa/banjian-implementation/ascii-results.json').write_text(json.dumps(result,indent=2),'utf-8')
    print(json.dumps(result));browser.close()
