import requests
import time
import boto3
from ec2_metadata import ec2_metadata
import os
from const import LB_PUBLIC_IP, TIME_OUT, PORT, HARAKIRI
from datetime import datetime


def work(buffer, iterations):
    import hashlib
    output = hashlib.sha512(buffer.encode('utf-8')).digest()
    for i in range(iterations - 1):
        output = hashlib.sha512(output).digest()
    return output


def main():
    start_time = datetime.utcnow()
    headers = {
        "Content-Type": "application/json",
        'Accept': 'application/json'
    }
    while True:
        dif = datetime.utcnow() - start_time
        request = requests.get(f'http://{LB_PUBLIC_IP}:{PORT}/get_job')
        job = request.json()
        if job:
            res = work(job["file"], job["iterations"])
            requests.put(f"http://{LB_PUBLIC_IP}:{PORT}/return_result", headers=headers, json={"job_id": job["job_id"],
                                                                                               "result": str(res)})
            start_time = datetime.utcnow()

        else:
            if dif.seconds > 10 and HARAKIRI:
                os.system('sudo shutdown -h now')

            time.sleep(1)


if __name__ == '__main__':
    main()
