#!/usr/bin/env bash
# Storm Proof AI installer - free download edition (Banksy AI LLC)
# Pulls the offline kit from the original public sources, so the only bandwidth used is yours.
#
#   sudo bash stormproof-install.sh --list                 show components and sizes
#   sudo bash stormproof-install.sh --dry-run              show what would be downloaded, nothing written
#   sudo bash stormproof-install.sh --only library,maps    install some components
#   sudo bash stormproof-install.sh                        install everything in the manifest
#   sudo bash stormproof-install.sh --check                offline self-test of what is installed
#
# Options: --dir DIR (default /opt/stormproof)  --manifest FILE  --skip a,b  --no-services  --yes
# Loaded drives ship without the "extras" part (iFixit guides, MedGemma) for licensing reasons:
#   sudo bash stormproof-install.sh --only extras      adds them free from the original sources
# Downloads resume if interrupted: just run the same command again.
set -uo pipefail

VERSION=0.1.0
DIR=/opt/stormproof
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HERE/stormproof-manifest.tsv"
ONLY=""; SKIP=""; DRY=0; CHECK=0; LIST=0; SERVICES=1; YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift ;;
    --manifest) MANIFEST="$2"; shift ;;
    --only) ONLY="$2"; shift ;;
    --skip) SKIP="$2"; shift ;;
    --dry-run) DRY=1 ;;
    --check) CHECK=1 ;;
    --list) LIST=1 ;;
    --no-services) SERVICES=0 ;;
    --yes|-y) YES=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (try --help)"; exit 2 ;;
  esac; shift
done

say(){ printf '\033[1;33m==>\033[0m %s\n' "$*"; }
ok(){ printf '  \033[32mok\033[0m  %s\n' "$*"; }
bad(){ printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILS=$((FAILS+1)); }
gb(){ awk -v b="${1:-0}" 'BEGIN{ if (b < 1e9) printf "%.0f MB", b/1e6; else printf "%.1f GB", b/1e9 }'; }
FAILS=0

[ -r "$MANIFEST" ] || { echo "manifest not found: $MANIFEST"; exit 1; }

# manifest rows: component  kind  name  source  bytes  post   (tab separated, # comments)
#   kind: url | ollama | docker | app     post: - | extract (unpack a .tar.bz2 here, then delete the archive)
rows(){ grep -v '^\s*#' "$MANIFEST" | grep -v '^\s*$'; }
wanted(){ case ",$SKIP," in *",$1,"*) return 1;; esac; [ -z "$ONLY" ] && return 0; case ",$ONLY," in *",$1,"*) return 0;; esac; return 1; }

# "@latest" sources: <index url>|<file prefix>|<suffix>  -> newest matching file in that directory listing
resolve(){
  local src="$1"
  case "$src" in
    daily'|'*) # daily'|'<base url>'|'<suffix>  -> newest dated build (YYYYMMDD) in the last 21 days
           local rest="${src#daily|}"; local base="${rest%%|*}" suf="${rest#*|}" d u
           for i in $(seq 0 21); do d=$(date -u -d "-$i day" +%Y%m%d); u="${base%/}/$d$suf"
             curl -fsI --max-time 15 "$u" >/dev/null 2>&1 && { echo "$u"; return; }; done ;;
    *'|'*) local idx="${src%%|*}" rest="${src#*|}"; local pre="${rest%%|*}" suf="${rest#*|}"
           local f; f=$(curl -fsSL --max-time 30 "$idx" | grep -oE "href=\"${pre}[^\"/]*${suf}\"" | sed 's/href="//;s/"$//' | sort -u | tail -1)
           [ -n "$f" ] && echo "${idx%/}/$f" ;;
    *) echo "$src" ;;
  esac
}

if [ $LIST -eq 1 ]; then
  printf '%-10s %-8s %-44s %10s\n' COMPONENT KIND NAME SIZE
  tot=0; while IFS=$'\t' read -r c k n s b note; do wanted "$c" || continue
    printf '%-10s %-8s %-44s %10s\n' "$c" "$k" "$n" "$(gb "$b")"; tot=$((tot+b)); done < <(rows)
  echo "total: $(gb $tot)"; exit 0
fi

