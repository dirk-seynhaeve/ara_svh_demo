#!/usr/bin/env bash
# Bootstrap script for Ara project (host)
# - Run with --check to print what would be installed and detection results
# - Run with --install to perform package install (requires sudo)
# - Run with --yes to skip confirmation

set -eu
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Generic package keys. We'll map these to distro-specific package names below.
KEYS=(
  build-essential
  cmake
  ninja-build
  autoconf
  automake
  libtool
  pkg-config
  texinfo
  help2man
  flex
  bison
  clang
  gcc
  g++
  libc++-dev
  libc++abi-dev
  python3
  python3-pip
  git
  ccache
  libelf-dev
  zlib1g
  zlib1g-dev
  libfl-dev
  linux-headers
)

# Distro-specific name maps (generic key -> distro package name)
declare -A PKG_DEBIAN
declare -A PKG_RHEL

# Debian/Ubuntu names (mostly identical to keys)
for k in "${KEYS[@]}"; do
  PKG_DEBIAN["$k"]="$k"
done
# linux-headers includes the running kernel version on Debian
PKG_DEBIAN[linux-headers]="linux-headers-$(uname -r)"

# RHEL equivalents (may be group names or multiple alternatives)
PKG_RHEL[build-essential]="Development Tools"
PKG_RHEL[cmake]="cmake"
PKG_RHEL[ninja-build]="ninja ninja-build"
PKG_RHEL[autoconf]="autoconf"
PKG_RHEL[automake]="automake"
PKG_RHEL[libtool]="libtool"
PKG_RHEL[pkg-config]="pkgconfig pkgconf"
PKG_RHEL[texinfo]="texinfo"
PKG_RHEL[help2man]="help2man"
PKG_RHEL[flex]="flex"
PKG_RHEL[bison]="bison"
PKG_RHEL[clang]="clang"
PKG_RHEL[gcc]="gcc"
PKG_RHEL[g++]="gcc-c++"
PKG_RHEL[libc++-dev]="libcxx-devel libcxx"
PKG_RHEL[libc++abi-dev]="libcxxabi-devel libcxxabi"
PKG_RHEL[python3]="python3"
PKG_RHEL[python3-pip]="python3-pip python3-pip-wheel"
PKG_RHEL[git]="git"
PKG_RHEL[ccache]="ccache"
PKG_RHEL[libelf-dev]="elfutils-libelf-devel libelf-devel"
PKG_RHEL[zlib1g]="zlib"
PKG_RHEL[zlib1g-dev]="zlib-devel"
PKG_RHEL[libfl-dev]="flex"
PKG_RHEL[linux-headers]="kernel-devel kernel-headers"

usage() {
  cat <<EOF
Usage: $0 [--check|--install] [--yes]

--check    : only check which packages are installed, test compilers and suggest flags
--install  : install the recommended packages via apt/dnf/yum (requires sudo)
--yes      : assume yes for install

Examples:
  $0 --check
  sudo $0 --install --yes
EOF
}

# ANSI color codes for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
RESET='\033[0m'

# Detect distribution and package manager (debian-like vs RHEL-like)
DISTRO_FAMILY="unknown"
PKG_MANAGER=""
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  id_lc=${ID_LIKE:-}
  id=${ID:-}
  if [[ " $id_lc " == *"debian"* || " $id_lc " == *"ubuntu"* || "$id" == "debian" || "$id" == "ubuntu" ]]; then
    DISTRO_FAMILY=debian
    if command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
      PKG_MANAGER=apt
    fi
  elif [[ " $id_lc " == *"rhel"* || " $id_lc " == *"fedora"* || "$id" == "centos" || "$id" == "rhel" || "$id" == "fedora" || "$id" == "rocky" || "$id" == "almalinux" ]]; then
    DISTRO_FAMILY=rhel
    if command -v dnf >/dev/null 2>&1; then
      PKG_MANAGER=dnf
    elif command -v yum >/dev/null 2>&1; then
      PKG_MANAGER=yum
    fi
  fi
fi

