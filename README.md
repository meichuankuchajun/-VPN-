# 一键 VPS 代理栈安装器

这个项目用于在 Linux VPS 上一键部署一套可直接使用、可直接分发的代理环境，包含：

* `Xray VMess`
* `Xray VLESS Reality`
* `Shadowsocks 兼容版`：`aes-256-gcm`
* `Shadowsocks 2022`：`2022-blake3-aes-256-gcm`
* 轻量级 HTTP 订阅文件服务器
* 两个可直接导入 Clash / Mihomo 的订阅链接

这个项目的目标不是做一个复杂面板，而是提供一套：

* 别人拿到脚本就能直接部署
* 部署完成就能直接拿到订阅链接
* 兼顾旧客户端兼容性和新协议支持
* 支持测试栈隔离和卸载清理

## 功能概览

安装脚本会自动完成：

1. 安装 `Xray`
2. 安装 `Shadowsocks Rust`
3. 生成各协议所需的 UUID、密码、Reality 密钥
4. 写入配置文件
5. 创建 `systemd` 服务
6. 部署一个轻量 HTTP 订阅服务器
7. 生成两个随机令牌订阅链接
8. 启动服务并验证订阅链接是否可在本机访问

## 当前支持的协议

当前版本支持以下协议：

* `VMess TCP`
* `VLESS Reality`
* `Shadowsocks aes-256-gcm`
* `Shadowsocks 2022-blake3-aes-256-gcm`

说明：

* `VMess` 兼容面较广，适合保底
* `VLESS Reality` 更现代，适合新客户端
* `Shadowsocks aes-256-gcm` 适合老客户端
* `Shadowsocks 2022` 适合较新的 `Mihomo / Clash Meta`

## 生成的订阅结构

脚本始终生成两个订阅链接：

### 1. `classic` 兼容版

用于兼容更多客户端，默认包含：

* `COMPAT-VMESS-TCP`
* `COMPAT-SS-AES256GCM`

适用场景：

* 老版本 Clash
* 不支持 `SS2022`
* 不支持 `VLESS Reality`
* 不确定客户端兼容性时优先使用

### 2. `meta` 最新版

用于较新的客户端，默认包含：

* `LATEST-VMESS-TCP`
* `LATEST-VLESS-REALITY-VISION`
* `LATEST-SS2022-BLAKE3-AES256`

适用场景：

* `Mihomo`
* `Clash Meta`
* `OpenClash` 使用 `mihomo` 内核

## 客户端兼容性建议

如果客户端导入时报错：

    cipher not supported

通常说明该客户端不支持 `SS2022`，这时请使用 `classic` 订阅。

建议选择如下：

* 旧版 Clash：优先 `classic`
* Mihomo / Clash Meta：优先 `meta`
* 不确定：先试 `classic`

## 项目结构

    .
    ├── README.md
    └── scripts
        ├── install_vpn_stack.sh
        └── uninstall_stack.sh

## 系统要求

* Ubuntu 20.04 / 22.04 / 24.04
* Debian 11 / 12
* `root` 权限
* 可访问公网的 VPS

## 快速开始

把脚本上传到 VPS 后执行：

    chmod +x install_vpn_stack.sh
    ./install_vpn_stack.sh

执行完成后，脚本会输出：

* 服务器 IP
* VMess 节点信息
* VLESS Reality 节点信息
* Shadowsocks 兼容版信息
* Shadowsocks 2022 信息
* `classic` 订阅链接
* `meta` 订阅链接

## 预设配置

脚本内置了多个完整预设：

    PRESET_CONFIGS=(
      "default"     # VMess 10086, VLESS Reality 10443, SS 兼容版 8388, SS2022 8389, 订阅 8090
      "compact"     # VMess 18086, VLESS Reality 18443, SS 兼容版 18388, SS2022 18389, 订阅 18090
      "alt"         # VMess 26086, VLESS Reality 26443, SS 兼容版 26388, SS2022 26389, 订阅 26090
    )

默认运行：

    ./install_vpn_stack.sh

