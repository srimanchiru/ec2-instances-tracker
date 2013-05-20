#!/bin/bash

# set -x

# --------- License Info ---------
# Copyright 2013 Emind Systems Ltd - htttp://www.emind.co
# This file is part of Emind Systems DevOps Tool set.
# Emind Systems DevOps Tool set is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
# Emind Systems DevOps Tool set is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Emind Systems DevOps Tool set. If not, see http://www.gnu.org/licenses/.

pid_file=/var/run/ec2-instances-tracker.pid
export JAVA_HOME=/usr/lib/jvm/jre
export EC2_HOME=/opt/aws/apitools/ec2

function usage () {
    echo "Usage: $0 -O <aim-key> -W <aws-secret> [-r all|<region-url>]"
}

while getopts O:W:rh flag; do
	case $flag in
	O)
	key=$OPTARG;
	;;
	W)
	secret=$OPTARG;
	;;
	r)
	region_option=$OPTARG;
	;;
	h)
	usage;
	exit;
	;;
  esac
done

if [ "x${key}" = "x" ] || [ "x${secret}" = "x" ]; then
	usage;
	exit;
fi

if [ -f ${pid_file} ]; then
	other_pid=$(cat ${pid_file})
	kill -0 ${other_pid} >/dev/null
	if [ $? -eq 0 ]; then
		logger -s -t ec2-instances-tracker "Another process is running with pid=${other_pid}"
		exit
	fi
else
	echo $$ > ${pid_file}
	logger -s -t ec2-instances-tracker "Start pid=$$"
fi

desc_instances="/opt/aws/bin/ec2-describe-instances -O ${key} -W ${secret}"
desc_reg_cmd="/opt/aws/bin/ec2-describe-regions -O ${key} -W ${secret}"

if [ "${region_option}" = "all" ] || [ "${region_option}" = "" ]; then
    aws_regions=$(${desc_reg_cmd} |awk '{print $3}')
elif [ "${region_option}" != "" ]; then
    aws_regions=${region_option}
fi

for region in ${aws_regions}; do
	cache_file=/tmp/ec2-instances-tracker.${region}
	logger -s -t ec2-instances-tracker "Discovering region=${region}"

	if [ -f ${cache_file} ]; then
		mv ${cache_file} ${cache_file}.last
	else
		touch ${cache_file}.last
	fi

	${desc_instances} --hide-tags --show-empty-fields --url https://${region} |grep -e ^INSTANCE > ${cache_file}.tmp
	if [ $? -eq 0 ]; then
		cat ${cache_file}.tmp | awk '{print "InstanceID="$2 " State="$6 " SecGrp="$7 " Type="$10 " AZ="$12 " PubIP="$17 "PrivIP="$18 " VpcID="$19 " SubnetID="$20}' | sort -d -f > ${cache_file}
		diff ${cache_file} ${cache_file}.last | sed 's|<|Conf=current|g' | sed 's|>|Conf=previus|g' | grep -E "^Conf=current" > ${cache_file}.msg
		while read -r line
		do
			logger -s -t ec2-instances-tracker "Region=${region} $line"
		done < ${cache_file}.msg
	fi
done

logger -s -t ec2-instances-tracker "End pid=$$"
rm -rf ${pid_file}
exit
