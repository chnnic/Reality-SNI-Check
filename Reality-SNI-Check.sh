#!/usr/bin/env bash
# ==============================================================================
#  reality-sni-check.sh  —  Reality dest/SNI 候选测速与合规检测
#
#  在【落地服务器】上跑：为该机测出握手最快、且满足 Reality 要求
#  (TLS1.3 + h2 + X25519) 的 SNI 候选，供 VLESS-Reality dest 选用。
#
#  用法:
#    ./reality-sni-check.sh                 # 测全部内置分类
#    ./reality-sni-check.sh -l              # 列出所有分类
#    ./reality-sni-check.sh -c edu          # 只测"大学"分类
#    ./reality-sni-check.sh -c edu,tech     # 测多个分类(逗号/空格分隔)
#    ./reality-sni-check.sh -a "a.com b.com"# 追加自定义站点一起测
#    ./reality-sni-check.sh -i              # 只进交互输入模式(一行可多站)
#    ./reality-sni-check.sh -n 5 -t 6       # 每站探测5次、单次超时6s
#    SNI_HOSTS="a.com b.com" ./reality-sni-check.sh   # 用自己的清单替换全部
#
#  分类键: cdn(全球CDN) cloud(云/开发) tech(科技大厂) fin(金融) edu(大学)
#          media(流媒体) social(社交) gaming(游戏) ecom(电商) region(区域锚点)
#  依赖: bash curl openssl timeout  (常见发行版默认都有)
# ------------------------------------------------------------------------------
#  免责声明 (DISCLAIMER):
#    本脚本仅是一个网络连通性与 TLS 握手参数的检测工具，功能等同于
#    curl / openssl 的批量封装，用于测量本机到公开网站的握手延迟、
#    TLS 版本、ALPN 与证书链等公开可见信息，供技术研究、服务器选型、
#    网络诊断与合法合规用途参考。
#
#    - 脚本本身不建立任何代理、不修改系统、不发送数据到第三方，
#      所有请求均为对目标站点 443 端口的标准 HTTPS 探测。
#    - 检测结果仅反映测量当时的网络状况，不构成任何保证或建议。
#    - 使用者须自行确保其使用方式符合所在地及目标服务器所在地的
#      法律法规及相关服务条款。因使用本脚本产生的任何后果，
#      由使用者自行承担，作者与分发者不承担任何责任。
#    - 请勿将本工具用于任何未经授权、违法或侵犯他人权益的用途。
#
#    继续使用即表示您已阅读、理解并同意上述条款。
# ==============================================================================
set -u

# ================== 内置候选站点：按分类组织 ==================
# 脚本会自动测每站在【本机】的握手延迟+合规+证书链，不合适的自动标记，不用手删。
# 分类键: cdn cloud tech fin edu media social gaming ecom region  (用 -c 选，见 -h)

