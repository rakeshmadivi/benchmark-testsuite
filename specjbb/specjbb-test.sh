#!/bin/bash
#-------------- SPEC JBB Test ------------

specjbb_tests()
{
	specjbb_home=$HOME/specjbb15
	echo -e "Want to run SPECJBB Test?(y/n)"
	read op
	if [ "$op" = "n" ];then
		echo -e "SPECJBB Test Cancelled by user.\nExiting...\n"
		exit
	else
		cd $specjbb_home
		echo -e "Are you sure configuration parameters are properly set?(y/n)"
		read op
		if [ "$op" = "y" ];then
			echo -e "Starting Power Collection..."
			start_power_collection &

			echo -e "Starting SPECJBB ...."
			time sudo ./run_multi.sh

			echo STOP > $powerstatfile
		elif [ "$op" = "n" ];then
			echo -e "Please edit configuration settings and re-run.\n"
		fi
	fi
}
