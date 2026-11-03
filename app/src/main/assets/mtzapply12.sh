#!/system/bin/sh
# MtzApply-12 — áp theme .mtz qua Theme Manager bằng quyền shell (Shizuku rish / adb).
# Cách dùng:  sh mtzapply12.sh [duong_dan.mtz] [--dry]
# Mặc định:   /sdcard/MIUI/theme/MtzApply.mtz
#
# Các bước (giống đường HyperTheme dùng khi không có ApplyThemeForScreenshot):
#  1) giải nén .mtz vào  .../files/MIUI/theme/.data/content/theme/<id>/
#  2) tạo file thông tin .mrm trong .../.data/meta/theme/<id>.mrm
#  3) mở ThemeDetailActivity với ViewLocalResource://view.local.resource#<id>

MTZ="/sdcard/MIUI/theme/MtzApply.mtz"
DRY=0
AUTO=0
for a in "$@"; do
  case "$a" in
    --dry) DRY=1 ;;
    --auto) AUTO=1 ;;
    *) MTZ="$a" ;;
  esac
done

TM=com.android.thememanager
BASE="${BASE:-/sdcard/Android/data/$TM/files/MIUI/theme/.data}"
REAL="${REAL:-/storage/emulated/0/Android/data/$TM/files/MIUI/theme/.data}"
CONTENT="$BASE/content/theme"
META="$BASE/meta/theme"
LOG="${LOG:-/sdcard/mtzapply12.log}"

say() { echo "[MtzApply-12] $*"; echo "[MtzApply-12] $*" >> "$LOG" 2>/dev/null; }
: > "$LOG" 2>/dev/null

say "uid=$(id -u) mtz=$MTZ"
if [ "$(id -u)" != "2000" ] && [ "$(id -u)" != "0" ] && [ -z "$ALLOW_ANY_UID" ]; then
  say "LOI: can chay bang quyen shell (Shizuku rish hoac adb shell), khong phai app thuong."
  exit 1
fi
[ -f "$MTZ" ] || { say "LOI: khong thay file $MTZ"; exit 1; }

# id theme: 32 ky tu hex tu md5 cua file .mtz (cung file -> cung id, chay lai se ghi de dung cho)
ID="$(md5sum "$MTZ" 2>/dev/null | cut -c1-32)"
[ -n "$ID" ] || ID="mtzapply$(date +%s)"
CDIR="$CONTENT/$ID"
MRM="$META/$ID.mrm"
say "id=$ID"

# --- file .mrm mau do Theme Manager/HyperTheme da tao truoc do (neu co) ---
TEMPLATE=""
if [ -d "$META" ]; then
  TEMPLATE="$(ls -t "$META"/*.mrm 2>/dev/null | grep -v "/$ID.mrm$" | head -n 1)"
fi

if [ "$DRY" = "1" ]; then
  say "DRY: se giai nen vao $CDIR, ghi $MRM, roi mo trang chi tiet. Mau .mrm: ${TEMPLATE:-khong co}"
  exit 0
fi

# 1) giai nen
rm -rf "$CDIR"
mkdir -p "$CDIR" "$META" || { say "LOI: khong tao duoc thu muc $CDIR"; exit 1; }
if command -v unzip >/dev/null 2>&1; then
  unzip -o -q "$MTZ" -d "$CDIR" 2>>"$LOG" || say "CANH BAO: unzip tra ve loi (xem log)"
else
  say "LOI: may khong co lenh unzip trong shell"; exit 1
fi
N="$(ls -A "$CDIR" 2>/dev/null | wc -l)"
say "da giai nen $N muc vao $CDIR"
[ "$N" -gt 0 ] || { say "LOI: thu muc dich rong"; exit 1; }
[ -f "$CDIR/description.xml" ] || say "CANH BAO: khong co description.xml o goc (mtz co the co thu muc con)"
chmod -R a+rX "$CDIR" 2>/dev/null

# 2) tao .mrm
TITLE=""
[ -f "$CDIR/description.xml" ] && TITLE="$(sed -n 's/.*<title[^>]*>\([^<]*\)<\/title>.*/\1/p' "$CDIR/description.xml" | head -n 1 | tr -d '"\\')"
[ -n "$TITLE" ] || TITLE="MtzApply"

if [ -n "$TEMPLATE" ] && [ -s "$TEMPLATE" ]; then
  OLD="$(basename "$TEMPLATE" .mrm)"
  say "dung mau .mrm: $TEMPLATE (id cu $OLD)"
  sed "s/$OLD/$ID/g" "$TEMPLATE" > "$MRM"
else
  say "khong co mau .mrm -> tu tao theo cac truong da biet"
  SIZE="$(wc -c < "$MTZ" | tr -d ' ')"
  cat > "$MRM" <<JSON
{"localId":"$ID","onlineId":"","assemblyId":"","productId":"","resourceCode":"theme","platform":17,"themeType":0,"hash":"$ID","title":"$TITLE","size":$SIZE,"contentPath":"$REAL/content/theme/$ID","metaPath":"$REAL/meta/theme/$ID.mrm"}
JSON
fi
chmod a+r "$MRM" 2>/dev/null
say "da ghi $MRM:"
cat "$MRM" >> "$LOG"; echo >> "$LOG"

# 3) mo trang chi tiet theme
logcat -c 2>/dev/null
am start --user 0 -a android.intent.action.VIEW \
  -d "ViewLocalResource://view.local.resource#$ID" \
  -n $TM/.module.detail.view.ThemeDetailActivity \
  --es REQUEST_RESOURCE_CODE theme 2>&1 | tee -a "$LOG"

# 4) tu dong bam "Ap dung" bang uiautomator + input tap (quyen shell)
auto_tap() {
  UI=/data/local/tmp/mtz_ui.xml
  TAPS=0; i=0
  while [ $i -lt 10 ] && [ $TAPS -lt 3 ]; do
    i=$((i+1)); sleep 2
    rm -f "$UI"
    uiautomator dump "$UI" >/dev/null 2>&1
    if [ ! -s "$UI" ]; then say "auto: uiautomator dump khong chay duoc"; return 1; fi
    say "auto[$i] chu tren man hinh: $(grep -o 'text="[^"]\+"' "$UI" | head -n 12 | tr '\n' ' ')"
    NODE="$(grep -o '<node [^>]*>' "$UI" | grep -E 'text="(Áp dụng|Áp dụng ngay|Apply|Apply now|应用|立即应用|Ap dung)"' | head -n 1)"
    if [ -z "$NODE" ]; then
      [ $TAPS -gt 0 ] && break
      continue
    fi
    B="$(echo "$NODE" | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p')"
    set -- $B
    [ -n "$4" ] || { say "auto: khong doc duoc bounds"; return 1; }
    X=$(( ($1 + $3) / 2 )); Y=$(( ($2 + $4) / 2 ))
    say "auto: bam Ap dung tai $X,$Y"
    input tap $X $Y
    TAPS=$((TAPS+1))
  done
  say "auto: xong ($TAPS lan bam)"
}
[ "$AUTO" = "1" ] && auto_tap

sleep 3
say "---- logcat (loi lien quan Theme Manager) ----"
logcat -d -t 400 2>/dev/null | grep -i "thememanager\|ThemeDetail\|MiuiTheme\|ResourceParse\|mrm" | grep -v "avc:" | tail -n 30 | tee -a "$LOG"
say "xong. Neu trang chi tiet hien ra -> bam 'Ap dung'. Neu loi: gui file $LOG"
