#!/bin/sh

exec > /root/setup-xidzwrt-v2.log 2>&1

# Script otomatis setup XIDZs-WRT
echo "=== XIDZs-WRT Auto Setup Script v2.0 ==="
echo "Waktu Instalasi: $(date '+%A, %d %B %Y %T')"

# Fungsi untuk logging
log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Fungsi untuk check command success
check_status() {
    if [ $? -eq 0 ]; then
        log "✓ $1 berhasil"
    else
        log "✗ $1 gagal"
    fi
}

# Modifikasi tampilan firmware version
log "Mengkustomisasi tampilan firmware..."
if [ -f "/www/luci-static/resources/view/status/include/10_system.js" ]; then
    sed -i "s#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' / ':'')+(luciversion||''),#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' By Xidz_x':''),#g" /www/luci-static/resources/view/status/include/10_system.js
    check_status "Modifikasi firmware version"
fi

# Ubah icon port menjadi animasi gif
if [ -f "/www/luci-static/resources/view/status/include/29_ports.js" ]; then
    sed -i -E "s|icons/port_%s.png|icons/port_%s.gif|g" /www/luci-static/resources/view/status/include/29_ports.js
    check_status "Modifikasi icon port"
fi

# Deteksi dan konfigurasi firmware
log "Mendeteksi jenis firmware..."
if grep -q "ImmortalWrt" /etc/openwrt_release; then
    sed -i "s/\(DISTRIB_DESCRIPTION='ImmortalWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
    sed -i 's|system/ttyd|services/ttyd|g' /usr/share/luci/menu.d/luci-app-ttyd.json 2>/dev/null
    log "Branch: $(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')"
elif grep -q "OpenWrt" /etc/openwrt_release; then
    sed -i "s/\(DISTRIB_DESCRIPTION='OpenWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release  
    log "Branch: $(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')"
fi

# Setup password root dengan enkripsi yang lebih baik
log "Mengatur password root..."
echo "root:xyyraa" | chpasswd 2>/dev/null
check_status "Setup password root"

# Konfigurasi sistem dasar
log "Mengkonfigurasi sistem dasar..."
uci batch << EOF
set system.@system[0].hostname='XIDZs-WRT'
set system.@system[0].timezone='WIB-7'
set system.@system[0].zonename='Asia/Jakarta'
delete system.ntp.server
add_list system.ntp.server="0.id.pool.ntp.org"
add_list system.ntp.server="1.id.pool.ntp.org"
add_list system.ntp.server="time.google.com"
add_list system.ntp.server="pool.ntp.org"
commit system
EOF
check_status "Konfigurasi sistem"

# Setup bahasa default
log "Mengatur bahasa default..."
uci set luci.@core[0].lang='en'
uci commit luci
check_status "Setup bahasa"

# Konfigurasi network yang lebih robust
log "Mengkonfigurasi network..."
uci batch << EOF
set network.wan=interface
set network.wan.proto='dhcp'
set network.wan.device='usb0'

set network.modem=interface
set network.modem.proto='dhcp'
set network.modem.device='eth1'

set network.rakitan=interface
set network.rakitan.proto='none'
set network.rakitan.device='wwan0'

delete network.wan6
delete network.globals.ula_prefix
commit network
EOF

# Konfigurasi firewall yang lebih aman
uci batch << EOF
set firewall.@defaults[0].input='ACCEPT'
set firewall.@defaults[0].output='ACCEPT'
set firewall.@defaults[0].forward='REJECT'
set firewall.@zone[1].network='wan modem'
commit firewall
EOF
check_status "Konfigurasi network dan firewall"

# Disable IPv6 secara menyeluruh
log "Menonaktifkan IPv6..."
uci batch << EOF
delete dhcp.lan.dhcpv6
delete dhcp.lan.ra
delete dhcp.lan.ndp
commit dhcp
EOF
check_status "Disable IPv6"

# Konfigurasi wireless dengan deteksi yang lebih baik
log "Mengkonfigurasi wireless..."
WIRELESS_COUNT=$(uci show wireless | grep "wifi-device" | wc -l)

if [ "$WIRELESS_COUNT" -gt 0 ]; then
    # Konfigurasi radio 2.4GHz
    uci batch << EOF
