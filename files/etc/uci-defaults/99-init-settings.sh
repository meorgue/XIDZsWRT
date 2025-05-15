#!/bin/sh

exec > /root/setup-xidzwrt.log 2>&1

# dont remove !!!
echo "Installed Time: $(date '+%A, %d %B %Y %T')"
sed -i "s#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' / ':'')+(luciversion||''),#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' By Xidz_x':''),#g" /www/luci-static/resources/view/status/include/10_system.js
sed -i -E "s|icons/port_%s.png|icons/port_%s.gif|g" /www/luci-static/resources/view/status/include/29_ports.js
if grep -q "ImmortalWrt" /etc/openwrt_release; then
  sed -i "s/\(DISTRIB_DESCRIPTION='ImmortalWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
  sed -i 's|system/ttyd|services/ttyd|g' /usr/share/luci/menu.d/luci-app-ttyd.json
  echo Branch version: "$(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')"
elif grep -q "OpenWrt" /etc/openwrt_release; then
  sed -i "s/\(DISTRIB_DESCRIPTION='OpenWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
  echo Branch version: "$(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')"
fi

# setup login root password
echo "setup login root password"
(echo "xyyraa"; sleep 2; echo "xyyraa") | passwd > /dev/null

# setup hostname and timezone
echo "setup hostname and timezone to asia/jakarta"
uci set system.@system[0].hostname='XIDZs-WRT'
uci set system.@system[0].timezone='WIB-7'
uci set system.@system[0].zonename='Asia/Jakarta'
uci delete system.ntp.server
uci add_list system.ntp.server="pool.ntp.org"
uci add_list system.ntp.server="id.pool.ntp.org"
uci add_list system.ntp.server="time.google.com"
uci commit system

# setup bahasa default
echo "setup bahasa english default"
uci set luci.@core[0].lang='en'
uci commit

# configure wan and lan
echo "configure wan and lan"
uci set network.WAN=interface
uci set network.WAN.proto='dhcp'
uci set network.WAN.device='usb0'
uci set network.WAN2=interface
uci set network.WAN2.proto='dhcp'
uci set network.WAN2.device='eth1'
uci set network.MODEM=interface
uci set network.MODEM.proto='none'
uci set network.MODEM.device='wwan0'
delete network.wan6
commit network
uci set firewall.@zone[1].network='WAN WAN2'
uci commit firewall

# disable ipv6 lan
echo "Disable IPv6 LAN..."
uci delete dhcp.lan.dhcpv6
uci delete dhcp.lan.ra
uci delete dhcp.lan.ndp
uci commit dhcp

# configure wiireless device
echo "configure wireless 2.4Ghz"
uci set wireless.@wifi-device[0].disabled='0'
uci set wireless.@wifi-iface[0].disabled='0'
uci set wireless.@wifi-device[0].country='ID'
uci set wireless.@wifi-device[0].htmode='HT40'
uci set wireless.@wifi-iface[0].mode='ap'
uci set wireless.@wifi-iface[0].encryption='none'
if grep -q "Raspberry Pi 4\|Raspberry Pi 3" /proc/cpuinfo; then
  uci set wireless.@wifi-device[1].disabled='0'
  uci set wireless.@wifi-iface[1].disabled='0'
  uci set wireless.@wifi-device[1].country='ID'
  uci set wireless.@wifi-device[1].channel='149'
  uci set wireless.@wifi-device[1].htmode='VHT80'
  uci set wireless.@wifi-iface[1].mode='ap'
  uci set wireless.@wifi-iface[1].ssid='XIDZs-WRT_5G'
  uci set wireless.@wifi-iface[1].encryption='none'
else
  uci set wireless.@wifi-device[0].channel='11'
  uci set wireless.@wifi-iface[0].ssid='XIDZs-WRT'
