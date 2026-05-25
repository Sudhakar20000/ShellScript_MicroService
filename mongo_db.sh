#!/bin/bash
LOGDIR=/var/log/mongo_log
mkdir -p $LOGDIR
chmod -R 755  $LOGDIR
chown -R ec2-user:ec2-user $LOGDIR
LOGFILE=$LOGDIR/$0.log
R="e\[31m"
G="e\[32m"
Y="e\[33m"
N="e\[0m"
TIME_STAMP=$(date '+%Y-%m-%d %H:%M:%S')
USERID=$(id -u)

if [ $USERID -ne 0 ]; then
  echo -e "$TIME_STAMP [ERROR] $R switch to root user $N" | tee -a $LOGFILE
  exit 1
fi
VALIDATE () {
  if [ $1 -ne 0 ]; then
  echo -e "$TIME_STAMP [ERROR] $R error for ..$2   $N" | tee -a $LOGFILE
  exit 1
  else
  echo -e "$TIME_STAMP [SUCCESS] $G success for ..$2   $N" | tee -a $LOGFILE
  fi
}

cp -r mongo.repo /etc/yum.repos.d/
VALIDATE $? "add repo"

dnf install mongodb-org -y &>> $LOGFILE
VALIDATE $? "install mongodb"

systemctl enable --now mongod
VALIDATE $? "enable and start"

sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mongod.conf
VALIDATE $? "change config"

systemctl restart mongod
VALIDATE $? "restart mongod"