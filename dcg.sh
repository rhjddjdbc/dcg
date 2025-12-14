#!/usr/bin/env bash
set -euo pipefail

# ==================== Config (Defaults) ====================
readonly BASE_IMAGES=("alpine:3.18" "debian:12" "debian:bookworm")
DEFAULT_BASE="alpine:3.18"
DEFAULT_USER="devuser"
DEFAULT_UID="1000"
DEFAULT_WORKDIR="/workspace"

# CLI state (mutable)
PROFILE_CHOICES=()
DRY_RUN=false
BASE_IMAGE="$DEFAULT_BASE"
USER_NAME="$DEFAULT_USER"
USER_UID="$DEFAULT_UID"
WORKDIR="$DEFAULT_WORKDIR"
CATEGORY_STRING=""
INSTALL_ZSH=false
BUILD_RUN=false

# ==================== Usage ====================
usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --base <image>         Base image (default: $DEFAULT_BASE)
  --profile <profile>    Predefined profile: WebDev|Embedded|DataScience|RE|FullStack (can be repeated)
  --categories "<list>"  Space-separated categories, e.g. "C Python Node Database"
  --user <name>          Username (default: $DEFAULT_USER)
  --uid <uid>            User ID (default: $DEFAULT_UID)
  --workdir <path>       Working directory (default: $DEFAULT_WORKDIR)
  --zsh                  Install zsh and recommended plugins (syntax highlighting, autosuggestions)
  --dry-run              Print Dockerfile to stdout instead of writing
  --build-run            Build and run the Docker container after generation
  -h, --help             Show this help
EOF
}

# ==================== CLI Parsing ====================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)       BASE_IMAGE="$2"; shift 2 ;;
    --profile)    PROFILE_CHOICES+=("$2"); shift 2 ;;
    --categories) CATEGORY_STRING="$2"; shift 2 ;;
    --user)       USER_NAME="$2"; shift 2 ;;
    --uid)        USER_UID="$2"; shift 2 ;;
    --workdir)    WORKDIR="$2"; shift 2 ;;
    --zsh)        INSTALL_ZSH=true; shift ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --build-run)  BUILD_RUN=true; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Ensure USER_UID is numeric and trimmed
USER_UID=$(echo "$USER_UID" | xargs)
if ! [[ "$USER_UID" =~ ^[0-9]+$ ]]; then
  echo "Error: uid must be numeric: '$USER_UID'"
  exit 1
fi

# Check if BASE_IMAGE is valid
if [[ ! " ${BASE_IMAGES[*]} " =~ " $BASE_IMAGE " ]]; then
  echo "Warning: '${BASE_IMAGE}' is not in the officially tested base images."
  echo "Tested images: ${BASE_IMAGES[*]}"
  echo "Continuing anyway..."
fi

# ==================== Package maps ====================
declare -A PACKAGE_MAP
PKG_INSTALL_CMD=""
ADD_USER_CMD=""
PKG_UPDATE_CMD=""
PKG_CLEAN_CMD=""

set_package_map_alpine() {
  PKG_INSTALL_CMD="apk add --no-cache"
  PKG_UPDATE_CMD="true"
  PKG_CLEAN_CMD="true"
  ADD_USER_CMD="adduser -D -u"
  PACKAGE_MAP=(
    [gcc]=gcc [make]=make [clang]=clang [build-base]=build-base [valgrind]=valgrind
    [python3]=python3 [python3-pip]=py3-pip [ipython]=py3-ipython [jupyter]=py3-jupyterlab
    [numpy]=py3-numpy [pandas]=py3-pandas [matplotlib]=py3-matplotlib
    [nodejs]=nodejs [npm]=npm [yarn]=yarn
    [nano]=nano [neovim]=neovim
    [curl]=curl [wget]=wget [netcat]=netcat-openbsd [tcpdump]=tcpdump [nmap]=nmap
    [gdb]=gdb [strace]=strace [ltrace]=ltrace [binutils]=binutils
    [radare2]=radare2 [file]=file [readelf]=binutils [lsof]=lsof [objdump]=binutils
    [rust]=rust [cargo]=cargo [rustfmt]=rustfmt [rust-analyzer]=rust-analyzer
    [sqlite]=sqlite [postgresql-client]=postgresql-client [redis-tools]=redis
    [bash]=bash
    [git]=git [ca-certificates]=ca-certificates
    [zsh]=zsh
  )
}

