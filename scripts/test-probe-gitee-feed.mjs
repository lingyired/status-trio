import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

test('probe creates with POST and deletes only its own files', () => {
  const code =     "let live = new Map();" +
    "globalThis.fetch = async (url, options={}) => {" +
    " const u = new URL(url); const path = u.pathname.split('/').at(-1);" +
    " if(options.method === 'POST') { if(live.has(path)) throw Error('duplicate'); live.set(path, 'owned-sha'); return Response.json({content:{sha:'owned-sha'}}); }" +
    " if(options.method === 'DELETE') { const b=JSON.parse(options.body); if(live.get(path)!==b.sha) throw Error('foreign delete'); live.delete(path); return Response.json({}); }" +
    " if(options.method) return new Response('wrong method', {status:400});" +
    " return new Response(live.has(path)?'<?xml version=\"1.0\"?><rss/>':'missing',{status:live.has(path)?200:404});" +
    "}; await import('./scripts/probe-gitee-feed.mjs'); if(live.size) throw Error('not cleaned');";
  const result=spawnSync(process.execPath,['--input-type=module','-e',code],{encoding:'utf8',env:{...process.env,GITEE_TOKEN:'test-only'}});
  assert.equal(result.status,0,result.stderr);
  assert.match(result.stdout,/minimal: POST ok, public 200/);
  assert.match(result.stdout,/full-no-github: POST ok, public 200/);
  assert.equal((result.stdout.match(/cleanup ok/g)||[]).length,2);
  assert.doesNotMatch(result.stdout+result.stderr,/test-only/);
});
