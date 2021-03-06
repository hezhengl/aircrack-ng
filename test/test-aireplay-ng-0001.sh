#!/bin/sh

if test ! -z "${CI}"; then exit 77; fi

# Check root
if [ $(id -u) -ne 0 ]; then
	echo "Not root, skipping"
	exit 77
fi

# Check hostapd is present
hash hostapd 2>&1 >/dev/null
if [ $? -ne 0 ]; then
	echo "HostAPd is not installed, skipping"
	exit 77
fi

# Load module
LOAD_MODULE=0
if [ $(lsmod | egrep mac80211_hwsim | wc -l) -eq 0 ]; then
	LOAD_MODULE=1
	modprobe mac80211_hwsim radios=1 2>&1 >/dev/null
	if [ $? -ne 0 ]; then
		# XXX: It can fail if inside a container too
		echo "Failed inserting module, skipping"
		exit 77
	fi
fi

# Check if there is only one radio
if [ $("${top_builddir}/scripts/airmon-ng" | egrep hwsim | wc -l) -gt 1 ]; then
	echo "More than one radio, hwsim may be in use by something else, skipping"
	exit 77
fi

# Check if interface is present and grab it
WI_IFACE=$("${top_builddir}/scripts/airmon-ng" 2>/dev/null | egrep hwsim | awk '{print $2}')
if [ -z "${WI_IFACE}" ]; then
	[ ${LOAD_MODULE} -eq 1 ] && rmmod mac80211_hwsim 2>&1 >/dev/null
	return 1
fi

# Set-up hostapd
SSID=thisrocks
TEMP_HOSTAPD_CONF=$(mktemp)
cat >> ${TEMP_HOSTAPD_CONF} << EOF
driver=nl80211
interface=${WI_IFACE}
channel=1
hw_mode=g
ssid=${SSID}
EOF

# Start it
TEMP_HOSTAPD_PID="/tmp/hostapd_pid_$(date +%s)"
hostapd -B ${TEMP_HOSTAPD_CONF} -P ${TEMP_HOSTAPD_PID} 2>&1 >/dev/null
if test $? -ne 0; then
	[ ${LOAD_MODULE} -eq 1 ] && rmmod mac80211_hwsim 2>&1 >/dev/null
	exit 1
fi

# Run actual test
"${top_builddir}/src/aireplay-ng${EXEEXT}" \
    -1 1 \
    -e "${SSID}" \
    -T 1 \
    ${WI_IFACE} \
	2>&1 >/dev/null

# Cleanup
kill -9 $(cat ${TEMP_HOSTAPD_PID} ) 2>&1 >/dev/null
[ ${LOAD_MODULE} -eq 1 ] && rmmod mac80211_hwsim 2>&1 >/dev/null

exit $?
