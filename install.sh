#!/bin/sh
# source: https://github.com/Raspberry100/Myzram-swap
# shellcheck disable=SC2039,SC2162

#[ "$(id -u)" -eq '0' ] || { echo "This script requires root." && exit 1; }
case "$(readlink /proc/$$/exe)" in */bash) set -euo pipefail ;; *) set -eu ;; esac

# ensure a predictable environment
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
\unalias -a

# installer main body:
_main() {
  # ensure $1 exists so 'set -u' doesn't error out
  { [ "$#" -eq "0" ] && set -- ""; } > /dev/null 2>&1

  case "$1" in
    "--uninstall")
      # uninstall, requires root
      assert_root
      _uninstall
      ;;
    "--install" | "")
      # install dpkg hooks, requires root
      assert_root
      _install "$@"
      ;;
    *)
      # unknown flags, print usage and exit
      _usage
      ;;
  esac
  exit 0
}

_install() {
  configdiff=''
  newconfig=''
  if systemctl -q is-active Myzram-swap.service; then
    echo "Stopping Myzram-swap service"
    systemctl stop Myzram-swap.service
  fi

  echo "Installing script and service ..."
  install -o root Myzram-swap.sh /usr/local/sbin/Myzram-swap.sh
  install -o root -m 0644 service/Myzram-swap.service /etc/systemd/system/Myzram-swap.service

  # rename & cleanup old version config file
  if [ -f /etc/default/Myzram-swap-service ]; then
    mv -f /etc/default/Myzram-swap-service /etc/default/zram-swap
    chown root:root /etc/default/Myzram-swap
    chmod 0644 /etc/default/Myzram-swap
  fi

  if [ -f /etc/default/Myzram-swap ]; then
    {
      set +e
      configdiff=$(diff -y /etc/default/Myzram-swap service/Myzram-swap.config)
      set -e
    } > /dev/null 2>&1
    if [ -n "$configdiff" ]; then
      yn=''
      echo "Local configuration differs from packaged version"
      echo
      echo "Install package default configuration? Local config will be saved as /etc/default/Myzram-swap.oldconfig"
      while true; do
        echo "(I)nstall package default / (K)eep local configuration / View (D)iff"
        printf "[i/k/d]: "
        read yn
        case "$yn" in
          [Ii]*)
            echo "Installing package default ..."
            install -o root -m 0644 --backup --suffix=".oldconfig" service/Myzram-swap.config /etc/default/Myzram-swap
            newconfig='y'
            break
            ;;
          [Kk]*) break ;;
          [Dd]*) printf "%s\n\n" "$configdiff" ;;
        esac
      done
    fi
  else
    install -o root -m 0644 -b service/Myzram-swap.config /etc/default/Myzram-swap
  fi

  echo "Reloading systemd unit files and enabling boot-time service ..."
  systemctl daemon-reload
  systemctl enable Myzram-swap.service

  if [ -n "$newconfig" ]; then
    cat <<- HEREDOC
		Configuration file updated; old config saved as /etc/default/Myzram-swap.oldconfig
		Please review changes between configurations and then start the service with
		systemctl start Myzram-swap.service
		HEREDOC
  else
    echo "Starting Myzram-swap service ..."
    systemctl start Myzram-swap.service
  fi

  echo
  echo "Myzram-swap service installed successfully!"
  echo
}

_uninstall() {
  if systemctl -q is-active Myzram-swap.service; then
    echo "Stopping Myzram-swap service"
    systemctl stop Myzram-swap.service
  fi

  echo "Uninstalling script and systemd service."
  if [ -f /etc/systemd/system/Myzram-swap.service ]; then
    systemctl disable Myzram-swap.service || true
    rm -f /etc/systemd/system/Myzram-swap.service
  fi
  if [ -f /usr/local/sbin/Myzram-swap.sh ]; then
    rm -f /usr/local/sbin/Myzram-swap.sh
  fi
  echo "Reloading systemd unit files"
  systemctl daemon-reload

  echo "Myzram-swap service uninstalled; remove configuration /etc/default/Myzram-swap if desired"
}

assert_root() { [ "$(id -u)" -eq '0' ] || { echo "This action requires root." && exit 1; }; }
_usage() { echo "Usage: $(basename "$0") (--install|--uninstall)"; }

_main "$@"
