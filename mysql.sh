#!/bin/bash
LOGDIR=/var/log/roboshop_log
LOGFILE=$LOGDIR/$0.log
mkdir -p $LOGDIR
chmod -R 755 $LOGDIR
chown -R ec2-user:ec2-user $LOGDIR
R="\e[31m"
G="\e[32m"
N="\e[0m"
TIME_STAMP=$(date '+%Y-%m-%d %H:%M:%S')
USERID=$(id -u)
if [ $USERID -ne 0 ]; then
 echo -e " $TIME_STAMP [ERROR] $R switch to root user $N" | tee -a $LOGFILE
 exit 1
fi

VALIDATE() {
    if [ $1 -ne 0 ]; then
    echo -e "$TIME_STAMP [ERROR] $R error for $2 $N" | tee -a $LOGFILE
    else
    echo -e "$TIME_STAMP [INFO] $G success for $2 $N" | tee -a $LOGFILE
    fi
}

dnf install mysql-server -y &>> $LOGFILE

VALIDATE $? "install mysql"

systemctl enable mysqld &>> $LOGFILE
systemctl start mysqld  &>> $LOGFILE

VALIDATE $? "enable and start mysql"

mysql_secure_installation --set-root-pass RoboShop@1  &>> $LOGFILE
VALIDATE $? "Setting up root password"