set_package_map_debian() {
  PKG_INSTALL_CMD="apt-get install -y --no-install-recommends"
  PKG_UPDATE_CMD="apt-get update"
  PKG_CLEAN_CMD="rm -rf /var/lib/apt/lists/*"
  ADD_USER_CMD="useradd -m -u"
  PACKAGE_MAP=(
    [gcc]=gcc [make]=make [clang]=clang [build-base]=build-essential [valgrind]=valgrind
    [python3]=python3 [python3-pip]=python3-pip [ipython]=ipython3 [jupyter]=jupyter-notebook
    [numpy]=python3-numpy [pandas]=python3-pandas [matplotlib]=python3-matplotlib
    [nodejs]=nodejs [npm]=npm [yarn]=yarnpkg
    [nano]=nano [neovim]=neovim
    [curl]=curl [wget]=wget [netcat]=netcat-traditional [tcpdump]=tcpdump [nmap]=nmap
    [gdb]=gdb [strace]=strace [ltrace]=ltrace [binutils]=binutils
    [file]=file [readelf]=binutils [lsof]=lsof [objdump]=binutils
    [rust]=rustc [cargo]=cargo
    [sqlite]=sqlite3 [postgresql-client]=postgresql-client [redis-tools]=redis-tools
    [bash]=bash 
    [git]=git [ca-certificates]=ca-certificates
    [zsh]=zsh
  )
}

if [[ "$BASE_IMAGE" == alpine* ]]; then
  set_package_map_alpine
  ZSH_SHELL_PATH="/bin/zsh"
else
  set_package_map_debian
  ZSH_SHELL_PATH="/bin/zsh"
fi

# ==================== Categories & Profiles ====================
declare -A CATEGORIES=(
  [C]="gcc make clang build-base gdb strace ltrace binutils valgrind"
  [Rust]="rust cargo rustfmt clippy rust-analyzer"
  [Python]="python3 python3-pip ipython jupyter numpy pandas matplotlib"
  [Node]="nodejs npm yarn"
  [Editors]="nano neovim"
  [Network]="curl wget netcat tcpdump nmap git ca-certificates"
  [Debugging/RE]="gdb strace ltrace radare2 file readelf lsof objdump valgrind"
  [Database]="sqlite postgresql-client redis-tools"
  [test]="git curl ca-certificates nano binutils"
)

declare -A PROFILES=(
  [WebDev]="Node Python Editors Network Database"
  [Embedded]="C Rust Editors Network Debugging/RE"
  [DataScience]="Python Editors Database"
  [RE]="Debugging/RE C Editors Network"
  [FullStack]="Node Python Editors Database Network C Rust Debugging/RE"
  [test]="test"
)

selected_categories=()
for profile in "${PROFILE_CHOICES[@]:-}"; do
  profile=$(echo "$profile" | xargs)
  if [[ -n "${PROFILES[$profile]:-}" ]]; then
    read -ra cats <<< "${PROFILES[$profile]}"
    selected_categories+=("${cats[@]}")
  else
    echo "Warning: Unknown profile '$profile'"
  fi
done

if [[ -n "$CATEGORY_STRING" ]]; then
  read -ra extra <<< "$CATEGORY_STRING"
  selected_categories+=("${extra[@]}")
fi

