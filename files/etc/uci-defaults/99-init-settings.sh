#!/bin/sh

# XIDZs-WRT Setup Script v2.0

# Logging setup
LOGFILE="/root/setup-xidzwrt-v2.log"
exec > "$LOGFILE" 2>&1

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Safe UCI operations
safe_uci_set() {
    if uci get "$1" >/dev/null 2>&1; then
        uci set "$1=$2"
        return 0
    else
        log_warn "UCI path $1 does not exist, skipping"
        return 1
    fi
}

# Detect OpenWrt version and variant
detect_system() {
    log "Detecting system information..."
    
    if [ -f "/etc/os-release" ]; then
        . /etc/os-release
        DISTRIB_ID="$ID"
        DISTRIB_RELEASE="$VERSION_ID"
    elif [ -f "/etc/openwrt_release" ]; then
        . /etc/openwrt_release
    fi
    
    MAJOR_VERSION=$(echo "$DISTRIB_RELEASE" | cut -d'.' -f1)
    
    log "System: $DISTRIB_ID $DISTRIB_RELEASE"
    log "Major version: $MAJOR_VERSION"
    
    # Detect architecture
    if [ -f "/etc/os-release" ]; then
        ARCH=$(grep "OPENWRT_ARCH" /etc/os-release | cut -d'"' -f2)
    fi
    [ -z "$ARCH" ] && ARCH=$(uname -m)
    
    # Detect network stack (DSA vs swconfig)
    if [ -d "/sys/class/net/br-lan" ] || uci show network 2>/dev/null | grep -q "device.*br-lan"; then
        NETWORK_STACK="dsa"
    else
        NETWORK_STACK="swconfig"
    fi
    
    # Detect firewall version
    if command_exists fw4; then
        FIREWALL_VERSION="fw4"
    else
        FIREWALL_VERSION="fw3"
    fi
    
    log "Architecture: $ARCH"
    log "Network stack: $NETWORK_STACK"
    log "Firewall: $FIREWALL_VERSION"
}

# Install time banner
setup_banner() {
    log "Setting up installation banner..."
    echo "=== XIDZs-WRT Setup ===" 
    echo "Installed Time: $(date '+%A, %d %B %Y %T')"
    echo "System: $DISTRIB_ID $DISTRIB_RELEASE"
    echo "Architecture: $ARCH"
    echo "======================="
}

# Patch LuCI interface
patch_luci_interface() {
    log "Patching LuCI interface..."
    
    local luci_system_file="/www/luci-static/resources/view/status/include/10_system.js"
    local luci_ports_file="/www/luci-static/resources/view/status/include/29_ports.js"
    
    if [ -f "$luci_system_file" ]; then
        sed -i "s#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' / ':'')+(luciversion||''),#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' By Xidz_x':''),#g" "$luci_system_file"
        log "LuCI system view patched"
    else
        log_warn "LuCI system view file not found"
    fi
    
    if [ -f "$luci_ports_file" ]; then
        sed -i -E "s|icons/port_%s.png|icons/port_%s.gif|g" "$luci_ports_file"
        log "LuCI ports view patched"
    else
        log_warn "LuCI ports view file not found"
    fi
}

# Update system release info
update_release_info() {
    log "Updating system release information..."
    
    case "$DISTRIB_ID" in
        "immortalwrt")
            sed -i "s/\(DISTRIB_DESCRIPTION='ImmortalWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
            
            # Update ttyd menu location for newer versions
            local ttyd_menu="/usr/share/luci/menu.d/luci-app-ttyd.json"
            if [ -f "$ttyd_menu" ]; then
                sed -i 's|system/ttyd|services/ttyd|g' "$ttyd_menu"
            fi
            ;;
        "openwrt")
            sed -i "s/\(DISTRIB_DESCRIPTION='OpenWrt [0-9]*\.[0-9]*\.[0-9]*\).*'/\1'/g" /etc/openwrt_release
            ;;
    esac
    
    local branch_version=$(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release | cut -d"'" -f2)
    log "Branch version: $branch_version"
}

