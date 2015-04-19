#!/usr/bin/env bash

SELF=$(readlink -f "$(dirname $0)")
export PATH=$PATH:$SELF
source bootstrap.sh

function run_bisect()
{
    local self="$SELF"
    local sources="$1"
    local script="$(readlink -f "$self/$2")"
    shift 2

    cd "$sources"
    git bisect start $@
    git bisect run bisect-tester.sh $self $sources $script
    git bisect log
}

function print_help()
{
    echo "$0 [ OPTS ] /path/to/linux-sources /tester-script args-for-bisect" >&2
    echo " -p     - prepare"
    echo
    echo " -h     - print this message"
    exit 1
}
function parse_options()
{
    local OPTIND OPTARG o

    while getopts "hpr:" o; do
        case $o in
            h) print_help ;;
            p) prepare ;;
        esac
    done

    shift $((OPTIND-1))
    run_bisect $@
}

function main()
{
    parse_options $@
}

main $@
