# JENKINS-MAINTENANCE-SCRIPT

Script completo de mantenimiento para Jenkins que automatiza tareas críticas de mantenimiento del servidor.

## 📋 Descripción

Este script proporciona una solución integral para el mantenimiento de servidores Jenkins, incluyendo:

- ✅ **Verificación del estado del sistema**: Comprueba espacio en disco, memoria y estado del servicio
- 🛑 **Detención segura de Jenkins**: Para el servicio de forma controlada
- 💾 **Backup automático de configuraciones**: Respalda configuraciones críticas, jobs, plugins y credenciales
- 🧹 **Limpieza de archivos temporales y cache**: Elimina archivos innecesarios para liberar espacio
- 🔄 **Reinicio y verificación del servicio**: Reinicia Jenkins y verifica que funcione correctamente
- 📦 **Gestión de backups**: Mantiene solo el backup más reciente para ahorrar espacio

## 🚀 Instalación

1. Clonar el repositorio:
```bash
git clone https://github.com/rmunate/JENKINS-MAINTENANCE-SCRIPT.git
cd JENKINS-MAINTENANCE-SCRIPT
```

2. Hacer el script ejecutable:
```bash
chmod +x jenkins_maintenance.sh
```

3. (Opcional) Personalizar la configuración:
```bash
nano jenkins_maintenance.conf
```

## 📖 Uso

### Ejecución básica

El script debe ejecutarse con privilegios de root o sudo:

```bash
sudo ./jenkins_maintenance.sh
```

### Personalización con variables de entorno

Puedes personalizar el comportamiento del script usando variables de entorno:

```bash
sudo JENKINS_HOME=/opt/jenkins BACKUP_DIR=/backup/jenkins ./jenkins_maintenance.sh
```

### Variables de entorno disponibles

- `JENKINS_HOME`: Ruta del directorio home de Jenkins (default: `/var/lib/jenkins`)
- `BACKUP_DIR`: Directorio donde se almacenarán los backups (default: `/var/backups/jenkins`)
- `JENKINS_SERVICE`: Nombre del servicio Jenkins (default: `jenkins`)

## 📝 Funcionalidades Detalladas

### 1. Verificación del Estado del Sistema

- Verifica el espacio disponible en disco
- Muestra el uso de memoria del sistema
- Comprueba si Jenkins está en ejecución
- Alerta si el espacio en disco es inferior al 10%

### 2. Detención Segura de Jenkins

- Para el servicio Jenkins de forma controlada
- Espera hasta 60 segundos para una detención limpia
- Verifica que el servicio se haya detenido correctamente

### 3. Backup Automático

El script crea un backup completo que incluye:

- `config.xml`: Configuración principal de Jenkins
- `jobs/`: Todos los trabajos configurados
- `users/`: Información de usuarios
- `plugins/`: Plugins instalados
- `secrets/`: Archivos de secretos
- `credentials.xml`: Credenciales almacenadas
- Archivos de claves de seguridad

Los backups se nombran con timestamp: `jenkins_backup_YYYYMMDD_HHMMSS.tar.gz`

### 4. Limpieza de Archivos Temporales

El script limpia:

- Archivos WAR temporales
- Cache de plugins (archivos .tmp y .bak)
- Logs antiguos (más de 30 días)
- Archivos .lock y .tmp
- Opcionalmente, workspaces de builds antiguos

### 5. Gestión de Backups

- Mantiene solo el backup más reciente por defecto
- Elimina automáticamente backups antiguos
- Configurable mediante la variable `MAX_BACKUPS`

### 6. Reinicio y Verificación

- Reinicia el servicio Jenkins
- Espera hasta 120 segundos para que Jenkins inicie completamente
- Verifica el estado del servicio
- Comprueba que los puertos estén escuchando

## 📊 Logs

El script genera logs detallados en `/var/log/jenkins_maintenance.log` con:

- Timestamp de cada operación
- Nivel de log (INFO, SUCCESS, WARNING, ERROR)
- Salida colorizada en la consola para fácil lectura

## ⚙️ Programación Automática

Para ejecutar el script automáticamente, puedes configurar un cron job:

```bash
# Editar crontab
sudo crontab -e

# Ejecutar cada domingo a las 2:00 AM
0 2 * * 0 /ruta/al/jenkins_maintenance.sh >> /var/log/jenkins_maintenance_cron.log 2>&1
```

## 🔒 Requisitos

- Sistema operativo Linux con systemd
- Privilegios de root o sudo
- Jenkins instalado y configurado
- Herramientas estándar: tar, find, netstat o ss

## ⚠️ Precauciones

- **Siempre haz una prueba en un entorno de desarrollo primero**
- El script detendrá Jenkins temporalmente, planifica el mantenimiento en horarios de bajo uso
- Asegúrate de tener suficiente espacio en disco para los backups
- Revisa los logs después de cada ejecución

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Por favor:

1. Fork el repositorio
2. Crea una rama para tu feature (`git checkout -b feature/NuevaFuncionalidad`)
3. Commit tus cambios (`git commit -m 'Agrega nueva funcionalidad'`)
4. Push a la rama (`git push origin feature/NuevaFuncionalidad`)
5. Abre un Pull Request

## 📄 Licencia

Este proyecto es de código abierto y está disponible bajo la licencia MIT.

## 👤 Autor

**Raul Mauricio Uñate Castro**

- GitHub: [@rmunate](https://github.com/rmunate)

## 📞 Soporte

Si encuentras algún problema o tienes sugerencias, por favor abre un issue en GitHub.
