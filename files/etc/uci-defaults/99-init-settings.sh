#!/bin/sh

exec > /root/setup-xidzwrt.log 2>&1

# dont remove !!!
echo "Installed Time: $(date '+%A, %d %B %Y %T')"

# Deteksi versi OpenWrt
OPENWRT_VERSION=$(grep 'DISTRIB_RELEASE=' /etc/openwrt_release | cut -d"'" -f2)
echo "Detected OpenWrt version: $OPENWRT_VERSION"

# Patch UI berdasarkan versi
if [ -f "/www/luci-static/resources/view/status/include/10_system.js" ]; then
    sed -i "s#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' / ':'')+(luciversion||''),#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' By Xidz_x':''),#g" /www/luci-static/resources/view/status/include/10_system.js
fi

if [ -f "/www/luci-static/resources/view/status/include/29_ports.js" ]; then
    sed -i -E "s|icons/port_%s.png|icons/port_%s.gif|g" /www/luci-static/resources/view/status/include/29_ports.js
fi

# Update release info
if grep -q "ImmortalWrt" /etc/openwrt_release; then
  sed -i "s/\(DISTRIB_DESCRIPTION='ImmortalWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
  if [ -f "/usr/share/luci/menu.d/luci-app-ttyd.json" ]; then
    sed -i 's|system/ttyd|services/ttyd|g' /usr/share/luci/menu.d/luci-app-ttyd.json
  fi
  echo Branch version: "$(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')"
elif grep -q "OpenWrt" /etc/openwrt_release; then
  sed -i "s/\(DISTRIB_DESCRIPTION='OpenWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
  echo Branch version: "$(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')"
fi

# setup login root password
echo "setup login root password"
(echo "xyyraa"; sleep 2; echo "xyyraa") | passwd > /dev/null 2>&1

# setup hostname and timezone
echo "setup hostname and timezone to asia/jakarta"
uci set system.@system[0].hostname='XIDZs-WRT'
uci set system.@system[0].timezone='WIB-7'
uci set system.@system[0].zonename='Asia/Jakarta'
uci -q delete system.ntp.server
uci add_list system.ntp.server="pool.ntp.org"
uci add_list system.ntp.server="id.pool.ntp.org"
uci add_list system.ntp.server="time.google.com"
uci commit system

# setup bahasa default
echo "setup bahasa english default"
uci set luci.@core[0].lang='en'
uci commit luci

# configure wan and lan
echo "configure wan and lan"
uci set network.wan=interface
uci set network.wan.proto='dhcp'

# wan and lan
if uci show network.lan | grep -q "device="; then
    uci set network.wan.device='usb0'
    uci set network.modem=interface
    uci set network.modem.proto='dhcp'
    uci set network.modem.device='eth1'
    uci set network.rakitan=interface
    uci set network.rakitan.proto='none'
    uci set network.rakitan.device='wwan0'
fi

uci -q delete network.wan6
uci commit network

# Update firewall config
if uci show firewall | grep -q "@zone\[1\]"; then
    uci set firewall.@zone[1].network='wan modem'
    uci commit firewall
fi

# disable ipv6 lan
echo "Disable IPv6 LAN..."
uci -q delete dhcp.lan.dhcpv6
uci -q delete dhcp.lan.ra
uci -q delete dhcp.lan.ndp
uci commit dhcp

# configure wireless device
echo "configure wireless device"
if uci show wireless | grep -q "wifi-device"; then
    uci set wireless.@wifi-device[0].disabled='0'
    uci set wireless.@wifi-iface[0].disabled='0'
    uci set wireless.@wifi-device[0].country='ID'
    uci set wireless.@wifi-device[0].htmode='HT40'
    uci set wireless.@wifi-iface[0].mode='ap'
    uci set wireless.@wifi-iface[0].encryption='none'
    
    if grep -q "Raspberry Pi 4\|Raspberry Pi 3" /proc/cpuinfo; then
        if uci show wireless | grep -q "@wifi-device\[1\]"; then
            uci set wireless.@wifi-device[1].disabled='0'
            uci set wireless.@wifi-iface[1].disabled='0'
            uci set wireless.@wifi-device[1].country='ID'
            uci set wireless.@wifi-device[1].channel='149'
            uci set wireless.@wifi-device[1].htmode='VHT80'
            uci set wireless.@wifi-iface[1].mode='ap'
            uci set wireless.@wifi-iface[1].ssid='XIDZs-WRT_5G'
            uci set wireless.@wifi-iface[1].encryption='none'
        fi
    else
        uci set wireless.@wifi-device[0].channel='8'
        uci set wireless.@wifi-iface[0].ssid='XIDZs-WRT'
    fi
    uci commit wireless
    
    # Restart wifi
    if command -v wifi >/dev/null 2>&1; then
        wifi reload && wifi up
    fi
    
    if iw dev 2>/dev/null | grep -q Interface; then
        if grep -q "Raspberry Pi 4\|Raspberry Pi 3" /proc/cpuinfo; then
            if ! grep -q "wifi up" /etc/rc.local 2>/dev/null; then
                [ -f /etc/rc.local ] || echo -e "#!/bin/sh\nexit 0" > /etc/rc.local
                sed -i '/exit 0/i # remove if you dont use wireless' /etc/rc.local
                sed -i '/exit 0/i sleep 10 && wifi up' /etc/rc.local
            fi
            if [ -f /etc/crontabs/root ] && ! grep -q "wifi up" /etc/crontabs/root; then
                echo "# remove if you dont use wireless" >> /etc/crontabs/root
                echo "0 */12 * * * wifi down && sleep 5 && wifi up" >> /etc/crontabs/root
                /etc/init.d/cron restart 2>/dev/null || service cron restart 2>/dev/null
            fi
        fi
    else
        echo "no wireless device detected."
    fi
