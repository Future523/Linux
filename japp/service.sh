#!/bin/sh

# Java application service manager

#Export PATH
PATH=/sbin:/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/bin:/bin:$PATH
export PATH
checkEnv=`env|grep MACHTYPE|wc -l`
if [ "$checkEnv" -lt 1 ]; then
    . /etc/profile
fi

curBasePath=`dirname $0`

if [ $# -ne 2 ]
then
    echo "Usage: service.sh start/stop/restart/show/status/create/check/monitor/cleanlog appName"
    exit 1
fi

APPNAME=$2

if [ "create" = "$1" ]
then
    if [ -d $curBasePath/$APPNAME ]
    then
        echo "Can't create this application, It already exists!"
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

APP_PID=0
function getAppPid {
    local pid=0
    APP_PID=0
    if [ -f "$curBasePath/$APPNAME/run/app.pid" ]; then
        pid=`cat $curBasePath/$APPNAME/run/app.pid|head -n 1|awk '{print $1}'`
    else
        return 1
    fi
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

case "$1" in
  create)
    #
    # Create New Application 
    #
    if [ ! -d $curBasePath/default ]
    then
        echo "Can't find the default application!"
        exit 1
    fi

    owner=""
    while [ -z "$owner" ]
    do
        echo -n "为便于跟踪,请输入此应用的维护人员:"
        read -e owner
    done

    cp -R /data/japplog/default /data/japplog/$APPNAME
    cp -R $curBasePath/default $curBasePath/$APPNAME
    ln -s /data/japplog/$APPNAME $curBasePath/$APPNAME/logs

    if [ $? = 0 ]
    then
        echo "New application is created sucessfully!"
        echo "Please change default setting!"
    else
        echo "Fail to create new application!"
        echo "Please check your permission!"
    fi

    sed -i "s/\/data\/japplog\/default/\/data\/japplog\/$APPNAME/" $curBasePath/$APPNAME/setting.sh

    echo "$owner" >> $curBasePath/$APPNAME/owner.txt

    exit $?
    ;;


  cleanlog)
    
    find /data/japplog/$APPNAME/ -type f -mtime +15 -exec rm -f {} \;
    exit $?
    ;;


  start)
    #
    # Start Application 
    #
    # Can not start app by root 
    getAppPid

    if [ `id -u` -eq "0" ];then
        echo "ERROR! Can not start $APPNAME Application by root "
	exit 0
    fi
    if [ "$APP_PID" -gt "1" ]; then
        echo "Application is running, can't start it again."
        exit 0
    fi
    $curBasePath/$APPNAME/bin/startup.sh
    exit $?
    ;;

  check)
    #
    # Check service and report
    #
    getAppPid

    if [ -r "$curBasePath/$APPNAME/monitorsetting.sh" ]; then
        . "$curBasePath/$APPNAME/monitorsetting.sh"
    fi
    RUN_PID=`/bin/ps -ef|/bin/grep "JAPP_FLAG=JAPP"|/bin/grep "$curBasePath/$APPNAME/lib"|/bin/grep -v "/bin/grep"|/bin/awk '{print $2}'`
    if [ -z "$RUN_PID" ];then
        RUN_PID=0
    fi
    if [ "$APP_PID" != "$RUN_PID" ];then
        kill -9 $RUN_PID
        rm -f $curBasePath/$APPNAME/run/app.pid
        sleep 2
        $curBasePath/$APPNAME/bin/startup.sh
        if [ -x "/usr/local/agenttools/agent/agentRepStr" ]; then
           echo `date +'%H:%M:%S'` >>$curBasePath/$APPNAME/run/monitor.log_`date +'%Y-%m-%d'`
           /usr/local/agenttools/agent/agentRepStr $AlarmId "[Japp][$APPNAME] Pid File Error!" >>$curBasePath/$APPNAME/run/monitor.log_`date +'%Y-%m-%d'`
           echo "============================="  >>$curBasePath/$APPNAME/run/monitor.log_`date +'%Y-%m-%d'`
        fi
	exit 0
    fi
    if [ "$APP_PID" -lt "1" ]; then
        $curBasePath/$APPNAME/bin/startup.sh
        if [ -x "/usr/local/agenttools/agent/agentRepStr" ]; then
           echo `date +'%H:%M:%S'`  >>$curBasePath/$APPNAME/run/monitor.log_`date +'%Y-%m-%d'`
           /usr/local/agenttools/agent/agentRepStr $AlarmId "[Japp][$APPNAME]异常重启" >>$curBasePath/$APPNAME/run/monitor.log_`date +'%Y-%m-%d'`
           echo "============================="  >>$curBasePath/$APPNAME/run/monitor.log_`date +'%Y-%m-%d'`
        fi
    fi
    find $curBasePath/$APPNAME/run/ -name "monitor.log*" -mtime +15 -exec rm -f {} \;
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
    # Stop Application 
    #
    $curBasePath/$APPNAME/bin/shutdown.sh
    exit $?
    ;;

  restart)
    #
    # Restart Application 
    #
    $curBasePath/$APPNAME/bin/shutdown.sh
    sleep 2 
    $curBasePath/$APPNAME/bin/startup.sh
    exit $?
    ;;

  getFD|getfd|getFd)
    #
    # get Application FD
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
    tmpStatFile=/tmp/japp_tmp_$APPNAME.stat
    jmap -heap $APP_PID > "$tmpStatFile"
    StatPG=`cat $tmpStatFile|grep -A4 "PS Perm Generation"|tail -n1|awk -F'.' '{print $1}'`
    StatTG=`cat $tmpStatFile|grep -A4 "PS Old Generation"|tail -n1|awk -F'.' '{print $1}'`
    StatYG=`cat $tmpStatFile|grep -A4 "Eden Space"|tail -n1|awk -F'.' '{print $1}'`
    
    #/usr/local/agenttools/agent/agentRepNum $MonitorTNId $StatTN
    #/usr/local/agenttools/agent/agentRepNum $MonitorFDId $StatFD
    #/usr/local/agenttools/agent/agentRepNum $MonitorVMId $StatVM
    #/usr/local/agenttools/agent/agentRepNum $MonitorRMId $StatRM
    #/usr/local/agenttools/agent/agentRepNum $MonitorPGId $StatPG
    #/usr/local/agenttools/agent/agentRepNum $MonitorTGId $StatTG
    #/usr/local/agenttools/agent/agentRepNum $MonitorYGId $StatYG
    
    exit $?
    ;;

  *)
    echo "Usage: service.sh start/stop/restart/show/status/create/check/monitor/cleanlog appName"
    exit 1
    ;;
esac
