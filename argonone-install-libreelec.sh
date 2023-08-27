#!/bin/bash


installdir=`dirname "$0"`
daemondir=/storage/.config/argonone.d
daemonname=argononed

daemonconfigfile=$daemondir/$daemonname.conf
daemonscript=$daemondir/$daemonname.py
daemonfanservice=/storage/.config/system.d/$daemonname.service
shutdownscript=$daemondir/$daemonname-poweroff.py
# Nombre antiguo. Comprobar apariciones:  argononeshutdownscript="/storage/.config/shutdown.sh"
systemshutdownscript=/storage/.config/shutdown.sh
uninstallscript=$installdir/argonone-uninstall.sh


echo Configuring /flash/config.txt

if ! grep -Fq 'Argon ONE' /flash/config.txt; then
    mount -o remount,rw /flash
    cat >>/flash/config.txt <<EOL


# Argon ONE
dtoverlay=gpio-ir,gpio_pin=23
dtparam=i2c=on
enable_uart=1
EOL
    mount -o remount,ro /flash
    echo '  Modified'
else
    echo '  Not modified'
fi


if [ ! -d $daemondir ]; then
    mkdir $daemondir
fi


# Generate config file for fan speed

echo Configuring $daemonconfigfile
if [ ! -f $daemonconfigfile ]; then
    cat >$daemonconfigfile <<EOL
#
# Argon One Fan Configuration
#
# List below the temperature (Celsius) and fan speed (in percent) pairs
# Use the following form:
# min.temperature=speed
#
# Example:
# 55=10
# 60=55
# 65=100
#
# For always on, use:
# 0=100
#
# For always off, use:
# 100=0
#
# Type the following at the command line for changes to take effect:
# systemctl restart $daemonname.service
#
55=10
60=55
65=100
EOL

    chmod 666 $daemonconfigfile
    echo '  Created'
else
    echo '  Not modified'
fi


# Generate script to monitor temperature and shutdown button
#    Shutdown button hardware seems not to work. It only sends signal on double click or makes a forced powerdouwn on long press

echo Writing $daemonscript
cat >$daemonscript <<EOL
#!/usr/bin/python

import sys
sys.path.append('/storage/.kodi/addons/virtual.system-tools/lib')
import smbus
sys.path.append('/storage/.kodi/addons/virtual.rpi-tools/lib')
import RPi.GPIO as GPIO
import os
import time
from threading import Thread



rev = GPIO.RPI_REVISION
if rev == 2 or rev == 3:
    bus = smbus.SMBus(1)
else:
    bus = smbus.SMBus(0)

GPIO.setwarnings(False)
GPIO.setmode(GPIO.BCM)
shutdown_pin=4
GPIO.setup(shutdown_pin, GPIO.IN,  pull_up_down=GPIO.PUD_DOWN)


# Power button of my ArgonONE V2 case only sends a signal at double click, so this original script will never work
# def shutdown_check():
#   while True:
#       pulsetime = 1
#       GPIO.wait_for_edge(shutdown_pin, GPIO.RISING)
#       time.sleep(0.01)
#       while GPIO.input(shutdown_pin) == GPIO.HIGH:
#           time.sleep(0.01)
#           pulsetime += 1
#       if pulsetime >=2 and pulsetime <=3:
#           os.system("reboot")
#       elif pulsetime >=4 and pulsetime <=5:
#           os.system('kodi-send --action="ShutDown()"')
#           #os.system("shutdown now -h")

def shutdown_check():
    GPIO.wait_for_edge(shutdown_pin, GPIO.RISING)
    os.system('kodi-send --action="Notification(Argon ONE, Power down, 5000)"')
    time.sleep(5)
    
    #os.system('kodi-send --action=Reboot')
    os.system('kodi-send --action=Powerdown')


def get_fanspeed(tempval, configlist):
    for curconfig in configlist:
        if tempval >= curconfig[0]:
            return curconfig[1]
    return 0


def load_config(fname):
    defaultconfig = [(65,100), (60,55), (55,10)]
    newconfig = []
    try:
        with open(fname, "r") as fp:
            for line in fp.read().splitlines():
                line = line.split('#', 1)[0]
                tmppair = line.split("=")
                if len(tmppair) != 2:
                    continue

                tempval = 0
                try:
                    tempval = float(tmppair[0])
                except:
                    continue
                if tempval < 0 or tempval > 100:
                    continue

                fanval = 0
                try:
                    fanval = int(float(tmppair[1]))
                except:
                    continue
                if fanval < 0 or fanval > 100:
                    continue
                if fanval < 1:
                    fanval = 0
                elif fanval < 25:
                    fanval = 25

                newconfig.append((tempval,fanval))
    except:
        newconfig = defaultconfig

    if len(newconfig) == 0:
        newconfig = defaultconfig
    newconfig.sort(key=lambda x:x[0], reverse=True)
    return newconfig

