#!/bin/sh

exec > /root/setup-xidzwrt-v2.log 2>&1

# Script otomatis setup XIDZs-WRT
echo "=== XIDZs-WRT Auto Setup Script v1.0 ==="
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
(echo "xyyraa"; echo "xyyraa") | passwd > /dev/null
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

# Setup network interfaces
log "setup network interface"
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
commit network
EOF

# Safe delete function
safe_delete_and_commit() {
    local config="$1"
    local entries="$2"
    local description="$3"
    local changes=false
    
    for entry in $entries; do
        if uci -q get "${config}.${entry}" >/dev/null 2>&1; then
            uci delete "${config}.${entry}"
            changes=true
            log "${entry} deleted"
        else
            log "${entry} not found"
        fi
    done
    
    if [ "$changes" = true ]; then
        uci commit "$config"
        log "$description committed"
    else
        log "No changes for $description"
    fi
}

# Hapus wan6 jika ada
safe_delete_and_commit "network" "wan6" "network wan6"

# Konfigurasi firewall defaults
if uci -q get firewall.@defaults[0] >/dev/null 2>&1; then
    uci set firewall.@defaults[0].input='ACCEPT'
    uci set firewall.@defaults[0].output='ACCEPT'
    uci set firewall.@defaults[0].forward='REJECT'
    log "Firewall defaults configured"
    firewall_changed=true
else
    log "Firewall defaults not found"
    firewall_changed=false
fi

# Konfigurasi firewall zone
if uci -q get firewall.@zone[1] >/dev/null 2>&1; then
    uci set firewall.@zone[1].network='wan modem'
    log "Firewall zone configured"
    firewall_changed=true
fi

# Commit firewall jika ada perubahan
if [ "$firewall_changed" = true ]; then
    uci commit firewall
fi

check_status "Setup wan and lan"

log "Menonaktifkan IPv6..."
safe_delete_and_commit "dhcp" "lan.dhcpv6 lan.ra lan.ndp" "IPv6 settings"
check_status "Disable IPv6"

# Konfigurasi wireless dengan error handling
log "Mengkonfigurasi wireless..."

# Cek apakah ada wireless device
if [ ! -f "/etc/config/wireless" ] || [ ! -s "/etc/config/wireless" ]; then
    log "File konfigurasi wireless tidak ditemukan, membuat konfigurasi baru..."
    wifi detect > /etc/config/wireless 2>/dev/null
fi

# Konfigurasi wireless dengan pengecekan sederhana
configure_wireless() {
    WIFI_DEVICES=$(uci show wireless | grep "wifi-device" | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1 | sort -u)
    
    if [ -z "$WIFI_DEVICES" ]; then
        log "Tidak ada wireless device yang terdeteksi"
        return 1
    fi
    
    # Konfigurasi setiap device yang ditemukan
    for device in $WIFI_DEVICES; do
        log "Mengkonfigurasi device: $device"
        
        # Set basic device config
        uci set wireless.$device.disabled='0' 2>/dev/null
        uci set wireless.$device.country='ID' 2>/dev/null
        
        # Set channel dan htmode berdasarkan band
        BAND=$(uci get wireless.$device.band 2>/dev/null || uci get wireless.$device.hwmode 2>/dev/null || echo "2g")
        
        if echo "$BAND" | grep -q "5g\|a"; then
            # 5GHz settings
            uci set wireless.$device.channel='149' 2>/dev/null
            uci set wireless.$device.htmode='VHT80' 2>/dev/null
            SSID_SUFFIX="_5G"
        else
            # 2.4GHz settings
            uci set wireless.$device.channel='5' 2>/dev/null
            uci set wireless.$device.htmode='HT40' 2>/dev/null
            SSID_SUFFIX=""
        fi
        
        # Cari interface untuk device ini
        INTERFACES=$(uci show wireless | grep "device='$device'" | cut -d'.' -f2 | cut -d'=' -f1)
        
        for iface in $INTERFACES; do
            log "Mengkonfigurasi interface: $iface"
            uci set wireless.$iface.disabled='0' 2>/dev/null
            uci set wireless.$iface.mode='ap' 2>/dev/null
            uci set wireless.$iface.ssid="XIDZs-WRT${SSID_SUFFIX}" 2>/dev/null
            uci set wireless.$iface.encryption='none' 2>/dev/null
            uci set wireless.$iface.network='lan' 2>/dev/null
        done
    done
    
    return 0
}

