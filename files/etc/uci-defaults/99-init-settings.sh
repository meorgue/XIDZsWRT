#!/bin/sh

exec >> /root/setup-xidzwrt.log 2>&1

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*"
}

backup_file() {
    [ -f "$1" ] && cp "$1" "$1.bak-$(date +%s)" 2>/dev/null
}

replace_in_file() {
    backup_file "$1"
    sed -i "s/$2/$3/g" "$1"
}

modify_firmware_version() {
    log "Modif Firmware Version di LuCI"
    replace_in_file "/www/luci-static/resources/view/status/include/10_system.js" \
        "_\\('Firmware Version'\\),(L.isObject(boardinfo.release)\\?boardinfo.release.description\\+' / ':\\'\\')\\+(luciversion\\|\\|\\'\\')," \
        "_\\('Firmware Version'\\),(L.isObject(boardinfo.release)\\?boardinfo.release.description\\+' By Xidz_x':\\'\\')"
    backup_file "/www/luci-static/resources/view/status/include/29_ports.js"
    sed -i -E 's|icons/port_%s.png|icons/port_%s.gif|g' /www/luci-static/resources/view/status/include/29_ports.js
}

fix_openwrt_release() {
    f="/etc/openwrt_release"
    log "Membersihkan $f"
    if grep -q ImmortalWrt "$f"; then
        sed -i "s/\(DISTRIB_DESCRIPTION='ImmortalWrt [0-9.]*\).*'/\1'/" "$f"
        sed -i 's|system/ttyd|services/ttyd|' /usr/share/luci/menu.d/luci-app-ttyd.json
        log "Branch: $(awk -F\' '/DISTRIB_DESCRIPTION=/{print $2}' "$f")"
    elif grep -q OpenWrt "$f"; then
        sed -i "s/\(DISTRIB_DESCRIPTION='OpenWrt [0-9.]*\).*'/\1'/" "$f"
        log "Branch: $(awk -F\' '/DISTRIB_DESCRIPTION=/{print $2}' "$f")"
    else
        log "File release tidak dikenali"
    fi
}

set_root_password() {
    log "Set root password 'xyyraa'"
    if command -v chpasswd >/dev/null 2>&1; then
        echo "root:xyyraa" | chpasswd
    else
        echo -e "xyyraa\nxyyraa" | passwd root >/dev/null 2>&1
    fi
}

setup_system_basic() {
    log "Setup hostname, timezone, NTP"
    uci batch <<-EOF
        set system.@system[0].hostname='XIDZs-WRT'
        set system.@system[0].timezone='WIB-7'
        set system.@system[0].zonename='Asia/Jakarta'
        delete system.ntp.server
        add_list system.ntp.server='pool.ntp.org'
        add_list system.ntp.server='id.pool.ntp.org'
        add_list system.ntp.server='time.google.com'
        commit system
EOF
}

setup_luci_language() {
    log "Set bahasa LuCI ke English"
    uci set luci.@core[0].lang='en' && uci commit luci
}

configure_network() {
    log "Konfigurasi network WAN & firewall"
    uci batch <<-EOF
        set network.WAN=interface
        set network.WAN.proto='dhcp'
        set network.WAN.device='usb0'
        set network.WAN2=interface
        set network.WAN2.proto='dhcp'
        set network.WAN2.device='eth1'
        set network.MODEM=interface
        set network.MODEM.proto='none'
        set network.MODEM.device='wwan0'
        delete network.wan6
        commit network
        set firewall.@zone[1].network='WAN WAN2'
        commit firewall
EOF
}

disable_ipv6_lan() {
    log "Disable IPv6 LAN"
    uci batch <<-EOF
        delete dhcp.lan.dhcpv6
        delete dhcp.lan.ra
        delete dhcp.lan.ndp
        commit dhcp
EOF
}

