#!/bin/bash
LOGDIR=/var/log/roboshop_log
LOGFILE=$LOGDIR/$0.sh
mkdir -p /var/log/roboshop_log
chmod -R 755 $LOGDIR
chown -R ec2-user:ec2-user $LOGDIR
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"
USERID=$(id -u)
TIME_STAMP=$(date '+%Y-%m-%d %H:%M:%S')
if [ $USERID -ne 0 ]; then
  echo -e "$TIME_STAMP [ERROR] $R switch to root user $N" | tee -a $LOGFILE 
  exit 1
fi
VALIDATE () {
    if [ $1 -ne 0 ]; then
    echo -e "$TIME_STAMP [error] $R error for $2 $N" | tee -a $LOGFILE
    exit 1
    else
    echo -e "$TIME_STAMP [INFO] $G success for $2 $N" | tee -a $LOGFILE
fi
}

dnf install python3 gcc python3-devel -y

VALIDATE $? "install python"

id roboshop
if [ $? -eq 0 ]; then
 echo -e "$TIME_STAMP the user exists $Y skpping.. $N" | tee -a $LOGFILE
 else
 useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop  &>>$LOGFILE
 echo -e "$TIME_STAMP [INFO] $G user created $N" | tee -a $LOGFILE
fi

mkdir -p /app

curl -L -o /tmp/payment.zip https://roboshop-artifacts.s3.amazonaws.com/payment-v3.zip
VALIDATE $? "download code"

cd /app 
unzip /tmp/payment.zip

VALIDATE $? "unzip code"

cd /app 
pip3 install -r requirements.txt
VALIDATE $? "install pip packages"

cp -r payment.service  /etc/systemd/system/payment.service
VALIDATE $? "copy user service"

systemctl daemon-reload
systemctl enable payment 
systemctl start payment
VALIDATE $? "enabe and start service"