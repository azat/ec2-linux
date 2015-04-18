#!/usr/bin/env bash

SELF="$1"
SOURCES="$2"

trap cleanup EXIT

cd "$SOURCES"

export PATH=$PATH:$SELF
source bootstrap.sh
version=$(git describe)

function log()
{
    local d=$(date +'%Y-%m-%d %H:%I:%S')
    echo "[$d] =================== $@ ==================="
}
function show_config()
{
    log "$@"
    log "Version: $version"
}
function check_command()
{
    local instance=$1
    local ip=$2
    shift 2
    local cmd=${@:-"uname -r"}
    show_config $ip

    if ! execute_command $ip $cmd; then
        console_instance $instance
        return 1
    fi
    return 0
}
function make_kernel()
{
    log "Making kernel package"

    make olddefconfig
    make-kpkg --rootcmd fakeroot --initrd kernel_image -j1 >/dev/null
}
function restart_kernel_with_bisecting()
{
    local instance=$1
    local ip=$2

    deb=$(ls -t ../*.deb | head -1)
    copy $deb $ip:/tmp/
    execute_command $ip 'sudo dpkg -i /tmp/*.deb'
    reboot_wait_instance $instance $ip
}
# XXX: special exit code
function check_kernel()
{
    log "Creating instance"
    read instance ip <<<$(create_wait_instance)
    export instance # for cleanup
    log "Instance $instance:$ip created"
    console_instance $instance

    log "Check with stock kernel"
    check_command $instance $ip || exit 1

    restart_kernel_with_bisecting $instance $ip

    log "Check with bisected kernel"
    check_command $instance $ip || exit 1
}

function cleanup()
{
    log "Terminating $instance"
    terminate_instance $instance
}

function main()
{
    show_config
    make_kernel || exit 1
    check_kernel
}
main
