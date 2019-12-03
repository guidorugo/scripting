import boto3
import argparse
import botocore
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--profile', '-p', nargs='?', help='Specify profile')
parser.add_argument('--region', '-r', nargs='?', help='Specify region')
args = parser.parse_args()

def turn_off_asg():
    if not len(sys.argv) == 5:
        parser.print_help()
        sys.exit(1)
    boto3.setup_default_session(profile_name=args.profile, region_name=args.region)
    for asg in boto3.client('autoscaling').describe_auto_scaling_groups()['AutoScalingGroups']:
        print('Setting desire capacity in ' + asg['AutoScalingGroupName'] + ' to 0')
        boto3.client('autoscaling').update_auto_scaling_group(AutoScalingGroupName=asg['AutoScalingGroupName'], MinSize=0, DesiredCapacity=0)

try:
    turn_off_asg()
except botocore.vendored.requests.exceptions.SSLError:
    print('Connection timed out')