fi
uci commit wireless
wifi reload && wifi up
if iw dev | grep -q Interface; then
  if grep -q "Raspberry Pi 4\|Raspberry Pi 3" /proc/cpuinfo; then
    if ! grep -q "wifi up" /etc/rc.local; then
      sed -i '/exit 0/i # remove if you dont use wireless' /etc/rc.local
      sed -i '/exit 0/i sleep 10 && wifi up' /etc/rc.local
    fi
    if ! grep -q "wifi up" /etc/crontabs/root; then
      echo "# remove if you dont use wireless" >> /etc/crontabs/root
      echo "0 */12 * * * wifi down && sleep 5 && wifi up" >> /etc/crontabs/root
      service cron restart
    fi
  fi
else
  echo "no wireless device detected."
fi

# remove huawei me909s and dw5821e usb-modeswitch"
echo "remove huawei me909s and dw5821e usb-modeswitch"
sed -i -e '/12d1:15c1/,+5d' -e '/413c:81d7/,+5d' /etc/usb-mode.json

# disable xmm-modem
echo "disable xmm-modem"
uci set xmm-modem.@xmm-modem[0].enable='0'
uci commit xmm-modem

# Disable opkg signature check
echo "disable opkg signature check"
sed -i 's/option check_signature/# option check_signature/g' /etc/opkg.conf

# add custom repository
echo "add custom repository"
echo "src/gz custom_packages https://dl.openwrt.ai/latest/packages/$(grep "OPENWRT_ARCH" /etc/os-release | awk -F '"' '{print $2}')/kiddin9" >> /etc/opkg/customfeeds.conf

# setup default theme
echo "setup tema argon default"
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit

# remove login password ttyd
echo "remove login password ttyd"
uci set ttyd.@ttyd[0].command='/bin/bash --login'
uci commit

# symlink Tinyfm
echo "symlink tinyfm"
ln -s / /www/tinyfm/rootfs

# setup misc settings and permission
echo "setup misc settings and permission"
sed -i -e 's/\[ -f \/etc\/banner \] && cat \/etc\/banner/#&/' \
       -e 's/\[ -n "$FAILSAFE" \] && cat \/etc\/banner.failsafe/& || \/usr\/bin\/idz/' /etc/profile
chmod +x /usr/lib/ModemManager/connection.d/10-report-down
chmod -R +x /sbin /usr/bin
chmod +x /root/install2.sh && bash /root/install2.sh

# move jquery.min.js
echo "move jquery.min.js"
mv /usr/share/netdata/web/lib/jquery-3.6.0.min.js /usr/share/netdata/web/lib/jquery-2.2.4.min.js

# setup Auto Vnstat Database Backup
echo "setup auto vnstat database backup"
chmod +x /etc/init.d/vnstat_backup
bash /etc/init.d/vnstat_backup enable

# setup vnstati.sh
echo "setup vnstati.sh"
chmod +x /www/vnstati/vnstati.sh
bash /www/vnstati/vnstati.sh

# restart netdata and vnstat
echo "restart netdata and vnstat"
/etc/init.d/netdata restart
sleep 2
/etc/init.d/vnstat restart

# remove storage.js
echo "remove storage.js"
rm -f /www/luci-static/resources/view/status/include/25_storage.js

# Setup uhttpd and PHP8
echo "setup uhttpd and php8"
uci set uhttpd.main.ubus_prefix='/ubus'
uci set uhttpd.main.interpreter='.php=/usr/bin/php-cgi'
uci set uhttpd.main.index_page='cgi-bin/luci'
uci add_list uhttpd.main.index_page='index.html'
uci add_list uhttpd.main.index_page='index.php'
uci commit uhttpd
sed -i -E "s|memory_limit = [0-9]+M|memory_limit = 128M|g" /etc/php.ini
sed -i -E "s|display_errors = On|display_errors = Off|g" /etc/php.ini
sed -i -E "s|max_execution_time = [0-9]+|max_execution_time = 120|g" /etc/php.ini
sed -i -E "s|max_input_time = [0-9]+|max_input_time = 120|g" /etc/php.ini
ln -sf /usr/bin/php-cli /usr/bin/php
[ -d /usr/lib/php8 ] && [ ! -d /usr/lib/php ] && ln -sf /usr/lib/php8 /usr/lib/php
echo "restart uhttpd"
/etc/init.d/uhttpd restart

echo "all setup complete"
rm -rf /etc/uci-defaults/$(basename $0)

exit 0