#!/usr/bin/env bash
# Bootstrap script for Ara project (host)
# - Run with --check to print what would be installed and detection results
# - Run with --install to perform package install (requires sudo)
# - Run with --yes to skip confirmation

set -eu
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

# Note: Debian/Ubuntu rarely require multiple hard-coded alternatives per
# logical package key. Package names on Debian family systems are generally
# stable across releases and derivatives, and APT/DPKG handle virtual
# packages/provides more consistently than RHEL tooling. We therefore keep
# a single canonical Debian package name per key (the `PKG_DEBIAN` map)
# and rely on `BIN_FOR_KEY` (representative binaries) for detection. If an
# edge-case appears, we can add an apt-time fallback that queries packages
# providing a file/binary instead of maintaining many hard-coded aliases.

# Debian/Ubuntu names (mostly identical to keys)
for k in "${KEYS[@]}"; do
  PKG_DEBIAN["$k"]="$k"
done
# linux-headers includes the running kernel version on Debian
# Fix this element in the PKG_DEBIANarray
PKG_DEBIAN[linux-headers]="linux-headers-$(uname -r)"

# RHEL equivalents (may be group names or multiple alternatives).
# Use space-separated strings for alternatives; split into arrays when needed.
declare -A PKG_RHEL
PKG_RHEL[build-essential]='Development Tools'
PKG_RHEL[cmake]='cmake'
PKG_RHEL[ninja-build]='ninja ninja-build'
PKG_RHEL[autoconf]='autoconf'
PKG_RHEL[automake]='automake'
PKG_RHEL[libtool]='libtool'
PKG_RHEL[pkg-config]='pkgconfig pkgconf'
PKG_RHEL[texinfo]='texinfo'
PKG_RHEL[help2man]='help2man'
PKG_RHEL[flex]='flex'
PKG_RHEL[bison]='bison'
PKG_RHEL[clang]='clang'
PKG_RHEL[gcc]='gcc'
PKG_RHEL[g++]='gcc-c++'
PKG_RHEL[libc++-dev]='libcxx-devel libcxx'
PKG_RHEL[libc++abi-dev]='libcxxabi-devel libcxxabi'
PKG_RHEL[python3]='python3'
PKG_RHEL[python3-pip]='python3-pip python3-pip-wheel'
PKG_RHEL[git]='git'
PKG_RHEL[ccache]='ccache'
PKG_RHEL[libelf-dev]='elfutils-libelf-devel libelf-devel'
PKG_RHEL[zlib1g]='zlib'
PKG_RHEL[zlib1g-dev]='zlib-devel'
PKG_RHEL[libfl-dev]='flex'
PKG_RHEL[linux-headers]='kernel-devel kernel-headers'

# Optional mapping from generic keys to one or more command names that
# indicate the tool is present on PATH. If a binary is found we treat
# the key as "installed" even if the package name differs between
# distros (this makes detection more robust).
declare -A BIN_FOR_KEY
BIN_FOR_KEY[ninja-build]='ninja'
BIN_FOR_KEY[pkg-config]='pkg-config'
BIN_FOR_KEY[python3-pip]='pip3'
BIN_FOR_KEY[g++]='g++'
BIN_FOR_KEY[python3]='python3'
BIN_FOR_KEY[ccache]='ccache'
BIN_FOR_KEY[git]='git'
BIN_FOR_KEY[clang]='clang'
BIN_FOR_KEY[gcc]='gcc'
BIN_FOR_KEY[cmake]='cmake'

