import boto3
import argparse
import botocore
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--profile', '-p', nargs='?', help='Specify profile')
parser.add_argument('--region', '-r', nargs='?', help='Specify region')
args = parser.parse_args()

def delete_rds():
    if not len(sys.argv) == 5:
        parser.print_help()
        sys.exit(1)
    boto3.setup_default_session(profile_name=args.profile, region_name=args.region)
    for rds in boto3.client('rds').describe_db_instances()['DBInstances']:
        if not rds['Engine'] == 'aurora':
            print('Removing ' + rds['DBInstanceIdentifier'])
            boto3.client('rds').delete_db_instance(DBInstanceIdentifier=rds['DBInstanceIdentifier'], FinalDBSnapshotIdentifier=rds['DBInstanceIdentifier'], DeleteAutomatedBackups=False)
        if rds['Engine'] == 'aurora':
            print('Removing ' + rds['DBInstanceIdentifier'])
            boto3.client('rds').delete_db_cluster(DBClusterIdentifier=rds['DBInstanceIdentifier'], FinalDBSnapshotIdentifier=rds['DBInstanceIdentifier'])

try:
    delete_rds()
except botocore.vendored.requests.exceptions.SSLError:
    print('Connection timed out')