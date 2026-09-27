#!/bin/bash

# Backend do plugin thecraftlab.daily-notes (Omarchy shell).
#
# Uso:
#   daily-notes.sh [opções] list
#   daily-notes.sh [opções] new [nome]
#   daily-notes.sh [opções] open <nome>
#   daily-notes.sh [opções] rename <de> <para>
#   daily-notes.sh [opções] delete <nome>
#   daily-notes.sh [opções] dir
#
# Opções:
#   --dir <pasta>        pasta das notas        (padrão: ~/Documents/daily)
#   --app-id <id>        app-id da janela do editor (padrão: TUI.float, que o
#                        Omarchy já abre flutuante e centralizado)
#   --nvim-appname <n>   NVIM_APPNAME usado pelo editor (padrão: nvim-daily)
#
# `list` imprime uma nota por linha: nome<TAB>mtime-epoch<TAB>bytes, da mais
# recente para a mais antiga. As demais ações imprimem o nome final do arquivo.

set -euo pipefail

NOTES_DIR="${DAILY_NOTES_DIR:-$HOME/Documents/daily}"
NVIM_APP="${DAILY_NOTES_NVIM_APPNAME:-nvim-daily}"
APP_ID="${DAILY_NOTES_APP_ID:-TUI.float}"

fail() {
  echo "daily-notes: $*" >&2
  exit 1
}

while [[ ${1:-} == --* ]]; do
  case "$1" in
    --dir)
      [[ -n ${2:-} ]] || fail "--dir precisa de uma pasta"
      NOTES_DIR="${2/#\~/$HOME}"
      shift 2
      ;;
    --app-id)
      [[ -n ${2:-} ]] || fail "--app-id precisa de um valor"
      APP_ID="$2"
      shift 2
      ;;
    --nvim-appname)
      [[ -n ${2:-} ]] || fail "--nvim-appname precisa de um valor"
      NVIM_APP="$2"
      shift 2
      ;;
    *) fail "opção desconhecida: $1" ;;
  esac
done

mkdir -p "$NOTES_DIR"

# Normaliza um nome digitado pelo usuário para "<nome>.md" seguro.
sanitize() {
  local name="$1"
  name="${name%.md}"
  name="${name//\//-}"
  name="$(printf '%s' "$name" | sed 's/^[[:space:].]*//; s/[[:space:]]*$//')"
  [[ -n $name ]] || fail "nome vazio"
  [[ $name != *".."* ]] || fail "nome inválido: $1"
  printf '%s.md' "$name"
}

cmd_list() {
  find "$NOTES_DIR" -maxdepth 1 -type f -name '*.md' -printf '%f\t%T@\t%s\n' \
    | sort -t $'\t' -k2,2nr
}

cmd_open() {
  local file
  file="$(sanitize "${1:?nome obrigatório}")"
  [[ -f "$NOTES_DIR/$file" ]] || fail "nota não encontrada: $file"
  echo "$file"
  # Terminal padrão do sistema com o app-id escolhido (TUI.float já é flutuante
  # no Omarchy; um id dedicado permite regras próprias em ~/.config/hypr) e um
  # Neovim com config separada via NVIM_APPNAME.
  bootstrap_nvim_config
  setsid uwsm-app -- xdg-terminal-exec \
    --app-id="$APP_ID" \
    --title="Daily · ${file%.md}" \
    -- env NVIM_APPNAME="${NVIM_APP:-nvim}" nvim "$NOTES_DIR/$file" >/dev/null 2>&1 &
}

# Na primeira vez, se a config do NVIM_APPNAME escolhido ainda não existir,
# copia a config inicial que vem com o plugin. Nunca toca em uma config existente.
bootstrap_nvim_config() {
  [[ -n $NVIM_APP && $NVIM_APP != "nvim" ]] || return 0
  local target="${XDG_CONFIG_HOME:-$HOME/.config}/$NVIM_APP"
  [[ ! -e $target ]] || return 0
  local template
  template="$(dirname "$(readlink -f "$0")")/nvim"
  [[ -f "$template/init.lua" ]] || return 0
  mkdir -p "$target"
  cp -n "$template/init.lua" "$target/init.lua"
}

cmd_new() {
  local base="${1:-$(date +%F)}"
  local file stem n=2
  file="$(sanitize "$base")"
  stem="${file%.md}"
  while [[ -e "$NOTES_DIR/$file" ]]; do
    file="$stem-$n.md"
    ((n++))
  done
  printf '# %s\n\n' "$stem" >"$NOTES_DIR/$file"
  cmd_open "$file"
}

cmd_rename() {
  local from to
  from="$(sanitize "${1:?origem obrigatória}")"
  to="$(sanitize "${2:?destino obrigatório}")"
  [[ -f "$NOTES_DIR/$from" ]] || fail "nota não encontrada: $from"
  if [[ $from == "$to" ]]; then
    echo "$to"
    exit 0
  fi
  [[ ! -e "$NOTES_DIR/$to" ]] || fail "já existe uma nota chamada ${to%.md}"
  mv -n "$NOTES_DIR/$from" "$NOTES_DIR/$to"
  echo "$to"
}

cmd_delete() {
  local file
  file="$(sanitize "${1:?nome obrigatório}")"
  [[ -f "$NOTES_DIR/$file" ]] || fail "nota não encontrada: $file"
  # Lixeira quando disponível; rm como último recurso.
  if command -v gio >/dev/null 2>&1 && gio trash "$NOTES_DIR/$file" 2>/dev/null; then
    :
  else
    rm -f -- "$NOTES_DIR/$file"
  fi
  echo "$file"
}

case "${1:-}" in
  list) cmd_list ;;
  new) cmd_new "${2:-}" ;;
  open) cmd_open "${2:-}" ;;
  rename) cmd_rename "${2:-}" "${3:-}" ;;
  delete) cmd_delete "${2:-}" ;;
  dir) echo "$NOTES_DIR" ;;
  *) fail "uso: daily-notes.sh [--dir <pasta>] [--app-id <id>] [--nvim-appname <n>] list|new|open|rename|delete|dir" ;;
esac
