#!/bin/bash
#--------------- NGINX TEST ----------------

nginx_tests()
{
	echo -e "Do you want to run NGINX test?(y/n)"
	read op

	if [ "$op" = "y" ];then
		# REFERENCE: https://github.com/wg/wrk
		# EX: wrk -t12 -c400 -d30s http://127.0.0.1:8080/index.html
		# Runs a benchmark for 30 seconds, using 12 threads, and keeping 400 HTTP connections open.

		# CHECK IF NGINX IS RUNNING ON PORT 80; IF NOT SET FOLLOWING PORT TO RESPECTIVE PORT NUMBER
		nginx_port=80

		echo -e "\nRunning nginx Benchmark...\n"
		outfile=nginx_benchmark.txt
		st=$SECONDS
		for((con=0;con<=10000000;con+=1000000))
		do
			for((th=0;th<=$ncpus;th+=10))
			do
				echo -e "\nRunning CON: $con TH: $th Configuration\n"
				echo -e "\n==== CON: $con TH: $th ====\n" >> $outfile
				#wrk -t$th -c$con -d30s http://localhost:${nginx_port}/index.nginx-debian.html >> $outfile
				ab -c $th -n $con -t 60 -g ${con}n_${th}c_ab_benchmark_gnuplot -e ${con}_${th}_ab_benchmark.csv http://127.0.0.1:${nginx_port}/index.nginx-debian.html >> $outfile
			done   
		done
		en=$SECONDS

		echo -e "ELAPSED TIME: $((en-st))" >> $outfile
	else
		echo -e "NGINX TEST Cancelled by user...\n"
	fi
}
