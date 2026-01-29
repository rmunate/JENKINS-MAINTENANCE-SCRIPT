# Ejemplos de Uso del Script de Mantenimiento de Jenkins

## Ejemplo 1: Ejecución Básica

```bash
# Ejecución simple con configuración por defecto
sudo ./jenkins_maintenance.sh
```

## Ejemplo 2: Personalización con Variables de Entorno

```bash
# Especificar directorio de Jenkins personalizado
sudo JENKINS_HOME=/opt/jenkins ./jenkins_maintenance.sh

# Especificar directorio de backup personalizado
sudo BACKUP_DIR=/mnt/backup/jenkins ./jenkins_maintenance.sh

# Especificar nombre del servicio personalizado
sudo JENKINS_SERVICE=jenkins-custom ./jenkins_maintenance.sh
```

## Ejemplo 3: Configuración Completa Personalizada

```bash
# Ejecutar con todas las variables personalizadas
sudo JENKINS_HOME=/opt/jenkins \
     BACKUP_DIR=/mnt/backup/jenkins \
     JENKINS_SERVICE=jenkins-master \
     ./jenkins_maintenance.sh
```

## Ejemplo 4: Programación con Cron

### Mantenimiento Semanal (Domingos a las 2:00 AM)

```bash
# Editar crontab
sudo crontab -e

# Agregar línea:
0 2 * * 0 /home/admin/jenkins_maintenance.sh >> /var/log/jenkins_maintenance_cron.log 2>&1
```

### Mantenimiento Mensual (Primer día del mes a las 3:00 AM)

```bash
# Agregar línea en crontab:
0 3 1 * * /home/admin/jenkins_maintenance.sh >> /var/log/jenkins_maintenance_cron.log 2>&1
```

### Mantenimiento Diario (Todos los días a las 1:00 AM)

```bash
# Agregar línea en crontab:
0 1 * * * /home/admin/jenkins_maintenance.sh >> /var/log/jenkins_maintenance_cron.log 2>&1
```

## Ejemplo 5: Verificación de Logs

```bash
# Ver los últimos logs del script
sudo tail -f /var/log/jenkins_maintenance.log

# Ver logs con filtro de errores
sudo grep ERROR /var/log/jenkins_maintenance.log

# Ver logs de la última ejecución
sudo tail -n 100 /var/log/jenkins_maintenance.log
```

## Ejemplo 6: Prueba en Modo Seco (Dry Run)

Para probar el script sin realizar cambios reales, puedes modificar temporalmente el script para agregar echo antes de los comandos destructivos:

```bash
# Ver qué archivos se eliminarían sin eliminarlos
find "${JENKINS_HOME}/plugins" -name "*.tmp" 2>/dev/null

# Ver el tamaño de los workspaces sin eliminarlos
find "${JENKINS_HOME}/jobs" -type d -name "workspace" -exec du -sh {} \;
```

## Ejemplo 7: Restauración desde Backup

```bash
# Listar backups disponibles
ls -lh /var/backups/jenkins/

# Restaurar un backup específico
# NOTA: Detener Jenkins primero
sudo systemctl stop jenkins

# Extraer backup
sudo tar -xzf /var/backups/jenkins/jenkins_backup_20240129_020000.tar.gz -C /var/lib/jenkins/

# Reiniciar Jenkins
sudo systemctl start jenkins
```

## Ejemplo 8: Integración con Scripts de Monitoreo

```bash
#!/bin/bash
# Script de wrapper con notificaciones

# Ejecutar mantenimiento
/home/admin/jenkins_maintenance.sh

# Verificar resultado
if [ $? -eq 0 ]; then
    echo "Mantenimiento completado exitosamente" | mail -s "Jenkins Maintenance OK" admin@example.com
else
    echo "ERROR en mantenimiento de Jenkins" | mail -s "Jenkins Maintenance FAILED" admin@example.com
fi
```

## Ejemplo 9: Ejecución con Ansible

```yaml
---
- name: Ejecutar mantenimiento de Jenkins
  hosts: jenkins_servers
  become: yes
  tasks:
    - name: Copiar script de mantenimiento
      copy:
        src: jenkins_maintenance.sh
        dest: /opt/scripts/jenkins_maintenance.sh
        mode: '0755'
    
    - name: Ejecutar mantenimiento
      shell: /opt/scripts/jenkins_maintenance.sh
      register: maintenance_output
    
    - name: Mostrar resultado
      debug:
        var: maintenance_output.stdout_lines
```

## Ejemplo 10: Monitoreo del Espacio de Backup

```bash
# Script para verificar espacio de backup antes de ejecutar mantenimiento
#!/bin/bash

BACKUP_DIR=/var/backups/jenkins
MIN_SPACE_GB=5

# Verificar espacio disponible
available_space=$(df -BG "$BACKUP_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')

if [ "$available_space" -lt "$MIN_SPACE_GB" ]; then
    echo "Advertencia: Espacio insuficiente en $BACKUP_DIR"
    exit 1
fi

# Ejecutar mantenimiento
./jenkins_maintenance.sh
```

## Consejos y Mejores Prácticas

1. **Siempre prueba primero**: Ejecuta el script en un entorno de desarrollo antes de usar en producción.

2. **Monitorea el espacio en disco**: Asegúrate de tener suficiente espacio para los backups.

3. **Revisa los logs regularmente**: Verifica que no haya errores o advertencias.

4. **Programa el mantenimiento**: Usa cron para ejecutar automáticamente en horarios de bajo tráfico.

5. **Mantén backups externos**: Considera copiar los backups a un almacenamiento externo o en la nube.

6. **Documenta tu configuración**: Mantén un registro de las variables personalizadas que usas.

7. **Prueba la restauración**: Periodicamente verifica que puedes restaurar desde los backups.
