#!/bin/bash
LOGDIR=/var/log/Mongo
mkdir -p $LOGDIR
chown ec2-user:ec2-user $LOGDIR
chmod 755 $LOGDIR
LOGFILE=$LOGDIR/$0.log
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"
TIME_STAMP=$(date "+%Y-%m-%d %H:%M:%S")
USERID=$(id -u)

if [ $USERID -ne 0 ]; then
  echo -e "$TIME_STAMP [ERROR] $R switch to root user $N" | tee -a $LOGFILE
  exit 1
fi
VALIDATE() {
 if [ $1 -ne 0 ]; then
 echo -e "$TIME_STAMP [ERROR] $R failed $2 .. $N" | tee -a $LOGFILE
 exit 1
 else
 echo -e "$TIME_STAMP [SUCCESS] $G Success .. $N" | tee -a $LOGFILE
 fi
}
 cp mongo.repo /etc/yum.repos.d/mongo.repo
 VALIDATE $? "Adding mongo.repo"

 dnf install mongodb-org -y &>> $LOGFILE
 VALIDATE $? "Installing Mongo"

 systemctl enable --now mongod
 VALIDATE $? "started and enable mongod"

 sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mongod.conf/
 VALIDATE $? "ip config change"

 systemctl restart mongod
 VALIDATE $? "mongodb restart"