# Setup system basics
setup_system_basics() {
    log "Setting up system basics..."
    
    # Set root password
    log "Setting root password..."
    (echo "xyyraa"; sleep 2; echo "xyyraa") | passwd >/dev/null 2>&1
    
    # Configure hostname and timezone
    log "Configuring hostname and timezone..."
    uci batch <<EOF
set system.@system[0].hostname='XIDZs-WRT'
set system.@system[0].timezone='WIB-7'
set system.@system[0].zonename='Asia/Jakarta'
delete system.ntp.server
add_list system.ntp.server='pool.ntp.org'
add_list system.ntp.server='id.pool.ntp.org'
add_list system.ntp.server='time.google.com'
commit system
EOF
    
    # Set default language
    log "Setting default language to English..."
    uci set luci.@core[0].lang='en'
    uci commit luci
}

# Configure network interfaces
configure_network() {
    log "Configuring network interfaces..."
    log "Network stack: $NETWORK_STACK"
    
    if [ "$NETWORK_STACK" = "dsa" ]; then
        uci batch <<EOF
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
commit network
EOF
    fi
    
    log "Network interfaces configured for $NETWORK_STACK"
}

# Configure firewall
configure_firewall() {
    log "Configuring firewall..."
    log "Firewall version: $FIREWALL_VERSION"
    
    uci batch <<EOF
set firewall.@zone[0].input='ACCEPT'
set firewall.@zone[0].output='ACCEPT'
set firewall.@zone[0].forward='ACCEPT'
set firewall.@zone[1].network='wan modem'
commit firewall
EOF
    
    # Disable IPv6 on LAN
    log "Disabling IPv6 on LAN..."
    uci batch <<EOF
delete dhcp.lan.dhcpv6
delete dhcp.lan.ra
delete dhcp.lan.ndp
commit dhcp
EOF
}

# Configure wireless
configure_wireless() {
    log "Configuring wireless..."
    
    # Check if wireless is available
    if ! uci show wireless >/dev/null 2>&1; then
        log_warn "No wireless configuration found"
        return 1
    fi
    
    # Get number of wifi devices
    local wifi_devices=$(uci show wireless | grep "wireless\.@wifi-device\[" | wc -l)
    log "Found $wifi_devices wireless devices"
    
    if [ "$wifi_devices" -eq 0 ]; then
        log_warn "No wireless devices detected"
        return 1
    fi
    
    # Configure first wireless device
    uci batch <<EOF
set wireless.@wifi-device[0].disabled='0'
set wireless.@wifi-iface[0].disabled='0'
set wireless.@wifi-device[0].country='ID'
set wireless.@wifi-device[0].channel='8'
set wireless.@wifi-device[0].htmode='HT40'
set wireless.@wifi-iface[0].mode='ap'
set wireless.@wifi-iface[0].ssid='XIDZs-WRT'
set wireless.@wifi-iface[0].encryption='none'
EOF
    
    # Configure second device if available (dual-band)
    if [ "$wifi_devices" -gt 1 ]; then
        log "Configuring dual-band wireless..."
        uci batch <<EOF
set wireless.@wifi-device[1].disabled='0'
set wireless.@wifi-iface[1].disabled='0'
set wireless.@wifi-device[1].country='ID'
set wireless.@wifi-device[1].channel='149'
set wireless.@wifi-device[1].htmode='VHT80'
set wireless.@wifi-iface[1].mode='ap'
set wireless.@wifi-iface[1].ssid='XIDZs-WRT_5G'
set wireless.@wifi-iface[1].encryption='none'
EOF
    fi
    
    uci commit wireless
    
    # Restart wireless
    if command_exists wifi; then
        wifi reload && wifi up
    fi
    
    # Add persistent wireless fixes for Raspberry Pi
    if grep -q "Raspberry Pi" /proc/cpuinfo && [ "$wifi_devices" -gt 1 ]; then
        log "Adding Raspberry Pi wireless fixes..."
        
        # Add to rc.local if not exists
        if ! grep -q "wifi up" /etc/rc.local 2>/dev/null; then
            sed -i '/exit 0/i # Wireless fix for Raspberry Pi' /etc/rc.local
            sed -i '/exit 0/i sleep 10 && wifi up' /etc/rc.local
        fi
        
        # Add cron job for wireless stability
        if ! crontab -l 2>/dev/null | grep -q "wifi up"; then
            (crontab -l 2>/dev/null; echo "0 */12 * * * wifi down && sleep 5 && wifi up") | crontab -
            /etc/init.d/cron restart 2>/dev/null
        fi
    fi
}

