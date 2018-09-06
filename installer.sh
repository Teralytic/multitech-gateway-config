#!/bin/bash
#
# Script to install packages for TTN on MultiTech Linux Conduit
#
# Written by Jac Kersing <j.kersing@the-box.com>
#
# Parts of the script based on tzselect by Paul Eggert.
#

STATUSFILE=/var/config/.installer
TZ=UTC
URL=https://raw.githubusercontent.com/Teralytic/multitech-gateway-config/master/US-global_conf.json

grep setup_complete $STATUSFILE > /dev/null 2> /dev/null
if [ $? -eq 0 ] ; then
	echo "gateway already setup, exiting"
	exit 0
fi

if [ ! -f $STATUSFILE ] ; then
	touch $STATUSFILE
fi

# Output one argument as-is to standard output.
# Safer than 'echo', which can mishandle '\' or leading '-'.
say() {
    printf '%s\n' "$1"
}

# Ask the user to select from the function's arguments,
# and assign the selected argument to the variable 'select_result'.
# Exit on EOF or I/O error.  Use the shell's 'select' builtin if available,
# falling back on a less-nice but portable substitute otherwise.
if
  case $BASH_VERSION in
  ?*) : ;;
  '')
    # '; exit' should be redundant, but Dash doesn't properly fail without it.
    (eval 'set --; select x; do break; done; exit') </dev/null 2>/dev/null
  esac
then
  # Do this inside 'eval', as otherwise the shell might exit when parsing it
  # even though it is never executed.
  eval '
    doselect() {
      select select_result
      do
	case $select_result in
	"") echo >&2 "Please enter a number in range." ;;
	?*) break
	esac
      done || exit
    }

    # Work around a bug in bash 1.14.7 and earlier, where $PS3 is sent to stdout.
    case $BASH_VERSION in
    [01].*)
      case `echo 1 | (select x in x; do break; done) 2>/dev/null` in
      ?*) PS3=
      esac
    esac
  '
else
  doselect() {
    # Field width of the prompt numbers.
    select_width=`expr $# : '.*'`

    select_i=

    while :
    do
      case $select_i in
      '')
	select_i=0
	for select_word
	do
	  select_i=`expr $select_i + 1`
	  printf >&2 "%${select_width}d) %s\\n" $select_i "$select_word"
	done ;;
      *[!0-9]*)
	echo >&2 'Please enter a number in range.' ;;
      *)
	if test 1 -le $select_i && test $select_i -le $#; then
	  shift `expr $select_i - 1`
	  select_result=$1
	  break
	fi
	echo >&2 'Please enter a number in range.'
      esac

      # Prompt and read input.
      printf >&2 %s "${PS3-#? }"
      read select_i || exit
    done
  }
fi

grep secure $STATUSFILE > /dev/null 2> /dev/null
if [ $? -ne 0 ] ; then
	# Start by securing the device
	echo "securing access to the device, enter the same password twice"
	passwd root
	echo "secure" >> $STATUSFILE
fi

grep timezone $STATUSFILE > /dev/null 2> /dev/null
if [ $? -ne 0 ] ; then
	# link choosen timezone, there was some cool tzselect stuff here
	ln -sf /usr/share/zoneinfo/$TZ /etc/localtime
	echo "timezone" >> $STATUSFILE
	echo "time zone set to $TZ"
	echo "this can be changed at /etc/localtime"
fi

# On to the network information
grep network $STATUSFILE > /dev/null 2> /dev/null
if [ $? -ne 0 ] ; then
	echo "network/cellular setup"
	cat << _EOF_ > /var/config/network/interfaces
# /etc/network/interfaces -- configuration file for ifup(8), ifdown(8)

# The loopback interface
auto lo
iface lo inet loopback

# Wired interface
auto eth0
iface eth0 inet dhcp
		post-up ifconfig eth0 mtu 1100
		udhcpc_opts -b -t 10
#iface eth0 inet static
#address 192.168.2.1
#netmask 255.255.255.0
#gateway 192.168.2.254

# Bridge interface with eth0 (comment out eth0 lines above to use bridge)
# iface eth0 inet manual
#
# auto br0
# iface br0 inet static
# bridge_ports eth0
# address 192.168.2.1
# netmask 255.255.255.0

