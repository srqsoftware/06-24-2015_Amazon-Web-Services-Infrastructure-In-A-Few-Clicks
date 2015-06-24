# Production data volume to back up
DATA_VOL="vol-93b46c83"

# Mount locations
DEVICE="/dev/sdj"
DATA_RESTORE=/mnt/latest_data_volume

S3_DIR="s3://itdatabase-backups/`date +'%Y%m%d'`"

# Working directories (temporary data)
SQL_BACKUP=/var/itdatabase/backups/sql
DATA_BACKUP=/var/itdatabase/backups/data

# AWS API config
AWS_PARAMS="--aws-access-key `cat /etc/ec2/aws-access-key-id` --aws-secret-key `cat /etc/ec2/aws-secret-access-key` --region us-west-2"
RDS_PARAMS="--access-key-id `cat /etc/ec2/aws-access-key-id` --secret-key `cat /etc/ec2/aws-secret-access-key` --region us-west-2"
AWS=/opt/aws/bin

# AWS CLI config
export AWS_ACCESS_KEY_ID=`cat /etc/ec2/aws-access-key-id`
export AWS_SECRET_ACCESS_KEY=`cat /etc/ec2/aws-secret-access-key`
AWS_CLI=/usr/bin/aws

# Split archives into chunks
ZIP="zip -s 50m"

# Cron jobs don't have env variables set
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi

#################################################

echo "Starting backup at `date`"

# Remove S3 directory if it already exists
$AWS_CLI s3 rm --recursive $S3_DIR

#################################################
# Back up database
#################################################
$AWS/rds-describe-db-snapshots --db-instance-identifier production --snapshot-type automated $RDS_PARAMS | tail -1 | awk '{print $2}' > /root/latest_rds_snapshot
RDS_SNAPSHOT=`cat /root/latest_rds_snapshot`

echo "Restoring latest RDS snapshot: $RDS_SNAPSHOT"
$AWS/rds-restore-db-instance-from-db-snapshot backup --db-snapshot-identifier $RDS_SNAPSHOT $RDS_PARAMS 
# Wait for DB to come on-line, ideally this would be a while loop
sleep 900

echo "Exporting databases..."
rm -rf $SQL_BACKUP
mkdir -p $SQL_BACKUP
/usr/local/bin/export_db
echo "Finished export `date`"

echo "Deleting temporary RDS instance"
$AWS/rds-delete-db-instance backup --force --skip-final-snapshot $RDS_PARAMS 

echo "Compressing files..."
for i in `ls $SQL_BACKUP`
do
  $ZIP $SQL_BACKUP/$i.zip $SQL_BACKUP/$i
  rm -f $SQL_BACKUP/$i 
done
echo "Finished compressing `date`"

echo "Uploading to S3..."
$AWS_CLI s3 cp --recursive $SQL_BACKUP $S3_DIR/sql
echo "Finished upload `date`"

#################################################
# Back up data volume
#################################################
$AWS/ec2-describe-snapshots $AWS_PARAMS | grep $DATA_VOL | sort -k 5 | tail -1 | awk '{print $2}' > /root/latest_data_snapshot
DATA_SNAPSHOT=`cat /root/latest_data_snapshot`

echo "Restoring latest Data volume snapshot: $DATA_SNAPSHOT"
$AWS/ec2-create-volume --snapshot $DATA_SNAPSHOT --availability-zone us-west-2b $AWS_PARAMS | awk '{print $2}' > /root/latest_data_volume
# Wait for EBS volume to come on-line, ideally this would be a while loop
sleep 300

# Attach the volume to the current instance
umount -f $DEVICE 2>/dev/null
sleep 10
# This is the machine running the backup job, _not_ production
EC2_INSTANCE=`$AWS/ec2-metadata -i | awk '{print $2}'`
$AWS/ec2-attach-volume `cat /root/latest_data_volume` -i $EC2_INSTANCE -d $DEVICE $AWS_PARAMS
sleep 10
mount -o nouuid $DEVICE $DATA_RESTORE
sleep 10

echo "Archiving data..."
rm -rf $DATA_BACKUP
mkdir -p $DATA_BACKUP
tar cf $DATA_BACKUP/mongo.tar -C $DATA_RESTORE mongo
tar cf $DATA_BACKUP/neo4j.tar -C $DATA_RESTORE neo4j
tar cf $DATA_BACKUP/tomcat.tar -C $DATA_RESTORE tomcat
echo "Finished archive `date`"

echo "Deleting temporary volume"
umount $DEVICE
sleep 30
$AWS/ec2-detach-volume `cat /root/latest_data_volume` $AWS_PARAMS
sleep 300
$AWS/ec2-delete-volume `cat /root/latest_data_volume` $AWS_PARAMS

echo "Compressing files..."
for i in `ls $DATA_BACKUP`
do
  $ZIP $DATA_BACKUP/$i.zip $DATA_BACKUP/$i
  rm -f $DATA_BACKUP/$i 
done
echo "Finished compressing `date`"

echo "Uploading to S3..."
$AWS_CLI s3 cp --recursive $DATA_BACKUP $S3_DIR/data
echo "Finished upload `date`"

#################################################

echo "Finished backup at `date`"
