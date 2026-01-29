#!/bin/bash
# ===============================================================================
# JENKINS MAINTENANCE SCRIPT
# ===============================================================================
# Descripción: Script completo de mantenimiento para Jenkins que incluye:
#              - Verificación del estado del sistema
#              - Detención segura de Jenkins
#              - Backup automático de configuraciones
#              - Limpieza de archivos temporales y cache
#              - Reinicio y verificación del servicio
#              - Gestión de backups (mantiene solo el más reciente)
#
# Autor: Raul Mauricio Uñate
# Versión: 2.0
# Fecha: 29 de enero de 2026
#
# Uso:
#   Interactivo: sudo ./jenkins-maintenance.sh
#   Silencioso:  sudo ./jenkins-maintenance.sh --silent
#   Cron:        sudo ./jenkins-maintenance.sh --cron
#
# Requisitos:
#   - Ejecutar como root o con sudo
#   - Jenkins instalado como servicio systemd
#   - Directorio de backup con permisos de escritura
#   - Herramientas: curl, systemctl, tar, find
#
# Salida:
#   - Modo interactivo: Output colorizado en consola
#   - Modo silencioso: Solo errores críticos
#   - Modo cron: Log detallado en archivo + errores críticos a consola
# ===============================================================================

# ===============================================================================
# CONFIGURACIÓN Y VARIABLES GLOBALES
# ===============================================================================

# Rutas y configuración de Jenkins
JENKINS_HOME="/var/lib/jenkins"
JENKINS_URL="http://localhost:8080"
BACKUP_DIR="/backup/jenkins"
LOG_DIR="/var/log/jenkins-maintenance"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")

# Archivos de salida
LOG_FILE="$LOG_DIR/maintenance_$DATE.log"
ERROR_LOG="$LOG_DIR/errors.log"

# Timeouts y límites
SHUTDOWN_TIMEOUT=30
STARTUP_TIMEOUT=120
MAX_BUILDS_PER_JOB=50
LOG_RETENTION_DAYS=30

# Colores para output (solo en modo interactivo)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Modo de ejecución (por defecto interactivo)
SILENT_MODE=false
CRON_MODE=false

# ===============================================================================
# FUNCIONES DE UTILIDAD
# ===============================================================================

# Función para mostrar ayuda
show_help() {
    cat << EOF
Jenkins Maintenance Script v2.0

Uso: $0 [OPCIONES]

OPCIONES:
    --silent    Modo silencioso (solo errores críticos)
    --cron      Modo cron (log a archivo + errores a consola)
    --help      Mostrar esta ayuda

DESCRIPCIÓN:
    Este script realiza mantenimiento completo de Jenkins incluyendo:
    1. Verificación del estado del sistema
    2. Detención controlada del servicio
    3. Backup de configuraciones críticas
    4. Limpieza de archivos temporales y cache
    5. Reinicio y verificación del servicio
    6. Limpieza de backups antiguos

EJEMPLOS:
    # Ejecución interactiva (manual)
    sudo $0

    # Ejecución silenciosa
    sudo $0 --silent

    # Para cron (recomendado)
    sudo $0 --cron

CRON EJEMPLO:
    # Mantenimiento diario a las 2:00 AM
    0 2 * * * /usr/local/bin/jenkins-maintenance.sh --cron

EOF
}

# Función de logging avanzada
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Log a archivo si está en modo cron
    if [ "$CRON_MODE" = true ]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi

    # Output a consola según el modo
    case "$level" in
        "INFO")
            if [ "$SILENT_MODE" = false ] && [ "$CRON_MODE" = false ]; then
                echo -e "${GREEN}[INFO]${NC} $message"
            fi
            ;;
        "WARN")
            if [ "$SILENT_MODE" = false ]; then
                echo -e "${YELLOW}[WARN]${NC} $message"
            fi
            if [ "$CRON_MODE" = true ]; then
                echo "[$timestamp] [WARN] $message" >> "$ERROR_LOG"
            fi
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            if [ "$CRON_MODE" = true ]; then
                echo "[$timestamp] [ERROR] $message" >> "$ERROR_LOG"
            fi
            ;;
        "SUCCESS")
            if [ "$SILENT_MODE" = false ]; then
                echo -e "${GREEN}[✓]${NC} $message"
            fi
            ;;
    esac
}

# Funciones de logging simplificadas
log_info() { log_message "INFO" "$1"; }
log_warn() { log_message "WARN" "$1"; }
log_error() { log_message "ERROR" "$1"; }
log_success() { log_message "SUCCESS" "$1"; }

