#!/bin/sh

echo 2 > /sys/class/net/eth1/queues/rx-0/rps_cpus
echo 1 > /sys/class/net/eth0/queues/rx-0/rps_cpus
echo 3 > /sys/class/net/wl0/queues/rx-0/rps_cpus
echo 3 > /sys/class/net/wl1/queues/rx-0/rps_cpus

echo 3 > /sys/class/net/wl14/queues/rx-0/rps_cpus
echo 3 > /sys/class/net/wl5/queues/rx-0/rps_cpus
echo 3 > /sys/class/net/wl9/queues/rx-0/rps_cpus
echo 3 > /sys/class/net/apcli0/queues/rx-0/rps_cpus
echo 3 > /sys/class/net/apclix0/queues/rx-0/rps_cpus

echo 3 > /proc/irq/77/smp_affinity
echo 3 > /proc/irq/78/smp_affinity
echo 3 > /proc/irq/79/smp_affinity
echo 3 > /proc/irq/7/smp_affinity