指定预设运行：

    INSTALL_PRESET=alt ./install_vpn_stack.sh

## 自定义端口

如果默认端口被占用，可以直接覆盖：

    XRAY_PORT=28186 \
    VLESS_REALITY_PORT=28443 \
    SS_LEGACY_PORT=28388 \
    SS_PORT=28389 \
    SUB_PORT=28090 \
    ./install_vpn_stack.sh

可覆盖的端口包括：

* `XRAY_PORT`
* `VLESS_REALITY_PORT`
* `SS_LEGACY_PORT`
* `SS_PORT`
* `SUB_PORT`

## 协议开关

你可以按需启用或关闭某些协议：

    ENABLE_VMESS=1
    ENABLE_VLESS_REALITY=1
    ENABLE_SS_LEGACY=1
    ENABLE_SS2022=1

例如，只部署 `VMess + SS 兼容版`：

    ENABLE_VLESS_REALITY=0 \
    ENABLE_SS2022=0 \
    ./install_vpn_stack.sh

例如，重点部署新版协议：

    ENABLE_VMESS=1 \
    ENABLE_VLESS_REALITY=1 \
    ENABLE_SS_LEGACY=0 \
    ENABLE_SS2022=1 \
    ./install_vpn_stack.sh

## 隔离部署

默认栈名为：

    STACK_NAME=vpn-stack

如果你要在同一台机器上测试多套配置，建议使用独立栈名：

    STACK_NAME=teststack \
    XRAY_PORT=28186 \
    VLESS_REALITY_PORT=28443 \
    SS_LEGACY_PORT=28388 \
    SS_PORT=28389 \
    SUB_PORT=28090 \
    ./install_vpn_stack.sh

这样会自动隔离：

* 配置目录
* 订阅目录
* 订阅服务脚本
* `systemd` 服务名

非常适合：

* 在已有节点机器上做测试
* 多人共用同一台测试机
* 不想覆盖现有运行环境

## Reality 参数

如果启用了 `VLESS Reality`，脚本会自动生成：

* `UUID`
* `private key`
* `public key`
* `short id`

默认参数：

    REALITY_SERVER_NAME=www.cloudflare.com
    REALITY_DEST=www.cloudflare.com:443

如需替换成别的目标，可以这样运行：

    REALITY_SERVER_NAME=www.microsoft.com \
    REALITY_DEST=www.microsoft.com:443 \
    ./install_vpn_stack.sh

## 输出示例

脚本执行完成后，会输出类似下面的内容：

    Deployment complete.
    
    Preset:
      default
    
    Stack:
      teststack
    
    Server:
      203.0.113.10
    
    Enabled protocols:
      VMess: 1
      VLESS Reality: 1
      Shadowsocks legacy: 1
      Shadowsocks 2022: 1
    
    VMess:
      server: 203.0.113.10
      port: 28186
      uuid: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    
    VLESS Reality:
      server: 203.0.113.10
      port: 28443
      uuid: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      public-key: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
      short-id: xxxxxxxx
      server-name: www.cloudflare.com
    
    Shadowsocks legacy:
      server: 203.0.113.10
      port: 28388
      cipher: aes-256-gcm
      password: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    
    Shadowsocks 2022:
      server: 203.0.113.10
      port: 28389
      cipher: 2022-blake3-aes-256-gcm
      password: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    
    Subscriptions:
      classic: http://203.0.113.10:28090/<token>.yaml
      meta:    http://203.0.113.10:28090/<token>.yaml

## 订阅内节点命名

为了让用户一眼能看懂订阅里的节点用途，脚本会生成清晰命名。

### `classic` 中的节点

* `COMPAT-VMESS-TCP`
* `COMPAT-SS-AES256GCM`

### `meta` 中的节点

* `LATEST-VMESS-TCP`
* `LATEST-VLESS-REALITY-VISION`
* `LATEST-SS2022-BLAKE3-AES256`

## 文件服务器说明

为了让部署足够轻量，这个项目默认不依赖 Nginx，而是直接使用一个小型 Python HTTP 文件服务器分发订阅。

优点：

