from flask import Flask, request, send_from_directory, jsonify
import requests, time, json, os
from functools import wraps

app = Flask(__name__)

LOKI_URL = os.environ.get(
    "LOKI_URL",
    "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
)
JOB_LABEL = "web-app-project"


def push_to_loki(level: str, message: str, endpoint: str = None):
    level = str(level).upper().strip()
    message = str(message).strip()
    timestamp = str(int(time.time() * 1e9))
    labels = {"job": JOB_LABEL, "level": level}
    if endpoint:
        labels["endpoint"] = endpoint

    payload = {
        "streams": [{
            "stream": labels,
            "values": [[timestamp, message]]
        }]
    }

    try:
        res = requests.post(
            LOKI_URL,
            data=json.dumps(payload),
            headers={"Content-Type": "application/json"},
            timeout=5
        )
        return res.status_code == 204
    except Exception as e:
        print(f"Error pushing to Loki: {str(e)}")
        return False


def log_api(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        start_time = time.time()
        response = func(*args, **kwargs)
        duration_ms = (time.time() - start_time) * 1000  # ms
        endpoint = request.path
        push_to_loki(
            level="INFO",
            message=f"{request.method} {endpoint} took {duration_ms:.2f}ms",
            endpoint=endpoint
        )
        return response
    return wrapper


@app.route("/")
@log_api
def index():
    return send_from_directory(".", "index.html")


@app.route("/push_log", methods=["POST"])
@log_api
def push_log():
    data = request.get_json(force=True) or {}
    level = data.get("level", "INFO")
    message = data.get("message", f"Manual {level} log from UI")
    push_to_loki(level, message, endpoint="/push_log")
    return jsonify({"success": True, "message": message})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
