import urllib.request

from flask import Flask, Response, jsonify

BASE = "http://100.100.100.100:8080"
ROUTES = {
    "/cali": "/zydezu.github/cali/alex/metrics.json",
    "/basil": "/zydezu.github/basil/alex/metrics.json",
}

app = Flask(__name__)


@app.route("/<path:route>")
def proxy(route):
    target = ROUTES.get("/" + route)
    if target is None:
        return jsonify({"error": "not found"}), 404
    try:
        data = urllib.request.urlopen(BASE + target, timeout=5).read()
        return Response(
            data,
            status=200,
            mimetype="application/json",
            headers={"Access-Control-Allow-Origin": "*"},
        )
    except Exception as e:
        return Response(
            f'{{"error": "{e}"}}',
            status=502,
            mimetype="application/json",
            headers={"Access-Control-Allow-Origin": "*"},
        )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8888)
