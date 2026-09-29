#!/usr/bin/env bash
# Copia de la configuración del anfitrión Proxmox a un Proxmox Backup Server remoto,
# CIFRADA EN EL CLIENTE (ejemplo).
#
# - El PBS guarda datos que no puede leer. Sin la clave no hay recuperación: la clave debe tener
#   una copia fuera del servidor (gestor de contraseñas). La copia que viaja dentro de /etc NO
#   cuenta, porque está cifrada con ella misma.
# - A diferencia de un `tar ... 2>/dev/null || true`, este script NO silencia errores: si falla,
#   avisa y sale con error.
# - Lo lanza un timer diario, después de las copias de los contenedores y antes de la poda del PBS.
set -euo pipefail

export PBS_REPOSITORY="<usuario>@pbs!<token>@<pbs.example.com>:<datastore>"
export PBS_PASSWORD_FILE="<RUTA_SECRETO_TOKEN>"      # 600, root
export PBS_FINGERPRINT="<HUELLA_CERTIFICADO_PBS>"    # fijada, verificada antes del alta
CLAVE="<RUTA_CLAVE_CIFRADO>"                          # 600, root
NAMESPACE="<namespace>"
TAG="copia-configuracion"

avisar() { "<RUTA>/avisar-telegram.sh" "🔴 Copia de configuración: $1" || true; }
trap 'avisar "falló en la línea $LINENO"; logger -t "$TAG" "ERROR línea $LINENO"; exit 1' ERR

trabajo=$(mktemp -d)
trap 'rm -rf "$trabajo"' EXIT

# El estado del hardware y del almacenamiento no vive en ningún fichero de /etc: se vuelca.
{
  echo "## pveversion";   pveversion -v
  echo "## discos";       lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
  echo "## zpool";        zpool status
  echo "## zfs";          zfs list -o name,used,avail,refquota
  echo "## raid";         cat /proc/mdstat
  echo "## almacenes";    pvesm status
} > "$trabajo/sistema.conf"

# /etc/pve es un montaje FUSE aparte: sin --include-dev NO entraría en la copia.
proxmox-backup-client backup \
  etc.pxar:/etc \
  scripts.pxar:/usr/local/bin \
  documentacion.pxar:"<RUTA_DOCUMENTACION_OPERACION>" \
  sistema.conf:"$trabajo/sistema.conf" \
  --include-dev /etc/pve \
  --keyfile "$CLAVE" \
  --crypt-mode encrypt \
  --ns "$NAMESPACE" \
  --backup-type host \
  --backup-id "$(hostname -s)-config"

logger -t "$TAG" "copia completada"

# Probar las DOS ramas antes de darlo por bueno: éxito real (varias veces) y fallo provocado
# (red caída, clave ausente), comprobando que el aviso LLEGA al móvil, no solo que se envía.
