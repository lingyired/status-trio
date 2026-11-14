#!/usr/bin/env node
// CI and local Skill entry point. Never builds, signs, or rolls back GitHub.
import { createHash } from 'node:crypto';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';

const fail = message => { throw new Error(message); };
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
export function validateManifest(m, tag, repo, sha) {
  if (m?.schema_version !== 1 || m.tag !== tag || m.source_sha !== sha || !/^[a-f0-9]{40}$/.test(sha) ||
      !/^[0-9]+(?:[.][0-9]+)*$/.test(m.version) || !/^[0-9]+$/.test(String(m.build)) ||
      m.minimum_system_version !== '13.0' || m.signing?.kind !== 'developer-id' || m.signing?.notarization_status !== 'accepted' ||
      !/^StatusTrio-[A-Za-z0-9._-]+[.]dmg$/.test(m.dmg?.filename) || !/^[a-f0-9]{64}$/.test(m.dmg?.sha256) ||
      !Number.isSafeInteger(m.dmg?.length) || m.dmg.length <= 0 || !m.sparkle?.signature ||
      m.sparkle.download_url !== 'https://github.com/' + repo + '/releases/download/' + tag + '/' + m.dmg.filename) {
    fail('Release manifest identity / notarized package contract mismatch');
  }
}
export function verifyBytes(bytes, dmg) {
  if (bytes.length !== dmg.length || hash(bytes) !== dmg.sha256) fail('Public attachment length / SHA-256 conflict; refusing overwrite');
}
export async function request(url, options = {}) {
  const { token, fetch: fetcher = fetch, method = 'GET', body, headers = {}, missing = false } = options;
  let response;
  try {
    response = await fetcher(url, { method, body, headers: {...headers, ...(token ? {Authorization:'Bearer ' + token} : {})}, signal:AbortSignal.timeout(300_000), redirect: token ? 'error' : 'follow' });
  } catch { fail('Network request failed (timeout, TLS, or redirect); retry the same tag after diagnosis'); }
  if (missing && response.status === 404) return null;
  if (!response.ok) fail('Remote request failed: HTTP ' + response.status);
  return response;
}
const json = async (url, options) => (await request(url, options))?.json();
const bytes = async url => Buffer.from(await (await request(url)).arrayBuffer());
const repoPath = value => {
  const repo = value?.replace(/^https:\/\/(github|gitee)[.]com\//, '').replace(/[.]git$/, '');
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo ?? '')) fail('Repository must be owner/repo');
  return repo;
};
const attachmentList = release => Array.isArray(release.assets) ? release.assets : release.assets?.links ?? [];
const attachmentURL = asset => asset.browser_download_url ?? asset.download_url;

