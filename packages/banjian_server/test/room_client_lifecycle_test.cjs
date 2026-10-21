const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const { webcrypto } = require('node:crypto');

function client() {
  const snapshot = {
    ...JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/room_snapshot.json'), 'utf8')),
    current: null, rounds: [],
  };
  // RoomStore.preview intentionally returns no rounds or snapshot revision.
  const preview = {
    id: snapshot.id, title: snapshot.title, ended: false,
    count: snapshot.memberCount, created: snapshot.created,
  };
  const elements = new Map(), handlers = new Map(), timers = new Map();
  let timerId = 0, socketCount = 0;
  const element = selector => {
    if (!elements.has(selector)) elements.set(selector, {
      dataset: {}, style: { setProperty() {} },
      classList: { toggle() {}, add() {}, remove() {} },
      value: 'Test participant', open: false, innerHTML: '',
    });
    return elements.get(selector);
  };
  const storage = new Map();
  const context = vm.createContext({
    snapshot, preview, structuredClone, URL, URLSearchParams, Uint8Array,
    crypto: webcrypto, btoa: value => Buffer.from(value).toString('base64'),
    innerHeight: 600, confirm: () => true,
    location: { pathname: '/join/' + snapshot.id, hash: '#invite=test', search: '', protocol: 'http:', host: 'localhost' },
    localStorage: { getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value) },
    sessionStorage: { getItem: () => null },
    document: {
      querySelector: element, querySelectorAll: () => [], getElementById: () => null,
      documentElement: element('html'), body: element('body'),
      addEventListener: (name, handler) => {
        const list = handlers.get(name) ?? [];
        list.push(handler); handlers.set(name, list);
      },
    },
    window: { addEventListener() {} }, matchMedia: () => ({ matches: true }),
    setTimeout: (fn, delay) => { const id = ++timerId; timers.set(id, { fn, delay }); return id; },
    clearTimeout: id => timers.delete(id),
    WebSocket: class {
      constructor() { this.readyState = 1; socketCount++; }
      close() { this.readyState = 3; this.onclose?.(); }
      send() {}
    },
  });
  const run = source => vm.runInContext(source, context);
  run(fs.readFileSync(path.join(__dirname, '../web/room_protocol.js'), 'utf8'));
  const source = fs.readFileSync(path.join(__dirname, '../web/app.js'), 'utf8');
  // Drive lifecycle events explicitly instead of running the initial animation.
  run(source.replace(/^render\(\);void withAsciiRefresh\(.*$/m, ''));
  return {
    run, timers, context, socketCount: () => socketCount,
    async submit() {
      for (const fn of handlers.get('submit')) await fn({ preventDefault() {}, target: { id: 'join' } });
    },
    async leave() {
      for (const fn of handlers.get('click')) await fn({ target: { closest: () => ({ dataset: { action: 'leave' } }) } });
    },
    async fire(id) {
      const timer = timers.get(id);
      timers.delete(id);
      await timer?.fn();
    },
  };
}

test('joined identity survives a failed first snapshot and recovers on retry', async () => {
  const c = client();
  c.run("event=structuredClone(preview); api=async path=>{if(path==='join')return {joined:true};throw Error('offline');};");
  await c.submit();
  assert.equal(c.run('identity.joined'), true);
  assert.equal(c.run('event'), null);
  assert.doesNotThrow(() => c.run('render()'));
  assert.equal(c.run("$('#toast').textContent"), 'offline');
  const retry = [...c.timers].find(([, timer]) => timer.delay === 3000);
  assert.ok(retry, 'failed snapshot must schedule recovery');
  c.run('api=async()=>structuredClone(snapshot);');
  await c.fire(retry[0]);
  assert.equal(c.run('event.id'), c.context.snapshot.id);
  assert.equal(c.run('online'), true);
  assert.equal(c.socketCount(), 1);
});

test('leave cancels live/reconnect timers and ignores late socket messages', async () => {
  const c = client();
  c.run("identity.joined=true;token='test-token';event=RoomProtocol.snapshot(structuredClone(snapshot));api=async()=>structuredClone(snapshot);connect();oldSocket=socket;requestLiveRefresh();reconnect=setTimeout(refresh,2500);");
  await c.leave();
  assert.equal(c.run('identity.joined'), false);
  assert.equal(c.run('online'), false);
  assert.equal(c.run('socket'), null);
  assert.equal([...c.timers.values()].some(timer => [60, 2500].includes(timer.delay)), false);
  c.run('oldSocket.onmessage({data:JSON.stringify(snapshot)});');
  await c.run('refresh()');
  c.run('connect();');
  assert.equal(c.socketCount(), 1);
  assert.equal(c.run('online'), false);
});

test('a state read completing after leave cannot reconnect or replace the snapshot', async () => {
  const c = client();
  c.run("identity.joined=true;token='test-token';event=RoomProtocol.snapshot(structuredClone(snapshot));api=()=>new Promise(resolve=>releaseRead=resolve);");
  const pending = c.run('refresh()');
  await c.leave();
  c.run("releaseRead({...snapshot,title:'Stale response',revision:snapshot.revision+1});");
  await pending;
  assert.equal(c.run('event.title'), c.context.snapshot.title);
  assert.equal(c.run('online'), false);
  assert.equal(c.socketCount(), 0);
});
