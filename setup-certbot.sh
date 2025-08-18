#!/bin/sh
# Interactive helper to install Nginx and Certbot, verify DNS, and obtain a Let's Encrypt certificate.
# It is designed for common Linux distros (Debian/Ubuntu, RHEL/CentOS/Alma/Rocky).
# Usage (interactive):
#   sudo ./setup-certbot.sh
# or with pre-set variables (still asks for confirmations):
#   sudo DOMAIN=queue.example.com EMAIL=admin@example.com ./setup-certbot.sh

set -eu

# Colors for readability (fallback if tput unavailable)
if command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold || true)"; NORMAL="$(tput sgr0 || true)"; RED="$(tput setaf 1 || true)"; GREEN="$(tput setaf 2 || true)"; YELLOW="$(tput setaf 3 || true)";
else
  BOLD=""; NORMAL=""; RED=""; GREEN=""; YELLOW="";
fi

need_root() {
  if [ "$(id -u)" != "0" ]; then
    echo "${RED}ERROR:${NORMAL} This script must be run as root (use sudo)." >&2
    exit 1
  fi
}

pause_confirm() {
  prompt="$1"
  while true; do
    printf "%s [y/N]: " "$prompt"
    read -r ans || true
    case "$ans" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO|"") return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

get_os_family() {
  # Echo: deb, rhel, unknown
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "${ID_LIKE:-$ID}" in
      *debian*|*ubuntu*|debian|ubuntu) echo deb; return ;;
      *rhel*|*fedora*|*centos*|rhel|fedora|centos|rocky|almalinux) echo rhel; return ;;
    esac
  fi
  echo unknown
}

ensure_cmd() {
  # ensure_cmd <command> <deb-pkg> <rhel-pkg>
  cmd="$1"; deb_pkg="$2"; rhel_pkg="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  osf="$(get_os_family)"
  echo "${YELLOW}Installing missing dependency:${NORMAL} $cmd"
  case "$osf" in
    deb)
      apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y "$deb_pkg" ;;
    rhel)
      if command -v dnf >/dev/null 2>&1; then
        dnf install -y "$rhel_pkg"
      else
        yum install -y "$rhel_pkg"
      fi ;;
    *)
      echo "${RED}WARNING:${NORMAL} Unknown OS; please install '$cmd' manually." ;;
  esac
}

resolve_ip() {
  # resolve A/AAAA; prefer A
  domain="$1"
  if command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$domain" | awk '{print $1; exit}' && return 0 || true
    getent ahostsv6 "$domain" | awk '{print $1; exit}' && return 0 || true
  fi
  if command -v dig >/dev/null 2>&1; then
    dig +short A "$domain" | head -n1 && return 0 || true
    dig +short AAAA "$domain" | head -n1 && return 0 || true
  fi
  if command -v host >/dev/null 2>&1; then
    host "$domain" | awk '/has address/ {print $4; exit}' && return 0 || true
  fi
  if command -v nslookup >/dev/null 2>&1; then
    nslookup "$domain" | awk '/Address: /{print $2}' | tail -n1 && return 0 || true
  fi
  return 1
}

public_ip() {
  if command -v curl >/dev/null 2>&1; then
    curl -4 -fsS https://api.ipify.org || curl -fsS https://ifconfig.me || true
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://api.ipify.org || wget -qO- https://ifconfig.me || true
  fi
}

ensure_nginx_installed() {
  if command -v nginx >/dev/null 2>&1; then
    echo "${GREEN}Nginx already installed.${NORMAL}"
    return 0
  fi
  echo "${YELLOW}Installing Nginx...${NORMAL}"
  osf="$(get_os_family)"
  case "$osf" in
    deb)
      apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y nginx ;;
    rhel)
      if command -v dnf >/dev/null 2>&1; then
        dnf install -y nginx
      else
        yum install -y epel-release || true
        yum install -y nginx
      fi ;;
    *)
      echo "${RED}ERROR:${NORMAL} Unsupported OS for automatic Nginx install. Install it manually and re-run."
      exit 1 ;;
  esac
}

