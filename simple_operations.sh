# Define our security credentials
AWS_PARAMS="--aws-access-key `cat /etc/ec2/aws-access-key-id` --aws-secret-key `cat /etc/ec2/aws-secret-access-key`"
RDS_PARAMS="--access-key-id `cat /etc/ec2/aws-access-key-id` --secret-key `cat /etc/ec2/aws-secret-access-key`"

#################
# EC2 (Servers)
#################

# Find IDs of active servers
ec2-describe-instances $AWS_PARAMS | grep 'running' | awk '{print $2}'

# Create an AMI (backup image) of a server
ec2-create-image $AWS_PARAMS --name cli-backup --no-reboot i-dae9cb73

# Reboot a server
ec2-reboot-instances $AWS_PARAMS i-dae9cb73

#################
# RDS (Databases)
#################

# Find IDs of active databases
rds-describe-db-instances $RDS_PARAMS | grep 'available' | awk '{print $2}'

# Create a snapshot (backup) of a database
rds-create-db-snapshot $RDS_PARAMS --db-instance-identifier test --db-snapshot-identifier cli-backup

# Reboot a database
rds-reboot-db-instance $RDS_PARAMS --db-instance-identifier test
