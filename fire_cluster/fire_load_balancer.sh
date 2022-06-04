#!/bin/bash

#WORKER_AMI_ID=$1

########## DELETE!!!
WORKER_AMI_ID="ami-0cfdacc89a6f7097f"

source "fire_cluster/const.txt"
KEY_PEM="$KEY_NAME.pem"

echo "Create an IAM Role"
aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$POLICY_PATH"

echo "Attach a Policy with the Role"
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

echo "Verify the policy assignment"
aws iam create-instance-profile --instance-profile-name "$ROLE_NAME"

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

aws iam add-role-to-instance-profile --role-name "$ROLE_NAME" --instance-profile-name "$ROLE_NAME"

echo "Associate IAM role to instance"
aws ec2 associate-iam-instance-profile --instance-id $INSTANCE_ID --iam-instance-profile Name="$ROLE_NAME"

PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids "$INSTANCE_ID" |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "New end point - $INSTANCE_ID @ $PUBLIC_IP"

echo "Deploy app"
ssh  -i "$KEY_PEM" -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@"$PUBLIC_IP" <<EOF

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

    echo WORKER_AMI_ID = "'$WORKER_AMI_ID'" >> "$LB_CONST"
    echo LB_PUBLIC_IP = "'$PUBLIC_IP'" >> "$LB_CONST"

    echo "Install requirements"
    pip3 install -r "$LB_REQ"

    export FLASK_APP="$LB_APP"
    echo "Run app"
    nohup flask run --host=0.0.0.0 &>/dev/null & exit

EOF