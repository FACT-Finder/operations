#!/bin/bash

VERBOSE=0

while /bin/true ; do
        if [ `ps -eaf | grep "productiveTomcat" | grep -v "grep" -c ` == "0" ] || [ `grep "Max open files" /proc/$(pidof java)/limits |grep -c "4096"` == "1" ]; then
		if (($VERBOSE)); then
			echo `date` started productiveTomcat
		fi
                sudo service tomcat7 restart
        fi
	
	sleep 5	

done