# Configure USB modem settings
configure_usb_modem() {
    log "Configuring USB modem settings..."
    
    # Remove specific USB modeswitch entries
    if [ -f "/etc/usb-mode.json" ]; then
        sed -i -e '/12d1:15c1/,+5d' -e '/413c:81d7/,+5d' /etc/usb-mode.json
        log "Removed Huawei ME909s and DW5821e USB modeswitch entries"
    fi
    
    # Disable XMM modem if present
    if uci show xmm-modem >/dev/null 2>&1; then
        uci set xmm-modem.@xmm-modem[0].enable='0'
        uci commit xmm-modem
        log "XMM modem disabled"
    fi
}

# Configure package manager
configure_package_manager() {
    log "Configuring package manager..."
    
    # Disable signature checking
    sed -i 's/option check_signature/# option check_signature/g' /etc/opkg.conf
    
    # Add custom repository
    local custom_repo="src/gz custom_packages https://dl.openwrt.ai/latest/packages/${ARCH}/kiddin9"
    echo "$custom_repo" >> /etc/opkg/customfeeds.conf
    
    log "Custom repository added: $custom_repo"
}

# Setup theme and interface
setup_theme_interface() {
    log "Setting up theme and interface..."
    
    # Set Argon theme if available
    if [ -d "/www/luci-static/argon" ]; then
        uci set luci.main.mediaurlbase='/luci-static/argon'
        uci commit luci
        log "Argon theme activated"
    fi
    
    # Configure TTYD
    if uci show ttyd >/dev/null 2>&1; then
        uci set ttyd.@ttyd[0].command='/bin/bash --login'
        uci commit ttyd
        log "TTYD configured"
    fi
    
    # Setup TinyFM symlink
    if [ -d "/www/tinyfm" ]; then
        ln -sf / /www/tinyfm/rootfs
        log "TinyFM symlink created"
    fi
}

# Configure web server and PHP
configure_web_server() {
    log "Configuring web server and PHP..."
    
    # Configure uhttpd
    uci batch <<EOF
set uhttpd.main.ubus_prefix='/ubus'
set uhttpd.main.index_page='cgi-bin/luci'
add_list uhttpd.main.index_page='index.html'
add_list uhttpd.main.index_page='index.php'
EOF
    
    # Configure PHP if available
    if command_exists php-cgi; then
        uci set uhttpd.main.interpreter='.php=/usr/bin/php-cgi'
        log "PHP-CGI configured"
        
        # Configure PHP settings
        if [ -f "/etc/php.ini" ]; then
            sed -i 's/memory_limit = [0-9]*M/memory_limit = 128M/g' /etc/php.ini
            sed -i 's/display_errors = On/display_errors = Off/g' /etc/php.ini
        fi
        
        # Create PHP symlinks
        [ -f "/usr/bin/php-cli" ] && ln -sf /usr/bin/php-cli /usr/bin/php
        
        # Handle different PHP versions
        for php_ver in php8 php7; do
            if [ -d "/usr/lib/$php_ver" ] && [ ! -d "/usr/lib/php" ]; then
                ln -sf "/usr/lib/$php_ver" /usr/lib/php
                break
            fi
        done
    fi
    
    uci commit uhttpd
    /etc/init.d/uhttpd restart
}

