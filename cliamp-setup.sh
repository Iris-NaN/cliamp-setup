#!/usr/bin/env bash
# cliamp 一键配置脚本（支持 Linux / macOS）
#
# 把 cliamp 终端音乐播放器安装并配置为「开箱即用」：本地播放、网易云
#（可选）、媒体键控制（可选）、国内 CDN 加速（可选，仅对中国大陆用户有意义）。
#
# 默认只做「基础」部分（安装 + 基础配置），所有地域相关 / 账号相关的增强
# 功能都通过开关开启，避免对不需要的用户产生副作用。
#
# 中国大陆用户请直接用预设：
#   ./cliamp-setup.sh --cn
# 该预设等价于：
#   NETEASE=1 NETEASE_BROWSER=firefox CN_DNS=1 HIR_RES=1 PLAYERCTL=1 \
#   USE_YAY=0 ./cliamp-setup.sh
# （USE_YAY=0 让国内用户跳过慢速 AUR，改用镜像直下载二进制）
#
# 也可用环境变量逐项控制：
#   NETEASE=1           启用网易云音乐（需先在浏览器登录 music.163.com）
#   NETEASE_BROWSER=    读取 cookie 的浏览器：firefox/chromium/edge/...
#   CN_DNS=1            把系统 DNS 改为国内优先（阿里+腾讯，1.1.1.1 兜底）
#   CN_HOSTS=1          额外把网易域名固定到国内 CDN（写入 /etc/hosts）
#   HIR_RES=1           启用 hi-res 输出（96kHz / 32bit 浮点）
#   PLAYERCTL=1         安装 playerctl，支持系统媒体键控制
#   PROVIDER=netease    启动默认进入的源
#   MIRROR=github.dpik.top   下载镜像域名（留空 "" 则直连 GitHub）
#   USE_YAY=1           允许用 yay 安装（AUR）；设 0 强制走预编译二进制
#                       （AUR 在国内很慢，--cn 预设默认关闭）
#
set -euo pipefail

# ===================== 可配置项（默认值，通用优先） =====================
MIRROR="${MIRROR:-github.dpik.top}" # 国内下载镜像；留空 "" 则直连
NETEASE="${NETEASE:-0}"        # 是否启用网易云音乐
NETEASE_BROWSER="${NETEASE_BROWSER:-firefox}"
CN_DNS="${CN_DNS:-0}"        # 是否改系统 DNS 为国内优先
CN_HOSTS="${CN_HOSTS:-0}"    # 是否把网易域名固定到国内 CDN
HIR_RES="${HIR_RES:-0}"      # 是否启用 hi-res 输出
PLAYERCTL="${PLAYERCTL:-1}"  # 是否安装 playerctl 媒体键
PROVIDER="${PROVIDER:-}"     # 启动默认源，如 netease
CLIAMP_VER="${CLIAMP_VER:-}" # 指定版本，留空则取最新
USE_YAY="${USE_YAY:-}"       # 空=用 yay；设 0 强制预编译二进制（国内更快）

# ===================== 解析参数 =====================
while [[ $# -gt 0 ]]; do
  case "$1" in
  --cn)
    NETEASE=1
    CN_DNS=1
    HIR_RES=1
    PLAYERCTL=1
    NETEASE_BROWSER="${NETEASE_BROWSER:-firefox}"
    : "${USE_YAY:=0}" # AUR 在国内慢，CN 预设默认走预编译二进制
    ;;
  --netease) NETEASE=1 ;;
  --no-yay) USE_YAY=0 ;;
  --no-playerctl) PLAYERCTL=0 ;;
  --help | -h)
    sed -n '3,40p' "$0"
    exit 0
    ;;
  *)
    echo "未知参数: $1"
    exit 1
    ;;
  esac
  shift
done

# ===================== 基础函数 =====================
info() { echo -e "\033[36m[信息]\033[0m $*"; }
warn() { echo -e "\033[33m[警告]\033[0m $*"; }
ok() { echo -e "\033[32m[完成]\033[0m $*"; }
die() {
  echo -e "\033[31m[错误]\033[0m $*" >&2
  exit 1
}

