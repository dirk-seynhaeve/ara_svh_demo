#!/usr/bin/env bash
# Bootstrap script for Ara project (host)
# - Run with --check to print what would be installed and detection results
# - Run with --install to perform package install (requires sudo)
# - Run with --yes to skip confirmation

set -eu
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PKGS=(
  # Essential build tools: compilers, make, linker
  build-essential
  # Build-system generators and ninja backend for LLVM/Verilator
  cmake
  ninja-build
  # Autotools for projects using autoconf/automake
  autoconf
  automake
  libtool
  pkg-config

  # Documentation/build helpers
  texinfo    # for make install/docs
  help2man   # generates manpages

  # Parser/lexer generators used by some tools
  flex       # lexical analyser generator
  bison      # parser generator

  # Compilers
  clang      # optional: used for LLVM/Verilator builds
  gcc        # host C compiler
  g++        # host C++ compiler

  # If building with clang, libc++ headers/libs are useful
  libc++-dev
  libc++abi-dev

  # Python and git for helper scripts and submodule tooling
  python3
  python3-pip
  git

  # Optional helpers to speed up repeated builds
  ccache

  # Verilator and toolchain prerequisites
  libelf-dev   # ELF manipulation (used when reading/writing ELF files)
  zlib1g       # runtime zlib (commonly present)
  zlib1g-dev   # zlib headers/libs for optional compression support
  libfl-dev    # libfl (flex) development files
)

# Add kernel headers package (dynamic name e.g. linux-headers-5.15.0-58-generic)
KHEADERS="linux-headers-$(uname -r)"
PKGS+=("$KHEADERS")

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
  echo "Packages to install: ${PKGS[*]}"
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
      echo "Installing Development Tools group (may require sudo)..."
      sudo $PKG_MANAGER groupinstall -y "Development Tools" || true
    fi
    # Translate package names and install
    RHEL_INSTALL=()
    for p in "${PKGS[@]}"; do
      # skip build-essential because covered by groupinstall
      if [[ "$p" == "build-essential" ]]; then
        continue
      fi
      # map linux-headers-* to kernel-devel
      mapped=$(translate_rhel "$p")
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
    if [[ ${#unique[@]} -gt 0 ]]; then
      echo "Installing: ${unique[*]}"
      sudo $PKG_MANAGER install -y "${unique[@]}"
    fi
    echo "Install finished (if successful). You may still need to pass clang flags when building Verilator."
    exit 0
  else
    # Default to Debian/apt path
    sudo apt update
    sudo apt install -y "${PKGS[@]}"
    echo "Packages installed (if successful). You may still need to pass clang flags when building Verilator."
    exit 0
  fi
fi

# --- CHECK MODE ---

echo "Checking installed packages..."
MISSING=()
# Compute the maximum package name length so the status column aligns
maxlen=0
for p in "${PKGS[@]}"; do
  plen=${#p}
  if (( plen > maxlen )); then
    maxlen=$plen
  fi
done
for p in "${PKGS[@]}"; do
  if [[ "$DISTRO_FAMILY" == "rhel" ]]; then
    # translate and test any of the possible RHEL package names
    alternatives=$(translate_rhel "$p")
    found=1
    for alt in $alternatives; do
      if rpm -q "$alt" >/dev/null 2>&1; then
        found=0
        break
      fi
    done
    if [[ $found -eq 0 ]]; then
      printf "  %-${maxlen}s : ${GREEN}%s${RESET}\n" "$p" "installed"
    else
      printf "  %-${maxlen}s : ${RED}%s${RESET}\n" "$p" "MISSING"
      MISSING+=("$p")
    fi
  else
    if dpkg -s "$p" >/dev/null 2>&1; then
      printf "  %-${maxlen}s : ${GREEN}%s${RESET}\n" "$p" "installed"
    else
      printf "  %-${maxlen}s : ${RED}%s${RESET}\n" "$p" "MISSING"
      MISSING+=("$p")
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
