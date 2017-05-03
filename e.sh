#!/bin/bash

VERSION=1.9-deb

# Welche Bereiche ausfuehren?
THREADDUMP=1
HEAPDUMP=1
KILLTOMCAT=1
ZIP=1
PROCESS_STRING=productiveTomcat


#
# Hilfe Screen
#
if [ "$1" = "-h" ] || [ "$1" = "-?" ] || [ "$1" = "--help" ]; then
	cat <<EOF_USAGE
Usage: e.sh [-h] [PID]
	-h	Show this screen
	PID	Process identifier of tomcat process
	
Version $VERSION
	
Description:
	This script will try to gather environment information and then kill the tomcat process.
	Use this script to quickly get a stalled tomcat up and running while saving information
	for post mortem analysis.
	If a PID was specified the script will use the specified PID. If it was not specified the
	script will check the process list for java processes containing "productiveTomcat". If
	exactly one productiveTomcat process was found the script will proceed. If there are less
	or more productiveTomcats the script will ask the user to specify a PID.
	Thread dump:
	The script will try to guess where the catalina.out file is and will extract the thread
	dump from it. It will print an error if the guessing process fails.
	Heap dump:
	The script will try to find the jmap command (supplied by Sun JDK). It will first try
	to use the JAVA_HOME environment variable if one is set. If there is no such environment
	variable the script will try to get the java path from the tomcat command. It this fails
	too it will just use jmap without explicit path and assume that the PATH environment
	variable is set correctly.
EOF_USAGE
	exit 0
fi


# Datum fuer Dateinamen
DATE=`date +"%F_%H.%M.%S"`
HOSTNAME=`hostname`
THREADDUMP_NAME="threaddump_${HOSTNAME}_$DATE.txt"
HEAPDUMP_NAME="heapdump_${HOSTNAME}_$DATE.hprof"
SYSTEMINFO_NAME="systeminfo_${HOSTNAME}_$DATE.txt"


#
# Tomcat PID finden
#
if [ ! -z "$1" ]; then
	echo "OK: Using specified PID: $1"
	TOMCAT_PID=$1
else
	NUMBER_TOMCATS_FOUND=`ps axo pid,command | grep java | grep $PROCESS_STRING | wc -l`
	if [ ! $NUMBER_TOMCATS_FOUND -eq 1 ]; then
		echo "ERR: $NUMBER_TOMCATS_FOUND $PROCESS_STRING found. Please specify a PID:  ./e.sh PID"
		exit -1
	fi
	TOMCAT_PID=`ps axo pid,command | grep java | grep $PROCESS_STRING | sed 's/ *\([0-9]\+\) .*$/\1/'`

	if [ ! -z "$TOMCAT_PID" ]; then
		echo "OK: Running Tomcat found. PID = $TOMCAT_PID"
	else
		TOMCAT_PID=`ps axo pid,command | grep java | grep $PROCESS_STRING | cut -d " " -f 2`
		if [ ! -z "$TOMCAT_PID" ]; then
			echo "OK: Running Tomcat found. PID = $TOMCAT_PID"
		else
			echo "ERR: No $PROCESS_STRING found. Please specify a PID:  ./e.sh PID"
			exit -1
		fi
	fi
fi

# Catalina Home finden
# 1. Commandozeile des Tomcat holen.
# 2. Den -Dcatalina.home Parameter finden
# 3. Den Teil rechts vom "=" abtrennen
CATALINA_HOME=`ps --pid $TOMCAT_PID --format command= | egrep -o "\-Dcatalina.home=[^ ]+" | cut --delimiter "=" -f 2`
CATALINA_BASE=`ps --pid $TOMCAT_PID --format command= | egrep -o "\-Dcatalina.base=[^ ]+" | cut --delimiter "=" -f 2`

# Systeminfo
#
echo "===== Systeminfo ====="

echo " - uptime"
echo " ====== UPTIME ======" >> $SYSTEMINFO_NAME
uptime >> $SYSTEMINFO_NAME

echo " - top, 3s"
echo " ====== TOP ======" >> $SYSTEMINFO_NAME
top -b -n 3 -c >> $SYSTEMINFO_NAME

echo " - lsof" 
echo "===== lsof =====" >> $SYSTEMINFO_NAME
lsof -bw -p $TOMCAT_PID >> $SYSTEMINFO_NAME

