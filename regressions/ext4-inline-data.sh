#!/usr/bin/env bash

# Measure performance of ext4 inline data VS noinline (for small enough files)

dev=$@

function log()
{
    local d=$(date +"%Y-%m-%d %H:%I:%S")
    echo "[$d] ==== $@ ===="
}
function drop_caches()
{
    echo 3 > /proc/sys/vm/drop_caches
}
function bench()
{
    drop_caches
    mount $dev /mnt
    df -hi /mnt
    time fs_mark -D 10000 -S0 -n 100000 -s1000 -L32 $(printf -- " -d %s" /mnt/{1,2,3,4,5,6,7})
    drop_caches
    time find /mnt -type f | wc -l
    df -hi /mnt
    umount $dev
}
function mkfs()
{
    mke2fs -F -t ext4 -I 4096 -m 0 -q $@
}

log "noinline data"
mkfs $dev
bench

log "inline data"
mkfs -O inline_data $dev
bench
