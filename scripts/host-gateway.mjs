import http from 'node:http';
import { pathToFileURL } from 'node:url';

// Fixed loopback upstreams: never proxy arbitrary URLs or Synapse admin/federation APIs.
export function createGateway({ webPort = 3100, matrixPort = 8008 } = {}) {
  return http.createServer((request, response) => {
    const path = request.url || '/';
    if (path === '/healthz') {
      response.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      response.end(JSON.stringify({ service: 'relay-gateway', status: 'running' })); return;
    }
    if (/^\/(?:_synapse|_matrix\/(?!client\/))/.test(path)) { response.writeHead(404); response.end(); return; }
    const isMatrix = path.startsWith('/_matrix/client/');
    const upstream = http.request({ hostname: '127.0.0.1', port: isMatrix ? matrixPort : webPort,
      path, method: request.method, headers: { ...request.headers, host: `127.0.0.1:${isMatrix ? matrixPort : webPort}` }, timeout: 60000,
    }, result => {
      const headers = { ...result.headers, 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'same-origin' };
      if (isMatrix || path.startsWith('/api/')) { headers['Cache-Control'] = 'no-store'; delete headers['expires']; }
      response.writeHead(result.statusCode || 502, headers); result.pipe(response);
    });
    upstream.on('timeout', () => upstream.destroy());
    upstream.on('error', () => { if (!response.headersSent) response.writeHead(502, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); response.end(JSON.stringify({ error: 'Relay is temporarily unavailable. Check the Mac and message server.' })); });
    request.on('aborted', () => upstream.destroy()); response.on('close', () => upstream.destroy());
    request.pipe(upstream);
  });
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.RELAY_GATEWAY_PORT || 3400);
  const gateway = createGateway({ webPort: Number(process.env.RELAY_WEB_PORT || 3100) });
  gateway.listen(port, '127.0.0.1', () => process.stdout.write(`Relay gateway listening on loopback port ${port}\n`));
  process.on('SIGTERM', () => gateway.close(() => process.exit(0)));
}
