LB_PUBLIC_IP=$1
KEY_NAME="Dynamic-workload-AWS"
KEY_PEM="$KEY_NAME.pem"
SEC_GRP="Dynamic-workload-SG"
UBUNTU_22_04_AMI="ami-04aa66cdfe687d427"

echo "Creating Ubuntu 22.04 instance..."
RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_22_04_AMI        \
    --instance-type t2.micro            \
    --key-name $KEY_NAME                \
    --credit-specification CpuCredits=unlimited \
    --tag-specifications "ResourceType=instance,Tags=[{Key=load_balancer_ip,Value=$MY_IP}]" \
    --security-groups $SEC_GRP)

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
    git clone {{}}
    cd {{}}

    echo "Install requirements"
    pip3 install -r requirements.txt

    echo LB_PUBLIC_IP = $LB_PUBLIC_IP >> {{}}const.py

    export FLASK_APP=app/app.py
    echo "Run app"
    python3 -m flask run --host=0.0.0.0

EOF