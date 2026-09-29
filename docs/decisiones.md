# Registro de decisiones

Cada entrada tiene la decisión, el porqué y la alternativa descartada.

---

### 1. Proxmox VE sobre un servidor dedicado
**Decisión:** un único servidor dedicado en un proveedor europeo, con Proxmox VE como hipervisor.
**Porqué:** los datos se quedan en la UE y bajo control propio, a coste fijo. Proxmox integra contenedores, VMs, snapshots, copias, cortafuegos y API en una sola herramienta libre.
**Descartado:** un PaaS o SaaS por aplicación (dependencia, coste por usuario y datos fuera de control) y Kubernetes (demasiada complejidad operativa para una sola persona y pocas aplicaciones).

### 2. Contenedores LXC en lugar de máquinas virtuales
**Decisión:** cada carga en un contenedor LXC **no privilegiado**, con el anidamiento activado para poder ejecutar Docker dentro.
**Porqué:** casi sin sobrecoste de RAM y CPU, arranque en segundos y copias y snapshots nativos de Proxmox. Todas las cargas son Linux.
**Descartado:** una VM por aplicación, porque multiplica la memoria reservada y los kernels a mantener sin aportar un aislamiento que haga falta aquí.

### 3. Un stack de Docker Compose por contenedor
**Decisión:** cada aplicación tiene su propio LXC y su propio Compose, con su base de datos y su almacenamiento.
**Porqué:** se puede copiar, restaurar, actualizar o revertir una aplicación sin tocar las demás. El radio de impacto de un fallo es un contenedor.
**Descartado:** un único host Docker con todas las aplicaciones (un `docker compose down` equivocado o una actualización de Docker afecta a todo) y una base de datos compartida.

### 4. ZFS en espejo para los datos y RAID1 para el sistema
**Decisión:** el sistema en RAID1 por software y los datos de los contenedores en un pool ZFS en espejo, con compresión y la ARC limitada.
**Porqué:** sobrevive a la pérdida de un disco, detecta corrupción silenciosa con *scrub* periódico, hace snapshots instantáneos y comprime a bajo coste. Con la ARC limitada, ZFS no se come la memoria de los contenedores.
**Descartado:** ZFS también para el sistema (se prefirió no complicar el arranque en el hardware del proveedor) y LVM-thin para los datos (sin checksums ni *scrub*).

### 5. Solo HTTP/HTTPS públicos; administración solo por VPN
**Decisión:** desde internet solo se llega al proxy inverso. El panel de Proxmox, SSH y los paneles de administración solo son accesibles por VPN, con una lista de dispositivos autorizados.
**Porqué:** la superficie de ataque se reduce a un servicio muy expuesto y bien mantenido. Sin VPN no hay nada que probar.
**Descartado:** SSH público con claves y fail2ban como única defensa, y bastión expuesto.

### 6. Un proxy inverso único con certificados automáticos
**Decisión:** Nginx Proxy Manager en su propio contenedor, con Let's Encrypt, HTTP/2, HSTS y bloqueo de exploits comunes.
**Porqué:** renovación automática de certificados y un único punto de entrada auditable. La configuración se revisa desde un panel accesible solo por VPN.
**Descartado:** un proxy dentro de cada aplicación (certificados duplicados y más superficie) y Traefik con etiquetas (acopla el proxy a Docker de cada contenedor).
**Matiz:** en la aplicación migrada se dejó HSTS sin `preload` durante la transición, para no bloquear una posible vuelta al servidor anterior.

### 7. Dos redes Docker por aplicación: interna y de salida
**Decisión:** la base de datos y el almacenamiento de objetos solo están en una red `internal: true`. La aplicación está además en una red de salida para SMTP y webhooks.
**Porqué:** aunque se comprometa la aplicación, la base de datos no tiene ruta a internet. Y quitar la red de salida rompe el correo (y con él el segundo factor de acceso), así que queda documentado por qué existe.
**Descartado:** una sola red bridge para todo el stack.

### 8. Almacenamiento de objetos sin exponer
**Decisión:** MinIO sin puertos publicados ni dominio. Los ficheros se sirven a través de la aplicación después de validar la sesión.
**Porqué:** un bucket mal configurado es una fuga clásica. Si no se puede llegar a él, no puede estar mal configurado hacia fuera.
**Descartado:** URLs prefirmadas con un dominio público para el almacenamiento.

### 9. Copias en tres capas, con la remota como dueña de la retención
**Decisión:**
1. snapshots ZFS automáticos (horarios y diarios);
2. copias diarias de cada contenedor en local, escalonadas para no competir;
3. copias al **Proxmox Backup Server remoto**, con poda, recolección de basura y verificación periódicas **definidas en el PBS**.

La aplicación crítica tiene además una copia horaria y archivado continuo de la base de datos.

**Porqué:** un snapshot en el mismo pool no protege de perder el pool, y una copia local no protege de perder el servidor. Si la retención se define también desde el hipervisor, los dos mecanismos compiten: el PBS es el dueño y el hipervisor solo empuja.
**Descartado:** solo snapshots (fue el estado inicial de algunos contenedores y se corrigió) y copias remotas sin verificación.

