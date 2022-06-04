#!/bin/bash

WORKER_AMI_ID=$1
source "fire_cluster/const.txt"
KEY_PEM="$KEY_NAME.pem"

printf "Create an IAM Role\n"
aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$POLICY_PATH"

printf "Attach a Policy with the Role\n"
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

printf "Verify the policy assignment\n"
aws iam create-instance-profile --instance-profile-name "$ROLE_NAME"

printf "Creating Ubuntu 22.04 instance...\n"
RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_22_04_AMI        \
    --instance-type t2.micro            \
    --key-name $KEY_NAME                \
    --credit-specification CpuCredits=unlimited \
    --security-groups $SEC_GRP)

INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')

printf "Waiting for instance creation...\n"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

aws iam add-role-to-instance-profile --role-name "$ROLE_NAME" --instance-profile-name "$ROLE_NAME"

printf "Associate IAM role to instance\n"
aws ec2 associate-iam-instance-profile --instance-id $INSTANCE_ID --iam-instance-profile Name="$ROLE_NAME"

PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids "$INSTANCE_ID" |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

printf "New end point - $INSTANCE_ID @ $PUBLIC_IP\n"

printf "Deploy app\n"

ssh -i "$KEY_PEM" -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@"$PUBLIC_IP" <<EOF

    printf "update apt get\n"
    sudo apt-get update -y

    printf "upgrade apt get\n"
    sudo apt-get upgrade -y

    printf "update apt get x2\n"
    sudo apt-get update -y

    printf "install pip\n"
    sudo apt-get install python3-pip -y

    printf "Clone repo\n"
    git clone "$GITHUB_URL.git"
    cd $PROJ_NAME

    echo WORKER_AMI_ID = "'$WORKER_AMI_ID'" >> "$LB_CONST"
    echo LB_PUBLIC_IP = "'$PUBLIC_IP'" >> "$LB_CONST"

    printf "Install requirements\n"
    pip3 install -r "$LB_REQ"


    export FLASK_APP=load_balancer/app.py
    nohup flask run --host=0.0.0.0 &>/dev/null & exit

EOF

echo "$PUBLIC_IP"