set wireless.@wifi-device[0].disabled='0'
set wireless.@wifi-device[0].country='ID'
set wireless.@wifi-device[0].channel='6'
set wireless.@wifi-device[0].htmode='HT40'
set wireless.@wifi-device[0].txpower='20'

set wireless.@wifi-iface[0].disabled='0'
set wireless.@wifi-iface[0].mode='ap'
set wireless.@wifi-iface[0].ssid='XIDZs-WRT'
set wireless.@wifi-iface[0].encryption='none'
set wireless.@wifi-iface[0].hidden='0'
EOF

    # Konfigurasi radio 5GHz jika ada
    if [ "$WIRELESS_COUNT" -gt 1 ]; then
        uci batch << EOF
set wireless.@wifi-device[1].disabled='0'
set wireless.@wifi-device[1].country='ID'
set wireless.@wifi-device[1].channel='149'
set wireless.@wifi-device[1].htmode='VHT80'
set wireless.@wifi-device[1].txpower='23'

set wireless.@wifi-iface[1].disabled='0'
set wireless.@wifi-iface[1].mode='ap'
set wireless.@wifi-iface[1].ssid='XIDZs-WRT_5G'
set wireless.@wifi-iface[1].encryption='none'
set wireless.@wifi-iface[1].hidden='0'
EOF
    fi
    
    uci commit wireless
    
    # Auto restart wifi untuk Raspberry Pi
    if grep -q "Raspberry Pi [34]" /proc/cpuinfo; then
        if ! grep -q "wifi up" /etc/rc.local; then
            sed -i '/exit 0/i # Auto wifi restart for stability' /etc/rc.local
            sed -i '/exit 0/i sleep 15 && wifi up' /etc/rc.local
        fi
        
        # Cron job wifi restart
        if ! grep -q "wifi up" /etc/crontabs/root 2>/dev/null; then
            mkdir -p /etc/crontabs
            echo "# WiFi stability check" >> /etc/crontabs/root
            echo "0 */6 * * * wifi down && sleep 10 && wifi up" >> /etc/crontabs/root
            /etc/init.d/cron restart 2>/dev/null
        fi
    fi
    
    wifi reload && sleep 3 && wifi up
    check_status "Konfigurasi wireless"
else
    log "Tidak ada perangkat wireless yang terdeteksi"
fi

# Optimisasi USB modem
log "Mengoptimalkan konfigurasi USB modem..."
if [ -f "/etc/usb-mode.json" ]; then
    # Hapus config modem yang konflik
    sed -i -e '/12d1:15c1/,+5d' -e '/413c:81d7/,+5d' -e '/12d1:1f01/,+5d' /etc/usb-mode.json
    check_status "Optimisasi USB modem"
fi

# Disable xmm-modem jika ada
if uci -q get xmm-modem.@xmm-modem[0] >/dev/null 2>&1; then
    uci set xmm-modem.@xmm-modem[0].enable='0'
    uci commit xmm-modem
    check_status "Disable xmm-modem"
fi

# Konfigurasi opkg
log "Mengkonfigurasi package manager..."
sed -i 's/option check_signature/# option check_signature/g' /etc/opkg.conf

# Update custom repository
if [ -f "/etc/opkg/customfeeds.conf" ]; then
    rm -f /etc/opkg/customfeeds.conf
fi
ARCH=$(grep "OPENWRT_ARCH" /etc/os-release | awk -F '"' '{print $2}')
echo "src/gz custom_packages https://dl.openwrt.ai/latest/packages/${ARCH}/kiddin9" > /etc/opkg/customfeeds.conf
check_status "Setup repository"

# Setup default theme
log "Mengatur tema default..."
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci
check_status "Setup tema argon"

# Konfigurasi TTYd
log "Mengkonfigurasi TTYd..."
if uci -q get ttyd.@ttyd[0] >/dev/null 2>&1; then
    uci set ttyd.@ttyd[0].command='/bin/bash --login'
    uci commit ttyd
    check_status "Konfigurasi TTYd"
fi

