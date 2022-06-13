from flask import Response, Flask, request
from datetime import datetime
from const import MAX_Q_TIME_SEC, PERIODIC_ITERATION, INSTANCE_TYPE, \
    PATH_TO_CONST_TXT, WORKER_AMI_ID, LB_PUBLIC_IP, USER_REGION
import json
import uuid
import time
import threading
import boto3

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


def fire_worker(app_path, harakiri=True, min_count=1, max_count=1):
    user_data = f"""#!/bin/bash
                   cd {const["PROJ_NAME"]}
                   git pull
                   echo LB_PUBLIC_IP = f{LB_PUBLIC_IP} >> {const["WORKER_CONST"]}
                   echo HARAKIRI = {harakiri} >> {const["WORKER_CONST"]}
                   python3 {app_path}
                """
    client = boto3.client('ec2', region_name=USER_REGION)
    response = client.run_instances(ImageId=WORKER_AMI_ID,
                                    InstanceType=INSTANCE_TYPE,
                                    MaxCount=max_count,
                                    MinCount=min_count,
                                    InstanceInitiatedShutdownBehavior='terminate',
                                    UserData=user_data,
                                    SecurityGroupIds=[const["SEC_GRP"]])
    return response


@app.before_first_request
def scale_up_periodic():
    read_const_from_txt(PATH_TO_CONST_TXT)
    global next_call

    if job_q and check_time_first_in_line() > MAX_Q_TIME_SEC:
        response = fire_worker(const["WORKER_APP"])
        resource = boto3.resource('ec2', region_name=USER_REGION)
        instance = resource.Instance(id=response['Instances'][0]['InstanceId'])
        instance.wait_until_running()
    next_call = next_call + PERIODIC_ITERATION
    threading.Timer(next_call - time.time(), scale_up_periodic).start()


@app.route('/add_job_to_q', methods=['PUT'])
def add_job_to_q():
    if request.method == "PUT":
        job_id = uuid.uuid4().int
        entry_time_utc = datetime.utcnow()
        job_q.append({"job_id": job_id,
                      "entry_time_utc": entry_time_utc,
                      "iterations": int(request.args.get("iterations")),
                      "file": request.get_data()
                      })
    return Response(status=200)


@app.route('/get_job', methods=['GET'])
def get_job():
    if request.method == "POST":
        if not job_q:
            Response(status=200)
        else:
            job = job_q[0]
            del job_q[0]

            return Response(mimetype='application/json',
                            response=json.dumps({"job_id": job["job_id"],
                                                 "entry_time_utc": job["entry_time_utc"],
                                                 "iterations": job["iterations"],
                                                 "file": job["file"],
                                                 }),
                            status=200)


@app.route('/return_result', methods=['PUT'])
def return_result():
    if request.method == "PUT":
        req = request.json()
        result_list.append({"job_id": req["job_id"],
                            "result": req["result"]
                            })


@app.route('/pullCompleted', methods=['POST'])
def pullCompleted():
    if request.method == "POST":
        top = int(request.args.get('top'))
        slice_index = min(top, len(result_list))
        return Response(mimetype='application/json',
                        response=json.dumps({"result": result_list[:slice_index]}),
                        status=200)


read_const_from_txt(PATH_TO_CONST_TXT)
fire_worker(const["WORKER_APP"], harakiri=False, min_count=1, max_count=1)