GRP_cdn=(                      # 全球 CDN / anycast，任何区就近命中，最干净
  www.cloudflare.com
  www.apple.com
  www.icloud.com
  gateway.icloud.com
  swscan.apple.com            # Apple 软更源，链短握手干净，经典 dest
  www.amazon.com
  www.microsoft.com           # 常因证书链长不合规，留着看它被筛掉
  www.bing.com
  dl.google.com
  www.google.com
  addons.mozilla.org          # 社区长期验证的干净 dest
  www.python.org
  www.wikipedia.org
  www.fastly.com
)
GRP_cloud=(                   # 云/开发基础设施，TLS 一般极规范
  aws.amazon.com
  azure.microsoft.com
  cloud.google.com
  www.digitalocean.com
  github.com
  gitlab.com
  www.docker.com
  registry.npmjs.org
  www.jsdelivr.com
  www.vercel.com
  www.netlify.com
  www.oracle.com
  www.ibm.com
)
GRP_tech=(                    # 科技/半导体/硬件大厂
  www.amd.com
  www.intel.com
  www.nvidia.com
  www.qualcomm.com
  www.arm.com
  www.tesla.com
  www.samsung.com
  www.sony.com
  www.lg.com
  www.dell.com
  www.hp.com
  www.lenovo.com
  www.cisco.com
  www.adobe.com
)
GRP_fin=(                     # 金融/支付/银行，证书规矩全球可达
  www.paypal.com
  www.visa.com
  www.mastercard.com
  www.americanexpress.com
  www.stripe.com
  www.jpmorgan.com
  www.goldmansachs.com
  www.hsbc.com
  www.citi.com
  www.blackrock.com
)
GRP_edu=(                     # 大学/教育机构，冷门不被封，选 CDN 托管的名校主站
  www.mit.edu
  www.stanford.edu
  www.harvard.edu
  www.berkeley.edu
  www.cornell.edu
  www.princeton.edu
  www.yale.edu
  www.columbia.edu
  www.ox.ac.uk
  www.cam.ac.uk
  www.imperial.ac.uk
  www.ethz.ch
  www.epfl.ch
  www.u-tokyo.ac.jp
  www.kyoto-u.ac.jp
  www.nus.edu.sg
  www.ntu.edu.sg
  www.hku.hk
  www.hkust.edu.hk
  www.tsinghua.edu.cn
  www.pku.edu.cn
  www.unimelb.edu.au
  www.utoronto.ca
)
GRP_media=(                   # 流媒体/内容平台
  www.spotify.com
  www.soundcloud.com
  vimeo.com
  www.twitch.tv
  www.pinterest.com
  www.imdb.com
  www.dailymotion.com
  www.flickr.com
)
GRP_social=(                  # 社交平台 (dest 从落地机方向可达即可)
  www.linkedin.com
  www.reddit.com
  www.quora.com
  www.medium.com
  www.wordpress.com
  www.tumblr.com
  discord.com
  www.snapchat.com
)
GRP_gaming=(                  # 游戏平台/发行商
  store.steampowered.com
  www.epicgames.com
  www.riotgames.com
  www.ea.com
  www.ubisoft.com
  www.playstation.com
  www.nintendo.com
  www.xbox.com
  www.roblox.com
  www.blizzard.com
)
GRP_ecom=(                    # 电商/零售/品牌
  www.ebay.com
  www.walmart.com
  www.target.com
  www.bestbuy.com
  www.etsy.com
  www.shopify.com
  www.alibaba.com
  www.ikea.com
  www.nike.com
  www.adidas.com
  www.zara.com
)
GRP_region=(                  # 区域锚点 (按落地机大区就近选，最自然)
  www.lovelive-anime.jp       # 日本
  www.yahoo.co.jp
  www.rakuten.co.jp
  www.ana.co.jp
  www.mercedes-benz.com       # 欧洲
  www.bmw.com
  www.audi.com
  www.lufthansa.com
  www.singaporeair.com        # 东南亚
  www.cathaypacific.com       # 香港
  www.qantas.com              # 澳洲
  www.salesforce.com          # 北美
)

# 分类顺序与中文标签 (键:标签)
CAT_KEYS=(cdn cloud tech fin edu media social gaming ecom region)
cat_label() {
  case "$1" in
    cdn)    echo "全球 CDN/anycast" ;;
    cloud)  echo "云/开发基础设施" ;;
    tech)   echo "科技/半导体大厂" ;;
    fin)    echo "金融/支付/银行" ;;
    edu)    echo "大学/教育机构" ;;
    media)  echo "流媒体/内容" ;;
    social) echo "社交平台" ;;
    gaming) echo "游戏平台" ;;
    ecom)   echo "电商/零售/品牌" ;;
    region) echo "区域锚点(日/欧/东南亚/港/澳)" ;;
    *)      echo "$1" ;;
  esac
}
# 取某分类的站点 (可移植写法，不依赖 nameref)
cat_hosts() {
  case "$1" in
    cdn)    printf '%s\n' "${GRP_cdn[@]}" ;;
    cloud)  printf '%s\n' "${GRP_cloud[@]}" ;;
    tech)   printf '%s\n' "${GRP_tech[@]}" ;;
    fin)    printf '%s\n' "${GRP_fin[@]}" ;;
    edu)    printf '%s\n' "${GRP_edu[@]}" ;;
    media)  printf '%s\n' "${GRP_media[@]}" ;;
    social) printf '%s\n' "${GRP_social[@]}" ;;
    gaming) printf '%s\n' "${GRP_gaming[@]}" ;;
    ecom)   printf '%s\n' "${GRP_ecom[@]}" ;;
    region) printf '%s\n' "${GRP_region[@]}" ;;
    *) : ;;
  esac
}

