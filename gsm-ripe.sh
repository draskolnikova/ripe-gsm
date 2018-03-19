#!/bin/bash

## Tested : 
## Prefix=apn,user,password
## APN AXIS=internet
## APN TSEL=internet
## APN XL  =internet
## APN ISAT=indosat3g

##########
## v0.2 ##
##########

mmcli=`which mmcli`
nmcli=`which nmcli`
ip=`which ip`

if [[ ! -f $mmcli && ! -f $nmcli ]]; then
	echo "NetworkManager and ModemManager not found, exiting"
	exit
fi

# Writing probes ip & mac address
mkdir -p /etc/probes && rm -f /etc/probes/ripe.conf
$ip neig sho | grep -e 'eth*.*lladdr' | awk '{print $1 " "$5}' >> /etc/probes/ripe.conf

## Deleting previous temporary files
rm -f /tmp/{gateway_ip,probe,probes,providers,result}.txt

for _id in `$mmcli -L | awk '{print $1}' | sed 1,2d`; do
	modem_id=`basename "$_id"`
	provider=`$mmcli -m $modem_id | grep "operator name" | awk '{print $4$5}' | cut -d "'" -f2`
	ifname=`$mmcli -m $modem_id | grep primary | awk '{print $4}' | cut -d "'" -f2`
	manufacture=`$mmcli -m $modem_id | grep manufacture | awk '{print $4}' | cut -d "'" -f2`
	model=`$mmcli -m $modem_id | grep model | awk '{print $3}' | cut -d "'" -f2`

	#Disable/Enable modem before dialing
	echo "=============================================="
	echo "Modem $manufacture $model succesfully enabled!" 
	$mmcli -m $modem_id -e > /dev/null 2>&1

	state=`$nmcli c s ${provider,,} | grep connection.id | awk '{print $2}'`
	gateway_ip=`$nmcli c s ${provider,,} | grep IP4.GATEWAY | awk '{print $2}'`

	echo $gateway_ip >> /tmp/gateway_ip.txt	
	echo ${provider^^} >> /tmp/providers.txt

	if [[ "$provider" == "INDOSATOOREDOO" || "$provider" == "ISAT" ]]; then
		echo "Enable ${provider,,} interface"
		if grep -q ${provider^^} /etc/iproute2/rt_tables; then
			echo "[!] Route exist, I do nothing :-)"
		else
			echo "Register ${provider^^} metrics to routing tables"
			echo "1$modem_id ${provider^^}" >> /etc/iproute2/rt_tables
		fi
		if [ "$state" == "${provider,,}" ]; then
			echo "[!] Interface ${provider,,} is exist, I do nothing :-)"
		else
			echo "Interface ${provider,,} successfully created and enabled"
			$nmcli c add type gsm ifname $ifname con-name ${provider,,} apn 'indosat3g' > /dev/null 2>&1
		fi
	elif [[ "$provider" != "INDOSATOOREDOO" ]]; then
		echo "Enabling ${provider,,} interface"
		if grep -q ${provider^^} /etc/iproute2/rt_tables; then
			echo "[!] Route exist, I do nothing :-)"
		else
			echo "Register ${provider^^} metrics to routing tables"
			echo "1$modem_id ${provider^^}" >> /etc/iproute2/rt_tables
		fi
		if [ "$state" == "${provider,,}" ]; then
			echo "[!] Interface ${provider,,} is exist, I do nothing :-)"
		else
			echo "Interface ${provider,,} successfully created and enabled"
			$nmcli c add type gsm ifname $ifname con-name ${provider,,} apn 'internet' > /dev/null 2>&1
		fi
	fi
done

result() {
temp=`cat /etc/probes/ripe.conf | awk '{print $1}'`
for x in $temp; do
	echo $x >> /tmp/probe.txt
done
paste -d' ' /tmp/probe.txt /tmp/gateway_ip.txt >> /tmp/probes.txt
paste -d' ' /tmp/probes.txt /tmp/providers.txt >> /tmp/result.txt
}

result
while IFS= read line
do
 route=`echo $line| awk '{ print $1 }'`
 gateway=`echo $line| awk '{ print $2 }'`
 provider=`echo $line| awk '{ print $3 }'`

 existing_route=`ip rule ls table $provider`
 [[ -z $existing_route ]] && $ip rule add from $route table $provider && $ip route add default via $gateway table $provider
 $ip route flush cache
done < /tmp/result.txt
