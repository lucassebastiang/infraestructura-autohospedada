# Prueba de restauración completa de un contenedor

Objetivo: demostrar que una copia remota **se puede restaurar entera** y el servicio de dentro funciona, **sin ningún riesgo para producción**.

## Antes de empezar

- Elige un **identificador fuera del rango de producción**. Si tienes uno reservado para provocar fallos de copia a propósito, no uses ese.
- Comprueba el espacio libre en el pool: la restauración ocupa lo mismo que el original.

## Restaurar

```bash
pct restore <ID_PRUEBA> <almacen-pbs>:backup/ct/<ID_ORIGEN>/<FECHA> --storage <pool>
```

## ⚠️ Antes del primer arranque

Un clon restaurado trae **la misma IP, la misma MAC y el arranque automático** del original. Si lo arrancas sin más, choca con el contenedor en producción. Y si el servicio restaurado manda alertas (una monitorización, por ejemplo), empezará a enviarlas **indistinguibles de las reales**.

```bash
pct set <ID_PRUEBA> --delete net0     # sin red: no puede hablar con nadie
pct set <ID_PRUEBA> --onboot 0        # no vuelve solo en el próximo reinicio
pct start <ID_PRUEBA>
```

Arrancarlo **sin red**, y no con otra IP, es a propósito: con cualquier ruta hacia fuera podría empezar a actuar como el original.

## Qué comprobar (y por qué)

Desde dentro del contenedor, contra `127.0.0.1`:

| Comprobación | Demuestra |
|---|---|
| La página de inicio no redirige al asistente de instalación | La base de datos ha venido entera |
| Un endpoint de la API devuelve JSON válido | La aplicación responde, no solo el puerto |
| Un recurso que identifica al producto | Es la aplicación esperada y no otra cosa escuchando |
| Un endpoint protegido devuelve 401 | La autenticación está configurada |
| `docker ps` → contenedores `healthy` con la misma imagen | El stack arranca como el original |
| **Filas por tabla, original frente a restaurado** | No falta nada |
| **SHA-256 de los ficheros de configuración** | Son idénticos |

## Limpiar y comprobar que no queda nada

```bash
pct stop <ID_PRUEBA>
pct destroy <ID_PRUEBA> --purge
```

Después verifica que no quedan dataset ZFS, punto de montaje, fichero de configuración, snapshots huérfanos ni referencias en trabajos de copia, cortafuegos o replicación, y que el pool ha recuperado el espacio. Comprueba también que el contenedor original sigue corriendo con su red intacta.

## Anótalo

Fecha, copia usada, tiempo de restauración, velocidad y resultado de cada comprobación, en el registro de cambios. **Una copia que no se ha restaurado es una hipótesis.**
