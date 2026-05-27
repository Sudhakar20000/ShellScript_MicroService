```bash id="8m0u17"
#!/bin/bash

AMI_ID="ami-0220d79f3f480ecf5"
INSTANCE_TYPE="t3.micro"

HOSTED_ZONE_ID="Z03774782PWBJZ4CLRX9V"
DOMAIN="sudhakar.shop"

VPC_ID="vpc-071995b72d576a774"
SUBNET_ID="subnet-08abe1757462b2432"

MY_IP=$(curl -s ifconfig.me)

ACTION=$1
shift

if [ -z "$ACTION" ]; then
    echo "Usage:"
    echo "./aws.sh create mongodb nginx"
    echo "./aws.sh delete frontend"
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Please pass component names"
    exit 1
fi

create() {

    component=$1

    echo "Creating : $component"

    # ----------------------------
    # Security Group
    # ----------------------------

    SG_ID=$(aws ec2 describe-security-groups \
        --filters Name=group-name,Values=robo-${component} \
        --query 'SecurityGroups[0].GroupId' \
        --output text)

    if [ "$SG_ID" == "None" ]; then

        echo "Security Group not found, creating..."

        SG_ID=$(aws ec2 create-security-group \
            --group-name robo-${component} \
            --description "SG for ${component}" \
            --vpc-id $VPC_ID \
            --query 'GroupId' \
            --output text)

        aws ec2 authorize-security-group-ingress \
            --group-id $SG_ID \
            --protocol tcp \
            --port 22 \
            --cidr ${MY_IP}/32

        echo "Security Group Created : $SG_ID"

    else
        echo "Security Group already exists : $SG_ID"
    fi

    # ----------------------------
    # EC2
    # ----------------------------

    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters Name=tag:Name,Values=ec2-${component} \
                  Name=instance-state-name,Values=pending,running,stopping,stopped \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text)

    if [ "$INSTANCE_ID" != "None" ]; then
        echo "EC2 already exists : $INSTANCE_ID"
        return
    fi

    echo "Creating EC2..."

    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id $AMI_ID \
        --instance-type $INSTANCE_TYPE \
        --security-group-ids $SG_ID \
        --subnet-id $SUBNET_ID \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ec2-${component}}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    echo "EC2 Created : $INSTANCE_ID"

    sleep 20

    PRIVATE_IP=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text)

    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    # ----------------------------
    # Route53
    # ----------------------------

    if [ "$component" == "frontend" ]; then
        RECORD_NAME=$DOMAIN
        IP=$PUBLIC_IP
    else
        RECORD_NAME="${component}.${DOMAIN}"
        IP=$PRIVATE_IP
    fi

    echo "Creating Route53 record..."

    cat > route53.json <<EOF
{
  "Comment": "Creating record",
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
        --change-batch file://route53.json >/dev/null

    rm -f route53.json

    echo "Route53 record created"
    echo
}

delete() {

    component=$1

    echo "Deleting : $component"

    # ----------------------------
    # Find Instance
    # ----------------------------

    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters Name=tag:Name,Values=ec2-${component} \
                  Name=instance-state-name,Values=pending,running,stopping,stopped \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text)

    if [ "$INSTANCE_ID" == "None" ]; then
        echo "EC2 not found"
    else

        PRIVATE_IP=$(aws ec2 describe-instances \
            --instance-ids $INSTANCE_ID \
            --query 'Reservations[0].Instances[0].PrivateIpAddress' \
            --output text)

        PUBLIC_IP=$(aws ec2 describe-instances \
            --instance-ids $INSTANCE_ID \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text)

        # ----------------------------
        # Route53 Delete
        # ----------------------------

        if [ "$component" == "frontend" ]; then
            RECORD_NAME=$DOMAIN
            IP=$PUBLIC_IP
        else
            RECORD_NAME="${component}.${DOMAIN}"
            IP=$PRIVATE_IP
        fi

        echo "Deleting Route53 record..."

        cat > route53.json <<EOF
{
  "Comment": "Deleting record",
  "Changes": [{
    "Action": "DELETE",
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
            --change-batch file://route53.json >/dev/null

        rm -f route53.json

        echo "Route53 record deleted"

        # ----------------------------
        # Delete EC2
        # ----------------------------

        echo "Terminating EC2 : $INSTANCE_ID"

        aws ec2 terminate-instances \
            --instance-ids $INSTANCE_ID >/dev/null

        echo "Waiting for termination..."

        aws ec2 wait instance-terminated \
            --instance-ids $INSTANCE_ID

        echo "EC2 deleted"
    fi

    # ----------------------------
    # Delete Security Group
    # ----------------------------

    SG_ID=$(aws ec2 describe-security-groups \
        --filters Name=group-name,Values=robo-${component} \
        --query 'SecurityGroups[0].GroupId' \
        --output text)

    if [ "$SG_ID" == "None" ]; then
        echo "Security Group not found"
    else

        echo "Deleting Security Group : $SG_ID"

        aws ec2 delete-security-group \
            --group-id $SG_ID

        echo "Security Group deleted"
    fi

    echo
}

for component in "$@"
do

    if [ "$ACTION" == "create" ]; then
        create $component

    elif [ "$ACTION" == "delete" ]; then
        delete $component

    else
        echo "Invalid action : $ACTION"
        echo "Use create or delete"
        exit 1
    fi

done
```
