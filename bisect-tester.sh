#!/usr/bin/env bash

SELF="$1"
SOURCES="$2"
SCRIPT="$3"

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

    if ! wait_command $ip $cmd; then
        console_instance $instance
        return 1
    fi
    return 0
}
function patch_kernel_add_xen()
{
    local config=.config
    # XXX v3.19-rc5 only (we need better mechanism)
    local options=(
        CONFIG_HYPERVISOR_GUEST=y
        CONFIG_PARAVIRT=y
        CONFIG_XEN=y
        CONFIG_XEN_DOM0=y
        CONFIG_XEN_PVHVM=y
        CONFIG_XEN_MAX_DOMAIN_MEMORY=500
        CONFIG_XEN_SAVE_RESTORE=y
        CONFIG_PARAVIRT_CLOCK=y
        CONFIG_PCI_XEN=y
        CONFIG_XEN_PCIDEV_FRONTEND=y
        CONFIG_SYS_HYPERVISOR=y
        CONFIG_XEN_BLKDEV_FRONTEND=y
        CONFIG_XEN_BLKDEV_BACKEND=y
        CONFIG_XEN_NETDEV_FRONTEND=y
        CONFIG_XEN_NETDEV_BACKEND=y
        CONFIG_INPUT_XEN_KBDDEV_FRONTEND=y
        CONFIG_HVC_DRIVER=y
        CONFIG_HVC_IRQ=y
        CONFIG_HVC_XEN=y
        CONFIG_HVC_XEN_FRONTEND=y
        CONFIG_FB_SYS_FILLRECT=m
        CONFIG_FB_SYS_COPYAREA=m
        CONFIG_FB_SYS_IMAGEBLIT=m
        CONFIG_FB_SYS_FOPS=m
        CONFIG_FB_DEFERRED_IO=y
        CONFIG_XEN_FBDEV_FRONTEND=m
        CONFIG_XEN_BALLOON=y
        CONFIG_XEN_SCRUB_PAGES=y
        CONFIG_XEN_DEV_EVTCHN=y
        CONFIG_XEN_BACKEND=y
        CONFIG_XENFS=y
        CONFIG_XEN_COMPAT_XENFS=y
        CONFIG_XEN_SYS_HYPERVISOR=y
        CONFIG_XEN_XENBUS_FRONTEND=y
        CONFIG_XEN_GNTDEV=m
        CONFIG_XEN_GRANT_DEV_ALLOC=m
        CONFIG_SWIOTLB_XEN=y
        CONFIG_XEN_PCIDEV_BACKEND=m
        CONFIG_XEN_PRIVCMD=y
        CONFIG_XEN_ACPI_PROCESSOR=m
        CONFIG_XEN_HAVE_PVMMU=y
        CONFIG_XEN_EFI=y
    )

    echo "# Patching for XEN (AWS EC2)" >> $config
    for o in ${options[@]}; do
        local key=${o/=*/}
        egrep -q "$key(=|\W|$)" $config && \
            sed -i "s/^.*$key.*$/$o/" $config || \
            echo $o >> $config
    done
    log "Patched for XEN"
}
function make_kernel()
{
    log "Making kernel package"

    make olddefconfig
    patch_kernel_add_xen
    make olddefconfig
    make-kpkg --rootcmd fakeroot --initrd kernel_image $MAKE_KPKG_OPTIONS >/dev/null
}
function drop_legacy_ec2_grub()
{
    local ip=$1
    execute_command $ip 'sudo apt-get --yes --force-yes purge grub-legacy-ec2'
    execute_command $ip 'sudo update-grub'
    execute_command $ip 'sudo grub-install /dev/xvda'
}
function restart_kernel_with_bisecting()
{
    local instance=$1
    local ip=$2

    # XXX: be more smart, using version
    deb=$(ls -t ../*.deb | head -1)
    copy $deb $ip:/tmp/
    execute_command $ip 'sudo dpkg -i /tmp/*.deb'
    drop_legacy_ec2_grub $ip
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
    # XXX: this is also additional waiting
    log "Instance $instance:$ip rebooted"
    console_instance $instance

    log "Check with bisected kernel"
    copy $SCRIPT $ip:/tmp/
    check_command $instance $ip /tmp/$(basename $SCRIPT) || exit 1
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