### 10. Cifrado en el cliente para lo sensible
**Decisión:** la configuración del hipervisor y la aplicación de datos más sensibles se copian **cifradas en el cliente**. La clave está en un gestor de contraseñas.
**Porqué:** el servidor de copias guarda bloques que no puede leer. Se asume el coste: **sin la clave no hay recuperación**, y la clave está dentro de lo que protege, así que esa copia no cuenta como copia de la clave.
**Descartado:** cifrar todo (complica la operación de copias que no lo necesitan) y confiar solo en el cifrado del disco del servidor remoto.

### 11. El servidor también es destino de copias de otra sede, sin poder leerlas
**Decisión:** recibe una réplica ZFS **cifrada de forma nativa** desde otra ubicación, con cuota, sin punto de montaje y con la clave fuera del servidor.
**Porqué:** copia cruzada entre sedes sin que ninguna pueda leer los datos de la otra. Contiene datos personales especialmente sensibles.
**Descartado:** réplica en claro o con la clave en ambos extremos.

### 12. Restauraciones de prueba completas
**Decisión:** validar las copias restaurando un contenedor entero desde el PBS remoto:
1. con un identificador fuera del rango de producción;
2. **sin red y sin arranque automático** (un clon trae la misma IP, la misma MAC y alertas activas);
3. comprobando el servicio por dentro, filas por tabla y hashes de ficheros;
4. destruyéndolo después y comprobando que no quedan restos.

**Porqué:** una copia que no se ha restaurado es una hipótesis.
**Descartado:** restaurar ficheros sueltos como prueba suficiente.

### 13. Versiones fijadas de todo
**Decisión:** imágenes y paquetes con versión explícita, sin `latest`.
**Porqué:** una actualización es un cambio con fecha, motivo y vuelta atrás. En una de las herramientas, `latest` apuntaba a una línea mayor antigua: habría instalado una versión inesperada.
**Descartado:** `latest` con actualizaciones automáticas de imágenes.

### 14. Actualizaciones automáticas solo de seguridad
**Decisión:** `unattended-upgrades` limitado al repositorio de seguridad de Debian, sin reinicios automáticos. El resto (Proxmox, kernel, herramientas) se actualiza a mano, en una ventana sin uso, con inventario previo y comprobación posterior.
**Porqué:** los parches de seguridad no esperan, y una actualización de hipervisor sí merece estar delante.
**Descartado:** todo automático (llegó a pasar por la configuración por defecto: APT suma las listas de orígenes de todos los ficheros) y todo manual.

### 15. Informe semanal por Telegram
**Decisión:** un timer de systemd genera cada semana un resumen: disponibilidad, actualizaciones pendientes, reinicio requerido, estado del pool, disco, unidades fallidas, copias de los últimos siete días y contenedores parados. La primera línea es un icono (🔴 ⚠️ ✅). Los secretos se leen en tiempo de ejecución y se pasan a `curl` por la entrada estándar, nunca como argumento. Hay reintentos y, si fallan todos, la unidad queda en error y el informe siguiente lo cuenta.
**Porqué:** la información llega sin tener que ir a buscarla, y el icono se entiende en un segundo.
**Descartado:** un panel web (nadie lo mira) y correo (se pierde entre el resto).

### 16. Alertas probadas en las dos ramas, sin tocar producción
**Decisión:** cada alerta se prueba en éxito y en fallo, varias veces, y solo se da por buena cuando alguien confirma que ha llegado al destino real. Para provocar el fallo se usa un monitor contra una dirección inexistente o un trabajo de copia desechable. **Nunca se para un servicio real.**
**Porqué:** un fallo intermitente hace que un único acierto engañe, y parar producción para probar es el riesgo que se quiere evitar.
**Descartado:** probar una vez y dar por bueno el «enviado».

### 17. Preferir IPv4 en el anfitrión
**Decisión:** la resolución de nombres del anfitrión prefiere IPv4 cuando hay ambas direcciones.
**Porqué:** algunas rutas IPv6 fallaban a nivel TCP/TLS de forma intermitente, y el cliente de notificaciones no reintentaba por IPv4: los avisos se perdían al azar.
**Descartado:** desactivar IPv6 por completo.

### 18. Asistente de IA con reglas escritas y privilegios temporales
**Decisión:** la administración se hace con Claude Code, con un fichero de reglas que carga en cada sesión, `sudo` con contraseña y permisos elevados **temporales y limitados a comandos concretos**, que se retiran al terminar y se comprueba que ya no funcionan.
**Porqué:** permite delegar el trabajo repetitivo y la documentación sin dar un acceso permanente e ilimitado.
**Descartado:** `sudo` sin contraseña permanente (era el estado inicial del sistema y se retiró) y no usar asistente.

### 19. Documentación viva en el propio servidor
**Decisión:** inventario, registro de cambios, pendientes y *runbooks* en el servidor. Se incluyen en la copia cifrada nocturna.
**Porqué:** el conocimiento de operación sobrevive a la pérdida del disco del sistema y a un cambio de persona o de sesión.
**Descartado:** documentación solo en el portátil del administrador.

### 20. Migraciones con ensayo general y verificación objetiva
**Decisión:** antes de cada corte se hace un ensayo completo con el origen todavía en marcha. En el corte se congela el origen, se copian los datos y se verifica **antes de cambiar el DNS**: número exacto de filas por tabla, hashes de ficheros tras pasar por la API S3, migraciones con sus fechas originales y firmas electrónicas válidas.
**Porqué:** los problemas aparecieron en el ensayo, no en la ventana de corte. Hasta el cambio de DNS, todo es reversible sin coste.
**Descartado:** migrar en caliente sin ensayo y verificar «que la web carga».
