#!/bin/sh

# Setup logging dengan timestamp dan status tracking
SCRIPT_VERSION="2.1.0"
LOG_FILE="/root/setup-xidzwrt.log"
STAT_FILE="/root/setup-status.json"

exec > "$LOG_FILE" 2>&1

# Function untuk logging dengan timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function untuk update status
update_status() {
    local step="$1"
    local status="$2"
    local message="$3"
    local current_step_num="$4"
    
    # Create or update status file
    cat > "$STAT_FILE" << EOF
{
    "script_version": "$SCRIPT_VERSION",
    "last_update": "$(date '+%Y-%m-%d %H:%M:%S')",
    "current_step": "$step",
    "current_step_number": $current_step_num,
    "status": "$status",
    "message": "$message",
    "total_steps": 25,
    "progress_percentage": $(( current_step_num * 100 / 25 ))
}
EOF
}

# Function untuk check status
check_stat() {
    if [ -f "$STAT_FILE" ]; then
        cat "$STAT_FILE"
    else
        echo '{"error": "Status file not found", "script_version": "'$SCRIPT_VERSION'"}'
    fi
}

# Jika parameter pertama adalah check_stat, tampilkan status dan keluar
if [ "$1" = "check_stat" ]; then
    check_stat
    exit 0
fi

# Mulai setup
log_message "=== XIDZs-WRT Setup Script v$SCRIPT_VERSION ==="
update_status "initialization" "running" "Starting setup process" 0

# dont remove !!!
log_message "Installed Time: $(date '+%A, %d %B %Y %T')"

# Step 1: Deteksi versi OpenWrt
update_status "detect_version" "running" "Detecting OpenWrt version" 1
OPENWRT_VERSION=$(grep 'DISTRIB_RELEASE=' /etc/openwrt_release | cut -d"'" -f2)
log_message "Detected OpenWrt version: $OPENWRT_VERSION"
update_status "detect_version" "completed" "OpenWrt version: $OPENWRT_VERSION" 1

# Step 2: Patch UI berdasarkan versi
update_status "patch_ui" "running" "Patching UI components" 2
if [ -f "/www/luci-static/resources/view/status/include/10_system.js" ]; then
    sed -i "s#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' / ':'')+(luciversion||''),#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' By Xidz_x':''),#g" /www/luci-static/resources/view/status/include/10_system.js
    log_message "UI system info patched"
fi

if [ -f "/www/luci-static/resources/view/status/include/29_ports.js" ]; then
    sed -i -E "s|icons/port_%s.png|icons/port_%s.gif|g" /www/luci-static/resources/view/status/include/29_ports.js
    log_message "UI ports icons patched"
fi
update_status "patch_ui" "completed" "UI components patched successfully" 2

# Step 3: Update release info
update_status "update_release" "running" "Updating release information" 3
if grep -q "ImmortalWrt" /etc/openwrt_release; then
  sed -i "s/\(DISTRIB_DESCRIPTION='ImmortalWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
  if [ -f "/usr/share/luci/menu.d/luci-app-ttyd.json" ]; then
    sed -i 's|system/ttyd|services/ttyd|g' /usr/share/luci/menu.d/luci-app-ttyd.json
  fi
  log_message "Branch version: $(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')"
elif grep -q "OpenWrt" /etc/openwrt_release; then
  sed -i "s/\(DISTRIB_DESCRIPTION='OpenWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
  log_message "Branch version: $(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')"
fi
update_status "update_release" "completed" "Release information updated" 3

# Step 4: Setup login root password
update_status "setup_password" "running" "Setting up root password" 4
log_message "setup login root password"
(echo "xyyraa"; sleep 2; echo "xyyraa") | passwd > /dev/null 2>&1
update_status "setup_password" "completed" "Root password configured" 4

# Step 5: Setup hostname and timezone
update_status "setup_system" "running" "Configuring hostname and timezone" 5
log_message "setup hostname and timezone to asia/jakarta"
uci set system.@system[0].hostname='XIDZs-WRT'
uci set system.@system[0].timezone='WIB-7'
uci set system.@system[0].zonename='Asia/Jakarta'
uci -q delete system.ntp.server
uci add_list system.ntp.server="pool.ntp.org"
uci add_list system.ntp.server="id.pool.ntp.org"
uci add_list system.ntp.server="time.google.com"
uci commit system
update_status "setup_system" "completed" "System settings configured" 5

# Step 6: Setup bahasa default
update_status "setup_language" "running" "Setting default language" 6
log_message "setup bahasa english default"
uci set luci.@core[0].lang='en'
uci commit luci
update_status "setup_language" "completed" "Default language set to English" 6