# Setup file manager
log "Mengkonfigurasi file manager..."
if [ -d "/www/tinyfm" ]; then
    ln -s / /www/tinyfm/rootfs 2>/dev/null
    check_status "Setup tinyfm"
fi

# Konfigurasi khusus Amlogic
log "Mengecek konfigurasi Amlogic..."
if opkg list-installed | grep -q luci-app-amlogic; then
    log "Device Amlogic terdeteksi"
    rm -f /etc/profile.d/30-sysinfo.sh
    # Comment LED control untuk manual enable
    sed -i '/exit 0/i #sleep 4 && /usr/bin/k5hgled -r  # uncomment for LED control' /etc/rc.local
    sed -i '/exit 0/i #sleep 4 && /usr/bin/k6hgled -r  # uncomment for LED control' /etc/rc.local
else
    log "Bukan device Amlogic, membersihkan file yang tidak perlu"
    rm -f /usr/bin/k5hgled /usr/bin/k6hgled /usr/bin/k5hgledon /usr/bin/k6hgledon 2>/dev/null
fi

# Setup profile dan permission
log "Mengatur profile dan permission..."
sed -i -e 's/\[ -f \/etc\/banner \] && cat \/etc\/banner/#&/' \
       -e 's/\[ -n "$FAILSAFE" \] && cat \/etc\/banner.failsafe/& || \/usr\/bin\/idz/' /etc/profile

# Set permission dengan pengecekan
[ -d "/usr/lib/ModemManager/connection.d" ] && chmod +x /usr/lib/ModemManager/connection.d/10-report-down 2>/dev/null
find /sbin /usr/bin -type f -exec chmod +x {} \; 2>/dev/null
[ -f "/www/vnstati/vnstati.sh" ] && chmod +x /www/vnstati/vnstati.sh
[ -f "/root/install2.sh" ] && chmod +x /root/install2.sh && /root/install2.sh
check_status "Setup profile dan permission"

# Konfigurasi Netdata
log "Mengkonfigurasi monitoring..."
if [ -d "/usr/share/netdata/web/lib" ]; then
    [ -f "/usr/share/netdata/web/lib/jquery-3.6.0.min.js" ] && \
    mv /usr/share/netdata/web/lib/jquery-3.6.0.min.js /usr/share/netdata/web/lib/jquery-2.2.4.min.js 2>/dev/null
    
    /etc/init.d/netdata restart 2>/dev/null
    check_status "Setup Netdata"
fi

# Setup VnStat
if command -v vnstat >/dev/null 2>&1; then
    mkdir -p /etc/vnstat
    /etc/init.d/vnstat restart 2>/dev/null
    [ -f "/www/vnstati/vnstati.sh" ] && /www/vnstati/vnstati.sh &
    
    # Enable vnstat backup
    [ -f "/etc/init.d/vnstat_backup" ] && chmod +x /etc/init.d/vnstat_backup && /etc/init.d/vnstat_backup enable
    check_status "Setup VnStat"
fi

# TTL Script
log "Mengkonfigurasi TTL..."
[ -f "/root/indowrt.sh" ] && chmod +x /root/indowrt.sh && /root/indowrt.sh &
check_status "Setup TTL"

# Port configuration
log "Mengkonfigurasi port..."
[ -f "/root/addport.sh" ] && chmod +x /root/addport.sh && /root/addport.sh &
check_status "Setup port"

# Konfigurasi tunneling applications dengan error handling
log "Mengkonfigurasi aplikasi tunneling..."
TUNNEL_APPS="luci-app-openclash luci-app-nikki luci-app-passwall"

