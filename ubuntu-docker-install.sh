#!/bin/bash

# Colores para la salida
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Función para imprimir mensajes
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Función para validar IP
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        for i in {1..4}; do
            if [[ $(echo "$ip" | cut -d. -f$i) -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Función para validar dominio
validate_domain() {
    if [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Verificar si se está ejecutando como root
if [ "$EUID" -ne 0 ]; then 
    print_error "Este script debe ejecutarse como root"
    exit 1
fi

# Solicitar IP
while true; do
    read -p "Ingrese la IP del servidor: " SERVER_IP
    if validate_ip "$SERVER_IP"; then
        break
    else
        print_error "IP inválida. Por favor, intente nuevamente."
    fi
done

# Solicitar dominio
while true; do
    read -p "Ingrese el dominio a utilizar: " DOMAIN
    if validate_domain "$DOMAIN"; then
        break
    else
        print_error "Dominio inválido. Por favor, intente nuevamente."
    fi
done

# Actualizar el sistema
print_message "Actualizando el sistema..."
apt-get update && apt-get upgrade -y

# Instalar dependencias necesarias
print_message "Instalando dependencias..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common

# Agregar la clave GPG oficial de Docker
print_message "Configurando repositorio de Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Configurar el repositorio
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Actualizar la base de datos de paquetes
apt-get update

# Instalar Docker
print_message "Instalando Docker..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verificar la instalación de Docker
if ! systemctl is-active --quiet docker; then
    print_error "Error al instalar Docker"
    exit 1
fi

# Crear red de Docker para Portainer
print_message "Creando red de Docker..."
docker network create portainer_network

# Instalar Portainer
print_message "Instalando Portainer..."
docker volume create portainer_data
docker run -d \
    --name portainer \
    --restart=always \
    --network portainer_network \
    -p 8000:8000 \
    -p 9443:9443 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest

# Verificar la instalación de Portainer
if ! docker ps | grep -q portainer; then
    print_error "Error al instalar Portainer"
    exit 1
fi

# Mostrar información final
print_message "Instalación completada exitosamente!"
echo -e "\nInformación importante:"
echo "- Docker y Portainer han sido instalados"
echo "- Portainer está disponible en:"
echo "  * HTTPS: https://$SERVER_IP:9443"
echo "  * HTTP: http://$SERVER_IP:9000"
echo "- Dominio configurado: $DOMAIN"
echo -e "\nRecuerde:"
echo "1. Al acceder por primera vez a Portainer, deberá crear una contraseña de administrador"
echo "2. Para verificar el estado de los servicios use: docker ps"

# Verificar si Docker está funcionando
if docker info >/dev/null 2>&1; then
    print_message "Docker está funcionando correctamente"
else
    print_warning "Docker está instalado pero podría haber problemas. Verifique el estado con 'docker info'"
fi
