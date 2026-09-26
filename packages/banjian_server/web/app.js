'use strict';
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function secret(){const bytes=new Uint8Array(24);crypto.getRandomValues(bytes);return btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=/g,'');}
function read(key, fallback=null){try{return JSON.parse(localStorage.getItem(key))??fallback;}catch{return fallback;}}
function save(key,value){try{localStorage.setItem(key,JSON.stringify(value));return true;}catch{toast('浏览器无法保存，请允许本地存储后再提交');return false;}}
const admin=location.pathname==='/admin';
const eventId=location.pathname.startsWith('/join/')?location.pathname.split('/')[2]:null;
const storageKey='banjian:'+eventId;
let identity=read(storageKey,{}), token=admin?sessionStorage.getItem('banjian-admin')||'':identity.token||'', event=null, events=[], tab='control', online=false, socket=null, reconnect=null, busy=false, flushing=false;
let invite=new URLSearchParams(location.hash.slice(1)).get('invite')||identity.invite||'';
let drafts=read(storageKey+':drafts',{}), pending=read(storageKey+':pending',[]), selectedRound=null;
let commentPager=null;
let adminPending=read('banjian:admin-pending');
let readEpoch=0,liveEpoch=0,announcedRevision=0,liveDirty=false,activeReads=0,liveTimer=null,socketKey=null;
let asciiFlight=null,asciiPull=0,asciiStart=null,asciiInterval=null;
const requestedTheme=new URLSearchParams(location.search).get('theme');
let roomTheme=['light','dark','system'].includes(requestedTheme)?requestedTheme:read('banjian:theme','system');
if(!['light','dark','system'].includes(roomTheme))roomTheme='system';
if(['light','dark','system'].includes(requestedTheme)){save('banjian:theme',roomTheme);const clean=new URL(location.href);clean.searchParams.delete('theme');history.replaceState(null,'',clean.toString());}
applyRoomTheme();
function toast(text){$('#toast').textContent=text;$('#toast').style.display='block';clearTimeout(toast.timer);toast.timer=setTimeout(()=>$('#toast').style.display='none',5000);}
async function api(path,body,auth=token){const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),15000);try{const r=await fetch('/api/'+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer '+auth}:{})},body:body?JSON.stringify(body):undefined,signal:controller.signal,redirect:'error'});const reader=r.body.getReader(),chunks=[];let size=0;while(true){const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>RoomProtocol.snapshotBytes){controller.abort();throw Error('活动数据过大，请分批查看');}chunks.push(part.value);}const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}const text=new TextDecoder().decode(bytes);let data;try{data=JSON.parse(text);}catch{throw Error('服务返回无效数据');}if(!r.ok){const error=Error(data.error||'请求失败');error.status=r.status;throw error;}return data;}finally{clearTimeout(timer);}}
const current=()=>event?.rounds.find(r=>r.id===event.current);
const status=r=>({waiting:'等待开始',open:'评分进行中',paused:'已暂停',closed:'已截止'}[r?.status]||'等待选番');
function cover(subject){return subject.cover?`<img class="cover" src="/cover/${esc(subject.cover)}" alt="${esc(subject.title)}">`:`<div class="cover placeholder">${esc(subject.title.slice(0,4))}</div>`;}
function hero(r){return `<div class="hero">${cover(r.subject)}<div><span class="badge">第 ${event.rounds.indexOf(r)+1} / ${event.rounds.length} 轮 · ${status(r)}</span><h2>${esc(r.subject.title)}</h2><p class="summary">${esc(r.subject.summary)||'一起看番，留下你的感受。'}</p><small>Bangumi #${r.subject.id}</small></div></div>`;}
function bars(r){const d=r.stats?.distribution||[],max=Math.max(1,...d);return `<div class="bars">${d.map((n,i)=>`<div class="bar"><span>${n||''}</span><i style="height:calc((100% - 36px) * ${n/max})"></i><span>${i+1}</span></div>`).join('')}</div>`;}
function metrics(r){return `<div class="metrics"><div class="metric"><strong>${r.stats?.mean?.toFixed(1)??'—'}</strong><small>平均评分</small></div><div class="metric"><strong>${r.count}</strong><small>已评分</small></div><div class="metric"><strong>${event.memberCount-r.count}</strong><small>未评分</small></div></div>`;}
function comments(r){const body= r.comments.length?[...r.comments].reverse().map(c=>`<div class="comment ${c.hidden?'hidden':''}"><div class="row between"><span><span class="avatar">匿</span> ${c.mine?'我 · 匿名短评':'匿名短评'} ${c.hidden?'· 已隐藏':''}</span>${admin?`<button class="link" data-action="hide" data-round="${r.id}" data-id="${c.id}" data-value="${!c.hidden}">${c.hidden?'恢复':'隐藏'}</button>`:''}</div><p>${esc(c.text)}</p></div>`).join(''):'<div class="empty">还没有可见短评</div>';return body+(r.commentsMore?`<button class="link" data-action="all-comments" data-round="${esc(r.id)}">查看全部 ${r.commentsTotal} 条短评</button>`:'');}
function render(){
  refreshPagedComments();
  const panelScroll=[...document.querySelectorAll('.arena-scroll')].map(el=>({top:el.scrollTop,height:el.scrollHeight}));
  const sharing=$('#modal').dataset.inviteEvent;
  if(admin&&sharing&&(event?.id!==sharing||event?.ended)){ $('#modal').close();delete $('#modal').dataset.inviteEvent;toast('这张二维码对应的活动已结束或已切换，请获取当前活动的新二维码。'); }
  const active=document.activeElement, focus=active?.id, editingRound=active?.dataset?.round, selection=typeof active?.selectionStart==='number'?[active.selectionStart,active.selectionEnd]:null;
  if(admin) renderAdmin();else renderParticipant();
  danmaku();
  document.querySelectorAll('.arena-scroll').forEach((el,index)=>{const old=panelScroll[index];if(old)el.scrollTop=old.top>0?old.top+el.scrollHeight-old.height:0;});
  if(admin&&$('#modal').open&&$('#modal').dataset.adminPanel){const offset=$('#modal').scrollTop;tab=$('#modal').dataset.adminPanel;$('#modal').innerHTML=`<button class="link close" data-action="close-modal">关闭</button>${adminContent()}`;$('#modal').scrollTop=offset;}
  if(focus&&document.getElementById(focus)&&(focus!=='comment-draft'||editingRound===document.getElementById(focus).dataset.round)){const el=document.getElementById(focus);el.focus({preventScroll:true});if(selection&&el.setSelectionRange)el.setSelectionRange(...selection);}
}
// New visible comments of the current round fly across once. The first
// render of a round only records what is already there.
let danmakuRound=null,danmakuSeen=new Set(),danmakuLane=0;
function danmaku(){
  const r=(admin?token:identity.joined)?current():null;
  if(!r||r.id!==danmakuRound){danmakuRound=r?.id??null;danmakuSeen=new Set(r?r.comments.map(c=>c.id):[]);return;}
  const fresh=r.comments.filter(c=>!danmakuSeen.has(c.id)&&!c.hidden);r.comments.forEach(c=>danmakuSeen.add(c.id));
  if(!fresh.length||matchMedia('(prefers-reduced-motion: reduce)').matches)return;
  let layer=$('#danmaku');
  if(!layer){layer=document.createElement('div');layer.id='danmaku';layer.className='danmaku';layer.setAttribute('aria-hidden','true');document.body.append(layer);}
  fresh.slice(-6).forEach((c,i)=>{if(layer.childElementCount>=12)return;const chars=[...c.text],el=document.createElement('div');el.className='danmaku-item';el.textContent=chars.length>40?chars.slice(0,40).join('')+'…':c.text;el.style.top=`${(danmakuLane++%5)*44}px`;el.style.animationDelay=`${i*.6}s`;el.addEventListener('animationend',()=>el.remove());layer.append(el);});
}
function summaryList(host){const list=RoomProtocol.summary(event),total=list.reduce((n,v)=>n+v.r.stats.count,0);const hint=event.ended?`按均分排名 · 共 ${list.length} 部 · ${total} 次评分`:host?'活动结束后，参与者会看到这份汇总':'目前只包含主持人已公布的轮次，活动结束后公布全部';return `<p class="hint">${hint}</p>`+(list.length?`<ol class="summary">${list.map(({rank,r})=>`<li class="summary-row"><span class="summary-rank ${rank<=3?'top':''}">${rank}</span><div class="grow"><strong>${esc(r.subject.title)}</strong><small>${r.stats.count} 人评分${r.myScore!=null?` · 我打了 ${r.myScore} 分`:''}</small></div><strong class="summary-mean">${r.stats.mean.toFixed(1)}</strong></li>`).join('')}</ol>`:'<div class="empty">还没有可以汇总的评分</div>');}
function header(){return `<header class="top"><div class="brand"><span class="logo">▶</span><div>MuBangumi <small>番剧鉴赏 · 番键会</small></div></div><div class="row"><span class="badge"><i class="dot"></i>${online?'实时连接':'正在重连'}</span>${adminPending?'<button class="soft" data-action="retry-admin">核对未确认操作</button>':''}<button data-action="refresh">刷新</button>${themeControl()}<button data-action="history">历史活动</button><button data-action="logout">锁定管理端</button></div></header>`;}
function renderAdmin(){
  document.body.classList.toggle('admin-active',!!token);
  if(!token){$('#app').innerHTML=`<main class="phone join"><div class="logo">▶</div><h1>管理番键会</h1><p class="muted">输入服务设备显示的管理密码。<br>参与二维码不包含管理权限。</p><form id="login"><label for="password">管理密码</label><input id="password" type="password" autocomplete="current-password" required minlength="12"><div class="space"></div><button class="primary full">进入管理</button></form><p class="hint">管理页面可以关闭，活动会在服务设备上继续运行。</p></main>`;return;}
  if(!event){$('#app').innerHTML=header()+`<main class="shell activity-library"><div class="card empty"><strong>把喜欢的番剧，放到一起聊</strong><p>创建一场番键会，邀请大家匿名评分和评论。</p><button class="primary" data-action="create">＋ 创建番键会</button></div>${events.map(e=>`<div class="card row between"><div><h3>${esc(e.title)}</h3><small>${e.ended?'已结束':'进行中'} · ${e.rounds} 部番剧</small></div><button data-action="open" data-id="${e.id}">打开活动</button></div>`).join('')}</main>`;return;}
  $('#app').innerHTML=header()+`<main class="shell">${online?'':'<div class="offline">连接已中断，显示最后保存状态；管理操作将在连接恢复后可用。</div>'}<section class="banner row between"><div><span class="badge">${event.ended?'活动已结束':'番键会进行中'}</span><h1>${esc(event.title)} <button class="link" data-action="rename" aria-label="修改活动名称">✎</button></h1><small>${event.memberCount} 个参与身份 · ${event.connections||0} 个在线参与连接 · 有名入场 / 匿名评分</small></div><div class="row"><button data-action="invite" ${event.ended?'disabled':''}>邀请参与</button>${event.ended?'<button data-action="active-event">返回当前活动</button>':''}<button data-action="export">导出记录</button>${event.rounds.some(r=>!r.subject.cover)?'<button data-action="repair-covers">补全封面</button>':''}${event.ended?'':`<button class="danger" data-action="end">结束活动</button>`}</div></section><nav class="tabs">${[['control','现场控制'],['playlist','番单'],['results','评分结果'],['members','成员']].map(([id,label])=>`<button class="${tab===id?'active':''}" data-action="tab" data-id="${id}">${label}</button>`).join('')}</nav>${arenaContent()}</main>`;
}
function adminContent(){const r=current();
  if(tab==='members')return `<div class="card"><h2>入场名单</h2><p class="muted">仅显示当前轮次的提交状态，不展示姓名与分数、评论的对应关系。</p><div class="member-grid">${event.members.map(m=>`<div class="member row between"><span class="row">${m.avatar?`<img class="avatar" src="/cover/${esc(m.avatar)}" alt="">`:`<span class="avatar">${esc([...m.name][0]||'?')}</span>`}<strong>${esc(m.name)}</strong></span><span class="badge">${m.submitted?'已评分':'未评分'}</span></div>`).join('')}</div></div>`;
  if(tab==='playlist')return `<div class="card"><div class="row between"><h2>今晚的番单</h2><button class="primary" data-action="search" ${event.ended?'disabled':''}>＋ 添加番剧</button></div>${event.rounds.map((v,i)=>`<div class="list-row">${cover(v.subject)}<div class="grow"><h3>${i+1}. ${esc(v.subject.title)}</h3><small>${status(v)}</small></div>${v.status==='waiting'&&!event.ended?`<button data-action="start" data-round="${v.id}">开始</button><button aria-label="上移" data-action="move" data-round="${v.id}" data-index="${i-1}" ${i===0?'disabled':''}>↑</button><button aria-label="下移" data-action="move" data-round="${v.id}" data-index="${i+1}" ${i===event.rounds.length-1?'disabled':''}>↓</button><button class="danger" data-action="remove" data-round="${v.id}">移除</button>`:''}</div>`).join('')||'<div class="empty">先添加几部番剧，也可以在服务手机上导入选定的收藏。</div>'}</div>`;
  if(tab==='results'){return `<div class="card"><div class="row between"><h2>评分结果</h2><button data-action="project">大屏展示</button></div><p class="hint">管理端可查看所有统计；参与者仅能查看已公布轮次，活动结束后公布全部。</p><section class="card"><h2>整场汇总</h2>${summaryList(true)}</section>${event.rounds.map(v=>`<section class="card">${hero(v)}${metrics(v)}${bars(v)}<button class="soft" data-action="publish" data-round="${v.id}" data-value="${!v.published}">${v.published?'撤回公布':'公布这一轮结果'}</button></section>`).join('')}</div>`;}
  if(!r)return `<div class="card empty"><strong>番单准备好了吗？</strong><p>选一部番剧开始，大家就能实时评分和评论。</p><button class="primary" data-action="tab" data-id="playlist">去选番</button></div>`;
  const next=event.rounds.find(v=>v.status==='waiting');
  return `<div class="grid"><div><section class="card"><div class="row between"><h2>正在鉴赏</h2><span class="badge">${status(r)}</span></div>${hero(r)}${metrics(r)}<div class="actions"><button data-action="${r.status==='paused'?'resume':'pause'}" data-round="${r.id}" ${r.status==='closed'||event.ended?'disabled':''}>${r.status==='paused'?'继续评分':'暂停评分'}</button><button data-action="close" data-round="${r.id}" ${r.status==='closed'||event.ended?'disabled':''}>截止本轮</button><button class="primary" data-action="start" data-round="${next?.id||''}" ${!next||event.ended?'disabled':''}>下一部 →</button></div><div class="space"></div><div class="rule"><div>向参与者公布结果<small>公开均分和分布，始终不显示个人评分</small></div><button class="${r.published?'soft':''}" data-action="publish" data-round="${r.id}" data-value="${!r.published}">${r.published?'已公布':'未公布'}</button></div><div class="rule"><div>对未评分的人也展示短评<small>参与者评分后自动可见本轮短评；开启后所有人可见</small></div><button class="${r.publicComments?'soft':''}" data-action="comments" data-round="${r.id}" data-value="${!r.publicComments}">${r.publicComments?'已开启':'未开启'}</button></div></section><section class="card"><h2>评分分布</h2>${bars(r)}</section></div><section class="card"><div class="row between"><h2>大家的匿名短评</h2><small>${r.comments.length} 条</small></div>${comments(r)}</section></div>`;
}
function renderParticipant(){
  document.body.classList.toggle('participant-active',!!identity.joined&&!!event);
  if(!eventId){$('#app').innerHTML='<main class="phone empty"><strong>番键会</strong>请扫描主持人分享的参与二维码。</main>';return;}
  if(!identity.joined){$('#app').innerHTML=`<main class="phone join"><div class="logo">▶</div><h1>${esc(event?.title||'加入番键会')}</h1><p class="muted">同一场鉴赏，不同的感受。</p>${event?.ended?'<div class="offline"><strong>这张二维码对应的活动已结束</strong><p>请扫描主持人正在进行的活动的新二维码。</p></div>':''}<form id="join"><label for="name">你的活动显示名</label><input id="name" maxlength="40" value="${esc(identity.name||'')}" placeholder="让主持人知道你来了" required><div class="privacy">入场名单显示你的名字，评分和短评匿名展示。<br>请固定使用本浏览器，避免重复身份。</div><button class="primary full" ${event?.ended&&!identity.token?'disabled':''}>${event?.ended?(identity.token?'返回活动记录':'活动已经结束'):'加入番键会 →'}</button></form></main>`;return;}
  if(!event){$('#app').innerHTML='<main class="phone empty">正在恢复活动…</main>';return;}
  const r=current(),draft=r?(drafts[r.id]||{}):{};
  const editable=r&&r.status==='open'&&!event.ended;
  const queued=pending.filter(c=>c.round===r?.id);
  if(!$('#participant-workspace')){
    document.body.classList.remove('typing-comment');
    $('#app').innerHTML=`<main id="participant-workspace" class="participant-workspace">
      <header class="participant-heading"><div id="participant-title"></div><div class="row"><button class="link" data-action="refresh">刷新</button><button class="link" data-action="leave">退出</button></div></header>
      <div class="participant-well"><div id="participant-connection" class="participant-connection"></div><div id="participant-hero" class="participant-hero"></div>
        <section class="participant-vote"><div class="row between"><h3>你的评分</h3><button class="link edit-score" data-action="edit-score">修改评分</button></div>
          <div class="scores">${Array.from({length:10},(_,i)=>`<button data-action="score" data-score="${i+1}" aria-label="${i+1} 分">${i+1}</button>`).join('')}</div>
          <p id="participant-receipt" class="hint" aria-live="polite"></p>
          <button id="participant-summary" class="soft" data-action="participant-sheet" data-id="summary" hidden>查看整场汇总</button>
        </section>
        <label class="sr-only" for="comment-draft">匿名短评</label><textarea id="comment-draft" maxlength="500" rows="2" placeholder="写一句感受，匿名发送…"></textarea>
        <p class="participant-privacy hint">评分与短评匿名展示 · 截止前可修改评分</p>
      </div>
      <footer class="participant-footer"><div class="participant-submit"><button class="primary" data-action="submit-score">提交评分</button><button class="soft" data-action="submit-comment">匿名发送</button></div>
        <nav class="participant-details"><button data-action="participant-sheet" data-id="comments">评论墙</button><button data-action="participant-sheet" data-id="results">统计</button><button data-action="participant-sheet" data-id="playlist">番单</button></nav>
      </footer></main>`;
  }
  $('#participant-title').innerHTML=`<strong>${esc(event.title)}</strong><small>${esc(event.name)} · ${event.memberCount} 人已入场</small>`;
  $('#participant-connection').textContent=online?(event.ended?'活动已结束':'● 实时连接'):'正在重连 · 未确认的输入已保留';
  $('#participant-connection').classList.toggle('offline-text',!online);
  $('#participant-hero').innerHTML=r?`${cover(r.subject)}<div><h2>${esc(r.subject.title)}</h2><span class="badge">第 ${event.rounds.indexOf(r)+1} / ${event.rounds.length} 轮 · ${status(r)}</span></div>`:'<div class="empty">主持人正在准备番单，请稍等…</div>';
  document.querySelectorAll('[data-action="score"]').forEach(b=>{const selected=Number(b.dataset.score)===(draft.score??r?.myScore);b.classList.toggle('selected',selected);b.setAttribute('aria-pressed',String(selected));b.disabled=!editable;});
  $('#participant-receipt').textContent=`${r?.myScore?`已确认评分：${r.myScore} 分`:'尚未确认评分'}${queued.length?` · ${queued.length} 条待确认`:''}${!editable&&r?` · ${event.ended?'活动已结束':status(r)}，目前不能提交。`:''}`;
  const editor=$('#comment-draft');
  if(editor.dataset.round&&editor.dataset.round!==r?.id){editor.blur();toast('已切换轮次，上一轮草稿已保留');}
  editor.dataset.round=r?.id||'';editor.disabled=!editable;
  if(editor.value!==(draft.text||''))editor.value=draft.text||'';
  const submit=$('[data-action="submit-score"]');submit.textContent=r?.myScore?'更新我的评分':'提交评分';submit.disabled=!editable||!(draft.score??r?.myScore);
  $('[data-action="submit-comment"]').disabled=!editable;
  $('#participant-summary').hidden=!event.ended;
  renderParticipantSheet();
}

function renderParticipantSheet(){
  const dialog=$('#modal'),kind=dialog.dataset.participantSheet;
  if(!kind||!dialog.open||!event)return;
  const scroll=$('#participant-sheet-content')?.scrollTop||0;
  const r=selectedRound?event.rounds.find(v=>v.id===selectedRound):current();
  let content='';
  if(kind==='summary')content=summaryList(false);
  else if(kind==='playlist')content=event.rounds.map(v=>`<div class="list-row"><div class="grow"><strong>${esc(v.subject.title)}</strong><small> · ${status(v)}</small></div><button class="link" data-action="review-round" data-id="${v.id}">查看</button></div>`).join('');
  else if(!r)content='<p class="muted">等待主持人开始</p>';
  else content=`<h3>${esc(r.subject.title)}</h3>${selectedRound?'<button class="link" data-action="review-current">返回当前轮次</button>':''}`+(kind==='comments'?`<p class="hint">${(r.commentsOpen??r.publicComments)?'大家的匿名短评':'评分后即可查看大家的短评，目前仅展示你自己的评论'}</p>${comments(r)}`:r.stats?metrics(r)+bars(r):'<div class="empty">结果暂未公布，个人分数仅自己可见。</div>');
  dialog.innerHTML=`<div class="row between"><h2>番键会现场</h2><button class="link" data-action="close-modal">关闭</button></div><nav class="tabs">${[['comments','评论墙'],['results','统计'],['playlist','番单'],['summary','汇总']].map(([id,label])=>`<button class="${kind===id?'active':''}" data-action="participant-sheet" data-id="${id}">${label}</button>`).join('')}</nav><div id="participant-sheet-content">${content}</div>`;
  $('#participant-sheet-content').scrollTop=scroll;
}

function openParticipantSheet(kind){
  const dialog=$('#modal');if(!dialog.open)selectedRound=null;delete dialog.dataset.inviteEvent;dialog.dataset.participantSheet=kind;
  dialog.classList.add('participant-drawer');if(!dialog.open)dialog.showModal();renderParticipantSheet();
}

function requestLiveRefresh(){liveDirty=true;if(activeReads||liveTimer)return;liveTimer=setTimeout(()=>{liveTimer=null;liveDirty=false;void refresh();},60);}
function applySnapshot(next){
  if(next.id!==event?.id&&event?.rounds)return false;
  if(event?.id===next.id&&event.serverEpoch===next.serverEpoch&&next.revision!=null&&event.revision!=null&&next.revision<event.revision)return false;
  if(event?.serverEpoch!==next.serverEpoch)announcedRevision=0;event=RoomProtocol.snapshot(next);return true;
}
function connect(){
  if(!event?.id||!token)return;
  const key=token+':'+event.id;
  if(socketKey===key&&socket&&socket.readyState<=1)return;
  if(socket){socket.onclose=null;socket.close();}
  clearTimeout(reconnect);socketKey=key;announcedRevision=0;
  const ws=new WebSocket(`${location.protocol==='https:'?'wss:':'ws:'}//${location.host}/ws`);socket=ws;
  const valid=()=>socket===ws&&socketKey===key&&token+':'+event?.id===key;
  ws.onopen=()=>{if(valid())ws.send(JSON.stringify({event:event.id,token,updates:'invalidate'}));};
  ws.onmessage=m=>{if(!valid())return;try{
    const next=JSON.parse(m.data);
    if(next.type==='invalidate'){
      if(next.event!==event.id||!Number.isSafeInteger(next.revision))throw Error('活动更新通知格式无效');
      announcedRevision=Math.max(announcedRevision,next.revision);liveEpoch++;online=true;requestLiveRefresh();return;
    }
    if(!applySnapshot(next))return;liveEpoch++;online=true;render();flush();
  }catch(e){toast(e.message||'活动数据格式无效');ws.close(1002,'Invalid room snapshot');}};
  ws.onclose=()=>{if(!valid())return;socket=null;socketKey=null;online=false;render();reconnect=setTimeout(refresh,2500);};
  ws.onerror=()=>ws.close();
}
async function refresh(){
  const epoch=++readEpoch,auth=token,id=event?.id||eventId,observedLive=liveEpoch,base=event;
  const valid=()=>epoch===readEpoch&&token===auth&&(event?.id||eventId)===id;
  activeReads++;
  try{
    if(admin&&!event){const data=await api('history');if(!valid())return;events=data.events;online=true;render();return;}
    const path='state?event='+encodeURIComponent(id);
    let payload=await api(path+(Number.isSafeInteger(base?.revision)?'&since='+base.revision+'&epoch='+encodeURIComponent(base.serverEpoch||''):''));
    if(!valid())return;
    let next;try{next=RoomProtocol.merge(base,payload);}catch(e){if(payload.type!=='delta')throw e;payload=await api(path);if(!valid())return;next=RoomProtocol.snapshot(payload);}
    if(next.id!==id)throw Error('活动编号不匹配');
    if(next.serverEpoch===event?.serverEpoch&&next.revision!=null&&next.revision<announcedRevision){liveDirty=true;}
    if(observedLive===liveEpoch||next.serverEpoch===event?.serverEpoch&&next.revision>event?.revision)applySnapshot(next);
    online=true;render();connect();flush();
  }catch(e){
    if(!valid()||observedLive!==liveEpoch)return;
    online=false;
    if(e.status===401){if(admin){token='';sessionStorage.removeItem('banjian-admin');}else{identity.joined=false;save(storageKey,identity);}render();toast(e.message);}
    else{render();clearTimeout(reconnect);reconnect=setTimeout(refresh,3000);toast(e.message||'连接失败');}
  }finally{activeReads--;if(!activeReads&&liveDirty)requestLiveRefresh();}
}
async function command(action,extra={},retry=false){
  if(busy)return false;
  if(adminPending&&!retry){toast('上一项操作还未确认，请先点击顶部「核对未确认操作」');return false;}
  if(!online){toast('请等待连接恢复');return false;}
  const c=retry?adminPending:{op:secret(),event:event?.id,version:event?.version,action,...extra};
  if(!c)return false;
  if(!save('banjian:admin-pending',c))return false;
  adminPending=c;busy=true;
  try{const result=await api('admin',c);save('banjian:admin-pending',null);adminPending=null;if(c.action==='create'||event?.id!==result.id)event={id:result.id};await refresh();return true;}
  catch(e){if(e.status&&e.status<500&&![401,429].includes(e.status)){save('banjian:admin-pending',null);adminPending=null;}toast(e.message+(adminPending?'；操作尚未确认，请恢复连接后核对':''));if(e.status===409)await refresh();render();return false;}
  finally{busy=false;}
}
function modal(html){delete $('#modal').dataset.pagedComments;$('#modal').classList.remove('results-project');delete $('#modal').dataset.adminPanel;delete $('#modal').dataset.participantSheet;$('#modal').classList.remove('participant-drawer');delete $('#modal').dataset.inviteEvent;$('#modal').innerHTML=`<button class="link close" data-action="close-modal">关闭</button>${html}`;$('#modal').showModal();}
async function enqueue(action,extra){const r=current();if(!r||r.status!=='open'||event.ended){toast('本轮不能提交');return;}const c={op:secret(),event:event.id,round:r.id,action,...extra};const next=[...pending,c];if(next.length>100){toast('待确认操作过多，请先恢复连接');return;}if(!save(storageKey+':pending',next))return;pending=next;toast('已保存，正在提交');render();await flush();}
async function flush(){if(flushing||!online||!identity.joined||admin)return;flushing=true;try{while(pending.length&&online){const c=pending[0];try{await api('command',c);pending.shift();save(storageKey+':pending',pending);if(c.action==='comment'&&drafts[c.round]?.text===c.text){drafts[c.round].text='';save(storageKey+':drafts',drafts);}toast(c.action==='score'?'评分已确认':'匿名短评已确认');}catch(e){if(e.status&&e.status<500&&e.status!==429){pending.shift();save(storageKey+':pending',pending);toast(e.message+'；输入已保留');}else{online=false;setTimeout(refresh,e.status===429?4000:2500);break;}}}render();}finally{flushing=false;}}
document.addEventListener('input',e=>{if(e.target.id==='comment-draft'){const r=current();if(r){drafts[r.id]={...drafts[r.id],text:e.target.value};save(storageKey+':drafts',drafts);}}});
document.addEventListener('submit',async e=>{e.preventDefault();if(busy)return;busy=true;try{
  if(e.target.id==='login'){const data=await api('login',{password:$('#password').value},'');token=data.token;sessionStorage.setItem('banjian-admin',token);await refresh();}
  if(e.target.id==='join'){const name=$('#name').value.trim();if(!name){toast('请填写活动显示名');return;}identity={...identity,name,invite,token:identity.token||secret(),op:secret()};if(!save(storageKey,identity))return;await api('join',{op:identity.op,event:eventId,invite,token:identity.token,name},'');identity.joined=true;save(storageKey,identity);token=identity.token;await refresh();}
  if(e.target.id==='search-form'){const data=await api('search?q='+encodeURIComponent($('#search-q').value));$('#search-results').innerHTML=data.subjects.map(s=>`<div class="list-row"><div class="grow"><h3>${esc(s.title)}</h3><small>#${s.id}</small></div><button class="soft" data-action="add" data-id="${s.id}">加入番单</button></div>`).join('')||'<div class="empty">没有找到动画条目</div>';}
}catch(error){toast(error.message);}finally{busy=false;}});
document.addEventListener('click',async e=>{const b=e.target.closest('[data-action]');if(!b||b.disabled)return;const a=b.dataset.action,r=b.dataset.round;try{
  if(['all-comments','comments-prev','comments-next','comments-retry'].includes(a)){await handleCommentPage(a,r);return;}

  if(a==='tab'){tab=b.dataset.id;if(admin&&tab!=='control'){modal(adminContent());$('#modal').dataset.adminPanel=tab;}else{if($('#modal').open)$('#modal').close();delete $('#modal').dataset.adminPanel;render();}}
  else if(a==='refresh'){await manualRefresh();}
  else if(a==='theme'){roomTheme={system:'light',light:'dark',dark:'system'}[roomTheme];save('banjian:theme',roomTheme);applyRoomTheme();render();}
  else if(a==='inspect-round'){const r=event.rounds.find(v=>v.id===b.dataset.id);if(r)modal(`<h2>${esc(r.subject.title)}</h2>${metrics(r)}${bars(r)}<h3>匿名短评</h3>${comments(r)}`);}
  else if(a==='close-modal'){if($('#modal').dataset.adminPanel)tab='control';$('#modal').close();delete $('#modal').dataset.participantSheet;delete $('#modal').dataset.adminPanel;$('#modal').classList.remove('participant-drawer');}
  else if(a==='create'){const title=prompt('番键会名称','今晚的番键会');if(title&&await command('create',{title}))$('#modal').close();}
  else if(a==='rename'){const title=prompt('修改活动名称',event.title);if(title)await command('rename',{title});}
  else if(a==='history'){const list=await api('history');modal(`<h2>历史活动</h2>${list.events.every(v=>v.ended)?'<button class="primary" data-action="create">创建新活动</button>':''}${list.events.map(v=>`<div class="list-row"><div class="grow"><h3>${esc(v.title)}</h3><small>${v.ended?'已结束':'进行中'} · ${v.rounds} 部番剧</small></div><button data-action="open" data-id="${v.id}">打开活动</button></div>`).join('')}`);}
  else if(a==='active-event'){const list=await api('history');const active=list.events.find(v=>!v.ended);if(!active){toast('当前没有进行中的活动，请创建新活动');return;}event={id:active.id};await refresh();}
  else if(a==='open'){$('#modal').close();delete $('#modal').dataset.adminPanel;event={id:b.dataset.id};await refresh();}
  else if(a==='logout'){await api('logout',{});token='';event=null;sessionStorage.removeItem('banjian-admin');socket?.close();render();}
  else if(a==='search'){modal('<h2>添加番剧</h2><p class="muted">搜索名称，或输入 Bangumi 条目 ID</p><form id="search-form" class="row"><input id="search-q" placeholder="例如：葬送的芙莉莲" required><button class="primary">搜索</button></form><div id="search-results" class="search-results"></div><p class="hint">选中后缓存标题、简介与封面，活动期间无需连接外网。</p>');}
  else if(a==='retry-admin'){await command('',{},true);}
  else if(a==='add'){b.disabled=true;b.textContent='正在准备…';const subject=await api('subject?id='+b.dataset.id);const accepted=await command('add',{subject});b.textContent=accepted?'已添加':'加入番单';b.disabled=accepted;if(subject.coverWarning)toast(subject.coverWarning);}
  else if(a==='invite'){const sharingId=event.id;const invitation=await api('invitation?event='+sharingId);if(event.id!==sharingId||event.ended){toast('活动已变化，请重新邀请');return;}const link=invitation.url;modal(`<h2>邀请大家来鉴赏</h2><p>用 MuBangumi 扫码进入原生参与页；其他扫码工具进入网页。</p><img class="qr" id="invite-qr" alt="参与二维码"><input id="invite-link" readonly value="${esc(link)}"><div class="space"></div><button data-action="copy-invite">复制参与链接</button><p class="hint">${invitation.localOnly?'当前地址仅限本机，请在服务设备连接 Wi-Fi / 热点后重新分享。':location.protocol==='http:'?'连接同一 Wi-Fi / 热点后，MuBangumi 自动寻找服务；其他扫码工具直接进入网页。':''}此链接不含管理权限。</p><button class="link danger" data-action="rotateInvite">更新邀请链接（旧链接失效）</button>`);$('#modal').dataset.inviteEvent=sharingId;const blob=new Blob([invitation.qr],{type:'image/svg+xml'});const url=URL.createObjectURL(blob);$('#invite-qr').src=url;$('#invite-qr').onload=()=>URL.revokeObjectURL(url);}
  else if(a==='copy-invite'){const el=$('#invite-link');el.select();try{await navigator.clipboard.writeText(el.value);toast('已复制');}catch{document.execCommand('copy');toast('链接已选中，可复制分享');}}
  else if(a==='repair-covers'){await api('repair-covers',{event:event.id});toast('正在后台补齐封面，请保持服务设备联网');}
  else if(a==='export'){modal('<h2>导出活动记录</h2><p>导出汇总评分和匿名短评，不包含姓名与评分对应表。</p><div class="actions"><button data-action="download" data-format="combined">评分与短评 CSV</button><button data-action="download" data-format="json">活动 JSON</button></div>');}
  else if(a==='download'){const res=await fetch('/api/export?event='+event.id+'&format='+b.dataset.format,{headers:{Authorization:'Bearer '+token}});if(!res.ok)throw Error('导出失败，请重新登录管理端');const url=URL.createObjectURL(await res.blob());const el=document.createElement('a');el.href=url;el.download='番键会-'+({combined:'评分与短评',json:'活动记录'}[b.dataset.format]||b.dataset.format)+(b.dataset.format==='json'?'.json':'.csv');el.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
  else if(a==='project'){$('#modal').classList.toggle('results-project');b.textContent=$('#modal').classList.contains('results-project')?'退出大屏':'大屏展示';}
  else if(a==='participant-sheet'){openParticipantSheet(b.dataset.id);}
  else if(a==='review-round'){selectedRound=b.dataset.id;openParticipantSheet('results');}
  else if(a==='review-current'){selectedRound=null;renderParticipantSheet();}
  else if(a==='edit-score'){$('#comment-draft').blur();document.body.classList.remove('typing-comment');}
  else if(a==='round'){selectedRound=b.dataset.id===event.current?null:b.dataset.id;render();}
  else if(a==='score'){const r=current();drafts[r.id]={...drafts[r.id],score:Number(b.dataset.score)};save(storageKey+':drafts',drafts);render();}
  else if(a==='submit-score'){const r=current();await enqueue('score',{score:drafts[r.id]?.score??r.myScore});}
  else if(a==='submit-comment'){const text=$('#comment-draft').value.trim();if(!text){toast('先写一句感受吧');return;}if(pending.some(c=>c.action==='comment'&&c.round===event.current&&c.text===text)){toast('这条短评还在等待确认');return;}await enqueue('comment',{text});}
  else if(a==='leave'){if(!confirm('退出活动？评分记录仍会保留，下次用本浏览器可恢复参与身份。'))return;identity.joined=false;save(storageKey,identity);socket?.close();online=false;render();}
  else{if(['end','close','start','remove','rotateInvite'].includes(a)&&!confirm({end:'结束活动后不能继续评分，确认结束？',close:'截止后无法重新开放本轮，确认截止？',start:'开始这部番剧，并截止当前轮次？',remove:'移除这部未开始的番剧？',rotateInvite:'更新后，未入场的人需要新链接。已入场身份保留。'}[a]))return;if(a==='publish'&&b.dataset.value==='true'&&!confirm('公布这一轮的均分和分布？'))return;await command(a,{...(r?{round:r}:{}),...(b.dataset.value?{value:b.dataset.value==='true'}:{}),...(a==='hide'?{comment:b.dataset.id}:{}),...(a==='move'?{index:Number(b.dataset.index)}:{})});if(a==='rotateInvite')$('#modal').close();}
}catch(error){toast(error.message);b.disabled=false;}});
async function loadInitialView(){render();if(admin){if(token)await refresh();}else if(eventId){if(identity.joined){await refresh();}else{try{event=await api('preview',{event:eventId,invite},'');online=true;render();}catch(e){online=false;toast(e.message);$('#app').innerHTML=`<main class="phone empty"><strong>暂时无法加入</strong>${esc(e.message)}<p>请确认设备连接同一 Wi-Fi，或向主持人获取有效邀请。</p><button data-action="reload">重新连接</button></main>`;document.querySelector('[data-action="reload"]').onclick=()=>location.reload();}}}}
window.addEventListener('online',()=>refresh());
render();void withAsciiRefresh(async()=>{await loadInitialView();if((token||eventId)&&!online)throw Error('连接失败，请重试');},true);

document.addEventListener('focusin',e=>{if(e.target.id==='comment-draft')document.body.classList.add('typing-comment');});
document.addEventListener('focusout',e=>{if(e.target.id==='comment-draft')document.body.classList.remove('typing-comment');});

function arenaContent(){
  const r=current(),next=event.rounds.find(v=>v.status==='waiting');
  const completed=event.rounds.filter(v=>v.status==='closed').length;
  const list=event.rounds.map((v,i)=>`<div class="arena-entry ${v.id===event.current?'current':''}"><span class="step-number">${v.status==='closed'?'✓':i+1}</span><div><strong>${esc(v.subject.title)}</strong><small>${status(v)}</small></div>${v.status==='waiting'&&!event.ended?`<button class="link" data-action="start" data-round="${v.id}">开始</button>`:`<button class="link" data-action="inspect-round" data-id="${v.id}">查看</button>`}</div>`).join('');
  return `<div class="arena">
    <aside class="arena-card arena-roster"><div class="arena-card-heading"><h2>鉴赏路线</h2><button class="link" data-action="search" ${event.ended?'disabled':''}>＋ 选番</button></div><div class="arena-scroll">${list||'<div class="empty">先添加几部番剧</div>'}</div></aside>
    <div class="arena-center"><section class="arena-card arena-current"><div class="arena-card-heading"><h2>正在鉴赏</h2><span class="badge">${event.ended?'活动已结束':status(r)}</span></div>
      ${r?`<div class="arena-subject">${cover(r.subject)}<div class="grow"><h2>${esc(r.subject.title)}</h2><p class="summary">${esc(r.subject.summary)}</p><small>第 ${event.rounds.indexOf(r)+1} / ${event.rounds.length} 轮</small></div><div class="attendance-ring" style="--attendance:${event.memberCount?r.count/event.memberCount*100:0}%" role="img" aria-label="本轮 ${r.count} / ${event.memberCount} 人已评分"><span><strong>${r.count}</strong><small>已评分</small></span></div></div>
      ${metrics(r)}<div class="actions arena-controls"><button data-action="${r.status==='paused'?'resume':'pause'}" data-round="${r.id}" ${r.status==='closed'||event.ended?'disabled':''}>${r.status==='paused'?'继续评分':'暂停评分'}</button><button data-action="close" data-round="${r.id}" ${r.status==='closed'||event.ended?'disabled':''}>截止本轮</button><button class="primary" data-action="start" data-round="${next?.id||''}" ${!next||event.ended?'disabled':''}>下一部 →</button></div>
      <div class="arena-toggles"><button class="${r.published?'soft':''}" data-action="publish" data-round="${r.id}" data-value="${!r.published}">${r.published?'结果已公布':'公布结果'}</button><button class="${r.publicComments?'soft':''}" data-action="comments" data-round="${r.id}" data-value="${!r.publicComments}">${r.publicComments?'短评墙已对全员开放':'短评墙对全员开放'}</button><button class="link" data-action="inspect-round" data-id="${r.id}">详细统计</button></div>`:'<div class="empty"><strong>准备开始鉴赏</strong>从番单选择一部番剧开始</div>'}
    </section><section class="arena-card arena-distribution"><div class="arena-card-heading"><h2>评分分布</h2><small>1–10 分 · 匿名统计</small></div>${r?bars(r):'<div class="empty">等待第一轮评分</div>'}</section></div>
    <aside class="arena-card arena-wall"><div class="arena-card-heading"><h2>匿名短评</h2><small>${r?.comments.length||0} 条</small></div><div class="arena-scroll">${r?comments(r):'<div class="empty">等待活动开始</div>'}</div></aside>
  </div><footer class="arena-progress"><span>整场进程</span><progress max="${Math.max(1,event.rounds.length)}" value="${completed}"></progress><strong>${completed} / ${event.rounds.length} 轮已完成</strong></footer>`;
}

function applyRoomTheme(){
  document.documentElement.dataset.theme=roomTheme;
  document.documentElement.style.colorScheme=roomTheme==='system'?'light dark':roomTheme;
}
function themeControl(){return `<button data-action="theme" aria-label="切换明暗主题">${{light:'浅色',dark:'深色',system:'跟随系统'}[roomTheme]}</button>`;}

function resizeParticipantViewport(){document.documentElement.style.setProperty('--participant-height',(window.visualViewport?.height||innerHeight)+'px');}
window.visualViewport?.addEventListener('resize',resizeParticipantViewport);window.addEventListener('resize',resizeParticipantViewport);resizeParticipantViewport();

function asciiNode(){
  let node=$('#ascii-loading');
  if(!node){node=document.createElement('div');node.id='ascii-loading';node.setAttribute('role','status');node.setAttribute('aria-live','polite');node.hidden=true;node.innerHTML='<pre aria-hidden="true"></pre><span></span>';document.body.append(node);}
  return node;
}
function positionAscii(){
  const target=document.querySelector('.participant-workspace')||document.querySelector('.admin-active #app')||document.querySelector('.phone')||$('#app');
  const rect=target.getBoundingClientRect(),node=asciiNode();node.style.top=rect.top+'px';node.style.left=rect.left+'px';node.style.width=rect.width+'px';
}
function drawAscii(label,mark='▶',frame=0){
  const node=asciiNode(),trail=['·       ','  ·     ','    ·   ','      · '][frame%4];
  node.querySelector('pre').innerHTML='╭───────────╮\n│ <b>'+mark+'</b> '+(mark==='▶'?trail:'        ')+'│\n╰───────────╯';
  node.querySelector('span').textContent=label;positionAscii();
}
function revealAscii(height){
  const node=asciiNode();node.hidden=false;node.classList.add('visible');document.documentElement.style.setProperty('--ascii-offset',height+'px');
  node.style.clipPath=`inset(0 0 ${Math.max(0,54-height)}px 0)`;
}
function concealAscii(){asciiNode().classList.remove('visible');document.documentElement.style.setProperty('--ascii-offset','0px');}
function withAsciiRefresh(task,initial=false){
  if(asciiFlight)return asciiFlight;
  asciiFlight=(async()=>{
    const start=performance.now(),label=initial?'正在加载…':'正在更新…';let frame=0,failed=false;
    revealAscii(54);drawAscii(label);
    const reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
    if(!reduced)asciiInterval=setInterval(()=>drawAscii(label,'▶',++frame),225);
    try{await task();}catch(e){failed=true;toast(e.message||'加载失败，请重试');}
    await new Promise(resolve=>setTimeout(resolve,Math.max(0,400-(performance.now()-start))));
    clearInterval(asciiInterval);asciiInterval=null;
    drawAscii(failed?'加载失败，向下重试':'已更新',failed?'!':'✓');
    await new Promise(resolve=>setTimeout(resolve,failed?650:220));
    concealAscii();await new Promise(resolve=>setTimeout(resolve,reduced?0:200));asciiNode().hidden=true;
  })().finally(()=>{asciiFlight=null;});return asciiFlight;
}
async function manualRefresh(){
  return withAsciiRefresh(async()=>{
    if(admin&&!token){render();return;}
    if(!admin&&!identity.joined){await loadInitialView();}else{await refresh();}
    if(!online)throw Error('连接失败，请检查网络后重试');
  });
}
document.addEventListener('touchstart',e=>{
  if(asciiFlight||e.touches.length!==1||e.target.closest('dialog,input,textarea,button,a,[contenteditable]')){asciiStart=null;return;}
  const scroll=e.target.closest('.arena-scroll,.participant-well,.activity-library,.arena-current');
  if(scroll&&scroll.scrollTop>0){asciiStart=null;return;}
  asciiStart={x:e.touches[0].clientX,y:e.touches[0].clientY};asciiPull=0;
},{passive:true});
document.addEventListener('touchmove',e=>{
  if(!asciiStart||asciiFlight||e.touches.length!==1)return;
  const dy=e.touches[0].clientY-asciiStart.y,dx=e.touches[0].clientX-asciiStart.x;
  if(dy<0||Math.abs(dx)>Math.abs(dy)){if(asciiPull){concealAscii();asciiNode().hidden=true;}asciiStart=null;asciiPull=0;return;}
  if(dy>6){e.preventDefault();asciiPull=Math.min(64,dy*.55);revealAscii(asciiPull);drawAscii(asciiPull>=52?'松开刷新':'下拉刷新');}
},{passive:false});
document.addEventListener('touchend',()=>{
  if(!asciiStart)return;asciiStart=null;
  if(asciiPull>=52){void manualRefresh();}else{concealAscii();setTimeout(()=>{if(!asciiFlight)asciiNode().hidden=true;},200);}
  asciiPull=0;
});
document.addEventListener('touchcancel',()=>{asciiStart=null;asciiPull=0;if(!asciiFlight){concealAscii();asciiNode().hidden=true;}});

document.addEventListener('input',e=>{if(!admin&&e.target.id==='name'){identity.name=e.target.value;save(storageKey,identity);}});

function commentStamp(round){const r=event?.rounds?.find(v=>v.id===round);return `${event?.id}:${event?.version}:${r?.commentsOpen??r?.publicComments}`;}
function refreshPagedComments(){
  if(!commentPager||!$('#modal').open||!$('#modal').dataset.pagedComments)return;
  if(event?.id!==commentPager.event){$('#modal').close();commentPager=null;return;}
  if(commentPager.stamp!==commentStamp(commentPager.round))void loadCommentPage();
}
async function handleCommentPage(action,round){
  if(action==='all-comments'){
    commentPager={event:event.id,round,cursors:[null],next:null,request:0,stamp:''};
    modal('<h2>匿名短评</h2><p>正在加载…</p>');$('#modal').dataset.pagedComments='true';
  }else if(!commentPager)return;
  else if(action==='comments-next'&&commentPager.next!=null)commentPager.cursors.push(commentPager.next);
  else if(action==='comments-prev'&&commentPager.cursors.length>1)commentPager.cursors.pop();
  await loadCommentPage();
}
async function loadCommentPage(){
  const pager=commentPager,dialog=$('#modal');if(!pager||!dialog.open||event?.id!==pager.event)return;
  const request=++pager.request,auth=token,offset=dialog.scrollTop;
  pager.stamp=commentStamp(pager.round);
  dialog.innerHTML='<button class="link close" data-action="close-modal">关闭</button><h2>匿名短评</h2><p>正在加载…</p>';
  try{
    const query=new URLSearchParams({event:pager.event,round:pager.round,limit:'50'});if(pager.cursors.at(-1)!=null)query.set('before',pager.cursors.at(-1));
    const page=RoomProtocol.commentsPage(await api('comments?'+query));
    if(commentPager!==pager||request!==pager.request||token!==auth||!dialog.open||event?.id!==pager.event)return;
    if(page.event!==pager.event||page.round!==pager.round)throw Error('评论所属活动不匹配');
    pager.next=page.nextCursor;
    dialog.innerHTML=`<button class="link close" data-action="close-modal">关闭</button><h2>匿名短评 · ${page.total} 条</h2><button class="link" data-action="comments-retry">刷新评论</button>${comments({id:pager.round,comments:[...page.comments].reverse()})}<div class="row"><button data-action="comments-prev" ${pager.cursors.length===1?'disabled':''}>上一页</button><span>第 ${pager.cursors.length} 页</span><button data-action="comments-next" ${pager.next==null?'disabled':''}>下一页</button></div>`;
    dialog.scrollTop=offset;
  }catch(e){if(commentPager===pager&&request===pager.request&&dialog.open)dialog.innerHTML=`<button class="link close" data-action="close-modal">关闭</button><p>${esc(e.message)}</p><button data-action="comments-retry">重试</button>`;}
}
