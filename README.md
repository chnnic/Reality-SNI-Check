# Reality-SNI-Check

> 在**落地服务器**上为 VLESS-Reality 挑选 `dest`/SNI 的一键检测工具。
> 一次跑完，自动测出**握手最快**且满足 Reality 硬性要求（TLS1.3 + h2 + X25519 + 短证书链）的候选站点。

选 SNI 不是拍脑袋填一个大站就完事——同一个站在不同落地机上的握手延迟差异很大，而且有些站根本不满足 Reality 的握手条件（比如不支持 TLS1.3、证书链太长）。这个脚本把这些判断自动化：**批量探测 → 合规筛选 → 按延迟排名 → 直接告诉你这台机该用哪个。**

---

## 特性

- **交互菜单**：直接运行即进入菜单，数字选择测试项（快速测试 / 全部 / 选分类 / 自定义 / 设置），无需记参数。
- **握手延迟实测**：基于 `curl` 的 `time_appconnect`，多次取最小值排除抖动，量的正是 Reality 回源真正付出的那段延迟。
- **Reality 合规检测**：一次 `openssl` 调用同时拿到 **TLS1.3 / ALPN(h2) / 临时密钥(X25519) / 证书链层数**，不合规的站直接标记。
- **证书链长度检查**：链太长（4+ 层）会导致 Reality 借用握手时出问题，脚本自动标出（这正是 `www.microsoft.com` 常被筛掉的原因）。
- **10 大分类、123 个内置站点**：覆盖 CDN、云、科技、金融、大学、流媒体、社交、游戏、电商、区域锚点，可按需选测。
- **自动排名 + 推荐**：只对通过 TLS1.3 的站按握手升序排名，末尾直接给出建议的 `dest`/SNI。
- **交互检测**：一行可输入多个网址（逗号或空格分隔），自动去掉 `http(s)://` 和路径。
- **零依赖污染**：不建代理、不改系统、不上报数据，纯标准 HTTPS 探测。

---

## 依赖

```
bash  curl  openssl  timeout
```

常见发行版（Debian / Ubuntu / CentOS / Alpine）默认都有。Alpine 需确保安装了 `bash`、`curl`、`openssl`、`coreutils`。

---

## 安装 / 运行

### 一键下载并运行

**推荐（下载到本地后运行，菜单与交互输入均正常）：**

```bash
curl -fsSL https://raw.githubusercontent.com/chnnic/Reality-SNI-Check/main/Reality-SNI-Check.sh -o Reality-SNI-Check.sh && chmod +x Reality-SNI-Check.sh && ./Reality-SNI-Check.sh
```

文件会留在当前目录，之后直接 `./Reality-SNI-Check.sh` 即可再次运行。

**管道一键运行（进程替换，保留终端输入，菜单可用）：**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/chnnic/Reality-SNI-Check/main/Reality-SNI-Check.sh)
```

> ⚠️ 不要用 `curl ... | bash`——管道会占用 stdin，导致菜单和交互输入读不到键盘、直接退出。请用上面 `bash <(...)` 的写法。

### 仅下载（不自动运行）

```bash
curl -fsSL https://raw.githubusercontent.com/chnnic/Reality-SNI-Check/main/Reality-SNI-Check.sh -o Reality-SNI-Check.sh
chmod +x Reality-SNI-Check.sh
```

### 安装为全局命令（任意目录直接调用）

装到 `PATH`，之后在任何目录敲 `reality-sni-check` 即可运行：

```bash
curl -fsSL https://raw.githubusercontent.com/chnnic/Reality-SNI-Check/main/Reality-SNI-Check.sh -o /usr/local/bin/reality-sni-check && chmod +x /usr/local/bin/reality-sni-check && reality-sni-check
```

以后升级：重跑上面这条即可覆盖为最新版。

### 无 curl 时用 wget

```bash
wget -qO Reality-SNI-Check.sh https://raw.githubusercontent.com/chnnic/Reality-SNI-Check/main/Reality-SNI-Check.sh && chmod +x Reality-SNI-Check.sh && ./Reality-SNI-Check.sh
```

> ⚠️ 必须在**落地服务器**上运行，不是本地。测的是「从落地机方向」到目标站的握手延迟——这才是 Reality 回源实际付出的成本。

---

## 用法

### 菜单模式（推荐，直接运行）

不带任何参数运行，进入交互菜单，用数字选择要做什么，无需记参数：

```bash
./Reality-SNI-Check.sh
```

```
════════ Reality SNI 检测 · 主菜单 ════════
  1) 快速测试   (cdn + cloud + tech，最常用)
  2) 全部分类   (123 站，较慢)
  3) 选择分类测试
  4) 自定义网址检测   (一行可多站)
  5) 设置   (次数=3 超时=5s)
  0) 退出
