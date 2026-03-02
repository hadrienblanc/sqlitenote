#!/usr/bin/env bash
set -euo pipefail

echo "=== sqlnote — installation des dépendances ==="

# Detect OS and package manager
detect_pm() {
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "brew"
  elif command -v pacman &>/dev/null; then
    echo "pacman"
  elif command -v apt &>/dev/null; then
    echo "apt"
  else
    echo "unknown"
  fi
}

PM=$(detect_pm)

if [[ "$PM" == "unknown" ]]; then
  echo "Systeme non supporté. Requis : macOS (brew), Arch (pacman) ou Ubuntu/Debian (apt)."
  exit 1
fi

echo "Gestionnaire de paquets détecté : $PM"

# macOS: install Homebrew if missing
if [[ "$PM" == "brew" ]] && ! command -v brew &>/dev/null; then
  echo "Homebrew requis. Installation..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

install_pkg() {
  local cmd="$1"
  local brew_name="${2:-$1}"
  local pacman_name="${3:-$1}"
  local apt_name="${4:-$1}"

  if command -v "$cmd" &>/dev/null; then
    echo "✓ $cmd déjà installé"
    return
  fi

  echo "→ Installation de $cmd..."
  case "$PM" in
    brew)   brew install "$brew_name" ;;
    pacman) sudo pacman -S --noconfirm "$pacman_name" ;;
    apt)    sudo apt-get install -y "$apt_name" ;;
  esac
}

# gum — disponible dans les repos Arch (AUR via go build ou charmbracelet)
# Pour apt, on passe par le repo Charm
install_gum() {
  if command -v gum &>/dev/null; then
    echo "✓ gum déjà installé"
    return
  fi

  echo "→ Installation de gum..."
  case "$PM" in
    brew)
      brew install gum
      ;;
    pacman)
      sudo pacman -S --noconfirm gum
      ;;
    apt)
      sudo mkdir -p /etc/apt/keyrings
      curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null || true
      echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list >/dev/null
      sudo apt-get update -qq
      sudo apt-get install -y gum
      ;;
  esac
}

# glow — même repo Charm pour apt
install_glow() {
  if command -v glow &>/dev/null; then
    echo "✓ glow déjà installé"
    return
  fi

  echo "→ Installation de glow..."
  case "$PM" in
    brew)
      brew install glow
      ;;
    pacman)
      sudo pacman -S --noconfirm glow
      ;;
    apt)
      # Le repo Charm est déjà ajouté par install_gum, mais on s'assure
      if [[ ! -f /etc/apt/sources.list.d/charm.list ]]; then
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null || true
        echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list >/dev/null
        sudo apt-get update -qq
      fi
      sudo apt-get install -y glow
      ;;
  esac
}

install_pkg sqlite3 sqlite3 sqlite sqlite3
install_gum
install_glow

echo ""
echo "=== Installation terminée ==="
echo "Lancer : ./notes"
