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

# Fungsi untuk cek interface ada atau tidak
interface_exists() {
    [ -d "/sys/class/net/$1" ]
}

# Fungsi untuk backup config
backup_config() {
    local config=$1
    cp "/etc/config/$config" "/etc/config/${config}.backup.$(date +%s)" 2>/dev/null
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

# Setup password root
log "Mengatur password root..."
(echo "xyyraa"; echo "xyyraa") | passwd > /dev/null 2>&1
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
uci set luci.@core[0].lang='en' 2>/dev/null
uci commit luci 2>/dev/null
check_status "Setup bahasa"

# konfigurasi network interfaces
log "Mengecek file konfigurasi network..."
if [ -f "/etc/config/network" ]; then
    log "File /etc/config/network ditemukan"
    
    log "Konfigurasi WAN interface (usb0)..."
    uci set network.wan=interface 2>/dev/null
    uci set network.wan.proto='dhcp' 2>/dev/null
    uci set network.wan.device='usb0' 2>/dev/null
    check_status "Konfigurasi WAN"

    log "Konfigurasi modem interface (eth1)..."
    uci set network.modem=interface 2>/dev/null
    uci set network.modem.proto='dhcp' 2>/dev/null
    uci set network.modem.device='eth1' 2>/dev/null
    check_status "Konfigurasi modem"

    log "Konfigurasi rakitan interface (wwan0)..."
    uci set network.rakitan=interface 2>/dev/null
    uci set network.rakitan.proto='none' 2>/dev/null
    uci set network.rakitan.device='wwan0' 2>/dev/null
    check_status "Konfigurasi rakitan"

    log "Menghapus konfigurasi IPv6 WAN..."
    uci delete network.wan6 2>/dev/null
    check_status "Hapus IPv6 WAN"
    
    log "Menyimpan konfigurasi network..."
    uci commit network 2>/dev/null
    check_status "Commit network config"
else
    log "File /etc/config/network tidak ditemukan"
fi

# konfigurasi firewall
log "Mengecek file konfigurasi firewall..."
if [ -f "/etc/config/firewall" ]; then
    log "File /etc/config/firewall ditemukan"
    
    log "Mengatur firewall defaults..."
    uci set firewall.@defaults[0].input='ACCEPT' 2>/dev/null
    check_status "Set firewall input ACCEPT"
    
    uci set firewall.@defaults[0].output='ACCEPT' 2>/dev/null
    check_status "Set firewall output ACCEPT"
    
    uci set firewall.@defaults[0].forward='REJECT' 2>/dev/null
    check_status "Set firewall forward REJECT"
    
    log "Mengatur zone WAN untuk interface wan, modem..."
    uci set firewall.@zone[1].network='wan modem' 2>/dev/null
    check_status "Set WAN zone"
    
    log "Menyimpan konfigurasi firewall..."
    uci commit firewall 2>/dev/null
    check_status "Commit firewall config"
else
    log "File /etc/config/firewall tidak ditemukan"
fi

# Disable IPv6 LAN
log "Mengecek file konfigurasi DHCP..."
if [ -f "/etc/config/dhcp" ]; then
    log "File /etc/config/dhcp ditemukan"
    
    log "Menonaktifkan DHCPv6..."
    uci delete dhcp.lan.dhcpv6 2>/dev/null
    check_status "Disable DHCPv6"
    
    log "Menonaktifkan Router Advertisement..."
    uci delete dhcp.lan.ra 2>/dev/null
    check_status "Disable RA"
    
    log "Menonaktifkan NDP..."
    uci delete dhcp.lan.ndp 2>/dev/null
    check_status "Disable NDP"
    
    log "Menyimpan konfigurasi DHCP..."
    uci commit dhcp 2>/dev/null
    check_status "Commit DHCP config"
else
    log "File /etc/config/dhcp tidak ditemukan"
fi

log "Konfigurasi network selesai"

# konfigurasi wireless device
log "konfigurasi wireless device..."
# 2.4GHz Generic
uci set wireless.@wifi-device[0].disabled='0' 2>/dev/null; check_status "Enable device 0"
uci set wireless.@wifi-iface[0].disabled='0' 2>/dev/null; check_status "Enable interface 0"
uci set wireless.@wifi-device[0].country='ID' 2>/dev/null; check_status "Country ID"
uci set wireless.@wifi-device[0].htmode='HT40' 2>/dev/null; check_status "HT40 mode"
uci set wireless.@wifi-iface[0].mode='ap' 2>/dev/null; check_status "AP mode"
uci set wireless.@wifi-iface[0].encryption='none' 2>/dev/null; check_status "No encryption"
uci set wireless.@wifi-device[0].channel='5' 2>/dev/null; check_status "Channel 5"
uci set wireless.@wifi-iface[0].ssid='XIDZs-WRT' 2>/dev/null; check_status "SSID XIDZs-WRT"

# 5GHz for Raspberry Pi
if grep -q "Raspberry Pi 4\|Raspberry Pi 3" /proc/cpuinfo; then
    log "Raspberry Pi detected, konfigurasi 5GHz..."
    uci set wireless.@wifi-device[1].disabled='0' 2>/dev/null; check_status "Enable device 1"
    uci set wireless.@wifi-iface[1].disabled='0' 2>/dev/null; check_status "Enable interface 1"
    uci set wireless.@wifi-device[1].country='ID' 2>/dev/null; check_status "Country ID 5GHz"
    uci set wireless.@wifi-device[1].channel='149' 2>/dev/null; check_status "Channel 149"
    uci set wireless.@wifi-device[1].htmode='VHT80' 2>/dev/null; check_status "VHT80 mode"
    uci set wireless.@wifi-iface[1].mode='ap' 2>/dev/null; check_status "AP mode 5GHz"
    uci set wireless.@wifi-iface[1].ssid='XIDZs-WRT_5G' 2>/dev/null; check_status "SSID 5G"
    uci set wireless.@wifi-iface[1].encryption='none' 2>/dev/null; check_status "No encryption 5GHz"
fi

# Apply and start
uci commit wireless 2>/dev/null; check_status "Save config"
wifi reload 2>/dev/null; check_status "WiFi reload"
wifi up 2>/dev/null; check_status "WiFi up"

sleep 3
if iw dev 2>/dev/null | grep -q Interface; then
    log "✓ Wireless active"
    
    if grep -q "Raspberry Pi 4\|Raspberry Pi 3" /proc/cpuinfo; then
        if ! grep -q "wifi up" /etc/rc.local 2>/dev/null; then
            sed -i '/exit 0/i # remove if you dont use wireless' /etc/rc.local 2>/dev/null; check_status "Add rc.local comment"
            sed -i '/exit 0/i sleep 10 && wifi up' /etc/rc.local 2>/dev/null; check_status "Add rc.local wifi"
        fi
        
        if ! grep -q "wifi up" /etc/crontabs/root 2>/dev/null; then
            echo "# remove if you dont use wireless" >> /etc/crontabs/root 2>/dev/null; check_status "Add cron comment"
            echo "0 */12 * * * wifi down && sleep 5 && wifi up" >> /etc/crontabs/root 2>/dev/null; check_status "Add cron job"
            /etc/init.d/cron restart 2>/dev/null; check_status "Restart cron"
        fi
    fi
else
    log "✗ No wireless device detected"
fi

log "Wireless configuration complete!"

# Optimisasi USB modem
log "Mengoptimalkan konfigurasi USB modem..."
if [ -f "/etc/usb-mode.json" ]; then
    # Hapus config modem yang bermasalah
    sed -i -e '/12d1:15c1/,+5d' -e '/413c:81d7/,+5d' -e '/12d1:1f01/,+5d' /etc/usb-mode.json 2>/dev/null
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
sed -i 's/option check_signature/# option check_signature/g' /etc/opkg.conf 2>/dev/null
check_status "Konfigurasi package manager"

# Update repository
log "Mengatur repository..."
if [ -f "/etc/opkg/customfeeds.conf" ]; then
    rm -f /etc/opkg/customfeeds.conf
fi
ARCH=$(grep "OPENWRT_ARCH" /etc/os-release 2>/dev/null | awk -F '"' '{print $2}')
[ -n "$ARCH" ] && echo "src/gz custom_packages https://dl.openwrt.ai/latest/packages/${ARCH}/kiddin9" > /etc/opkg/customfeeds.conf
check_status "Setup repository"

# Setup tema default
log "Mengatur tema default..."
uci set luci.main.mediaurlbase='/luci-static/argon' 2>/dev/null
uci commit luci 2>/dev/null
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
    ln -sf / /www/tinyfm/rootfs 2>/dev/null
    check_status "Setup tinyfm"
fi

# Konfigurasi khusus Amlogic
log "Mengecek konfigurasi device..."
if opkg list-installed 2>/dev/null | grep -q luci-app-amlogic; then
    log "Device Amlogic terdeteksi"
    rm -f /etc/profile.d/30-sysinfo.sh 2>/dev/null
    if [ -f "/etc/rc.local" ] && ! grep -q "hgled" /etc/rc.local; then
        sed -i '/exit 0/i #sleep 4 && /usr/bin/k5hgled -r' /etc/rc.local 2>/dev/null
        sed -i '/exit 0/i #sleep 4 && /usr/bin/k6hgled -r' /etc/rc.local 2>/dev/null
    fi
    check_status "Konfigurasi Amlogic"
else
    log "Device non-Amlogic, bersihkan file yang tidak perlu"
    rm -f /usr/bin/k5hgled /usr/bin/k6hgled /usr/bin/k5hgledon /usr/bin/k6hgledon 2>/dev/null
    check_status "Cleanup device files"
fi

# Setup profile dan permission
log "Mengatur profile dan permission..."
# Update profile
if [ -f "/etc/profile" ]; then
    sed -i -e 's/\[ -f \/etc\/banner \] && cat \/etc\/banner/#&/' \
           -e 's/\[ -n "$FAILSAFE" \] && cat \/etc\/banner.failsafe/& || \/usr\/bin\/idz/' /etc/profile 2>/dev/null
fi

# Set permission dengan pengecekan yang lebih aman
[ -d "/usr/lib/ModemManager/connection.d" ] && chmod +x /usr/lib/ModemManager/connection.d/10-report-down 2>/dev/null
find /sbin /usr/bin -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null
[ -f "/www/vnstati/vnstati.sh" ] && chmod +x /www/vnstati/vnstati.sh 2>/dev/null

# Jalankan installer tambahan
if [ -f "/root/install2.sh" ]; then
    chmod +x /root/install2.sh 2>/dev/null
    /root/install2.sh &
    log "Menjalankan installer tambahan"
fi
check_status "Setup profile dan permission"

# Konfigurasi monitoring services
log "Mengkonfigurasi layanan monitoring..."

# Netdata
if [ -d "/usr/share/netdata/web/lib" ]; then
    if [ -f "/usr/share/netdata/web/lib/jquery-3.6.0.min.js" ]; then
        mv /usr/share/netdata/web/lib/jquery-3.6.0.min.js /usr/share/netdata/web/lib/jquery-2.2.4.min.js 2>/dev/null
    fi
    /etc/init.d/netdata restart >/dev/null 2>&1 &
    check_status "Setup Netdata"
fi

# VnStat
if command -v vnstat >/dev/null 2>&1; then
    mkdir -p /etc/vnstat
    /etc/init.d/vnstat restart >/dev/null 2>&1
    [ -f "/www/vnstati/vnstati.sh" ] && /www/vnstati/vnstati.sh >/dev/null 2>&1 &
    [ -f "/etc/init.d/vnstat_backup" ] && {
        chmod +x /etc/init.d/vnstat_backup 2>/dev/null
        /etc/init.d/vnstat_backup enable 2>/dev/null
    }
    check_status "Setup VnStat"
fi

# Scripts tambahan
log "Menjalankan script tambahan..."
[ -f "/root/indowrt.sh" ] && { chmod +x /root/indowrt.sh 2>/dev/null; /root/indowrt.sh >/dev/null 2>&1 & }
[ -f "/root/addport.sh" ] && { chmod +x /root/addport.sh 2>/dev/null; /root/addport.sh >/dev/null 2>&1 & }
check_status "Eksekusi script tambahan"

# Konfigurasi tunneling applications
log "Mengkonfigurasi aplikasi tunneling..."
for pkg in luci-app-openclash luci-app-nikki luci-app-passwall; do
    if opkg list-installed 2>/dev/null | grep -qw "$pkg"; then
        log "$pkg terdeteksi"
        case "$pkg" in
            luci-app-openclash)
                [ -f "/etc/openclash/core/clash_meta" ] && chmod +x /etc/openclash/core/clash_meta
                [ -f "/etc/openclash/Country.mmdb" ] && chmod +x /etc/openclash/Country.mmdb
                find /etc/openclash -name "Geo*" -exec chmod +x {} \; 2>/dev/null
                
                # Patch OpenClash
                [ -f "/usr/bin/patchoc.sh" ] && {
                    bash /usr/bin/patchoc.sh >/dev/null 2>&1
                    if [ -f "/etc/rc.local" ] && ! grep -q "patchoc.sh" /etc/rc.local; then
                        sed -i '/exit 0/i #/usr/bin/patchoc.sh' /etc/rc.local 2>/dev/null
                    fi
                }
                
                # Symlinks dan cleanup
                [ -f "/etc/openclash/history/Quenx.db" ] && ln -sf /etc/openclash/history/Quenx.db /etc/openclash/cache.db 2>/dev/null
                [ -f "/etc/openclash/core/clash_meta" ] && ln -sf /etc/openclash/core/clash_meta /etc/openclash/clash 2>/dev/null
                
                # Cleanup dan restore config
                rm -f /etc/config/openclash 2>/dev/null
                rm -rf /etc/openclash/custom /etc/openclash/game_rules 2>/dev/null
                rm -f /usr/share/openclash/openclash_version.sh 2>/dev/null
                find /etc/openclash/rule_provider -type f ! -name "*.yaml" -exec rm -f {} \; 2>/dev/null
                [ -f "/etc/config/openclash1" ] && mv /etc/config/openclash1 /etc/config/openclash 2>/dev/null
                
                check_status "Konfigurasi OpenClash"
                ;;
            luci-app-nikki)
                rm -rf /etc/nikki/run/providers 2>/dev/null
                find /etc/nikki/run -name "Geo*" -exec chmod +x {} \; 2>/dev/null
                
                # Symlinks
                [ -d "/etc/openclash/proxy_provider" ] && ln -sf /etc/openclash/proxy_provider /etc/nikki/run/ 2>/dev/null
                [ -d "/etc/openclash/rule_provider" ] && ln -sf /etc/openclash/rule_provider /etc/nikki/run/ 2>/dev/null
                
                # Update config
                sed -i '64s/Enable/Disable/' /etc/config/alpha 2>/dev/null
                sed -i '170s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null
                
                check_status "Konfigurasi Nikki"
                ;;
            luci-app-passwall)
                sed -i '88s/Enable/Disable/' /etc/config/alpha 2>/dev/null
                sed -i '171s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null
                check_status "Konfigurasi Passwall"
                ;;
        esac
    else
        case "$pkg" in
            luci-app-openclash)
                # Cleanup OpenClash
                rm -f /etc/config/openclash1 2>/dev/null
                rm -rf /etc/openclash /usr/share/openclash /usr/lib/lua/luci/view/openclash 2>/dev/null
                sed -i -e '104s/Enable/Disable/' -e '167s#.*#<!-- & -->#' -e '187s#.*#<!-- & -->#' -e '189s#.*#<!-- & -->#' /etc/config/alpha 2>/dev/null
                sed -i -e '167s#.*#<!-- & -->#' -e '187s#.*#<!-- & -->#' -e '189s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null
                ;;
            luci-app-nikki)
                rm -rf /etc/config/nikki /etc/nikki 2>/dev/null
                sed -i '120s/Enable/Disable/' /etc/config/alpha 2>/dev/null
                sed -i '168s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null
                ;;
            luci-app-passwall)
                rm -f /etc/config/passwall 2>/dev/null
                sed -i '136s/Enable/Disable/' /etc/config/alpha 2>/dev/null
                sed -i '169s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null
                ;;
        esac
        check_status "Cleanup $pkg"
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
        sed -i "s|display_errors = Off|display_errors = On|g" /etc/php.ini 2>/dev/null
    fi
    
    /etc/init.d/uhttpd restart >/dev/null 2>&1
    check_status "Konfigurasi web server dan PHP"
fi

# Restart services untuk memastikan konfigurasi diterapkan
log "Restarting services..."
/etc/init.d/network restart >/dev/null 2>&1 &
sleep 2
/etc/init.d/firewall restart >/dev/null 2>&1 &
/etc/init.d/dnsmasq restart >/dev/null 2>&1 &

# Summary
log "=== RINGKASAN KONFIGURASI ==="
log "Hostname: $(uci get system.@system[0].hostname 2>/dev/null)"
log "LAN IP: $(uci get network.lan.ipaddr 2>/dev/null)"
log "WAN Device: $(uci get network.wan.device 2>/dev/null)"
[ "$(uci get network.modem 2>/dev/null)" = "interface" ] && log "Modem Device: $(uci get network.modem.device 2>/dev/null)"
log "Wireless devices: $(uci show wireless | grep -c "wifi-device")"
log "Password: xyyraa"
log "=== SETUP SELESAI ==="
log "Reboot disarankan untuk memastikan semua konfigurasi diterapkan"

exit 0