# ---------------------------------------------------------------- offline self-test
if [ $CHECK -eq 1 ]; then
  say "Offline self-test of $DIR"
  while IFS=$'\t' read -r c k n s b note; do wanted "$c" || continue
    case "$k" in
      url) f="$DIR/$c/$n"
           if [ "$c" = routing ] && [ -s "$DIR/routing/custom_files/valhalla_tiles.tar" ]; then ok "$c: prebuilt road tiles"
           elif [ -f "$f.done" ] && [ "$note" = extract ]; then ok "$c: $n (unpacked)"
           elif [ -f "$f.done" ] && [ "$(stat -c %s "$f" 2>/dev/null || echo 0)" -ge $((b * 9 / 10)) ]; then ok "$c: $n ($(gb "$(stat -c %s "$f")"))"
           else bad "$c: $n missing or incomplete"; fi ;;
      ollama) if command -v ollama >/dev/null && ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$n"; then ok "$c: model $n"
              else bad "$c: model $n not installed"; fi ;;
      docker) if command -v docker >/dev/null && docker image inspect "$n" >/dev/null 2>&1; then ok "$c: image $n"
              else bad "$c: image $n not pulled"; fi ;;
      app) if [ -x "$DIR/$c/venv/bin/$n" ] && [ -x "$DIR/$c/vibe" ]; then ok "$c: $n ($("$DIR/$c/venv/bin/$n" --version 2>/dev/null | head -1))"
           else bad "$c: $n not installed"; fi ;;
    esac
  done < <(rows)
  if systemctl is-active --quiet stormproof-library 2>/dev/null; then
    curl -fs -m 5 http://127.0.0.1:8090/ >/dev/null && ok "library server answers on :8090" || bad "library server not answering on :8090"
  fi
  if command -v ollama >/dev/null && curl -fs -m 5 http://127.0.0.1:11434/api/tags >/dev/null; then ok "AI server answers on :11434"; fi
  [ $FAILS -eq 0 ] && say "All checks passed." || say "$FAILS check(s) failed. Run the installer again to finish missing parts."
  exit $FAILS
fi

# models shipped on a loaded drive live in $DIR/ollama/models (ollama's own layout)
model_on_dir(){ local n="$1" name tag ns base; name="${n%%:*}"; tag="${n#*:}"; [ "$tag" = "$n" ] && tag=latest
  case "$name" in */*) ns="${name%%/*}"; base="${name#*/}";; *) ns=library; base="$name";; esac
  [ -f "$DIR/ollama/models/manifests/registry.ollama.ai/$ns/$base/$tag" ]; }
TILES="$DIR/routing/custom_files/valhalla_tiles.tar"

# ---------------------------------------------------------------- plan
say "Storm Proof AI installer $VERSION -> $DIR"
need=0; plan=()
while IFS=$'\t' read -r c k n s b note; do wanted "$c" || continue
  have=0
  case "$k" in
    url) f="$DIR/$c/$n"; [ -f "$f.done" ] && have=1
         [ "$c" = routing ] && [ -s "$TILES" ] && have=1 ;;   # prebuilt road tiles on a loaded drive
    ollama) model_on_dir "$n" && have=1
            command -v ollama >/dev/null && ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$n" && have=1 ;;
    docker) command -v docker >/dev/null && docker image inspect "$n" >/dev/null 2>&1 && have=1 ;;
    app) [ -x "$DIR/$c/venv/bin/$n" ] && have=1 ;;
  esac
  if [ $have -eq 1 ]; then echo "  have  $c/$n"; else echo "  get   $c/$n  ($(gb "$b"))"; need=$((need+b)); plan+=("$c"$'\t'"$k"$'\t'"$n"$'\t'"$s"$'\t'"$b"$'\t'"$note"); fi
done < <(rows)
echo "to download: $(gb $need)"
[ ${#plan[@]} -eq 0 ] && { say "Nothing to download."; }

mkdir -p "$DIR" 2>/dev/null || { [ $DRY -eq 1 ] || { echo "cannot create $DIR (run with sudo or use --dir)"; exit 1; }; }
probe="$DIR"; [ -d "$probe" ] || probe="$(dirname "$DIR")"
free=$(( $(df --output=avail -B1 "$probe" | tail -1) ))
echo "free space at $probe: $(gb $free)"
if [ $need -gt $((free - 5000000000)) ]; then
  echo "Not enough space: need $(gb $need) plus 5 GB headroom. Pick fewer components with --only, or use --dir on a bigger drive."; exit 1
fi

if [ $DRY -eq 1 ]; then
  say "Dry run - resolving sources only"
  for r in "${plan[@]}"; do IFS=$'\t' read -r c k n s b post <<<"$r"
    case "$k" in url) u=$(resolve "$s")
                     if [ -z "$u" ]; then bad "$c: could not resolve $s"
                     elif curl -fsIL --max-time 30 -o /dev/null "$u"; then ok "$c: $u"
                     else bad "$c: not reachable: $u"; fi ;;
                 *) ok "$c: $k $n" ;; esac
  done; exit $FAILS
