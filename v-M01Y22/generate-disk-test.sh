#!/bin/bash

[ $# -eq 1 ] && block_devs=($(echo $1 | xargs -n1 -d: | xargs) )

echo  "Provided: $1 [ $block_devs ,${#block_devs[$@]} Devices]"


IODEPTH=(1 2 4 8 16 32 64)


for i in ${IODEPTH[@]}
do
tname=disk-benchmark-IOD_${IODEPTH}.fio

cat <<EOF | tee $tname

[global]
name=$tname

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
buffered=0

# delay can be range. but for this test we use fixed.
startdelay=4

ramp_time=5

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
bs=4k

EOF

echo RUNNING: $tname

res_dir=disk-bench-results

mkdir -p $res_dir

fio --output-format=json $res_dir/${tname/.fio/.json}

done