fi

# remove huawei me909s and dw5821e usb-modeswitch
echo "remove huawei me909s and dw5821e usb-modeswitch"
if [ -f /etc/usb-mode.json ]; then
    sed -i -e '/12d1:15c1/,+5d' -e '/413c:81d7/,+5d' /etc/usb-mode.json
fi

# disable xmm-modem
echo "disable xmm-modem"
if uci show xmm-modem >/dev/null 2>&1; then
    uci set xmm-modem.@xmm-modem[0].enable='0'
    uci commit xmm-modem
fi

# Disable opkg signature check
echo "disable opkg signature check"
sed -i 's/option check_signature/# option check_signature/g' /etc/opkg.conf

# add custom repository
echo "add custom repository"
ARCH=$(grep "OPENWRT_ARCH" /etc/os-release 2>/dev/null | awk -F '"' '{print $2}')
[ -z "$ARCH" ] && ARCH=$(uname -m)
if [ ! -f /etc/opkg/customfeeds.conf ] || ! grep -q "custom_packages" /etc/opkg/customfeeds.conf; then
    echo "src/gz custom_packages https://dl.openwrt.ai/latest/packages/${ARCH}/kiddin9" >> /etc/opkg/customfeeds.conf
fi

# setup default theme
echo "setup tema argon default"
if uci show luci.main >/dev/null 2>&1; then
    uci set luci.main.mediaurlbase='/luci-static/argon'
    uci commit luci
fi

# remove login password ttyd
echo "remove login password ttyd"
if uci show ttyd >/dev/null 2>&1; then
    uci set ttyd.@ttyd[0].command='/bin/bash --login'
    uci commit ttyd
fi

# symlink Tinyfm
echo "symlink tinyfm"
[ -d /www/tinyfm ] && ln -s / /www/tinyfm/rootfs

# setup device amlogic
echo "setup device amlogic"
if opkg list-installed 2>/dev/null | grep -q luci-app-amlogic; then
    echo "luci-app-amlogic detected."
    rm -f /etc/profile.d/30-sysinfo.sh
    [ -f /etc/rc.local ] || echo -e "#!/bin/sh\nexit 0" > /etc/rc.local
    sed -i '/exit 0/i #sleep 4 && /usr/bin/k5hgled -r' /etc/rc.local
    sed -i '/exit 0/i #sleep 4 && /usr/bin/k6hgled -r' /etc/rc.local
else
    echo "luci-app-amlogic no detected."
    rm -f /usr/bin/k5hgled /usr/bin/k6hgled /usr/bin/k5hgledon /usr/bin/k6hgledon
fi

# setup misc settings and permission
echo "setup misc settings and permission"
sed -i -e 's/\[ -f \/etc\/banner \] && cat \/etc\/banner/#&/' \
       -e 's/\[ -n "$FAILSAFE" \] && cat \/etc\/banner.failsafe/& || \/usr\/bin\/idz/' /etc/profile
       
[ -f /usr/lib/ModemManager/connection.d/10-report-down ] && chmod +x /usr/lib/ModemManager/connection.d/10-report-down
chmod -R +x /sbin /usr/bin 2>/dev/null
[ -f /root/install2.sh ] && chmod +x /root/install2.sh && /root/install2.sh

# move jquery.min.js
echo "move jquery.min.js"
if [ -f /usr/share/netdata/web/lib/jquery-3.6.0.min.js ]; then
    mv /usr/share/netdata/web/lib/jquery-3.6.0.min.js /usr/share/netdata/web/lib/jquery-2.2.4.min.js
fi

# setup Auto Vnstat Database Backup
echo "setup auto vnstat database backup"
if [ -f /etc/init.d/vnstat_backup ]; then
    chmod +x /etc/init.d/vnstat_backup && /etc/init.d/vnstat_backup enable
fi

# setup vnstati.sh
echo "setup vnstati.sh"
if [ -f /www/vnstati/vnstati.sh ]; then
    chmod +x /www/vnstati/vnstati.sh && /www/vnstati/vnstati.sh
fi

# restart netdata and vnstat
echo "restart netdata and vnstat"
[ -f /etc/init.d/netdata ] && /etc/init.d/netdata restart
[ -f /etc/init.d/vnstat ] && /etc/init.d/vnstat restart

# add TTL
echo "add and run script ttl"
[ -f /root/indowrt.sh ] && chmod +x /root/indowrt.sh && /root/indowrt.sh

