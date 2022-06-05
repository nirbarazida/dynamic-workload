import requests
import boto3
from ec2_metadata import ec2_metadata
import os
from const import LB_PUBLIC_IP, TIME_OUT, PORT

def work(buffer, iterations):
    # TODO: do something
    pass

def main():
    while True:
        buffer, iterations = None, None # TODO: change to func var
        response = requests.get(f'http://{LB_PUBLIC_IP}:{PORT}/get_job', timeout=TIME_OUT)
        if response:
            buffer = response.json()
            work(response, iterations)
        else:
            os.system('sudo shutdown -h now')

if __name__ == '__main__':
    main()