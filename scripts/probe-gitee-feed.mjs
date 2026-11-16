#!/usr/bin/env node
// Diagnostic only: verifies whether Gitee serves a small XML and a full
// Gitee-only appcast. Never touches a real release, appcast or DMG.
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const token = process.env.GITEE_TOKEN;
if (!token) {
  console.error('GITEE_TOKEN is required (enter it locally, never in chat/logs).');
  process.exit(2);
}
const repo = process.env.GITEE_REPOSITORY || 'lingyired/status-trio';
const api = 'https://gitee.com/api/v5/repos/' + repo + '/contents/';
const branch = 'main';

async function create(path, content) {
  const response = await fetch(api + path, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ content: Buffer.from(content).toString('base64'), message: 'diagnostic probe', branch }),
  });
  if (!response.ok) throw new Error('POST ' + path + ' HTTP ' + response.status);
  return response.json();
}
async function remove(path, sha) {
  const response = await fetch(api + path, {
    method: 'DELETE',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ sha, message: 'diagnostic probe cleanup', branch }),
  });
  return response.ok;
}
async function publicStatus(path) {
  const response = await fetch('https://gitee.com/' + repo + '/raw/main/' + path, { redirect: 'follow' });
  const body = Buffer.from(await response.arrayBuffer());
  return { status: response.status, bytes: body.length, head: body.subarray(0, 80).toString('utf8').replace(/\s+/g, ' ') };
}

const minimal = '<?xml version="1.0" encoding="utf-8"?><rss version="2.0"><channel><title>probe</title></channel></rss>';
let full = null;
try {
  const appcast = readFileSync('appcast.xml');
  const match = appcast.toString().match(/<enclosure\s+url="([^"]+)"[\s\S]*?sparkle:edSignature="([^"]+)"[\s\S]*?length="([0-9]+)"/);
  if (match) {
    const dir = mkdtempSync(join(tmpdir(), 'gitee-probe-'));
    writeFileSync(join(dir, 'source.xml'), appcast);
    writeFileSync(join(dir, 'map.json'), JSON.stringify({
      [match[1]]: { url: 'https://gitee.com/' + repo + '/attach_files/0/download/probe.dmg', length: Number(match[3]), signature: match[2] },
    }));
    execFileSync('python3', ['scripts/generate-gitee-appcast.py', join(dir, 'source.xml'), join(dir, 'map.json'), join(dir, 'out.xml'), repo]);
    full = readFileSync(join(dir, 'out.xml'));
    rmSync(dir, { recursive: true, force: true });
  }
} catch (error) {
  console.error('Unable to build full probe feed: ' + error.message);
}

for (const [label, content] of [['minimal', minimal], ['full-no-github', full]]) {
  if (!content) continue;
  const path = 'gitee-feed-probe-' + label + '-' + randomUUID() + '.xml';
  let written;
  try {
    written = await create(path, content);
    const result = await publicStatus(path);
    console.log(label + ': POST ok, public ' + result.status + ', ' + result.bytes + ' bytes, ' + result.head);
  } catch (error) {
    process.exitCode = 1;
    console.error(label + ': ' + error.message);
  } finally {
    if (written?.content?.sha) {
      const removed = await remove(path, written.content.sha);
      console.log(label + ': cleanup ' + (removed ? 'ok' : 'failed; remove ' + path + ' manually'));
      if (!removed) process.exitCode = 1;
    }
  }
}
