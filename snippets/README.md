# Ejemplos genéricos

Escritos para ilustrar las ideas del caso de estudio. **Todos los valores son de ejemplo** (`<...>`, `example.com`). No son la configuración real del servidor, y tienes que revisarlos antes de usarlos en el tuyo.

| Fichero | Qué muestra |
|---|---|
| [docker-compose.yml](docker-compose.yml) | Stack tipo: app + PostgreSQL + MinIO, con red interna sin salida, red de salida, healthchecks y secretos como ficheros |
| [informe-semanal.sh](informe-semanal.sh) | Estructura del informe semanal por Telegram: comprobaciones, icono de estado, envío con reintentos y sin exponer el token |
| [copia-configuracion.sh](copia-configuracion.sh) | Copia de la configuración del anfitrión a un Proxmox Backup Server, cifrada en el cliente y avisando si falla |
| [prueba-restauracion.md](prueba-restauracion.md) | Lista de pasos para restaurar un contenedor entero sin riesgo para producción |
| [actualizaciones-seguridad.conf](actualizaciones-seguridad.conf) | `unattended-upgrades` limitado de verdad a las actualizaciones de seguridad |
