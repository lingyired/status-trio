#!/usr/bin/env node
// CI and local Skill entry point. Never builds, signs, or rolls back GitHub.
import { createHash } from 'node:crypto';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';

let stage = 'initializing';
const nativeFetch = globalThis.fetch;
const fail = message => { throw new Error(stage + ': ' + message); };
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
export function validateManifest(m, tag, repo, sha) {
  const schemaOk =
    m?.schema_version === 1 ||
    (m?.schema_version === 2 &&
      m?.candidate?.publishable === true &&
      m?.candidate?.source_sha === m?.source_sha);
  if (!schemaOk || m.tag !== tag || m.source_sha !== sha || !/^[a-f0-9]{40}$/.test(sha) ||
      !/^[0-9]+(?:[.][0-9]+)*$/.test(m.version) || !/^[0-9]+$/.test(String(m.build)) ||
      m.minimum_system_version !== '13.0' || m.signing?.kind !== 'developer_id' ||
      m.notarization?.status !== 'accepted_and_stapled' ||
      !/^StatusTrio-[A-Za-z0-9._-]+[.]dmg$/.test(m.dmg?.filename) || !/^[a-f0-9]{64}$/.test(m.dmg?.sha256) ||
      !/^[1-9][0-9]*$/.test(String(m.dmg?.length)) || !m.dmg?.ed_signature ||
      !/^StatusTrio-[A-Za-z0-9._-]+[.]zip$/.test(m.zip?.filename) || !/^[a-f0-9]{64}$/.test(m.zip?.sha256) ||
      !/^[1-9][0-9]*$/.test(String(m.zip?.length)) || !m.zip?.ed_signature ||
      m.zip?.ed_signature === 'diagnostic-not-for-publication' ||
      m.release?.repo !== repo) {
    fail('Release manifest identity / notarized package contract mismatch');
  }
}
export function verifyBytes(bytes, entry) {
  if (bytes.length !== Number(entry.length) || hash(bytes) !== entry.sha256) fail('Public attachment length / SHA-256 conflict; refusing overwrite');
}

/// Highest build advertised by an appcast and the version string that claims
/// it. Used to keep a mirror from replacing a newer feed with an older tag.
export function feedIdentity(xml) {
  let build = null;
  let version = null;
  for (const item of String(xml).matchAll(/<item>([\s\S]*?)<\/item>/g)) {
    const match = /<sparkle:version>\s*([0-9]+)\s*<\/sparkle:version>/.exec(item[1]);
    if (!match) continue;
    const candidate = Number(match[1]);
    if (build === null || candidate > build) {
      build = candidate;
      version = /<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>/.exec(item[1])?.[1] ?? null;
    }
  }
  return { build, version };
}

