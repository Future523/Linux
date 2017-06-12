#!/bin/sh

# Tomcat service manager
# History: 20131230 initialized

#Setting
#AlarmId=118116

#Export PATH
PATH=/sbin:/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/bin:/bin:$PATH
export PATH
checkEnv=`env|grep MACHTYPE|wc -l`
if [ "$checkEnv" -lt 1 ]; then
    . /etc/profile
fi

MAX_SHUTDOWN_TIME=10

curBasePath=`dirname $0`

if [ $# -ne 2 ]
then
    echo "Usage: service.sh start/stop/restart/show/status/create/check/monitor/cleanlog appName"
    exit 1
fi

TMPNAME=$2
APPNAME=`echo $TMPNAME|sed 's/\///g'`

if [ "create" = "$1" ]
then
    if [ -d $curBasePath/$APPNAME ]
    then
        echo "Can't create application, already exists!"
        exit 1
    fi
else
    if [ ! -d $curBasePath/$APPNAME ]
    then
        echo "Can't find the application, appName=$APPNAME"
        exit 1
    fi
fi

if [ "default" = "$APPNAME" ]
then
    echo "Can't operate [default] application!"
    exit 1
fi

#pid
APP_PID=0
function getAppPid {
    local pid=0
    APP_PID=0
    pid=`/bin/ps -ef|/bin/grep "jweb/$APPNAME/bin/bootstrap.jar"|/bin/grep -v "/bin/grep"|/bin/awk '{print $2}'|head -n 1`
    if [ -z "$pid" ]; then
        return 1
    fi
    isRunning=`ps -p $pid --no-header -o comm|grep "java"|wc -l`
    if [ "$isRunning" -gt 0  ]; then
        APP_PID=$pid
        return 0
    else
        return 1
    fi
}

function startService {
    getAppPid
    if [ "$APP_PID" -gt 0 ]; then
        echo "Error:$APPNAME is running." 
        rm -f $curBasePath/$APPNAME/down.txt
        return 1
    else
        $curBasePath/$APPNAME/bin/startup.sh
        sleep 2
        rm -f $curBasePath/$APPNAME/down.txt
        return 0
    fi
}

function stopService {
    touch $curBasePath/$APPNAME/down.txt
    getAppPid
    if [ "$APP_PID" -gt 0 ]; then
        #tmpChkSum=`md5sum $curBasePath/$APPNAME/bin/bootstrap.jar|awk '{print $1}'`
        #if [ "$tmpChkSum" = "4ef17e8955ffd547a1bdbca96e7cef01" ]; then 
            $curBasePath/$APPNAME/bin/shutdown.sh
        #else 
        #    $curBasePath/$APPNAME/bin/shutdown.sh $MAX_SHUTDOWN_TIME -force
        #fi
    else
        echo "[$APPNAME] is not running."
        return 1;
    fi

    for ((i=0; i<MAX_SHUTDOWN_TIME; i++)); do
        getAppPid
        if [ "$APP_PID" -eq 0 ]; then
             return 0
        fi
        sleep 1
    done

    getAppPid
    if [ "$APP_PID" -gt 0 ]; then
        echo "Tomcat don't shutdown within $MAX_SHUTDOWN_TIME seconds, sending SIGKILL..."
        kill -9 $APP_PID
    fi
    return 0
}

case "$1" in
  create)
    #
    # Create New Tomcat
    #
    if [ ! -d $curBasePath/default ]
    then
        echo "Can't find the [default] application!"
        exit 1
    fi

    owner=""
    while [ -z "$owner" ]
    do
        echo -n "Please input the owner of this application:"
        read -e owner
    done

    cp -R /data/jweblog/default /data/jweblog/$APPNAME
    cp -R $curBasePath/default $curBasePath/$APPNAME
    ln -s /data/jweblog/$APPNAME $curBasePath/$APPNAME/logs

    if [ $? = 0 ]
    then
        echo "New application is created sucessfully!"
        echo "Please change default settings!"
    else
        echo "Failed to create new application!"
        echo "Please check your permission!"
    fi

    sed -i "s/\/data\/jweblog\/default/\/data\/jweblog\/$APPNAME/" $curBasePath/$APPNAME/setting.sh

    echo "$owner" >> $curBasePath/$APPNAME/owner.txt

    exit $?
    ;;

  upgrade)
    
	echo "============================"
	echo "Upgrade $APPNAME"
	echo "============================"
	echo "1. Checking..."
	tmpChk1=`md5sum $curBasePath/default/bin/catalina.sh|awk '{print $1}'`
	tmpChk2=`md5sum $curBasePath/$APPNAME/bin/catalina.sh|awk '{print $1}'`
	if [ "$tmpChk1" = "$tmpChk2" ]; then
		echo "$APPNAME is up to date."
		exit 0
	fi
	
	echo -n "Upgrade process will restart this application, do you want to continue(y/N):"
	read -e question
	if [ "$question" != "y" -a  "$question" != "Y" ]; then
	    exit 0
	fi

	getAppPid
	if [ "$APP_PID" -gt 0 ]; then
	    echo "Shutdowning..."
	    stopService
	fi
	
	curDay=`date +%Y%m%d`
	echo "2. Backuping..."
	mkdir -p $curBasePath/$APPNAME/backup/$curDay
	cp -pr $curBasePath/$APPNAME/bin $curBasePath/$APPNAME/backup/$curDay/
	cp -pr $curBasePath/$APPNAME/lib $curBasePath/$APPNAME/backup/$curDay/
	cp -pr $curBasePath/$APPNAME/conf $curBasePath/$APPNAME/backup/$curDay/
	
	echo "3. Upgrading..."
	rm -f $curBasePath/$APPNAME/lib/*
	cp -pr $curBasePath/default/lib $curBasePath/$APPNAME/
	cp -pr $curBasePath/default/bin $curBasePath/$APPNAME/
	cp -pr $curBasePath/default/conf $curBasePath/$APPNAME/
	
	cp -pr $curBasePath/$APPNAME/backup/$curDay/conf/Catalina $curBasePath/$APPNAME/conf/
	cp -f $curBasePath/$APPNAME/backup/$curDay/conf/catalina.properties $curBasePath/$APPNAME/conf/
	cp -f $curBasePath/$APPNAME/backup/$curDay/conf/server.xml $curBasePath/$APPNAME/conf/
	
	cp -f $curBasePath/$APPNAME/backup/$curDay/bin/paipaiso.sh $curBasePath/$APPNAME/bin/
	cp -f $curBasePath/$APPNAME/backup/$curDay/bin/paipaichkjar.sh $curBasePath/$APPNAME/bin/
	cp -f $curBasePath/$APPNAME/backup/$curDay/bin/setenv.sh $curBasePath/$APPNAME/bin/

	if [ "$APP_PID" -gt 0 ]; then
	    echo "Startup service..."
	    startService
	fi
	
	echo "4. Done"
	
    echo "Please check your application."
    
    ;;	
	
  cleanlog)
    
    find /data/jweblog/$APPNAME/ -type f -mtime +15 -exec rm -f {} \;
    exit $?
    ;;

  start)
    #
    # Start Tomcat
    #
    startService
    exit $?
    ;;

  check)
    #
    # Check service and report
    #

    if [ -r "$curBasePath/$APPNAME/monitorsetting.sh" ]; then
        . "$curBasePath/$APPNAME/monitorsetting.sh"
    fi
    getAppPid
    if [ "$APP_PID" -lt 1 ]; then
        startService
    fi
    ;;

  status|show)
    #
    # Status
    #
    getAppPid
    if [ "$APP_PID" -gt 0 ]; then
        ps -f -p $APP_PID|grep "java"
    else
        echo "[$APPNAME] is not running."
    fi
    ;;

  stop)
    #
    # Stop Tomcat
    #
    stopService
    exit $?
    ;;

  restart)
    #
    # Restart Tomcat
    #
    stopService
    sleep 1 
    startService

    exit $?
    ;;

  getFD|getfd|getFd)
    #
    # get Tomcat FD
    #
    getAppPid
    if [ "$APP_PID" -gt 0 ]; then
        lsof -a -n -P -p $APP_PID|/usr/bin/wc -l
    else
        echo "0"
    fi

    exit $?
    ;;

  getPid|getPID)
    #
    # get PID 
    #   
    getAppPid
    if [ "$APP_PID" -gt 0 ]; then
        echo $APP_PID 
    else
        echo "0"
    fi
    
    exit $?
    ;;

  monitor)
    #
    # monitor 
    # 
    getAppPid
    if [ "$APP_PID" -lt 1 ]; then
        exit 1
    fi

    if [ ! -x "/usr/local/agenttools/agent/agentRepNum" ]; then
        exit 1
    fi

    if [ ! -r "$curBasePath/$APPNAME/monitorsetting.sh" ]; then
        exit 1
    fi
    . "$curBasePath/$APPNAME/monitorsetting.sh"
    if [ "$EnableMonitor" -ne 1 ]; then
        exit 1
    fi
    StatFD=`lsof -a -n -P -p $APP_PID|/usr/bin/wc -l`
    StatTN=`jstack $APP_PID|grep "java.lang.Thread.State:"|wc -l`
    StatVM=`ps --no-header -o 'vsz' -p $APP_PID`
    StatRM=`ps --no-header -o 'rsz' -p $APP_PID`
    tmpStatFile=/tmp/tomcat_tmp_$APPNAME.stat
    jmap -heap $APP_PID > "$tmpStatFile"
    StatPG=`cat $tmpStatFile|grep -A4 "PS Perm Generation"|tail -n1|awk -F'.' '{print $1}'`
    StatTG=`cat $tmpStatFile|grep -A4 "PS Old Generation"|tail -n1|awk -F'.' '{print $1}'`
    StatYG=`cat $tmpStatFile|grep -A4 "Eden Space"|tail -n1|awk -F'.' '{print $1}'`

    /usr/local/agenttools/agent/agentRepNum $MonitorTNId $StatTN
    /usr/local/agenttools/agent/agentRepNum $MonitorFDId $StatFD
    /usr/local/agenttools/agent/agentRepNum $MonitorVMId $StatVM
    /usr/local/agenttools/agent/agentRepNum $MonitorRMId $StatRM
    /usr/local/agenttools/agent/agentRepNum $MonitorPGId $StatPG
    /usr/local/agenttools/agent/agentRepNum $MonitorTGId $StatTG
    /usr/local/agenttools/agent/agentRepNum $MonitorYGId $StatYG

    exit $?
    ;;

  *)
    echo "Usage: service.sh start/stop/restart/show/status/create/check/monitor/cleanlog appName"
    exit 1
    ;;
esac