# Setup monitoring services
setup_monitoring() {
    log "Setting up monitoring services..."
    
    # Create vnstat directory
    mkdir -p /etc/vnstat
    
    # Configure netdata jQuery fix
    if [ -f "/usr/share/netdata/web/lib/jquery-3.6.0.min.js" ]; then
        mv /usr/share/netdata/web/lib/jquery-3.6.0.min.js /usr/share/netdata/web/lib/jquery-2.2.4.min.js
        log "Netdata jQuery fixed"
    fi
    
    # Restart monitoring services
    for service in netdata vnstat; do
        if [ -f "/etc/init.d/$service" ]; then
            /etc/init.d/$service restart
            log "$service restarted"
        fi
    done
    
    # Run vnstati if available
    [ -f "/www/vnstati/vnstati.sh" ] && bash /www/vnstati/vnstati.sh
    
    # Enable vnstat backup
    if [ -f "/etc/init.d/vnstat_backup" ]; then
        chmod +x /etc/init.d/vnstat_backup
        /etc/init.d/vnstat_backup enable
        log "VNStat backup service enabled"
    fi
}

# Setup VPN and tunnel applications
setup_tunnel_apps() {
    log "Configuring tunnel applications..."
    
    local tunnel_apps="luci-app-openclash luci-app-nikki luci-app-passwall"
    
    for app in $tunnel_apps; do
        if opkg list-installed | grep -qw "$app"; then
            log "$app detected - configuring..."
            
            case "$app" in
                "luci-app-openclash")
                    setup_openclash
                    ;;
                "luci-app-nikki")
                    setup_nikki
                    ;;
                "luci-app-passwall")
                    setup_passwall
                    ;;
            esac
        else
            log "$app not installed - cleaning up..."
            cleanup_tunnel_app "$app"
        fi
    done
}

# OpenClash specific setup
setup_openclash() {
    local oc_dir="/etc/openclash"
    
    # Set permissions for core files
    [ -f "$oc_dir/core/clash_meta" ] && chmod +x "$oc_dir/core/clash_meta"
    [ -f "$oc_dir/Country.mmdb" ] && chmod +x "$oc_dir/Country.mmdb"
    find "$oc_dir" -name "Geo*" -type f -exec chmod +x {} \; 2>/dev/null
    
    # Apply patches
    [ -f "/usr/bin/patchoc.sh" ] && bash /usr/bin/patchoc.sh
    
    # Create symlinks
    [ -f "$oc_dir/history/Quenx.db" ] && ln -s "$oc_dir/history/Quenx.db" "$oc_dir/cache.db"
    [ -f "$oc_dir/core/clash_meta" ] && ln -s "$oc_dir/core/clash_meta" "$oc_dir/clash"
    
    # Clean up and restore config
    rm -rf "$oc_dir/custom" "$oc_dir/game_rules"
    find "$oc_dir/rule_provider" -type f ! -name "*.yaml" -delete 2>/dev/null
    
    [ -f "/etc/config/openclash1" ] && mv /etc/config/openclash1 /etc/config/openclash 2>/dev/null
    
    log "OpenClash configured"
}

# Nikki specific setup
setup_nikki() {
    local nikki_dir="/etc/nikki"
    
    rm -rf "$nikki_dir/run/providers"
    find "$nikki_dir/run" -name "Geo*" -type f -exec chmod +x {} \; 2>/dev/null
    
    # Symlink to OpenClash resources
    if [ -d "/etc/openclash/proxy_provider" ]; then
        ln -s /etc/openclash/proxy_provider "$nikki_dir/run/"
        ln -s /etc/openclash/rule_provider "$nikki_dir/run/"
    fi
    
    log "Nikki configured"
}

# Passwall specific setup
setup_passwall() {
    log "Passwall detected and configured"
}

