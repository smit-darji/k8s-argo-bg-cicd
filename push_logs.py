from flask import Flask, request, send_from_directory, jsonify
import requests, time, json, os, threading
from functools import wraps

app = Flask(__name__)

# Loki config
LOKI_URL = os.environ.get(
    "LOKI_URL",
    "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
)
JOB_LABEL = "web-app-project"


def push_to_loki(level: str, message: str, endpoint: str = None, extra: dict = None):
    """Push structured log to Loki."""
    timestamp = str(int(time.time() * 1e9))
    labels = {"job": JOB_LABEL, "level": level.upper(), "endpoint": endpoint or "unknown"}

    log_entry = {
        "time": time.strftime("%Y-%m-%d %H:%M:%S"),
        "level": level.upper(),
        "endpoint": endpoint,
        "message": message,
    }

    # Merge extra info (like duration, status, method, etc.)
    if extra:
        log_entry.update(extra)

    payload = {
        "streams": [{
            "stream": labels,
            "values": [[timestamp, json.dumps(log_entry)]]
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
    """Decorator to log request + response time for APIs."""
    @wraps(func)
    def wrapper(*args, **kwargs):
        start_time = time.time()
        method = request.method
        endpoint = request.path
        try:
            response = func(*args, **kwargs)
            status_code = response.status_code if hasattr(response, "status_code") else 200
        except Exception as e:
            status_code = 500
            raise e
        finally:
            duration_ms = (time.time() - start_time) * 1000
            push_to_loki(
                "INFO",
                f"{method} {endpoint} -> {status_code} in {duration_ms:.2f}ms",
                endpoint=endpoint,
                extra={
                    "method": method,
                    "status_code": status_code,
                    "duration_ms": round(duration_ms, 2)
                }
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


# --- 🔁 Automatic demo logger ---
def auto_demo_logger(interval=30):
    while True:
        ts = time.strftime("%Y-%m-%d %H:%M:%S")
        msg = f"Auto demo log at {ts}"
        push_to_loki("INFO", msg, endpoint="/auto_log")
        time.sleep(interval)


def start_background_logger():
    thread = threading.Thread(target=auto_demo_logger, args=(30,), daemon=True)
    thread.start()


if __name__ == "__main__":
    start_background_logger()
    app.run(host="0.0.0.0", port=80)
