#!/usr/bin/env python3
"""
Minimal web UI for pia-wg-firewalla.
Started automatically when WEB_PORT is set (default 8080, 0 = disabled).
Requires only Python 3 stdlib — no pip packages.
"""
import json, os, subprocess, sys, time, html as _html
from http.server import BaseHTTPRequestHandler, HTTPServer

DATA_DIR = os.environ.get('DATA_DIR', '/data/pia-wg')
SCRIPT   = '/app/pia-wg-firewalla.sh'

CONFIG_FIELDS = [
    # (env_key, label, is_sensitive)
    ('PIA_USER',                 'PIA Username',               False),
    ('PIA_PASS',                 'PIA Password',               True),
    ('DIP_TOKEN',                'Dedicated IP Token',         True),
    ('PIA_REGION',               'Region (ignored if DIP set)', False),
    ('FIREWALLA_PROFILE_ID',     'Firewalla Profile ID',       False),
    ('WG_MANAGED_BY_FIREWALLA',  'Firewalla Manages Interface', False),
    ('WG_DNS_OVERRIDE',          'DNS Override (blank = PIA)', False),
    ('WATCHDOG_INTERVAL',        'Watchdog Interval (s)',      False),
    ('MAX_DOWN_TIME',            'Max Down Time before reconnect (s)', False),
    ('VPN_CHECK_IP',             'Connectivity Ping IP',       False),
    ('KEY_REFRESH_INTERVAL',     'Key Refresh Interval (s)',   False),
]

# ─── helpers ──────────────────────────────────────────────────────────────────

def _read(path, default=''):
    try:
        with open(path) as f: return f.read().strip()
    except: return default

def _age(path):
    try: return int(time.time() - os.path.getmtime(path))
    except: return None

def _run(*args, timeout=60):
    try:
        r = subprocess.run(list(args), capture_output=True, text=True,
                           timeout=timeout, env=dict(os.environ))
        return (r.stdout + r.stderr).strip(), r.returncode == 0
    except subprocess.TimeoutExpired:
        return 'Command timed out', False
    except Exception as e:
        return str(e), False

def _log_path():
    return f'{DATA_DIR}/pia-wg.log'

# ─── status ───────────────────────────────────────────────────────────────────

def get_status():
    profile_id   = os.environ.get('FIREWALLA_PROFILE_ID', '')
    profile_name = os.environ.get('PROFILE_NAME', 'PIA_WG')
    managed      = os.environ.get('WG_MANAGED_BY_FIREWALLA', 'false').lower() == 'true'

    if managed and profile_id:
        iface = f'vpn_{profile_id}'
        mode  = 'app-integration'
    elif managed:
        iface = f'vpn_{profile_name}'
        mode  = 'legacy'
    else:
        iface = profile_name[:15]
        mode  = 'standalone'

    wg_up, handshake_age = False, None
    try:
        r = subprocess.run(['wg', 'show', iface, 'latest-handshakes'],
                           capture_output=True, text=True, timeout=5)
        wg_up = r.returncode == 0
        for line in r.stdout.strip().split('\n'):
            parts = line.split()
            if len(parts) >= 2 and parts[1] != '0':
                handshake_age = int(time.time()) - int(parts[1])
    except: pass

    token_age    = _age(f'{DATA_DIR}/token')
    token_ttl    = int(os.environ.get('TOKEN_TTL', 72000))
    key_age      = _age(f'{DATA_DIR}/last_setup')
    key_interval = int(os.environ.get('KEY_REFRESH_INTERVAL', 150))

    server = {}
    try:
        s = json.loads(_read(f'{DATA_DIR}/server.json', '{}'))
        server['peer_ip']     = s.get('peer_ip', '')
        server['server_port'] = s.get('server_port', '')
    except: pass
    try:
        d = json.loads(_read(f'{DATA_DIR}/dip_server.json', '{}'))
        server['cn'] = d.get('cn', '')
        server['ip'] = d.get('ip', '')
    except: pass

    return dict(
        interface=iface, up=wg_up, mode=mode,
        handshake_age=handshake_age,
        token_age=token_age, token_ttl=token_ttl,
        token_valid=token_age is not None and token_age < token_ttl,
        key_age=key_age, key_interval=key_interval,
        key_fresh=key_age is not None and key_age < key_interval,
        server=server,
    )

# ─── config ──────────────────────────────────────────────────────────────────

def load_cfg():
    cfg = {k: os.environ.get(k, '') for k, _, _ in CONFIG_FIELDS}
    try:
        with open(f'{DATA_DIR}/.env') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, _, v = line.partition('=')
                    cfg[k.strip()] = v.strip().strip('"\'')
    except: pass
    return cfg