def temp_check():
    fanconfig = load_config("$daemonconfigfile")
    address=0x1a
    prevblock=0
    while True:
        temp = os.popen("vcgencmd measure_temp").readline()
        temp = temp.removeprefix("temp=")
        tempval = float(temp.strip().removesuffix("'C"))
        block = get_fanspeed(tempval, fanconfig)
        if block < prevblock:
            time.sleep(10)
        prevblock = block
        try:
            if block > 0:
                bus.write_byte(address,100)
                time.sleep(1)
            bus.write_byte(address,block)
        except IOError:
            pass
        time.sleep(10)


try:
    t1 = Thread(target = shutdown_check)
    t2 = Thread(target = temp_check)
    t1.start()
    t2.start()
except:
    t1.stop()
    t2.stop()
    GPIO.cleanup()
EOL

chmod 755 $daemonscript


# Generate daemon fan service file

echo Writing $daemonfanservice
cat >$daemonfanservice <<EOL
[Unit]
Description=Argon One Fan and Button Service
After=multi-user.target
[Service]
Type=simple
Restart=always
RemainAfterExit=true
ExecStart=/bin/sh -c ". /etc/profile; exec /usr/bin/python $daemonscript"
[Install]
WantedBy=multi-user.target
EOL

chmod 644 $daemonfanservice


# Generate script that runs every shutdown event

echo Writing $shutdownscript
cat >$shutdownscript <<EOL
#!/usr/bin/python

import sys
sys.path.append('/storage/.kodi/addons/virtual.system-tools/lib')
import smbus
sys.path.append('/storage/.kodi/addons/virtual.rpi-tools/lib')
import RPi.GPIO as GPIO


rev = GPIO.RPI_REVISION
if rev == 2 or rev == 3:
    bus = smbus.SMBus(1)
else:
    bus = smbus.SMBus(0)

try:
    bus.write_byte(0x1a,0)      # Stop fan
    bus.write_byte(0x1a,0xFF)   # Wait 13s and then cut down power to Pi
except:
    pass
EOL

chmod 755 $shutdownscript


# Generate or edit system shutdown Script

echo Configuring $systemshutdownscript
# This will try to edit shutdown script looking for a "case" with "halt)" and "poweroff)" options
if [ -f $systemshutdownscript ]; then
    modified=0

    if ! grep -Fq "Argon ONE halt actions" $systemshutdownscript; then
        sed -i "s@\(\s*\)halt)@\1halt)\n\1\1/usr/bin/python $shutdownscript # Argon ONE halt actions@" $systemshutdownscript
        modified=1
    fi
    if ! grep -Fq "Argon ONE poweroff actions" $systemshutdownscript; then
        sed -i "s@\(\s*\)poweroff)@\1poweroff)\n\1\1/usr/bin/python $shutdownscript # Argon ONE poweroff actions@" $systemshutdownscript
        modified=1
    fi

    if [ $modified == 1 ] ; then
        echo '  Modified'
    else
        echo '  Not modified'
    fi

else
    cat >$systemshutdownscript <<EOL
#!/bin/bash

case "\$1" in
  halt)
    /usr/bin/python $shutdownscript # Argon ONE halt actions
    ;;
  poweroff)
    /usr/bin/python $shutdownscript # Argon ONE poweroff actions
    ;;
  reboot)
    #
    ;;
  *)
    #
    ;;
esac
EOL

    chmod 755 $systemshutdownscript
    echo '  Created'

fi


# Generate uninstall Script

echo Configuring $uninstallscript
cat >$uninstallscript <<EOL
#!/bin/bash
echo "-------------------------"
echo "Argon One Uninstall Tool"
echo "-------------------------"
echo -n "Press Y to continue:"
read -n 1 confirm
echo
if [[ "\$confirm" != "y" && "\$confirm" != "Y" ]]; then
    echo "Cancelled"
    exit
fi

if ( systemctl list-units --full -all | grep -Fq $daemonname.service ) ; then
    systemctl stop $daemonname
    systemctl disable $daemonname
fi

[[ -f $daemonscript         ]] && rm $daemonscript
[[ -f $daemonfanservice     ]] && rm $daemonfanservice
[[ -f $shutdownscript       ]] && rm $shutdownscript
#[[ -f $systemshutdownscript ]] && rm $systemshutdownscript
[[ -f $uninstallscript      ]] && rm $uninstallscript

 sed -i '/Argon ONE/d' $systemshutdownscript

echo "Removed Argon ONE service and files"
EOL

chmod 755 $uninstallscript



systemctl daemon-reload
systemctl enable $daemonname
systemctl start $daemonname
 
echo "***************************"
echo "Argon One install completed"
echo "     Francisco Guindos     "
echo "    francisco@guindos.es   "
echo "***************************"

if [ ! -d /storage/.kodi/addons/virtual.system-tools/lib ] || [ ! -d /storage/.kodi/addons/virtual.rpi-tools/lib ]; then
    echo
    echo Argon ONE fan and power button service is installed but you have to install two addons for it to work:
    echo '   LibreELEC repository > Pogram addons > System tools'
    echo '   LibreELEC repository > Pogram addons > Raspberry Pi Tools'
fi

