#!/bin/bash

# GLOBAL VALUES
ncpus=`nproc`
th_per_core=$(echo `lscpu | grep Thread|cut -f2 -d':'`)

powerstatfile=power_collect.status
POWERGET=""
function start_power_collection()
{
  outfile=power_stats.txt
  if [ -f "$powerstatfile" ];then
    echo Removing Existing power status file...
    rm -rf $powerstatfile
  fi
  
  collectstatfile=collect.status
  collectlog=ngcollect.log
  
  sudo ipmitool sdr list | grep "Watts" 2>&1 > /dev/null
  if [ "$?" = "1" ];then
    #export POWERGET=AMPS
    echo -e "Collecting Volts and Amps..."
    
    while true
    do
      timenow=`date +"%d-%b-%Y %H:%M:%S"`
      echo -e "${timenow} Collecting..." >> $collectlog
      date >> $outfile
      sudo ipmitool sdr list | egrep "Volts|Amps" >> $outfile
      
      if [ -f "$powerstatfile" ];then
        if [ "`cat $powerstatfile`" = "STOP" ] ;then
          echo -e "Got STOP Command...\nSTOPPING power collection...\n"
          exit
        fi
      else
        echo -en "\rCollecting Power Utilization (Volts,Amps)..."
      fi
      
      sleep 30
      
    done
  else
    #export POWERGET=WATTS
    echo -e "Collecting Watts..."
    while true
    do
      timenow=`date +"%d-%b-%Y %H:%M:%S"`
      echo -e "${timenow} Collecting..." >> $collectlog
      date >> $outfile
      sudo ipmitool sdr list | grep "Watts" >> $outfile
      
      if [ -f "$powerstatfile" ];then
        if [ "`cat $powerstatfile`" = "STOP" ] ;then
          echo -e "Got STOP Command...\nSTOPPING power collection...\n"
          exit
        fi
      else
        echo -en "\rCollecting Power Utilization (Watts)..."
      fi
      
      sleep 30
      
    done
  fi    
}

function install_mysql()
{
  #echo -e "Install MySQL?(y/n):\n"
  #read op
  which mysql > /dev/null 2>&1
  if [ "$?" = "0" ]; then
    echo -e "MySQL Already installed.\n"
  else
    echo -e "Installing MySQL..."
    wget https://dev.mysql.com/get/mysql-apt-config_0.8.10-1_all.deb
    sudo dpkg -i mysql-apt-config*
    sudo apt update

    echo Installing MySQL...
    sudo apt-get -y install mysql-server
    
    #echo "Now you can check the status of the mysql server using: sudo service mysql status.\n"
    which mysql
    if [ "$?" = "0" ];then
      echo -e "Creating user: 'rakesh' and granting privilages"
      mysql -u root -p root@123 -e "create user 'rakesh'@'localhost' identified with mysql_native_password by 'rakesh123';"
      mysql -u root -p root@123 -e "grant all privileges on * . * to 'rakesh'@'localhost';"
      if [ "$?" != "0" ]; then
        echo -e "Error while creating user.\nPlease login to root on nother terminal and run following commands in it:\n"
        echo "create user 'rakesh'@'localhost' identified with mysql_native_password by 'rakesh123';"
        echo "grant all privileges on * . * to 'rakesh'@'localhost';"
        echo "After above commands you can run the sysbench MySQL benchmark.\n"
        exit
      fi
      # mysql -u root -p root@123 -e "grant all privileges on * . * to 'rakesh'@'localhost';"
    fi

    #sudo systemctl status mysql
  fi
}

function install_sysbench()
{
  apt -y install make automake libtool pkg-config libaio-dev
  # For MySQL support
  apt -y install libmysqlclient-dev libssl-dev
  # For PostgreSQL support
  apt -y install libpq-dev
  
  echo "Downloading source..."
  git clone --recursive https://github.com/akopytov/sysbench.git
  
  echo "Building sysbench"
  cd sysbench
  ./autogen.sh
  # Add --with-pgsql to build with PostgreSQL support
  ./configure
  make -j8
  sudo make install
}

function new_sysbench_quick_install()
{
  which sysbench > /dev/null 2>&1
  if [ "$?" = "0" ]; then
    echo -e "\nSysbench Already installed.\n`sysbench --version`"
  else
    echo -e "Installing Sysbench 1.0...\n"
    sudo apt-get install curl -y
    curl -s https://packagecloud.io/install/repositories/akopytov/sysbench/script.deb.sh | sudo bash
    sudo apt-get -y install sysbench
  fi
}