export async function synchronize(config) {
  const started = Date.now();
  const { mode, tag, token, githubToken, feedURL } = config;
  if (!['check','sync','verify'].includes(mode) || !/^v[0-9]+(?:[.][0-9]+)*(?:[-.][A-Za-z0-9]+)*$/.test(tag ?? '')) fail('Usage: check|sync|verify <tag>');
  const github = repoPath(config.github || 'lingyired/status-trio');
  const gitee = repoPath(config.gitee || 'lingyired/status-trio');
  const gh = 'https://api.github.com/repos/' + github;
  const gt = 'https://gitee.com/api/v5/repos/' + gitee;
  const feed = feedURL || 'https://gitee.com/' + gitee + '/raw/main/appcast-gitee.xml';
  if (new URL(feed).protocol !== 'https:' || new URL(feed).host !== 'gitee.com') fail('Feed must be a public Gitee HTTPS URL');
  const ghOptions = {token:githubToken};
  const release = await json(gh + '/releases/tags/' + encodeURIComponent(tag), ghOptions);
  if (release.draft || release.prerelease || release.tag_name !== tag || !release.published_at || release.html_url !== 'https://github.com/' + github + '/releases/tag/' + tag) fail('Not an authoritative published stable GitHub Release');
  const commit = await json(gh + '/commits/' + encodeURIComponent(tag), ghOptions);
  const asset = name => {
    const matches = release.assets.filter(a => a.name === name && a.state === 'uploaded');
    if (matches.length !== 1) fail('Missing or ambiguous GitHub asset: ' + name);
    const url = 'https://github.com/' + github + '/releases/download/' + tag + '/' + name;
    if (matches[0].browser_download_url !== url) fail('GitHub asset URL identity mismatch');
    return matches[0];
  };
  const manifestAsset = asset('release-manifest.json');
  const manifestBytes = await bytes(manifestAsset.browser_download_url);
  const manifest = JSON.parse(manifestBytes);
  validateManifest(manifest, tag, github, commit.sha);
  const dmgAsset = asset(manifest.dmg.filename);
  if (dmgAsset.size !== manifest.dmg.length) fail('GitHub asset metadata length mismatch');
  const checksum = await bytes(asset(manifest.dmg.filename + '.sha256').browser_download_url);
  if (checksum.toString().trim() !== manifest.dmg.sha256 + '  ' + manifest.dmg.filename) fail('Checksum sidecar identity mismatch');
  const dmg = await bytes(dmgAsset.browser_download_url);
  verifyBytes(dmg, manifest.dmg);
  const sourceFile = await json(gh + '/contents/appcast.xml?ref=main', ghOptions);
  if (sourceFile.encoding !== 'base64') fail('Unsupported authoritative feed encoding');
  const source = Buffer.from(sourceFile.content, 'base64');
  const remoteFile = await json(gt + '/contents/appcast-gitee.xml?ref=main', {missing:true});
  if (remoteFile && remoteFile.encoding !== 'base64') fail('Unsupported Gitee feed encoding');
  if (mode !== 'sync') {
    // Read-only modes still require an already usable public feed.
    await request(feed);
    if (!remoteFile?.sha) fail('Mirror appcast is missing');
  }
  let releases = [];
  for (let page=1; ; page++) {
    const batch = await json(gt + '/releases?per_page=100&page=' + page);
    releases.push(...batch);
    if (batch.length < 100) break;
    if (page >= 100) fail('Too many releases; refusing incomplete retention view');
  }
  let mirror = releases.find(r => r.tag_name === tag);
  if (releases.filter(r => r.tag_name === tag).length > 1) fail('Ambiguous Gitee tag');
  const marker = 'Status Trio mirror SHA-256: ' + manifest.dmg.sha256;
  if (mirror && (!mirror.body?.includes(marker) || mirror.prerelease || mirror.target_commitish !== manifest.source_sha)) fail('Existing Gitee release identity conflict; refusing overwrite');
  if (mode === 'sync' && !token) fail('GITEE_TOKEN required for sync');
  if (!mirror && mode !== 'sync') fail('Mirror release is missing');
  const mutate = async (url, data, method='POST') => json(url, {token, method, body:JSON.stringify(data), headers:{'Content-Type':'application/json'}});
  if (!mirror) {
    mirror = await mutate(gt + '/releases', {tag_name:tag, name:release.name || tag, target_commitish:manifest.source_sha, body:marker + '\nAuthoritative release: ' + release.html_url, prerelease:false});
  }
  const files = [[manifest.dmg.filename,dmg],[manifest.dmg.filename + '.sha256',checksum],['release-manifest.json',manifestBytes]];
  let mirrorURL;
  for (const [name, content] of files) {
    mirror = await json(gt + '/releases/' + mirror.id);
    const matches = attachmentList(mirror).filter(a => a.name === name);
    if (matches.length > 1) fail('Duplicate Gitee attachment name');
    let existing = matches[0];
    if (!existing) {
      if (mode !== 'sync') fail('Mirror attachment missing: ' + name);
      const form = new FormData();
      form.set('file', new Blob([content]), name);
      await request(gt + '/releases/' + mirror.id + '/attach_files', {method:'POST',token,body:form});
      mirror = await json(gt + '/releases/' + mirror.id);
      existing = attachmentList(mirror).find(a => a.name === name);
      if (!existing) fail('Uploaded attachment not visible; retry same tag');
    }
    const url = attachmentURL(existing);
    if (!url || new URL(url).protocol !== 'https:' || new URL(url).hostname !== 'gitee.com') fail('Unexpected Gitee attachment URL');
    // Public download deliberately carries no credentials.
    const publicBytes = await bytes(url);
    if (publicBytes.length !== content.length || hash(publicBytes) !== hash(content)) fail('Existing Gitee attachment differs; refusing overwrite');
    if (name === manifest.dmg.filename) mirrorURL = url;
  }
  const directory = await mkdtemp(join(tmpdir(), 'status-trio-gitee-'));
  let derived;
  try {
    const mappings = {[manifest.sparkle.download_url]:{url:mirrorURL,length:manifest.dmg.length,signature:manifest.sparkle.signature}};
    await writeFile(join(directory,'source.xml'),source);
    await writeFile(join(directory,'map.json'),JSON.stringify(mappings));
    execFileSync('python3',[join(dirname(fileURLToPath(import.meta.url)),'generate-gitee-appcast.py'),join(directory,'source.xml'),join(directory,'map.json'),join(directory,'output.xml'),gitee],{stdio:['ignore','pipe','pipe']});
    derived = await readFile(join(directory,'output.xml'));
  } finally { await rm(directory,{recursive:true,force:true}); }
  // No deletion: unselected history reverts to authoritative GitHub URLs.
  // Capacity reclamation remains disabled until the real API is qualified.
  if (mode === 'sync') {
    const current = remoteFile
      ? await json(gt + '/contents/appcast-gitee.xml?ref=main', {missing:true})
      : null;
    if (remoteFile && current?.sha !== remoteFile.sha) fail('Gitee feed changed concurrently; retry same tag');
    if (!current || !Buffer.from(current.content,'base64').equals(derived)) {
      await mutate(gt + '/contents/appcast-gitee.xml',{...(current?.sha ? {sha:current.sha} : {}),branch:'main',message:'Mirror verified ' + tag,content:derived.toString('base64')},'PUT');
    }
  }
  const publicFeed = await bytes(feed);
  if (!publicFeed.equals(derived)) fail('Public feed not converged; attachment is safe, retry same tag after cache refresh');
  return {mode,tag,version:manifest.version,build:manifest.build,sha256:manifest.dmg.sha256,github:manifest.sparkle.download_url,gitee:mirrorURL,feed,elapsed_ms:Date.now()-started,result:'verified',retention:'No automatic deletion until Gitee API qualification'};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [mode,tag] = process.argv.slice(2);
  synchronize({mode,tag,github:process.env.GITHUB_REPOSITORY,gitee:process.env.GITEE_REPOSITORY,token:process.env.GITEE_TOKEN,githubToken:process.env.GH_TOKEN,feedURL:process.env.GITEE_FEED_URL})
    .then(result => console.log(JSON.stringify(result,null,2)))
    .catch(() => { console.error('Gitee mirror verification/sync failed. No GitHub mutation performed. Inspect configuration and retry the same tag; credentials and response bodies are intentionally omitted.'); process.exitCode=1; });
}
