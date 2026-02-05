import http.server
import json
import socketserver
import os
from datetime import datetime

PORT = 12345
LOG_FILE = "logs.json"

# 初始化日志文件
if not os.path.exists(LOG_FILE):
    with open(LOG_FILE, 'w') as f:
        json.dump([], f)

class LogRequestHandler(http.server.BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            
            html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>SensePath Remote Debug Info</title>
                <style>
                    body { font-family: -apple-system, sans-serif; background: #1a1a1a; color: #eee; margin: 20px; }
                    .card { background: #2a2a2a; border-radius: 12px; padding: 20px; margin-bottom: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.3); }
                    .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #444; padding-bottom: 10px; margin-bottom: 15px; }
                    .status { font-weight: bold; padding: 4px 12px; border-radius: 20px; font-size: 0.9em; }
                    .status-normal { background: #28a745; color: white; }
                    .status-warning { background: #ffc107; color: black; }
                    .status-stop { background: #dc3545; color: white; }
                    .metrics { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; }
                    .metric-box { background: #333; padding: 10px; border-radius: 8px; text-align: center; }
                    .metric-label { font-size: 0.8em; color: #888; display: block; }
                    .metric-value { font-size: 1.2em; font-weight: bold; color: #007aff; }
                    .log-area { font-family: monospace; background: #000; padding: 15px; border-radius: 8px; height: 300px; overflow-y: auto; font-size: 0.85em; }
                    .log-entry { margin-bottom: 4px; border-bottom: 1px solid #1a1a1a; padding-bottom: 2px; }
                    .timestamp { color: #666; margin-right: 8px; }
                    .error { color: #ff3b30; }
                </style>
                <script>
                    async function fetchLogs() {
                        try {
                            const res = await fetch('/data');
                            const data = await res.json();
                            if (data.length > 0) {
                                const latest = data[data.length - 1];
                                document.getElementById('state').innerText = latest.state;
                                document.getElementById('state').className = 'status status-' + latest.state.toLowerCase();
                                document.getElementById('left').innerText = latest.left.toFixed(2) + 'm';
                                document.getElementById('center').innerText = latest.center.toFixed(2) + 'm';
                                document.getElementById('right').innerText = latest.right.toFixed(2) + 'm';
                                document.getElementById('invalid').innerText = (latest.invalidRatio * 100).toFixed(0) + '%';
                                document.getElementById('stability').innerText = latest.stability.toFixed(2) + 'm';
                                document.getElementById('fps').innerText = latest.fps.toFixed(1);
                                
                                const logList = document.getElementById('log-list');
                                logList.innerHTML = data.slice(-50).reverse().map(log => `
                                    <div class="log-entry">
                                        <span class="timestamp">${log.timestamp}</span>
                                        [${log.state}] L:${log.left.toFixed(2)} C:${log.center.toFixed(2)} R:${log.right.toFixed(2)}
                                    </div>
                                `).join('');
                            }
                        } catch (e) {
                            console.error("Fetch failed", e);
                        }
                    }
                    setInterval(fetchLogs, 500);
                </script>
            </head>
            <body>
                <h1>SensePath Remote Monitor</h1>
                <div class="card">
                    <div class="header">
                        <h2>Real-time State</h2>
                        <span id="state" class="status">DETACHED</span>
                    </div>
                    <div class="metrics">
                        <div class="metric-box"><span class="metric-label">Left</span><span class="metric-value" id="left">-</span></div>
                        <div class="metric-box"><span class="metric-label">Center</span><span class="metric-value" id="center">-</span></div>
                        <div class="metric-box"><span class="metric-label">Right</span><span class="metric-value" id="right">-</span></div>
                        <div class="metric-box"><span class="metric-label">Holes</span><span class="metric-value" id="invalid">-</span></div>
                        <div class="metric-box"><span class="metric-label">Jitter</span><span class="metric-value" id="stability">-</span></div>
                        <div class="metric-box"><span class="metric-label">FPS</span><span class="metric-value" id="fps">-</span></div>
                    </div>
                </div>
                <h3>Activity Logs</h3>
                <div class="log-area" id="log-list">
                    Waiting for data...
                </div>
            </body>
            </html>
            """
            self.wfile.write(html.encode('utf-8'))
            
        elif self.path == '/data':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            with open(LOG_FILE, 'r') as f:
                self.wfile.write(f.read().encode('utf-8'))
                
    def do_POST(self):
        if self.path == '/log':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            
            try:
                new_log = json.loads(post_data.decode('utf-8'))
                new_log['timestamp'] = datetime.now().strftime("%H:%M:%S.%f")[:-3]
                
                with open(LOG_FILE, 'r+') as f:
                    logs = json.load(f)
                    logs.append(new_log)
                    if len(logs) > 500: logs = logs[-500:] # 保持最近500条
                    f.seek(0)
                    json.dump(logs, f)
                    f.truncate()
                
                self.send_response(200)
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"status": "ok"}')
            except Exception as e:
                print(f"Error processing log: {e}")
                self.send_response(400)
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(str(e).encode('utf-8'))

with socketserver.TCPServer(("", PORT), LogRequestHandler) as httpd:
    print(f"Server started at http://localhost:{PORT}")
    print("CRITICAL: Use HTTP only. HTTPS is NOT supported.")
    # 获取本地 IP
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
        print(f"Remote End Point: http://{ip}:{PORT}/log")
    finally:
        s.close()
    httpd.serve_forever()