echo " - free"
echo "==== free [MB] ====="  >> $SYSTEMINFO_NAME
free -m >> $SYSTEMINFO_NAME

#
#
# Thread Dump
#
if [ $THREADDUMP -eq 1 ]; then
	echo "===== Thread Dump ====="
	
	TOMCAT_LOGS="$CATALINA_BASE/logs"
		if [ -d "$TOMCAT_LOGS" ]; then
		# tomcat logs verzeichnis gefunden

		CATALINA_LOG="$TOMCAT_LOGS/catalina.out"
		if [ -e "$CATALINA_LOG" ]; then
			# catalina.out gefunden

			echo "OK: catalina.out found here: $CATALINA_LOG"
			echo "OK: Creating Thread Dump $THREADDUMP_NAME"
			kill -QUIT $TOMCAT_PID
			sleep 5
			tail -n 100000 "$CATALINA_LOG" > "$THREADDUMP_NAME"
		else
			echo "ERR: Tomcat logs directory found but there is no 'catalina.out'. This file was checked: $CATALINA_LOG Thread dump will NOT be created."
		fi
	else
		# kein tomcat logs verzeichnis gefunden
		echo "ERR: No tomcat logs directory found. This one was assumed: $TOMCAT_LOGS Thread dump will NOT be created."
	fi
fi

#
# Heap Dump
#
if [ $HEAPDUMP -eq 1 ]; then
	echo "===== Heap Dump ====="

	# Ueber JAVA_HOME
	JMAP1=$JAVA_HOME/bin/jmap

	# Ueber den Tomcat Process
	# erstmal den pfad des java befehls holen
	JMAP2=`ps --pid $TOMCAT_PID --format command= | cut --delimiter " " -f 1`
	# dann java durch jmap ersetzen
	JMAP2=`echo "$JMAP2" | awk '{sub(/bin\/java/,"bin/jmap");print}'`
	
	# Auf korrekte PATH einstellungen verlassen
	JMAP3=jmap

	# jmap finden
	if [ -e $JMAP1 ]; then
		JMAP="$JMAP1"
	else
		if [ -e $JMAP2 ]; then
			JMAP="$JMAP2"
		else
			echo "WARN: No jmap found. I'll try to use jmap without specifying an explicit path. These locations were checked:"
			echo "  $JMAP1";
			echo "  $JMAP2";
			JMAP="$JMAP3"
		fi
	fi
	
	## Versuch 1
	echo "OK: Creating heap dump $HEAPDUMP_NAME"
	JMAP_CMD_LINE="-dump:format=b,file=$HEAPDUMP_NAME $TOMCAT_PID"
	if ! "$JMAP" $JMAP_CMD_LINE ; then
		echo "ERR: Creating heap dump failed. Command used: $JMAP $JMAP_CMD_LINE"

		## Versuch 2
		echo "OK: Trying a workaround for vms <= 6u24."
		# einen hard link zur socket datei der vm erstellen, dort wo jmap danach sucht
		JMAP_WORKAROUND_LINK=/tmp/.java_pid${TOMCAT_PID}
		ln ${CATALINA_HOME}/temp/.java_pid${TOMCAT_PID} $JMAP_WORKAROUND_LINK
		if ! "$JMAP" $JMAP_CMD_LINE ; then

			## Versuch 3
			echo "OK: Trying to force the dump. This may take 5-10min!"
			if ! "$JMAP" -F $JMAP_CMD_LINE ; then
				echo "ERR: Creating heap dump with force switch failed too."
			fi
		fi

		# Link wieder entfernen
		rm $JMAP_WORKAROUND_LINK
	else
		chmod g+r $HEAPDUMP_NAME
	fi
fi


#
# Tomcat neustarten
#
if [ $KILLTOMCAT -eq 1 ]; then
	echo "===== Killing Tomcat ====="
	kill -9 $TOMCAT_PID
fi

#
# Die Ausgabe-Dateien zippen
#
if [ $ZIP -eq 1 ]; then
	echo ===== Zipping ======
	if [ -e $THREADDUMP_NAME ]; then
		nice gzip $THREADDUMP_NAME
	fi
	if [ -e $HEAPDUMP_NAME ]; then
		nice gzip $HEAPDUMP_NAME
	fi
	if [ -e $SYSTEMINFO_NAME ]; then
		nice gzip $SYSTEMINFO_NAME
	fi
fi


