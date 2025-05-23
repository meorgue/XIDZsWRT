#!/bin/sh

exec > /root/setup-xidzwrt.log 2>&1

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Start setup script"

# Fungsi safe sed dengan backup, untuk debugging jika perlu
safe_sed() {
  local file=$1
  shift
  cp "$file" "${file}.bak.$$" 2>/dev/null || true
  sed -i "$@" "$file"
}

# Update firmware version
log "Update firmware version description"
safe_sed /www/luci-static/resources/view/status/include/10_system.js \
  "s#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+'.*#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' By Xidz_x':'')#g"

# Ganti ekstensi port icon .png ke .gif
log "Replace port icons extension"
safe_sed /www/luci-static/resources/view/status/include/29_ports.js \
  -E "s|icons/port_([0-9]+)\.png|icons/port_\1.gif|g"

# Perbaharui openwrt_release sesuai firmware
if grep -q "ImmortalWrt" /etc/openwrt_release 2>/dev/null; then
  log "Detected ImmortalWrt"
  safe_sed /etc/openwrt_release "s/^DISTRIB_DESCRIPTION='ImmortalWrt [0-9.]*.*/DISTRIB_DESCRIPTION='ImmortalWrt'/"
  safe_sed /usr/share/luci/menu.d/luci-app-ttyd.json "s|system/ttyd|services/ttyd|g"
  distrib=$(awk -F"'" '/DISTRIB_DESCRIPTION=/{print $2}' /etc/openwrt_release)
  log "Branch version: $distrib"
elif grep -q "OpenWrt" /etc/openwrt_release 2>/dev/null; then
  log "Detected OpenWrt"
  safe_sed /etc/openwrt_release "s/^DISTRIB_DESCRIPTION='OpenWrt [0-9.]*.*/DISTRIB_DESCRIPTION='OpenWrt'/"
  distrib=$(awk -F"'" '/DISTRIB_DESCRIPTION=/{print $2}' /etc/openwrt_release)
  log "Branch version: $distrib"
else
  log "Unknown firmware, skipping release update"
fi

# Setup password root
log "Setup root password"
(echo "xyyraa"; sleep 1; echo "xyyraa") | passwd root >/dev/null 2>&1 || log "Password setup failed"

# Set hostname dan timezone
log "Set hostname and timezone"
uci batch <<EOF
set system.@system[0].hostname='XIDZs-WRT'
set system.@system[0].timezone='WIB-7'
set system.@system[0].zonename='Asia/Jakarta'
delete system.ntp.@server[-1]
add_list system.ntp.server='pool.ntp.org'
add_list system.ntp.server='id.pool.ntp.org'
add_list system.ntp.server='time.google.com'
commit system
EOF

# Set bahasa luci ke English
log "Set luci language to English"
uci set luci.@core[0].lang='en'
uci commit luci

# Konfigurasi network interfaces
log "Configure network interfaces"
uci batch <<EOF
set network.TETHERING=interface
set network.TETHERING.proto='dhcp'
set network.TETHERING.device='usb0'
set network.WAN=interface
set network.WAN.proto='dhcp'
set network.WAN.device='eth1'
set network.MODEM=interface
set network.MODEM.proto='none'
set network.MODEM.device='wwan0'
delete network.wan6
commit network
set firewall.@zone[1].network='TETHERING WAN'
commit firewall
EOF

# Disable IPv6 pada LAN DHCP
log "Disable IPv6 on LAN DHCP"
uci -q batch <<EOF
delete dhcp.lan.dhcpv6
delete dhcp.lan.ra
delete dhcp.lan.ndp
commit dhcp
EOF

# Setup wireless
log "Setup wireless"
uci set wireless.@wifi-device[0].disabled=0
uci set wireless.@wifi-iface[0].disabled=0
uci set wireless.@wifi-device[0].country='ID'
uci set wireless.@wifi-device[0].htmode='HT40'
uci set wireless.@wifi-iface[0].mode='ap'
uci set wireless.@wifi-iface[0].encryption='none'

if grep -iqE "Raspberry Pi 4|Raspberry Pi 3" /proc/cpuinfo; then
  log "Detected Raspberry Pi 3/4, enable 5GHz"
  uci set wireless.@wifi-device[1].disabled=0
  uci set wireless.@wifi-iface[1].disabled=0
  uci set wireless.@wifi-device[1].country='ID'
  uci set wireless.@wifi-device[1].channel='149'
  uci set wireless.@wifi-device[1].htmode='VHT80'
  uci set wireless.@wifi-iface[1].mode='ap'
  uci set wireless.@wifi-iface[1].ssid='XIDZs-WRT_5G'
  uci set wireless.@wifi-iface[1].encryption='none'