# Función para mostrar encabezados de sección
show_section() {
    local title="$1"
    if [ "$SILENT_MODE" = false ] && [ "$CRON_MODE" = false ]; then
        echo ""
        echo "=== $title ==="
    fi
    log_info "Iniciando: $title"
}

# Función para verificar prerrequisitos
check_prerequisites() {
    local errors=0

    # Verificar que se ejecuta como root
    if [ "$EUID" -ne 0 ]; then
        log_error "Este script debe ejecutarse como root (use sudo)"
        ((errors++))
    fi

    # Verificar herramientas necesarias
    local tools=("systemctl" "curl" "tar" "find" "netstat")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Herramienta requerida no encontrada: $tool"
            ((errors++))
        fi
    done

    # Crear directorios necesarios
    mkdir -p "$BACKUP_DIR" "$LOG_DIR"

    # Verificar que Jenkins existe como servicio
    if ! systemctl list-unit-files | grep -q jenkins; then
        log_error "Jenkins no está instalado como servicio systemd"
        ((errors++))
    fi

    return $errors
}

# Función para obtener estadísticas del sistema
get_system_stats() {
    local stats_file="/tmp/jenkins_stats_before.tmp"

    # Información del sistema
    echo "system_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')" > "$stats_file"
    echo "disk_usage_before=$(df -h $JENKINS_HOME | tail -1 | awk '{print $5}')" >> "$stats_file"
    echo "jenkins_home_size_before=$(du -sh $JENKINS_HOME 2>/dev/null | cut -f1)" >> "$stats_file"
    echo "memory_usage=$(free -h | awk 'NR==2{printf "%.1f%%", $3/$2*100}')" >> "$stats_file"

    # Cargar estadísticas
    source "$stats_file"
    log_info "Carga del sistema: $system_load"
    log_info "Uso de memoria: $memory_usage"
    log_info "Tamaño Jenkins antes: $jenkins_home_size_before"
    log_info "Uso de disco antes: $disk_usage_before"
}

# ===============================================================================
# PROCESAMIENTO DE ARGUMENTOS
# ===============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --silent)
            SILENT_MODE=true
            shift
            ;;
        --cron)
            CRON_MODE=true
            SILENT_MODE=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Opción desconocida: $1"
            show_help
            exit 1
            ;;
    esac
done

# ===============================================================================
# INICIO DEL SCRIPT PRINCIPAL
# ===============================================================================

# Mostrar encabezado solo en modo interactivo
if [ "$SILENT_MODE" = false ] && [ "$CRON_MODE" = false ]; then
    echo "==============================================="
    echo "  JENKINS MAINTENANCE SCRIPT v2.0"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "==============================================="
fi

# Verificar prerrequisitos
if ! check_prerequisites; then
    log_error "Falló la verificación de prerrequisitos"
    exit 1
fi

# Obtener estadísticas iniciales
get_system_stats

# ===============================================================================
# PASO 1: VERIFICACIÓN DEL ESTADO INICIAL
# ===============================================================================
show_section "1. VERIFICACIÓN DEL ESTADO INICIAL"

# Variable para tracking del estado
JENKINS_WAS_RUNNING=false

# Verificar estado del servicio Jenkins
if systemctl is-active --quiet jenkins; then
    JENKINS_WAS_RUNNING=true
    log_success "Jenkins está ACTIVO"

    # Obtener información detallada del proceso
    JENKINS_PID=$(systemctl show -p MainPID jenkins | cut -d= -f2)
    if [ "$JENKINS_PID" -ne 0 ]; then
        MEM_USED=$(ps -p $JENKINS_PID -o %mem --no-headers | tr -d ' ')
        CPU_USED=$(ps -p $JENKINS_PID -o %cpu --no-headers | tr -d ' ')
        log_info "PID: $JENKINS_PID | Memoria: ${MEM_USED}% | CPU: ${CPU_USED}%"
    fi
else
    log_warn "Jenkins NO está activo"
fi

# Verificar conectividad de red
if netstat -tln | grep -q :8080; then
    log_success "Puerto 8080 está ESCUCHANDO"
else
    if [ "$JENKINS_WAS_RUNNING" = true ]; then
        log_warn "Puerto 8080 NO está escuchando (Jenkins activo pero sin red)"
    fi
fi

# Verificar respuesta HTTP (solo si Jenkins está corriendo)
if [ "$JENKINS_WAS_RUNNING" = true ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$JENKINS_URL" 2>/dev/null)
    case "$HTTP_CODE" in
        200) log_success "Web UI responde correctamente (HTTP $HTTP_CODE)" ;;
        000) log_warn "Sin conectividad HTTP (timeout o conexión rechazada)" ;;
        *) log_warn "Web UI responde con código: HTTP $HTTP_CODE" ;;
    esac
