from flask import Response, Flask, render_template, request, redirect
import requests
from const import LB_PUBLIC_IP
import json

app = Flask(__name__)

@app.route('/enqueue', methods=['PUT'])
def enqueue():
    params = {"iterations": str(request.args.get("iterations"))}
    requests.put(f"{LB_PUBLIC_IP}/add_job_to_q", params=params)


@app.route('/pullCompleted', methods=['POST'])
def pullCompleted():
    r = requests.post(f"{LB_PUBLIC_IP}/pullCompleted")
    return Response(mimetype='application/json',
                    response=json.dumps({"job_id": r.content["job_id"],
                                         "result": r.content["result"]
                                         }),
                    status=200)