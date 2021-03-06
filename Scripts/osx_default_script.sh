#/usr/bin/env bash

# Pansift Telegraf input.exec script for writing influx measurements and tags

#set -e
#set -vx

# Note: We can't afford to have a comma or space out of place with InfluxDB ingestion in the line protocol
LDIFS=$IFS

script_name=$(basename "$0")
# Get configuration targets etc
PANSIFT_PREFERENCES="$HOME"/Library/Preferences/Pansift
source "$PANSIFT_PREFERENCES"/pansift.conf

if [[ ${#1} = 0 ]]; then
	echo "Usage: Pass one parameter -n|--network -m|--machine -t|--trace -s|--scan -w|--web"
	echo "Usage: ./$script_name -i"
	exit 0;
fi

airport="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
plistbuddy="/usr/libexec/PlistBuddy"
curl_path="/opt/local/bin/curl"
agent[0]="Mozilla/5.0 (Macintosh; Intel Mac OS X 11_2_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.82 Safari/537.36"
agent[1]="Mozilla/5.0 (Macintosh; Intel Mac OS X 11.2; rv:86.0) Gecko/20100101 Firefox/86.0"
agent[2]="Mozilla/5.0 (Macintosh; Intel Mac OS X 11_2_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.3 Safari/605.1.15"
curl_user_agent=$[$RANDOM % ${#agent[@]}]
#curl_user_agent="pansift.com/0.1"
#curl_user_agent="pansift-${PANSIFT_UUID}"
dns_query_host=$(uuidgen)
dns_query_domain="doesnotexist.pansift.com"
dns_query="$dns_query_host.$dns_query_domain"

# These commands we want to and are happy to run each time as they may change frequently enough that we want to globally
# make decisions about them or reference them in more than one function or type of switch.
systemsoftware=$(sw_vers)
osx_mainline=$(echo -n "$systemsoftware" | grep -i "productversion" | cut -d':' -f2- | cut -d'.' -f1 | xargs)
network_interfaces=$(networksetup -listallhardwareports)

# Old versions of curl will fail with status 53 on SSL/TLS negotiation on newer hosts
# User really needs a newer curl binary but can also put defaults here
if test -f "$curl_path"; then
	curl_binary="/opt/local/bin/curl -A "$curl_user_agent" --no-keepalive"
else
	curl_binary="/usr/bin/curl -A "$curl_user_agent" --no-keepalive"
fi

remove_chars () {
	read data
	newdata=$(echo -n "$data" | awk '{$1=$1;print}' | tr ',' '.' | tr -s ' ' | tr '[:upper:]' '[:lower:]' | tr -d '\r' | sed 's! !\\ !g')
	echo -n $newdata
}

remove_chars_except_spaces () {
	# This is for fieldset fields where there may be a space, as telegraf will add it's own backslash \ and if we already have one then we get "\\ "
	read data
	newdata=$(echo -n "$data" | awk '{$1=$1;print}' | tr ',' '.' | tr -s ' ' | tr '[:upper:]' '[:lower:]' | tr -d '\r')
	echo -n $newdata
}
remove_chars_delimit_colon () {
	# This is for fieldset fields with lists and we remove the comma just to be sure (and also *all* spaces)
	read data
	newdata=$(echo -n "$data" | awk '{$1=$1;print}' | tr ',' ':' | tr '[:upper:]' '[:lower:]' | tr -d '\r' | tr -d ' ')
	echo -n $newdata
}

timeout () { 
	perl -e 'alarm shift; exec @ARGV' "$@" 
}

asn_trace () {
	# Requires internet_measure to be called in advance
	internet_measure
	# This is not an explicit ASN path but rather the ASNs from a traceroute so it's not a BGP metric but a representation of AS zones 
	measurement="pansift_osx_paths"
	if [ "$internet_connected" == "true" ]; then
		i=0
		IFS=","
		for host in $PANSIFT_HOSTS_CSV
		do
			if [ ! -z "$host" ]; then
				asn_trace=$(timeout 10 traceroute -I -w1 -S -an "$host" 2>/dev/null | grep -v "trace" | awk '{ORS=":"}{gsub("[][]",""); print $2}' | sed 's/.$//' | remove_chars)
				target_host=$(echo -n "$host" | remove_chars)
				tagset=$(echo -n "from_asn=$internet_asn,destination=$target_host")
				fieldset=$( echo -n "asn_trace=\"$asn_trace\"")
				timesuffix=$(expr 1000000000 + $i + 1) # This is to get around duplicates in Influx with measurement, tag, and timestamp the same.
				timesuffix=${timesuffix:1} # We drop the leading "1" and end up with incrementing nanoseconds 9 digits long
				timestamp=$(date +%s)$timesuffix
				echo -ne "$measurement,$tagset $fieldset $timestamp\n"
				((i++))
			fi
		done
		IFS=$OLDIFS
	else
		tagset="from_asn=AS0,destination=localhost"
		fieldset="asn_trace=AS0"
		timestamp=$(date +%s)000000000
		echo -ne "$measurement,$tagset $fieldset $timestamp\n"
	fi

}

system_measure () {
	#hostname=$(hostname | remove_chars)
	#username=$(echo -n "$USER" | remove_chars)
	# Uptime and uptime_format are already covered by the default plugin.
	#uptime=$(sysctl kern.boottime | cut -d' ' -f5 | cut -d',' -f1)

	product_name=$(echo -n "$systemsoftware" | egrep -i "productname" | cut -d':' -f2- | remove_chars)
	product_version=$(echo -n "$systemsoftware" | egrep -i "productversion" | cut -d':' -f2- | remove_chars)
	build_version=$(echo -n "$systemsoftware" | egrep -i "buildversion" | cut -d':' -f2- | remove_chars)

	systemprofile_sphardwaredatatype=$(system_profiler SPHardwareDataType)
	model_name=$(echo -n "$systemprofile_sphardwaredatatype" | egrep -i "model name" | cut -d':' -f2- | remove_chars)
	model_identifier=$(echo -n "$systemprofile_sphardwaredatatype" | egrep -i "model identifier" | cut -d':' -f2- | remove_chars)
	memory=$(echo -n "$systemprofile_sphardwaredatatype" | egrep -i "memory" | cut -d':' -f2- | remove_chars_except_spaces)
	boot_romversion=$(echo -n "$systemprofile_sphardwaredatatype" | egrep -i "boot rom version" | cut -d':' -f2- | remove_chars)
	smc_version=$(echo -n "$systemprofile_sphardwaredatatype" | egrep -i "smc version" | cut -d':' -f2- | remove_chars)
	serial_number=$(echo -n "$systemprofile_sphardwaredatatype" | egrep -i "serial number" | cut -d':' -f2- | remove_chars)
}


network_measure () {
	if [ $osx_mainline == 11 ]; then
		netstat4_print_position=4 # 11.x Big Sur onwards
	else 
		netstat4_print_position=6 # 10.x 
	fi
	netstat4=$(netstat -rn -f inet)
	netstat6=$(netstat -rn -f inet6)
	dg4_ip=$(echo -n "$netstat4" | grep -qi default || { echo -n 'none'; exit 0;}; echo -n "$netstat4" | grep -i default | awk '{print $2}' | remove_chars)
	dg6_fullgw=$(echo -n "$netstat6" | grep -qi default || { echo -n 'none'; exit 0;}; echo -n "$netstat6" | grep -i default | awk '{print $2}' | remove_chars)
	dg6_ip=$(echo -n "$netstat6" | grep -qi default || { echo -n 'none'; exit 0;}; echo -n "$netstat6" | grep -i default | awk '{print $2}' | cut -d'%' -f1 | remove_chars)
	dg4_interface=$(echo -n "$netstat4" | grep -qi default || { echo -n 'none'; exit 0;}; echo -n "$netstat4" | grep -i default | awk -v x=$netstat4_print_position '{print $x}' | remove_chars)
	dg6_interface=$(echo -n "$netstat6" | grep -qi default || { echo -n 'none'; exit 0; }; echo -n "$netstat6" | grep -i default | awk '{print $2}'| remove_chars)
	dg6_interface_device_only=$(echo -n "$dg6_interface" | cut -d'%' -f2)
	if [ $dg6_interface == "none" ]; then
  dg6_interface_device_only = "none"
	fi
	# Grabbing network interfaces from global 
	hardware_interfaces=$(echo -n "$network_interfaces" | awk -F ":" '/Hardware Port:|Device:/{print $2}' | paste -d',' - - )
	dg4_hardware_type=$(echo -n "$hardware_interfaces" | grep -qi "$dg4_interface" || { echo -n 'unknown'; exit 0; }; echo -n "$hardware_interfaces" | grep -i "$dg4_interface" | cut -d',' -f1 | xargs)
	dg6_hardware_type=$(echo -n "$hardware_interfaces" | grep -qi "$dg6_interface_device_only" || { echo -n 'unknown'; exit 0; }; echo -n "$hardware_interfaces" | grep -i "$dg6_interface_device_only" | cut -d',' -f1 | xargs)
	if [ ! "$dg4_ip" == "none" ]; then
		dg4_router_ether=$(arp "$dg4_ip")
	else
		dg4_router_ether="none"
	fi
	if [ ! "$dg4_interface" == "none" ]; then
		dg4_interface_ether=$(ifconfig "$dg4_interface" | egrep ether | xargs | cut -d' ' -f2 | remove_chars)
	else
		dg4_interface_ether="none"
	fi
	if [ ! "$dg6_interface" == "none" ]; then
		dg6_interface_ether=$(ifconfig "$dg6_interface_device_only" | grep "ether" | xargs | cut -d' ' -f2 | remove_chars)
		dg6_router_ether=$(ndp -anr | egrep "$dg6_interface" | xargs | cut -d' ' -f2 | remove_chars )
	else
		dg6_interface_ether="none"
		dg6_router_ether="none"
	fi

	dg4_response=$(echo -n "$netstat4" | grep -qi default || { echo -n 0; exit 0; }; [[ ! "$dg4_ip" == "none" ]] && ping -c1 -i1 -o "$dg4_ip" | tail -n1 | cut -d' ' -f4 | cut -d'/' -f2 || echo -n 0)
	dg6_response=$(echo -n "$netstat6" | grep -qi default || { echo -n 0; exit 0; }; [[ ! "$dg6_ip" == "none" ]] && ping6 -c1 -i1 -o "$dg6_fullgw" | tail -n1 | cut -d' ' -f4 | cut -d'/' -f2 || echo -n 0)

	if [[ "$dg4_response" > 0 ]] || [[ "$dg6_respone" > 0 ]]; then
		locally_connected="true"
	else
		locally_connected="false"
	fi  
	dns4_query_response="0"
	dns6_query_response="0"
	RESOLV=/etc/resolv.conf
	if test -f "$RESOLV"; then
		dns4_primary=$(cat /etc/resolv.conf | grep -q '\..*\..*\.' || { echo -n '0.0.0.0'; exit 0; }; cat /etc/resolv.conf | grep '\..*\..*\.' | head -n1 | cut -d' ' -f2 | remove_chars)
		dns6_primary=$(cat /etc/resolv.conf | grep -q 'nameserver.*:' || { echo -n '::'; exit 0; }; cat /etc/resolv.conf | grep 'nameserver.*:' | head -n1 | cut -d' ' -f2 | remove_chars)
		if [ $dns4_primary != "0.0.0.0" ]; then
			dns4_query_response=$(dig -4 +tries=2 @"$dns4_primary" "$dns_query" | grep -m1 -i "query time" | cut -d' ' -f4 | remove_chars)
		else
			dns4_query_response="0"
		fi
		if [ $dns6_primary != "::" ]; then
			dns6_query_response=$(dig -6 +tries=2 @"$dns6_primary" "$dns_query" | grep -m1 -i "query time" | cut -d' ' -f4 | remove_chars)
			[ -z "$dns6_query_response" ] && dns6_query_response="0"
		else 
			dns6_query_response="0"
		fi
	else
		dns4_primary="0.0.0.0"
		dns6_primary="::"
	fi
}

internet_measure () {
	# We need basic ICMP response times from lighthouse too?
	#
	internet4_connected=$(ping -o -c3 -i1 -t5 $PANSIFT_ICMP4_TARGET > /dev/null 2>&1 || { echo -n "false"; exit 0;}; echo -n "true")
	internet6_connected=$(ping6 -o -c3 -i1 $PANSIFT_ICMP6_TARGET > /dev/null 2>&1 || { echo -n "false"; exit 0;}; echo -n "true")
	internet_connected="false" # Default to be overwritten below
	internet_dualstack="false" # "
	ipv4_only="false" # "
	ipv6_only="false" # "
	internet4_public_ip="0.0.0.0"
	internet6_public_ip="::"
	internet_asn="0i"

	if [ "$internet4_connected" == "true" ] || [ "$internet6_connected" == "true" ]; then
		internet_connected="true"
	else
		internet_connected="false"
		internet4_public_ip="0.0.0.0"
		internet6_public_ip="::"
		internet_asn="0i"
	fi
	if [ "$internet4_connected" == "true" ] && [ "$internet6_connected" == "true" ]; then
		ipv4_only="false"
		ipv6_only="false"
		internet_dualstack="true"
		lighthouse4=$($curl_binary -m3 -sN -4 -k -L -i "$PANSIFT_LIGHTHOUSE" 2>&1 || exit 0)
		lighthouse6=$($curl_binary -m3 -sN -6 -k -L -i "$PANSIFT_LIGHTHOUSE" 2>&1 || exit 0)
		internet_asn=$(echo -n "$lighthouse4" | grep -qi "x-pansift-client-asn" || { echo -n '0'; exit 0;}; echo -n "$lighthouse4" | grep -i "x-pansift-client-asn" | cut -d' ' -f2 | remove_chars )i
		internet4_public_ip=$(echo -n "$lighthouse4" | grep -qi "x-pansift-client-ip" || { echo -n '0.0.0.0'; exit 0;}; echo -n "$lighthouse4" | grep -i "x-pansift-client-ip" | cut -d' ' -f2 | remove_chars )
		internet6_public_ip=$(echo -n "$lighthouse6" | grep -qi "x-pansift-client-ip" || { echo -n '::'; exit 0;}; echo -n "$lighthouse6" | grep -i "x-pansift-client-ip" | cut -d' ' -f2 | remove_chars )
	fi
	if [ "$internet4_connected" == "true" ] && [ "$internet6_connected" == "false" ]; then
		ipv4_only="true"
		ipv6_only="false"
		internet_dualstack="false"
		lighthouse4=$($curl_binary -m3 -sN -4 -k -L -i "$PANSIFT_LIGHTHOUSE" 2>&1 || exit 0)
		internet_asn=$(echo -n "$lighthouse4" | egrep -qi "x-pansift-client-asn" || { echo -n '0'; exit 0;}; echo -n "$lighthouse4" | egrep -i "x-pansift-client-asn" | cut -d' ' -f2 | remove_chars )i
		internet4_public_ip=$(echo -n "$lighthouse4" | egrep -qi "x-pansift-client-ip" || { echo -n '0.0.0.0'; exit 0;}; echo -n "$lighthouse4" | egrep -i "x-pansift-client-ip" | cut -d' ' -f2 | remove_chars )
		internet6_public_ip="::"
	fi
	if [ "$internet4_connected" == "false" ] && [ "$internet6_connected" == "true" ]; then
		ipv4_only="false"
		ipv6_only="true"
		internet_dualstack="false"
		lighthouse6=$($curl_binary -m3 -sN -6 -k -L -i "$PANSIFT_LIGHTHOUSE" 2>&1 || exit 0)
		internet_asn=$(echo -n "$lighthouse6" | egrep -qi "x-pansift-client-asn" || { echo -n '0'; exit 0;}; echo -n "$lighthouse6" | egrep -i "x-pansift-client-asn" | cut -d' ' -f2 | remove_chars )i
		internet4_public_ip="0.0.0.0"
		internet6_public_ip=$(echo -n "$lighthouse6" | egrep -qi "x-pansift-client-ip" || { echo -n '::'; exit 0;}; echo -n "$lighthouse6" | egrep -i "x-pansift-client-ip" | cut -d' ' -f2 | remove_chars )
	fi
}

wlan_measure () {
	# Need to add a separate PlistBuddy to extract keys rather than below as is cleaner + can get NSS (Number of Spatial Streams)
	airport_output=$($airport -I)
	wlan_connected=$(echo -n "$airport_output" | grep -q 'AirPort: Off' && echo -n 'false' || echo -n 'true')
	if [ $wlan_connected == "true" ]; then
		wlan_state=$(echo -n "$airport_output" | egrep -i '[[:space:]]state' | cut -d':' -f2- | remove_chars) 
		if [ $wlan_state == "scanning" ]; then
			wlan_state="running" # This is increasing the cardinality needlessly, can revert if queries actually need scanning time
		fi
		wlan_op_mode=$(echo -n "$airport_output"| egrep -i '[[:space:]]op mode' | cut -d':' -f2- | remove_chars)
		# In an enviornment with the Airport on and no known or previously connected networks this needs to be set
		if [ ${#wlan_op_mode} == 0 ]; then
			wlan_op_mode="none"
		fi
		wlan_rssi=$(echo -n "$airport_output" | egrep -i '[[:space:]]agrCtlRSSI' | cut -d':' -f2- | remove_chars)
		wlan_noise=$(echo -n "$airport_output" | egrep -i '[[:space:]]agrCtlNoise' | cut -d':' -f2- | remove_chars)
		wlan_snr=$(var=$(( $(( $wlan_noise * -1)) - $(( $wlan_rssi * -1)) )); echo -n $var)i
		wlan_spatial_streams=$(echo -n "$airport_output" | egrep -i '[[:space:]]agrCtlNoise' | cut -d':' -f2- | remove_chars)
		# because of mathematical operation, add back in i
		wlan_rssi="$wlan_rssi"i
		wlan_noise="$wlan_noise"i
		wlan_last_tx_rate=$(echo -n "$airport_output"| egrep -i '[[:space:]]lastTxRate' | cut -d':' -f2- | remove_chars)i
		wlan_max_rate=$(echo -n "$airport_output" | egrep -i '[[:space:]]maxRate' | cut -d':' -f2- | remove_chars)i
		wlan_ssid=$(echo -n "$airport_output" | egrep -i '[[:space:]]ssid' | cut -d':' -f2- | awk '{$1=$1;print}')
		wlan_bssid=$(echo -n "$airport_output" | egrep -i '[[:space:]]bssid' | awk '{$1=$1;print}' | cut -d' ' -f2)
		wlan_mcs=$(echo -n "$airport_output"| egrep -i '[[:space:]]mcs' | cut -d':' -f2 | remove_chars)i
		wlan_80211_auth=$(echo -n "$airport_output"| egrep -i '[[:space:]]802\.11 auth' |  cut -d':' -f2 | remove_chars)
		wlan_link_auth=$(echo -n "$airport_output" | egrep -i '[[:space:]]link auth' |  cut -d':' -f2 | remove_chars)
		wlan_last_assoc_status=$(echo -n "$airport_output" | egrep -i 'lastassocstatus' |  cut -d':' -f2 | remove_chars)i
		wlan_channel=$(echo -n "$airport_output"| egrep -i '[[:space:]]channel' |  cut -d':' -f2 | awk '{$1=$1;print}' | cut -d',' -f1 | remove_chars)i

		# Here we need to add airport -I -x for PLIST and then extract the NSS if available. Also can direct extract channel width value as BANDWIDTH
		# Turns out that (other than using native API) the airport -I vs -Ix give additional information
		airport_more_data="$PANSIFT_LOGS"/airport-more-info.plist #Need a better way to do the install location, assuming ~/p3 for now.
		airport_info_xml=$($airport -Ix)
		printf "%s" "$airport_info_xml" > "$airport_more_data" &
		pid=$!
		wait $pid
		if [ $osx_mainline == 11 ]; then
			if [ $wlan_op_mode != "none" ]; then
			wlan_number_spatial_streams=$("$plistbuddy" "${airport_more_data}" -c "print NSS" | remove_chars)i
			wlan_width=$("$plistbuddy" "${airport_more_data}" -c "print BANDWIDTH" | remove_chars)i
			else
			wlan_number_spatial_streams=0i
			wlan_width=0i
			fi
		else 
			wlan_number_spatial_streams=0i
			width_increment=$(echo -n "$airport_output"| egrep -i '[[:space:]]channel' |  cut -d':' -f2 | awk '{$1=$1;print}' | cut -d',' -f2 | remove_chars)
			if [[ "$width_increment" == 1 ]]; then
				wlan_width=40i
			elif [[ "$width_increment" == 2 ]]; then
				wlan_width=80i
			else
				wlan_width=20i
			fi
		fi

		# Here we grab more information about the local airport card or about the currently connected network (not available above)
		wlan_sp_airport_data_type=$(system_profiler SPAirPortDataType)
		wlan_supported_phy_mode=$(echo -n "$wlan_sp_airport_data_type" | egrep -i "Supported PHY Modes" | cut -d':' -f2- | remove_chars)
		wlan_current_phy_mode=$(echo -n "$wlan_sp_airport_data_type" | egrep -i "PHY Mode:" | head -n1 | cut -d':' -f2- | remove_chars)
		wlan_supported_channels=$(echo -n "$wlan_sp_airport_data_type" | egrep -i "Supported Channels:" | head -n1 | cut -d':' -f2- | remove_chars_delimit_colon)
	else
		#set all values null as can not have an empty tag
		wlan_state="none"
		wlan_op_mode="none"
		wlan_80211_auth="none"
		wlan_link_auth="none"
		wlan_current_phy_mode="none"
		wlan_supported_phy_mode="none"
		wlan_channel=0i
		wlan_width=20i # Can we default to 20 (20MHz) i.e. does 0 mean 20, what about .ax?
		wlan_rssi=0i
		wlan_noise=0i
		wlan_snr=0i
		wlan_last_tx_rate=0i
		wlan_max_rate=0i
		wlan_ssid=""
		wlan_bssid=""
		wlan_mcs=0i
		wlan_last_assoc_status=-1i
		wlan_number_spatial_streams=1i
		wlan_supported_channels=""
	fi
}

wlan_scan () {
	airport_output=$("$airport" -s -x)
	if [ -z "$airport_output" ]; then
		#echo -n "No airport output in scan"
		wlan_scan_on="false"
		wlan_scan_data="none"
		measurement="pansift_osx_wlanscan"
		tagset=$(echo -n "wlan_scan_on=$wlan_scan_on")
		fieldset=$( echo -n "wlan_on=false")
		results
	else
		# Need to migrate this to XML output and a data structure that Influx can ingest that includes taking in to account spaces in SSID hence XML
		#scandata="/tmp/airport.plist"
		scandata="$PANSIFT_LOGS"/airport-scan.plist #Need a better way to do the install location, assuming ~/p3 for now. 
		#test -f $scandata || touch $scandata
		#if [[ ! -e $scandata ]]; then
		#  touch $scandata
		#fi
		#echo $airport_output > tempfile && cp tempfile $scandata # This is a hack to wait for the completion of writing data
		printf "%s" "$airport_output" > "$scandata" &
		pid=$!
		wait $pid
		wlan_scan_on="true"
		precount=$(
		"$plistbuddy" "${scandata}" -c "print ::" | # Extract array items
			cat -v |                                  # Convert from binary output to ascii
			grep -E "^\s{4}Dict" |                    # Search for top-level dictionaries
			wc -l |                                   # Count top-level dictionaries
			xargs                                     # Trim whitespace
		)
		count=$(expr "${precount}" - 1)
		for i in $(seq 0 "${count}")
		do
			wlan_scan_ssid=$("$plistbuddy" "$scandata" -c "print :$i:SSID_STR")
			wlan_scan_bssid=$("${plistbuddy}" "${scandata}" -c "print :$i:BSSID")
			#wlan_scan_bssid_tag=$(echo -n "$wlan_scan_bssid")  # BSSID should be a clean string as opposed to using SSID as a tag which needs to escape spaces with backslash \
			wlan_scan_channel=$("${plistbuddy}" "${scandata}" -c "print :$i:CHANNEL")i
			wlan_scan_rssi=$("${plistbuddy}" "${scandata}" -c "print :$i:RSSI")i
			wlan_scan_noise=$("${plistbuddy}" "${scandata}" -c "print :$i:NOISE")i
			wlan_scan_ht_secondary_chan_offset=$("${plistbuddy}" "${scandata}" -c "print :$i:HT_IE:HT_SECONDARY_CHAN_OFFSET" 2>/dev/null)i
			if [ $wlan_scan_ht_secondary_chan_offset == "i" ]; then
				wlan_scan_ht_secondary_chan_offset="0i"
			fi
			measurement="pansift_osx_wlanscan"
			#tagset=$(echo -n "wlan_scan_on=$wlan_scan_on,wlan_scan_bssid_tag=$wlan_scan_bssid_tag")
			tagset=$(echo -n "wlan_scan_on=$wlan_scan_on")
			fieldset=$( echo -n "wlan_scan_ssid=\"$wlan_scan_ssid\",wlan_scan_bssid=\"$wlan_scan_bssid\",wlan_scan_channel=$wlan_scan_channel,wlan_scan_rssi=$wlan_scan_rssi,wlan_scan_noise=$wlan_scan_noise,wlan_scan_ht_secondary_chan_offset=$wlan_scan_ht_secondary_chan_offset")
			timesuffix=$(expr 1000000000 + $i + 1) # This is to get around duplicates in Influx with measurement, tag, and timestamp the same. 
			timesuffix=${timesuffix:1} # We drop the leading "1" and end up with incrementing nanoseconds 9 digits long
			timestamp=$(date +%s)$timesuffix
			echo -ne "$measurement,$tagset $fieldset $timestamp\n" 
		done
	fi
}


http_checks () {
	# Yes we know this curl speed_download is single stream and not multithreaded/pipelined, it's just indicative of over X
	measurement="pansift_osx_http"
	i=0
	IFS=","
	for host in $PANSIFT_HOSTS_CSV
	do
		if [ ! -z "$host" ]; then
			http_url=$(echo -n "$host" | remove_chars)
			target_host="https://"$host
			curl_response=$(curl -A "$curl_user_agent" -k -s -o /dev/null -w "%{http_code}:%{speed_download}" -L "$target_host" --stderr - | remove_chars)
			http_status=$(echo -n "$curl_response" | cut -d':' -f1 | sed 's/^000/0/' | remove_chars)i
			http_speed_bytes=$(echo -n "$curl_response" | cut -d':' -f2)
			# bc doesn't print a leading zero and this confuses poor influx
			http_speed_megabits=$(echo "scale=3;($http_speed_bytes * 8) / 1000000" | bc -l | tr -d '\n' | sed 's/^\./0./' | remove_chars)
			tagset=$(echo -n "http_url=$http_url")
			fieldset=$( echo -n "http_status=$http_status,http_speed_megabits=$http_speed_megabits")
			timesuffix=$(expr 1000000000 + $i + 1) # This is to get around duplicates in Influx with measurement, tag, and timestamp the same.
			timesuffix=${timesuffix:1} # We drop the leading "1" and end up with incrementing nanoseconds 9 digits long
			timestamp=$(date +%s)$timesuffix
			echo -ne "$measurement,$tagset $fieldset $timestamp\n"
			((i++))
		fi
	done
	IFS=$OLDIFS
}

# Telegraf: Need quotes for string field values but not in tags / also remember to use remove_chars for spaces and commas

results () {
	timestamp=$(date +%s)000000000
	echo -e "$measurement,$tagset $fieldset $timestamp\n"
}
while :; do
	case $1 in
		-m|--machine) 
			system_measure
			measurement="pansift_osx_machine"            
			tagset=$(echo -n "product_name=$product_name,model_name=$model_name,model_identifier=$model_identifier,serial_number=$serial_number")
			fieldset=$(echo -n "product_version=\"$product_version\",boot_romversion=\"$boot_romversion\",smc_version=\"$smc_version\",memory=\"$memory\"")
			results
			;;
		-n|--network) 
			internet_measure
			network_measure
			wlan_measure
			measurement="pansift_osx_network"
			tagset=$(echo -n "internet_connected=$internet_connected,internet_dualstack=$internet_dualstack,ipv4_only=$ipv4_only,ipv6_only=$ipv6_only,locally_connected=$locally_connected,wlan_connected=$wlan_connected,wlan_state=$wlan_state,wlan_op_mode=$wlan_op_mode,wlan_supported_phy_mode=$wlan_supported_phy_mode") 
			fieldset=$( echo -n "internet4_public_ip=\"$internet4_public_ip\",internet6_public_ip=\"$internet6_public_ip\",internet_asn=$internet_asn,dg4_ip=\"$dg4_ip\",dg6_ip=\"$dg6_ip\",dg4_hardware_type=\"$dg4_hardware_type\",dg6_hardware_type=\"$dg6_hardware_type\",dg4_interface=\"$dg4_interface\",dg6_interface=\"$dg6_interface\",dg6_interface_device_only=\"$dg6_interface_device_only\",dg4_interface_ether=\"$dg4_interface_ether\",dg6_interface_ether=\"$dg6_interface_ether\",dg4_response=$dg4_response,dg6_response=$dg6_response,dns4_primary=\"$dns4_primary\",dns6_primary=\"$dns6_primary\",dns4_query_response=$dns4_query_response,dns6_query_response=$dns6_query_response,wlan_rssi=$wlan_rssi,wlan_noise=$wlan_noise,wlan_snr=$wlan_snr,wlan_last_tx_rate=$wlan_last_tx_rate,wlan_max_rate=$wlan_max_rate,wlan_ssid=\"$wlan_ssid\",wlan_bssid=\"$wlan_bssid\",wlan_mcs=$wlan_mcs,wlan_number_spatial_streams=$wlan_number_spatial_streams,wlan_last_assoc_status=$wlan_last_assoc_status,wlan_channel=$wlan_channel,wlan_width=$wlan_width,wlan_current_phy_mode=\"$wlan_current_phy_mode\",wlan_supported_channels=\"$wlan_supported_channels\",wlan_80211_auth=\"$wlan_80211_auth\",wlan_link_auth=\"$wlan_link_auth\"")
			results
			;;
		-s|--scan)
			# The reason we don't set the single measurement here is we are looping in the scan
			wlan_scan
			;;
		-w|--web)
			# The reason we don't set the single measurement here is we are looping in the checks
			http_checks
			;;
		-t|--trace)
			# The reason we don't set the single measurement here is we are looping in the checks
			asn_trace
			;;
		*) break
	esac
	shift
done
