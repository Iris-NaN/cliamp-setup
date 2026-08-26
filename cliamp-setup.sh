#!/usr/bin/env bash
# cliamp 一键配置脚本
#
# 适用于 Arch / Debian(Ubuntu) / Fedora / macOS，把 cliamp 终端音乐播放器
# 安装并配置为「开箱即用」：本地播放、网易云（可选）、媒体键控制（可选）、
# 国内 CDN 加速（可选，仅对中国大陆用户有意义）。
#
# 默认只做「通用」部分（安装 + 基础配置），所有地域相关 / 账号相关的
# 增强功能都通过开关开启，保证脚本对全球用户都可移植。
#
# 中国大陆用户请直接用预设：
#   ./cliamp-setup.sh --cn
# 该预设等价于：
#   NETEASE=1 NETEASE_BROWSER=firefox CN_DNS=1 HIR_RES=1 PLAYERCTL=1 \
#   ./cliamp-setup.sh
#
# 也可用环境变量逐项控制：
#   NETEASE=1           启用网易云音乐（需先在浏览器登录 music.163.com）
#   NETEASE_BROWSER=    读取 cookie 的浏览器：firefox/chromium/edge/...
#   CN_DNS=1            把系统 DNS 改为国内优先（阿里+腾讯，1.1.1.1 兜底）
#   CN_HOSTS=1          额外把网易域名固定到国内 CDN（写入 /etc/hosts）
#   HIR_RES=1           启用 hi-res 输出（96kHz / 32bit 浮点）
#   PLAYERCTL=1         安装 playerctl，支持系统媒体键控制
#   PROVIDER=netease    启动默认进入的源
#   MIRROR=ghfast.top   下载镜像域名（留空则直连 GitHub）
#
set -euo pipefail

# ===================== 可配置项（默认值，通用优先） =====================
MIRROR="${MIRROR:-ghfast.top}"        # 国内下载镜像；留空 "" 则直连
NETEASE="${NETEASE:-0}"               # 是否启用网易云音乐
NETEASE_BROWSER="${NETEASE_BROWSER:-firefox}"
CN_DNS="${CN_DNS:-0}"                 # 是否改系统 DNS 为国内优先
CN_HOSTS="${CN_HOSTS:-0}"             # 是否把网易域名固定到国内 CDN
HIR_RES="${HIR_RES:-0}"               # 是否启用 hi-res 输出
PLAYERCTL="${PLAYERCTL:-1}"           # 是否安装 playerctl 媒体键
PROVIDER="${PROVIDER:-}"              # 启动默认源，如 netease
CLIAMP_VER="${CLIAMP_VER:-}"          # 指定版本，留空则取最新

# ===================== 解析参数 =====================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cn) NETEASE=1; CN_DNS=1; HIR_RES=1; PLAYERCTL=1; NETEASE_BROWSER="${NETEASE_BROWSER:-firefox}";;
    --netease) NETEASE=1;;
    --no-playerctl) PLAYERCTL=0;;
    --help|-h) sed -n '3,40p' "$0"; exit 0;;
    *) echo "未知参数: $1"; exit 1;;
  esac
  shift
done

# ===================== 基础函数 =====================
info()  { echo -e "\033[36m[信息]\033[0m $*"; }
warn()  { echo -e "\033[33m[警告]\033[0m $*"; }
ok()    { echo -e "\033[32m[完成]\033[0m $*"; }
die()   { echo -e "\033[31m[错误]\033[0m $*" >&2; exit 1; }

# 带镜像前缀的 GitHub 下载地址
gh_url() {
  local path="$1"
  if [[ -n "$MIRROR" ]]; then
    echo "https://${MIRROR}/https://github.com/${path}"
  else
    echo "https://github.com/${path}"
  fi
}

need_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then return; fi
  if ! command -v sudo >/dev/null 2>&1; then
    die "需要 root 权限，请安装 sudo 或以 root 运行"
  fi
  sudo -v || die "获取 sudo 权限失败"
}

# ===================== 检测系统 =====================
OS="$(uname -s)"
case "$OS" in
  Linux)   ;;
  Darwin)  ;;
  *) die "不支持的操作系统: $OS" ;;
esac

DISTRO="unknown"
if [[ "$OS" == "Linux" ]]; then
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO="${ID:-unknown}"
  fi
fi

info "检测到系统: $OS / $DISTRO"

# ===================== 安装 cliamp =====================
install_cliamp() {
  if command -v cliamp >/dev/null 2>&1; then
    info "cliamp 已安装: $(cliamp --version 2>/dev/null)"
    return
  fi

  case "$DISTRO" in
    arch|archlinux|manjaro)
      if command -v yay >/dev/null 2>&1; then
        need_sudo
        info "通过 AUR 安装 cliamp-bin（预编译，自带编解码库）"
        yay -S --needed --noconfirm cliamp-bin
      else
        warn "未找到 yay，尝试直接下载预编译二进制"
        install_cliamp_bin
      fi
      ;;
    debian|ubuntu|linuxmint|fedora|rhel|centos)
      install_cliamp_bin
      ;;
    *)
      if [[ "$OS" == "Darwin" ]]; then
        if command -v brew >/dev/null 2>&1; then
          info "通过 Homebrew 安装"
          brew install bjarneo/cliamp/cliamp
        else
          install_cliamp_bin
        fi
      else
        install_cliamp_bin
      fi
      ;;
  esac
}

