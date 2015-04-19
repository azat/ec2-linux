#!/usr/bin/env bash

SELF=$(readlink -f "$(dirname $0)")
source $SELF/config.sh

function sg_name()
{
    echo linux-dev-sg
}
function create_security_group()
{
    local name=$(sg_name)

    aws ec2 create-security-group --group-name $name --description ' -- '
    for ip in ${WHITELIST_IPADDRESSES[@]}; do
        aws ec2 authorize-security-group-ingress --group-name $name \
            --protocol tcp --port 22 --cidr $ip/32
    done
}

function key_name()
{
    echo linux-dev-key
}
function key_file()
{
    echo $SELF/${@:-"$(key_name)"}.pem
}
function create_key_pair()
{
    local name=$(key_name)
    local file=$(key_file $name)

    aws ec2 create-key-pair --key-name $name --query KeyMaterial --output text > $file
    chmod 400 $file
}

function prepare()
{
    aws ec2 describe-security-groups |& fgrep -q $(sg_name) || create_security_group
    aws ec2 describe-key-pairs |& fgrep -q $(key_name) || create_key_pair
}

function create_instance()
{
    local id=ami-accff2b1 # ubuntu server 14.04
    local t=t2.micro
    local key=$(key_name)
    local sg=$(sg_name)

    aws ec2 run-instances \
        --image-id $id --count 1 \
        --instance-type $t --key-name $key \
        --security-groups $sg \
        --query 'Instances[0].InstanceId' \
        $@ \
    | tr -d '"'
}
function wait_instance()
{
    local t=1

    local address=None
    while [ "$address" = None ]; do
        address=$(aws ec2 describe-instances \
            --instance-ids $@ \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            2>/dev/null)
        sleep $t
    done

    echo $address
}
function create_wait_instance()
{
    local instance=$(create_instance)
    local ip=$(wait_instance $instance)
    wait_command $ip uname -a >& /dev/null
    echo $instance $ip
}
function terminate_instance()
{
    aws ec2 terminate-instances --instance-ids $@
}
function reboot_instance()
{
    aws ec2 reboot-instances --instance-ids $@
}
function reboot_wait_instance()
{
    local instance=$1
    local ip=$2

    # XXX: Or just execute_command 'shutdown -r now', but with this instance
    # will not reboot right now, but after sometime, and we could have stalled
    # instance
    execute_command $ip sync
    reboot_instance $instance
    wait_command $ip uname -a >& /dev/null
}
function console_instance()
{
    local t=1

    while ! aws ec2 get-console-output --instance-id $@ 2>/dev/null; do
        sleep $t
    done
}

function ssh_user()
{
    echo ubuntu
}
function ssh_options()
{
    local key=$(key_file)
    local t=300
    echo \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=$t \
        -i $key
}
function wait_command()
{
    local ip=$1
    shift
    local retries=10
    local t=1

    local i=0
    while [ $i -lt $retries ]; do
        execute_command $ip $@ && return 0 || continue
        let --i
        sleep 1
    done
    return 1
}
function execute_command()
{
    local ip=$1
    shift

    ssh $(ssh_options) -t $(ssh_user)@$ip $@
}
function copy()
{
    local from="$1"
    local to="$2"

    scp $(ssh_options) $from $(ssh_user)@$to
}