# add port board.json
echo "add port board.json"
[ -f /root/addport.sh ] && chmod +x /root/addport.sh && /root/addport.sh

# setup tunnel installed
for pkg in luci-app-openclash luci-app-nikki luci-app-passwall; do
    if opkg list-installed 2>/dev/null | grep -qw "$pkg"; then
        echo "$pkg detected"
        case "$pkg" in
            luci-app-openclash)
                [ -f /etc/openclash/core/clash_meta ] && chmod +x /etc/openclash/core/clash_meta
                [ -f /etc/openclash/Country.mmdb ] && chmod +x /etc/openclash/Country.mmdb
                chmod +x /etc/openclash/Geo* 2>/dev/null
                echo "patching openclash overview"
                [ -f /usr/bin/patchoc.sh ] && bash /usr/bin/patchoc.sh
                [ -f /etc/rc.local ] && sed -i '/exit 0/i #/usr/bin/patchoc.sh' /etc/rc.local 2>/dev/null
                [ -f /etc/openclash/history/Quenx.db ] && ln -s /etc/openclash/history/Quenx.db /etc/openclash/cache.db
                [ -f /etc/openclash/core/clash_meta ] && ln -s /etc/openclash/core/clash_meta /etc/openclash/clash
                rm -f /etc/config/openclash
                rm -rf /etc/openclash/custom /etc/openclash/game_rules
                rm -f /usr/share/openclash/openclash_version.sh
                [ -d /etc/openclash/rule_provider ] && find /etc/openclash/rule_provider -type f ! -name "*.yaml" -exec rm -f {} \;
                [ -f /etc/config/openclash1 ] && mv /etc/config/openclash1 /etc/config/openclash 2>/dev/null
                ;;
            luci-app-nikki)
                rm -rf /etc/nikki/run/providers
                chmod +x /etc/nikki/run/Geo* 2>/dev/null
                echo "symlink nikki to openclash"
                [ -d /etc/openclash/proxy_provider ] && ln -s /etc/openclash/proxy_provider /etc/nikki/run
                [ -d /etc/openclash/rule_provider ] && ln -s /etc/openclash/rule_provider /etc/nikki/run
                [ -f /etc/config/alpha ] && sed -i '64s/'Enable'/'Disable'/' /etc/config/alpha
                [ -f /usr/lib/lua/luci/view/themes/argon/header.htm ] && sed -i '170s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
                ;;
            luci-app-passwall)
                [ -f /etc/config/alpha ] && sed -i '88s/'Enable'/'Disable'/' /etc/config/alpha
                [ -f /usr/lib/lua/luci/view/themes/argon/header.htm ] && sed -i '171s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
                ;;
        esac
    else
        echo "$pkg no detected"
        case "$pkg" in
            luci-app-openclash)
                rm -f /etc/config/openclash1
                rm -rf /etc/openclash /usr/share/openclash /usr/lib/lua/luci/view/openclash
                [ -f /etc/config/alpha ] && sed -i '104s/'Enable'/'Disable'/' /etc/config/alpha
                if [ -f /usr/lib/lua/luci/view/themes/argon/header.htm ]; then
                    sed -i '167s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
                    sed -i '187s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
                    sed -i '189s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
                fi
                ;;
            luci-app-nikki)
                rm -rf /etc/config/nikki /etc/nikki
                [ -f /etc/config/alpha ] && sed -i '120s/'Enable'/'Disable'/' /etc/config/alpha
                [ -f /usr/lib/lua/luci/view/themes/argon/header.htm ] && sed -i '168s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
                ;;
            luci-app-passwall)
                rm -f /etc/config/passwall
                [ -f /etc/config/alpha ] && sed -i '136s/'Enable'/'Disable'/' /etc/config/alpha
                [ -f /usr/lib/lua/luci/view/themes/argon/header.htm ] && sed -i '169s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
                ;;
        esac
    fi
done

# Setup uhttpd and PHP8
echo "setup uhttpd and php8"
if uci show uhttpd.main >/dev/null 2>&1; then
    uci set uhttpd.main.ubus_prefix='/ubus'
    uci set uhttpd.main.interpreter='.php=/usr/bin/php-cgi'
    uci set uhttpd.main.index_page='cgi-bin/luci'
    uci add_list uhttpd.main.index_page='index.html'
    uci add_list uhttpd.main.index_page='index.php'
    uci commit uhttpd
fi

if [ -f /etc/php.ini ]; then
    sed -i -E "s|memory_limit = [0-9]+M|memory_limit = 128M|g" /etc/php.ini
    sed -i -E "s|display_errors = On|display_errors = Off|g" /etc/php.ini
fi

[ -f /usr/bin/php-cli ] && ln -sf /usr/bin/php-cli /usr/bin/php
[ -d /usr/lib/php8 ] && [ ! -d /usr/lib/php ] && ln -sf /usr/lib/php8 /usr/lib/php
[ -f /etc/init.d/uhttpd ] && /etc/init.d/uhttpd restart

echo "all setup complete"
rm -rf /etc/uci-defaults/$(basename $0)

exit 0