# Wifi client
# NOTE: udev rules will bring up wlan0 automatically if a wifi device is detected
# and the wlan0 interface is defined, therefore an "auto wlan0" line is not needed.
# If "auto wlan0" is also specified, startup conflicts may result.
#iface wlan0 inet dhcp
#wpa-conf /var/config/wpa_supplicant.conf
#wpa-driver nl80211
_EOF_

	mlinux-set-apn hologram
	pppd call gsm
	cat << _EOF_ > /etc/default/ppp
# Check to see if the SIM is registered before using ppp.
# Need this if using a cellular connection.
CHECKREGISTRATION=0
# Note that boot will not complete until
# ppp completes, and the PPPTIMEOUT is the
# maximum wait time for the SIM to register
# for cellular PPP.
PPPTIMEOUT=60
_EOF_

	cat << _EOF_ > /etc/ppp/ppp_on_boot
#!/bin/sh
#
#   Rename this file to ppp_on_boot and pppd will be fired up as
#   soon as the system comes up, connecting to provider.
#
#   If you also make this file executable, and replace the first line
#   with just "#!/bin/sh", the commands below will be executed instead.
#

# The location of the ppp daemon itself (shouldn't need to be changed)
PPPD=/usr/sbin/pppd

# The default provider to connect to
sleep 10s
$PPPD call gsm
_EOF_

	update-rc.d ppp defaults
	echo "testing connectivity to www.thethingsnetwork.org"
	sleep 20s

	# Network should be configured allowing access to remote servers at this point
	wget http://www.thethingsnetwork.org/ --no-check-certificate -O /dev/null -o /dev/null
	if [ $? -ne 0 ] ; then
		echo "error in network settings, cannot access www.thethingsnetwork.org"
		exit 1
	else
		echo "network" >> $STATUSFILE
		echo "network configuration written"
	fi
fi

# Set date and time using ntpdate
grep date $STATUSFILE > /dev/null 2> /dev/null
if [ $? -ne 0 ] ; then
	/etc/init.d/ntpd stop
	ntpdate north-america.pool.ntp.org
	hwclock -u -w
	echo "date" >> $STATUSFILE
fi

if [ ! -d /var/config/lora ] ; then
	mkdir /var/config/lora
fi

# Check MTAC-LORA configuration
grep mtac_check $STATUSFILE > /dev/null 2> /dev/null
if [ $? -ne 0 ] ; then
	lora_id=$(mts-io-sysfs show lora/product-id 2> /dev/null)
	if [ "$lora_id" == "MTAC-LORA-868" ] ; then
		echo "detected 868MHz card, not compatible, exiting"
		exit 1
	fi
	if [ "$lora_id" == "MTAC-LORA-H-868" ] ; then
		echo "detected 868MHz USB card, not compatible, exiting"
		exit 1
	fi
	if [ "$lora_id" == "MTAC-LORA-H-915" ] ; then
		echo "detected 915MHz USB card"
	fi
	if [ "$lora_id" == "MTAC-LORA-915" ] ; then
		echo "detected 915MHz card"
	fi
	echo "mtac_check" >> $STATUSFILE
fi

# Create lora configuration directory and initial files
grep loraconf $STATUSFILE > /dev/null 2> /dev/null
if [ $? -ne 0 ] ; then
	gwid=$(mts-io-sysfs show lora/eui 2> /dev/null | sed 's/://g')
	if [ X"$gwid" == X"" ] ; then
		echo "could not obtain gateway id, LoRa card not found, exiting"
		exit 1
	fi
	cat << _EOF_ > /var/config/lora/local_conf.json
{
/* Settings defined in global_conf will be overwritten by those in local_conf */
    "gateway_conf": {
        /* gateway_ID is based on unique hardware ID, do not edit */
        "gateway_ID": "$gwid"
    }
}
_EOF_
	echo "get up-to-date configuration for packet forwarder"
	wget $URL -O /var/config/lora/global_conf.json
	if [ ! -f /var/config/lora/global_conf.json ] ; then
		echo "download of configuration failed, exiting"
		exit 1
	fi
	echo "loraconf" >> $STATUSFILE
fi

# Enable the MultiTech lora packet forwarder processes
grep enable-mtech $STATUSFILE > /dev/null 2> /dev/null
if [ $? -ne 0 ] ; then
	echo "enable multitech packet forwarder"
	/etc/init.d/lora-network-server stop
	update-rc.d -f lora-network-server remove > /dev/null 2> /dev/null
	update-rc.d lora-packet-forwarder defaults 80 30
	cat << _EOF_ > /etc/default/lora-network-server