fi

# Verificar espacio en disco
DISK_USAGE=$(df -h $JENKINS_HOME | tail -1 | awk '{print $5}' | tr -d '%')
DISK_TOTAL=$(df -h $JENKINS_HOME | tail -1 | awk '{print $2}')
DISK_USED=$(df -h $JENKINS_HOME | tail -1 | awk '{print $3}')

log_info "Espacio en disco: ${DISK_USED} / ${DISK_TOTAL} (${DISK_USAGE}%)"

# Advertencia si el disco está muy lleno
if [ "$DISK_USAGE" -gt 85 ]; then
    log_warn "⚠️  Disco con uso alto: ${DISK_USAGE}% - Limpieza crítica necesaria"
elif [ "$DISK_USAGE" -gt 70 ]; then
    log_warn "⚠️  Disco con uso moderado: ${DISK_USAGE}% - Limpieza recomendada"
fi

# Verificar jobs activos/en cola (solo si Jenkins está corriendo)
if [ "$JENKINS_WAS_RUNNING" = true ] && curl -s -f "$JENKINS_URL/api/json" >/dev/null 2>&1; then
    # Intentar obtener información de jobs en cola
    QUEUE_SIZE=$(curl -s "$JENKINS_URL/queue/api/json" 2>/dev/null | grep -o '"items":\[[^]]*\]' | grep -o '\{[^}]*\}' | wc -l)
    if [ "$QUEUE_SIZE" -gt 0 ]; then
        log_warn "Hay $QUEUE_SIZE jobs en cola - serán cancelados al detener Jenkins"
    else
        log_info "No hay jobs en cola"
    fi
fi

# ===============================================================================
# PASO 2: DETENCIÓN CONTROLADA DE JENKINS
# ===============================================================================
show_section "2. DETENCIÓN CONTROLADA DE JENKINS"

# Solo detener si está corriendo
if [ "$JENKINS_WAS_RUNNING" = true ]; then
    log_info "Iniciando detención controlada de Jenkins..."

    # Detención normal
    if systemctl stop jenkins; then
        log_info "Comando de detención enviado"
    else
        log_error "Fallo al enviar comando de detención"
        exit 1
    fi

    # Esperar detención normal con timeout
    wait_count=0
    while [ $wait_count -lt $SHUTDOWN_TIMEOUT ]; do
        if ! systemctl is-active --quiet jenkins; then
            log_success "Jenkins detenido normalmente (${wait_count}s)"
            break
        fi
        sleep 1
        ((wait_count++))

        # Mostrar progreso cada 5 segundos en modo interactivo
        if [ $((wait_count % 5)) -eq 0 ] && [ "$SILENT_MODE" = false ]; then
            log_info "Esperando detención... ${wait_count}/${SHUTDOWN_TIMEOUT}s"
        fi
    done

    # Si no se detuvo normalmente, forzar detención
    if systemctl is-active --quiet jenkins; then
        log_warn "Detención normal timeout, forzando detención..."
        if systemctl kill jenkins; then
            sleep 5
            if ! systemctl is-active --quiet jenkins; then
                log_success "Jenkins forzadamente detenido"
            else
                log_error "No se pudo detener Jenkins incluso con kill"
                exit 1
            fi
        else
            log_error "Fallo al forzar detención de Jenkins"
            exit 1
        fi
    fi

    # Verificar que no hay procesos Jenkins residuales
    if pgrep -f "java.*jenkins" > /dev/null; then
        log_warn "Procesos Jenkins residuales detectados, limpiando..."
        # Buscar específicamente procesos Java de Jenkins, no el script
        pkill -f "java.*jenkins"
        sleep 2
    fi

    log_success "Jenkins completamente detenido"
else
    log_info "Jenkins ya estaba detenido, continuando..."
fi

# ===============================================================================
# PASO 3: BACKUP DE SEGURIDAD
# ===============================================================================
show_section "3. CREACIÓN DE BACKUP DE SEGURIDAD"

BACKUP_FILE="$BACKUP_DIR/jenkins_backup_$DATE.tar.gz"
log_info "Creando backup en: $BACKUP_FILE"

# Crear backup excluyendo directorios temporales y cache
# para optimizar tamaño y tiempo
EXCLUDE_PATTERNS=(
    --exclude="$JENKINS_HOME/workspace/*/target/*"
    --exclude="$JENKINS_HOME/workspace/*/.git/*"
    --exclude="$JENKINS_HOME/workspace/*/node_modules/*"
    --exclude="$JENKINS_HOME/cache/*"
    --exclude="$JENKINS_HOME/.cache/*"
    --exclude="$JENKINS_HOME/.gradle/*"
    --exclude="$JENKINS_HOME/.npm/*"
    --exclude="$JENKINS_HOME/.m2/repository/*"
    --exclude="$JENKINS_HOME/logs/*"
    --exclude="$JENKINS_HOME/war/*"
    --exclude="$JENKINS_HOME/plugins/*.bak"
    --exclude="$JENKINS_HOME/plugins/*.old"
    --exclude="$JENKINS_HOME/updates/*"
)