# Step 7: Configure wan and lan
update_status "setup_network" "running" "Configuring network interfaces" 7
log_message "configure wan and lan"
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
update_status "setup_network" "completed" "Network interfaces configured" 7

# Step 8: Update firewall config
update_status "setup_firewall" "running" "Configuring firewall" 8
if uci show firewall | grep -q "@zone\[1\]"; then
    uci set firewall.@zone[1].network='wan modem'
    uci commit firewall
    log_message "Firewall zones updated"
fi
update_status "setup_firewall" "completed" "Firewall configured" 8

# Step 9: Disable ipv6 lan
update_status "disable_ipv6" "running" "Disabling IPv6 on LAN" 9
log_message "Disable IPv6 LAN..."
uci -q delete dhcp.lan.dhcpv6
uci -q delete dhcp.lan.ra
uci -q delete dhcp.lan.ndp
uci commit dhcp
update_status "disable_ipv6" "completed" "IPv6 disabled on LAN" 9

# Step 10: Configure wireless device
update_status "setup_wireless" "running" "Configuring wireless devices" 10
log_message "configure wireless device"
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
        log_message "no wireless device detected."
    fi
fi
update_status "setup_wireless" "completed" "Wireless devices configured" 10

# Step 11: Remove huawei me909s and dw5821e usb-modeswitch
update_status "remove_modeswitch" "running" "Removing USB modeswitch entries" 11
log_message "remove huawei me909s and dw5821e usb-modeswitch"
if [ -f /etc/usb-mode.json ]; then
    sed -i -e '/12d1:15c1/,+5d' -e '/413c:81d7/,+5d' /etc/usb-mode.json
fi
update_status "remove_modeswitch" "completed" "USB modeswitch entries removed" 11

# Step 12: Disable xmm-modem
update_status "disable_xmm" "running" "Disabling XMM modem" 12
log_message "disable xmm-modem"
if uci show xmm-modem >/dev/null 2>&1; then
    uci set xmm-modem.@xmm-modem[0].enable='0'
    uci commit xmm-modem
fi
update_status "disable_xmm" "completed" "XMM modem disabled" 12

# Step 13: Disable opkg signature check
update_status "disable_signature" "running" "Disabling OPKG signature check" 13
log_message "disable opkg signature check"
sed -i 's/option check_signature/# option check_signature/g' /etc/opkg.conf
update_status "disable_signature" "completed" "OPKG signature check disabled" 13

# Step 14: Add custom repository
update_status "add_repo" "running" "Adding custom repository" 14
log_message "add custom repository"
ARCH=$(grep "OPENWRT_ARCH" /etc/os-release 2>/dev/null | awk -F '"' '{print $2}')
[ -z "$ARCH" ] && ARCH=$(uname -m)
if [ ! -f /etc/opkg/customfeeds.conf ] || ! grep -q "custom_packages" /etc/opkg/customfeeds.conf; then
    echo "src/gz custom_packages https://dl.openwrt.ai/latest/packages/${ARCH}/kiddin9" >> /etc/opkg/customfeeds.conf
fi
update_status "add_repo" "completed" "Custom repository added" 14

# Step 15: Setup default theme
update_status "setup_theme" "running" "Setting up default theme" 15
log_message "setup tema argon default"
if uci show luci.main >/dev/null 2>&1; then
    uci set luci.main.mediaurlbase='/luci-static/argon'
    uci commit luci
fi
update_status "setup_theme" "completed" "Argon theme set as default" 15

# Step 16: Remove login password ttyd
update_status "setup_ttyd" "running" "Configuring TTYD" 16
log_message "remove login password ttyd"
if uci show ttyd >/dev/null 2>&1; then
    uci set ttyd.@ttyd[0].command='/bin/bash --login'
    uci commit ttyd
fi
update_status "setup_ttyd" "completed" "TTYD configured" 16

# Step 17: Symlink Tinyfm
update_status "setup_tinyfm" "running" "Setting up TinyFM" 17
log_message "symlink tinyfm"
[ -d /www/tinyfm ] && ln -s / /www/tinyfm/rootfs
update_status "setup_tinyfm" "completed" "TinyFM configured" 17

# Step 18: Setup device amlogic
update_status "setup_amlogic" "running" "Configuring Amlogic device" 18
log_message "setup device amlogic"
if opkg list-installed 2>/dev/null | grep -q luci-app-amlogic; then
    log_message "luci-app-amlogic detected."
    rm -f /etc/profile.d/30-sysinfo.sh
    [ -f /etc/rc.local ] || echo -e "#!/bin/sh\nexit 0" > /etc/rc.local
    sed -i '/exit 0/i #sleep 4 && /usr/bin/k5hgled -r' /etc/rc.local
    sed -i '/exit 0/i #sleep 4 && /usr/bin/k6hgled -r' /etc/rc.local
