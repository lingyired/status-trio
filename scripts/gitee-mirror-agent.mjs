#!/usr/bin/env node
// Local Agent entry: resolve secrets in this process, reuse the mirror core.
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { synchronize } from './sync-gitee-release.mjs';

export function resolveToken(env = process.env, readKeychain = execFileSync) {
  if (env.GITEE_TOKEN) return env.GITEE_TOKEN;
  try {
    const token = readKeychain('/usr/bin/security', [
      'find-generic-password', '-s', 'status-trio.gitee-token',
      '-a', 'lingyired', '-w',
    ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
    if (token) return token;
  } catch { /* Never include Keychain stdout/stderr or a secret in errors. */ }
  throw new Error('GITEE_TOKEN is not available. Add a generic password in macOS Keychain Access: name status-trio.gitee-token, account lingyired; or provide GITEE_TOKEN to this process. Do not paste the token in chat.');
}

export async function runAgentMirror(args, env = process.env, run = synchronize, readKeychain = execFileSync) {
  const [mode, tag] = args;
  if (args.length !== 2 || !['check', 'sync', 'verify'].includes(mode) || !/^v[0-9]+(?:[.][0-9]+)*(?:[-.][A-Za-z0-9]+)*$/.test(tag ?? '')) {
    throw new Error('Usage: node scripts/gitee-mirror-agent.mjs check|sync|verify <tag>');
  }
  return run({
    mode, tag,
    github: env.GITHUB_REPOSITORY || 'lingyired/status-trio',
    gitee: env.GITEE_REPOSITORY || 'lingyired/status-trio',
    feedURL: env.GITEE_FEED_URL,
    githubToken: env.GH_TOKEN,
    token: mode === 'sync' ? resolveToken(env, readKeychain) : undefined,
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  runAgentMirror(process.argv.slice(2))
    .then(result => console.log(JSON.stringify(result, null, 2)))
    .catch(error => { console.error(error.message); process.exitCode = 1; });
}
