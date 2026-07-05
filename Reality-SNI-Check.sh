#!/usr/bin/env bash
# ==============================================================================
#  reality-sni-check.sh  —  Reality dest/SNI 候选测速与合规检测
#
#  在【落地服务器】上跑：为该机测出握手最快、且满足 Reality 要求
#  (TLS1.3 + h2 + X25519) 的 SNI 候选，供 VLESS-Reality dest 选用。
#
#  用法:
#    ./reality-sni-check.sh                 # 无参数 → 进交互菜单(选测试项)
#    ./reality-sni-check.sh -l              # 列出所有分类
#    ./reality-sni-check.sh -c edu          # 直接只测"大学"分类(跳过菜单)
#    ./reality-sni-check.sh -c edu,tech     # 测多个分类(逗号/空格分隔)
#    ./reality-sni-check.sh -r jp           # 按地区推荐(该区归属站+全球站)
#    ./reality-sni-check.sh -a "a.com b.com"# 追加自定义站点一起测
#    ./reality-sni-check.sh -i              # 只进交互输入模式(一行可多站)
#    ./reality-sni-check.sh -n 5 -t 6       # 每站探测5次、单次超时6s
#    SNI_HOSTS="a.com b.com" ./reality-sni-check.sh   # 用自己的清单替换全部
#
#  分类键: cdn(全球CDN) cloud(云/开发) tech(科技大厂) fin(金融) edu(大学)
#          media(流媒体) social(社交) gaming(游戏) ecom(电商) region(区域锚点)
#  地区键: global us eu jp hk sg cn au kr   (-r 用)
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
  www.naver.com               # 韩国
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

# ---------------- 地区标签 ----------------
# SNI 站点的“归属地区”：落地机在某区时，选该区归属站更贴合正常流量画像。
# 未列出的一律 global（大厂 CDN，任何区都自然）。
host_region() {
  case "$1" in
    www.lovelive-anime.jp|www.yahoo.co.jp|www.rakuten.co.jp|www.ana.co.jp|www.u-tokyo.ac.jp|www.kyoto-u.ac.jp) echo jp ;;
    www.mercedes-benz.com|www.bmw.com|www.audi.com|www.lufthansa.com|www.ox.ac.uk|www.cam.ac.uk|www.imperial.ac.uk|www.ethz.ch|www.epfl.ch|www.zara.com|www.ikea.com|www.adidas.com) echo eu ;;
    www.nus.edu.sg|www.ntu.edu.sg|www.singaporeair.com) echo sg ;;
    www.hku.hk|www.hkust.edu.hk|www.cathaypacific.com) echo hk ;;
    www.tsinghua.edu.cn|www.pku.edu.cn|www.alibaba.com) echo cn ;;
    www.qantas.com|www.unimelb.edu.au) echo au ;;
    www.naver.com) echo kr ;;
    www.mit.edu|www.stanford.edu|www.harvard.edu|www.berkeley.edu|www.cornell.edu|www.princeton.edu|www.yale.edu|www.columbia.edu|www.utoronto.ca) echo us ;;
    *) echo global ;;
  esac
}

REGION_KEYS=(global us eu jp hk sg cn au kr)
region_label() {
  case "$1" in
    global) echo "全球通用(大厂CDN)" ;;
    us)     echo "美国/北美" ;;
    eu)     echo "欧洲" ;;
    jp)     echo "日本" ;;
    hk)     echo "香港" ;;
    sg)     echo "东南亚/新加坡" ;;
    cn)     echo "中国大陆" ;;
    au)     echo "澳洲" ;;
    kr)     echo "韩国" ;;
    *)      echo "$1" ;;
  esac
}

# 全部站点去重
all_hosts() { local k; for k in "${CAT_KEYS[@]}"; do cat_hosts "$k"; done | awk '!seen[$0]++'; }

# 某地区的候选：该区归属站 + 全球站（global 永远纳入，作为安全底牌）
region_hosts() {
  local r="$1" h reg
  all_hosts | while IFS= read -r h; do
    [[ -z "$h" ]] && continue
    reg=$(host_region "$h")
    if [[ "$r" == "global" ]]; then
      [[ "$reg" == "global" ]] && echo "$h"
    else
      [[ "$reg" == "$r" || "$reg" == "global" ]] && echo "$h"
    fi
  done
}

