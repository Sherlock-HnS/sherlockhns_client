#!/usr/bin/env bash
# Música do LMS: baixa do YouTube, normaliza por loudness e registra na playlist.
#
#   tools/add_music.sh add [URL]   baixa -> normaliza (2 passes) -> mp3 final -> playlist
#   tools/add_music.sh list        lista as faixas da playlist
#   tools/add_music.sh verify      confere arquivos, hash do nome e loudness de cada faixa
#
# Por que o hash no nome do arquivo?
#   O cache de sons do GMod no cliente não tem como ser invalidado. Se um arquivo
#   for trocado mantendo o caminho, quem já baixou continua com o antigo. Então o
#   nome carrega os primeiros 8 hex do SHA-256 do mp3 FINAL (já normalizado): conteúdo
#   novo = caminho novo. Nunca edite um mp3 já publicado; rode o "add" de novo.
#
# Variáveis opcionais:
#   LUFS=-16        loudness integrado alvo
#   TP=-1.5         true peak máximo (dBTP)
#   LRA=11          faixa de loudness
#   BITRATE=192k    bitrate CBR do mp3 (CBR deixa o SetTime/seek do cliente preciso)
#   LMS_SOUND_ROOT  pasta que contém sound/ (padrão: addon/)

set -euo pipefail


ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONTENT_ROOT="${LMS_SOUND_ROOT:-$ROOT/addon}"

REL_DIR="sherlockhns/lms"
LMS_DIR="$CONTENT_ROOT/sound/$REL_DIR"
PLAYLIST="$ROOT/addon/lua/sherlockhns_client/sh_lms_playlist.lua"

LUFS="${LUFS:--16}"
TP="${TP:--1.5}"
LRA="${LRA:-11}"
BITRATE="${BITRATE:-192k}"
TOLERANCE="1.0"                                  # |LUFS medido - alvo| aceito

if [ -t 1 ]; then
  C_BLD=$'\033[1m'; C_GRN=$'\033[32m'; C_RED=$'\033[31m'; C_YLW=$'\033[33m'; C_OFF=$'\033[0m'
else
  C_BLD=""; C_GRN=""; C_RED=""; C_YLW=""; C_OFF=""
fi
step() { printf '\n%s%s%s\n' "$C_BLD" "$*" "$C_OFF"; }
ok()   { printf '  %s✓%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_YLW" "$C_OFF" "$*"; }
die()  { printf '%s✗ %s%s\n' "$C_RED" "$*" "$C_OFF" >&2; exit 1; }

need() {
  local c
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "falta o comando '$c' (brew install $c)"; done
}

sha8() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -c1-8
  else shasum -a 256 "$1" | cut -c1-8; fi
}

