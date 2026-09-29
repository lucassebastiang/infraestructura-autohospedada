#!/usr/bin/env bash
# Informe semanal del anfitrión Proxmox por Telegram (estructura de ejemplo).
#
# Lo lanza un timer de systemd (OnCalendar semanal, Persistent=true, RandomizedDelaySec).
# Solo LEE: simula actualizaciones, no instala nada.
#
# Primera línea = icono de estado:
#   🔴 pool no sano · alguna copia con error · ninguna copia en 7 días · copia de configuración
#      fallida o sin ejecutarse en 36 h
#   ⚠️ reinicio pendiente · actualizaciones de seguridad · unidades fallidas · contenedor parado
#   ✅ lo demás
#
# SIN_ENVIO=1 imprime el texto sin enviarlo.
set -euo pipefail

CONFIG_SECRETOS="<RUTA_FICHERO_CON_TOKEN_Y_CHAT>"   # legible solo por root
TAG="informe-semanal"

log() { logger -t "$TAG" -- "$*"; }

rojo=0; aviso=0
lineas=()
add() { lineas+=("$1"); }

# --- Comprobaciones -----------------------------------------------------------------------------

add "Encendido: $(uptime -p)"
add "Kernel: $(uname -r)"

apt-get update -qq >/dev/null 2>&1 || { aviso=1; add "apt-get update ha fallado"; }
pendientes=$(apt-get -s dist-upgrade | grep -c '^Inst ' || true)
seguridad=$(apt-get -s dist-upgrade | grep '^Inst ' | grep -ci 'security' || true)
add "Actualizaciones: $pendientes (de seguridad: $seguridad)"
(( seguridad > 0 )) && aviso=1

if [[ -f /var/run/reboot-required ]]; then aviso=1; add "Reinicio pendiente"; fi

estado_zfs=$(zpool status -x)
[[ "$estado_zfs" == "all pools are healthy" ]] || { rojo=1; add "ZFS: $estado_zfs"; }

add "Disco /: $(df -h / --output=pcent | tail -1 | tr -d ' ')"

fallidas=$(systemctl --failed --no-legend --plain | awk '{print $1}' | paste -sd, -)
[[ -n "$fallidas" ]] && { aviso=1; add "Unidades fallidas: $fallidas"; }

# Copias de los últimos 7 días. OJO: pvesh devuelve 50 tareas por defecto; con varios trabajos
# diarios hay más a la semana y el recuento saldría corto sin avisar.
desde=$(date -d '7 days ago' +%s)
tareas=$(pvesh get /nodes/"$(hostname)"/tasks --typefilter vzdump --since "$desde" \
          --limit 10000 --output-format json)
total=$(jq 'length' <<<"$tareas")
errores=$(jq '[.[] | select(.status != "OK" and (.status | test("WARNINGS") | not))] | length' <<<"$tareas")
avisos=$(jq '[.[] | select(.status | test("WARNINGS"))] | length' <<<"$tareas")
add "Copias 7 días: $total (errores: $errores, avisos: $avisos)"
(( total == 0 || errores > 0 )) && rojo=1
(( avisos > 0 )) && aviso=1

# Un oneshot que no ha corrido desde el arranque sale Result=success: se mira también la fecha.
ultima=$(systemctl show copia-configuracion.service -p ExecMainExitTimestamp --value)
resultado=$(systemctl show copia-configuracion.service -p Result --value)
if [[ "$resultado" != "success" || -z "$ultima" ]] \
   || (( $(date +%s) - $(date -d "$ultima" +%s) > 36*3600 )); then
  rojo=1; add "Copia de configuración: fallida o sin ejecutarse en 36 h"
fi

parados=$(pct list | awk 'NR>1 && $2!="running" {print $1}' | paste -sd, -)
[[ -n "$parados" ]] && { aviso=1; add "Contenedores parados: $parados"; }

# --- Mensaje ------------------------------------------------------------------------------------

if (( rojo )); then icono="🔴"; elif (( aviso )); then icono="⚠️"; else icono="✅"; fi
texto="$icono Informe semanal · $(hostname -s)"$'\n'"$(printf '%s\n' "${lineas[@]}")"

if [[ "${SIN_ENVIO:-0}" == "1" ]]; then printf '%s\n' "$texto"; exit 0; fi

# --- Envío --------------------------------------------------------------------------------------
# Token y chat se leen AHORA y llegan a curl por stdin (-K -): no aparecen en `ps`, ni en el log,
# ni en disco.
# leer_secreto: adapta a tu formato (en Proxmox, p. ej., el webhook de notificaciones en base64).
leer_secreto() { awk -v k="$1" -F' *= *' '$1==k {print $2}' "$CONFIG_SECRETOS"; }
token=$(leer_secreto token)
chat=$(leer_secreto chat_id)

for intento in 1 2 3; do
  if printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token" \
     | curl -4 -sS --fail --max-time 20 -K - \
            --data-urlencode "chat_id=$chat" --data-urlencode "text=$texto" >/dev/null; then
    log "enviado (intento $intento)"
    exit 0
  fi
  log "fallo de envío (intento $intento)"
  sleep 10
done

log "ERROR: no se pudo enviar tras 3 intentos"
exit 1   # la unidad queda en «failed» y el informe siguiente lo contará