ROUNDS=3          # 每站探测次数，取最小值避免抖动
TIMEOUT=5         # 单次连接超时(秒)
EXTRA_HOSTS=()
INTERACTIVE_ONLY=0
SEL_CATS=()       # -c 指定的分类；空=全部

# ---------------- 颜色 ----------------
if [[ -t 1 ]]; then
  C_B=$'\e[1m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_D=$'\e[2m'; C_C=$'\e[36m'; NC=$'\e[0m'
else
  C_B=""; C_G=""; C_Y=""; C_R=""; C_D=""; C_C=""; NC=""
fi

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -22; exit 0; }

list_cats() {
  printf "${C_B}可用分类 (用 -c 选，逗号分隔):${NC}\n"
  for k in "${CAT_KEYS[@]}"; do
    printf "  ${C_C}%-8s${NC} %s  ${C_D}(%d 站)${NC}\n" "$k" "$(cat_label "$k")" "$(cat_hosts "$k" | grep -c .)"
  done
  exit 0
}

while getopts "a:c:n:t:ilh" opt; do
  case "$opt" in
    a) read -r -a EXTRA_HOSTS <<< "$OPTARG" ;;
    c) IFS=', ' read -r -a SEL_CATS <<< "$OPTARG" ;;
    n) ROUNDS="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    i) INTERACTIVE_ONLY=1 ;;
    l) list_cats ;;
    h) usage ;;
    *) usage ;;
  esac
done

# 环境变量覆盖：SNI_HOSTS 优先级最高，直接替换全部内置分类
SNI_OVERRIDE=()
[[ -n "${SNI_HOSTS:-}" ]] && read -r -a SNI_OVERRIDE <<< "$SNI_HOSTS"

# 把 URL / 带路径的输入规整成纯主机名
normalize_host() {
  local h="$1"
  h="${h#http://}"; h="${h#https://}"   # 去 scheme
  h="${h%%/*}"                          # 去路径
  h="${h%%:*}"                          # 去端口
  h="${h// /}"                          # 去空格
  printf '%s' "$h"
}

# 探测单个站点，输出: "minAppconnect tls13 h2 tempkey chain httpcode"
probe_host() {
  local host="$1" best="" code="-" line ac
  # 延迟: curl 取 ROUNDS 次 time_appconnect 最小值
  for _ in $(seq 1 "$ROUNDS"); do
    line=$(curl -sS -o /dev/null --max-time "$TIMEOUT" \
        -w "%{time_appconnect} %{http_code}" "https://${host}/" 2>/dev/null) || continue
    ac="${line%% *}"; code="${line##* }"
    [[ -z "$ac" || "$ac" == "0.000000" ]] && continue
    if [[ -z "$best" ]] || awk "BEGIN{exit !($ac < $best)}"; then best="$ac"; fi
  done
  [[ -z "$best" ]] && { printf 'FAIL - - - - %s' "$code"; return; }

  # 一次 openssl -showcerts 同时拿: TLS1.3 / ALPN(h2) / 临时密钥(X25519) / 证书链层数
  local so tls13="no" h2="no" tempkey="-" chain=0
  so=$(echo -n | timeout "$TIMEOUT" openssl s_client -connect "${host}:443" \
        -servername "$host" -alpn h2,http/1.1 -showcerts 2>/dev/null)
  grep -qE "New, TLSv1\.3|Protocol *: *TLSv1\.3" <<< "$so" && tls13="yes"
  grep -qi "ALPN protocol: h2" <<< "$so" && h2="yes"
  tempkey=$(grep "Server Temp Key" <<< "$so" | sed 's/.*Server Temp Key: *//; s/,.*//' | head -1)
  [[ -z "$tempkey" ]] && tempkey="-"
  chain=$(grep -c "BEGIN CERTIFICATE" <<< "$so")   # 证书链层数(叶子+中间)
  [[ -z "$chain" ]] && chain=0

  printf '%s %s %s %s %s %s' "$best" "$tls13" "$h2" "$tempkey" "$chain" "$code"
}

