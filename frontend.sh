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

dnf module disable nginx -y
dnf module enable nginx:1.24 -y
dnf install nginx -y
VALIDATE $? "install nginx"

systemctl enable nginx 
systemctl start nginx 
VALIDATE $? "start nginx"

rm -rf /usr/share/nginx/html/* 
VALIDATE $? "remove default files"

curl -o /tmp/frontend.zip https://roboshop-artifacts.s3.amazonaws.com/frontend-v3.zip
VALIDATE $? "get the code"

cd /usr/share/nginx/html 
unzip /tmp/frontend.zip
VALIDATE $? "unzip the code"

cp -r  nginx.conf /etc/nginx/nginx.conf
VALIDATE $? "copy configure files"

systemctl restart nginx 
VALIDATE $? "restart the nginx"
