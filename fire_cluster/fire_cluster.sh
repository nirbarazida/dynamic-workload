KEY_NAME="Dynamic-workload-AWS"
KEY_PEM="$KEY_NAME.pem"

echo "create key pair $KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $KEY_NAME \
    | jq -r ".KeyMaterial" > $KEY_PEM

# secure the key pair
chmod 400 $KEY_PEM

SEC_GRP="Dynamic-workload-SG"

echo "setup firewall $SEC_GRP"
aws ec2 create-security-group   \
    --group-name $SEC_GRP       \
    --description "Access my instances"

# figure out my ip
MY_IP=$(curl ipinfo.io/ip)
echo "My IP: $MY_IP"

echo "setup rule allowing SSH access to $MY_IP only"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 22 --protocol tcp \
    --cidr $MY_IP/32

echo "setup rule allowing HTTP (port 5000) access to $MY_IP only"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 5000 --protocol tcp \
    --cidr $MY_IP/32

# TODO: send parameters
echo "Create worker AMI"
chmod 777 create_worker_ami.sh
WORKER_AMI_ID=$(./create_worker_ami.sh)

# TODO: send parameters
echo "Fire load balancer"
chmod 777 fire_load_balancer.sh
LB_PUBLIC_IP=$(./fire_load_balancer.sh "$WORKER_AMI_ID")

# TODO: send parameters
echo "Fire first end point"
chmod 777 fire_end_point.sh $LB_PUBLIC_IP
./fire_end_point.sh

# TODO: send parameters
echo "Fire second end point"
chmod 777 fire_end_point.sh $LB_PUBLIC_IP
./fire_end_point.sh



# TODO: fire base worker so I'll always have one up