setup_wireless() {
    log "Setup wireless"
    uci set wireless.@wifi-device[0].disabled='0'
    uci set wireless.@wifi-iface[0].disabled='0'
    uci set wireless.@wifi-device[0].country='ID'
    uci set wireless.@wifi-device[0].htmode='HT40'
    uci set wireless.@wifi-iface[0].mode='ap'
    uci set wireless.@wifi-iface[0].encryption='none'

    if grep -qE 'Raspberry Pi (3|4)' /proc/cpuinfo; then
        uci set wireless.@wifi-device[1].disabled='0'
        uci set wireless.@wifi-iface[1].disabled='0'
        uci set wireless.@wifi-device[1].country='ID'
        uci set wireless.@wifi-device[1].channel='149'
        uci set wireless.@wifi-device[1].htmode='VHT80'
        uci set wireless.@wifi-iface[1].mode='ap'
        uci set wireless.@wifi-iface[1].ssid='XIDZs-WRT_5G'
        uci set wireless.@wifi-iface[1].encryption='none'
    else
        uci set wireless.@wifi-device[0].channel='5'
        uci set wireless.@wifi-iface[0].ssid='XIDZs-WRT'
    fi

    uci commit wireless
    wifi reload && wifi up

    if iw dev | grep -q Interface && grep -qE 'Raspberry Pi (3|4)' /proc/cpuinfo; then
        grep -q 'wifi up' /etc/rc.local || sed -i '/exit 0/i #wifi up\nsleep 10 && wifi up' /etc/rc.local
        grep -q 'wifi up' /etc/crontabs/root || {
            echo '#wifi up' >> /etc/crontabs/root
            echo '0 */12 * * * wifi down && sleep 5 && wifi up' >> /etc/crontabs/root
            service cron restart
        }
    elif ! iw dev | grep -q Interface; then
        log "Tidak ada wireless device"
    fi
}

remove_usb_modeswitch() {
    log "Remove USB modeswitch rules"
    sed -i -e '/12d1:15c1/,+5d' -e '/413c:81d7/,+5d' /etc/usb-mode.json
}

disable_xmm_modem() {
    log "Disable xmm-modem"
    uci set xmm-modem.@xmm-modem[0].enable='0' && uci commit xmm-modem
}

disable_opkg_signature() {
    log "Disable opkg signature check"
    sed -i 's/option check_signature/#&/' /etc/opkg.conf
}

add_custom_opkg_feed() {
    arch=$(awk -F '"' '/OPENWRT_ARCH/ {print $2}' /etc/os-release)
    log "Tambah custom feed untuk arch=$arch"
    echo "src/gz custom_packages https://dl.openwrt.ai/latest/packages/$arch/kiddin9" >> /etc/opkg/customfeeds.conf
}

set_luci_theme_argon() {
    log "Set tema LuCI Argon"
    uci set luci.main.mediaurlbase='/luci-static/argon' && uci commit luci
}

remove_ttyd_password() {
    log "Remove ttyd password"
    uci set ttyd.@ttyd[0].command='/bin/bash --login' && uci commit ttyd
}

symlink_tinyfm_rootfs() {
    log "Buat symlink tinyfm"
    ln -s / /www/tinyfm/rootfs
}

amlogic_device_setup() {
    log "Setup amlogic device"
    if opkg list-installed | grep -q luci-app-amlogic; then
        log "luci-app-amlogic ditemukan"
        rm -f /etc/profile.d/30-sysinfo.sh
        sed -i '/exit 0/i #sleep 5 && /usr/bin/k5hgled -r\n#sleep 5 && /usr/bin/k6hgled -r' /etc/rc.local
    else
        log "luci-app-amlogic tidak ditemukan"
        rm -f /usr/bin/k5hgled /usr/bin/k6hgled /usr/bin/k5hgledon /usr/bin/k6hgledon
    fi
}

set_misc_permissions() {
    log "Set permissions & modif /etc/profile"
    sed -i -e 's/\[ -f \/etc\/banner \] && cat \/etc\/banner/#&/' \
           -e 's/\[ -n "$FAILSAFE" \] && cat \/etc\/banner.failsafe/& || \/usr\/bin\/idz/' /etc/profile
    chmod +x /usr/lib/ModemManager/connection.d/10-report-down
    chmod -R +x /sbin /usr/bin
}

run_install2_script() {
    [ -x /root/install2.sh ] && { log "Jalankan /root/install2.sh"; /root/install2.sh; }
}

move_jquery_version() {
    log "Ganti jquery ke versi lama di netdata"
    mv /usr/share/netdata/web/lib/jquery-3.6.0.min.js /usr/share/netdata/web/lib/jquery-2.2.4.min.js
}

setup_vnstat_backup() {
    log "Aktifkan vnstat backup"
    chmod +x /etc/init.d/vnstat_backup
    /etc/init.d/vnstat_backup enable
}

setup_vnstati_script() {
    log "Setup & jalankan vnstati"
    chmod +x /www/vnstati/vnstati.sh
    /www/vnstati/vnstati.sh
}

restart_netdata_vnstat() {
    log "Restart netdata & vnstat"
    /etc/init.d/netdata restart
    sleep 2
    /etc/init.d/vnstat restart
}

