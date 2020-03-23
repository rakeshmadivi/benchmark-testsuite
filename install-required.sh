#!/bin/bash
# ---------- Installing required Softwares --------------

head_dir=$PWD

nginxloc=/usr/sbin
export PATH=${nginx}:$PATH

checkbinary(){
	[ $# -ne 1 ] && echo "Error: $0 doesn't have enough arguments to proceed." && exit
	which $1 > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		echo 0 && return 0
	else
		echo 1 && return 1
	fi
}

# Display some message
disp_msg(){echo -e "\t$@"}

# To return success case
success(){
	echo 0
	return 0
}

# To return failed case
fail(){
	echo 1
	return 1
}

# @arg1 => index/id of test according to LONG,inst_fun,test_fun,directories
ifinstalled(){
	[ $# -ne 1 ] && echo Error: $0 is being called incorrectly. && exit;
	testid=$1
	case $testid in
		# 0 - SPECCPU
		0)
			checkbinary runcpu
			if [ $? -eq 0 ]
			then
				disp_msg "${longopts[$testid]} - Found."
				return 0
			else
				inst_dir=${HOME}/speccpu_inst
				disp_msg "Checking for $inst_dir"
				if [ ! -d $inst_dir ]
				then
					disp_msg "$inst_dir: No such directory."
					return 1
				else
					[ "$SPEC" = "" ] && disp_msg "Sourcing '$inst_dir/shrc'" && cd $inst_dir && source shrc && disp_msg "Done."
					return 0
				fi

			fi
			;;

		# 1 - SPECJBB
		1)
			checkbinary java
			return $?	
			;;

		# 2 - STREAM
		2)
			binsin=${directories}/stream-scaling
			exe1=${binsin}/stream
			exe2=${binsin}/stream-scaling
			exe3=${binsin}/multi-stream-scaling
			exe4=${binsin}/multi-averager
			[ -f $binsin ] && [ -x $exe1 ] && [ -x $exe2 ] && [ -x $exe3 ] && [ -x $exe4 ] && disp_msg "${longopts[$testid]}: Found"
			return $?
			;;

		# 3 - SSSPTS
		3)
			dir=${directories[$testid]}/
			f1=${dir}/start-tests.sh
			f2=${dir}/ssspts-main.sh
			f3=${dir}/ssspts-common.sh
			f4=${dir}/ssspts-iops.sh
			f5=${dir}/ssspts-tp.sh
			f6=${dir}/ssspts-latency.sh

			# Check if all files are present
			[ -d $dir ] && [ -x $f1 ] && [ -x $f2 ] && [ -x $f3 ] && [ -x $f4 ] && [ -x $f5 ] && [ -x $f6 ] && disp_msg "${longopts[$testid]}: Found files for this test"
			return $?
			;;

		# 4 - IPERF
		4)
			checkbinary iperf
			return $?
			;;

		# 5 - SYSBENCH
		5)
			checkbinary sysbench
			returned=$?
			if [ $returned -eq 0 ]
			then
				sb_version=$(sysbench --version|cut -f2 -d' ')
				if [ ${sb_version%%.*} -eq 1 ]
				then
					echo $(sysbench --version) is already installed.
				else
					echo $(sysbench --version) is already installed. Please use newer Sysbench 1.0 version.
				fi
			else
				return $returned
			fi
			;;

		# 6 - REDIS
		6)
			checkbinary redis-benchmark
			return $?
			;;

		# 7 - NGINX
		7)
			export PATH=/usr/sbin:$PATH
			checkbinary nginx 
			return $?
			;;
	esac
}

#SPECCPU-2017
install_speccpu(){
	echo Installing SPECCPU
	if [ $USER != "root" ]
	then
		echo Need to be ROOT/sudo to install SPECCPU
		exit
	else
		# Following commands to be executed by ROOT
		ISO=cpu2017-1_0_5.iso
		mnt_dir=/mnt/speccpu_mnt
		install_dir=$HOME/specccpu_inst

		[ ! -f $ISO ] && echo Error: Installation file not available. && fail && return $?
		[ -d $install_dir ] && echo NOTE: Installation destination already exists. SPECCPU might have already installed. && success && return $?

		# Create mount directory and mount SPECCPU ISO
		mkdir -p $mnt_dir && mount $ISO $mnt_dir

		# Go to mount directory and start installation
		cd $mnt_dir && $(yes|./install.sh -d $install_dir) && echo Installed SPECCPU Successfully.
		echo Source shrc/cshrc in $install_dir to set up SPECPCPU Environment.

	fi
}

