#!/bin/bash

source "fire_cluster/const.txt"
KEY_PEM="$KEY_NAME.pem"

IMAGE_ID=$(aws ec2 describe-images --owners self --filters "Name=tag:$IMG_TAG_KEY_1,Values=[$IMG_TAG_VAL_1]" "Name=name, Values=[$AMI_NAME]" | jq --raw-output '.Images[] | .ImageId')

if [[ $IMAGE_ID ]]
then
  echo "$IMAGE_ID"
  exit
fi

printf "Creating Ubuntu 22.04 instance...\n"
RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id "$UBUNTU_22_04_AMI"        \
    --instance-type t2.micro            \
    --key-name "$KEY_NAME"                \
    --credit-specification CpuCredits=unlimited \
    --security-groups "$SEC_GRP")

INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')

printf "Waiting for instance creation...\n"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids "$INSTANCE_ID" |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

printf "New instance $INSTANCE_ID @ $PUBLIC_IP \n"

printf "Deploy app \n"
ssh  -i "$KEY_PEM" -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=1600" ubuntu@"$PUBLIC_IP" <<EOF

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

    printf "Install requirements\n"
    pip3 install -r "$WORKER_REQ"

    printf "Run app\n"
    nohup python3 "$WORKER_APP" &>/dev/null & exit

EOF

REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')

printf "Creating new image...\n"
IMAGE_ID=$(aws ec2 create-image --instance-id "$INSTANCE_ID" \
      --name $AMI_NAME \
      --tag-specifications ResourceType=image,Tags="[{Key=$IMG_TAG_KEY_1,Value=$IMG_TAG_VAL_1}]" \
      --description "An AMI for workers in hash cluster" \
      --region "$REGION" \
      --query ImageId --output text)

printf "Waiting for image creation...\n"
aws ec2 wait image-available \
    --image-ids $IMAGE_ID

aws ec2 terminate-instances --instance-ids $INSTANCE_ID

echo $IMAGE_ID