fi

if [ $YES -eq 0 ] && [ ${#plan[@]} -gt 0 ]; then
  read -r -p "Download $(gb $need) now? [y/N] " a; case "$a" in y|Y|yes) ;; *) echo "stopped"; exit 0;; esac
fi

# ---------------------------------------------------------------- tools
apt_get(){ command -v apt-get >/dev/null || { echo "apt-get not found: install '$*' yourself"; return 1; }
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >/dev/null; }
command -v curl >/dev/null || apt_get curl

# offline app bundles shipped on loaded drives (apps/): used when the internet is down
offline_apps(){
  if ! command -v kiwix-serve >/dev/null; then
    t=$(ls "$DIR"/apps/kiwix-tools_linux-x86_64*.tar.gz 2>/dev/null | head -1)
    [ -n "$t" ] && { say "Installing kiwix-tools from the drive"; tar -xzf "$t" -C /tmp && cp /tmp/kiwix-tools_linux-x86_64*/kiwix-* /usr/local/bin/ && ok "kiwix-tools (offline)"; }
  fi
  if ! command -v ollama >/dev/null; then
    t=$(ls "$DIR"/apps/ollama-linux-amd64.tar.zst 2>/dev/null | head -1)
    if [ -n "$t" ] && command -v zstd >/dev/null; then
      say "Installing Ollama from the drive"
      tar -C /usr/local --zstd -xf "$t" || { bad "Ollama unpack failed"; return; }
      r="$DIR/apps/ollama-linux-amd64-rocm.tar.zst"
      [ -e /dev/kfd ] && [ -f "$r" ] && { echo "  adding AMD GPU support..."; tar -C /usr/local --zstd -xf "$r"; }
      id ollama >/dev/null 2>&1 || useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama 2>/dev/null
      usermod -aG render,video ollama 2>/dev/null
      cat > /etc/systemd/system/ollama.service <<EOF
[Unit]
Description=Ollama Service
After=network-online.target
[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
[Install]
WantedBy=default.target
EOF
      systemctl daemon-reload && systemctl enable --now ollama >/dev/null 2>&1 && ok "ollama (offline)"
    fi
  fi
}
[ "$(id -u)" -eq 0 ] && [ -d "$DIR/apps" ] && offline_apps
# AI models on the drive: point Ollama at them (installs Ollama online if the drive has no bundle)
if [ "$(id -u)" -eq 0 ] && [ -d "$DIR/ollama/models/manifests" ]; then
  command -v ollama >/dev/null || { say "Installing Ollama (the AI model server) from ollama.com"; curl -fsSL https://ollama.com/install.sh | sh || bad "Ollama install failed"; }
  if command -v ollama >/dev/null && command -v systemctl >/dev/null; then
    mkdir -p /etc/systemd/system/ollama.service.d
    printf '[Service]\nEnvironment=OLLAMA_MODELS=%s\n' "$DIR/ollama/models" > /etc/systemd/system/ollama.service.d/stormproof.conf
    systemctl daemon-reload && systemctl restart ollama && ok "AI models served from $DIR/ollama/models"
  fi
fi
kinds=$(printf '%s\n' "${plan[@]}" | cut -f2 | sort -u)
if echo "$kinds" | grep -qx ollama && ! command -v ollama >/dev/null; then
  say "Installing Ollama (the AI model server) from ollama.com"
  curl -fsSL https://ollama.com/install.sh | sh || { echo "Ollama install failed"; exit 1; }
fi
if echo "$kinds" | grep -qx docker && ! command -v docker >/dev/null; then
  say "Installing Docker (runs the directions engine)"; apt_get docker.io || exit 1
fi

# ---------------------------------------------------------------- vibe coding (aider + local coding model)
install_vibe(){ # component app pip-spec
  local c="$1" app="$2" spec="$3" d="$DIR/$1" py=""
  say "$c: offline vibe coding ($spec)"
  for v in python3.12 python3.13 python3.11 python3; do
    command -v $v >/dev/null && $v -c 'import sys; sys.exit(0 if (3,9) <= sys.version_info[:2] <= (3,13) else 1)' && { py=$(command -v $v); break; }
  done
  mkdir -p "$d"
  if [ -n "$py" ] && $py -c 'import venv, ensurepip' 2>/dev/null; then
    $py -m venv "$d/venv" && "$d/venv/bin/pip" -q install --upgrade pip >/dev/null && "$d/venv/bin/pip" -q install "$spec" \
      || { bad "$c: pip install of $spec failed; run again"; return; }
  else
    # newer Ubuntu ships Python 3.14, which aider doesn't support yet: use uv to fetch a private Python 3.12
    if [ ! -x "$d/bin/uv" ]; then
      echo "  getting uv (Python manager from astral.sh)..."
      curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$d/bin" UV_NO_MODIFY_PATH=1 sh >/dev/null 2>&1 \
        || { bad "$c: could not install uv"; return; }
    fi
    export UV_PYTHON_INSTALL_DIR="$d/python" UV_CACHE_DIR="$d/.uv-cache"
    "$d/bin/uv" venv -q --python 3.12 "$d/venv" && "$d/bin/uv" pip install -q --python "$d/venv/bin/python" "$spec" \
      || { bad "$c: install of $spec failed; run again"; return; }
    rm -rf "$d/.uv-cache"
  fi
  cat > "$d/model-settings.yml" <<'EOF'
- name: ollama_chat/qwen3-coder:30b
  extra_params: {num_ctx: 32768}
- name: ollama_chat/qwen3-coder-next:latest
  extra_params: {num_ctx: 32768}
- name: ollama_chat/qwen3:4b
  extra_params: {num_ctx: 16384}
EOF
  cat > "$d/vibe" <<EOF
#!/bin/sh
# Storm Proof AI: vibe code with a local model, no internet.
#   vibe                  chat in the terminal, in the current folder
#   vibe --browser        the same, in a web page
#   VIBE_MODEL=qwen3-coder-next:latest vibe    use the bigger coder
export OLLAMA_API_BASE=\${OLLAMA_API_BASE:-http://127.0.0.1:11434}
export LITELLM_LOCAL_MODEL_COST_MAP=True
exec "$d/venv/bin/$app" --model "ollama_chat/\${VIBE_MODEL:-qwen3-coder:30b}" \\
  --model-settings-file "$d/model-settings.yml" \\
  --no-check-update --no-show-release-notes --analytics-disable --no-show-model-warnings "\$@"
EOF
  chmod +x "$d/vibe"
  [ "$(id -u)" -eq 0 ] && ln -sf "$d/vibe" /usr/local/bin/vibe
  ok "$c: type 'vibe' in any project folder"
}

# ---------------------------------------------------------------- download
for r in "${plan[@]}"; do IFS=$'\t' read -r c k n s b post <<<"$r"
  case "$k" in
    url)
      u=$(resolve "$s"); [ -z "$u" ] && { bad "$c: could not find a download for $n"; continue; }
      out="$DIR/$c/$n"; mkdir -p "$(dirname "$out")"
      say "$c: $(basename "$u")"
      tries=0; until curl -fL --retry 5 --retry-delay 10 -C - -o "$out.part" "$u"; do
        tries=$((tries+1)); [ $tries -ge 3 ] && break; echo "  retrying ($tries)..."; sleep 15; done
      [ $tries -ge 3 ] && { bad "$c: download failed; run again to resume"; continue; }
      sum=$(curl -fsL --max-time 30 "$u.sha256" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9a-f]{64}$')
      if [ -n "$sum" ]; then
        echo "  verifying checksum..."
        [ "$(sha256sum "$out.part" | awk '{print $1}')" = "$sum" ] || { bad "$c: checksum mismatch - deleting and retry next run"; rm -f "$out.part"; continue; }
      fi
      mv "$out.part" "$out"
      if [ "${post:-}" = extract ]; then
        command -v lbzip2 >/dev/null || apt_get lbzip2 || true
        echo "  unpacking (this takes a while)..."
        if command -v lbzip2 >/dev/null; then tar -I lbzip2 -xf "$out" -C "$DIR/$c"; else tar -xjf "$out" -C "$DIR/$c"; fi \
          || { bad "$c: unpack failed; run again"; continue; }
        : > "$out"   # keep a 0-byte marker, free the space
      fi
      echo "$u" > "$out.done"; ok "$c: $n" ;;
    ollama) say "$c: AI model $n"; ollama pull "$n" && ok "$c: $n" || bad "$c: pull of $n failed; run again" ;;
    docker) say "$c: image $n"; docker pull "$n" >/dev/null && ok "$c: $n" || bad "$c: pull of $n failed; run again" ;;
    app) install_vibe "$c" "$n" "$s" ;;
  esac