# This function only works for sysbench version: 0.4.12
function old_sysbench_tests()
{
  echo which test to perform?
  echo -e "1. CPU \n2. MEMORY"
  echo Enter:
  read op
  if [ "$op" = "1" ]; then
    echo Running CPU Workload Benchmark...
    outfile=sysbench_cpu.txt
    init=10000
    
     rm -rf $outfile
    
    st=$SECONDS
    for((mx=$init; mx<=$init*10; mx*=2))
    do
      for((th=2; th<=$ncpus; th*=2))
      do
        echo "\nRunning for PR: $mx TH: $th Configuration"
        echo PR:$mx TH:$th >> $outfile
        sysbench --test=cpu --cpu-max-prime=$mx --num-threads=$th run >> $outfile
      done
    done
    en=$SECONDS
    
    echo Elapsed Time: $((en-st)) >> $outfile
    
  elif [ "$op" = "2" ]; then
    echo Running MEMORY Workload Benchmark...
    outfile=sysbench_memory.txt
    
    init=10000
    
    # Trying to allocate memory more than L3 Cache and stretch to RAM
    memload=250M
    totalmem=100G
    
    rm -rf $outfile
    
    st=$SECONDS
    for((th=2; th<=$ncpus; th*=2))
    do
        echo "Running with MEMLOAD: $memload, TOTALMEM: $totalmem, THREADS: $th"
        echo TH:$th >> $outfile
        # --memory-scope=global/local --memory-oper=read/write/none
        sysbench --test=memory --memory-block-size=$memload --memory-total-size=$totalmem --memory-scope=global --memory-oper=read --num-threads=$th run >> $outfile
    done
    en=$SECONDS
    
    echo Elapsed Time: $((en-st)) >> $outfile
  fi
}

# This function only works for sysbench version: 1.0
function new_sysbench_tests()
{
  echo -e "Do you want to run SYSBNECH-1.0 test?(y/n)"
  read op
  
  if [ "$op" = "y" ];then
    echo which test to perform?
    echo -e "1. CPU \n2. MEMORY \n3. MYSQL"
    echo Enter:
    read op

    if [ "$op" = "1" ]; then

      # SYSBENCH CPU TEST

      echo -e "Running CPU Workload Benchmark..."
      outfile=sysbench_cpu.txt
      init=10000

       rm -rf $outfile

      st=$SECONDS
      for((mx=$init; mx<=$init*10; mx*=2))
      do
        for((th=2; th<=$ncpus; th+=2))
        do
          echo -e "\nRunning for PR: $mx TH: $th Configuration"
          echo PR:$mx TH:$th >> $outfile
          sysbench cpu --cpu-max-prime=$mx --threads=$th run >> $outfile
        done
      done
      en=$SECONDS   
      echo Elapsed Time: $((en-st)) >> $outfile

      # NEXT TRY TASKSET TO PIN PROCESSES/THREADS TO PROCESSORS/LOGICAL PROCESSORS


    elif [ "$op" = "2" ]; then

      # SYSBENCH MEMORY TEST

      echo -e "Running MEMORY Workload Benchmark..."
      outfile=sysbench_memory.txt

      init=10000

      # Trying to allocate memory more than L3 Cache and stretch to RAM
      memload=262144K
      totalmem=100G

      rm -rf $outfile

      st=$SECONDS
      for((th=2; th<=$ncpus; th+=2))
      do
          echo "Running with MEMLOAD: $memload, TOTALMEM: $totalmem, THREADS: $th"
          echo TH:$th >> $outfile
          # --memory-scope=global/local --memory-oper=read/write/none
          sysbench memory --memory-block-size=$memload --memory-total-size=$totalmem --memory-scope=global --memory-oper=read --threads=$th run >> $outfile
      done
      en=$SECONDS

      echo Elapsed Time: $((en-st)) >> $outfile
    elif [ "$op" = "3" ];then

      # SYSBENCH MYSQL TEST

      echo -e "\nRunning SQL Benchmark..."
      outfile=sysbench_mysql.txt
      outfile2=sysbench_mysql_pinned.txt
      
      rm -rf $outfile

      ntables=10

      echo "Preparing Database for benchmarking..."
      echo -e "Creating $ntables ..."
      sysbench oltp_read_write --db-driver=mysql --mysql-user=rakesh --mysql-password=rakesh123 --tables=$ntables --table-size=1000000 --threads=$ntables prepare
      
      # Insert only
      # sysbench /usr/share/sysbench/oltp_insert.lua --db-driver=mysql --mysql-user=root --mysql-password='' --mysql-host=127.0.0.1 --mysql-port=3310 --report-interval=2 --tables=8 --threads=8 --time=60 run

      # Write only
      # sysbench /usr/share/sysbench/oltp_write_only.lua --db-driver=mysql --mysql-user=root --mysql-password='' --mysql-host=127.0.0.1 --mysql-port=3310  --report-interval=2 --tables=8 --threads=8 --time=60 run
      
      steps=$((ncpus/4))
      thpercore=$(echo `lscpu| grep "per core"|cut -f2 -d ':'`)


      # -------------- PROCESSOR PINNING
      export pinlist=""
      st=$SECONDS

      for((th=${steps}; th<=$ncpus; th+=${steps}))
      do
        echo "Running SQL Read only Benchmark with TH: $th using processor pinning..."
        cpusreq=$((th/2))
        for((i=1;i<=$cpusreq;i++))
        do

          if [ "$pinlist" != "" ];then
            export pinlist=${pinlist},`cat /sys/devices/system/cpu/cpu${i}/topology/thread_siblings_list`
          else
            export pinlist=`cat /sys/devices/system/cpu/cpu${i}/topology/thread_siblings_list`
          fi
        done
        echo FOR:$th  PINLIST: $pinlist
        sleep 2
        numactl -C $pinlist --localalloc sysbench oltp_read_only --threads=$th --mysql-user=rakesh --mysql-password=rakesh123 --tables=10 --table-size=1000000 --histogram=on --time=300 run >> $outfile2
      done
      en=$SECONDS
      echo $((en-st)) >> $outfile2
      
      #----------- NO PINNING
      st=$SECONDS
      for((th=$steps; th<=$ncpus; th+=$steps))
      do
        echo "Running SQL Read only Benchmark with TH: $th"
        sysbench oltp_read_only --threads=$th --mysql-user=rakesh --mysql-password=rakesh123 --tables=10 --table-size=1000000 --histogram=on --time=300 run >> $outfile
      done
      en=$SECONDS
      echo $((en-st)) >> $outfile
    else
      echo -e "\nNO TEST SELECTED FOR SYSBENCH.\n"
    fi
  else
    echo -e "SYSBENCH TEST Cancelled by user...\n"
  fi
}