lua_escape() { sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

slugify() {
  printf '%s' "$1" | { iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || cat; } \
    | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+|_+$//g' | cut -c1-60
}

human_size() { du -h "$1" | cut -f1 | tr -d ' '; }

# Mede o loudness de um arquivo (1ª passada do loudnorm). Imprime o JSON do ffmpeg.
measure() {
  ffmpeg -hide_banner -nostats -i "$1" \
    -af "loudnorm=I=${LUFS}:TP=${TP}:LRA=${LRA}:print_format=json" -f null - 2>&1 \
    | awk '/^\{/{p=1} p{print} /^\}/{p=0}'
}

# ---------------------------------------------------------------- add
cmd_add() {
  need yt-dlp ffmpeg ffprobe jq curl awk sed iconv
  local URL="${1:-}"
  if [ -z "$URL" ]; then read -r -p "URL do YouTube: " URL; fi
  [ -n "$URL" ] || die "URL vazia."
  [ -f "$PLAYLIST" ] || die "playlist não encontrada: ${PLAYLIST#$ROOT/}"
  mkdir -p "$LMS_DIR"

  local TMP
  TMP="$(mktemp -d)"

  trap 'rm -rf "${TMP:-}"' EXIT

  # ---------- 1/4 metadados
  step "[1/4] Lendo informações do vídeo"
  local meta YT_ID YT_TITLE YT_UPLOADER
  meta=$(yt-dlp --no-playlist --skip-download --no-warnings \
          --print "%(id)s" --print "%(title)s" --print "%(uploader)s" "$URL") \
    || die "yt-dlp não conseguiu ler a URL."
  YT_ID=$(sed -n 1p <<<"$meta"); YT_TITLE=$(sed -n 2p <<<"$meta"); YT_UPLOADER=$(sed -n 3p <<<"$meta")
  [ "$YT_UPLOADER" = "NA" ] && YT_UPLOADER=""
  ok "$YT_TITLE  (${YT_UPLOADER:-canal desconhecido})"

  local THUMB="" q u code
  for q in maxresdefault hqdefault; do
    u="https://i3.ytimg.com/vi/$YT_ID/$q.jpg"
    code=$(curl -s -o /dev/null -w '%{http_code}' -I "$u" || true)
    if [ "$code" = "200" ]; then THUMB="$u"; break; fi
  done
  [ -n "$THUMB" ] || THUMB="https://i3.ytimg.com/vi/$YT_ID/hqdefault.jpg"

  local slug; slug=$(slugify "$YT_TITLE")
  [ -n "$slug" ] || slug="yt_$(printf '%s' "$YT_ID" | tr '[:upper:]' '[:lower:]')"

  # ---------- 2/4 download (melhor áudio, SEM recodificar: só um encode lossy no final)
  step "[2/4] Baixando o melhor áudio"
  yt-dlp --no-playlist --no-warnings --newline --color never \
         -f "bestaudio/best" -o "$TMP/src.%(ext)s" "$URL" \
    || die "falha no download."
  local SRC; SRC=$(ls "$TMP"/src.* 2>/dev/null | head -n1 || true)
  [ -f "$SRC" ] || die "arquivo baixado não apareceu."
  ok "origem: $(basename "$SRC") ($(human_size "$SRC"))"

  # ---------- 3/4 normalização por loudness (EBU R128, 2 passes)
  step "[3/4] Normalizando para ${LUFS} LUFS (TP ${TP} dBTP, LRA ${LRA})"
  local json; json=$(measure "$SRC")
  [ -n "$json" ] || die "o ffmpeg não devolveu as medições do loudnorm."

  local m_i m_tp m_lra m_thr m_off
  m_i=$(jq -r '.input_i' <<<"$json");   m_tp=$(jq -r '.input_tp' <<<"$json")
  m_lra=$(jq -r '.input_lra' <<<"$json"); m_thr=$(jq -r '.input_thresh' <<<"$json")
  m_off=$(jq -r '.target_offset' <<<"$json")
  ok "medido: ${m_i} LUFS, pico ${m_tp} dBTP, LRA ${m_lra}"

  local STAGE="$TMP/out.mp3"
  ffmpeg -hide_banner -loglevel error -y -i "$SRC" -vn -map_metadata -1 \
    -af "loudnorm=I=${LUFS}:TP=${TP}:LRA=${LRA}:measured_I=${m_i}:measured_TP=${m_tp}:measured_LRA=${m_lra}:measured_thresh=${m_thr}:offset=${m_off}:linear=true:print_format=summary" \
    -ar 44100 -ac 2 -c:a libmp3lame -b:a "$BITRATE" -write_id3v2 0 -write_xing 1 "$STAGE" \
    || die "falha ao normalizar/codificar."
  [ -s "$STAGE" ] || die "mp3 final vazio."

  # confere o resultado de verdade (mede o arquivo já codificado)
  local final_i dev
  final_i=$(measure "$STAGE" | jq -r '.input_i')
  dev=$(awk -v a="$final_i" -v b="$LUFS" 'BEGIN{d=a-b; if(d<0)d=-d; print d}')
  if awk -v d="$dev" -v t="$TOLERANCE" 'BEGIN{exit !(d>t)}'; then
    die "loudness final ${final_i} LUFS fora do alvo ${LUFS} (±${TOLERANCE}). Nada foi publicado."
  fi
  ok "resultado: ${final_i} LUFS"

  # ---------- 4/4 nome definitivo = slug + hash do conteúdo final
  step "[4/4] Publicando na pasta de sons"
  local hash name OUT
  hash=$(sha8 "$STAGE")
  name="${slug}_${hash}"
  OUT="$LMS_DIR/$name.mp3"
  if [ -f "$OUT" ] || grep -Fq "\"$REL_DIR/$name.mp3\"" "$PLAYLIST"; then
    die "essa faixa (mesmo conteúdo) já existe: $name.mp3"
  fi
  mv "$STAGE" "$OUT"
  ok "${OUT#$ROOT/}  ($(human_size "$OUT"))"

  # ---------- metadados da playlist
  step "Informações da faixa"
  local NAME AUTHOR ALBUM
  read -r -p "  Nome   [$YT_TITLE]: " NAME;     NAME="${NAME:-$YT_TITLE}"
  read -r -p "  Autor  [$YT_UPLOADER]: " AUTHOR; AUTHOR="${AUTHOR:-$YT_UPLOADER}"
  read -r -p "  Álbum  []: " ALBUM

  local entry
  entry=$(printf '    {\n        file      = "%s/%s.mp3",\n        name      = "%s",\n        author    = "%s",\n        album     = "%s",\n        thumbnail = "%s",\n    },' \
    "$REL_DIR" "$name" "$(printf '%s' "$NAME" | lua_escape)" "$(printf '%s' "$AUTHOR" | lua_escape)" \
    "$(printf '%s' "$ALBUM" | lua_escape)" "$THUMB")

  local tmp; tmp=$(mktemp)
  ENTRY="$entry" awk '
    { lines[NR]=$0 }
    /^SherlockHNS\.LMS\.Playlist[ \t]*=[ \t]*\{[ \t]*$/ { st=NR }
    st && !cl && NR>st && /^\}[ \t]*$/ { cl=NR }
    END {
      if (!cl) exit 2
      for (i=1;i<=NR;i++) { if (i==cl) print ENVIRON["ENTRY"]; print lines[i] }
    }' "$PLAYLIST" >"$tmp" || { rm -f "$tmp"; die "não achei o fim de SherlockHNS.LMS.Playlist em ${PLAYLIST#$ROOT/}."; }
  mv "$tmp" "$PLAYLIST"

  echo
  ok "Adicionada à playlist: ${PLAYLIST#$ROOT/}"
  echo "  Teste no servidor:  hns_lms_test \"$NAME\""
  echo "  Arquivo publicado em: $LMS_DIR"
  echo "  O caminho relativo no GMod continua sendo: $REL_DIR/$name.mp3"
  echo "  Publique a atualização do addon para distribuir a faixa pela Workshop."
}

# ---------------------------------------------------------------- list
cmd_list() {
  [ -f "$PLAYLIST" ] || die "playlist não encontrada."
  awk '
    /file[ \t]*=/   { gsub(/.*file[ \t]*=[ \t]*"|",?[ \t]*$/, ""); f=$0 }
    /name[ \t]*=/   { gsub(/.*name[ \t]*=[ \t]*"|",?[ \t]*$/, ""); n=$0 }
    /author[ \t]*=/ { gsub(/.*author[ \t]*=[ \t]*"|",?[ \t]*$/, ""); a=$0; i++; printf "%2d. %s — %s\n      %s\n", i, n, a, f }
  ' "$PLAYLIST"
}

# ---------------------------------------------------------------- verify
cmd_verify() {
  need ffmpeg jq awk
  [ -f "$PLAYLIST" ] || die "playlist não encontrada."
  local bad=0 f path base hash want got dev

  step "Faixas da playlist"
  while IFS= read -r f; do
    path="$CONTENT_ROOT/sound/$f"
    if [ ! -f "$path" ]; then printf '  %s✗%s falta o arquivo: %s\n' "$C_RED" "$C_OFF" "$f"; bad=1; continue; fi

    base=$(basename "$f" .mp3); want="${base##*_}"; got=$(sha8 "$path")
    if [ "$want" != "$got" ]; then
      printf '  %s✗%s %s: hash do nome (%s) ≠ conteúdo (%s). O arquivo foi alterado após publicar!\n' "$C_RED" "$C_OFF" "$base" "$want" "$got"
      bad=1; continue
    fi

    got=$(measure "$path" | jq -r '.input_i')
    dev=$(awk -v a="$got" -v b="$LUFS" 'BEGIN{d=a-b; if(d<0)d=-d; print d}')
    if awk -v d="$dev" -v t="$TOLERANCE" 'BEGIN{exit !(d>t)}'; then
      printf '  %s✗%s %s: %s LUFS (alvo %s)\n' "$C_RED" "$C_OFF" "$base" "$got" "$LUFS"; bad=1
    else
      ok "$base  ${got} LUFS"
    fi
  done < <(grep -oE 'file[[:space:]]*=[[:space:]]*"[^"]+"' "$PLAYLIST" | sed -E 's/.*"([^"]+)"/\1/')

  step "Arquivos fora da playlist"
  local found=0
  if [ -d "$LMS_DIR" ]; then
    for path in "$LMS_DIR"/*.mp3; do
      [ -e "$path" ] || continue
      if ! grep -Fq "\"$REL_DIR/$(basename "$path")\"" "$PLAYLIST"; then
        warn "órfão: ${path#$CONTENT_ROOT/}"; found=1
      fi
    done
  fi
  [ "$found" = 0 ] && ok "nenhum"

  [ "$bad" = 0 ] || die "verificação com problemas."
  echo; ok "tudo certo."
}

case "${1:-}" in
  add)    shift; cmd_add "${1:-}" ;;
  list)   cmd_list ;;
  verify) cmd_verify ;;
  *)      sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