configure_tunnel_apps() {
    for pkg in luci-app-openclash luci-app-nikki luci-app-passwall; do
        if opkg list-installed | grep -qw "$pkg"; then
            log "$pkg terdeteksi, konfigurasi"
            case "$pkg" in
                luci-app-openclash)
                    chmod +x /etc/openclash/core/clash_meta /etc/openclash/Country.mmdb
                    chmod +x /etc/openclash/Geo* 2>/dev/null
                    log "Patch openclash"
                    bash /usr/bin/patchoc.sh
                    sed -i '/exit 0/i #/usr/bin/patchoc.sh' /etc/rc.local 2>/dev/null
                    ln -s /etc/openclash/history/Quenx.db /etc/openclash/cache.db
                    ln -s /etc/openclash/core/clash_meta /etc/openclash/clash
                    rm -rf /etc/openclash/custom /etc/openclash/game_rules
                    rm -f /etc/config/openclash
                    find /etc/openclash/rule_provider -type f ! -name '*.yaml' -exec rm -f {} \;
                    mv /etc/config/openclash1 /etc/config/openclash 2>/dev/null
                    ;;
                luci-app-nikki)
                    rm -rf /etc/nikki/run/providers
                    chmod +x /etc/nikki/run/Geo* 2>/dev/null
                    log "Symlink nikki ke openclash"
                    ln -s /etc/openclash/proxy_provider /etc/nikki/run
                    ln -s /etc/openclash/rule_provider /etc/nikki/run
                    sed -i -e '64s/Enable/Disable/' /etc/config/alpha
                    sed -i -e '170s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
                    ;;
                luci-app-passwall)
                    sed -i -e '88s/Enable/Disable/' /etc/config/alpha
                    sed -i -e '171s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
                    ;;
            esac
        else
            log "$pkg tidak terdeteksi, hapus konfigurasi"
            case "$pkg" in
                luci-app-openclash)
                    rm -f /etc/config/openclash1
                    rm -rf /etc/openclash /usr/share/openclash /usr/lib/lua/luci/view/openclash
                    sed -i -e '104s/Enable/Disable/' /etc/config/alpha
                    sed -i -e '167s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
                    sed -i -e '187s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
                    sed -i -e '189s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
                    ;;
                luci-app-nikki)
                    rm -rf /etc/config/nikki /etc/nikki
                    sed -i -e '120s/Enable/Disable/' /etc/config/alpha
                    sed -i -e '168s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
                    ;;
                luci-app-passwall)
                    rm -f /etc/config/passwall
                    sed -i -e '136s/Enable/Disable/' /etc/config/alpha
                    sed -i -e '169s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm
                    ;;
            esac
        fi
    done
}

setup_uhttpd_php8() {
    log "Setup uhttpd & PHP8"
    uci batch <<-EOF
        set uhttpd.main.ubus_prefix='/ubus'
        set uhttpd.main.interpreter='.php=/usr/bin/php-cgi'
        set uhttpd.main.index_page='cgi-bin/luci'
        add_list uhttpd.main.index_page='index.html'
        add_list uhttpd.main.index_page='index.php'
        commit uhttpd
EOF
    [ -f /etc/php.ini ] && sed -i \
        -e 's/memory_limit = [0-9]\+M/memory_limit = 128M/' \
        -e 's/display_errors = On/display_errors = Off/' /etc/php.ini
    ln -sf /usr/bin/php-cli /usr/bin/php
    [ -d /usr/lib/php8 -a ! -d /usr/lib/php ] && ln -sf /usr/lib/php8 /usr/lib/php
    /etc/init.d/uhttpd restart
}

main() {
    log "Mulai setup Xidz_WRT"
    modify_firmware_version
    fix_openwrt_release
    set_root_password
    setup_system_basic
    setup_luci_language
    configure_network
    disable_ipv6_lan
    setup_wireless
    remove_usb_modeswitch
    disable_xmm_modem
    disable_opkg_signature
    add_custom_opkg_feed
    set_luci_theme_argon
    remove_ttyd_password
    symlink_tinyfm_rootfs
    amlogic_device_setup
    set_misc_permissions
    run_install2_script
    move_jquery_version
    setup_vnstat_backup
    setup_vnstati_script
    restart_netdata_vnstat
    configure_tunnel_apps
    setup_uhttpd_php8
    log "Setup Xidz_WRT selesai"
    rm -f /etc/uci-defaults/$(basename "$0")
}

main "$@"