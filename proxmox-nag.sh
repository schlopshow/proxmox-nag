#!/bin/sh
set -eu

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to log messages
log() {
    printf "[INFO] %s\n" "$1"
}

# Function to assert root privileges
assert_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This action requires root privileges." >&2
        exit 1
    fi
}

# Function to remove a file if it exists
remove_if_exists() {
    [ -f "$1" ] && rm -f "$1"
}

# Function to disable the Proxmox license nag
disable_nag() {
    local nag_token="data.status.toLowerCase() !== 'active'"
    local nag_file="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    local script_name="$(basename "$0")"

    if grep -qs "$nag_token" "$nag_file" > /dev/null 2>&1; then
        log "$script_name: Removing Nag ..."
        sed -i.orig "s/$nag_token/false/g" "$nag_file"
        systemctl restart pveproxy.service
    fi
}

# Function to disable the paid repository list
disable_paid_repo() {
    local paid_base="/etc/apt/sources.list.d/pve-enterprise"

    if [ -f "$paid_base.list" ]; then
        log "$script_name: Disabling PVE paid repo list ..."
        mv -f "$paid_base.list" "$paid_base.disabled"
    fi
}

# Uninstall function
_uninstall() {
    log "Removing installed files..."
    remove_if_exists "/etc/apt/apt.conf.d/86pve-nags"
    remove_if_exists "/usr/share/pve-nag-buster.sh"
    log "Uninstallation complete."
}

# Install function
_install() {
    assert_root
    log "Creating PVE no-subscription repo list..."

    # Get the OS release information
    VERSION_CODENAME=''
    . /etc/os-release
    if [ -n "$VERSION_CODENAME" ]; then
        RELEASE="$VERSION_CODENAME"
    else
        RELEASE=$(awk -F"[)(]+" '/VERSION=/ {print $2}' /etc/os-release)
    fi

    # Create the pve-no-subscription list
    echo "deb http://download.proxmox.com/debian/pve $RELEASE pve-no-subscription" > "/etc/apt/sources.list.d/pve-no-subscription.list"

    # Create dpkg hooks
    log "Creating dpkg hooks in /etc/apt/apt.conf.d ..."
    cat <<- 'EOF' > "/etc/apt/apt.conf.d/86pve-nags"
	DPkg::Pre-Install-Pkgs {
	    "while read -r pkg; do case $pkg in *proxmox-widget-toolkit* | *pve-manager*) touch /tmp/.pve-nag-buster && exit 0; esac done < /dev/stdin";
	};

	DPkg::Post-Invoke {
	    "[ -f /tmp/.pve-nag-buster ] && { /usr/share/pve-nag-buster.sh; rm -f /tmp/.pve-nag-buster; }; exit 0";
	};
	EOF

    # Disable the Proxmox license nag
    disable_nag

    # Disable the paid repository list
    disable_paid_repo

    log "Installation complete."
}

# Main function
_main() {
    case "$1" in
        "--uninstall")
            _uninstall
            ;;
        "--install" | "")
            _install
            ;;
        *)
            echo "Usage: $(basename "$0") (--install|--uninstall)" >&2
            exit 1
            ;;
    esac
}

# Call the main function with all arguments
_main "$@"

