#!/bin/bash

WORKER_AMI_ID=$1
LB_PUBLIC_IP=$2
source "fire_cluster/const.txt"
KEY_PEM="$KEY_NAME_LB.pem"

echo "Creating Ubuntu 22.04 instance..."
RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id "$WORKER_AMI_ID"        \
    --instance-type t2.micro            \
    --key-name "$KEY_NAME_LB"                \
    --credit-specification CpuCredits=unlimited \
    --tag-specifications "ResourceType=instance,Tags=[{Key=load_balancer_ip,Value=$MY_IP}]" \
    --security-groups "$SEC_GRP_LB")

INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')
echo "$INSTANCE_ID" >> workers_id_list.txt

echo "Waiting for instance creation..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids "$INSTANCE_ID" |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "New end point - $INSTANCE_ID @ $PUBLIC_IP"

# TODO: fire instance and not connect to it with SSH - using tag
echo "Deploy app"
ssh  -i "$KEY_PEM" -o "IdentitiesOnly=yes" -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@"$PUBLIC_IP" <<EOF

    echo LB_PUBLIC_IP = "$LB_PUBLIC_IP" >> "$WORKER_CONST"

    export FLASK_APP="$WORKER_APP"
    echo "Run app"
    python3 -m flask run --host=0.0.0.0

EOF