# 表头
print_header() {
  printf "\n${C_B}%-24s %10s  %-6s %-4s %-14s %-4s %-5s %s${NC}\n" \
    "SNI 站点" "握手(s)" "TLS1.3" "h2" "临时密钥" "链" "HTTP" "合规"
  printf "${C_D}%s${NC}\n" "--------------------------------------------------------------------------------------------"
}

# 单行渲染 + 收集用于排序 (host|ac|qualify)
RESULTS=()
render_row() {
  local host="$1" out ac tls13 h2 tempkey chain code qualify mark ac_disp x25519="no"
  out=$(probe_host "$host")
  read -r ac tls13 h2 tempkey chain code <<< "$out"

  if [[ "$ac" == "FAIL" ]]; then
    printf "${C_R}%-24s %10s  %-6s %-4s %-14s %-4s %-5s %s${NC}\n" \
      "$host" "超时/失败" "-" "-" "-" "-" "$code" "✗"
    RESULTS+=("$host|999|no")
    return
  fi

  [[ "$tempkey" == *X25519* ]] && x25519="yes"
  # 证书链: 1~2 短链最优, 3 尚可, 4+ 偏长(Reality 借用握手易出问题)
  local chain_ok="no"
  [[ "$chain" =~ ^[0-9]+$ && "$chain" -ge 1 && "$chain" -le 3 ]] && chain_ok="yes"

  # Reality 合规: TLS1.3 必须; h2 / X25519 / 短证书链 三者齐 = 推荐
  local full="no"
  if [[ "$tls13" == "yes" && "$h2" == "yes" && "$x25519" == "yes" && "$chain_ok" == "yes" ]]; then
    qualify="${C_G}✓ 推荐${NC}"; mark="ok"; full="yes"
  elif [[ "$tls13" == "yes" && "$chain" -gt 3 ]]; then
    qualify="${C_Y}△ 链偏长${NC}"; mark="ok"      # 其它没问题但链太长，能试不首选
  elif [[ "$tls13" == "yes" ]]; then
    qualify="${C_Y}△ 可用${NC}"; mark="ok"        # 缺 h2 或 x25519
  else
    qualify="${C_R}✗ 不可${NC}"; mark="bad"        # 无 TLS1.3
  fi

  ac_disp=$(awk "BEGIN{printf \"%.3f\", $ac}")
  local ct ch cc
  [[ "$tls13" == "yes" ]] && ct="${C_G}yes${NC}" || ct="${C_R}no${NC}"
  [[ "$h2"   == "yes" ]] && ch="${C_G}yes${NC}" || ch="${C_Y}no${NC}"
  if   [[ "$chain" -le 2 && "$chain" -ge 1 ]]; then cc="${C_G}${chain}${NC}"
  elif [[ "$chain" -eq 3 ]]; then cc="${C_Y}${chain}${NC}"
  else cc="${C_R}${chain}${NC}"; fi

  printf "%-24s ${C_C}%10s${NC}  %-15b %-13b %-14s %-13b %-5s %b\n" \
    "$host" "$ac_disp" "$ct" "$ch" "${tempkey:0:14}" "$cc" "$code" "$qualify"

  if [[ "$mark" == "bad" ]]; then
    RESULTS+=("$host|999|no")
  else
    RESULTS+=("$host|$ac|$([[ "$full" == "yes" ]] && echo yes || echo partial)")
  fi
}

run_batch() {
  local hosts=("$@")
  print_header
  for h in "${hosts[@]}"; do
    h=$(normalize_host "$h"); [[ -z "$h" ]] && continue
    render_row "$h"
  done
}

