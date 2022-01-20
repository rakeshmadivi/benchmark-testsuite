#!/bin/bash

f=10.0.48.155-jbb-tuning-16-09-21.1

if [ -f $f ]
then

	mapfile -t tunes <<< "$(cat $f | grep "|")"

	for i in "${tunes[@]}"
	do
		default_k=$(echo -e "$i" | cut -f1 -d'|' ) #| cut -f1 -d'-')
		default_v=$(echo -e "$i" | cut -f2 -d'|' | cut -f1 -d'-')

		echo "KEY: $default_k VALUE: $default_v"
	done

	RESET_TUNES=1

	if [ $RESET_TUNES -eq 1 ]
	then
		echo resetting tuned kernel/vm params to default values...

		default_tunes=/etc/sysctl.d/50-default-tunes.conf
		cat << EOF | sudo tee $default_tunes
# Global Kernel Tuning
kernel.numa_balancing = 1
kernel.sched_cfs_bandwidth_slice_us = 5000
kernel.sched_child_runs_first = 0
kernel.sched_latency_ns = 24000000
kernel.sched_migration_cost_ns = 5000000
kernel.sched_min_granularity_ns = 3000000
kernel.sched_nr_migrate = 32
kernel.sched_rr_timeslice_ms = 100
kernel.sched_rt_period_us = 1000000
kernel.sched_rt_runtime_us = 950000
kernel.sched_schedstats = 0
kernel.sched_tunable_scaling = 1
kernel.sched_wakeup_granularity_ns = 4000000

# Virtual Memory Settings
vm.dirty_background_ratio = 10
vm.dirty_expire_centisecs = 3000
vm.dirty_ratio = 20
vm.dirty_writeback_centisecs = 500
#vm.overcommit_memory=2
vm.swappiness = 60
# net.ipv4.tcp_timestamps=0
EOF

sudo sysctl -f $default_tunes

fi

fi
