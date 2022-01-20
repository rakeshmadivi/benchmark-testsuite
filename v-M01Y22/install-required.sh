#!/bin/bash
# ---------- Installing required Softwares --------------

head_dir=$PWD

nginxloc=/usr/sbin
export PATH=${nginxloc}:$PATH

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
disp_msg(){
	echo -e "\t$@"
}

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
	stream_root=$head_dir/stream_modified
	git clone --recursive https://github.com/rakeshmadivi/stream-scaling $stream_root && echo "NOTE: If already existing binaries are not working, it is required to recompile the source."
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

install_ycsb(){

	ycsb_version=go-ycsb
	if [ "$ycsb_version" == "go-ycsb" ]
	then
		git clone https://github.com/pingcap/go-ycsb.git
		pushd go-ycsb
		make -j$(nproc)
		popd
	else
		curl -O --location https://github.com/brianfrankcooper/YCSB/releases/download/0.17.0/ycsb-0.17.0.tar.gz
		tar xfvz ycsb-0.17.0.tar.gz && echo "[ $(app_get_fname ${BASH_SOURCE}) ] YCSB Home Directory: $PWD"
	fi
}
