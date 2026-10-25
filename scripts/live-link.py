"""Loopback-only WhatsApp pairing display. Never serves account credentials."""
import importlib.util, json, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

spec = importlib.util.spec_from_file_location('live', Path(__file__).with_name('live-matrix.py'))
live = importlib.util.module_from_spec(spec)
spec.loader.exec_module(live)
state = {'image': b'', 'status': 'Waiting for WhatsApp QR…'}

def update():
    room = json.loads((live.PRIVATE/'live-test.json').read_text())['management_room']
    path = 'rooms/' + live.requests.utils.quote(room, safe='') + '/messages?dir=b&limit=12'
    last = None
    while True:
        try:
            events = live.request('GET', path)['chunk']
            for event in events:
                if event.get('sender') != '@whatsappbot:relay.local':
                    continue
                content = event.get('content', {})
                content = content.get('m.new_content', content)
                if content.get('msgtype') == 'm.image' and content.get('url'):
                    url = content['url']
                    if url != last:
                        media = url.removeprefix('mxc://')
                        response = live.requests.get(live.BASE+'/_matrix/client/v1/media/download/'+media,
                            headers={'Authorization':'Bearer '+live.account()['access_token']}, timeout=15)
                        if response.ok:
                            state['image'] = response.content
                            state['status'] = 'Scan with WhatsApp → Settings → Linked Devices → Link a Device.'
                            last = url
                    break
                body = content.get('body','')
                if 'logged in' in body.lower() or 'successfully' in body.lower():
                    state['image'] = b''
                    state['status'] = 'WhatsApp linked. Return to Codex to choose the test conversation.'
                    break
        except Exception:
            state['status'] = 'Waiting for the local bridge…'
        time.sleep(2)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        path = self.path.split('?')[0]
        if path == '/qr.png':
            data, kind = state['image'], 'image/png'
        elif path == '/status':
            data, kind = json.dumps({'status':state['status'],'hasQR':bool(state['image'])}).encode(), 'application/json'
        elif path == '/':
            data = '''<!doctype html><title>Relay · Link WhatsApp</title><style>body{font:20px system-ui;text-align:center;padding:30px;background:#f4f7f5;color:#173c30}img{width:320px;max-width:90vw}p{max-width:650px;margin:25px auto}</style><h1>Link WhatsApp to Relay</h1><p id="status">Preparing QR…</p><img id="qr" hidden><p>History import is off. No conversations are enabled yet.</p><script>async function update(){let s=await(await fetch('/status')).json();document.querySelector('#status').textContent=s.status;let q=document.querySelector('#qr');q.hidden=!s.hasQR;if(s.hasQR)q.src='/qr.png?t='+Date.now()}update();setInterval(update,2500)</script>'''.encode()
            kind = 'text/html; charset=utf-8'
        else:
            self.send_error(404); return
        self.send_response(200)
        self.send_header('Content-Type',kind)
        self.send_header('Cache-Control','no-store')
        self.end_headers(); self.wfile.write(data)

threading.Thread(target=update, daemon=True).start()
print('Local pairing display: http://127.0.0.1:8765', flush=True)
ThreadingHTTPServer(('127.0.0.1',8765), Handler).serve_forever()
