#!/bin/bash

[ $# -eq 1 ] && block_devs=($(echo $1 | tr ':' '\n' | xargs) )

echo  "Provided: $1 [ $block_devs ,${#block_devs[$@]} Devices]"

cat <<EOF | tee disk-benchmark.fio

[global]
name=GEN

# If block device is specified, skip 'size' option else skip 'filename' & enable 'size' option
# filename/size option
$(

if [ ${#block_devs[@]} -eq 0 ]
then
	#f_size=$()
	echo size=200M
else
	echo filename=$1 #${block_devs[@]}
fi

direct=1

[ $direct -eq 1 ] && echo -e "direct=$direct\nsync=0" || echo -e "direct=$direct\nsync=1"

)

runtime=5m
iodepth=1

numjobs=1

# This pattern can be anything hex,integer,string
buffer_pattern=0xdeadface

percentile_list=99.999 
write_lat_log=latlog 
group_reporting

# Try writes of (%) 100 95 65 50 35 5 0
rwmixwrite=100

stonewall

[READ-BW]
rw=read
bs=4k

[WRITE-BW]
rw=write
bs=4k


[randread]
rw=randread
bs=128k

[randwrite]
rw=randwrite
bs=128k

[readwrite]
rw=readwrite

EOF