# 依次尝试：用户镜像 -> 若干公共镜像 -> 直连 GitHub，返回首个可用的内容
CURL_OPT=(-fsSL --connect-timeout 10 --max-time 60)
gh_fetch() {
  local path="$1" u tmp
  local urls=()
  [[ -n "$MIRROR" ]] && urls+=("https://${MIRROR}/https://github.com/${path}")
  urls+=("https://ghproxy.net/https://github.com/${path}")
  urls+=("https://mirror.ghproxy.com/https://github.com/${path}")
  urls+=("https://github.com/${path}")
  tmp="$(mktemp)"
  for u in "${urls[@]}"; do
    info "尝试下载源: $u"
    if curl "${CURL_OPT[@]}" "$u" -o "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
      cat "$tmp"; rm -f "$tmp"; return 0
    fi
  done
  rm -f "$tmp"; return 1
}

# 同上，但把内容保存到文件 $1
gh_download() {
  local out="$1" path="$2" u
  local urls=()
  [[ -n "$MIRROR" ]] && urls+=("https://${MIRROR}/https://github.com/${path}")
  urls+=("https://ghproxy.net/https://github.com/${path}")
  urls+=("https://mirror.ghproxy.com/https://github.com/${path}")
  urls+=("https://github.com/${path}")
  for u in "${urls[@]}"; do
    info "尝试下载源: $u"
    if curl "${CURL_OPT[@]}" -o "$out" "$u" 2>/dev/null && [[ -s "$out" ]]; then
      return 0
    fi
  done
  return 1
}

need_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then return; fi
  command -v sudo >/dev/null 2>&1 || die "需要 root 权限，请安装 sudo 或以 root 运行"
  sudo -v || die "获取 sudo 权限失败"
}

# ===================== 检测系统（Linux / macOS） =====================
OS="$(uname -s)"
case "$OS" in
Linux)
  DISTRO="unknown"
  [[ -f /etc/os-release ]] && . /etc/os-release && DISTRO="${ID:-unknown}"
  [[ "$DISTRO" == "arch" || "$DISTRO" == "archlinux" || "$DISTRO" == "manjaro" ]] ||
    warn "当前发行版 $DISTRO 非 Arch，将尝试下载预编译二进制兜底"
  ;;
Darwin)
  warn "检测到 macOS，将使用 brew 与预编译二进制"
  ;;
*)
  die "本脚本仅支持 Linux / macOS，当前系统: $OS"
  ;;
esac

# ===================== 安装 cliamp =====================
install_cliamp() {
  if command -v cliamp >/dev/null 2>&1; then
    info "cliamp 已安装: $(cliamp --version 2>/dev/null)"
    return
  fi
  if [[ "$USE_YAY" != "0" ]] && command -v yay >/dev/null 2>&1; then
    need_sudo
    info "通过 AUR 安装 cliamp-bin（预编译，自带编解码库，免 Go 编译）"
    # 若用户改投源码包 cliamp，构建时需拉取 Go 模块，提前设国内 GOPROXY 避免被墙超时
    export GOPROXY="https://goproxy.cn,https://proxy.golang.org,direct"
    export GOFLAGS="${GOFLAGS:-} -mod=mod"
    yay -S --needed --noconfirm cliamp-bin
  else
    [[ "$USE_YAY" == "0" && -n "$(command -v yay 2>/dev/null)" ]] &&
      info "已跳过 yay（USE_YAY=0），改用预编译二进制"
    need_sudo
    if [[ -z "$CLIAMP_VER" ]]; then
      CLIAMP_VER="$(gh_fetch "bjarneo/cliamp/releases/latest" |
        grep -oE '"tag_name": *"v[^"]+"' | head -1 | grep -oE '[0-9.]+')" || true
    fi
    [[ -z "$CLIAMP_VER" ]] && die "无法获取 cliamp 最新版本（请检查网络或设置 MIRROR=\"\" 直连）"
    info "安装 cliamp v$CLIAMP_VER（预编译二进制）"
    local bin=""
    if [[ "$OS" == "Darwin" ]]; then
      bin="cliamp-darwin-amd64"
      [[ "$(uname -m)" == "arm64" ]] && bin="cliamp-darwin-arm64"
    else
      bin="cliamp-linux-amd64"
      [[ "$(uname -m)" == "aarch64" ]] && bin="cliamp-linux-arm64"
    fi
    gh_download /tmp/cliamp.tmp "bjarneo/cliamp/releases/download/v${CLIAMP_VER}/${bin}" ||
      die "下载 cliamp 失败（已尝试镜像与直连）"
    sudo install -m 755 /tmp/cliamp.tmp /usr/local/bin/cliamp
    rm -f /tmp/cliamp.tmp
    ok "cliamp 已装到 /usr/local/bin/cliamp"
  fi
}

