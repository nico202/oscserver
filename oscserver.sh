#!/bin/bash
#Start and stop timemachine, with custom options, and running timemachine-to-timeline after it

#Quante ore tengo aperto timemachine dopo l'avvio?
PIPEHOURS=24

#Toggle: start or stop? =1
#NO. STOP & START	=0
TOGGLE=0

SAVETIME=10
COMMANDAFTERSLEEP=0.3

RECDIR=/RECORDINGS/

PORT=4444
echo "OSC: osc.udp://studio:$PORT/"

CHS=8
#Timemachine command:
TIMEMACHINE="timemachine -c $CHS -i"
portconnect()
{
for ((CH=1;CH<=$CHS;CH++)); do
	jack_connect system:capture_$CH TimeMachine:in_$CH
done
}

TEMP=/tmp/osc.log

killall oscdump
oscdump $PORT > $TEMP &
PID=$!

#Be sure to not have it running when we don't want it
function clean()
{
	RUN=0
	killall oscdump
	killall inotifywait
	kill -2 $PID
	rm -f $TEMP
	kill -2 $TIMEPID
	killall timemachine
	kill -9 $$
	exit 0
	killall oscserver
}

trap clean SIGHUP SIGINT SIGTERM

aftersplit(){
	#0. If last was STOP, exit
	[ "$NAME" == "STOP" ] && RUN=0 && clean
	#1. Move to a custom name
	NEWREC=`cat /tmp/timemachineout | tail -9 | grep tm| tail -c 29| sed -s "s|'||g"`
	echo $NEWREC e $NAME
	[ "$NAME" != "Toggle" ] && NAME=$NAME"_$NEWREC" && mv $RECDIR/$NEWREC $RECDIR/$NAME
	[ "$NAME" == "Toggle" ] && NAME=$NEWREC
 
	#2. Timemachine-to-timeline
	( cd $RECDIR && xterm -e timemachine-to-timeline $NAME & )

}
#Comandi di avvio registrazione
starttime(){
	echo "start" > /tmp/command
	echo "Recording STARTed"
	echo 1 > /tmp/timestate
	sleep $COMMANDAFTERSLEEP
}

stoptime(){
	echo "stop" > /tmp/command
	echo "Recording STOPped"
	echo 0 > /tmp/timestate
	sleep $COMMANDAFTERSLEEP
}

toggletime(){
	#STOP AND START
	[ $TOGGLE -eq 0 ] && echo "debug: stop and start" && stoptime && starttime
	#REAL TOGGLE
	echo "debug: toggle record state"
	[ $TOGGLE -eq 1 ] && [ `cat /tmp/timestate` -eq 0 ] && starttime
	[ $TOGGLE -eq 1 ] && [ `cat /tmp/timestate` -eq 1 ] && stoptime
	#command to be done after splitting the recordin (ie. convert)
	aftersplit &
}


boot(){
	echo "Starting timemachine in background"
	PIPETIME=`expr 60 \* 60 \* $PIPEHOURS`
	[ -e /tmp/command ] && echo "debug: timemachine è in esecuzione? Lo uccido" && rm /tmp/command
	killall timemachine
	mkfifo /tmp/command
	#Keep pipe open for $PIPETIME
	sleep $PIPETIME > /tmp/command &
	#Start timemachine in interactive mode
	echo "0" > /tmp/timestate
	cd $RECDIR
	( $TIMEMACHINE < /tmp/command  >> /tmp/timemachineout & ) && TIMEPID=$!
	#Let Timemachine start
	TIMEPID=$!
	sleep 1
	#Se vogliamo la registrazione persistente, avviamo fin da subito!
	[ $TOGGLE -eq 0 ] && starttime
	portconnect
}

quit(){
	echo "stop" > /tmp/command
	sleep $COMMANDAFTERSLEEP
	echo "quit" > /tmp/command
	sleep $COMMANDAFTERSLEEP
	rm /tmp/command
	sleep $SAVETIME
	killall timetoggle
}

#Start timemachine
boot
RUN=1
#Wait for a command
echo "Watch starting"
while [ $RUN ]
do
while inotifywait -qqe modify $TEMP; do 
	tail -1 $TEMP | grep -q Toggle && NAME=`tail -1 $TEMP | awk '{ print $NF }' | sed -s 's|"||g'` && toggletime
done
done

echo "Stop the server"
kill -9 $PID