# Helper: check whether a RHEL key is present on this host. This first
# checks for a matching executable (from BIN_FOR_KEY) and falls back to
# probing RPM package names from `PKG_RHEL` alternatives. Special-case
# the `build-essential` key which maps to the "Development Tools"
# group on RHEL.
rhel_key_installed() {
  local key="$1"
  # build-essential -> Development Tools group
  if [[ "$key" == "build-essential" ]]; then
    if command -v $PKG_MANAGER >/dev/null 2>&1; then
      if $PKG_MANAGER group list --installed 2>/dev/null | grep -qi "Development Tools"; then
        return 0
      fi
    fi
    # fallback: check representative packages
    if rpm -q gcc >/dev/null 2>&1 || rpm -q make >/dev/null 2>&1; then
      return 0
    fi
    return 1
  fi

  # If a representative binary is configured for this key, prefer that
  if [[ -n "${BIN_FOR_KEY[$key]:-}" ]]; then
    read -r -a bins <<< "${BIN_FOR_KEY[$key]}"
    for b in "${bins[@]}"; do
      if command -v "$b" >/dev/null 2>&1; then
        return 0
      fi
    done
  fi

  # fall back to checking RPM packages listed in PKG_RHEL
  if [[ -n ${PKG_RHEL[$key]:-} ]]; then
    read -r -a alts <<< "${PKG_RHEL[$key]}"
  else
    alts=("$key")
  fi
  for alt in "${alts[@]}"; do
    if rpm -q "$alt" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

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
RESET='\033[0m'

# Detect distribution and package manager (debian-like vs RHEL-like)
DISTRO_FAMILY="unknown"
PKG_MANAGER=""
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  id_lc=${ID_LIKE:-}
  id=${ID:-}
  # Read /etc/os-release and determine distro family. We inspect
  # `ID_LIKE` (may contain multiple space-separated tokens) and `ID`.
  # Match family keywords in `ID_LIKE` and perform an exact match on
  # `ID` to avoid accidental partial matches.
  if [[ "$id_lc" =~ (debian|ubuntu) || "$id" =~ ^(debian|ubuntu)$ ]]; then
    DISTRO_FAMILY=debian
    if command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
      PKG_MANAGER=apt
    fi
  elif [[ "$id_lc" =~ (rhel|fedora) || "$id" =~ ^(centos|rhel|fedora|rocky|almalinux)$ ]]; then
    # RHEL-family (RHEL, CentOS, Fedora, Rocky, AlmaLinux).
    # Prefer `dnf` when available, fall back to `yum`.
    DISTRO_FAMILY=rhel
    if command -v dnf >/dev/null 2>&1; then
      PKG_MANAGER=dnf
    elif command -v yum >/dev/null 2>&1; then
      PKG_MANAGER=yum
    fi
  fi
fi

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
  cat <<'MSG'
Error: Unable to determine package manager (apt/dnf/yum).
This bootstrap helper supports Debian-like and RHEL-like distributions only.
Please install the required packages manually or run this script on a supported distro.
MSG
  exit 1
fi

# Confirm detected distro family and package manager
echo "Detected distro family: $DISTRO_FAMILY (package manager: $PKG_MANAGER)"
if [[ "$DISTRO_FAMILY" != "debian" && "$DISTRO_FAMILY" != "rhel" ]]; then
  cat <<MSG
Error: unsupported distro family '$DISTRO_FAMILY'.
This bootstrap helper only supports Debian-like and RHEL-like distributions.
MSG
  exit 1
fi

# Build the list of distro-specific package names we'll check/install
DISPLAY_PKGS=()
for key in "${KEYS[@]}"; do
  if [[ "$DISTRO_FAMILY" == "rhel" ]]; then
    # Choose a display name for RHEL: split the space-separated
    # alternatives from `PKG_RHEL` into an array and use the first
    # alternative by default. If the Debian package name (from
    # `PKG_DEBIAN`) appears among the alternatives, prefer that for
    # display (so `ninja-build` is shown instead of `ninja`). This
    # preserves multi-word names (e.g. "Development Tools") and
    # dashes in package names.
    if [[ -n ${PKG_RHEL[$key]:-} ]]; then
      read -r -a alts <<< "${PKG_RHEL[$key]}"
      display_alt="${alts[0]}"
      # Prefer the Debian package name when available in alternatives
      deb_name="${PKG_DEBIAN[$key]:-$key}"
      for a in "${alts[@]}"; do
        if [[ "$a" == "$deb_name" ]]; then
          display_alt="$a"
          break
        fi
      done
      DISPLAY_PKGS+=("$display_alt")
    else
      DISPLAY_PKGS+=("$key")
    fi
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
      # Use centralized detection helper for RHEL keys
      NEED_DEV_GROUP=0
      if rhel_key_installed "$key"; then
        found=0
      else
        found=1
      fi
      if [[ $found -ne 0 ]]; then
        MISSING+=("$disp")
        MISSING_KEYS+=("$key")
        if [[ "$key" == "build-essential" ]]; then
          NEED_DEV_GROUP=1
        else
          # Populate the alternatives array from PKG_RHEL (space-separated)
          # If there is no explicit RHEL mapping, fall back to the generic key.
          if [[ -n ${PKG_RHEL[$key]:-} ]]; then
            read -r -a alternatives <<< "${PKG_RHEL[$key]}"
          else
            alternatives=("$key")
          fi
          for m in "${alternatives[@]}"; do
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
      if [[ -n ${PKG_RHEL[$key]:-} ]]; then
        read -r -a mapped <<< "${PKG_RHEL[$key]}"
      else
        mapped=("$key")
      fi
      for m in "${mapped[@]}"; do
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
    # Detect package presence using the centralized helper
    # `rhel_key_installed` (it prefers representative binaries and
    # falls back to RPM package names listed in `PKG_RHEL`). This
    # avoids manual alternatives expansion here.
    if rhel_key_installed "$key"; then
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
  cat <<MSG

Missing packages detected: ${MISSING[*]}
Run: sudo $0 --install --yes
MSG
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

cat <<MSG

Bootstrap check completed. If you want to install missing packages, run: sudo $0 --install --yes
MSG

exit 0