# FOR NGINX TEST 1. Install wrk; 2. install NGINX
# INSTALLING WRK
function install_wrk()
{
  which wrk > /dev/null 2>&1
  if [ "$?" = "0" ]; then
    echo -e "\n'wrk' Already installed.\n`wrk --version`"
  else
    echo -e "\nINSTALLING wrk...\n"
    sudo apt-get install build-essential libssl-dev git -y
    git clone https://github.com/wg/wrk.git wrk
    cd wrk
    make -j`nproc`

    # move the executable to somewhere in your PATH, ex:
    sudo cp wrk /usr/local/bin
  fi
}

# INSTALLING NGINX
function install_nginx()
{
  echo -e "\nINSTALLING NGINX...\n"
  # GET PGP Key for NGINX to eliminate warnings during installation
  wget http://nginx.org/keys/nginx_signing.key
  
  # ADD THE KEY TO APT
  sudo apt-key add nginx_signing.key
  
  # ADD SOURCES LIST TO THE APT SOURCES LIST
  # Code name for Debian 4.9 is stretch
  sudo echo "deb http://nginx.org/packages/mainline/debian/ stretch nginx" >> /etc/apt/sources.list
  sudo echo "deb-src http://nginx.org/packages/mainline/debian/ stretch nginx" >> /etc/apt/sources.list
  
  # UPDATE AND INSTALL NGINX
  sudo apt-get update
  sudo apt-get install nginx
}

function nginx_tests()
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

# INSTALLING TINYMEMBENCH
function install_tinymembench()
{
  echo -e "\nInstalling tinymembench...\n"
  git clone --recursive https://github.com/ssvb/tinymembench.git
  ch tinymembench
  make -j8
  # OR CFLAGS="-O2 -march=atom -mtune=atom"
}

# CACHE TEST TINYMEMBENCH
function tinymembench_tests()
{
  echo -e "Do you want to run stream test?(y/n)"
  read op
  
  if [ "$op" = "y" ];then
    outfile=tinymembench_benchmark.txt
    rm -rf $outfile

    if [ ! -d "tinymembench" ];then
      echo "\n'tinymembech' folder could not found in current working directory... Downloading tinymembench...\n"
      git clone --recursive https://github.com/ssvb/tinymembench
      export tinymem_loc=$PWD/tinymembench
      cd $tinymem_loc
      make -j`nproc`
    else
      cd tinymembench
    fi
    st=$SECONDS
    ./tinymembench >> $outfile
    en=$SECONDS
    echo -e "Elapsed time: $((en-st)) Seconds."
  else
    echo -e "TINYMEMBENCH TEST Cancelled by user...\n"
  fi
}