# 按分类分组跑：每类一个小标题，最后统一排名
run_categories() {
  local cats=("$@") k host first=1
  for k in "${cats[@]}"; do
    local list; list=$(cat_hosts "$k")
    [[ -z "$list" ]] && { printf "${C_R}未知分类: %s${NC}\n" "$k"; continue; }
    printf "\n${C_B}▎%s  ${C_D}[%s]${NC}\n" "$(cat_label "$k")" "$k"
    print_header
    while IFS= read -r host; do
      host=$(normalize_host "$host"); [[ -z "$host" ]] && continue
      render_row "$host"
    done <<< "$list"
  done
}

# 排序输出最佳推荐
print_best() {
  echo
  printf "${C_B}══ 本机最优 SNI 排名 (仅列 TLS1.3 通过者，按握手升序) ══${NC}\n"
  local sorted top1=""
  sorted=$(printf '%s\n' "${RESULTS[@]}" \
    | awk -F'|' '$2!=999' | sort -t'|' -k2 -n)
  if [[ -z "$sorted" ]]; then
    printf "${C_R}没有站点通过 TLS1.3，检查落地机出网/换候选列表${NC}\n"; return
  fi
  local rank=1
  while IFS='|' read -r host ac tag; do
    local badge=""
    [[ "$tag" == "yes" ]] && badge="${C_G}[全合规]${NC}" || badge="${C_Y}[缺h2/x25519]${NC}"
    printf "  %d) ${C_B}%-24s${NC} %ss  %b\n" "$rank" "$host" "$(awk "BEGIN{printf \"%.3f\",$ac}")" "$badge"
    [[ $rank -eq 1 ]] && top1="$host"
    ((rank++)); [[ $rank -gt 6 ]] && break
  done <<< "$sorted"
  [[ -n "$top1" ]] && printf "\n${C_G}${C_B}→ 建议 dest/SNI: %s${NC}\n" "$top1"
}

# 交互输入模式：一行可输入多个，逗号或空格分隔
interactive_loop() {
  echo
  printf "${C_B}── 自定义检测：输入网址/域名(可多个，逗号或空格分隔)；空行结束 ──${NC}\n"
  local raw tok
  while true; do
    printf "${C_C}检测 > ${NC}"; read -r raw || break
    [[ -z "$raw" ]] && break
    # 逗号统一成空格，再按空白切成多个
    raw="${raw//,/ }"
    local hosts=()
    for tok in $raw; do
      tok=$(normalize_host "$tok"); [[ -n "$tok" ]] && hosts+=("$tok")
    done
    [[ ${#hosts[@]} -eq 0 ]] && continue
    RESULTS=()                      # 本轮独立排名
    print_header
    for tok in "${hosts[@]}"; do render_row "$tok"; done
    [[ ${#hosts[@]} -gt 1 ]] && print_best   # 输入多个时给本轮排名+推荐
  done
}

# ==============================  主流程  ======================================
printf "${C_B}Reality SNI 候选检测${NC}  ${C_D}(每站%d次取最小 · 超时%ds)${NC}\n" "$ROUNDS" "$TIMEOUT"
printf "${C_D}仅用于连通性/TLS 握手检测，请在符合当地法律法规与服务条款前提下使用，后果自负。${NC}\n"

if [[ "$INTERACTIVE_ONLY" -eq 1 ]]; then
  interactive_loop
  exit 0
fi

RESULTS=()
if [[ ${#SNI_OVERRIDE[@]} -gt 0 ]]; then
  # SNI_HOSTS 覆盖：忽略分类，直接测这批
  run_batch "${SNI_OVERRIDE[@]}"
else
  # 选定分类(默认全部) + -a 追加
  if [[ ${#SEL_CATS[@]} -eq 0 ]]; then SEL_CATS=("${CAT_KEYS[@]}"); fi
  run_categories "${SEL_CATS[@]}"
  if [[ ${#EXTRA_HOSTS[@]} -gt 0 ]]; then
    printf "\n${C_B}▎追加站点  ${C_D}[-a]${NC}\n"
    run_batch "${EXTRA_HOSTS[@]}"
  fi
fi

print_best

# 批量测完后，再给一次交互补测的机会
echo
printf "${C_D}(可继续输入网址补测，直接回车退出)${NC}\n"
interactive_loop
printf "${C_D}完成。${NC}\n"
