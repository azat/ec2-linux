#!/usr/bin/env bash

# https://lkml.org/lkml/2015/3/31/735

sleep 120
awk 'BEGIN { while (i++ < 60) { getline < "/proc/loadavg"; close("/proc/loadavg"); print $1; sum += $1; system("sleep 10"); } --i; avg=sum/i; print "Avg: " avg; if (avg > 0.8) { exit(1) } else { exit(0) } }'
