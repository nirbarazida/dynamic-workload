import requests
import boto3
from ec2_metadata import ec2_metadata
import os
from const import LB_PUBLIC_IP, TIME_OUT, PORT


def work(buffer, iterations):
    import hashlib
    output = hashlib.sha512(buffer).digest()
    for i in range(iterations - 1):
        output = hashlib.sha512(output).digest()
    return output


def main():
    while True:
        request = requests.get(f'http://{LB_PUBLIC_IP}:{PORT}/get_job', timeout=TIME_OUT)
        if request:
            job = request.get_json()
            res = work(job["file"], job["iterations"])
            requests.put(f"http://{LB_PUBLIC_IP}:{PORT}/add_job_to_q", json={"job_id": job["job_id"],
                                                                      "result": res})
        else:
            os.system('sudo shutdown -h now')


if __name__ == '__main__':
    main()