done

# ---------------------------------------------------------------- services
unit(){ # name description execstart [extra [Service] lines]
  cat > /etc/systemd/system/$1.service <<EOF
[Unit]
Description=$2
After=network.target
[Service]
ExecStart=$3
Restart=on-failure
$4
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload && systemctl enable --now "$1" >/dev/null 2>&1; }
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ $SERVICES -eq 1 ] && command -v systemctl >/dev/null && [ "$(id -u)" -eq 0 ]; then
  # library: kiwix-serve on :8090
  if ls "$DIR"/library/*.zim "$DIR"/extras/*.zim >/dev/null 2>&1; then
    command -v kiwix-serve >/dev/null || { say "Installing kiwix-tools (library server)"; apt_get kiwix-tools || true; }
    if command -v kiwix-serve >/dev/null; then
      unit stormproof-library "Storm Proof AI offline library" "/bin/sh -c 'exec $(command -v kiwix-serve) --port 8090 \$\$(ls $DIR/library/*.zim $DIR/extras/*.zim 2>/dev/null)'" \
        && ok "library: http://$IP:8090" || bad "library service did not start"
    fi
  fi
  # map: nginx serves the map file with range requests on :8080
  if [ -s "$DIR/maps/world.pmtiles" ]; then
    command -v nginx >/dev/null || { say "Installing nginx (map server)"; apt_get nginx || true; }
    if command -v nginx >/dev/null; then
      mkdir -p "$DIR/www/maps"; ln -sf "$DIR/maps/world.pmtiles" "$DIR/www/maps/world.pmtiles"
      [ -f "$DIR/www/index.html" ] || echo '<!doctype html><title>Storm Proof AI</title><h1>Storm Proof AI</h1><p><a href="http://'"$IP"':8090">Library</a></p>' > "$DIR/www/index.html"
      cat > /etc/nginx/sites-available/stormproof <<EOF
server { listen 8080; root $DIR/www; location / { try_files \$uri \$uri/ =404; }
  location /search/ { proxy_pass http://127.0.0.1:2322/; }
  location /route/  { proxy_pass http://127.0.0.1:8002/; } }
EOF
      ln -sf /etc/nginx/sites-available/stormproof /etc/nginx/sites-enabled/stormproof
      nginx -t >/dev/null 2>&1 && systemctl reload-or-restart nginx && ok "map files: http://$IP:8080/maps/world.pmtiles" || bad "nginx config failed"
    fi
  fi
  # address search: photon on 127.0.0.1:2322
  if [ -d "$DIR/search/photon_data" ] && [ -s "$DIR/search/photon.jar" ]; then
    command -v java >/dev/null || { say "Installing Java (address search)"; apt_get default-jre-headless || true; }
    command -v java >/dev/null && unit stormproof-search "Storm Proof AI address search" \
      "$(command -v java) -Xmx6g -jar $DIR/search/photon.jar serve -data-dir $DIR/search -listen-ip 127.0.0.1 -listen-port 2322" "WorkingDirectory=$DIR/search" \
      && ok "address search: 127.0.0.1:2322" || bad "address search did not start"
  fi
  # directions: valhalla builds its road tiles from the downloaded OSM files on first start (several hours)
  command -v docker >/dev/null || { [ -s "$TILES" ] && { say "Installing Docker (runs the directions engine)"; apt_get docker.io || true; }; }
  if { ls "$DIR"/routing/custom_files/*.osm.pbf >/dev/null 2>&1 || [ -s "$TILES" ]; } && command -v docker >/dev/null; then
    docker inspect stormproof-routing >/dev/null 2>&1 || docker run -d --name stormproof-routing --restart unless-stopped \
      -p 127.0.0.1:8002:8002 -v "$DIR/routing/custom_files:/custom_files" \
      -e server_threads=$(nproc) -e build_elevation=False -e build_transit=False -e build_admins=True -e build_time_zones=True \
      -e build_tar=True -e serve_tiles=True -e use_tiles_ignore_pbf=True -e force_rebuild=False \
      ghcr.io/valhalla/valhalla-scripted:latest >/dev/null \
      && ok "directions: building road tiles now (hours); follow with: docker logs -f stormproof-routing" || bad "directions container did not start"
  fi
fi

say "Done. $FAILS problem(s)."
[ $FAILS -eq 0 ] && echo "Next: unplug the internet and run:  sudo bash $0 --check"
exit $FAILS
