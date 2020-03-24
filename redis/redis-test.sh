#!/bin/bash
#---------------- REDIS TEST --------------------
redis_tests()
{
  echo -e "Do you want to run redis test?(y/n)"
  read op
  
  if [ "$op" = "y" ];then
    which redis-benchmark > /dev/null 2>&1
    if [ "$?" != "0" ];then
      echo -e "\nError: redis-benchmark is not installed. Please install and re-run.\n"
    else
      outfile=redis_benchmark.txt
      outfile2=redis_benchmark_nopinnin.txt
      rm -rf $outfile
      echo -e "`lscpu | grep Model`" >> $outfile
      echo -e "`lscpu | grep Model`" >> $outfile2
      
      redis_pid=`pidof redis-server`
      redis_cpu=`ps -o psr ${redis_pid}|tail -n1`
      other_cpus="`echo $(numactl --hardware | grep cpus | grep -v "${redis_cpu}" | cut -f4- -d' ')|sed -r 's/[ ]/,/g'`"
      echo -e "Redis server running on: ${redis_cpu} and redis-benchmark will run on: ${other_cpus}\n"
      sleep 2
      totreq=10000000
      reqstep=$((totreq/4))
      
      cpustep=$((ncpus/4))
      
      for((req=$reqstep; req<=$totreq; req+=$reqstep))
      do
        for((par_c=$cpustep; par_c<=$ncpus; par_c+=$cpustep))
        do
          echo -e "\nRunning: ==== ${par_c}C_${req}N for get,set operations with pinning ===="
          echo -e "\n==== ${par_c}C_${req}N ====" >> $outfile

          st=$SECONDS
          taskset -c ${other_cpus} redis-benchmark -n $req -c $par_c -t get,set -q >> $outfile
          en=$SECONDS
          echo -e "Elapsed Time: $((en-st)) Seconds." >> $outfile
          
          # NO PINNING 
          echo -e "\nRunning: ==== ${par_c}C_${req}N for get,set operations ===="
          echo -e "\n==== ${par_c}C_${req}N ====" >> $outfile2

          st=$SECONDS
          redis-benchmark -n $req -c $par_c -t get,set -q >> $outfile2
          en=$SECONDS
          echo -e "Elapsed Time: $((en-st)) Seconds." >> $outfile2
          
        done
      done
     fi
   else
    echo -e "REDIS TEST Cancelled by user...\n"
   fi
}
