#/bin/bash

export PATH="/bin:/usr/bin";
echo `date` cron gestartet
echo `ps ux | grep checkserver.sh | grep -v "grep" -c`
if [ `ps ux | grep checkserver.sh | grep -v "grep" -c` == "0" ]; then
        bash ~/checkserver.sh >> ~/checkserver.log 2>&1 &
        echo `date` checkserver.sh neu gestartet.
fi