install_specjbb(){
	jbbfile=SPECjbb2015-v1_01.iso #SPECjbb2015.tar.gz
	install_dir=$HOME/specjbb
	which java
	if [ $? -ne 0 ]
	then
		echo JAVA Not Found. Installing JAVA
		sudo apt-get install default-jdk && echo DONE.
		
		# set JAVA_HOME variable
		jp=update-alternatives --config java| grep java-8 | awk '{print $NF}'
		echo export JAVA_HOME=${jp%/bin/java} >> $HOME/.bashrc && echo Setting JAVA_HOME Done.
	else
		jbbextension=${jbbfile#*.}
		if [ $jbbextension = "iso" ]
		then
			echo Using $jbbfile for mounting
			[ $USER != "root" ] && echo Must be ROOT/sudo user to perform this operation && return 1
			sudo mkdir -p $install_dir
			sudo mount $jbbfile $install_dir

		elif [ $jbbextension = "tar.gz" ]
		then
			echo Using $jbbfile
			check=${jbbfile%.tar.gz}
			[ -d  $check ] && echo NOTE: Seems like SPECJBB is already installed. Folder \'$check\' already exists. && return 1
			tar -xvf $jbbfile && echo -e "Please make required configuration settings in ${install_dir}/config/*.raw,\nNUMA settings in ${install_dir}/*.sh\nand\nStart execution using ${install_dir}/*.sh"
		elif [ $jbbextension = "zip" ]
		then
			echo Using $jbbfile
			check=${jbbfile%.tar.gz}
			[ -d  $check ] && echo NOTE: Seems like SPECJBB is already installed. Folder \'$check\' already exists. && return 1
			unzip $jbbfile
		fi
	fi
}

install_mysql(){
	echo -e "Installing MySQL..."
	wget https://dev.mysql.com/get/mysql-apt-config_0.8.10-1_all.deb
	sudo dpkg -i mysql-apt-config*
	sudo apt update

	sudo apt-get -y install mysql-server

	#echo "Now you can check the status of the mysql server using: sudo service mysql status.\n"
	which mysql
	if [ "$?" = "0" ];then
		echo -e "Creating user: 'rakesh' and granting privilages"
		mysql -u root -p root@123 -e "create user 'rakesh'@'localhost' identified with mysql_native_password by 'rakesh123';"
		mysql -u root -p root@123 -e "grant all privileges on * . * to 'rakesh'@'localhost';"
		if [ "$?" != "0" ]; then
			echo -e "Error while creating user."
			echo "Please login to root on nother terminal and run following commands in it:"
			echo "create user 'rakesh'@'localhost' identified with mysql_native_password by 'rakesh123';"
			echo "grant all privileges on * . * to 'rakesh'@'localhost';"
			echo "After above commands you can run the sysbench MySQL benchmark.\n"
			exit
		fi
		# mysql -u root -p root@123 -e "grant all privileges on * . * to 'rakesh'@'localhost';"
	fi

	#sudo systemctl status mysql
}

# SYSBENCH
install_sysbench(){
	# Install MySQL Database
	install_mysql

	msg="Installing Sysbench 1.0..."
	echo $msg
	which curl >/dev/null 2>&1 && [ $? -ne 0 ] && sudo apt-get install curl -y
	curl -s https://packagecloud.io/install/repositories/akopytov/sysbench/script.deb.sh | sudo bash
	sudo apt-get -y install sysbench && echo $msg DONE.
}

# STREAM
install_stream(){
	
	binary=multi-strem-scaling
	stream_dir=$head_dir/stream/stream-scaling
	git clone --recursive https://github.com/rakeshmadivi/stream-scaling && echo "NOTE: If already existing binaries are not working, it is required to recompile the source."
}

install_iperf(){
	binary=iperf3
	msg="Installing $binary ..."

	echo $msg
	sudo apt-get install iperf3 -y && echo $msg DONE.
}

# STRESS-NG
install_stressng(){
	binary=stress-ng
	msg="Installing $binary ..."
	echo $msg && sudo apt-get install $binary -y 
	echo $msg DONE.
}

# REDIS
install_redisserver(){
	binary=redis-server
	msg="Installing $binary ..."
	echo $msg && sudo apt-get install $binary -y && echo DONE. && echo NOTE: Check Redis server configuration if it is properly configured.
}

# INSTALLING NGINX
install_nginx()
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
	sudo apt-get install nginx -y
}

install_ipmi(){
	checkbinary ipmitool
	[ $? -ne 0 ] && sudo apt-get install ipmitool -y
}
