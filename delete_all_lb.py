import boto3
import argparse
import botocore
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--profile', '-p', nargs='?', help='Specify profile')
parser.add_argument('--region', '-r', nargs='?', help='Specify region')
args = parser.parse_args()

def delete_load_balancer():
    if not len(sys.argv) == 5:
        parser.print_help()
        sys.exit(1)
    boto3.setup_default_session(profile_name=args.profile, region_name=args.region)
    for lbs in boto3.client('elb').describe_load_balancers()['LoadBalancerDescriptions']:
        print('Removing ' + lbs['LoadBalancerName'])
        boto3.client('elb').delete_load_balancer(LoadBalancerName=lbs['LoadBalancerName'])

try:
    delete_load_balancer()
except botocore.vendored.requests.exceptions.SSLError:
    print('Connection timed out')