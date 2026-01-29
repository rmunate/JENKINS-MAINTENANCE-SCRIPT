#!/bin/bash

################################################################################
# Script de Mantenimiento para Jenkins
# Descripción: Script completo de mantenimiento para Jenkins que incluye:
#              - Verificación del estado del sistema
#              - Detención segura de Jenkins
#              - Backup automático de configuraciones
#              - Limpieza de archivos temporales y cache
#              - Reinicio y verificación del servicio
#              - Gestión de backups (mantiene solo el más reciente)
################################################################################

# Colores para la salida
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Sin color

# Variables de configuración
JENKINS_HOME="${JENKINS_HOME:-/var/lib/jenkins}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/jenkins}"
JENKINS_SERVICE="${JENKINS_SERVICE:-jenkins}"
LOG_FILE="/var/log/jenkins_maintenance.log"
MAX_BACKUPS=1  # Mantener solo el backup más reciente

################################################################################
# Funciones auxiliares
################################################################################

log_message() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $@"
    log_message "INFO" "$@"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $@"
    log_message "SUCCESS" "$@"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $@"
    log_message "WARNING" "$@"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@"
    log_message "ERROR" "$@"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root o con sudo"
        exit 1
    fi
}

################################################################################
# 1. Verificación del estado del sistema
################################################################################

check_system_status() {
    log_info "=== Verificando estado del sistema ==="
    
    # Verificar espacio en disco
    log_info "Verificando espacio en disco..."
    df -h | grep -E "^Filesystem|/$|${JENKINS_HOME}" | tee -a "$LOG_FILE"
    
    # Verificar espacio disponible (mínimo 10% libre)
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        log_warning "Espacio en disco bajo: ${disk_usage}% usado"
    else
        log_success "Espacio en disco OK: ${disk_usage}% usado"
    fi
    
    # Verificar memoria
    log_info "Verificando memoria del sistema..."
    free -h | tee -a "$LOG_FILE"
    
    # Verificar estado actual de Jenkins
    log_info "Verificando estado de Jenkins..."
    if systemctl is-active --quiet "$JENKINS_SERVICE"; then
        log_success "Jenkins está actualmente en ejecución"
        return 0
    else
        log_warning "Jenkins no está en ejecución"
        return 1
    fi
}

################################################################################
# 2. Detención segura de Jenkins
################################################################################

safe_jenkins_shutdown() {
    log_info "=== Iniciando detención segura de Jenkins ==="
    
    if ! systemctl is-active --quiet "$JENKINS_SERVICE"; then
        log_warning "Jenkins ya está detenido"
        return 0
    fi
    
    log_info "Deteniendo Jenkins..."
    systemctl stop "$JENKINS_SERVICE"
    
    # Esperar a que Jenkins se detenga completamente
    local max_wait=60
    local waited=0
    while systemctl is-active --quiet "$JENKINS_SERVICE" && [[ $waited -lt $max_wait ]]; do
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""
    
    if systemctl is-active --quiet "$JENKINS_SERVICE"; then
        log_error "Jenkins no se detuvo en ${max_wait} segundos"
        return 1
    else
        log_success "Jenkins detenido correctamente"
        return 0
    fi
}

################################################################################
# 3. Backup automático de configuraciones
################################################################################

backup_jenkins_config() {
    log_info "=== Iniciando backup de configuraciones ==="
    
    # Crear directorio de backup si no existe
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_info "Creando directorio de backup: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
    fi
    
    # Nombre del backup con timestamp
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="${BACKUP_DIR}/jenkins_backup_${timestamp}.tar.gz"
    
    log_info "Creando backup en: $backup_file"
    
    # Archivos y directorios importantes a respaldar
    local items_to_backup=(
        "config.xml"
        "jobs"
        "users"
        "plugins"
        "secrets"
        "credentials.xml"
        "secret.key"
        "secret.key.not-so-secret"
        "identity.key.enc"
        "hudson.model.UpdateCenter.xml"
    )
    
    # Crear lista de archivos existentes
    local backup_items=""
    for item in "${items_to_backup[@]}"; do
        if [[ -e "${JENKINS_HOME}/${item}" ]]; then
            backup_items="${backup_items} ${item}"
        fi
    done
    
    # Crear backup
    if tar -czf "$backup_file" -C "$JENKINS_HOME" $backup_items 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Backup creado exitosamente: $backup_file"
        
        # Mostrar tamaño del backup
        local size=$(du -h "$backup_file" | cut -f1)
        log_info "Tamaño del backup: $size"
        
        return 0
    else
        log_error "Error al crear el backup"
        return 1
    fi
}

################################################################################
# 4. Gestión de backups (mantener solo el más reciente)
################################################################################

manage_backups() {
    log_info "=== Gestionando backups antiguos ==="
    
    # Contar backups existentes
    local backup_count=$(ls -1 "${BACKUP_DIR}"/jenkins_backup_*.tar.gz 2>/dev/null | wc -l)
    log_info "Backups encontrados: $backup_count"
    
    if [[ $backup_count -gt $MAX_BACKUPS ]]; then
        log_info "Eliminando backups antiguos (manteniendo solo los ${MAX_BACKUPS} más recientes)..."
        
        # Listar backups ordenados por fecha (más antiguos primero) y eliminar los excedentes
        ls -1t "${BACKUP_DIR}"/jenkins_backup_*.tar.gz | tail -n +$((MAX_BACKUPS + 1)) | while read -r old_backup; do
            log_info "Eliminando backup antiguo: $old_backup"
            rm -f "$old_backup"
        done
        
        log_success "Backups antiguos eliminados"
    else
        log_info "No hay backups antiguos que eliminar"
    fi
    
    # Listar backups actuales
    log_info "Backups actuales:"
    ls -lh "${BACKUP_DIR}"/jenkins_backup_*.tar.gz 2>/dev/null | tee -a "$LOG_FILE"
}