# Crear el backup con barra de progreso en modo interactivo
if [ "$SILENT_MODE" = false ]; then
    tar "${EXCLUDE_PATTERNS[@]}" -czf "$BACKUP_FILE" "$JENKINS_HOME" 2>/dev/null &
    TAR_PID=$!

    # Mostrar progreso
    while kill -0 $TAR_PID 2>/dev/null; do
        echo -n "."
        sleep 1
    done
    echo ""
    wait $TAR_PID
    TAR_STATUS=$?
else
    tar "${EXCLUDE_PATTERNS[@]}" -czf "$BACKUP_FILE" "$JENKINS_HOME" 2>/dev/null
    TAR_STATUS=$?
fi

# Verificar resultado del backup
if [ $TAR_STATUS -eq 0 ] && [ -f "$BACKUP_FILE" ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log_success "Backup creado exitosamente: $(basename "$BACKUP_FILE") (${BACKUP_SIZE})"

    # Verificar integridad del backup
    if tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then
        log_success "Integridad del backup verificada"
    else
        log_warn "Backup creado pero con posibles problemas de integridad"
    fi
else
    log_error "Error al crear el backup"
    # En modo cron, intentar continuar sin backup
    if [ "$CRON_MODE" = true ]; then
        log_error "Continuando sin backup en modo cron"
    else
        exit 1
    fi
fi

# ===============================================================================
# PASO 4: LIMPIEZA COMPLETA DEL SISTEMA
# ===============================================================================
show_section "4. LIMPIEZA COMPLETA DEL SISTEMA"

# Contador de espacio liberado
SPACE_FREED=0

# Función para calcular tamaño de directorio
get_dir_size() {
    local dir="$1"
    if [ -d "$dir" ]; then
        du -sb "$dir" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

# Función para limpiar directorio con reporte
clean_directory() {
    local dir="$1"
    local description="$2"

    if [ -d "$dir" ]; then
        size_before=$(get_dir_size "$dir")
        files_before=$(find "$dir" -type f 2>/dev/null | wc -l)

        # Limpiar contenido pero mantener directorio
        rm -rf "$dir"/* 2>/dev/null
        rm -rf "$dir"/.* 2>/dev/null

        size_after=$(get_dir_size "$dir")
        space_freed=$((size_before - size_after))

        if [ $space_freed -gt 0 ]; then
            space_freed_mb=$((space_freed / 1024 / 1024))
            log_success "Limpio $description: ${files_before} archivos, ${space_freed_mb}MB liberados"
            SPACE_FREED=$((SPACE_FREED + space_freed))
        else
            log_info "Limpio $description: ya estaba vacío"
        fi
    else
        log_info "$description: directorio no existe"
    fi
}

# A. Limpieza de directorios de caché de Jenkins
log_info "Limpiando cachés de Jenkins..."
CACHE_DIRS=(
    "$JENKINS_HOME/cache:Cache principal"
    "$JENKINS_HOME/.cache:Cache oculto"
    "$JENKINS_HOME/.gradle:Cache Gradle"
    "$JENKINS_HOME/.npm:Cache NPM"
    "$JENKINS_HOME/.m2/repository:Cache Maven"
    "$JENKINS_HOME/caches:Cachés varios"
    "$JENKINS_HOME/temp:Archivos temporales"
)

for dir_info in "${CACHE_DIRS[@]}"; do
    IFS=':' read -r dir desc <<< "$dir_info"
    clean_directory "$dir" "$desc"
done

# B. Limpieza de logs antiguos de builds
log_info "Limpiando logs de builds antiguos (>$LOG_RETENTION_DAYS días)..."
if [ -d "$JENKINS_HOME/jobs" ]; then
    LOGS_CLEANED=0
    while IFS= read -r -d '' logfile; do
        rm -f "$logfile"
        ((LOGS_CLEANED++))
    done < <(find "$JENKINS_HOME/jobs" -name "log" -type f -mtime +$LOG_RETENTION_DAYS -print0 2>/dev/null)

    while IFS= read -r -d '' logfile; do
        rm -f "$logfile"
        ((LOGS_CLEANED++))
    done < <(find "$JENKINS_HOME/jobs" -name "*.log" -type f -mtime +$LOG_RETENTION_DAYS -print0 2>/dev/null)

    log_success "Logs eliminados: $LOGS_CLEANED archivos"
else
    log_info "Directorio de jobs no encontrado"
fi

# C. Limpieza de workspaces inactivos
log_info "Limpiando workspaces inactivos (>7 días sin uso)..."
if [ -d "$JENKINS_HOME/workspace" ]; then
    WORKSPACES_CLEANED=0
    while IFS= read -r -d '' workspace; do
        rm -rf "$workspace"
        ((WORKSPACES_CLEANED++))
    done < <(find "$JENKINS_HOME/workspace" -type d -name "*" -mtime +7 -print0 2>/dev/null)

    log_success "Workspaces eliminados: $WORKSPACES_CLEANED directorios"
fi

# D. Limpieza de builds antiguos (mantener solo los más recientes)
log_info "Limpiando builds antiguos (manteniendo últimos $MAX_BUILDS_PER_JOB por job)..."
BUILDS_CLEANED=0
if [ -d "$JENKINS_HOME/jobs" ]; then
    for job_builds_dir in "$JENKINS_HOME/jobs"/*/builds/; do
        if [ -d "$job_builds_dir" ]; then
            job_name=$(basename "$(dirname "$job_builds_dir")")
            builds_count=$(ls -1 "$job_builds_dir" 2>/dev/null | wc -l)

            if [ "$builds_count" -gt "$MAX_BUILDS_PER_JOB" ]; then
                to_remove=$((builds_count - MAX_BUILDS_PER_JOB))
                ls -t "$job_builds_dir" | tail -n +$((MAX_BUILDS_PER_JOB + 1)) | \
                while read -r build; do
                    rm -rf "$job_builds_dir/$build" 2>/dev/null
                    ((BUILDS_CLEANED++))
                done
                log_info "Job '$job_name': eliminados $to_remove builds antiguos"
            fi
        fi
    done
fi
log_success "Total builds eliminados: $BUILDS_CLEANED"

# E. Limpieza del sistema operativo
log_info "Limpiando archivos temporales del sistema..."
TEMP_DIRS=(
    "/tmp:Temporal global"
    "/var/tmp:Temporal variable"
)

for dir_info in "${TEMP_DIRS[@]}"; do
    IFS=':' read -r dir desc <<< "$dir_info"
    if [ -d "$dir" ]; then
        find "$dir" -type f -atime +1 -delete 2>/dev/null
        log_info "Limpio $desc"
    fi
done

# Limpieza de logs del sistema (mantener últimos 3 días)
if command -v journalctl &> /dev/null; then
    journalctl --vacuum-time=3d >/dev/null 2>&1
    log_info "Logs del sistema optimizados"
fi

# F. Limpieza de Docker (si está presente)
if command -v docker &> /dev/null && docker info >/dev/null 2>&1; then
    log_info "Limpiando recursos de Docker..."

    # Limpiar contenedores parados
    CONTAINERS_REMOVED=$(docker container prune -f 2>/dev/null | grep "Total reclaimed space" | awk '{print $4$5}' || echo "0")

    # Limpiar imágenes huérfanas
    IMAGES_REMOVED=$(docker image prune -f 2>/dev/null | grep "Total reclaimed space" | awk '{print $4$5}' || echo "0")

    # Limpiar volúmenes no utilizados
    VOLUMES_REMOVED=$(docker volume prune -f 2>/dev/null | grep "Total reclaimed space" | awk '{print $4$5}' || echo "0")

    log_success "Docker limpiado: Contenedores: $CONTAINERS_REMOVED, Imágenes: $IMAGES_REMOVED, Volúmenes: $VOLUMES_REMOVED"
fi

# Mostrar resumen de limpieza
TOTAL_FREED_MB=$((SPACE_FREED / 1024 / 1024))
if [ $TOTAL_FREED_MB -gt 0 ]; then
    log_success "Espacio total liberado: ${TOTAL_FREED_MB}MB"
else
    log_info "Sistema ya estaba optimizado"
fi

# ===============================================================================
# PASO 5: REINICIO Y VERIFICACIÓN DE JENKINS
# ===============================================================================
show_section "5. REINICIO Y VERIFICACIÓN DE JENKINS"

# Solo reiniciar si estaba corriendo originalmente
if [ "$JENKINS_WAS_RUNNING" = true ]; then
    log_info "Reiniciando Jenkins..."

    # Verificar integridad antes del reinicio
    log_info "Verificando integridad de archivos críticos..."

    # Verificar archivos críticos de Jenkins
    CRITICAL_FILES=(
        "$JENKINS_HOME/config.xml"
        "$JENKINS_HOME/users"
        "$JENKINS_HOME/plugins"
    )

    MISSING_FILES=0
    for file in "${CRITICAL_FILES[@]}"; do
        if [ ! -e "$file" ]; then
            log_warn "Archivo crítico faltante: $file"
            ((MISSING_FILES++))
        fi
    done

    if [ $MISSING_FILES -gt 0 ]; then
        log_error "Se detectaron $MISSING_FILES archivos críticos faltantes"
        log_error "Restaurando desde backup antes del reinicio..."

        # Restaurar backup automáticamente
        if [ -f "$BACKUP_FILE" ]; then
            log_info "Restaurando backup: $BACKUP_FILE"
            tar -xzf "$BACKUP_FILE" -C / 2>/dev/null
            if [ $? -eq 0 ]; then
                log_success "Backup restaurado exitosamente"
            else
                log_error "Error al restaurar backup"
                exit 1
            fi
        else
            log_error "No hay backup disponible para restaurar"
            exit 1
        fi
    fi

    # Iniciar servicio con mejor manejo de errores
    log_info "Intentando iniciar servicio Jenkins..."
    START_OUTPUT=$(systemctl start jenkins 2>&1)
    START_STATUS=$?

    if [ $START_STATUS -eq 0 ]; then
        log_success "Comando de inicio enviado exitosamente"
    else
        log_error "Error al iniciar Jenkins (código: $START_STATUS)"
        log_error "Output del comando: $START_OUTPUT"

        # Diagnóstico detallado
        log_info "Ejecutando diagnóstico del error..."

        # Mostrar status del servicio
        JENKINS_STATUS=$(systemctl status jenkins.service --no-pager -l 2>&1)
        log_error "Status del servicio Jenkins:"
        echo "$JENKINS_STATUS" | head -20

        # Mostrar logs recientes de Jenkins
        log_error "Últimos logs de Jenkins:"
        journalctl -u jenkins.service --no-pager -n 10 2>/dev/null || echo "No se pudieron obtener logs"

        # Verificar permisos
        log_info "Verificando permisos de $JENKINS_HOME..."
        JENKINS_OWNER=$(stat -c %U "$JENKINS_HOME" 2>/dev/null || echo "unknown")
        JENKINS_GROUP=$(stat -c %G "$JENKINS_HOME" 2>/dev/null || echo "unknown")
        log_info "Propietario actual: $JENKINS_OWNER:$JENKINS_GROUP"

        # Intentar reparar permisos
        if id jenkins >/dev/null 2>&1; then
            log_info "Reparando permisos de Jenkins..."
            chown -R jenkins:jenkins "$JENKINS_HOME" 2>/dev/null
            log_info "Permisos reparados"

            # Segundo intento de inicio
            log_info "Segundo intento de inicio..."
            if systemctl start jenkins; then
                log_success "Jenkins iniciado en segundo intento"
            else
                log_error "Segundo intento fallido"
                log_warn "Para diagnóstico manual: systemctl status jenkins.service"
                log_warn "Para logs detallados: journalctl -xeu jenkins.service"
                log_warn "Para restaurar: tar -xzf $BACKUP_FILE -C /"
                exit 1
            fi
        else
            log_error "Usuario 'jenkins' no encontrado en el sistema"
            exit 1
        fi
    fi

    # Esperar a que el servicio esté activo
    log_info "Esperando activación del servicio..."
    wait_count=0
    while [ $wait_count -lt 30 ]; do
        if systemctl is-active --quiet jenkins; then
            log_success "Servicio Jenkins activo (${wait_count}s)"
            break
        fi
        sleep 1
        ((wait_count++))

        # Mostrar progreso cada 5 segundos
        if [ $((wait_count % 5)) -eq 0 ] && [ "$SILENT_MODE" = false ]; then
            log_info "Esperando activación... ${wait_count}/30s"
        fi
    done

    if ! systemctl is-active --quiet jenkins; then
        log_error "Jenkins no se activó como servicio después de 30s"

        # Diagnóstico adicional
        JENKINS_STATUS=$(systemctl is-failed jenkins 2>/dev/null)
        if [ "$JENKINS_STATUS" = "failed" ]; then
            log_error "El servicio Jenkins está en estado 'failed'"
            journalctl -u jenkins.service --no-pager -n 5 2>/dev/null || echo "No logs disponibles"
        fi

        log_warn "Para restaurar: tar -xzf $BACKUP_FILE -C /"
        exit 1
    fi

    # Esperar a que Jenkins responda HTTP
    log_info "Esperando que Jenkins responda..."
    retries=0
    max_retries=$((STARTUP_TIMEOUT / 10))

    while [ $retries -lt $max_retries ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$JENKINS_URL" 2>/dev/null)
        case "$HTTP_CODE" in
            200)
                log_success "✅ Jenkins completamente funcional (${retries}0s)"
                break
                ;;
            403|401)
                log_success "✅ Jenkins responde pero requiere autenticación (${retries}0s)"
                break
                ;;
            503)
                if [ "$SILENT_MODE" = false ]; then
                    log_info "Jenkins iniciando... (${retries}0s)"
                fi
                ;;
            000)
                if [ "$SILENT_MODE" = false ]; then
                    log_info "Esperando conexión... (${retries}0s)"
                fi
                ;;
            *)
                if [ "$SILENT_MODE" = false ]; then
                    log_info "HTTP $HTTP_CODE - Continuando espera... (${retries}0s)"
                fi
                ;;
        esac

        sleep 10
        ((retries++))
    done

    # Verificación final
    if [ $retries -eq $max_retries ]; then
        log_error "❌ Jenkins no responde después de ${STARTUP_TIMEOUT}s"
        log_error "Posible problema en la configuración o corrupción"
        log_warn "Para restaurar: tar -xzf $BACKUP_FILE -C /"
        exit 1
    fi

    # Verificar puerto de red
    if netstat -tln | grep -q :8080; then
        log_success "Puerto 8080 activo"
    else
        log_warn "Puerto 8080 no detectado"
    fi

