import socket, time
from flask import Flask, request, jsonify

app = Flask(__name__)
HOST = socket.gethostname()   # on a scale set this is the VM instance name

@app.route("/")
def home():
    return f"<h1>EcoBuy Store</h1><p>Served by instance: <b>{HOST}</b></p>"

@app.route("/health")
def health():
    return jsonify(status="ok"), 200

@app.route("/load")
def load():
    """Burns CPU for ~n ms so autoscaling can be triggered on demand."""
    ms = min(int(request.args.get("n", 200)), 2000)
    end = time.time() + ms / 1000
    while time.time() < end:
        sum(i * i for i in range(1000))
    return jsonify(instance=HOST, burned_ms=ms)
