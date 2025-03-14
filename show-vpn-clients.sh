#!/bin/bash
# ссылка на github https://github.com/NickNeoOne/bash-scripts
echo ""
echo "================================================ Show client connected to sstp ================================================="
accel-cmd show sessions username,state,calling-sid,ip,uptime-raw,rx-bytes,tx-bytes
echo "================================================================================================================================"
echo ""
echo ""
echo "================================================ Show client connected to ipsec ================================================"
#ipsec status | grep  "ESTABLISHED"
ipsec status | grep -e "ESTABLISHED" -e "===" | sed '{N
s/\n//}' | awk -F "," {'print $2'}
echo "================================================================================================================================"
echo ""



echo "====================================================== Show leases on ipsec ===================================================="
ipsec leases | grep -v "pool" |grep  "online"
echo "================================================================================================================================"
echo ""
