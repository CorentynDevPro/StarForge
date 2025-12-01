#!/usr/bin/env bash
set -eu

# get_hero_profile.sh
# Usage:
#   ./get_hero_profile.sh          -> interactive : demande l'Invite/NameCode
#   ./get_hero_profile.sh --login  -> interactive : demande username puis password
#
# Note: ne commite jamais ce script avec des identifiants en clair.

OUTDIR="./gotest_outputs"
mkdir -p "$OUTDIR"

URL="https://pcmob.parse.gemsofwar.com/call_function"
CLIENT_VER="8.9.0"

# Envoie une requête POST et sauvegarde headers+body
do_request() {
  local payload="$1"
  local out="$2"
  local hdr="$3"

  httpcode=$(curl -s -D "$hdr" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "User-Agent: Mozilla/5.0 (Macintosh) curl" \
    -H "Origin: https://pcmob.parse.gemsofwar.com" \
    -X POST -d "$payload" \
    "$URL" -o "$out" -w "%{http_code}")
  echo "$httpcode"
}

pretty_print() {
  local f="$1"
  if command -v jq >/dev/null 2>&1; then
    jq . "$f" || cat "$f"
  else
    echo "(Installer jq pour afficher proprement : brew install jq)"
    cat "$f"
  fi
}

fetch_by_namecode() {
  local nc="$1"
  nc="$(echo -n "$nc" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [ -z "$nc" ]; then
    echo "NameCode vide. Abandon."
    return 1
  fi

  safe="$(echo "$nc" | sed -E 's/[^A-Za-z0-9_.-]/_/g')"
  out="$OUTDIR/get_hero_profile_${safe}.json"
  hdr="$OUTDIR/get_hero_profile_${safe}.http"

  payload=$(printf '{"functionName":"get_hero_profile","clientVersion":"%s","NameCode":"%s"}' "$CLIENT_VER" "$nc")
  echo "Récupération du profil pour NameCode=$nc ..."
  http=$(do_request "$payload" "$out" "$hdr")
  echo "HTTP: $http"
  echo "Body: $out"
  echo "Headers: $hdr"
  echo
  pretty_print "$out"
  return 0
}

do_login_and_fetch() {
  local user="$1"
  local pass="$2"
  user="$(echo -n "$user" | tr -d '\r\n')"

  safe="$(echo "$user" | sed -E 's/[^A-Za-z0-9_.-]/_/g')"
  login_out="$OUTDIR/login_user_${safe}.json"
  login_hdr="$OUTDIR/login_user_${safe}.http"

  payload=$(printf '{"functionName":"login_user","username":"%s","password":"%s","clientVersion":"%s"}' \
    "$user" "$pass" "$CLIENT_VER")

  echo "Tentative de connexion pour username=$user ..."
  http=$(do_request "$payload" "$login_out" "$login_hdr")
  echo "HTTP: $http"
  echo "Login body: $login_out"
  echo "Login headers: $login_hdr"
  echo
  pretty_print "$login_out"
  echo

  # Essayer d'extraire un NameCode depuis la réponse si jq est disponible
  if command -v jq >/dev/null 2>&1; then
    namecode=$(jq -r '.result.NameCode // .result.nameCode // .result.InviteCode // .result.inviteCode // .result.username // .result.user.NameCode // empty' "$login_out" 2>/dev/null || true)
    if [ -n "$namecode" ]; then
      echo "NameCode détecté dans la réponse de login: $namecode"
      echo
      fetch_by_namecode "$namecode"
      return 0
    fi
  else
    echo "jq non trouvé : impossible d'extraire automatiquement le NameCode depuis la réponse de login."
    echo "Ouvre $login_out et cherche le NameCode/InviteCode manuellement."
    return 1
  fi

  echo "Aucun NameCode détecté automatiquement dans la réponse de login."
  echo "Ouvre $login_out pour inspecter la réponse (ou utilise --invite)."
  return 1
}

print_usage() {
  cat <<EOF
Usage:
  $0               -> demande l'Invite/NameCode
  $0 --login       -> demande username puis password (prompt interactif)
  $0 --help
EOF
}

# Arguments
if [ "${1-}" = "--help" ] || [ "${1-}" = "-h" ]; then
  print_usage
  exit 0
fi

if [ "${1-}" = "--login" ]; then
  # Prompt username/password
  read -r -p "Username: " USERNAME
  # password en mode silencieux
  read -r -s -p "Password: " PASSWORD
  echo
  if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "Username ou password vide. Abandon."
    exit 1
  fi
  do_login_and_fetch "$USERNAME" "$PASSWORD"
  exit $?
fi

# Par défaut (sans option) : demander l'invite code / NameCode
read -r -p "Enter Invite/NameCode: " INV
if [ -z "$INV" ]; then
  echo "Aucun code fourni. Abandon."
  exit 1
fi
fetch_by_namecode "$INV"