# Jalankan konfigurasi
if configure_wireless; then
    # Commit perubahan
    uci commit wireless 2>/dev/null
    check_status "Konfigurasi wireless"
    
    # Restart wireless
    wifi reload 2>/dev/null
    sleep 3
    wifi up 2>/dev/null
    
    # Verifikasi
    sleep 2
    if iw dev 2>/dev/null | grep -q "Interface" || iwconfig 2>/dev/null | grep -q "IEEE"; then
        log "Wireless berhasil aktif"
        
        # Auto restart hanya untuk Raspberry Pi
        if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
            # Tambah ke rc.local jika belum ada
            if [ -f "/etc/rc.local" ] && ! grep -q "wifi up" /etc/rc.local; then
                sed -i '/exit 0/i sleep 10 && wifi up' /etc/rc.local 2>/dev/null
            fi
        fi
        
        check_status "Aktivasi wireless"
    else
        log "Wireless tidak aktif atau tidak ada device"
        check_status "Aktivasi wireless"
    fi
else
    log "Tidak ada wireless device yang dapat dikonfigurasi"
    check_status "Konfigurasi wireless"
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
check_status "Mengkonfigurasi package manager"

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
    sed -i '/exit 0/i #sleep 4 && /usr/bin/k5hgled -r' /etc/rc.local
    sed -i '/exit 0/i #sleep 4 && /usr/bin/k6hgled -r' /etc/rc.local
else
    log "Bukan device Amlogic, membersihkan file yang tidak perlu"
    rm -f /usr/bin/k5hgled /usr/bin/k6hgled /usr/bin/k5hgledon /usr/bin/k6hgledon 2>/dev/null
    check_status "setup device amlogic"
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
    
    # restart netdata
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
check_status "Setup port board.json"

# Konfigurasi tunneling applications dengan error handling
log "Mengkonfigurasi aplikasi tunneling..."
for pkg in luci-app-openclash luci-app-nikki luci-app-passwall; do
  if opkg list-installed | grep -qw "$pkg"; then
    log "$pkg detected"
    case "$pkg" in
      luci-app-openclash)
        chmod +x /etc/openclash/core/clash_meta
        chmod +x /etc/openclash/Country.mmdb
        chmod +x /etc/openclash/Geo* 2>/dev/null
        log "patching openclash overview"
        bash /usr/bin/patchoc.sh
        sed -i '/exit 0/i #/usr/bin/patchoc.sh' /etc/rc.local 2>/dev/null
        ln -s /etc/openclash/history/Quenx.db /etc/openclash/cache.db
        ln -s /etc/openclash/core/clash_meta /etc/openclash/clash
        rm -f /etc/config/openclash
        rm -rf /etc/openclash/custom /etc/openclash/game_rules
        rm -f /usr/share/openclash/openclash_version.sh
        find /etc/openclash/rule_provider -type f ! -name "*.yaml" -exec rm -f {} \;
        mv /etc/config/openclash1 /etc/config/openclash 2>/dev/null
        check_status "konfigure openclash detected"
        ;;
      luci-app-nikki)
        rm -rf /etc/nikki/run/providers
        chmod +x /etc/nikki/run/Geo* 2>/dev/null
        log "symlink nikki to openclash"
        ln -s /etc/openclash/proxy_provider /etc/nikki/run
        ln -s /etc/openclash/rule_provider /etc/nikki/run
        sed -i '64s/'Enable'/'Disable'/' /etc/config/alpha
        sed -i '170s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
        check_status "konfigure nikki detected"
        ;;
      luci-app-passwall)
        sed -i '88s/'Enable'/'Disable'/' /etc/config/alpha
        sed -i '171s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
        check_status "konfigure passwall detected"
        ;;
    esac
  else
    log "$pkg no detected"
    case "$pkg" in
      luci-app-openclash)
        rm -f /etc/config/openclash1
        rm -rf /etc/openclash /usr/share/openclash /usr/lib/lua/luci/view/openclash
        sed -i '104s/'Enable'/'Disable'/' /etc/config/alpha
        sed -i '167s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
        sed -i '187s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
        sed -i '189s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
        check_status "konfigure openclash no detected"
        ;;
      luci-app-nikki)
        rm -rf /etc/config/nikki /etc/nikki
        sed -i '120s/'Enable'/'Disable'/' /etc/config/alpha
        sed -i '168s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
        check_status "konfigure nikki no detected"
        ;;
      luci-app-passwall)
        rm -f /etc/config/passwall
        sed -i '136s/'Enable'/'Disable'/' /etc/config/alpha
        sed -i '169s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
        check_status "konfigure passwall no detected"
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
echo "=== RINGKASAN SETUP ==="
echo "Hostname: $(uci get system.@system[0].hostname)"
echo "Timezone: $(uci get system.@system[0].zonename)"
echo "Firmware: $(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | awk -F"'" '{print $2}')"
echo ""
log "=== Setup XIDZs-WRT selesai! ==="
log "Silakan reboot untuk menerapkan semua perubahan"

# Cleanup script
rm -f /etc/uci-defaults/$(basename $0) 2>/dev/null

exit 0