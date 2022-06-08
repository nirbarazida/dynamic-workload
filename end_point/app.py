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
        res = requests.put(url=f"http://{LB_PUBLIC_IP}/add_job_to_q?iterations={iterations}",
                           data=data_file)
        # TODO: is res.status valid?
        return Response(status=res.status)


@app.route('/pullCompleted', methods=['POST'])
def pullCompleted():
    if request.method == "POST":
        # TODO: implement top
        res = requests.post(f"http://{LB_PUBLIC_IP}/pullCompleted")
        last_job = res.get_json()
        return Response(mimetype='application/json',
                        response=json.dumps({"job_id": last_job["job_id"],
                                             "result": last_job["result"]
                                             }),
                        status=200)