# Mapping of Debian package names to common RHEL equivalents (space-separated alternatives)
declare -A RHEL_MAP
RHEL_MAP[build-essential]="Development Tools"
RHEL_MAP[cmake]="cmake"
RHEL_MAP[ninja-build]="ninja ninja-build"
RHEL_MAP[autoconf]="autoconf"
RHEL_MAP[automake]="automake"
RHEL_MAP[libtool]="libtool"
RHEL_MAP[pkg-config]="pkgconfig pkgconf"
RHEL_MAP[texinfo]="texinfo"
RHEL_MAP[help2man]="help2man"
RHEL_MAP[flex]="flex"
RHEL_MAP[bison]="bison"
RHEL_MAP[clang]="clang"
RHEL_MAP[gcc]="gcc"
RHEL_MAP[g++]="gcc-c++"
RHEL_MAP[libc++-dev]="libcxx-devel libcxx"
RHEL_MAP[libc++abi-dev]="libcxxabi-devel libcxxabi"
RHEL_MAP[python3]="python3"
RHEL_MAP[python3-pip]="python3-pip python3-pip-wheel"
RHEL_MAP[git]="git"
RHEL_MAP[ccache]="ccache"
RHEL_MAP[libelf-dev]="elfutils-libelf-devel libelf-devel"
RHEL_MAP[zlib1g]="zlib"
RHEL_MAP[zlib1g-dev]="zlib-devel"
RHEL_MAP[libfl-dev]="flex"
RHEL_MAP[linux-headers]="kernel-devel kernel-headers"

# Helper: translate a Debian package name to RHEL alternatives
translate_rhel() {
  local pkg="$1"
  # kernel headers (dynamic name) -> kernel-devel
  if [[ "$pkg" == linux-headers-* ]]; then
    echo "kernel-devel"
    return
  fi
  if [[ -n "${RHEL_MAP[$pkg]:-}" ]]; then
    echo "${RHEL_MAP[$pkg]}"
  else
    # fallback: try the same name
    echo "$pkg"
  fi
}

# If we couldn't determine a package manager from /etc/os-release, probe common managers
if [[ -z "$PKG_MANAGER" ]]; then
  if command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER=apt
    DISTRO_FAMILY=debian
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER=dnf
    DISTRO_FAMILY=rhel
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER=yum
    DISTRO_FAMILY=rhel
  fi
fi

if [[ -z "$PKG_MANAGER" ]]; then
  echo "Error: Unable to determine package manager (apt/dnf/yum)."
  echo "This bootstrap helper supports Debian-like and RHEL-like distributions only."
  echo "Please install the required packages manually or run this script on a supported distro."
  exit 1
fi

# Confirm detected distro family and package manager
echo "Detected distro family: $DISTRO_FAMILY (package manager: $PKG_MANAGER)"
if [[ "$DISTRO_FAMILY" != "debian" && "$DISTRO_FAMILY" != "rhel" ]]; then
  echo "Error: unsupported distro family '$DISTRO_FAMILY'."
  echo "This bootstrap helper only supports Debian-like and RHEL-like distributions."
  exit 1
fi

# Build the list of distro-specific package names we'll check/install
DISPLAY_PKGS=()
for key in "${KEYS[@]}"; do
  if [[ "$DISTRO_FAMILY" == "rhel" ]]; then
    # choose the first token of the RHEL mapping for display purposes
    val="${PKG_RHEL[$key]:-$key}"
    first=${val%% *}
    DISPLAY_PKGS+=("$first")
  else
    DISPLAY_PKGS+=("${PKG_DEBIAN[$key]:-$key}")
  fi
done

# Helper: compute which packages are missing on this host.
# Populates arrays: MISSING (display names), MISSING_KEYS (generic keys),
# and PKGS_TO_INSTALL (distro-specific package names appropriate for installer).
compute_missing() {
  MISSING=()
  MISSING_KEYS=()
  PKGS_TO_INSTALL=()
  if [[ "$DISTRO_FAMILY" == "rhel" ]]; then
    local RHEL_INSTALL=()
    NEED_DEV_GROUP=0
    for idx in "${!KEYS[@]}"; do
      key=${KEYS[$idx]}
      disp=${DISPLAY_PKGS[$idx]}
      alternatives="${PKG_RHEL[$key]:-$key}"
      if [[ "$key" == "linux-headers" ]]; then
        alternatives="kernel-devel"
      fi
      # Treat build-essential as a groupinstall (Development Tools)
      if [[ "$key" == "build-essential" ]]; then
        alternatives="Development Tools"
      fi
      found=1
      for alt in $alternatives; do
        if rpm -q "$alt" >/dev/null 2>&1; then
          found=0
          break
        fi
      done
      if [[ $found -ne 0 ]]; then
        MISSING+=("$disp")
        MISSING_KEYS+=("$key")
        # If this is the build-essential key, mark the groupinstall flag
        if [[ "$key" == "build-essential" ]]; then
          NEED_DEV_GROUP=1
        else
          for m in $alternatives; do
            RHEL_INSTALL+=("$m")
          done
        fi
      fi
    done
    # dedupe RHEL_INSTALL into PKGS_TO_INSTALL
    declare -A _seen_r
    for pkg in "${RHEL_INSTALL[@]}"; do
      if [[ -z "${_seen_r[$pkg]:-}" ]]; then
        _seen_r[$pkg]=1
        PKGS_TO_INSTALL+=("$pkg")
      fi
    done
  else
    for idx in "${!KEYS[@]}"; do
      key=${KEYS[$idx]}
      disp=${DISPLAY_PKGS[$idx]}
      if dpkg -s "$disp" >/dev/null 2>&1; then
        continue
      else
        MISSING+=("$disp")
        MISSING_KEYS+=("$key")
        PKGS_TO_INSTALL+=("${PKG_DEBIAN[$key]:-$key}")
      fi
    done
  fi
}

