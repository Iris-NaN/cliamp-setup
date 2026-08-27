# cliamp-setup

cliamp（终端版 Winamp 风格音乐播放器）的一键配置脚本，支持 Arch / Debian / Fedora / macOS。

脚本默认只做「通用」部分（安装 cliamp + ffmpeg + yt-dlp + 基础配置），
所有地域相关 / 账号相关的增强功能都通过开关开启，保证对全球用户可移植。

## 快速开始

```bash
git clone https://github.com/Iris-NaN/cliamp-setup.git
cd cliamp-setup
chmod +x cliamp-setup.sh
./cliamp-setup.sh --cn      # 中国大陆用户一键预设
```

> 注：脚本支持 Linux 与 macOS。但 `--cn` 中的「国内 DNS」与「网易 CDN hosts」
> 两项为 Linux 专属（依赖 systemd-resolved / NetworkManager / `/etc/hosts`），
> 在 macOS 上会自动跳过并提示手动配置。

## 中国大陆预设 `--cn` 包含

- 启用网易云音乐（需提前在浏览器登录 music.163.com）
- 系统 DNS 改为国内优先（阿里 + 腾讯，1.1.1.1 兜底），并锁定 NetworkManager 不覆盖
- 网易域名固定到国内 CDN（写入 `/etc/hosts`，可重复运行刷新）
- hi-res 输出（96kHz / 32bit 浮点）
- 安装 playerctl，支持系统媒体键控制

> 为什么需要这些？网易云会把走国外 DNS 的用户调度到海外限速节点，
> 导致播放卡顿或超时。上述优化让流量走国内 CDN，速度从数十 KB/s 提升到数十 MB/s。

## 逐项控制（环境变量）

| 变量 | 默认 | 说明 |
|---|---|---|
| `NETEASE=1` | 0 | 启用网易云音乐 |
| `NETEASE_BROWSER=` | firefox | 读取 cookie 的浏览器 |
| `CN_DNS=1` | 0 | 系统 DNS 改国内优先 |
| `CN_HOSTS=1` | 0 | 网易域名固定到国内 CDN |
| `HIR_RES=1` | 0 | 启用 hi-res 输出 |
| `PLAYERCTL=1` | 1 | 安装 playerctl 媒体键 |
| `PROVIDER=netease` | 空 | 启动默认进入的源 |
| `MIRROR=ghfast.top` | ghfast.top | 下载镜像域名，留空 `""` 直连 GitHub |

示例：

```bash
# 只装基础 + 网易云，不改 DNS
NETEASE=1 ./cliamp-setup.sh

# 完全自定义
NETEASE=1 NETEASE_BROWSER=chromium CN_HOSTS=1 HIR_RES=1 ./cliamp-setup.sh
```

## 使用 cliamp

```bash
cliamp ~/Music                 # 播放本地目录
cliamp --provider netease      # 直接进网易云
# 播放中：
#   ? / Ctrl+K  查看全部快捷键
#   M           打开网易云
#   Ctrl+F      搜索网易云歌曲
#   y           歌词
#   f           收藏 ★
#   z           随机播放
#   Ctrl+S      保存歌曲到 ~/Music/cliamp
```

## 媒体键（playerctl）

```bash
playerctl play-pause          # 播放/暂停
playerctl next / previous     # 切歌
playerctl position 10+        # 快进 10 秒
playerctl volume 0.5          # 音量 50%
```

## 维护

- 网易 CDN 的 IP 会变化。若某天播放变慢，重新运行 `CN_HOSTS=1 ./cliamp-setup.sh` 刷新 hosts 即可。
- 升级 cliamp：`yay -S cliamp-bin`（AUR）或 `cliamp upgrade`。