请选择 >
```

- **1 快速测试**：只测最常用的 3 个分类，省时。
- **2 全部分类**：测全部 123 站。
- **3 选择分类测试**：进入二级菜单，分类带编号，输入数字多选（空格或逗号分隔，`a` 全选，回车返回）。
- **4 自定义网址检测**：手动输入网址，一行可输入多个（逗号或空格分隔）。
- **5 设置**：调整每站探测次数与单次超时。
- **0 退出**。

每完成一次测试自动回到主菜单，可连续测多项，无需重启脚本。

### 命令行模式（熟手 / 脚本调用）

带参数运行会跳过菜单直接执行，适合自动化：

```bash
./Reality-SNI-Check.sh -l               # 列出所有分类及站点数
./Reality-SNI-Check.sh -c edu           # 只测“大学”分类
./Reality-SNI-Check.sh -c edu,tech      # 测多个分类（逗号或空格分隔）
./Reality-SNI-Check.sh -a "a.com b.com" # 在内置基础上追加站点一起测
./Reality-SNI-Check.sh -i               # 只进交互输入模式（一行可多站）
./Reality-SNI-Check.sh -n 5 -t 6        # 每站探测 5 次、单次超时 6 秒

# 用自己的清单完全替换内置列表
SNI_HOSTS="www.apple.com www.amd.com www.nus.edu.sg" ./Reality-SNI-Check.sh
```

### 参数

| 参数 | 说明 |
|------|------|
| *(无参数)* | 进入交互菜单 |
| `-l` | 列出所有分类及各自站点数 |
| `-c <分类>` | 只测指定分类，多个用逗号或空格分隔（跳过菜单） |
| `-a "<站点...>"` | 在内置列表基础上追加站点一起测 |
| `-i` | 只进交互输入模式 |
| `-n <次数>` | 每站探测次数（默认 3，取最小值） |
| `-t <秒>` | 单次连接超时（默认 5） |
| `-h` | 显示帮助 |
| `SNI_HOSTS=` | 环境变量，优先级最高，直接替换全部内置分类 |

---

## 分类

| 键 | 分类 | 站点数 |
|------|------|:---:|
| `cdn` | 全球 CDN / anycast | 14 |
| `cloud` | 云 / 开发基础设施 | 13 |
| `tech` | 科技 / 半导体大厂 | 14 |
| `fin` | 金融 / 支付 / 银行 | 10 |
| `edu` | 大学 / 教育机构 | 23 |
| `media` | 流媒体 / 内容 | 8 |
| `social` | 社交平台 | 8 |
| `gaming` | 游戏平台 | 10 |
| `ecom` | 电商 / 零售 / 品牌 | 11 |
| `region` | 区域锚点（日 / 欧 / 东南亚 / 港 / 澳） | 12 |

跑全部 123 站会花点时间；日常按落地机大区选 2~3 个分类即可，例如新加坡落地机跑 `-c cdn,cloud,edu`。

---

## 输出说明

```
▎云/开发基础设施  [cloud]

SNI 站点                   握手(s)  TLS1.3 h2   临时密钥   链  HTTP  合规
--------------------------------------------------------------------------
cloud.google.com            0.040   yes    yes  X25519     3   403   ✓ 推荐
azure.microsoft.com         0.270   yes    yes  X25519     3   403   ✓ 推荐
...

══ 本机最优 SNI 排名 (仅列 TLS1.3 通过者，按握手升序) ══
  1) cloud.google.com         0.040s  [全合规]
  ...

