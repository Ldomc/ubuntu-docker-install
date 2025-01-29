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

# Función para validar token de Cloudflare
validate_cloudflare_token() {
    if [[ $1 =~ ^eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*$ ]]; then
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

# Solicitar token de Cloudflare
while true; do
    read -p "Ingrese el token de Cloudflare Tunnel: " CLOUDFLARE_TOKEN
    if validate_cloudflare_token "$CLOUDFLARE_TOKEN"; then
        break
    else
        print_error "Token inválido. Debe ser un token JWT válido."
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

# Crear red de Docker para Portainer y Cloudflare
print_message "Creando red de Docker..."
docker network create proxy_network

# Instalar Portainer
print_message "Instalando Portainer..."
docker volume create portainer_data
docker run -d \
    --name portainer \
    --restart=always \
    --network proxy_network \
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

# Crear directorio para Cloudflare
mkdir -p /opt/cloudflared
cd /opt/cloudflared

# Crear archivo docker-compose para Cloudflare Tunnel
print_message "Configurando Cloudflare Tunnel..."
cat > docker-compose.yml << EOL
version: '3.8'
services:
  cloudflared:
    container_name: cloudflared
    image: cloudflare/cloudflared:latest
    restart: unless-stopped
    command: tunnel --no-autoupdate run --token ${CLOUDFLARE_TOKEN}
    networks:
      - proxy_network

networks:
  proxy_network:
    external: true
EOL

# Iniciar Cloudflare Tunnel
print_message "Iniciando Cloudflare Tunnel..."
docker compose up -d

# Verificar que Cloudflare Tunnel está corriendo
if ! docker ps | grep -q cloudflared; then
    print_error "Error al iniciar Cloudflare Tunnel"
    exit 1
fi

# Mostrar información final
print_message "Instalación completada exitosamente!"
echo -e "\nInformación importante:"
echo "- Docker, Portainer y Cloudflare Tunnel han sido instalados"
echo "- Portainer está disponible localmente en:"
echo "  * HTTPS: https://$SERVER_IP:9443"
echo "  * HTTP: http://$SERVER_IP:9000"
echo "- Dominio configurado: $DOMAIN"
echo "- Cloudflare Tunnel está ejecutándose y redirigiendo el tráfico"
echo -e "\nRecuerde:"
echo "1. Puede acceder a Portainer a través de su dominio Cloudflare configurado"
echo "2. Al acceder por primera vez a Portainer, deberá crear una contraseña de administrador"
echo "3. Los logs de Cloudflare Tunnel se pueden ver con: docker logs cloudflared"
echo "4. Para verificar el estado del túnel: docker ps | grep cloudflared"

# Verificar si todos los servicios están funcionando
if docker info >/dev/null 2>&1; then
    print_message "Docker está funcionando correctamente"
else
    print_warning "Docker está instalado pero podría haber problemas. Verifique el estado con 'docker info'"
fi

if docker ps | grep -q cloudflared; then
    print_message "Cloudflare Tunnel está funcionando correctamente"
else
    print_warning "Cloudflare Tunnel está instalado pero podría haber problemas. Verifique los logs con 'docker logs cloudflared'"
fi