ROUNDS=3          # 每站探测次数，取最小值避免抖动
TIMEOUT=5         # 单次连接超时(秒)
EXTRA_HOSTS=()
INTERACTIVE_ONLY=0
SEL_CATS=()       # -c 指定的分类；空=全部
SEL_REGION=""     # -r 指定的地区；空=不按地区

# ---------------- 颜色 ----------------
if [[ -t 1 ]]; then
  C_B=$'\e[1m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_D=$'\e[2m'; C_C=$'\e[36m'; NC=$'\e[0m'
else
  C_B=""; C_G=""; C_Y=""; C_R=""; C_D=""; C_C=""; NC=""
fi

usage() { grep '^#' "$0" | sed '/^#!/d; s/^# \{0,1\}//' | head -22; exit 0; }

die() {
  printf "%s错误: %s%s\n" "$C_R" "$*" "$NC" >&2
  exit 1
}

is_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

category_exists() {
  local want="$1" k
  for k in "${CAT_KEYS[@]}"; do
    [[ "$k" == "$want" ]] && return 0
  done
  return 1
}

region_exists() {
  local want="$1" r
  for r in "${REGION_KEYS[@]}"; do
    [[ "$r" == "$want" ]] && return 0
  done
  return 1
}

validate_options() {
  local k
  is_positive_int "$ROUNDS" || die "-n 必须是正整数: $ROUNDS"
  is_positive_int "$TIMEOUT" || die "-t 必须是正整数秒数: $TIMEOUT"
  for k in "${SEL_CATS[@]}"; do
    category_exists "$k" || die "未知分类: $k"
  done
  if [[ -n "$SEL_REGION" ]]; then
    region_exists "$SEL_REGION" || die "未知地区: $SEL_REGION"
  fi
}

OPENSSL_X25519_ARGS=()
detect_openssl_x25519_args() {
  local help
  help=$(openssl s_client -help 2>&1 || true)
  if grep -q -- "-groups" <<< "$help"; then
    OPENSSL_X25519_ARGS=(-groups X25519)
  elif grep -q -- "-curves" <<< "$help"; then
    OPENSSL_X25519_ARGS=(-curves X25519)
  fi
}

probe_x25519() {
  local host="$1" xs
  [[ ${#OPENSSL_X25519_ARGS[@]} -gt 0 ]] || return 1
  xs=$(echo -n | timeout "$TIMEOUT" openssl s_client -connect "${host}:443" \
        -servername "$host" -verify_hostname "$host" -alpn h2,http/1.1 \
        "${OPENSSL_X25519_ARGS[@]}" 2>&1 | tr -d '\0')
  grep -qE "New, TLSv1\.3|Protocol *: *TLSv1\.3" <<< "$xs" || return 1
  grep -qiE "Verify return code: 0 \(ok\)|Verification: OK" <<< "$xs" || return 1
  return 0
}

list_cats() {
  printf "${C_B}可用分类 (用 -c 选，逗号分隔):${NC}\n"
  for k in "${CAT_KEYS[@]}"; do
    printf "  ${C_C}%-8s${NC} %s  ${C_D}(%d 站)${NC}\n" "$k" "$(cat_label "$k")" "$(cat_hosts "$k" | grep -c .)"
  done
  exit 0
}

while getopts "a:c:r:n:t:ilh" opt; do
  case "$opt" in
    a) read -r -a EXTRA_HOSTS <<< "$OPTARG" ;;
    c) IFS=', ' read -r -a SEL_CATS <<< "$OPTARG" ;;
    r) SEL_REGION="$OPTARG" ;;
    n) ROUNDS="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    i) INTERACTIVE_ONLY=1 ;;
    l) list_cats ;;
    h) usage ;;
    *) usage ;;
  esac
done

validate_options
detect_openssl_x25519_args

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