# ===================== 依赖 =====================
install_pkg() {
  if command -v pacman >/dev/null 2>&1; then
    need_sudo; sudo pacman -S --needed --noconfirm "$@"
  elif command -v brew >/dev/null 2>&1; then
    brew install "$@"
  elif command -v apt-get >/dev/null 2>&1; then
    need_sudo; sudo apt-get install -y "$@"
  elif command -v dnf >/dev/null 2>&1; then
    need_sudo; sudo dnf install -y "$@"
  else
    warn "未检测到已知包管理器，请手动安装: $*"
  fi
}

install_deps() {
  info "安装可选依赖 ffmpeg / yt-dlp"
  install_pkg ffmpeg yt-dlp

  if [[ "$PLAYERCTL" == "1" ]]; then
    info "安装 playerctl（系统媒体键控制）"
    install_pkg playerctl
  fi
}

# ===================== 音频桥接 =====================
check_audio() {
  if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
    ok "检测到 PulseAudio/PipeWire 音频服务"
  else
    warn "未检测到运行中的音频服务，请确认 PipeWire/PulseAudio 已启动"
  fi
  if command -v pacman >/dev/null 2>&1; then
    need_sudo
    if ! pacman -Q pipewire-alsa >/dev/null 2>&1 && ! pacman -Q pulseaudio-alsa >/dev/null 2>&1; then
      warn "建议安装 ALSA 桥接：sudo pacman -S pipewire-alsa"
    fi
  elif [[ "$OS" == "Darwin" ]]; then
    ok "macOS 使用系统音频，无需额外桥接"
  fi
}

# ===================== 配置文件 =====================
write_config() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/cliamp"
  mkdir -p "$dir"

  info "写入配置: $dir/config.toml"
  {
    echo "# cliamp 配置（由 cliamp-setup 生成）"
    echo "volume = 0"
    echo "repeat = \"off\""
    echo "shuffle = true"
    echo "initial_directory = \"~/Music\""
    echo "eq_preset = \"Flat\""
    echo "eq = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]"
    [[ -n "$PROVIDER" ]] && echo "provider = \"$PROVIDER\""

    if [[ "$HIR_RES" == "1" ]]; then
      echo ""
      echo "# 高解析输出"
      echo "sample_rate = 96000"
      echo "buffer_ms = 250"
      echo "resample_quality = 4"
      echo "bit_depth = 32"
    fi

    if [[ "$NETEASE" == "1" ]]; then
      echo ""
      echo "# 网易云音乐（需先在 $NETEASE_BROWSER 登录 music.163.com）"
      echo "[netease]"
      echo "enabled = true"
      echo "cookies_from = \"$NETEASE_BROWSER\""
    fi
  } >"$dir/config.toml"

  if [[ ! -f "$dir/radios.toml" ]]; then
    info "写入示例电台: $dir/radios.toml"
    cat >"$dir/radios.toml" <<'EOF'
# 自定义电台：按 R 打开电台浏览器时会与内置电台一起显示
[[station]]
name = "SomaFM Groove Salad"
url = "https://ice1.somafm.com/groovesalad-128-mp3"

[[station]]
name = "SomaFM Lush"
url = "https://ice1.somafm.com/lush-128-mp3"

[[station]]
name = "Radio Paradise Main Mix"
url = "https://stream.radioparadise.com/mp3-128"
EOF
  fi
}

# ===================== yt-dlp 配置 =====================
write_ytdlp_config() {
  [[ "$CN_DNS" != "1" && "$CN_HOSTS" != "1" ]] && return
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp"
  mkdir -p "$dir"
  info "写入 yt-dlp 配置: $dir/config"
  {
    echo "# cliamp 调用 yt-dlp 时会读取本文件"
    if [[ "$CN_DNS" == "1" || "$CN_HOSTS" == "1" ]]; then
      echo "# 强制 IPv4，避免 IPv6 到国内 CDN 的可疑路由导致卡顿"
      echo "--force-ipv4"
    fi
    echo "--retries 10"
    echo "--socket-timeout 15"
    echo "--retry-sleep 2"
  } >"$dir/config"
}

