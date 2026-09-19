(function (root) {
  'use strict';
  const snapshotBytes=8*1024*1024;
  const checkedRounds=new WeakSet(),checkedSnapshots=new WeakSet();
  function invalid(field){throw Error('活动数据格式无效：'+field);}
  function object(v,k){if(!v||typeof v!=='object'||Array.isArray(v))invalid(k);return v;}
  function text(v,k,max=200){if(typeof v!=='string'||!v.length||[...v].length>max)invalid(k);return v;}
  function id(v,k){text(v,k,128);if(!/^[A-Za-z0-9_-]+$/.test(v))invalid(k);return v;}
  function integer(v,k,min=0,max=2147483647){if(!Number.isSafeInteger(v)||v<min||v>max)invalid(k);return v;}
  function bool(v,k){if(typeof v!=='boolean')invalid(k);return v;}
  function comment(c){object(c,'comment');id(c.id,'comment.id');text(c.text,'comment.text',500);bool(c.hidden??false,'comment.hidden');if(c.mine!==undefined)bool(c.mine,'comment.mine');return c;}
  function round(r){
    object(r,'round');if(checkedRounds.has(r))return r;id(r.id,'round.id');object(r.subject,'subject');integer(r.subject.id,'subject.id',1);text(r.subject.title,'subject.title');
    if(r.subject.summary!==undefined&&(typeof r.subject.summary!=='string'||[...r.subject.summary].length>6000))invalid('summary');
    if(r.subject.cover!==undefined&&typeof r.subject.cover!=='string')invalid('cover');
    if(r.subject.cover&& !/^[a-f0-9]{64}$/.test(r.subject.cover))invalid('cover');
    if(!['waiting','open','paused','closed'].includes(r.status))invalid('round.status');
    bool(r.published,'published');bool(r.publicComments,'publicComments');integer(r.count,'count',0,500);
    if(r.myScore!=null)integer(r.myScore,'myScore',1,10);
    if(!Array.isArray(r.comments)||r.comments.length>5000)invalid('comments');r.comments.forEach(comment);
    if(r.commentsTotal!==undefined)integer(r.commentsTotal,'commentsTotal',r.comments.length,5000);
    if(r.commentsMore!==undefined)bool(r.commentsMore,'commentsMore');
    if(r.stats!=null){const s=object(r.stats,'stats');integer(s.count,'stats.count',0,500);if(s.count!==r.count)invalid('stats.count');if(!Array.isArray(s.distribution)||s.distribution.length!==10)invalid('distribution');s.distribution.forEach(v=>integer(v,'distribution',0,500));if(s.distribution.reduce((a,b)=>a+b,0)!==s.count)invalid('distribution');if((s.count===0)!==(s.mean===null)||s.mean!==null&&(typeof s.mean!=='number'||!Number.isFinite(s.mean)||s.mean<1||s.mean>10))invalid('mean');}
    Object.freeze(r.subject);r.comments.forEach(Object.freeze);Object.freeze(r.comments);if(r.stats){Object.freeze(r.stats.distribution);Object.freeze(r.stats);}Object.freeze(r);checkedRounds.add(r);return r;
  }
  function snapshot(v){
    object(v,'snapshot');if(checkedSnapshots.has(v))return v;id(v.id,'id');text(v.title,'title',80);bool(v.ended,'ended');integer(v.version,'version',1);integer(v.memberCount,'memberCount',0,500);
    if(v.revision!==undefined)integer(v.revision,'revision',1);
    if(!Array.isArray(v.rounds)||v.rounds.length>100)invalid('rounds');v.rounds.forEach(round);
    if(new Set(v.rounds.map(r=>r.id)).size!==v.rounds.length)invalid('round IDs');
    if(v.current!=null&&!v.rounds.some(r=>r.id===v.current))invalid('current');if(v.members){if(!Array.isArray(v.members)||v.members.length>500)invalid('members');v.members.forEach(m=>{text(m.name,'member.name',40);bool(m.submitted,'submitted');Object.freeze(m);});Object.freeze(v.members);}Object.freeze(v.rounds);Object.freeze(v);checkedSnapshots.add(v);return v;
  }
  function merge(previous,payload){
    object(payload,'snapshot');if(payload.type!=='delta')return snapshot(payload);
    if(!previous||previous.serverEpoch!==payload.serverEpoch||previous.id!==payload.id||previous.revision!==payload.baseRevision)invalid('requires resynchronization');
    if(!Array.isArray(payload.rounds)||payload.rounds.length>100)invalid('delta.rounds');
    const changes=new Map(payload.rounds.map(r=>[round(r).id,r]));if(changes.size!==payload.rounds.length)invalid('delta round IDs');
    if([...changes.keys()].some(id=>!previous.rounds.some(r=>r.id===id)))invalid('delta.round');
    if(integer(payload.revision,'revision',1)<previous.revision)invalid('delta.revision');
    const result={...previous,...payload,rounds:previous.rounds.map(r=>changes.get(r.id)||r)};delete result.type;delete result.baseRevision;return snapshot(result);
  }
  function commentsPage(v){object(v,'comments page');id(v.event,'event');id(v.round,'round');integer(v.revision,'revision',1);integer(v.total,'total',0,5000);if(v.nextCursor!==null)integer(v.nextCursor,'cursor',1);if(!Array.isArray(v.comments)||v.comments.length>100)invalid('comments');v.comments.forEach(comment);return v;}
  const api=Object.freeze({snapshotBytes,snapshot,merge,commentsPage});
  root.RoomProtocol=api;if(typeof module!=='undefined')module.exports=api;
})(globalThis);