ensure_certbot_installed() {
  if command -v certbot >/dev/null 2>&1; then
    echo "${GREEN}Certbot already installed.${NORMAL}"
    return 0
  fi
  echo "${YELLOW}Installing Certbot...${NORMAL}"
  # Prefer snap if available
  if command -v snap >/dev/null 2>&1; then
    snap install core || true
    snap refresh core || true
    snap install --classic certbot
    ln -sf /snap/bin/certbot /usr/bin/certbot || true
    return 0
  fi
  # Fallback to distro packages
  osf="$(get_os_family)"
  case "$osf" in
    deb)
      apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y certbot ;;
    rhel)
      if command -v dnf >/dev/null 2>&1; then
        dnf install -y certbot
      else
        yum install -y certbot
      fi ;;
    *)
      echo "${RED}ERROR:${NORMAL} Unable to install Certbot automatically on this OS. Install it manually and re-run."
      exit 1 ;;
  esac
}

obtain_cert_standalone() {
  domain="$1"; email="$2"
  echo "${YELLOW}Preparing to obtain certificate for ${BOLD}$domain${NORMAL}${YELLOW} using HTTP-01 (standalone).${NORMAL}"
  # Ensure port 80 is free: stop nginx temporarily if running
  if pgrep -x nginx >/dev/null 2>&1; then
    echo "Stopping Nginx temporarily to free port 80 for standalone challenge..."
    systemctl stop nginx >/dev/null 2>&1 || service nginx stop >/dev/null 2>&1 || true
  fi
  certbot certonly --standalone -d "$domain" -m "$email" --agree-tos --no-eff-email --preferred-challenges http
  echo "Starting Nginx again..."
  systemctl start nginx >/dev/null 2>&1 || service nginx start >/dev/null 2>&1 || nginx
}

main() {
  need_root

  DOMAIN_IN="${DOMAIN:-}"
  EMAIL_IN="${EMAIL:-}"

  if [ -z "$DOMAIN_IN" ]; then
    printf "Enter your domain (e.g., queue.example.com): "
    read -r DOMAIN_IN
  fi
  if [ -z "$EMAIL_IN" ]; then
    printf "Enter your email for Let’s Encrypt notifications: "
    read -r EMAIL_IN
  fi

  if [ -z "$DOMAIN_IN" ] || [ -z "$EMAIL_IN" ]; then
    echo "${RED}ERROR:${NORMAL} DOMAIN and EMAIL are required." >&2
    exit 1
  fi

  echo "\n${BOLD}DNS Verification${NORMAL}"
  ensure_cmd dig dnsutils bind-utils || true
  ensure_cmd curl curl curl || true

  domain_ip="$(resolve_ip "$DOMAIN_IN" || true)"
  pub_ip="$(public_ip || true)"
  echo "Resolved IP for ${BOLD}$DOMAIN_IN${NORMAL}: ${YELLOW}${domain_ip:-unknown}${NORMAL}"
  echo "This server public IP: ${YELLOW}${pub_ip:-unknown}${NORMAL}"
  echo "For HTTP-01 validation, the domain must resolve to this server’s public IP and port 80 must be reachable."
  if ! pause_confirm "Is the DNS configured correctly for $DOMAIN_IN and propagated?"; then
    echo "Aborting per user choice. Configure DNS and try again."
    exit 1
  fi

  echo "\n${BOLD}Install prerequisites${NORMAL}"
  if ! pause_confirm "Install or ensure Nginx and Certbot are present?"; then
    echo "Aborting per user choice."
    exit 1
  fi

  ensure_nginx_installed
  ensure_certbot_installed

  echo "\n${BOLD}Obtain certificate${NORMAL}"
  if ! pause_confirm "Proceed to request a certificate for $DOMAIN_IN via HTTP-01 challenge?"; then
    echo "Aborting per user choice."
    exit 1
  fi

  obtain_cert_standalone "$DOMAIN_IN" "$EMAIL_IN"

  cert_dir="/etc/letsencrypt/live/${DOMAIN_IN}"
  fullchain="$cert_dir/fullchain.pem"
  privkey="$cert_dir/privkey.pem"

  if [ -r "$fullchain" ] && [ -r "$privkey" ]; then
    echo "\n${GREEN}Certificate obtained successfully.${NORMAL}"
    echo "Fullchain: $fullchain"
    echo "Privkey  : $privkey"
    echo "\nNext: You can generate the Nginx stream config with:"
    echo "  make nginx-config DOMAIN=$DOMAIN_IN CERT_DIR=$cert_dir"
  else
    echo "${RED}ERROR:${NORMAL} Certificate files not found at $cert_dir. Check Certbot output above."
    exit 1
  fi
}

main "$@"
