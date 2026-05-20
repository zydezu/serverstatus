import threading
import urllib.request
import webbrowser
from http.server import HTTPServer, SimpleHTTPRequestHandler

BASE = "http://100.100.100.100:8080"
ROUTES = {
    "/cali": "/zydezu.github/cali/alex/metrics.json",
    "/basil": "/zydezu.github/basil/alex/metrics.json",
}


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        target = ROUTES.get(self.path)
        if target:
            try:
                data = urllib.request.urlopen(BASE + target, timeout=5).read()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(data)
            except Exception as e:
                self.send_response(502)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(f'{{"error": "{e}"}}'.encode())
        else:
            super().do_GET()


if __name__ == "__main__":
    server = HTTPServer(("localhost", 9090), Handler)
    threading.Timer(
        0.5, lambda: webbrowser.open("http://localhost:9090/index.html")
    ).start()
    server.serve_forever()
