#!/usr/bin/python3

import requests
import argparse
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--url', '-u', metavar='<url>', nargs='?', help='Marathon URL')
parser.add_argument('--up', action='store_true', help='Scale all up to 1')
parser.add_argument('--down', action='store_true', help='Scale all down to 0')
args = parser.parse_args()

if (args.up and args.down) or (not args.up and not args.down):
    sys.exit('You should specify one and only one action.')

if not args.url:
    parser.print_help(sys.stderr)
    sys.exit('\nMissing Marathon URL')

marathon = str(args.url)+'/v2/apps'
get_apps = requests.get(marathon)
if args.up:
    payload = {'instances': 1}
    for each_app in get_apps.json()['apps']:
        requests.put(marathon+each_app['id']+"?force=true", json=payload)
        print(each_app+' set to 1')

elif args.down:
    payload = {'instances': 0}
    for each_app in get_apps.json()['apps']:
        requests.put(marathon+each_app['id']+"?force=true", json=payload)
        print(each_app+' set to 0')
