from flask import Response, Flask, render_template, request, redirect
import requests
from const import LB_PUBLIC_IP
import json

app = Flask(__name__)


@app.route('/enqueue', methods=['PUT'])
def enqueue():
    if request.method == "PUT":
        iterations = int(request.args.get("iterations"))
        data_file = request.get_data()
        res = requests.put(url=f"http://{LB_PUBLIC_IP}:5000/add_job_to_q?iterations={iterations}",
                           data=data_file)
        return Response(status=res.status_code)


@app.route('/pullCompleted', methods=['POST'])
def pullCompleted():
    if request.method == "POST":
        top = int(request.args.get('top'))
        res = requests.post(f"http://{LB_PUBLIC_IP}:5000/pullCompleted?top={top}")
        return Response(mimetype='application/json',
                        response=json.dumps(res.json()),
                        status=200)
