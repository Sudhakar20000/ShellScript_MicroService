#/bin/bash
LOGDIR=/var/log/Mongo
mkdir -p $LOGDIR
chown ec2-user:ec2-user $LOGDIR
chmod 755 $LOGDIR
LOGFILE=$LOGDIR/$0.log
R="\e[31m"
G="\e[32"
Y="\e[33"
N="\e[0"
TIME_STAMP=$(date "+%Y-%m-%d %H:%M:%D")
USERID=$(id -u)

if [ USERID -eq 0 ]; then
  echo -e "$TIME_STAMP [ERROR] $R swithch to root user $N" | tee -a $LOGFILE
  exit 1
fi
VALIDATE()
 if [ $1 -nq 0 ]; then
 echo -e "$TIME_STAMP [ERROR] $R failed $2 .. $N" | tee -a $LOGFILE
 exit 1
 else
 echo -e "$TIME_STAMP [SUCCESS] $G Success .. $N" | tee -a $LOGFILE
 fi

 cp mongo.repo /etc/yum.repos.d/mongo.repo
 VALIDATE $? "Adding mongo.repo"

 dnf install mongodb-org -y &>> $LOGFILE
 VALIDATE $? "Installing Mongo"

 systemctl enable --now mongodb
 VALIDATE $? "started and enable mongodb"

 sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mongod.conf/g
 VALIDATE $? "ip config change"

 systemctl restart mongodb
 VALIDATE $? "mongodb restart"





