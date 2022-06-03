import requests
import boto3
from ec2_metadata import ec2_metadata
#TODO: add const file
from const import LB_URL, TIME_OUT

def work(buffer, iterations):
    # do something
    pass


def shutdown():
    # TODO: when launching instance add role EC2FullAccess
    # TODO: pip install ec2-metadata


    instance_region, instance_id = ec2_metadata.region, ec2_metadata.instance_id

    ec2 = boto3.resource('ec2', region_name=instance_region)
    instance = ec2.Instance(instance_id)

    instance.terminate()


def main():
    while True:
        # TODO: Uncomment
        # buffer, iterations = None, None # TODO: change to func var
        # response = requests.get(LB_URL, timeout=TIME_OUT)
        # #TODO: change to if response is None
        # if response:
        #     work(response, iterations)
        # else:
        #     shutdown()
        pass

if __name__ == '__main__':
    main()