→ 建议 dest/SNI: cloud.google.com
```

### 列含义

| 列 | 含义 |
|------|------|
| **握手(s)** | TCP+TLS 握手耗时（`time_appconnect`），越低越好 |
| **TLS1.3** | 是否协商到 TLS 1.3（Reality **必需**） |
| **h2** | ALPN 是否协商到 HTTP/2（强烈建议） |
| **临时密钥** | ECDHE 密钥交换算法，应包含 **X25519** |
| **链** | 证书链层数（叶子 + 中间）；越短越好 |
| **HTTP** | 根路径返回码（仅参考，403/301 不影响 Reality） |

### 合规标记

| 标记 | 含义 |
|------|------|
| `✓ 推荐` | TLS1.3 + h2 + X25519 + 短链（≤3）全部满足，最佳 dest |
| `△ 链偏长` | 其余合规但证书链 4+ 层，能试但不首选 |
| `△ 可用` | 通过 TLS1.3，但缺 h2 或 X25519 |
| `✗ 不可` | 无 TLS1.3，Reality 无法使用 |

---

## 为什么这些检测项对 Reality 重要

- **TLS1.3（必需）**：Reality 借用目标站的 TLS1.3 握手，目标站不支持则协议无法工作。
- **X25519（必需）**：Reality 的密钥交换基于 X25519，目标站必须能协商该曲线。
- **h2（建议）**：ALPN 协商到 h2 让借用的握手更贴近主流浏览器行为。
- **证书链长度**：链过长会让 Reality 借用握手时出问题，短链（1~3 层）最稳。
- **握手延迟**：dest 回源模式下，每次建连都要实连一次目标站，该站从落地机方向的 RTT 直接叠加进握手延迟。

---

## 选 SNI 的建议

- **优先大站是对的**：大厂 anycast/CDN 站流量基数大、封禁附带损害高，反而更安全；冷门小站的稳定长连接才是异常特征。
- **别扎堆最热门那几个**：人人都用同一个 SNI 会招致针对性行为分析，选合规但相对冷门的大站更稳。
- **就近匹配落地机大区**：新加坡落地配 `www.nus.edu.sg`、日本配 `www.u-tokyo.ac.jp`、香港配 `www.hku.hk`，既降握手延迟又更自然。
- **SNI 要和 dest 一致**：报的 SNI 必须指向你真实可达的那个站，否则主动探测一握手就露破绽。
- **大学站是被低估的优质选项**：`.edu` 极少被封，但要选**托管在大厂 CDN 上的名校主站**——小院校自建站常 TLS 老旧、证书链杂，脚本会直接标出。

---

## 常见问题

**Q：跑完所有站都显示 `✗ 不可` 或超时？**
A：检查落地机出网是否正常（`curl -I https://www.cloudflare.com`）。部分机房对 UDP/某些目的地有限制。

**Q：`www.microsoft.com` 为什么被标记为不合规？**
A：它在部分区域返回的证书链偏长（含多级/交叉签名），Reality 借用握手易出问题。脚本特意保留它，方便直观看到「链偏长」的效果。

**Q：结果每次不完全一样？**
A：握手延迟受实时网络波动影响。建议对候选站隔几小时多测两轮，选**又快又稳**的——抖动大的站会变成偶发的连不上。

---

## 免责声明

本脚本仅是一个网络连通性与 TLS 握手参数的检测工具，功能等同于 `curl` / `openssl` 的批量封装，用于测量本机到公开网站的握手延迟、TLS 版本、ALPN 与证书链等**公开可见信息**，供技术研究、服务器选型、网络诊断与合法合规用途参考。

- 脚本本身不建立任何代理、不修改系统、不发送数据到第三方，所有请求均为对目标站点 443 端口的标准 HTTPS 探测。
- 检测结果仅反映测量当时的网络状况，不构成任何保证或建议。
- 使用者须自行确保其使用方式符合**所在地及目标服务器所在地**的法律法规及相关服务条款。因使用本脚本产生的任何后果，由使用者自行承担，作者与分发者不承担任何责任。
- 请勿将本工具用于任何未经授权、违法或侵犯他人权益的用途。

**继续使用即表示您已阅读、理解并同意上述条款。**

---

## License

MIT
