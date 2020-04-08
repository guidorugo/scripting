import boto3
import argparse
import botocore
import sys

# NEEDS SOME WORK

parser = argparse.ArgumentParser()
parser.add_argument('--profile', '-p', nargs='?', help='Specify profile')
parser.add_argument('--region', '-r', nargs='?', help='Specify region')
args = parser.parse_args()

def delete_elasticache():
    if not len(sys.argv) == 5:
        parser.print_help()
        sys.exit(1)
    boto3.setup_default_session(profile_name=args.profile, region_name=args.region)
    for cluster in boto3.client('elasticache').describe_cache_clusters()['CacheClusters']:
        print('Removing ' + cluster['CacheClusterId'])
        try:
            boto3.client('elasticache').delete_cache_cluster(CacheClusterId=cluster['CacheClusterId'],FinalSnapshotIdentifier=cluster['CacheClusterId'])
            boto3.client('elasticache').delete_cache_cluster(CacheClusterId=cluster['CacheClusterId'])
            boto3.client('elasticache').delete_replication_group(ReplicationGroupId=cluster['CacheClusterId'],FinalSnapshotIdentifier=cluster['CacheClusterId'])
        except:
            pass

try:
    delete_elasticache()
except botocore.vendored.requests.exceptions.SSLError:
    print('Connection timed out')