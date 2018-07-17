#!/bin/bash

## fedora ARM 27
## Console IP 192.168.255.14
## Prefix    =apn,user,password
## APN AXIS  =AXIS    
## APN TSEL  =telkomsel
## APN XL    =internet
## APN ISAT  =indosatgprs
## APN 3     =3gprs
## smartfren =smartfren4G


mmcli=`which mmcli`
nmcli=`which nmcli`
ip=`which ip`
firewallcmd=`which firewall-cmd`

enable(){
	provider=$1
	provider_apn=$2
	modem_id=$3
	state=$4

	echo "Enable ${provider,,} interface"
	if [ ! -f `cat /etc/iproute2/rt_tables | awk '{print $2}' | grep $provider` ]; then
		echo "[!] Route exist, I do nothing :-)"
	else
		echo "Register ${provider^^} metrics to routing tables"
		echo "1$modem_id ${provider^^}" >> /etc/iproute2/rt_tables
	fi
	if [ "$state" == "${provider,,}" ]; then
		echo "[!] Interface ${provider,,} is exist, I do nothing :-)"
	else
		echo "Interface ${provider,,} successfully created and enabled"
		$nmcli c add type gsm ifname $ifname con-name ${provider,,} apn $provider_apn > /dev/null 2>&1
		sleep 5
	fi
}

result() {
temp=`cat /etc/probes/ripe.conf | awk '{print $1}'`
for x in $temp; do
	echo $x >> /tmp/probe.txt
done
paste -d' ' /tmp/probe.txt /tmp/gateway_ip.txt >> /tmp/probes.txt
paste -d' ' /tmp/probes.txt /tmp/providers.txt >> /tmp/result.txt
}


if [[ ! -f $mmcli && ! -f $nmcli ]]; then
	echo "NetworkManager and ModemManager not found, exiting"
	exit
fi

if mmcli -L | grep 'No modems were found' > /dev/null 2>&1; then
        echo "Modems not found"
        exit
fi

# Writing probes ip & mac address
mkdir -p /etc/probes && rm -f /etc/probes/ripe.conf
$ip neig sho | grep -e 'eth*.*lladdr' | awk '{print $1 " "$5}' >> /etc/probes/ripe.conf
sed -i "/192.168.255.14/d" /etc/probes/ripe.conf

## Deleting previous temporary files
rm -f /tmp/{gateway_ip,probe,probes,providers,result}.txt

# Enabling modem
for _id in `$mmcli -L | awk '{print $1}' | sed 1,2d`; do

	modem_id=`basename "$_id"`
	provider=`$mmcli -m $modem_id | grep "operator name" | awk '{print $4$5}' | cut -d "'" -f2`
	ifname=`$mmcli -m $modem_id | grep primary | awk '{print $4}' | cut -d "'" -f2`
	manufacture=`$mmcli -m $modem_id | grep manufacture | awk '{print $4}' | cut -d "'" -f2`
	model=`$mmcli -m $modem_id | grep model | awk '{print $3}' | cut -d "'" -f2`
	state=`$nmcli c s ${provider,,} | grep connection.id | awk '{print $2}'`

	#Disable/Enable modem before dialing
	echo "=============================================="
	echo "Modem $manufacture $model succesfully enabled!" 
	$mmcli -m $modem_id -e > /dev/null 2>&1


	case "$provider" in
		"INDOSATOOREDOO" ) enable "$provider" "indosatgprs" "$modem_id" "$state"
			;;
		"ISAT" ) enable "$provider" "indosatgprs" "$modem_id" "$state"
			;;
		"XL" ) enable "$provider" "internet" "$modem_id" "$state"
			;;
		"3" ) enable "$provider" "3gprs" "$modem_id" "$state"
			;;
		"smartfren" ) enable "$provider" "smartfren4G" "$modem_id" "$state"
			;;
		"TSEL" ) enable "$provider" "telkomsel" "$modem_id" "$state"
			;;
	esac

	gateway_ip=`$nmcli c s ${provider,,} | grep IP4.GATEWAY | awk '{print $2}'`
	echo $gateway_ip >> /tmp/gateway_ip.txt	
	echo ${provider^^} >> /tmp/providers.txt
done

##Policy Based Routing
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

##Masquerade config
echo "=============================================="
if [ ! -z `$firewallcmd --query-masquerade | grep no` ]; then
	echo "Creating masquerade to all intefaces"
	$firewallcmd --add-masquerade 
	$firewallcmd --add-masquerade --permanent 
	echo "Masquerade created"
else
	echo "Masquerade has been created"
fi
