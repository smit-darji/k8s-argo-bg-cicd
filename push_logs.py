from flask import Flask, request, send_from_directory
import requests, time, json, os

app = Flask(__name__)

# Loki endpoint (use your K8s service DNS or override with env variable)
LOKI_URL = os.environ.get(
    "LOKI_URL",
    "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
)
JOB_LABEL = "web-app-project"

def push_to_loki(level: str, message: str):
    timestamp = str(int(time.time() * 1e9))  # nanoseconds
    payload = {
        "streams": [{
            "stream": {"job": JOB_LABEL, "level": level},
            "values": [[timestamp, message]]
        }]
    }
    try:
        res = requests.post(
            LOKI_URL,
            data=json.dumps(payload),
            headers={"Content-Type": "application/json"}
        )
        if res.status_code == 204:
            return True, f"✅ {level} log pushed to Loki!"
        else:
            return False, f"❌ Failed ({res.status_code}): {res.text}"
    except Exception as e:
        return False, f"⚠️ Error: {str(e)}"

# Serve index.html at root
@app.route("/")
def index():
    return send_from_directory(".", "index.html")

# Unified endpoint for success/error logs
@app.route("/push_log", methods=["POST"])
def push_log():
    data = request.get_json() or {}
    level = data.get("level", "INFO").upper()
    message = data.get("message", f"Manual {level} log from UI")
    success, response = push_to_loki(level, message)
    return response

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
