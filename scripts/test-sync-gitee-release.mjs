import test from 'node:test';
import assert from 'node:assert/strict';
import { synchronize, validateManifest, verifyBytes, request } from './sync-gitee-release.mjs';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
const bytes = Buffer.from('original signed dmg');

async function mockMirror(run) {
  const m = manifest();
  const source = '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>42</sparkle:version><enclosure url="' + m.sparkle.download_url + '" length="' + bytes.length + '" sparkle:edSignature="signature"/></item></channel></rss>';
  const state = {release:null, files:new Map(),feed:Buffer.from(source),feedSHA:'initial',writes:[],failure:null};
  const contents = new Map([[m.dmg.filename,bytes],[m.dmg.filename+'.sha256',Buffer.from(sha+'  '+m.dmg.filename+'\n')],['release-manifest.json',Buffer.from(JSON.stringify(m))]]);
  const server = createServer(async (req,res) => {
    const target = new URL(new URL(req.url,'http://local').searchParams.get('url'));
    const p = target.pathname;
    const respond = (value,status=200) => {res.statusCode=status;res.end(Buffer.isBuffer(value)?value:JSON.stringify(value));};
    if (req.method !== 'GET') state.writes.push(p);
    if (state.failure?.(p,req.method)) return respond({message:'secret'},state.status??503);
    if (target.hostname==='api.github.com') {
      assert.equal(req.method,'GET','GitHub is read only');
      if(p.endsWith('/releases/tags/v1.2.3')) return respond({tag_name:m.tag,published_at:'2026-01-01',html_url:'https://github.com/lingyired/status-trio/releases/tag/'+m.tag,assets:[...contents].map(([name,data])=>({name,state:'uploaded',size:data.length,browser_download_url:'https://github.com/lingyired/status-trio/releases/download/'+m.tag+'/'+name}))});
      if(p.endsWith('/commits/v1.2.3')) return respond({sha:m.source_sha});
      if(p.endsWith('/contents/appcast.xml')) return respond({encoding:'base64',content:Buffer.from(source).toString('base64')});
    }
    if(target.hostname==='github.com') return respond(contents.get(decodeURIComponent(p.split('/').at(-1))));
    if(p.includes('/raw/')) return respond(state.feed);
    if(p.includes('/attach_files/') && req.method==='GET') {
      assert.equal(req.headers.authorization,undefined,'Public downloads have no token');
      return respond(state.files.get(p.split('/').at(-1))??Buffer.from('missing'));
    }
    if(p.endsWith('/contents/appcast.xml')) {
      if(req.method==='GET') return respond({sha:state.feedSHA,encoding:'base64',content:state.feed.toString('base64')});
      const chunks=[];for await (const chunk of req) chunks.push(chunk);
      const payload=JSON.parse(Buffer.concat(chunks));
      assert.equal(payload.sha,state.feedSHA);
      state.feed=Buffer.from(payload.content,'base64');state.feedSHA='next';return respond({content:{sha:'next'}});
    }
    if(p.endsWith('/releases') && req.method==='GET') return respond(state.release?[state.release]:[]);
    if(p.endsWith('/releases') && req.method==='POST') {
      const chunks=[];for await (const chunk of req) chunks.push(chunk);
      state.release={...JSON.parse(Buffer.concat(chunks)),id:1,assets:[]};return respond(state.release);
    }
    if(p.endsWith('/releases/1')) return respond(state.release);
    if(p.endsWith('/releases/1/attach_files')) {
      const chunks=[];for await (const chunk of req) chunks.push(chunk);
      const form=await new Response(Buffer.concat(chunks),{headers:{'content-type':req.headers['content-type']}}).formData();
      const file=form.get('file');state.files.set(file.name,Buffer.from(await file.arrayBuffer()));
      state.release.assets.push({name:file.name,browser_download_url:'https://gitee.com/lingyired/status-trio/attach_files/1/download/'+file.name});
      return respond({});
    }
    respond({error:'unknown '+p},404);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const original=globalThis.fetch;
  globalThis.fetch=(url,options)=>original('http://127.0.0.1:'+server.address().port+'/?url='+encodeURIComponent(url),options);
  try { await run(state); } finally {globalThis.fetch=original;await new Promise(resolve=>server.close(resolve));}
}
const sync=()=>synchronize({mode:'sync',tag:'v1.2.3',token:'secret'});
test('first sync, repeat, check and verify reuse the original attachments',async()=>mockMirror(async state=>{
  assert.equal((await sync()).result,'verified');
  const count=state.writes.length;
  await sync();assert.equal(state.writes.length,count);
  await synchronize({mode:'check',tag:'v1.2.3'});await synchronize({mode:'verify',tag:'v1.2.3'});
  assert.equal(state.writes.length,count);
}));
for (const status of [401,413,503]) test('upload HTTP '+status+' keeps previous feed and can resume',async()=>mockMirror(async state=>{
  const original=Buffer.from(state.feed);state.status=status;state.failure=(p,method)=>p.endsWith('/attach_files')&&method==='POST';
  await assert.rejects(sync());assert.deepEqual(state.feed,original);
  state.failure=null;await sync();assert.equal(state.files.size,3);
}));
test('partly uploaded release resumes without a second DMG upload',async()=>mockMirror(async state=>{
  state.failure=(p,method)=>p.endsWith('/attach_files')&&method==='POST'&&state.files.size===1;
  await assert.rejects(sync());assert.equal(state.files.size,1);
  state.failure=null;await sync();assert.equal(state.release.assets.length,3);
}));
test('feed update failure preserves uploaded package for recovery',async()=>mockMirror(async state=>{
  state.failure=(p,method)=>p.endsWith('/contents/appcast.xml')&&method==='PUT';
  await assert.rejects(sync());assert.equal(state.files.size,3);
  state.failure=null;await sync();assert.equal(state.release.assets.length,3);
}));
test('same tag with different bytes fails without replacing attachment',async()=>mockMirror(async state=>{
  await sync();state.files.set('StatusTrio-1.2.3.dmg',Buffer.from('tampered'));const count=state.writes.length;
  await assert.rejects(sync());assert.equal(state.writes.length,count);
}));

const sha = createHash('sha256').update(bytes).digest('hex');
const manifest = () => ({schema_version:1, version:'1.2.3',build:'42',tag:'v1.2.3',source_sha:'a'.repeat(40),minimum_system_version:'13.0',signing:{kind:'developer-id',notarization_status:'accepted'},dmg:{filename:'StatusTrio-1.2.3.dmg',length:bytes.length,sha256:sha},sparkle:{signature:'signature',download_url:'https://github.com/lingyired/status-trio/releases/download/v1.2.3/StatusTrio-1.2.3.dmg'}});
test('manifest identity and signed public package required', () => {
  assert.doesNotThrow(() => validateManifest(manifest(), 'v1.2.3', 'lingyired/status-trio', 'a'.repeat(40)));
  for (const mutate of [m => m.source_sha='b'.repeat(40), m => m.signing.notarization_status='skipped',m => m.tag='v1.0',m => m.dmg.filename='../diagnostic.dmg',m => m.sparkle.download_url='https://evil.test/a.dmg']) {
    const m = manifest(); mutate(m); assert.throws(() => validateManifest(m,'v1.2.3','lingyired/status-trio','a'.repeat(40)));
  }
});
test('byte identity cannot be overwritten', () => {
  assert.doesNotThrow(() => verifyBytes(bytes,manifest().dmg));
  assert.throws(() => verifyBytes(Buffer.from('different'),manifest().dmg));
});
test('HTTP errors redact token and response body', async () => {
  await assert.rejects(request('https://gitee.com/api/v5/test', {token:'secret',fetch:async () => new Response('secret detail',{status:401})}), e => !e.message.includes('secret') && e.message.includes('401'));
});
