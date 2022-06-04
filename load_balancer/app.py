from flask import Response, Flask, request
from datetime import datetime
from const import ITERATIONS, MAX_Q_TIME_SEC, PERIODIC_ITERATION, INSTANCE_TYPE, \
    PATH_TO_CONST_TXT, WORKER_AMI_ID, LB_PUBLIC_IP
import json
import uuid
import time
import threading
import boto3
import os
import subprocess

app = Flask(__name__)
job_q = []
result_list = []
next_call = time.time()

def read_const_from_txt(path):
    global const
    with open(path, "r") as f:
        lines = f.readlines()
        items = [line.replace('"', "").replace("\n", "") for line in lines if "=" in line]
        const = dict([el.split("=") for el in items])


def check_time_first_in_line():
    dif = datetime.utcnow() - job_q[0]["entry_time_utc"]
    return dif.seconds


def fire_worker():
    client = boto3.client('ec2', region_name='us-west-2')
    response = client.run_instances(ImageId=WORKER_AMI_ID,
                                    InstanceType=INSTANCE_TYPE,
                                    MaxCount=1,
                                    MinCount=1,
                                    UserData=f"""
                                               #!/bin/bash
                                               cd {const["PROJ_NAME"]}
                                               echo LB_PUBLIC_IP = f{LB_PUBLIC_IP} >> f{const["WORKER_CONST"]}
                                               python3 {const["WORKER_APP"]}
                                               """,
                                    SecurityGroupIds=[const["SEC_GRP"]])
    return response


@app.before_first_request
def scale_up_periodic():
    read_const_from_txt(PATH_TO_CONST_TXT)
    global next_call

    if job_q and check_time_first_in_line() > MAX_Q_TIME_SEC:
        fire_worker()
    next_call = next_call + PERIODIC_ITERATION
    threading.Timer(next_call - time.time(), scale_up_periodic).start()


@app.route('/add_job_to_q', methods=['POST'])
def add_job_to_q():
    job_id = uuid.uuid4().int
    entry_time_utc = datetime.utcnow()
    job_q.append({"job_id": job_id,
                  # TODO: with the body containing the actual data???
                  "content": str(request.args.get(ITERATIONS)),
                  "entry_time_utc": entry_time_utc})
    # TODO: with the body containing the actual data???
    return Response(mimetype='application/json',
                    response=json.dumps({"job_id": job_id}),
                    status=200)


@app.route('/get_job', methods=['PUT'])
def get_job():
    # TODO: How do I know it doesn't send same job to 2 machines?
    # TODO: How do I know it doesn't run forever? does hangout 10 sec does it?
    if job_q:
        job = job_q[0]
        del job_q[0]

        return Response(mimetype='application/json',
                        # TODO: with the body containing the actual data???
                        response=json.dumps({"job_id": job["job_id"],
                                             "content": job["content"]
                                             }),
                        status=200)
    else:
        return Response(mimetype='application/json',
                        response=json.dumps({"job_id": None,
                                             "content": None
                                             }),
                        status=200)


@app.route('/return_result', methods=['PUT'])
def return_result():
    result_list.append({"result": str(request.args.get(ITERATIONS)),
                        "job_id": str(request.args.get(ITERATIONS))})


@app.route('/pullCompleted', methods=['POST'])
def pullCompleted():
    return Response(mimetype='application/json',
                    response=json.dumps({"job_id": result_list[-1]["job_id"],
                                         "result": result_list[-1]["result"]
                                         }),
                    status=200)
