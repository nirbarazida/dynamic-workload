#!/bin/bash

WORKER_AMI_ID=$1
source "fire_cluster/const.txt"
KEY_PEM="$KEY_NAME.pem"

echo "Create an IAM Role"
aws iam create-role --role-name EC2FullAccess --assume-role-policy-document file://trust-policy.json

echo "Attach a Policy with the Role"
aws iam attach-role-policy --role-name EC2FullAccess --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

echo "Verify the policy assignment"
aws iam list-attached-role-policies --role-name sqsAccessRole

aws iam add-role-to-instance-profile --role-name EC2FullAccess --instance-profile-name EC2FullAccessInstanceProfile

echo "Creating Ubuntu 22.04 instance..."
RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_22_04_AMI        \
    --instance-type t2.micro            \
    --key-name $KEY_NAME                \
    --credit-specification CpuCredits=unlimited \
    --tag-specifications "ResourceType=instance,Tags=[{Key=load_balancer_ip,Value=$MY_IP}]" \
    --security-groups $SEC_GRP \
    --iam-instance-profile Name="EC2FullAccess")

INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')
echo "$INSTANCE_ID" >> workers_id_list.txt

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
    git clone "$GITHUB_URL.pem"
    cd $PROJ_NAME

    echo WORKER_AMI_ID = $WORKER_AMI_ID >> "$LB_CONST"
    echo LB_PUBLIC_IP = $PUBLIC_IP >> "$LB_CONST"

    echo "Install requirements"
    pip3 install -r "$LB_REQ"

    echo "Init load balancer"
    chmod 400 "$LB_INIT_PATH"
    ./"$LB_INIT_PATH"

    export FLASK_APP="$LB_APP"
    echo "Run app"
    python3 -m flask run --host=0.0.0.0

EOF