# Cleanup tunnel app remnants
cleanup_tunnel_app() {
    local app="$1"
    
    case "$app" in
        "luci-app-openclash")
            rm -rf /etc/openclash /usr/share/openclash /usr/lib/lua/luci/view/openclash
            rm -f /etc/config/openclash1
            ;;
        "luci-app-nikki")
            rm -rf /etc/config/nikki /etc/nikki
            ;;
        "luci-app-passwall")
            rm -f /etc/config/passwall
            ;;
    esac
}

# Setup Amlogic specific configurations
setup_amlogic() {
    log "Checking Amlogic configuration..."
    
    if opkg list-installed | grep -q luci-app-amlogic; then
        log "Amlogic app detected"
        rm -f /etc/profile.d/30-sysinfo.sh
        
        # Add LED control to rc.local (commented out by default)
        if ! grep -q "k5hgled\|k6hgled" /etc/rc.local; then
            sed -i '/exit 0/i #sleep 4 && /usr/bin/k5hgled -r' /etc/rc.local
            sed -i '/exit 0/i #sleep 4 && /usr/bin/k6hgled -r' /etc/rc.local
        fi
    else
        # Clean up LED binaries if no Amlogic app
        rm -f /usr/bin/k*hgled*
    fi
}

# Run additional setup scripts
run_additional_scripts() {
    log "Running additional setup scripts..."
    
    local scripts="install2.sh indowrt.sh addport.sh"
    
    for script in $scripts; do
        local script_path="/root/$script"
        if [ -f "$script_path" ]; then
            chmod +x "$script_path"
            
            case "$script" in
                "install2.sh")
                    log "Running additional installer..."
                    bash "$script_path"
                    ;;
                "indowrt.sh")
                    log "Running TTL configuration..."
                    bash "$script_path"
                    ;;
                "addport.sh")
                    log "Adding port configuration..."
                    bash "$script_path"
                    ;;
            esac
        else
            log_warn "Script $script not found"
        fi
    done
}

# Set final permissions
set_permissions() {
    log "Setting file permissions..."
    
    # Set permissions for various directories and files
    local paths="/sbin /usr/bin"
    for path in $paths; do
        [ -d "$path" ] && find "$path" -type f -exec chmod +x {} \; 2>/dev/null
    done
    
    # Specific file permissions
    local files="/usr/lib/ModemManager/connection.d/10-report-down /www/vnstati/vnstati.sh"
    for file in $files; do
        [ -f "$file" ] && chmod +x "$file"
    done
}

# Update system profile
update_system_profile() {
    log "Updating system profile..."
    
    # Modify profile for custom banner
    if [ -f "/etc/profile" ]; then
        sed -i -e 's/\[ -f \/etc\/banner \] && cat \/etc\/banner/#&/' \
               -e 's/\[ -n "$FAILSAFE" \] && cat \/etc\/banner.failsafe/& || \/usr\/bin\/idz/' /etc/profile
    fi
}

# Final system restart and cleanup
final_cleanup() {
    log "Performing final cleanup..."
    
    # Remove the setup script from uci-defaults
    rm -f "/etc/uci-defaults/$(basename "$0")"
    
    # Restart essential services
    local services="network firewall uhttpd"
    for service in $services; do
        if [ -f "/etc/init.d/$service" ]; then
            /etc/init.d/$service restart >/dev/null 2>&1
            log "Service $service restarted"
        fi
    done
    
    log "Setup completed successfully!"
    log "Log file saved: $LOGFILE"
    
    echo ""
    echo "=== XIDZs-WRT Setup Complete ==="
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "System will be ready after network restart"
    echo "================================"
}

# Main execution
main() {
    setup_banner
    detect_system
    patch_luci_interface
    update_release_info
    setup_system_basics
    configure_network
    configure_firewall
    configure_wireless
    configure_usb_modem
    configure_package_manager
    setup_theme_interface
    configure_web_server
    setup_monitoring
    setup_tunnel_apps
    setup_amlogic
    run_additional_scripts
    set_permissions
    update_system_profile
    final_cleanup
}

# Error handling
set -e
trap 'log_error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"

exit 0