def save_cfg(updates):
    cfg = load_cfg()
    known = {k for k, _, _ in CONFIG_FIELDS}
    cfg.update({k: v for k, v in updates.items() if k in known})
    path = f'{DATA_DIR}/.env'
    with open(path, 'w') as f:
        f.write('# pia-wg configuration — managed by web UI\n')
        for k, v in cfg.items():
            if k and v:
                f.write(f'{k}={v}\n')
    os.chmod(path, 0o600)

# ─── logs ────────────────────────────────────────────────────────────────────

def tail_log(n=120):
    try:
        with open(_log_path()) as f:
            lines = f.readlines()
        return ''.join(lines[-n:]) if lines else '(log is empty)'
    except:
        return ('No log file yet.\n'
                'Logs appear here once the container has been running.\n'
                'To watch live: docker compose logs -f')

# ─── HTML (single-file, no CDN dependencies) ─────────────────────────────────

PAGE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>PIA WireGuard</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:system-ui,-apple-system,sans-serif;background:#f3f4f6;color:#111827;padding:16px;max-width:900px;margin:0 auto}
h1{font-size:1.35rem;font-weight:700;color:#1d4ed8;margin-bottom:16px;display:flex;align-items:center;gap:8px}
.card{background:#fff;border-radius:10px;padding:18px;margin-bottom:16px;box-shadow:0 1px 4px rgba(0,0,0,.08)}
h2{font-size:.95rem;font-weight:600;color:#374151;margin-bottom:14px;border-bottom:1px solid #f0f0f0;padding-bottom:8px}
.row{display:flex;flex-wrap:wrap;gap:14px}
.col{flex:1;min-width:160px;background:#f9fafb;border-radius:8px;padding:10px}
.lbl{font-size:10px;text-transform:uppercase;letter-spacing:.06em;color:#9ca3af;margin-bottom:3px}
.val{font-size:.92rem;font-weight:600;color:#111827}
.badge{display:inline-block;padding:2px 9px;border-radius:9999px;font-size:11px;font-weight:700}
.g{background:#dcfce7;color:#15803d} .r{background:#fee2e2;color:#b91c1c} .y{background:#fef3c7;color:#b45309} .b{background:#dbeafe;color:#1d4ed8}
.btns{display:flex;flex-wrap:wrap;gap:8px;margin-top:4px}
button{padding:8px 16px;border:none;border-radius:7px;cursor:pointer;font-size:13px;font-weight:600;transition:.15s}
.btn-b{background:#3b82f6;color:#fff}.btn-b:hover{background:#2563eb}
.btn-s{background:#6b7280;color:#fff}.btn-s:hover{background:#4b5563}
.btn-g{background:#10b981;color:#fff}.btn-g:hover{background:#059669}
.btn-r{background:#ef4444;color:#fff}.btn-r:hover{background:#dc2626}
.field{margin-bottom:12px}
.field label{display:block;font-size:12px;font-weight:600;color:#374151;margin-bottom:4px}
.field input{width:100%;padding:7px 10px;border:1px solid #d1d5db;border-radius:6px;font-size:13px;color:#111827}
.field input:focus{outline:none;border-color:#3b82f6;box-shadow:0 0 0 3px rgba(59,130,246,.15)}
.note{font-size:11px;color:#6b7280;margin-top:3px}
.log{font-family:'Courier New',monospace;font-size:11px;line-height:1.5;background:#18181b;color:#d4d4d4;padding:14px;border-radius:8px;max-height:340px;overflow-y:auto;white-space:pre-wrap;word-break:break-all}
.overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:50;padding:20px;overflow-y:auto}
.modal{background:#fff;border-radius:10px;padding:22px;max-width:660px;margin:40px auto}
.modal h2{border:none}
.code-block{font-family:'Courier New',monospace;font-size:12px;background:#f0f9ff;border:1px solid #bae6fd;padding:14px;border-radius:8px;white-space:pre;overflow-x:auto;user-select:all;cursor:text;margin:12px 0}
#toast{position:fixed;bottom:20px;right:20px;padding:10px 18px;border-radius:8px;font-size:13px;font-weight:600;color:#fff;display:none;z-index:200;pointer-events:none}
</style>
</head>
<body>
<h1><span>🔒</span> PIA WireGuard</h1>

<div class="card" id="status-card"><em>Loading status…</em></div>

<div class="card">
<h2>Actions</h2>
<div class="btns">
<button class="btn-b" onclick="doReconnect()">↺ Reconnect</button>
<button class="btn-s" onclick="doGenCfg()">📋 Generate Config for App</button>
</div>
</div>

<div class="card">
<h2>Settings &nbsp;<button class="btn-g" style="font-size:12px;padding:6px 12px;float:right" onclick="doSave()">Save</button></h2>
<div id="cfg-form"><em>Loading…</em></div>
<p class="note" style="margin-top:4px">Settings are saved to <code>/data/pia-wg/.env</code>. Restart the container to apply.</p>
</div>

<div class="card">
<h2>Logs &nbsp;<button class="btn-s" style="font-size:12px;padding:6px 12px;float:right" onclick="loadLogs()">Refresh</button></h2>
<div id="log-out" class="log">Loading…</div>
</div>

<!-- Generate-config modal -->
<div class="overlay" id="gcfg-modal">
<div class="modal">
<h2>📋 WireGuard Config — paste into Firewalla app</h2>
<div id="gcfg-text" class="code-block"></div>
<ol style="font-size:13px;line-height:1.8;color:#374151;margin:0 0 14px 18px">
<li>Copy the config above (click → Ctrl+A, Ctrl+C)</li>
<li>Firewalla app → <strong>VPN Client → Add VPN → WireGuard</strong> → paste → Save</li>
<li>Find profile ID: <code style="background:#f3f4f6;padding:1px 5px;border-radius:4px">ls -t ~/.firewalla/run/wg_profile/*.conf | head -1</code></li>
<li>Close this modal → paste the profile ID into the <strong>Firewalla Profile ID</strong> field in Settings → <strong>Save</strong> → restart the container</li>
</ol>
<div class="btns">
<button class="btn-b" onclick="copyGcfg()">Copy Config</button>
<button class="btn-s" onclick="closeModal('gcfg-modal')">Close</button>
</div>
</div>
</div>

<div id="toast"></div>

<script>
function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')}
function fmt(s){
  if(s==null||s===undefined)return'—';
  s=Number(s);
  if(s<60)return s+'s';
  if(s<3600)return Math.floor(s/60)+'m '+s%60+'s';
  return Math.floor(s/3600)+'h '+Math.floor((s%3600)/60)+'m';
}
function toast(msg,ok){
  var t=document.getElementById('toast');
  t.textContent=msg;t.style.background=ok?'#059669':'#dc2626';
  t.style.display='block';clearTimeout(t._tid);
  t._tid=setTimeout(()=>t.style.display='none',3000);
}

function loadStatus(){
  fetch('/api/status').then(r=>r.json()).then(d=>{
    var hs=d.handshake_age,hs_ok=hs!=null&&hs<120;
    var ttl_left=d.token_valid?d.token_ttl-d.token_age:0;
    var key_next=d.key_age!=null?Math.max(0,d.key_interval-d.key_age):null;
    var html=`<h2>Status</h2><div class="row">
<div class="col"><div class="lbl">Interface</div>
  <div class="val">${esc(d.interface)}</div>
  <span class="badge ${d.up?'g':'r'}" style="margin-top:4px">${d.up?'UP':'DOWN'}</span></div>
<div class="col"><div class="lbl">Last Handshake</div>
  <div class="val"><span class="badge ${hs==null?'r':hs_ok?'g':'y'}">${hs==null?'Never':fmt(hs)+' ago'}</span></div></div>
<div class="col"><div class="lbl">PIA Token</div>
  <div class="val"><span class="badge ${d.token_valid?'g':'r'}">${d.token_valid?'Valid · '+fmt(ttl_left)+' left':'Expired'}</span></div></div>
<div class="col"><div class="lbl">Key Refresh</div>
  <div class="val"><span class="badge ${d.key_fresh?'g':'y'}">${d.key_age==null?'Unknown':fmt(d.key_age)+' ago'}</span></div>
  ${key_next!==null?'<div class="note">next in ~'+fmt(key_next)+'</div>':''}</div>`;
    if(d.server&&d.server.ip){
      html+=`<div class="col"><div class="lbl">Server</div>
<div class="val" style="font-size:.82rem">${esc(d.server.cn||d.server.ip)}</div>
<div class="note">${esc(d.server.ip)} · peer ${esc(d.server.peer_ip||'—')}</div></div>`;
    }
    html+=`<div class="col"><div class="lbl">Mode</div><div class="val" style="font-size:.82rem">${esc(d.mode)}</div></div>`;
    html+='</div>';
    document.getElementById('status-card').innerHTML=html;
  }).catch(()=>{});
}

function loadConfig(){
  fetch('/api/config').then(r=>r.json()).then(fields=>{
    var h='<div class="row" style="flex-wrap:wrap">';
    fields.forEach(f=>{
      var v=esc(f.value||'');
      h+=`<div class="col field" style="flex:1;min-width:260px">
<label>${esc(f.label)}</label>
<input type="${f.sensitive?'password':'text'}" id="f_${esc(f.key)}" value="${v}"${f.sensitive?' autocomplete="new-password"':''}>
</div>`;
    });
    h+='</div>';
    document.getElementById('cfg-form').innerHTML=h;
  });
}

function loadLogs(){
  fetch('/api/logs').then(r=>r.text()).then(t=>{
    var el=document.getElementById('log-out');
    el.textContent=t;el.scrollTop=el.scrollHeight;
  });
}

function doReconnect(){
  if(!confirm('Force a fresh key registration and reconnect?\n\nThis re-registers your WireGuard key with PIA immediately.'))return;
  fetch('/api/reconnect',{method:'POST'}).then(r=>r.json()).then(d=>{
    toast(d.ok?'Reconnect triggered — check logs in ~10s':'Error: '+d.error,d.ok);
    if(d.ok)setTimeout(loadLogs,8000);
  }).catch(e=>toast('Request failed: '+e,false));
}

function doGenCfg(){
  toast('Registering key with PIA…',true);
  fetch('/api/generate-config',{method:'POST'}).then(r=>r.json()).then(d=>{
    if(d.ok){
      document.getElementById('gcfg-text').textContent=d.config;
      document.getElementById('gcfg-modal').style.display='block';
    } else {
      toast('Error: '+d.error,false);
    }
  }).catch(e=>toast('Request failed: '+e,false));
}

function copyGcfg(){
  var txt=document.getElementById('gcfg-text').textContent;
  if(navigator.clipboard){navigator.clipboard.writeText(txt).then(()=>toast('Copied!',true));}
  else{var ta=document.createElement('textarea');ta.value=txt;document.body.appendChild(ta);ta.select();document.execCommand('copy');document.body.removeChild(ta);toast('Copied!',true);}
}

function closeModal(id){document.getElementById(id).style.display='none';}

function doSave(){
  var data={};
  document.querySelectorAll('#cfg-form input').forEach(el=>{ data[el.id.replace('f_','')]=el.value; });
  fetch('/api/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)})
    .then(r=>r.json()).then(d=>toast(d.ok?'Saved to /data/pia-wg/.env — restart container to apply':'Error: '+d.error,d.ok))
    .catch(e=>toast('Request failed: '+e,false));
}

loadStatus();loadConfig();loadLogs();
setInterval(loadStatus,10000);
setInterval(loadLogs,20000);
</script>
</body>
</html>"""


# ─── HTTP handler ─────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress default access log; Docker logs are noisy enough

    def _send_json(self, data, code=200):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_text(self, text, ctype='text/plain; charset=utf-8'):
        body = text.encode()
        self.send_response(200)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get('Content-Length', 0))
        return self.rfile.read(n) if n else b''

    def do_GET(self):
        p = self.path.split('?')[0]
        if p in ('/', '/index.html'):
            self._send_text(PAGE, 'text/html; charset=utf-8')
        elif p == '/api/status':
            self._send_json(get_status())
        elif p == '/api/config':
            cfg = load_cfg()
            self._send_json([
                {'key': k, 'label': l, 'sensitive': s, 'value': cfg.get(k, '')}
                for k, l, s in CONFIG_FIELDS
            ])
        elif p == '/api/logs':
            self._send_text(tail_log())
        else:
            self.send_response(404); self.end_headers()

    def do_POST(self):
        p = self.path.split('?')[0]

        if p == '/api/reconnect':
            try:
                log_f = open(_log_path(), 'a')
                subprocess.Popen([SCRIPT, 'reconnect'],
                                 stdout=log_f, stderr=subprocess.STDOUT)
                self._send_json({'ok': True})
            except Exception as e:
                self._send_json({'ok': False, 'error': str(e)})

        elif p == '/api/generate-config':
            try:
                out, ok = _run(SCRIPT, 'generate-config', '--new-token', timeout=90)
                # Extract just the [Interface]...[Peer]... block
                lines, in_block = [], False
                for line in out.split('\n'):
                    if line.strip().startswith('[Interface]'):
                        in_block = True
                    if in_block:
                        if line.startswith('═') and lines:
                            break
                        lines.append(line)
                config = '\n'.join(lines).strip()
                self._send_json({'ok': bool(config), 'config': config or out,
                                 'error': '' if config else 'Could not parse config from output'})
            except Exception as e:
                self._send_json({'ok': False, 'error': str(e)})

        elif p == '/api/config':
            try:
                updates = json.loads(self._body())
                save_cfg(updates)
                self._send_json({'ok': True})
            except Exception as e:
                self._send_json({'ok': False, 'error': str(e)})

        else:
            self.send_response(404); self.end_headers()


# ─── entry point ─────────────────────────────────────────────────────────────

def run(port=8080):
    httpd = HTTPServer(('0.0.0.0', port), Handler)
    print(f'[web-ui] http://0.0.0.0:{port}', flush=True)
    httpd.serve_forever()


if __name__ == '__main__':
    port = int(os.environ.get('WEB_PORT', '8080'))
    if port == 0:
        sys.exit(0)
    run(port)