function refuseFeedDowngrade(bytes, manifest) {
  const identity = feedIdentity(bytes);
  if (identity.build === null) return;
  if (identity.build > Number(manifest.build)) {
    fail('Gitee feed already advertises build ' + identity.build + '; refusing to replace it with older build ' + manifest.build);
  }
  if (identity.build === Number(manifest.build) && identity.version !== null && identity.version !== manifest.version) {
    fail('Gitee feed already uses build ' + identity.build + ' for version ' + identity.version + '; refusing identity conflict');
  }
}
export async function request(url, options = {}) {
  const { token, fetch: fetcher = fetch, method = 'GET', body, headers = {}, missing = false } = options;
  let response;
  try {
    response = await fetcher(url, { method, body, headers: {...headers, ...(token ? {Authorization:'Bearer ' + token} : {})}, signal:AbortSignal.timeout(300_000), redirect: token ? 'error' : 'follow' });
  } catch { fail('network request failed (timeout, TLS, or redirect)'); }
  if (missing && response.status === 404) return null;
  if (!response.ok) fail('HTTP ' + response.status);
  return response;
}
const json = async (url, options) => (await request(url, options))?.json();
const bytes = async url => Buffer.from(await (await request(url)).arrayBuffer());
async function uploadAttachment(url, name, content, token) {
  // Node's FormData upload can stall on Gitee for multi-megabyte files; curl
  // sends a bounded multipart request. Tests replace global fetch, in which
  // case the in-memory transport is used instead.
  if (globalThis.fetch !== nativeFetch) {
    const form = new FormData();
    form.set('access_token', token);
    form.set('file', new Blob([content]), name);
    await request(url, { method: 'POST', token, body: form });
    return;
  }
  const directory = await mkdtemp(join(tmpdir(), 'status-trio-upload-'));
  const file = join(directory, name);
  try {
    await writeFile(file, content);
    const credentialFile = join(directory, 'upload-token');
    await writeFile(credentialFile, token, { mode: 0o600 });
    let output;
    try {
      output = execFileSync('curl', [
        '--silent', '--show-error', '--max-time', '900',
        '--write-out', '\\n%{http_code}',
        '--form', 'access_token=<' + credentialFile,
        '--form', 'file=@' + file,
        url,
      ], { encoding: 'utf8', maxBuffer: 1024 * 1024 });
    } catch {
      fail('network upload failed');
    }
    const code = output.trim().split('\n').pop();
    if (!/^2[0-9][0-9]$/.test(code ?? '')) fail('HTTP ' + code);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

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
  stage = 'reading GitHub release';
  const release = await json(gh + '/releases/tags/' + encodeURIComponent(tag), ghOptions);
  if (release.draft || release.prerelease || release.tag_name !== tag || !release.published_at || release.html_url !== 'https://github.com/' + github + '/releases/tag/' + tag) fail('Not an authoritative published stable GitHub Release');
  stage = 'resolving GitHub commit';
  const commit = await json(gh + '/commits/' + encodeURIComponent(tag), ghOptions);
  const asset = name => {
    const matches = release.assets.filter(a => a.name === name && a.state === 'uploaded');
    if (matches.length !== 1) fail('Missing or ambiguous GitHub asset: ' + name);
    const url = 'https://github.com/' + github + '/releases/download/' + tag + '/' + name;
    if (matches[0].browser_download_url !== url) fail('GitHub asset URL identity mismatch');
    return matches[0];
  };
  // Download through the API asset endpoint: github.com release redirects are
  // blocked on some networks even when api.github.com is reachable.
  const assetBytes = async item => Buffer.from(await (await request(item.url, {
    headers: { Accept: 'application/octet-stream' },
  })).arrayBuffer());
  stage = 'reading release manifest';
  const manifestAsset = asset('release-manifest.json');
  const manifestBytes = await assetBytes(manifestAsset);
  const manifest = JSON.parse(manifestBytes);
  validateManifest(manifest, tag, github, commit.sha);
  const dmgAsset = asset(manifest.dmg.filename);
  if (dmgAsset.size !== Number(manifest.dmg.length)) fail('GitHub DMG metadata length mismatch');
  const dmgChecksum = await assetBytes(asset(manifest.dmg.filename + '.sha256'));
  if (dmgChecksum.toString().trim() !== manifest.dmg.sha256 + '  ' + manifest.dmg.filename) fail('DMG checksum sidecar mismatch');
  const zipAsset = asset(manifest.zip.filename);
  if (zipAsset.size !== Number(manifest.zip.length)) fail('GitHub ZIP metadata length mismatch');
  const zipChecksum = await assetBytes(asset(manifest.zip.filename + '.sha256'));
  if (zipChecksum.toString().trim() !== manifest.zip.sha256 + '  ' + manifest.zip.filename) fail('ZIP checksum sidecar mismatch');
  stage = 'downloading GitHub ZIP';
  const archive = config.localZip ? await readFile(config.localZip) : await assetBytes(zipAsset);
  verifyBytes(archive, manifest.zip);
  const sourceFile = await json(gh + '/contents/appcast.xml?ref=main', ghOptions);
  if (sourceFile.encoding !== 'base64') fail('Unsupported authoritative feed encoding');
  const source = Buffer.from(sourceFile.content, 'base64');
  stage = 'reading Gitee feed metadata';
  const remoteFileValue = await json(gt + '/contents/appcast-gitee.xml?ref=main', {missing:true});
  // Gitee returns 200 [] for a missing file, unlike GitHub's 404.
  const remoteFile = Array.isArray(remoteFileValue) ? null : remoteFileValue;
  if (remoteFile && remoteFile.encoding !== 'base64') fail('Unsupported Gitee feed encoding');
  if (remoteFile) refuseFeedDowngrade(Buffer.from(remoteFile.content, 'base64'), manifest);
  if (mode !== 'sync') {
    // Read-only modes still require an already usable public feed.
    await request(feed);
    if (!remoteFile?.sha) fail('Mirror appcast is missing');
  }
  stage = 'listing Gitee releases';
  let releases = [];
  for (let page=1; ; page++) {
    const batch = await json(gt + '/releases?per_page=100&page=' + page);
    releases.push(...batch);
    if (batch.length < 100) break;
    if (page >= 100) fail('Too many releases; refusing incomplete retention view');
  }
  let mirror = releases.find(r => r.tag_name === tag);
  if (releases.filter(r => r.tag_name === tag).length > 1) fail('Ambiguous Gitee tag');
  const marker = 'Status Trio mirror ZIP SHA-256: ' + manifest.zip.sha256;
  const sourceMarker = 'Source commit: ' + manifest.source_sha;
  if (mirror && (!mirror.body?.includes(marker) || !mirror.body?.includes(sourceMarker) || mirror.prerelease)) fail('Existing Gitee release identity conflict; refusing overwrite');
  if (mode === 'sync' && !token) fail('GITEE_TOKEN required for sync');
  if (!mirror && mode !== 'sync') fail('Mirror release is missing');
  const mutate = async (url, data, method='POST') => json(url, {token, method, body:JSON.stringify(data), headers:{'Content-Type':'application/json'}});
  if (!mirror) {
    stage = 'creating Gitee release';
    mirror = await mutate(gt + '/releases', {tag_name:tag, name:release.name || tag, target_commitish:'main', body:marker + '\n' + sourceMarker + '\nAuthoritative release: ' + release.html_url, prerelease:false});
  }
  const files = [[manifest.zip.filename,archive],[manifest.zip.filename + '.sha256',zipChecksum],['release-manifest.json',manifestBytes]];
  let mirrorURL;
  for (const [name, content] of files) {
    mirror = await json(gt + '/releases/' + mirror.id);
    const matches = attachmentList(mirror).filter(a => a.name === name);
    if (matches.length > 1) fail('Duplicate Gitee attachment name');
    let existing = matches[0];
    if (!existing) {
      if (mode !== 'sync') fail('Mirror attachment missing: ' + name);
      stage = 'uploading ' + name;
      await uploadAttachment(gt + '/releases/' + mirror.id + '/attach_files', name, content, token);
      mirror = await json(gt + '/releases/' + mirror.id);
      existing = attachmentList(mirror).find(a => a.name === name);
      if (!existing) fail('Uploaded attachment not visible; retry same tag');
    }
    const url = attachmentURL(existing);
    if (!url || new URL(url).protocol !== 'https:' || new URL(url).hostname !== 'gitee.com') fail('Unexpected Gitee attachment URL');
    // Public download deliberately carries no credentials.
    const publicBytes = await bytes(url);
    if (publicBytes.length !== content.length || hash(publicBytes) !== hash(content)) fail('Existing Gitee attachment differs; refusing overwrite');
    if (name === manifest.zip.filename) mirrorURL = url;
  }
  const directory = await mkdtemp(join(tmpdir(), 'status-trio-gitee-'));
  let derived;
  try {
    const authoritativeDownload = 'https://github.com/' + github + '/releases/download/' + tag + '/' + manifest.dmg.filename;
    const mappings = {[authoritativeDownload]:{
      url:mirrorURL,
      source_length:String(manifest.dmg.length),
      source_signature:manifest.dmg.ed_signature,
      length:Number(manifest.zip.length),
      signature:manifest.zip.ed_signature,
    }};
    await writeFile(join(directory,'source.xml'),source);
    await writeFile(join(directory,'map.json'),JSON.stringify(mappings));
    execFileSync('python3',[join(dirname(fileURLToPath(import.meta.url)),'generate-gitee-appcast.py'),join(directory,'source.xml'),join(directory,'map.json'),join(directory,'output.xml'),gitee],{stdio:['ignore','pipe','pipe']});
    derived = await readFile(join(directory,'output.xml'));
  } finally { await rm(directory,{recursive:true,force:true}); }
  // No deletion: unselected history reverts to authoritative GitHub URLs.
  // Capacity reclamation remains disabled until the real API is qualified.
  if (mode === 'sync') {
    stage = 're-reading Gitee feed';
    const currentValue = remoteFile
      ? await json(gt + '/contents/appcast-gitee.xml?ref=main', {missing:true})
      : null;
    const current = Array.isArray(currentValue) ? null : currentValue;
    if (current) refuseFeedDowngrade(Buffer.from(current.content, 'base64'), manifest);
    if (remoteFile && current?.sha !== remoteFile.sha) fail('Gitee feed changed concurrently; retry same tag');
    if (!current || !Buffer.from(current.content,'base64').equals(derived)) {
      stage = 'writing Gitee feed';
      await mutate(gt + '/contents/appcast-gitee.xml',{...(current?.sha ? {sha:current.sha} : {}),branch:'main',message:'Mirror verified ' + tag,content:derived.toString('base64')},current ? 'PUT' : 'POST');
    }
  }
  stage = 'verifying public Gitee feed';
  const publicFeed = await bytes(feed);
  if (!publicFeed.equals(derived)) fail('Public feed not converged; attachment is safe, retry same tag after cache refresh');
  return {mode,tag,version:manifest.version,build:manifest.build,zip_sha256:manifest.zip.sha256,github_dmg:'https://github.com/' + github + '/releases/download/' + tag + '/' + manifest.dmg.filename,github_zip:'https://github.com/' + github + '/releases/download/' + tag + '/' + manifest.zip.filename,gitee:mirrorURL,feed,elapsed_ms:Date.now()-started,result:'verified',retention:'No automatic deletion until Gitee API qualification'};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [mode,tag] = process.argv.slice(2);
  synchronize({mode,tag,github:process.env.GITHUB_REPOSITORY,gitee:process.env.GITEE_REPOSITORY,token:process.env.GITEE_TOKEN,githubToken:process.env.GH_TOKEN,feedURL:process.env.GITEE_FEED_URL,localZip:process.env.GITEE_LOCAL_ZIP})
    .then(result => console.log(JSON.stringify(result,null,2)))
    .catch(error => { console.error('Gitee mirror verification/sync failed: ' + (error?.message || 'unknown error')); console.error('No GitHub mutation performed. Credentials and response bodies are intentionally omitted; retry the same tag.'); process.exitCode=1; });
}