# 探测单个站点，输出: "minHandshake tls13 h2 tempkey chain httpcode certok"
probe_host() {
  local host="$1" best="" code="-" line ac hc

  # 详情：一次 openssl -showcerts 拿 TLS1.3 / ALPN(h2) / 临时密钥(X25519) / 证书链层数 / 证书验证结果
  local so tls13="no" h2="no" tempkey="-" chain=0 certok="no"
  so=$(echo -n | timeout "$TIMEOUT" openssl s_client -connect "${host}:443" \
        -servername "$host" -verify_hostname "$host" -alpn h2,http/1.1 \
        -showcerts 2>&1 | tr -d '\0')
  grep -qE "New, TLSv1\.3|Protocol *: *TLSv1\.3" <<< "$so" && tls13="yes"
  grep -qi "ALPN protocol: h2" <<< "$so" && h2="yes"
  grep -qiE "Verify return code: 0 \(ok\)|Verification: OK" <<< "$so" && certok="yes"
  tempkey=$(grep "Server Temp Key" <<< "$so" | sed 's/.*Server Temp Key: *//; s/,.*//' | head -1)
  [[ -z "$tempkey" ]] && tempkey="-"
  if [[ "$tls13" == "yes" && "$certok" == "yes" && "$tempkey" != *X25519* ]] && probe_x25519 "$host"; then
    tempkey="X25519"
  fi
  chain=$(grep -c "BEGIN CERTIFICATE" <<< "$so")   # 证书链层数(叶子+中间)
  [[ -z "$chain" ]] && chain=0
  local handshake_ok="no"; [[ "$chain" -ge 1 ]] && handshake_ok="yes"

  # 延迟：只测 TLS 握手(time_appconnect)——这正是 Reality 关心的、与 HTTP 层无关。
  #   用 --http1.1 避开部分站(Akamai 等)对裸 curl 的 h2 INTERNAL_ERROR；
  #   即使 HTTP 被拦(code=000/403)，握手时间仍有效，照常采用，不再误判失败。
  for _ in $(seq 1 "$ROUNDS"); do
    line=$(curl -sS -o /dev/null --http1.1 --max-time "$TIMEOUT" \
        -w "%{time_appconnect} %{http_code}" "https://${host}/" 2>/dev/null)
    ac="${line%% *}"; hc="${line##* }"
    if [[ -n "$ac" && "$ac" != "0.000000" && "$ac" != "0" ]]; then
      [[ -n "$hc" && "$hc" != "000" ]] && code="$hc"
      if [[ -z "$best" ]] || awk "BEGIN{exit !($ac < $best)}"; then best="$ac"; fi
    fi
  done

  # curl 一次握手时间都没拿到，但 openssl 握手其实成功 → 用 openssl 计时兜底
  if [[ -z "$best" && "$handshake_ok" == "yes" && "$certok" == "yes" ]]; then
    local t0 t1
    t0=$(date +%s.%N 2>/dev/null)
    echo -n | timeout "$TIMEOUT" openssl s_client -connect "${host}:443" \
         -servername "$host" -verify_hostname "$host" -verify_return_error >/dev/null 2>&1
    t1=$(date +%s.%N 2>/dev/null)
    if [[ -n "$t0" && -n "$t1" ]]; then
      best=$(awk "BEGIN{d=$t1-$t0; if(d>0)printf \"%.3f\",d; else print \"\"}")
      [[ -n "$best" ]] && code="tls"    # 标记：握手可用，HTTP 层无响应
    fi
  fi

  [[ -z "$best" ]] && { printf 'FAIL %s %s %s %s %s %s' "$tls13" "$h2" "$tempkey" "$chain" "$code" "$certok"; return; }
  printf '%s %s %s %s %s %s %s' "$best" "$tls13" "$h2" "$tempkey" "$chain" "$code" "$certok"
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
  local host="$1" out ac tls13 h2 tempkey chain code certok qualify mark ac_disp x25519="no"
  out=$(probe_host "$host")
  read -r ac tls13 h2 tempkey chain code certok <<< "$out"

  if [[ "$ac" == "FAIL" ]]; then
    if [[ "$tls13" == "yes" && "$certok" != "yes" ]]; then
      printf "${C_R}%-24s %10s  %-6s %-4s %-14s %-4s %-5s %s${NC}\n" \
        "$host" "证书无效" "$tls13" "$h2" "${tempkey:0:14}" "$chain" "$code" "✗ 证书"
      RESULTS+=("$host|999|no")
      return
    fi
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
  if [[ "$tls13" == "yes" && "$certok" != "yes" ]]; then
    qualify="${C_R}✗ 证书${NC}"; mark="bad"
  elif [[ "$tls13" == "yes" && "$h2" == "yes" && "$x25519" == "yes" && "$chain_ok" == "yes" ]]; then
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
  local cats=("$@") k host
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
  printf "${C_B}══ 本机最优 SNI 排名 (仅列证书有效且 TLS1.3 通过者，按握手升序) ══${NC}\n"
  local sorted top1=""
  sorted=$(printf '%s\n' "${RESULTS[@]}" \
    | awk -F'|' '$2!=999' | sort -t'|' -k2 -n)
  if [[ -z "$sorted" ]]; then
    printf "${C_R}没有站点满足证书有效且通过 TLS1.3，检查落地机出网/换候选列表${NC}\n"; return
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

# ============================  交互菜单  ======================================
# 从分类里多选 (数字，空格/逗号分隔; a=全部; 回车返回)
menu_pick_categories() {
  echo
  printf "${C_B}选择分类 (数字，空格或逗号分隔; a=全部; 回车返回):${NC}\n"
  local i=1 k
  for k in "${CAT_KEYS[@]}"; do
    printf "  ${C_C}%2d${NC}) %-7s %s ${C_D}(%d 站)${NC}\n" \
      "$i" "$k" "$(cat_label "$k")" "$(cat_hosts "$k" | grep -c .)"
    ((i++))
  done
  printf "${C_C}选择 > ${NC}"; local sel; read -r sel
  [[ -z "$sel" ]] && return 1
  if [[ "$sel" == "a" || "$sel" == "A" ]]; then SEL_CATS=("${CAT_KEYS[@]}"); return 0; fi
  sel="${sel//,/ }"; SEL_CATS=(); local n
  for n in $sel; do
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    [[ "$n" -ge 1 && "$n" -le ${#CAT_KEYS[@]} ]] && SEL_CATS+=("${CAT_KEYS[$((n-1))]}")
  done
  [[ ${#SEL_CATS[@]} -eq 0 ]] && return 1
  return 0
}

# 设置探测次数/超时
settings_menu() {
  echo
  printf "${C_B}当前设置: 每站探测 %d 次 · 单次超时 %d 秒${NC}\n" "$ROUNDS" "$TIMEOUT"
  printf "新的探测次数 (回车不改): "; local r; read -r r
  [[ "$r" =~ ^[0-9]+$ && "$r" -ge 1 ]] && ROUNDS="$r"
  printf "新的超时秒数 (回车不改): "; local t; read -r t
  [[ "$t" =~ ^[0-9]+$ && "$t" -ge 1 ]] && TIMEOUT="$t"
  printf "${C_G}已更新: %d 次 · %d 秒${NC}\n" "$ROUNDS" "$TIMEOUT"
}

# 跑选定分类并出排名
run_selected() {
  RESULTS=()
  run_categories "$@"
  print_best
}

# 从地区里选一个 (数字; 回车返回)
menu_pick_region() {
  echo
  printf "${C_B}选择落地机所在/目标地区 (数字; 回车返回):${NC}\n"
  printf "${C_D}  会测「该地区归属站 + 全球通用站」，推荐里挑就近又合规的。${NC}\n"
  local i=1 r
  for r in "${REGION_KEYS[@]}"; do
    local n; n=$(region_hosts "$r" | grep -c .)
    printf "  ${C_C}%2d${NC}) %-7s %s ${C_D}(%d 站)${NC}\n" "$i" "$r" "$(region_label "$r")" "$n"
    ((i++))
  done
  printf "${C_C}选择 > ${NC}"; local sel; read -r sel
  [[ -z "$sel" ]] && return 1
  [[ "$sel" =~ ^[0-9]+$ ]] || return 1
  [[ "$sel" -ge 1 && "$sel" -le ${#REGION_KEYS[@]} ]] || return 1
  SEL_REGION="${REGION_KEYS[$((sel-1))]}"
  return 0
}

# 按地区跑：该区归属站 + 全球站，出排名
run_region() {
  local r="$1" rh=() h
  region_exists "$r" || { printf "${C_R}未知地区: %s${NC}\n" "$r"; return 1; }
  while IFS= read -r h; do [[ -n "$h" ]] && rh+=("$h"); done < <(region_hosts "$r")
  [[ ${#rh[@]} -eq 0 ]] && { printf "${C_R}未知地区: %s${NC}\n" "$r"; return 1; }
  RESULTS=()
  printf "\n${C_B}▎地区推荐: %s ${C_D}[%s] · 含全球通用站${NC}\n" "$(region_label "$r")" "$r"
  print_header
  for h in "${rh[@]}"; do render_row "$h"; done
  print_best
}

# 清屏 (仅终端下生效，管道/重定向不清，避免破坏日志)
cls() {
  [[ -t 1 ]] || return 0
  if command -v clear >/dev/null 2>&1; then clear; else printf '\033[2J\033[H'; fi
}

# 看完结果后暂停，回车返回主菜单
pause_return() {
  printf "\n${C_D}按回车返回主菜单...${NC}"; read -r _ || true
}

# 主菜单
main_menu() {
  local TOTAL_SITES; TOTAL_SITES=$(for k in "${CAT_KEYS[@]}"; do cat_hosts "$k"; done | grep -c .)
  while true; do
    cls                                   # 返回/进入主菜单都清屏
    printf "${C_B}════════ Reality SNI 检测 · 主菜单 ════════${NC}\n"
    printf "${C_D}仅用于连通性/TLS 握手检测，请合规使用，后果自负${NC}\n\n"
    printf "  ${C_C}1${NC}) 快速测试   ${C_D}(cdn + cloud + tech，最常用)${NC}\n"
    printf "  ${C_C}2${NC}) 全部分类   ${C_D}(%d 站，较慢)${NC}\n" "$TOTAL_SITES"
    printf "  ${C_C}3${NC}) 选择分类测试\n"
    printf "  ${C_C}4${NC}) 按地区推荐   ${C_D}(就近 + 合规)${NC}\n"
    printf "  ${C_C}5${NC}) 自定义网址检测   ${C_D}(一行可多站)${NC}\n"
    printf "  ${C_C}6${NC}) 设置   ${C_D}(次数=%d 超时=%ds)${NC}\n" "$ROUNDS" "$TIMEOUT"
    printf "  ${C_C}0${NC}) 退出\n"
    printf "${C_C}请选择 > ${NC}"; local c; read -r c || break
    case "$c" in
      1) cls; run_selected cdn cloud tech;        pause_return ;;
      2) cls; run_selected "${CAT_KEYS[@]}";       pause_return ;;
      3) cls; if menu_pick_categories; then run_selected "${SEL_CATS[@]}"; pause_return; fi ;;
      4) cls; if menu_pick_region; then run_region "$SEL_REGION"; pause_return; fi ;;
      5) cls; interactive_loop;                    pause_return ;;
      6) cls; settings_menu;                       pause_return ;;
      0|q|Q) cls; printf "${C_D}再见。${NC}\n"; break ;;
      "") : ;;                                     # 空输入：循环顶部重绘
      *) printf "${C_R}无效选择: %s${NC}\n" "$c"; sleep 1 ;;
    esac
  done
}

# ==============================  主流程  ======================================
printf "${C_B}Reality SNI 候选检测${NC}  ${C_D}(每站%d次取最小 · 超时%ds)${NC}\n" "$ROUNDS" "$TIMEOUT"
printf "${C_D}仅用于连通性/TLS 握手检测，请在符合当地法律法规与服务条款前提下使用，后果自负。${NC}\n"

# -i 只进交互输入
if [[ "$INTERACTIVE_ONLY" -eq 1 ]]; then
  interactive_loop; exit 0
fi

# -r 按地区直接跑
if [[ -n "$SEL_REGION" ]]; then
  run_region "$SEL_REGION"
  exit $?
fi

# 传了 CLI 参数(分类/追加/SNI_HOSTS 覆盖) → 直接跑，不进菜单
if [[ ${#SNI_OVERRIDE[@]} -gt 0 || ${#SEL_CATS[@]} -gt 0 || ${#EXTRA_HOSTS[@]} -gt 0 ]]; then
  RESULTS=()
  if [[ ${#SNI_OVERRIDE[@]} -gt 0 ]]; then
    run_batch "${SNI_OVERRIDE[@]}"
  else
    [[ ${#SEL_CATS[@]} -eq 0 ]] && SEL_CATS=("${CAT_KEYS[@]}")
    run_categories "${SEL_CATS[@]}"
    if [[ ${#EXTRA_HOSTS[@]} -gt 0 ]]; then
      printf "\n${C_B}▎追加站点  ${C_D}[-a]${NC}\n"
      run_batch "${EXTRA_HOSTS[@]}"
    fi
  fi
  print_best
  if [[ -t 0 ]]; then
    echo; printf "${C_D}(可继续输入网址补测，直接回车退出)${NC}\n"
    interactive_loop
  fi
  printf "${C_D}完成。${NC}\n"
  exit 0
fi

# 无参数 → 进菜单
main_menu