# ===================== 国内 DNS =====================
setup_cn_dns() {
  [[ "$CN_DNS" != "1" ]] && return
  [[ "$OS" == "Darwin" ]] && { warn "macOS 不支持自动切换系统 DNS，请在系统设置中手动配置"; return; }
  need_sudo
  info "将系统 DNS 改为国内优先（阿里 + 腾讯，1.1.1.1 兜底）"
  [[ -f /etc/resolv.conf ]] && sudo cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%s)

  if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    sudo mkdir -p /etc/systemd/resolved.conf.d
    printf '[Resolve]\nDNS=223.5.5.5 119.29.29.29 1.1.1.1\nDNSDefault=223.5.5.5\n' |
      sudo tee /etc/systemd/resolved.conf.d/cliamp.conf >/dev/null
    sudo systemctl restart systemd-resolved
  elif systemctl is-active --quiet NetworkManager 2>/dev/null; then
    sudo mkdir -p /etc/NetworkManager/conf.d
    printf '[main]\ndns=none\n' | sudo tee /etc/NetworkManager/conf.d/dns.conf >/dev/null
    sudo systemctl reload NetworkManager
    printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\nnameserver 1.1.1.1\n' | sudo tee /etc/resolv.conf >/dev/null
  else
    printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\nnameserver 1.1.1.1\n' | sudo tee /etc/resolv.conf >/dev/null
  fi
  ok "DNS 已切换为国内优先"
}

# ===================== 国内 hosts 固定 =====================
setup_cn_hosts() {
  [[ "$CN_HOSTS" != "1" ]] && return
  [[ "$OS" == "Darwin" ]] && { warn "macOS 不支持自动写入网易 CDN hosts，已跳过"; return; }
  need_sudo
  command -v python3 >/dev/null 2>&1 || die "解析网易 CDN 需要 python3，请先安装"
  info "把网易域名固定到国内 CDN（写入 /etc/hosts，带可更新标记）"
  local hosts="/etc/hosts"
  sudo cp "$hosts" "${hosts}.bak.$(date +%s)"

  local domains="music.163.com interface.music.163.com"
  for n in 700 701 702 703 704 705 706 707 708 709 710 800 801 802 803 804 805 806 807 808 809 810 821 851; do
    domains="$domains m${n}.music.126.net"
  done
  domains="$domains p1.music.126.net p2.music.126.net p3.music.126.net p4.music.126.net p5.music.126.net"

  sudo sed -i "/# === cliamp netease cdn/,/# === cliamp netease cdn end/d" "$hosts"

  local tmp
  tmp="$(mktemp)"
  {
    echo ""
    echo "# === cliamp netease cdn ($(date +%F) 生成，可重跑脚本刷新)"
    for d in $domains; do
      local ip=""
      ip="$(curl -fsS --max-time 6 "https://dns.alidns.com/resolve?name=$d&type=A" |
        python3 -c "import json,sys
try:
  data=json.load(sys.stdin)
  ips=[a['data'] for a in data.get('Answer',[]) if a['type']==1]
  print(ips[0] if ips else '')
except: pass" 2>/dev/null)"
      [[ -n "$ip" ]] && echo "$ip $d"
    done
    echo "# === cliamp netease cdn end"
  } >"$tmp"
  cat "$tmp" | sudo tee -a "$hosts" >/dev/null
  rm -f "$tmp"
  ok "/etc/hosts 已更新网易国内 CDN 条目"
}

# ===================== 主流程 =====================
main() {
  info "开始配置 cliamp ..."
  install_cliamp
  install_deps
  check_audio
  write_config
  write_ytdlp_config
  setup_cn_dns
  setup_cn_hosts
  ok "全部完成！"
  echo ""
  echo "使用方法："
  echo "  cliamp ~/Music           # 播放本地目录"
  [[ "$NETEASE" == "1" ]] && echo "  cliamp --provider netease   # 或启动后按 M 进入网易云"
  echo "  播放中按 ? 或 Ctrl+K 查看全部快捷键"
  [[ "$PLAYERCTL" == "1" ]] && echo "  媒体键 / playerctl play-pause 可控制播放"
}

main "$@"