# Remove duplicates
if [[ ${#selected_categories[@]} -gt 0 ]]; then
  mapfile -t selected_categories < <(printf '%s\n' "${selected_categories[@]}" | awk '!seen[$0]++')
fi

# ==================== Resolve Packages ====================
all_packages=()

for cat in "${selected_categories[@]:-}"; do
  if [[ -n "${CATEGORIES[$cat]:-}" ]]; then
    read -ra tools <<< "${CATEGORIES[$cat]}"
    for tool in "${tools[@]}"; do
      if [[ -n "${PACKAGE_MAP[$tool]:-}" ]]; then
        read -ra pkgs <<< "${PACKAGE_MAP[$tool]}"
        all_packages+=("${pkgs[@]}")
      else
        echo "Warning: Tool '$tool' not found in PACKAGE_MAP, skipping."
      fi
    done
  else
    echo "Warning: Unknown category '$cat'"
  fi
done

# Always include safety packages
all_packages+=("git" "ca-certificates" "bash" "curl")

if [ "$INSTALL_ZSH" = true ]; then
    all_packages+=("zsh")
fi

# Remove duplicates
mapfile -t all_packages < <(printf '%s\n' "${all_packages[@]}" | awk '!seen[$0]++')

packages="${all_packages[*]:-none}"

# ==================== Helper ====================
detect_container_tool() {
  if command -v podman &>/dev/null; then
    echo "podman"
  elif command -v docker &>/dev/null; then
    echo "docker"
  else
    echo "Error: Neither Docker nor Podman found on your system. Please install one of them."
    exit 1
  fi
}

build_and_run_container() {
  local tag="$1"
  local tool="$2"
  
  echo "Using $tool to build and run the container with tag: $tag"

  echo "Building image: $tag"
  if ! $tool build -t "$tag" .; then
    echo "Error: Image build failed"
    exit 1
  fi

  echo "Running container: $tag"
  if ! $tool run --rm -it "$tag"; then
    echo "Error: Container run failed"
    exit 1
  fi
}

# ==================== Gen Dockerfile ====================
generate_dockerfile() {
  local default_shell="/bin/bash"
  if [ "$INSTALL_ZSH" = true ]; then
    default_shell="/bin/zsh"
  elif [[ "$BASE_IMAGE" == alpine* ]]; then
    default_shell="/bin/ash"
  fi

  local user_home="/home/$USER_NAME"

  cat <<EOF
FROM $BASE_IMAGE
LABEL maintainer="$USER_NAME" \
      description="Dev container generated by $(basename "$0")"
EOF

  [[ "$BASE_IMAGE" != alpine* ]] && echo -e "\nARG DEBIAN_FRONTEND=noninteractive"

  [[ -n "$packages" ]] && {
    echo -e "\n# Install packages"
    if [[ "$BASE_IMAGE" == alpine* ]]; then
      echo "RUN $PKG_INSTALL_CMD $packages git curl"
    else
      cat <<EOF
RUN $PKG_UPDATE_CMD && \\
    $PKG_INSTALL_CMD $packages git curl && \\
    $PKG_CLEAN_CMD
EOF
    fi
  }

  # User creation
  echo -e "\n# Create user"
  if [[ "$BASE_IMAGE" == alpine* ]]; then
    echo "RUN getent passwd $USER_NAME || adduser -D -u $USER_UID -s $default_shell $USER_NAME"
  else
    echo "RUN getent passwd $USER_NAME || useradd -m -u $USER_UID -s $default_shell $USER_NAME"
  fi

  # Ensure workdir exists
  echo "RUN mkdir -p $WORKDIR && chown -R $USER_UID:$USER_UID $WORKDIR"
  echo "WORKDIR $WORKDIR"
  echo "ENV HOME=$user_home"

  # Copy current directory
  echo "COPY --chown=$USER_UID:$USER_UID . $WORKDIR"

# ==================== ZSH Setup ====================
if [ "$INSTALL_ZSH" = true ]; then
  echo -e "\n# Install Oh-My-Zsh + plugins for $USER_NAME"
  cat <<EOF
RUN ZSH_CUSTOM=/home/$USER_NAME/.oh-my-zsh/custom && \\
    if [ ! -d /home/$USER_NAME/.oh-my-zsh ]; then \\
        sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; \\
    fi && \\
    mkdir -p \$ZSH_CUSTOM/plugins && \\
    [ ! -d "\$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions \$ZSH_CUSTOM/plugins/zsh-autosuggestions || echo "zsh-autosuggestions already installed" && \\
    [ ! -d "\$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \$ZSH_CUSTOM/plugins/zsh-syntax-highlighting || echo "zsh-syntax-highlighting already installed" && \\
    if [ -f /home/$USER_NAME/.zshrc ]; then \\
        sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' /home/$USER_NAME/.zshrc; \\
    fi && \\
    chown -R $USER_UID:$USER_UID /home/$USER_NAME
EOF
fi


  # Set default user and shell
  echo -e "\n# Default user and shell"
  echo "USER $USER_UID"
  echo "CMD [\"$default_shell\"]"
}
# ==================== Output ====================
if $DRY_RUN; then
  generate_dockerfile || { echo "Error generating Dockerfile"; exit 1; }
else
  generate_dockerfile > Dockerfile || { echo "Error generating Dockerfile"; exit 1; }
  echo "Dockerfile generated successfully!"
  echo "   Base: $BASE_IMAGE"
  echo "   User: $USER_NAME (uid: $USER_UID)"
  echo "   Profiles: ${PROFILE_CHOICES[*]:-none}"
  echo "   Categories: ${selected_categories[*]:-none}"
  echo -n "   Packages: "
  if [[ -n "${packages}" ]]; then
    echo "$packages"
  else
    echo "none"
  fi
fi

# Build and run only if not dry-run
if $BUILD_RUN && ! $DRY_RUN; then
  container_tool=$(detect_container_tool)
  IMAGE_TAG="${USER_NAME}_container:latest"
  build_and_run_container "$IMAGE_TAG" "$container_tool"
fi
