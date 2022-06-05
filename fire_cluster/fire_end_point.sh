#!/bin/bash

LB_PUBLIC_IP=$1
source "fire_cluster/const.txt"
KEY_PEM="$KEY_NAME.pem"

echo "Creating Ubuntu 22.04 instance..."
RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_22_04_AMI        \
    --instance-type t2.micro            \
    --key-name $KEY_NAME                \
    --credit-specification CpuCredits=unlimited \
    --security-groups $SEC_GRP)

INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')

echo "Waiting for instance creation..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids "$INSTANCE_ID" |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "New end point - $INSTANCE_ID @ $PUBLIC_IP"

echo "Deploy app"
ssh  -i "$KEY_PEM" -o "IdentitiesOnly=yes" -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@"$PUBLIC_IP" <<EOF

    echo "update apt get"
    sudo apt-get update -y

    echo "upgrade apt get"
    sudo apt-get upgrade -y

    echo "update apt get x2"
    sudo apt-get update -y

    echo "install pip"
    sudo apt-get install python3-pip -y

    echo "Clone repo"
    git clone "$GITHUB_URL.git"
    cd $PROJ_NAME

    echo "Install requirements"
    pip3 install -r "$END_POINT_REQ"

    echo LB_PUBLIC_IP = "'$LB_PUBLIC_IP'" >> "$END_POINT_CONST"

    export FLASK_APP="end_point/app.py"
    nohup flask run --host=0.0.0.0 &>/dev/null & exit

EOF

echo "$PUBLIC_IP"