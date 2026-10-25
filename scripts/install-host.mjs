import { mkdir, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
const root = resolve(import.meta.dirname, '..');
const escape = text => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const logs = resolve(root, 'artifacts'); await mkdir(logs, { recursive: true });
const agents = resolve(homedir(), 'Library/LaunchAgents'); await mkdir(agents, { recursive: true });
const destination = resolve(agents, 'app.relay.host.plist');
const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>app.relay.host</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>${escape(resolve(root, 'scripts/start-host.sh'))}</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>10</integer>
<key>WorkingDirectory</key><string>${escape(root)}</string>
<key>StandardOutPath</key><string>${escape(resolve(logs, 'host.log'))}</string>
<key>StandardErrorPath</key><string>${escape(resolve(logs, 'host-error.log'))}</string>
</dict></plist>`;
await writeFile(destination, plist, { mode: 0o600 });
console.log(`Prepared ${destination}`);
if (process.argv.includes('--start')) {
  spawnSync('launchctl', ['bootout', `gui/${process.getuid()}`, destination], { stdio: 'ignore' });
  const result = spawnSync('launchctl', ['bootstrap', `gui/${process.getuid()}`, destination], { stdio: 'inherit' });
  process.exitCode = result.status || 0;
}
