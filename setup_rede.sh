#!/bin/bash
# setup_completo_balanceador.sh - Configuração de Rede, Nginx e Firewall

# Verifica se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo "Execute como root (sudo)."
    exit 1
fi

echo "================================================"
echo " ETAPA 1: CONFIGURAÇÃO DE REDE INTERNA"
echo "================================================"
echo "Placas de rede disponíveis no sistema (ignore a que já tem IP):"
ip -br link show | awk '{print $1}' | grep -v "^lo$"
echo "------------------------------------------------"

read -p "Qual é o NOME da nova placa (ex: eth1, ens19)? " IFACE
read -p "Qual será o IP interno desta VM (ex: 10.10.0.10)? " IP_ADDR

# 1. Cria a configuração da nova interface isolada
mkdir -p /etc/network/interfaces.d/
cat <<EOF > /etc/network/interfaces.d/$IFACE
auto $IFACE
iface $IFACE inet static
    address $IP_ADDR/24
EOF

# Garante que o arquivo principal lê a pasta interfaces.d
if ! grep -q "source /etc/network/interfaces.d" /etc/network/interfaces; then
    echo "source /etc/network/interfaces.d/*" >> /etc/network/interfaces
fi

# Levanta a placa imediatamente e injeta o IP a quente
ip link set $IFACE up 2>/dev/null
ip addr flush dev $IFACE 2>/dev/null
ip addr add $IP_ADDR/24 dev $IFACE

echo "------------------------------------------------"
echo "Rede configurada! Verifique se o IP $IP_ADDR aparece abaixo:"
ip a show $IFACE
echo ""

echo "================================================"
echo " ETAPA 2: CONFIGURAÇÃO DO NGINX E FIREWALL"
echo "================================================"

# VARIÁVEIS (Padronizadas para a rede 10.10.0.x)
IP_SRV_A="10.10.0.11"
IP_SRV_B="10.10.0.12"
IP_PROMETHEUS="10.10.0.5"

echo "Configurando o Nginx como Load Balancer..."
cat <<EOF > /etc/nginx/conf.d/balanceador.conf
upstream servidores_backend {
    server $IP_SRV_A:80 weight=1;
    server $IP_SRV_B:80 weight=1;
}

server {
    listen 80;
    location / {
        proxy_pass http://servidores_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}

server {
    listen 8080;
    location /stub_status {
        stub_status;
        allow 127.0.0.1;
        deny all;
    }
}
EOF
systemctl restart nginx

echo "Atualizando regras do Firewall (UFW)..."
# Remove regras antigas (se existirem) para evitar duplicidade
ufw delete allow from $IP_PROMETHEUS to any port 9100 proto tcp >/dev/null 2>&1
ufw delete allow from $IP_PROMETHEUS to any port 9113 proto tcp >/dev/null 2>&1

# Adiciona as regras corretas
ufw allow from $IP_PROMETHEUS to any port 9100 proto tcp
ufw allow from $IP_PROMETHEUS to any port 9113 proto tcp
ufw reload

echo "================================================"
echo "Balanceador atualizado com sucesso!"
echo "================================================"