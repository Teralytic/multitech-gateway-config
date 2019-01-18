#Script to enable call home and return gwid
#
#
#
#

#Turn on Call Home function
curl -s -X POST -H ‘Content-Type: application/json’ -d ‘{}’ http://127.0.0.1/api/command/call_home_enable

#return gwid
gwid=$(mts-io-sysfs show lora/eui 2> /dev/null | sed 's/://g')
echo "add $gwid to LoRa server and print label"

#shutdown after
echo "gateway will shutdown after enter key is pressed"
echo "remove sd card after power down"
read n
sync;sync;sync
shutdown -h now
sleep 600