# set to "yes" or "no" to control starting on boot
ENABLED="no"
_EOF_
	cat << _EOF_ > /etc/default/lora-packet-forwarder
# set to "yes" or "no" to control starting on boot
ENABLED="yes"
_EOF_
	cat << _EOF_ > /etc/default/gpsd
# set to "yes" or "no" to control starting on boot
ENABLED="no"
_EOF_
	cat << _EOF_ > /etc/default/ntpd
ENABLED="yes"

CONFIGFILE=/etc/ntp.conf

# Require a GPS lock/fix before starting NTP
# This is needed if we are not using NTP servers.
# NTP will not work with the GPS if  the GPS is not
# locked before starting.
# See /etc/default/gpsd for the states required.
GPSD_REQUIRED=0

# Number of seconds between testing for a GPS
# lock prior to calling ntpd.
GPSD_WAIT_TIME=120

# If there is a uBlox GPS present, the time is
# read from the GPS to initialize the system time
# before NTP is started.
SET_SYSTEM_CLOCK=1
_EOF_
	cat << _EOF_ > /etc/ntp.conf
# The driftfile must remain in a place specific to this
# machine - it records the machine specific clock error
# Driftfile must be in a directory owned by ntp
driftfile /var/lib/ntp/ntp.drift

# This is the US timeserver pool.  You should use a pool
# close to your location.
pool us.pool.ntp.org iburst

# This should be a server that is close (in IP terms)
# to the machine.  Add other servers as required.
server time.nist.gov

restrict default kod nomodify notrap nopeer noquery
restrict -6 default kod nomodify notrap nopeer noquery
restrict 127.0.0.1 mask 255.255.255.0
restrict -6 ::1

# GPS Serial data reference (NTP0)
# This sets the GPS 50 milliseconds slower than the PPS.
server 127.127.28.0 true
fudge 127.127.28.0 time1 0.050 refid GPS

# GPS PPS reference (NTP2)
server 127.127.28.2 prefer true
fudge 127.127.28.2 time1 0.000 refid PPS

# Using local hardware clock as fallback
# Disable this when using ntpd -q -g -x as ntpdate or it will sync to itself
# The stratum should be a high value so this does not get chosen
# except in dire circumstances.
server 127.127.1.0
fudge 127.127.1.0 stratum 14
# Defining a default security setting
restrict default
_EOF_
	echo "enable-mtech" >> $STATUSFILE
fi

# Everything is in place, start forwarder
/etc/init.d/lora-packet-forwarder start
sleep 10s

grep monit $STATUSFILE > /dev/null 2> /dev/null
if [ $? -ne 0 ] ; then
	echo "installing monit"
	cat << _EOF_ > /etc/default/monit
# set to "yes" or "no" to control starting on boot
ENABLED="yes"
_EOF_
	sed -i 's/admin:monit/root:t3ralyt1c/' /etc/monitrc
	sed -i 's/use address localhost/use address 0.0.0.0/' /etc/monitrc
	sed -i 's?allow localhost?allow 0.0.0.0/0.0.0.0?' /etc/monitrc
	cat << _EOF_ > /etc/monit.d/ppp
check process ppp0 with pidfile /run/ppp0.pid
program start = "/usr/sbin/pppd call gsm"
program stop = "/usr/bin/killall pppd"
_EOF_
	cat << _EOF_ >/etc/monit.d/lora-packet-forwarder
check process lora-pkt-fwd-1 with pidfile /run/lora/lora-pkt-fwd-1.pid
program start = "/etc/init.d/lora-packet-forwarder start"
program stop = "/etc/init.d/lora-packet-forwarder stop"
_EOF_
	echo 192.168.1.2  $(uname -n) >> /etc/hosts
	monit -t
	echo "monit" >> $STATUSFILE
fi

ps -A | grep lora > /dev/null 2> /dev/null
if [ $? -eq 0 ] ; then
	echo "installation is now complete"
	echo "add $gwid to LoRa server and print label"
	echo "setup_complete" >> $STATUSFILE
	echo "gateway will shutdown after enter key is pressed"
	echo "remove sd card after power down"
	read n
	sync;sync;sync
	shutdown -h now
	sleep 600
fi
