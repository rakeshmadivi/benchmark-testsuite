#!/bin/bash
SRC_DIR=""
DST_DIR=""
RUN_DIR=""

parseArgs(){
	sopts=(s: d: r: )
	lopts=(src-dir: dst-dir: run-dir:)

	SHORT=$(echo "$sopts" | xargs -n1 | paste -d, -s)

	OPTS=$(getopt -o )
}

#========= SPECCPU =========
install_SPECCPU(){

}


run_SPECCPU(){
}


#========= SPECJBB =========
install_SPECJBB(){
}


run_SPECJBB(){
}


#========= STREAM =========
install_STREAM(){
}


run_STREAM(){
}


#========= SSSPTS =========
install_SSSPTS(){
}


run_SSSPTS(){
}


#========= SYSBENCH =========
install_SYSBENCH(){
}


run_SYSBENCH(){
}


#========= REDIS =========
install_REDIS(){
}


run_REDIS(){
}


#========= NGINX =========
install_NGINX(){
}


run_NGINX(){
}


