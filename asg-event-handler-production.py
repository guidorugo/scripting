from __future__ import print_function
import json
import boto3

# Lambda to be executed after EC2_INSTANCE_LAUNCH or TEST_NOTIFICATION events are detected.

def asg_order(event, context):
    asg_msg = json.loads(event['Records'][0]['Sns']['Message'])
    print(asg_msg)
    asg_name = asg_msg['AutoScalingGroupName']
    asg_event = asg_msg['Event']
    if asg_event == "autoscaling:EC2_INSTANCE_LAUNCH" or asg_event == "autoscaling:TEST_NOTIFICATION":
        print("Handling Launch Event for " + asg_name)
        autoscaling = boto3.client('autoscaling', region_name='us-east-1')
        ec2 = boto3.client('ec2', region_name='us-east-1')
        route53 = boto3.client('route53')
        asg_tagresponse = autoscaling.describe_tags(
                Filters=[
                    {
                        'Name': 'auto-scaling-group',
                        'Values': [asg_name]
                        },
                    {
                        'Name': 'key',
                        'Values': ['role', 'Environment']
                        },
                    ],
                MaxRecords=2)
        print("Processing ASG Tags")
        if len(asg_tagresponse['Tags']) <= 1:
            print("ASG: " + asg_name + " have no valid tags.")
            return asg_msg
        asg_env = asg_tagresponse['Tags'][0]['Value']
        asg_role = asg_tagresponse['Tags'][1]['Value']
        hosted_zone = 'us-east-1'+'.'+asg_env+
        hosted_zone_id = route53.list_hosted_zones_by_name(DNSName=hosted_zone)['HostedZones'][0]['Id']
        asg_instance_list = map(lambda instance: instance['InstanceId'],
                                autoscaling.describe_auto_scaling_groups(AutoScalingGroupNames=[asg_name])
                                ['AutoScalingGroups'][0]['Instances'])
        # Nasty hack to get rid of bogus instance id's of unexisting instances returned by the autoscaling api
        # but don't exist for the ec2 api and throw exceptions, blocking the function. 
        for instance in list(asg_instance_list):
            try:
                ec2.describe_instances(DryRun=False, InstanceIds=[instance])
            except:
                print("removing: " + instance)
                asg_instance_list.remove(instance)
        instance_position = dict.fromkeys(asg_instance_list)
        print(instance_position)
        asg_size = range(1, autoscaling.describe_auto_scaling_groups(AutoScalingGroupNames=[asg_name])['AutoScalingGroups'][0]['MaxSize']+1)
        for index in asg_size:
            instance = ec2.describe_instances(
                    DryRun=False,
                    InstanceIds=asg_instance_list,
                    Filters=[
                        {
                            'Name': 'tag-key',
                            'Values': ['Environment']
                            },
                        {
                            'Name': 'tag-value',
                            'Values': [asg_env]
                            },
                        {
                            'Name': 'tag-key',
                            'Values': ['role'],
                            },
                        {
                            'Name': 'tag-value',
                            'Values': [asg_role]
                            },
                        {
                            'Name': 'instance-state-name',
                            'Values': ['running', 'pending']
                            },
                        {
                            'Name': 'tag-key',
                            'Values': ['Name']
                            },
                        {
                            'Name': 'tag-value',
                            'Values': [asg_env+'-'+asg_role+str(index)]
                            }
                        ]
                    )
            if instance['Reservations']:
                instance_position[instance['Reservations'][0]['Instances'][0]['InstanceId']] = index
        print(asg_size)
        for order in asg_size:
            x = filter(lambda k: instance_position[k] == order, instance_position.keys())
            record_name = asg_role+str(order)+'.us-east-1'+'.'+asg_env
            if not x:
                z = filter(lambda k: instance_position[k] is None, instance_position.keys())
                instance_position[z[0]] = order
                ec2.create_tags(
                        DryRun=False,
                        Resources=z,
                        Tags=[
                            {
                                'Key': 'Name',
                                'Value': asg_env+'-'+asg_role+str(order)
                            },
                        ]
                    )
                instance_ip = map(lambda reservation: reservation['Instances'][0]['NetworkInterfaces'][0]
                                  ['PrivateIpAddress'], ec2.describe_instances(DryRun=False, InstanceIds=z)
                                  ['Reservations'])
                route53.change_resource_record_sets(
                    HostedZoneId=hosted_zone_id,
                    ChangeBatch={
                        'Changes': [
                            {
                                'Action': 'UPSERT',
                                'ResourceRecordSet': {
                                    'Name': record_name,
                                    'Type': 'A',
                                    'TTL': 300,
                                    'ResourceRecords': [{'Value': instance_ip[0]}]
                                    }
                                }
                            ]
                        }
                    )
                print("Assigned position "+str(order)+" to: "+z[0])
                print(record_name)
            else:
                ec2.create_tags(
                        DryRun=False,
                        Resources=x,
                        Tags=[
                            {
                                'Key': 'Name',
                                'Value': asg_env+'-'+asg_role+str(order)
                            },
                        ]
                    )
                instance_ip = map(lambda reservation: reservation['Instances'][0]['NetworkInterfaces'][0]
                                  ['PrivateIpAddress'], ec2.describe_instances(DryRun=False, InstanceIds=x)
                                  ['Reservations'])
                route53.change_resource_record_sets(
                    HostedZoneId=hosted_zone_id,
                    ChangeBatch={
                        'Changes': [
                            {
                                'Action': 'UPSERT',
                                'ResourceRecordSet': {
                                    'Name': record_name,
                                    'Type': 'A',
                                    'TTL': 300,
                                    'ResourceRecords': [{'Value': instance_ip[0]}]
                                    }
                                }
                            ]
                        }
                    )
    return asg_msg