################################################################################
# 5. Limpieza de archivos temporales y cache
################################################################################

cleanup_temp_files() {
    log_info "=== Limpiando archivos temporales y cache ==="
    
    local cleaned=0
    
    # Limpiar workspace builds antiguos
    if [[ -d "${JENKINS_HOME}/jobs" ]]; then
        log_info "Limpiando workspaces antiguos..."
        find "${JENKINS_HOME}/jobs" -type d -name "workspace" -exec du -sh {} \; 2>/dev/null | tee -a "$LOG_FILE"
        # Descomentar la siguiente línea para eliminar workspaces (PRECAUCIÓN)
        # find "${JENKINS_HOME}/jobs" -type d -name "workspace" -exec rm -rf {} \; 2>/dev/null
    fi
    
    # Limpiar archivos temporales
    if [[ -d "${JENKINS_HOME}/war" ]]; then
        log_info "Limpiando archivos war temporales..."
        local size_before=$(du -sh "${JENKINS_HOME}/war" 2>/dev/null | cut -f1)
        rm -rf "${JENKINS_HOME}/war"/*
        log_success "Archivos war limpiados (antes: $size_before)"
        cleaned=1
    fi
    
    # Limpiar cache de plugins
    if [[ -d "${JENKINS_HOME}/plugins" ]]; then
        log_info "Limpiando cache de plugins..."
        find "${JENKINS_HOME}/plugins" -name "*.tmp" -delete 2>/dev/null
        find "${JENKINS_HOME}/plugins" -name "*.bak" -delete 2>/dev/null
        cleaned=1
    fi
    
    # Limpiar logs antiguos (más de 30 días)
    if [[ -d "${JENKINS_HOME}/logs" ]]; then
        log_info "Limpiando logs antiguos (>30 días)..."
        find "${JENKINS_HOME}/logs" -type f -name "*.log" -mtime +30 -delete 2>/dev/null
        cleaned=1
    fi
    
    # Limpiar archivos .tmp y .lock
    log_info "Limpiando archivos temporales y locks..."
    find "${JENKINS_HOME}" -name "*.tmp" -delete 2>/dev/null
    find "${JENKINS_HOME}" -name "*.lock" -delete 2>/dev/null
    
    if [[ $cleaned -eq 1 ]]; then
        log_success "Limpieza completada"
    else
        log_info "No se encontraron archivos para limpiar"
    fi
}

################################################################################
# 6. Reinicio y verificación del servicio
################################################################################

restart_jenkins() {
    log_info "=== Iniciando Jenkins ==="
    
    systemctl start "$JENKINS_SERVICE"
    
    # Esperar a que Jenkins inicie
    log_info "Esperando a que Jenkins inicie..."
    local max_wait=120
    local waited=0
    
    while ! systemctl is-active --quiet "$JENKINS_SERVICE" && [[ $waited -lt $max_wait ]]; do
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""
    
    if systemctl is-active --quiet "$JENKINS_SERVICE"; then
        log_success "Jenkins iniciado correctamente"
        return 0
    else
        log_error "Jenkins no se inició en ${max_wait} segundos"
        return 1
    fi
}

verify_jenkins() {
    log_info "=== Verificando estado de Jenkins ==="
    
    # Verificar estado del servicio
    systemctl status "$JENKINS_SERVICE" --no-pager | tee -a "$LOG_FILE"
    
    # Verificar que el puerto esté escuchando (usualmente 8080)
    log_info "Verificando puertos en escucha..."
    netstat -tlnp 2>/dev/null | grep java || ss -tlnp | grep java | tee -a "$LOG_FILE"
    
    if systemctl is-active --quiet "$JENKINS_SERVICE"; then
        log_success "Jenkins está funcionando correctamente"
        return 0
    else
        log_error "Jenkins no está funcionando correctamente"
        return 1
    fi
}

################################################################################
# Función principal
################################################################################

main() {
    log_info "================================================"
    log_info "Iniciando script de mantenimiento de Jenkins"
    log_info "Fecha: $(date)"
    log_info "================================================"
    
    # Verificar que se ejecuta como root
    check_root
    
    # 1. Verificar estado del sistema
    check_system_status
    local jenkins_was_running=$?
    
    # 2. Detener Jenkins de forma segura
    if [[ $jenkins_was_running -eq 0 ]]; then
        if ! safe_jenkins_shutdown; then
            log_error "Error al detener Jenkins. Abortando."
            exit 1
        fi
    fi
    
    # 3. Crear backup de configuraciones
    if ! backup_jenkins_config; then
        log_error "Error al crear backup. Continuando con precaución..."
    fi
    
    # 4. Gestionar backups (eliminar antiguos)
    manage_backups
    
    # 5. Limpiar archivos temporales
    cleanup_temp_files
    
    # 6. Reiniciar Jenkins
    if [[ $jenkins_was_running -eq 0 ]]; then
        if ! restart_jenkins; then
            log_error "Error al reiniciar Jenkins"
            exit 1
        fi
        
        # 7. Verificar que Jenkins esté funcionando
        sleep 5
        verify_jenkins
    else
        log_info "Jenkins no se reiniciará porque no estaba en ejecución originalmente"
    fi
    
    log_info "================================================"
    log_success "Mantenimiento de Jenkins completado"
    log_info "================================================"
}

# Ejecutar función principal
main "$@"