function stream_tests()
{
  echo -e "Do you want to run stream test?(y/n)"
  read op
  
  if [ "$op" = "y" ];then
    #location=`locate multi-streaam-scaling`
    if [ ! -d "stream-scaling" ];then
      echo -e "\nStream-scaling Folder not found in current working path.\nDownloading stream-scaling....\n"
      git clone --recursive https://github.com/jainmjo/stream-scaling.git
    fi
    cd stream-scaling
    outfile=stream_scaling_benchmark.txt
    iters=4
    testname=stream_scale_${iters}iters
    ./multi-stream-scaling $iters  $testname
    ./multi-averager $testname > stream.txt
    if [ "`which gnuplot`" != "" ];then
      echo -e "Plotting Triad..."
      gnuplot stream-plot
      echo -e "\nNOTE: If you want to plot for 'Scale', please edit find parameter to 'Scale' in stream-graph.py and re-run 'multi-averager'\n"
    fi
  else
    echo -e "STREAM TEST Cancelled by user...\n"
  fi
}

# REDIS TEST
function redis_tests()
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

# SPEC
function speccpu_tests()
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

function specjbb_tests()
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

function install_stressng()
{
  echo -e "Installing stress-ng...\n"
  sudo apt-get install stress-ng
}

function stress_tests()
{
  which stress-ng 2>/dev/null 
  if [ "$?" = "0" ];then
    outfile=stress_ng_power.txt
    #statfile=power_collect.status
    collectstatfile=collect.status

    # Remove Existing power collection status file
    rm -rf $powerstatfile
    
    if [ -f "${PWD}/$outfile" ];then
      echo -e "Old result is existing, moving to: old.${outfile}\n"
    fi
    
    ncpus=`nproc`

    echo -e "Starting POWER COLLECTION...\n"
    start_power_collection &

    for((load=10;load<=100;load+=10))
    do
      echo -e "Running CPU LOAD of: ${load}"
      echo -e "STRESS_NG ${load}% LOAD STARTED at `date`" >> $outfile
      stress-ng -c $ncpus -l $load >> $outfile
      echo -e "STRESS_NG ${load}% LOAD COMPLETED at `date`" >> $outfile

      # Sending 'STOP' command to stop collection
      if [ "${load}" = "100" ] ;then
        echo -e "Done STRESS_NG TESTS.\n"
        echo -e "STOP" > $powerstatfile
      fi
    done
  else
    echo -e "ERROR: stress-ng is not installed.\nPlease install stress-ng and re-run.\n"
  fi
  
}

function install()
{
  # INSTALL MYSQL
  # -------------
  #install_mysql

  # INSTALL SYSBENCH
  # -------------
  #install_sysbench
  # OR
  #new_sysbench_quick_install

  # INSTALL WRK & NGINX; TEST NGINX
  # -------------------------------
  #install_wrk
  #install_nginx
  
  # INSTALL STRESS-NG
  #install_stressng
  
  echo "You want to continue with installation?(y/n)"
  read conf

  if [ "$conf" = "y" ];then

    # APPEND INSTALL FUNCTION NAMES
    test_names=(install_mysql new_sysbench_quick_install install_wrk install_nginx install_stressng )
    total_tests=${#test_names[*]}
    for i in $(seq 0 $(( total_tests - 1)) )
    do
      echo $i ${test_names[$i]}
    done

    echo "Enter the test numbers you want to perform:\n"
    read -a A

    for i in ${A[*]}
    do
      if [ $i -lt $total_tests ];then
        echo "Installing: ${test_names[$i]}"
        ${test_names[$i]}
      else
        echo "  Invalid Test Index.\n"
      fi
    done
  else
      echo "Installation skipped by the user.\n"
  fi
}

function tests()
{
  #speccpu_tests
  #specjbb_tests

  # SYSBENCH TESTS
  #---------------
  # Before running Sysbench test
  # create a user in mysql and use legacy password authentication method with following command
  # Ex: CREATE USER 'username’@‘localhost’ IDENTIFIED WITH mysql_native_password BY ‘password’;

  #new_sysbench_tests

  # NGINX TESTS
  #nginx_tests

  # STREAM TESTS
  #stream_tests

  # REDIS TESTS
  #redis_tests
  
  # STRESS-NG
  #stress_tests
  
  # APPEND TEST NAMES 
  test_names=(speccpu_tests specjbb_tests new_sysbench_tests nginx_tests stream_tests redis_tests stress_tests )
  total_tests=${#test_names[*]}
  for i in $(seq 0 $(( total_tests - 1)) )
  do
    echo $i ${test_names[$i]}      
  done
  
  echo "Enter the test numbers you want to perform:\n"
  read -a A
  
  for i in ${A[*]}
  do
    if [ $i -lt $total_tests ];then
      echo "Performing: ${test_names[$i]}"
      ${test_names[$i]}
    else
      echo "  Invalid Test Index.\n"
    fi
  done  
}

# INSTALL REQUIRED PACKAGES
install

# PERFORM TESTS
tests