for pkg in $TUNNEL_APPS; do
    if opkg list-installed | grep -qw "$pkg"; then
        log "$pkg terdeteksi, mengkonfigurasi..."
        case "$pkg" in
            luci-app-openclash)
                # OpenClash configuration
                [ -f "/etc/openclash/core/clash_meta" ] && chmod +x /etc/openclash/core/clash_meta
                [ -f "/etc/openclash/Country.mmdb" ] && chmod +x /etc/openclash/Country.mmdb
                find /etc/openclash -name "Geo*" -exec chmod +x {} \; 2>/dev/null
                
                # Patch OpenClash
                [ -f "/usr/bin/patchoc.sh" ] && bash /usr/bin/patchoc.sh
                
                # Create symlinks
                ln -s /etc/openclash/history/Quenx.db /etc/openclash/cache.db 2>/dev/null
                ln -s /etc/openclash/core/clash_meta /etc/openclash/clash 2>/dev/null
                
                # Cleanup dan backup config
                rm -f /etc/config/openclash
                rm -rf /etc/openclash/custom /etc/openclash/game_rules
                find /etc/openclash/rule_provider -type f ! -name "*.yaml" -exec rm -f {} \; 2>/dev/null
                [ -f "/etc/config/openclash1" ] && mv /etc/config/openclash1 /etc/config/openclash 2>/dev/null
                ;;
                
            luci-app-nikki)
                rm -rf /etc/nikki/run/providers 2>/dev/null
                find /etc/nikki/run -name "Geo*" -exec chmod +x {} \; 2>/dev/null
                
                # Symlink ke OpenClash resources
                ln -s /etc/openclash/proxy_provider /etc/nikki/run/ 2>/dev/null
                ln -s /etc/openclash/rule_provider /etc/nikki/run/ 2>/dev/null
                
                # Alpha config
                sed -i '64s/Enable/Disable/' /etc/config/alpha 2>/dev/null
                sed -i '170s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null
                ;;
                
            luci-app-passwall)
                sed -i '88s/Enable/Disable/' /etc/config/alpha 2>/dev/null
                sed -i '171s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null
                ;;
        esac
    else
        log "$pkg tidak terdeteksi, membersihkan konfigurasi..."
        case "$pkg" in
            luci-app-openclash)
                rm -f /etc/config/openclash1 2>/dev/null
                rm -rf /etc/openclash /usr/share/openclash /usr/lib/lua/luci/view/openclash 2>/dev/null
                ;;
            luci-app-nikki)
                rm -rf /etc/config/nikki /etc/nikki 2>/dev/null
                ;;
            luci-app-passwall)
                rm -f /etc/config/passwall 2>/dev/null
                ;;
        esac
    fi
done

# Konfigurasi web server dan PHP
log "Mengkonfigurasi web server..."
if command -v php-cgi >/dev/null 2>&1; then
    uci batch << EOF
set uhttpd.main.ubus_prefix='/ubus'
set uhttpd.main.interpreter='.php=/usr/bin/php-cgi'
set uhttpd.main.index_page='cgi-bin/luci'
add_list uhttpd.main.index_page='index.html'
add_list uhttpd.main.index_page='index.php'
commit uhttpd
EOF

    # PHP optimization
    if [ -f "/etc/php.ini" ]; then
        sed -i -E "s|memory_limit = [0-9]+M|memory_limit = 128M|g" /etc/php.ini
        sed -i -E "s|display_errors = On|display_errors = Off|g" /etc/php.ini
    fi
    
    # PHP symlinks
    ln -sf /usr/bin/php-cli /usr/bin/php 2>/dev/null
    [ -d /usr/lib/php8 ] && [ ! -d /usr/lib/php ] && ln -sf /usr/lib/php8 /usr/lib/php
    
    /etc/init.d/uhttpd restart
    check_status "Setup web server dan PHP"
else
    log "PHP tidak terinstall, melewati konfigurasi PHP"
fi

# Cleanup dan finalisasi
log "Membersihkan file sementara..."
rm -rf /tmp/luci-* /tmp/*.tmp 2>/dev/null
sync

# Final status
echo ""
echo "=== RINGKASAN SETUP ==="
echo "Hostname: $(uci get system.@system[0].hostname)"
echo "Timezone: $(uci get system.@system[0].zonename)"  
echo "Theme: $(basename $(uci get luci.main.mediaurlbase))"
echo "Wireless: $([ "$WIRELESS_COUNT" -gt 0 ] && echo "Enabled ($WIRELESS_COUNT radio)" || echo "Disabled")"
echo "Firmware: $(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')"
echo ""
log "=== Setup XIDZs-WRT selesai! ==="
log "Silakan reboot untuk menerapkan semua perubahan"

# Cleanup script
rm -f /etc/uci-defaults/$(basename $0) 2>/dev/null

exit 0