install_cliamp_bin() {
  need_sudo
  [[ -z "$CLIAMP_VER" ]] && CLIAMP_VER="$(curl -fsSL "$(gh_url bjarneo/cliamp/releases/latest)" | grep -oE '"tag_name": *"v[^"]+"' | head -1 | grep -oE '[0-9.]+')"
  [[ -z "$CLIAMP_VER" ]] && die "无法获取 cliamp 最新版本"
  info "安装 cliamp v$CLIAMP_VER"
  local bin="cliamp-linux-amd64"
  [[ "$(uname -m)" == "aarch64" ]] && bin="cliamp-linux-arm64"
  local url="$(gh_url "bjarneo/cliamp/releases/download/v${CLIAMP_VER}/${bin}")"
  curl -fL --retry 3 -o /tmp/cliamp.tmp "$url" || die "下载 cliamp 失败"
  sudo install -m 755 /tmp/cliamp.tmp /usr/local/bin/cliamp
  rm -f /tmp/cliamp.tmp
  ok "cliamp 已装到 /usr/local/bin/cliamp"
}

# ===================== 依赖 =====================
install_deps() {
  info "安装可选依赖 ffmpeg / yt-dlp（扩展格式与在线源）"
  case "$DISTRO" in
    arch|archlinux|manjaro)
      need_sudo
      sudo pacman -S --needed --noconfirm ffmpeg yt-dlp
      ;;
    debian|ubuntu|linuxmint)
      need_sudo
      sudo apt-get update -y && sudo apt-get install -y ffmpeg yt-dlp
      ;;
    fedora|rhel|centos)
      need_sudo
      sudo dnf install -y ffmpeg yt-dlp
      ;;
    *)
      if [[ "$OS" == "Darwin" ]]; then
        command -v brew >/dev/null 2>&1 && brew install ffmpeg yt-dlp
      else
        warn "请手动安装 ffmpeg 与 yt-dlp"
      fi
      ;;
  esac

  if [[ "$PLAYERCTL" == "1" ]]; then
    info "安装 playerctl（系统媒体键控制）"
    case "$DISTRO" in
      arch|archlinux|manjaro) need_sudo; sudo pacman -S --needed --noconfirm playerctl ;;
      debian|ubuntu|linuxmint) need_sudo; sudo apt-get install -y playerctl ;;
      fedora|rhel|centos) need_sudo; sudo dnf install -y playerctl ;;
      *) [[ "$OS" == "Darwin" ]] && command -v brew >/dev/null && brew install playerctl ;;
    esac
  fi
}

# ===================== 音频桥接（仅 Linux） =====================
check_audio() {
  [[ "$OS" != "Linux" ]] && return
  if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
    ok "检测到 PulseAudio/PipeWire 音频服务"
  elif command -v pipewire >/dev/null 2>&1; then
    warn "未检测到运行中的音频服务，请确认 PipeWire/PulseAudio 已启动"
  fi

  case "$DISTRO" in
    arch|archlinux|manjaro)
      need_sudo
      if ! pacman -Q pipewire-alsa >/dev/null 2>&1 && ! pacman -Q pulseaudio-alsa >/dev/null 2>&1; then
        warn "建议安装 ALSA 桥接：sudo pacman -S pipewire-alsa"
      fi
      ;;
  esac
}

# ===================== 配置文件 =====================
write_config() {
  local dir
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then dir="$XDG_CONFIG_HOME/cliamp"; else dir="$HOME/.config/cliamp"; fi
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
  } > "$dir/config.toml"

  # 自定义电台
  if [[ ! -f "$dir/radios.toml" ]]; then
    info "写入示例电台: $dir/radios.toml"
    cat > "$dir/radios.toml" <<'EOF'
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
  local dir
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then dir="$XDG_CONFIG_HOME/yt-dlp"; else dir="$HOME/.config/yt-dlp"; fi
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
  } > "$dir/config"
}

# ===================== 国内 DNS =====================
setup_cn_dns() {
  [[ "$CN_DNS" != "1" ]] && return
  need_sudo
  info "将系统 DNS 改为国内优先（阿里 + 腾讯，1.1.1.1 兜底）"
  # 备份
  [[ -f /etc/resolv.conf ]] && sudo cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%s)

  if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    sudo mkdir -p /etc/systemd/resolved.conf.d
    printf '[Resolve]\nDNS=223.5.5.5 119.29.29.29 1.1.1.1\nDNSDefault=223.5.5.5\n' | sudo tee /etc/systemd/resolved.conf.d/cliamp.conf >/dev/null
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
  need_sudo
  info "把网易域名固定到国内 CDN（写入 /etc/hosts，带可更新标记）"
  local domains="music.163.com interface.music.163.com"
  for n in 700 701 702 703 704 705 706 707 708 709 710 800 801 802 803 804 805 806 807 808 809 810 821 851; do
    domains="$domains m${n}.music.126.net"
  done
  domains="$domains p1.music.126.net p2.music.126.net p3.music.126.net p4.music.126.net p5.music.126.net"

  # 先移除旧区块
  sudo sed -i "/# === cliamp netease cdn/,/# === cliamp netease cdn end/d" /etc/hosts

  local tmp; tmp="$(mktemp)"
  {
    echo ""
    echo "# === cliamp netease cdn ($(date +%F) 生成，可重跑脚本刷新)"
    for d in $domains; do
      local ip=""
      ip="$(curl -fsS --max-time 6 "https://dns.alidns.com/resolve?name=$d&type=A" \
            | python3 -c "import json,sys
try:
  data=json.load(sys.stdin)
  ips=[a['data'] for a in data.get('Answer',[]) if a['type']==1]
  print(ips[0] if ips else '')
except: pass" 2>/dev/null)"
      [[ -n "$ip" ]] && echo "$ip $d"
    done
    echo "# === cliamp netease cdn end"
  } > "$tmp"
  cat "$tmp" | sudo tee -a /etc/hosts >/dev/null
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