else
    log_info "Jenkins no estaba corriendo inicialmente, manteniéndolo detenido"
fi

# ===============================================================================
# PASO 6: ESTADÍSTICAS POST-MANTENIMIENTO
# ===============================================================================
show_section "6. ESTADÍSTICAS POST-MANTENIMIENTO"

# Obtener estadísticas finales
DISK_AFTER=$(df -h $JENKINS_HOME | tail -1 | awk '{print $5}' | tr -d '%')
JENKINS_SIZE_AFTER=$(du -sh $JENKINS_HOME 2>/dev/null | cut -f1)
DISK_USAGE_AFTER=$(df -h $JENKINS_HOME | tail -1 | awk '{print $5}')

# Comparar con estadísticas iniciales
source "/tmp/jenkins_stats_before.tmp" 2>/dev/null || true

log_info "📊 RESUMEN DE CAMBIOS:"
log_info "  Tamaño Jenkins: $jenkins_home_size_before → $JENKINS_SIZE_AFTER"
log_info "  Uso de disco: $disk_usage_before → $DISK_USAGE_AFTER"

# Calcular mejora en el disco
DISK_IMPROVEMENT=$((${disk_usage_before%\%} - DISK_AFTER))
if [ $DISK_IMPROVEMENT -gt 0 ]; then
    log_success "  Disco liberado: ${DISK_IMPROVEMENT}% de mejora"
