import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolveToken, runAgentMirror } from './gitee-mirror-agent.mjs';

test('environment token takes precedence; keychain secret stays internal', () => {
  assert.equal(resolveToken({GITEE_TOKEN:'env-secret'},()=>{throw Error('must not read');}),'env-secret');
  let args;
  assert.equal(resolveToken({},(...values)=>{args=values;return 'keychain-secret\n';}),'keychain-secret');
  assert.equal(args[0],'/usr/bin/security');
  assert.deepEqual(args[1],['find-generic-password','-s','status-trio.gitee-token','-a','lingyired','-w']);
});
test('missing keychain token produces actionable instructions without leaking errors', () => {
  assert.throws(()=>resolveToken({},()=>{throw Error('secret output');}),e=>/Keychain/.test(e.message)&&!e.message.includes('secret output'));
});
test('read-only commands never resolve write credentials', async () => {
  for(const mode of ['check','verify']) {
    let config;
    await runAgentMirror([mode,'v1.9.6'],{GITEE_TOKEN:'write-secret'},async c=>{config=c;return {result:'verified'};},()=>{throw Error('must not access Keychain');});
    assert.equal(config.token,undefined);
  }
});
test('sync uses the same core and credentials without logging them', async () => {
  let config;
  const output=await runAgentMirror(['sync','v1.9.6'],{},async c=>{config=c;return {result:'verified'};},()=> 'keychain-secret');
  assert.equal(config.token,'keychain-secret');assert.equal(config.tag,'v1.9.6');
  assert.deepEqual(output,{result:'verified'});
});
test('invalid command fails before credentials or network', async()=>{
  await assert.rejects(runAgentMirror(['publish','v1.9.6'],{},()=>{throw Error('network');},()=>{throw Error('keychain');}),/Usage/);
});
test('release completion only records local agent handoff',()=>{
  const release=readFileSync('.github/workflows/release.yml','utf8');
  assert.equal(release.includes('actions/workflows/gitee-sync.yml/dispatches'),false);
  assert.match(release,/Gitee mirror pending local Agent sync/);
  const publish=release.slice(release.indexOf('  publish:'));
  assert.match(publish,/actions: read/);assert.doesNotMatch(publish,/actions: write/);
});
