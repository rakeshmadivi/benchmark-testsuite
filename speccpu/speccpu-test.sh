#!/bin/bash
#------------ SPEC CPU Test -----------------
# SPEC
speccpu_tests()
{
	default_loc=${HOME}/spec2017
	echo -e "SPEC HOME Location: $default_loc \nIs above location correct?(y/n): "
	read confirm
	speccpu_home=""
	if [ "$confirm" = "y" ];then
		speccpu_home=$default_loc
	else
		echo -e "Please enter SPECCPU-2017 Installed Location(Full path): "
		read speccpu_home #=$HOME/spec2017_install/
	fi

	echo -e "SELECTED SPEC HOME LOCATION: ${speccpu_home}\n"
	echo Sourcing SPEC Environment...
	cd $speccpu_home && source shrc

	cd config
	cfg_list=($(echo `ls *.cfg`))
	for i in $(seq 0 $(( ${#cfg_list[*]} - 1)) )
	do
		echo $i ${cfg_list[$i]}      
	done

	echo -e "Enter config file index: "
	read cfg_option
	cfgfile=$cfg_list[$cfg_option]

	#=$1
	copies=$ncpus
	threads=1

	stack_size=`ulimit -s`
	stack_msg="\nNOTE: Stack Size is lesser than required limit. You might want to increase limit else you might experience cam4_s failure.\n"

	echo -e "Changing STACKSIZE soft limit..."
	ulimit -S -s 512000

	echo ULIMIT: `ulimit -s`

	echo -e "\nUSING CONFIGURATION FILE: $cfgfile [ PATH: $PWD ] \n"
	#cd $speccpu_home/
	#source $speccpu_home/shrc
	#cd config

	declare -a spectests=("intrate" "fprate" "intspeed" "fpspeed")
	for i in "${spectests[@]}"
	do    
		sleep 3
		st=$SECONDS
		if [ "$i" = "intspeed" ] || [ "$i" = "fpspeed" ]; then
			copies=1
			threads=$th_per_core

			echo -e "RUN: $i \nCONFIG: $cfgfile \nCOPIES: $copies THREADS: $threads"

			pin=`cat /sys/devices/system/cpu/cpu1/topology/thread_siblings_list`
			echo -e "Running $i with PINNING: ${pin}"
			time numactl -C ${pin} -l runcpu -c $cfgfile --tune=base --copies=$copies --threads=$threads --reportable $i

			echo -e "Running $i with NO_PINNING"
			time runcpu -c $cfgfile --tune=base --copies=$copies --threads=$threads --reportable $i

		else
			copies=$ncpus
			threads=1
			echo -e "RUN: $i \nCONFIG: $cfgfile \nCOPIES: $copies THREADS: $threads"
			time runcpu -c $cfgfile --tune=base --copies=$copies --threads=$threads --reportable $i
		fi
		en=$SECONDS
		echo -e "${i} : Elapsed time - $((en-st)) Seconds."          
	done
}