MODE=check
ASSUME_YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE=check; shift ;;
    --install) MODE=install; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

echo "Ara bootstrap helper"

if [[ "$MODE" == "install" ]]; then
  # compute which packages are actually missing and should be installed
  compute_missing
  echo "Packages to install: ${PKGS_TO_INSTALL[*]}"
  if [[ $ASSUME_YES -eq 0 ]]; then
    read -r -p "Proceed to install these packages? [y/N] " reply || true
    if [[ "${reply,,}" != "y" ]]; then
      echo "Aborting install."; exit 1
    fi
  fi
  if [[ "$DISTRO_FAMILY" == "rhel" && -n "$PKG_MANAGER" ]]; then
    echo "Detected RHEL-like distro, using $PKG_MANAGER to install packages."
    # Try to install Development Tools group (covers build-essential equivalent)
    if [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
      if [[ ${NEED_DEV_GROUP:-0} -eq 1 ]]; then
        echo "Installing Development Tools group (may require sudo)..."
        sudo $PKG_MANAGER groupinstall -y "Development Tools" || true
      fi
    fi
    # Translate package names and install
    RHEL_INSTALL=()
    for key in "${KEYS[@]}"; do
      # skip build-essential because covered by groupinstall
      if [[ "$key" == "build-essential" ]]; then
        continue
      fi
      mapped="${PKG_RHEL[$key]:-${key}}"
      # expand linux-headers mapping if needed
      if [[ "$key" == "linux-headers" ]]; then
        mapped="kernel-devel"
      fi
      for m in $mapped; do
        RHEL_INSTALL+=("$m")
      done
    done
    # deduplicate
    unique=()
    declare -A seen
    for pkg in "${RHEL_INSTALL[@]}"; do
      if [[ -z "${seen[$pkg]:-}" ]]; then
        seen[$pkg]=1
        unique+=("$pkg")
      fi
    done
    if [[ ${#PKGS_TO_INSTALL[@]} -gt 0 ]]; then
      echo "Installing: ${PKGS_TO_INSTALL[*]}"
      sudo $PKG_MANAGER install -y "${PKGS_TO_INSTALL[@]}"
    fi
    echo "Install finished (if successful). You may still need to pass clang flags when building Verilator."
    exit 0
  else
    # Default to Debian/apt path
    if [[ ${#PKGS_TO_INSTALL[@]} -gt 0 ]]; then
      sudo apt update
      sudo apt install -y "${PKGS_TO_INSTALL[@]}"
    else
      echo "No packages to install."
    fi
    echo "Packages installed (if successful). You may still need to pass clang flags when building Verilator."
    exit 0
  fi
fi

# --- CHECK MODE ---

echo "Checking installed packages..."
MISSING=()
# Compute the maximum package name length so the status column aligns
maxlen=0
for p in "${DISPLAY_PKGS[@]}"; do
  plen=${#p}
  if (( plen > maxlen )); then
    maxlen=$plen
  fi
done
for idx in "${!KEYS[@]}"; do
  key=${KEYS[$idx]}
  disp=${DISPLAY_PKGS[$idx]}
  if [[ "$DISTRO_FAMILY" == "rhel" ]]; then
    # get alternatives from PKG_RHEL mapping
    alternatives="${PKG_RHEL[$key]:-$key}"
    # special-case linux-headers
    if [[ "$key" == "linux-headers" ]]; then
      alternatives="kernel-devel"
    fi
    found=1
    for alt in $alternatives; do
      if rpm -q "$alt" >/dev/null 2>&1; then
        found=0
        break
      fi
    done
    if [[ $found -eq 0 ]]; then
      printf "  %-${maxlen}s : ${GREEN}%s${RESET}\n" "$disp" "installed"
    else
      printf "  %-${maxlen}s : ${RED}%s${RESET}\n" "$disp" "MISSING"
      MISSING+=("$disp")
    fi
  else
    if dpkg -s "$disp" >/dev/null 2>&1; then
      printf "  %-${maxlen}s : ${GREEN}%s${RESET}\n" "$disp" "installed"
    else
      printf "  %-${maxlen}s : ${RED}%s${RESET}\n" "$disp" "MISSING"
      MISSING+=("$disp")
    fi
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo
  echo "Missing packages detected: ${MISSING[*]}"
  echo "Run: sudo $0 --install --yes"
fi

# Compiler detection

echo
echo "Checking compilers and C++ linkage behavior..."

TMPDIR=$(mktemp -d)
cat > "$TMPDIR/test.cc" <<'CPP'
#include <iostream>
int main(){ std::cout << "ok\n"; return 0; }
CPP

RET_CLANG=1
RET_CLANG_LIBCXX=1
RET_GXX=1

if command -v clang++ >/dev/null 2>&1; then
  echo "clang++: found -> testing compile/link"
  if clang++ -O2 -o "$TMPDIR/test_clang" "$TMPDIR/test.cc" >/dev/null 2>&1; then
    echo "  clang++ -> ok (linked with default libs)"
    RET_CLANG=0
  else
    echo "  clang++ -> failed to link with default settings"
  fi
  echo "  testing clang++ with -stdlib=libc++ (if libc++ present)"
  if clang++ -O2 -stdlib=libc++ -o "$TMPDIR/test_clang_libcxx" "$TMPDIR/test.cc" >/dev/null 2>&1; then
    echo "  clang++ + -stdlib=libc++ -> ok"
    RET_CLANG_LIBCXX=0
  else
    echo "  clang++ + -stdlib=libc++ -> failed"
  fi
else
  echo "clang++: not found"
fi

if command -v g++ >/dev/null 2>&1; then
  echo "g++: found -> testing compile/link"
  if g++ -O2 -o "$TMPDIR/test_gxx" "$TMPDIR/test.cc" >/dev/null 2>&1; then
    echo "  g++ -> ok"
    RET_GXX=0
  else
    echo "  g++ -> failed"
  fi
else
  echo "g++: not found"
fi

# Summarize

echo
echo "Compiler summary:"
if [[ $RET_CLANG -eq 0 ]]; then
  echo "  clang++ links successfully with default settings"
else
  echo "  clang++ failed to link with default settings"
fi
if [[ $RET_CLANG_LIBCXX -eq 0 ]]; then
  echo "  clang++ + -stdlib=libc++ links successfully"
else
  echo "  clang++ + -stdlib=libc++ failed to link (libc++ may be missing)"
fi
if [[ $RET_GXX -eq 0 ]]; then
  echo "  g++ links successfully"
else
  echo "  g++ failed to link"
fi

# Recommend flags

echo
if [[ $RET_CLANG -ne 0 && $RET_CLANG_LIBCXX -eq 0 ]]; then
  echo "Recommendation: Use the top-level Makefile which already configures clang to use libc++ when building Verilator."
  echo "  From the project root run: make verilator"
  echo "  If you invoke Verilator's build manually, pass the same flags the Makefile uses:"
  echo "    CXX=clang++ CXXFLAGS=\"-stdlib=libc++\" LDFLAGS=\"-stdlib=libc++\" ./configure && make && make install"
  echo "  Ensure \`libc++-dev\`/\`libc++abi-dev\` are installed if you plan to use clang+libc++."
elif [[ $RET_GXX -eq 0 ]]; then
  echo "Recommendation: You can also build Verilator with gcc/g++; the Makefile will use your chosen CC/CXX if set:"
  echo "  CC=gcc CXX=g++ make verilator"
else
  echo "No working C++ compiler detected — please install g++ or clang and retry."
fi

# Cleanup
rm -rf "$TMPDIR"

echo
echo "Bootstrap check completed. If you want to install missing packages, run: sudo $0 --install --yes"

exit 0