else
  uci set wireless.@wifi-device[0].channel='8'
  uci set wireless.@wifi-iface[0].ssid='XIDZs-WRT'
fi

uci commit wireless

wifi reload 2>/dev/null || /sbin/wifi reload
wifi up 2>/dev/null || /sbin/wifi up

if iw dev | grep -q Interface; then
  if grep -iqE "Raspberry Pi 3|Raspberry Pi 4" /proc/cpuinfo; then
    if ! grep -q "wifi up" /etc/rc.local; then
      sed -i '/exit 0/i # wireless auto-up\nsleep 10 && wifi up' /etc/rc.local
    fi
    if ! grep -q "wifi up" /etc/crontabs/root; then
      echo "# wireless auto-restart" >> /etc/crontabs/root
      echo "0 */12 * * * wifi down && sleep 5 && wifi up" >> /etc/crontabs/root
      /etc/init.d/cron restart || service cron restart
    fi
  fi
else
  log "No wireless interfaces detected"
fi

# Remove usb-modeswitch entries Huawei ME909s dan DW5821E
log "Remove Huawei ME909s and DW5821E usb-modeswitch"
for id in '12d1:15c1' '413c:81d7'; do
  sed -i "/$id/,+5d" /etc/usb-mode.json 2>/dev/null || true
done

# Disable xmm-modem
log "Disable xmm-modem"
if uci show xmm-modem >/dev/null 2>&1; then
  uci set xmm-modem.@xmm-modem[0].enable='0'
  uci commit xmm-modem
fi

# Disable opkg signature check
log "Disable opkg signature check"
sed -i 's/^\s*option check_signature/#&/' /etc/opkg.conf

# Tambah custom repository
log "Add custom opkg repository"
arch=$(awk -F'"' '/OPENWRT_ARCH/ {print $2}' /etc/os-release)
echo "src/gz custom_packages https://dl.openwrt.ai/latest/packages/$arch/kiddin9" >> /etc/opkg/customfeeds.conf

# Set default theme Argon
log "Set luci theme to Argon"
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci

# Remove login password for ttyd
log "Remove login password for ttyd"
uci set ttyd.@ttyd[0].command='/bin/bash --login'
uci commit ttyd

# Symlink Tinyfm rootfs
log "Symlink Tinyfm rootfs"
ln -s / /www/tinyfm/rootfs

# Setup amlogic device if luci-app-amlogic installed
if opkg list-installed | grep -qw luci-app-amlogic; then
  log "luci-app-amlogic detected"
  rm -f /etc/profile.d/30-sysinfo.sh
  sed -i '/exit 0/i #sleep 5 && /usr/bin/k5hgled -r\n#sleep 5 && /usr/bin/k6hgled -r' /etc/rc.local
else
  log "luci-app-amlogic not detected"
  rm -f /usr/bin/k5hgled /usr/bin/k6hgled /usr/bin/k5hgledon /usr/bin/k6hgledon
fi

# Misc setup dan permission
log "Setup misc permissions"
sed -i -e 's/\[ -f \/etc\/banner \] && cat \/etc\/banner/#&/' \
       -e 's/\[ -n "\$FAILSAFE" \] && cat \/etc\/banner.failsafe/& || \/usr\/bin\/idz/' /etc/profile

chmod +x /usr/lib/ModemManager/connection.d/10-report-down 2>/dev/null || true
chmod -R +x /sbin /usr/bin 2>/dev/null || true

# Jalankan install2.sh jika ada
if [ -x /root/install2.sh ]; then
  log "Execute /root/install2.sh"
  /root/install2.sh
fi

# Move jquery versi lama di netdata jika ada
if [ -f /usr/share/netdata/web/lib/jquery-3.6.0.min.js ]; then
  log "Move jquery-3.6.0.min.js to jquery-2.2.4.min.js"
  mv /usr/share/netdata/web/lib/jquery-3.6.0.min.js /usr/share/netdata/web/lib/jquery-2.2.4.min.js
fi

# Setup vnstat backup auto
if [ -x /etc/init.d/vnstat_backup ]; then
  log "Enable vnstat backup"
  chmod +x /etc/init.d/vnstat_backup
  /etc/init.d/vnstat_backup enable
fi

# Setup vnstati
if [ -x /www/vnstati/vnstati.sh ]; then
  log "Run vnstati.sh"
  chmod +x /www/vnstati/vnstati.sh
  /www/vnstati/vnstati.sh
