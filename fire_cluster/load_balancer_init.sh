#!/bin/bash

source "fire_cluster/const.txt"
KEY_PEM="$KEY_NAME_LB.pem"

echo "create key pair $KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $KEY_NAME_LB \
    | jq -r ".KeyMaterial" > $KEY_PEM

# secure the key pair
chmod 400 $KEY_PEM

echo "setup firewall $SEC_GRP_LB"
aws ec2 create-security-group   \
    --group-name $SEC_GRP_LB       \
    --description "Access my instances"

# figure out my ip
MY_IP=$(curl ipinfo.io/ip)
echo "My IP: $MY_IP"

echo "setup rule allowing SSH access to $MY_IP only"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP_LB --port 22 --protocol tcp \
    --cidr $MY_IP/32

echo "setup rule allowing HTTP (port 5000) access to $MY_IP only"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP_LB --port 5000 --protocol tcp \
    --cidr $MY_IP/32