* 部署简单
* 易读易改
* 一键完成
* 不额外引入 Web 服务器配置复杂度

订阅文件默认存放目录：

    /opt/<stack-name>/subscription/public

订阅链接使用随机令牌路径，例如：

    http://203.0.113.10:28090/AbCdEf1234567890XYZ.yaml

注意：

* 这只是“难猜路径”，不是强鉴权
* 默认仍然是 `HTTP`
* 如有域名，建议后续加反向代理和 `HTTPS`

## 安装后的服务名

每个栈会创建以下 `systemd` 服务：

    xray-<stack-name>
    shadowsocks-legacy-<stack-name>
    shadowsocks-rust-<stack-name>
    clash-subscription-<stack-name>

## 重要路径

    /usr/local/bin/xray
    /usr/local/bin/ssserver
    /usr/local/bin/ssservice
    /usr/local/bin/<stack-name>-subscription-server.py
    
    /usr/local/etc/<stack-name>-xray/config.json
    /etc/<stack-name>-shadowsocks-legacy/config.json
    /etc/<stack-name>-shadowsocks-rust/config.json
    
    /opt/<stack-name>/subscription/public
    
    /etc/systemd/system/xray-<stack-name>.service
    /etc/systemd/system/shadowsocks-legacy-<stack-name>.service
    /etc/systemd/system/shadowsocks-rust-<stack-name>.service
    /etc/systemd/system/clash-subscription-<stack-name>.service

## 常用命令

查看服务状态：

    systemctl status xray-<stack-name>
    systemctl status shadowsocks-legacy-<stack-name>
    systemctl status shadowsocks-rust-<stack-name>
    systemctl status clash-subscription-<stack-name>

查看监听端口：

    ss -tulpn

查看订阅目录：

    ls -la /opt/<stack-name>/subscription/public

本机测试订阅：

    curl http://127.0.0.1:<sub-port>/<token>.yaml

## 卸载脚本

项目已提供卸载脚本：

[scripts/uninstall_stack.sh](/C:/Users/admin/Documents/Codex/2026-05-13/107-172-75-141-rraonyavm12989tkr4-vps/scripts/uninstall_stack.sh)

基础用法：

    chmod +x uninstall_stack.sh
    STACK_NAME=teststack ./uninstall_stack.sh

这个脚本会：

1. 停止对应栈的服务
2. 禁用对应 `systemd` 服务
3. 删除配置目录
4. 删除订阅目录
5. 删除该栈的订阅服务脚本
6. 重新加载 `systemd`

如果你确定还要把共享二进制一起删掉，可以这样：

    STACK_NAME=teststack REMOVE_BINARIES=1 ./uninstall_stack.sh

注意：

* `REMOVE_BINARIES=1` 会删除 `/usr/local/bin/xray`、`ssserver`、`ssservice`
* 如果机器上还有别的栈在共用这些程序，不要开启这个选项

## 安全建议

这个项目重点是“一键可用”，不是“最高安全基线”。如果你要长期公开使用，建议至少补上这些措施：

1. SSH 改为密钥登录
2. 关闭 root 密码直登
3. 使用防火墙限制不需要的端口
4. 有域名时给订阅服务加 `HTTPS`
5. 不要公开完整订阅链接
6. 定期轮换 UUID、密码、Reality 密钥
7. 不要在不同场景长期复用同一组端口和同一栈名

## 当前版本不解决的问题

当前项目不试图解决以下问题：

* 域名和 HTTPS 自动申请
* Web 面板
* 多用户账号管理
* 用量统计
* 节点限速
* 自动更新订阅内容模板
* 更复杂的混淆与流量伪装策略

这些内容可以后续逐步扩展，但不建议一开始就把脚本做得过重。

## 后续建议扩展

如果你后面还想继续增强，这几个方向是最实用的：

1. 增加 `HTTPS + 域名` 订阅发布方案
2. 增加二维码导出
3. 增加 `VLESS + WS + TLS`
4. 增加 `Trojan`
5. 增加自动更新功能
6. 增加更细粒度的协议组合模板