elif [ $DISK_IMPROVEMENT -eq 0 ]; then
    log_info "  Uso de disco sin cambios significativos"
else
    log_warn "  Uso de disco aumentó (posible debido a logs/backups)"
fi

# Estadísticas de Jenkins
if [ -d "$JENKINS_HOME/jobs" ]; then
    JOB_COUNT=$(find "$JENKINS_HOME/jobs" -maxdepth 1 -type d 2>/dev/null | wc -l)
    if [ $JOB_COUNT -gt 1 ]; then
        log_info "📁 Total de jobs: $((JOB_COUNT - 1))"
    else
        log_info "📁 No hay jobs configurados"
    fi
fi

if [ -d "$JENKINS_HOME/plugins" ]; then
    PLUGIN_COUNT=$(ls -1 "$JENKINS_HOME/plugins"/*.jpi 2>/dev/null | wc -l)
    log_info "🔌 Total de plugins: $PLUGIN_COUNT"
fi

# Top 5 jobs por tamaño (solo en modo interactivo)
if [ "$SILENT_MODE" = false ] && [ -d "$JENKINS_HOME/jobs" ]; then
    echo ""
    echo "📊 Top 5 jobs por tamaño:"
    find "$JENKINS_HOME/jobs" -maxdepth 1 -type d -exec du -sh {} \; 2>/dev/null | \
    sort -hr | head -5 | while read -r size job; do
        job_name=$(basename "$job")
        if [ "$job_name" != "jobs" ]; then
            echo "   $size - $job_name"
        fi
    done
fi

# ===============================================================================
# PASO 7: GESTIÓN DE BACKUPS
# ===============================================================================
show_section "7. GESTIÓN DE BACKUPS"

# Contar backups existentes
if [ -d "$BACKUP_DIR" ]; then
    BACKUPS_BEFORE=$(find "$BACKUP_DIR" -name "jenkins_backup_*.tar.gz" 2>/dev/null | wc -l)
    log_info "Backups encontrados: $BACKUPS_BEFORE"

    if [ $BACKUPS_BEFORE -gt 1 ]; then
        log_info "Eliminando backups antiguos (manteniendo solo el actual)..."

        # Eliminar todos excepto el backup actual
        find "$BACKUP_DIR" -name "jenkins_backup_*.tar.gz" ! -name "$(basename "$BACKUP_FILE")" -delete 2>/dev/null

        # Verificar resultado
        BACKUPS_AFTER=$(find "$BACKUP_DIR" -name "jenkins_backup_*.tar.gz" 2>/dev/null | wc -l)
        BACKUPS_DELETED=$((BACKUPS_BEFORE - BACKUPS_AFTER))

        if [ $BACKUPS_DELETED -gt 0 ]; then
            log_success "✅ Eliminados $BACKUPS_DELETED backups antiguos"

            # Mostrar espacio liberado por limpieza de backups
            if [ "$SILENT_MODE" = false ]; then
                BACKUP_DIR_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
                log_info "Espacio actual de backups: $BACKUP_DIR_SIZE"
            fi
        else
            log_warn "No se pudieron eliminar backups antiguos"
        fi

        log_success "✅ Mantenido solo el backup actual: $(basename "$BACKUP_FILE")"
    else
        log_info "No había backups antiguos para eliminar"
    fi

    # Verificar integridad del backup final
    if [ -f "$BACKUP_FILE" ]; then
        if tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then
            log_success "✅ Backup final verificado e íntegro"
        else
            log_error "❌ El backup final tiene problemas de integridad"
        fi
    fi
else
    log_warn "Directorio de backup no existe: $BACKUP_DIR"
fi

# ===============================================================================
# LIMPIEZA Y FINALIZACIÓN
# ===============================================================================

# Limpiar archivos temporales del script
rm -f "/tmp/jenkins_stats_before.tmp" 2>/dev/null

# Rotar logs del script si está en modo cron
if [ "$CRON_MODE" = true ]; then
    # Mantener solo últimos 10 logs del script
    find "$LOG_DIR" -name "maintenance_*.log" -type f | sort | head -n -10 | xargs rm -f 2>/dev/null

    # Comprimir logs antiguos de errores si son grandes
    if [ -f "$ERROR_LOG" ]; then
        ERROR_LOG_SIZE=$(stat -c%s "$ERROR_LOG" 2>/dev/null || echo 0)
        if [ $ERROR_LOG_SIZE -gt 1048576 ]; then  # > 1MB
            gzip "$ERROR_LOG" 2>/dev/null
            touch "$ERROR_LOG"  # Crear nuevo archivo de errores
        fi
    fi
fi

# ===============================================================================
# RESUMEN FINAL
# ===============================================================================
echo ""
if [ "$SILENT_MODE" = false ]; then
    echo "==============================================="
    echo "  ✅ MANTENIMIENTO COMPLETADO EXITOSAMENTE"
    echo "  📅 $(date '+%Y-%m-%d %H:%M:%S')"
    echo "==============================================="
fi

# Log final siempre visible
log_success "🎯 MANTENIMIENTO JENKINS COMPLETADO"

# Información de backup
log_info "💾 Backup actual: $(basename "$BACKUP_FILE")"
if [ -f "$BACKUP_FILE" ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log_info "📦 Tamaño del backup: $BACKUP_SIZE"
    log_info "🔄 Para restaurar: tar -xzf $BACKUP_FILE -C /"
fi

# Información para cron
if [ "$CRON_MODE" = true ]; then
    log_info "📝 Log detallado: $LOG_FILE"
    if [ -f "$ERROR_LOG" ] && [ -s "$ERROR_LOG" ]; then
        log_warn "⚠️  Errores registrados en: $ERROR_LOG"
    fi
fi

# Estadísticas finales condensadas
if [ "$SILENT_MODE" = false ]; then
    echo ""
    echo "📊 RESUMEN RÁPIDO:"
    echo "   • Jenkins: $([ "$JENKINS_WAS_RUNNING" = true ] && echo "Reiniciado ✅" || echo "Mantenido detenido ⏹️")"
    echo "   • Disco: $disk_usage_before → $DISK_USAGE_AFTER"
    echo "   • Backup: $(basename "$BACKUP_FILE") ($BACKUP_SIZE)"
    echo "   • Duración: $(( $(date +%s) - $(date -d "$DATE" +%s 2>/dev/null || echo $(date +%s)) )) segundos"
    echo ""
fi

# Exit con código de éxito
exit 0