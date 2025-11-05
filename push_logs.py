from flask import Flask, request
import requests, time, json, os

app = Flask(__name__)

# Loki endpoint (use your K8s service DNS)
LOKI_URL = os.environ.get("LOKI_URL", "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push")
JOB_LABEL = "web-app-project"

def push_to_loki(level: str, message: str):
    """Helper function to push a log message to Loki"""
    timestamp = str(int(time.time() * 1e9))
    payload = {
        "streams": [{
            "stream": {"job": JOB_LABEL, "level": level},
            "values": [[timestamp, message]]
        }]
    }
    try:
        res = requests.post(LOKI_URL, data=json.dumps(payload), headers={"Content-Type": "application/json"})
        if res.status_code == 204:
            return True, f"✅ {level} log pushed to Loki!"
        else:
            return False, f"❌ Failed ({res.status_code}): {res.text}"
    except Exception as e:
        return False, f"⚠️ Error: {str(e)}"

@app.route("/web_app_success", methods=["POST"])
def web_app_success():
    data = request.get_json() or {}
    message = data.get("message", "Manual success log from UI")
    success, response = push_to_loki("INFO", message)
    return response

@app.route("/web_app_error", methods=["POST"])
def web_app_error():
    data = request.get_json() or {}
    message = data.get("message", "Manual error log from UI")
    success, response = push_to_loki("ERROR", message)
    return response

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
