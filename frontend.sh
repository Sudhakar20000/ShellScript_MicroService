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
SCRIPI_DIR=$PWD

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

dnf module disable nginx -y  &>>$LOGFILE
dnf module enable nginx:1.24 -y  &>>$LOGFILE
dnf install nginx -y  &>>$LOGFILE
VALIDATE $? "install nginx"

systemctl enable nginx  &>>$LOGFILE
systemctl start nginx  &>>$LOGFILE
VALIDATE $? "start nginx"

rm -rf /usr/share/nginx/html/*  &>>$LOGFILE
VALIDATE $? "remove default files"

curl -o /tmp/frontend.zip https://roboshop-artifacts.s3.amazonaws.com/frontend-v3.zip  &>>$LOGFILE
VALIDATE $? "get the code"

cd /usr/share/nginx/html  &>>$LOGFILE
unzip /tmp/frontend.zip  &>>$LOGFILE
VALIDATE $? "unzip the code"

cp -r  $SCRIPI_DIR/nginx.conf /etc/nginx/nginx.conf  &>>$LOGFILE
VALIDATE $? "copy configure files"

systemctl restart nginx  &>>$LOGFILE
VALIDATE $? "restart the nginx"
