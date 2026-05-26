#!/bin/bash

AMI_ID="ami-0220d79f3f480ecf5"
INSTANCE_TYPE="t3.micro"
HOSTED_ZONE_ID="Z03774782PWBJZ4CLRX9V"
DOMAIN="sudhakar.shop"
VPC_ID="vpc-071995b72d576a774"
SUBNET_ID="subnet-08abe1757462b2432"

MY_IP=$(curl -s ifconfig.me)

for component in "$@"
do
    echo "Processing: $component"

    # Check Security Group Exists or Not
    SG_ID=$(aws ec2 describe-security-groups \
        --filters Name=group-name,Values=robo-${component} \
        --query 'SecurityGroups[0].GroupId' \
        --output text)

    if [ "$SG_ID" == "None" ]
    then
        echo "Creating Security Group"

        SG_ID=$(aws ec2 create-security-group \
            --group-name robo-${component} \
            --description "SG for ${component}" \
            --vpc-id $VPC_ID \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${component}-sg}]" \
            --query 'GroupId' \
            --output text)

        aws ec2 authorize-security-group-ingress \
            --group-id $SG_ID \
            --protocol tcp \
            --port 22 \
            --cidr ${MY_IP}/32

        echo "SSH rule added"
    else
        echo "Security Group already exists: $SG_ID"
    fi

    # Create EC2 Instance
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id $AMI_ID \
        --instance-type $INSTANCE_TYPE \
        --security-group-ids $SG_ID \
        --subnet-id $SUBNET_ID \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ec2-${component}}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    echo "Created EC2: $INSTANCE_ID"

    sleep 20

    PRIVATE_IP=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text)

    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    # Route53 Logic
    if [ "$component" == "frontend" ]
    then
        RECORD_NAME="${DOMAIN}"
        IP=$PUBLIC_IP
    else
        RECORD_NAME="${component}.${DOMAIN}"
        IP=$PRIVATE_IP
    fi

    echo "Creating Route53 record: $RECORD_NAME -> $IP"

    cat > route53.json <<EOF
{
  "Comment": "Create record for ${component}",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "${RECORD_NAME}",
      "Type": "A",
      "TTL": 1,
      "ResourceRecords": [{
        "Value": "${IP}"
      }]
    }
  }]
}
EOF

    aws route53 change-resource-record-sets \
        --hosted-zone-id $HOSTED_ZONE_ID \
        --change-batch file://route53.json

    echo "Route53 record created"

done