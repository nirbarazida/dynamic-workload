#!/bin/bash
source "fire_cluster/const.txt"
KEY_PEM="$KEY_NAME.pem"
USER_REGION=$(aws configure get region --output text)

function create_key_pair() {
    KEY_PEM="$KEY_NAME.pem"

    echo "create key pair $KEY_PEM to connect to instances and save locally"
    aws ec2 create-key-pair --key-name "$KEY_NAME" \
    | jq -r ".KeyMaterial" > "$KEY_PEM"

    # secure the key pair
    chmod 400 "$KEY_PEM"

}

function setup_security_group() {
  printf "setup firewall $SEC_GRP"
  aws ec2 create-security-group   \
  --group-name "$SEC_GRP"       \
  --description "Access my instances"

  # figure out my ip
  MY_IP=$(curl ipinfo.io/ip)
  printf "My IP: %s" "$MY_IP"

  printf "setup rule allowing SSH access to %s only" "$MY_IP"
  aws ec2 authorize-security-group-ingress        \
      --group-name "$SEC_GRP" --port 22 --protocol tcp \
      --cidr "$MY_IP"/32

  printf "setup rule allowing HTTP (port 5000) access to %s only" "$MY_IP"
  aws ec2 authorize-security-group-ingress        \
      --group-name "$SEC_GRP" --port 5000 --protocol tcp \
      --cidr "$MY_IP"/32

  echo "$MY_IP"
}

function run_instance() {
  AMI_ID=$1
  printf "Creating Ubuntu 22.04 instance using %s...\n" "$AMI_ID"

  RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id "$AMI_ID"        \
    --instance-type t2.micro            \
    --key-name "$KEY_NAME"                \
    --security-groups "$SEC_GRP")

  INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')

  printf "Waiting for instance creation...\n"
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

  PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids "$INSTANCE_ID" |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress')

  printf "New instance $INSTANCE_ID @ $PUBLIC_IP \n"

  echo $PUBLIC_IP $INSTANCE_ID

}

function create_worker_ami() {
  IMAGE_ID=$(aws ec2 describe-images --owners self --filters "Name=tag:$IMG_TAG_KEY_1,Values=[$IMG_TAG_VAL_1]" "Name=name, Values=[$AMI_NAME]" | jq --raw-output '.Images[] | .ImageId')

  if [[ $IMAGE_ID ]]
  then
    echo "$IMAGE_ID"
    return
  fi

  printf "Creating Ubuntu 22.04 instance using %s...\n" "$AMI_ID"

  RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id "$UBUNTU_22_04_AMI"        \
    --instance-type t2.micro            \
    --key-name "$KEY_NAME"                \
    --security-groups "$SEC_GRP")

  INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')

  printf "Waiting for instance creation...\n"
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

  PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids "$INSTANCE_ID" |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress')

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
EOF

  printf "Creating new image...\n"
  IMAGE_ID=$(aws ec2 create-image --instance-id "$INSTANCE_ID" \
        --name "$AMI_NAME" \
        --tag-specifications ResourceType=image,Tags="[{Key=$IMG_TAG_KEY_1,Value=$IMG_TAG_VAL_1}]" \
        --description "An AMI for workers in hash cluster" \
        --region "$USER_REGION" \
        --query ImageId --output text)

  printf "Waiting for image creation...\n"
  aws ec2 wait image-available \
      --image-ids "$IMAGE_ID"

  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"

  echo "$IMAGE_ID"
}

function fire_load_balancer() {
  WORKER_AMI_ID=$1

  printf "Create an IAM Role\n"
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$POLICY_PATH"

  printf "Attach a Policy with the Role\n"
  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

  printf "Verify the policy assignment\n"
  aws iam create-instance-profile --instance-profile-name "$ROLE_NAME"

  printf "Creating Ubuntu 22.04 instance using %s...\n" "$AMI_ID"

  RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id "$UBUNTU_22_04_AMI"        \
    --instance-type t2.micro            \
    --key-name "$KEY_NAME"                \
    --security-groups "$SEC_GRP")

  INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')

  printf "Waiting for instance creation...\n"
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

  PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids "$INSTANCE_ID" |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress')

  printf "New instance $INSTANCE_ID @ $PUBLIC_IP \n"

  aws iam add-role-to-instance-profile --role-name "$ROLE_NAME" --instance-profile-name "$ROLE_NAME"

  printf "Associate IAM role to instance\n"
  aws ec2 associate-iam-instance-profile --instance-id "$INSTANCE_ID" --iam-instance-profile Name="$ROLE_NAME"

  printf "New end point - %s @ %s \n" "$INSTANCE_ID" "$PUBLIC_IP"

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
      echo USER_REGION = "'$USER_REGION'" >> "$LB_CONST"

      printf "Install requirements\n"
      pip3 install -r "$LB_REQ"

      export FLASK_APP="load_balancer/app.py"
      nohup flask run --host=0.0.0.0 &>/dev/null & exit
EOF

  echo "$PUBLIC_IP"

}

function fire_end_point() {
  LB_PUBLIC_IP=$1

  printf "Creating Ubuntu 22.04 instance using %s...\n" "$AMI_ID"

  RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id "$UBUNTU_22_04_AMI"        \
    --instance-type t2.micro            \
    --key-name "$KEY_NAME"                \
    --security-groups "$SEC_GRP")

  INSTANCE_ID=$(echo "$RUN_INSTANCES" | jq -r '.Instances[0].InstanceId')

  printf "Waiting for instance creation...\n"
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

  PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids "$INSTANCE_ID" |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress')

  printf "New instance $INSTANCE_ID @ $PUBLIC_IP \n"

  echo "Deploy app"
  ssh -i "$KEY_PEM" -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@"$PUBLIC_IP" <<EOF

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
}


#printf "Create key pair \n"
#create_key_pair
#
#printf "Create security group \n"
#MY_IP=$(setup_security_group)
#
#printf "Create worker AMI \n"
#worker_AMI_logs=$(create_worker_ami)
#echo "$worker_AMI_logs" >> worker_AMI_logs.txt
#WORKER_AMI_ID=$(echo "$worker_AMI_logs" | tail -1)
#printf "Using %s \n" "$WORKER_AMI_ID"

WORKER_AMI_ID="ami-0a5c702ff19516dfa"

printf "Fire load balancer  \n"
LB_logs=$(fire_load_balancer "$WORKER_AMI_ID")
echo "$LB_logs" >> LB_logs.txt
LB_PUBLIC_IP=$(echo "$LB_logs" | tail -1)
printf "New load balancer @ %s \n" "$LB_PUBLIC_IP"

#printf "Fire first end point \n"
#EP_1_logs=$(fire_end_point "$LB_PUBLIC_IP")
#echo "$EP_1_logs" >> EP_1_logs.txt
#EP_1_PUBLIC_IP=$(echo "$EP_1_logs" | tail -1)
#printf "New end point @ %s \n" "$EP_1_PUBLIC_IP"
#
#printf "Fire second end point"
#EP_2_logs=$(fire_end_point "$LB_PUBLIC_IP")
#echo "$EP_2_logs" >> EP_2_logs.txt
#EP_2_PUBLIC_IP=$(echo "$EP_2_logs" | tail -1)
#printf "New end point @ %s \n" "$EP_2_PUBLIC_IP"