fi

# Restart netdata dan vnstat
log "Restart netdata and vnstat"
/etc/init.d/netdata restart 2>/dev/null || true
/etc/init.d/vnstat restart 2>/dev/null || true

# Jalankan skrip indowrt.sh (TTL)
if [ -x /root/indowrt.sh ]; then
  log "Run /root/indowrt.sh"
  chmod +x /root/indowrt.sh
  /root/indowrt.sh
fi

# Setup aplikasi tunnel: openclash, nikki, passwall
log "Setup tunnel packages"
for pkg in luci-app-openclash luci-app-nikki luci-app-passwall; do
  if opkg list-installed | grep -qw "$pkg"; then
    log "$pkg detected"
    case "$pkg" in
      luci-app-openclash)
        chmod +x /etc/openclash/core/clash_meta /etc/openclash/Country.mmdb /etc/openclash/Geo* 2>/dev/null || true
        if [ -x /usr/bin/patchoc.sh ]; then
          log "Patching openclash overview"
          /usr/bin/patchoc.sh
          sed -i '/exit 0/i #/usr/bin/patchoc.sh' /etc/rc.local 2>/dev/null || true
        fi
        ln -s /etc/openclash/history/Quenx.db /etc/openclash/cache.db 2>/dev/null || true
        ln -s /etc/openclash/core/clash_meta /etc/openclash/clash 2>/dev/null || true
        rm -f /etc/config/openclash
        rm -rf /etc/openclash/custom /etc/openclash/game_rules
        rm -f /usr/share/openclash/openclash_version.sh
        find /etc/openclash/rule_provider -type f ! -name '*.yaml' -exec rm -f {} \; 2>/dev/null || true
        mv /etc/config/openclash1 /etc/config/openclash 2>/dev/null || true
        ;;
      luci-app-nikki)
        rm -rf /etc/nikki/run/providers 2>/dev/null || true
        chmod +x /etc/nikki/run/Geo* 2>/dev/null || true
        log "Symlink nikki to openclash"
        ln -s /etc/openclash/proxy_provider /etc/nikki/run
        ln -s /etc/openclash/rule_provider /etc/nikki/run
        sed -i "64s/'Enable'/'Disable'/" /etc/config/alpha 2>/dev/null || true
        sed -i '170s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null || true
        ;;
      luci-app-passwall)
        sed -i "88s/'Enable'/'Disable'/" /etc/config/alpha 2>/dev/null || true
        sed -i '171s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null || true
        ;;
    esac
  else
    log "$pkg not detected, remove configs"
    case "$pkg" in
      luci-app-openclash)
        rm -f /etc/config/openclash1
        rm -rf /etc/openclash /usr/share/openclash /usr/lib/lua/luci/view/openclash 2>/dev/null || true
        sed -i "104s/'Enable'/'Disable'/" /etc/config/alpha 2>/dev/null || true
        sed -i '167s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null || true
        sed -i '187s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null || true
        sed -i '189s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null || true
        ;;
      luci-app-nikki)
        rm -rf /etc/config/nikki /etc/nikki 2>/dev/null || true
        sed -i "120s/'Enable'/'Disable'/" /etc/config/alpha 2>/dev/null || true
        sed -i '168s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null || true
        ;;
      luci-app-passwall)
        rm -f /etc/config/passwall 2>/dev/null || true
        sed -i "136s/'Enable'/'Disable'/" /etc/config/alpha 2>/dev/null || true
        sed -i '169s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null || true
        ;;
    esac
  fi
done

# Setup uhttpd dan php8
log "Setup uhttpd and PHP8"
uci batch <<EOF
set uhttpd.main.ubus_prefix='/ubus'
set uhttpd.main.interpreter='.php=/usr/bin/php-cgi'
set uhttpd.main.index_page='cgi-bin/luci'
add_list uhttpd.main.index_page='index.html'
add_list uhttpd.main.index_page='index.php'
commit uhttpd
EOF

safe_sed /etc/php.ini \
  -E "s|memory_limit\s*=\s*[0-9]+M|memory_limit = 128M|g" \
  -E "s|display_errors\s*=\s*On|display_errors = Off|g"

ln -sf /usr/bin/php-cli /usr/bin/php

[ -d /usr/lib/php8 ] && [ ! -d /usr/lib/php ] && ln -sf /usr/lib/php8 /usr/lib/php

/etc/init.d/uhttpd restart

log "Setup complete"

rm -f /etc/uci-defaults/$(basename "$0")

exit 0