else
    log_message "luci-app-amlogic no detected."
    rm -f /usr/bin/k5hgled /usr/bin/k6hgled /usr/bin/k5hgledon /usr/bin/k6hgledon
fi
update_status "setup_amlogic" "completed" "Amlogic device configured" 18

# Step 19: Setup misc settings and permission
update_status "setup_misc" "running" "Setting up miscellaneous settings" 19
log_message "setup misc settings and permission"
sed -i -e 's/\[ -f \/etc\/banner \] && cat \/etc\/banner/#&/' \
       -e 's/\[ -n "$FAILSAFE" \] && cat \/etc\/banner.failsafe/& || \/usr\/bin\/idz/' /etc/profile
       
[ -f /usr/lib/ModemManager/connection.d/10-report-down ] && chmod +x /usr/lib/ModemManager/connection.d/10-report-down
chmod -R +x /sbin /usr/bin 2>/dev/null
[ -f /root/install2.sh ] && chmod +x /root/install2.sh && /root/install2.sh
update_status "setup_misc" "completed" "Miscellaneous settings configured" 19

# Step 20: Move jquery.min.js
update_status "move_jquery" "running" "Moving jQuery files" 20
log_message "move jquery.min.js"
if [ -f /usr/share/netdata/web/lib/jquery-3.6.0.min.js ]; then
    mv /usr/share/netdata/web/lib/jquery-3.6.0.min.js /usr/share/netdata/web/lib/jquery-2.2.4.min.js
fi
update_status "move_jquery" "completed" "jQuery files moved" 20

# Step 21: Setup Auto Vnstat Database Backup
update_status "setup_vnstat_backup" "running" "Setting up Vnstat backup" 21
log_message "setup auto vnstat database backup"
if [ -f /etc/init.d/vnstat_backup ]; then
    chmod +x /etc/init.d/vnstat_backup && /etc/init.d/vnstat_backup enable
fi
update_status "setup_vnstat_backup" "completed" "Vnstat backup configured" 21

# Step 22: Setup vnstati.sh
update_status "setup_vnstati" "running" "Setting up Vnstati" 22
log_message "setup vnstati.sh"
if [ -f /www/vnstati/vnstati.sh ]; then
    chmod +x /www/vnstati/vnstati.sh && /www/vnstati/vnstati.sh
fi
update_status "setup_vnstati" "completed" "Vnstati configured" 22

# Step 23: Restart netdata and vnstat
update_status "restart_services" "running" "Restarting services" 23
log_message "restart netdata and vnstat"
[ -f /etc/init.d/netdata ] && /etc/init.d/netdata restart
[ -f /etc/init.d/vnstat ] && /etc/init.d/vnstat restart

# add TTL
log_message "add and run script ttl"
[ -f /root/indowrt.sh ] && chmod +x /root/indowrt.sh && /root/indowrt.sh

# add port board.json
log_message "add port board.json"
[ -f /root/addport.sh ] && chmod +x /root/addport.sh && /root/addport.sh
update_status "restart_services" "completed" "Services restarted and scripts executed" 23

# Step 24: Setup tunnel applications
update_status "setup_tunnels" "running" "Configuring tunnel applications" 24
for pkg in luci-app-openclash luci-app-nikki luci-app-passwall; do
    if opkg list-installed 2>/dev/null | grep -qw "$pkg"; then
        log_message "$pkg detected"
        case "$pkg" in
            luci-app-openclash)
                [ -f /etc/openclash/core/clash_meta ] && chmod +x /etc/openclash/core/clash_meta
                [ -f /etc/openclash/Country.mmdb ] && chmod +x /etc/openclash/Country.mmdb
                chmod +x /etc/openclash/Geo* 2>/dev/null
                log_message "patching openclash overview"
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
                log_message "symlink nikki to openclash"
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
        log_message "$pkg no detected"
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
update_status "setup_tunnels" "completed" "Tunnel applications configured" 24

# Step 25: Setup uhttpd and PHP8
update_status "setup_uhttpd_php" "running" "Setting up uHTTPd and PHP8" 25
log_message "setup uhttpd and php8"
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
update_status "setup_uhttpd_php" "completed" "uHTTPd and PHP8 configured" 25

# Final completion
update_status "completed" "success" "All setup completed successfully" 25
log_message "all setup complete"

# Cleanup
rm -rf /etc/uci-defaults/$(basename $0)

exit 0