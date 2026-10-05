# Documentação de Infraestrutura e Monitoramento: Nginx, Prometheus e Grafana

Este documento detalha a arquitetura, as configurações e o plano de testes do ambiente distribuído com balanceamento de carga e observabilidade.

## 1. Topologia de Rede e Arquitetura

O ambiente foi provisionado em uma rede privada isolada (`10.10.0.0/24`). O acesso aos exporters é restrito via firewall (UFW) exclusivamente ao IP do Prometheus (VM 4).

| Hostname | IP | Função | Portas Expostas |
| :--- | :--- | :--- | :--- |
| **TX-BALANCEADOR** (VM 1) | `10.10.0.10` | Nginx Load Balancer (Proxy Reverso) | `80` (Web), `8080` (stub_status interno), `9100`, `9113` |
| **TX-SRV-A** (VM 2) | `10.10.0.11` | Backend A (Nginx + FastAPI) | `80`, `5000` (FastAPI em 127.0.0.1), `9100`, `9113` |
| **TX-SRV-B** (VM 3) | `10.10.0.12` | Backend B (Nginx + FastAPI) | `80`, `5000` (FastAPI em 127.0.0.1), `9100`, `9113` |
| **TX-GRAFANA** (VM 4) | `10.10.0.5` | Prometheus Server e Grafana OSS | `9090` (Prometheus), `3000` (Grafana) |

---

## 2. Inicialização da Aplicação (Backends)

Em **TX-SRV-A** e **TX-SRV-B**, a aplicação FastAPI escuta estritamente na interface de loopback (`127.0.0.1`), garantindo que o tráfego passe obrigatoriamente pelo proxy reverso do Nginx.

**Comando de execução (Servidor A):**

```bash
NOME_INSTANCIA="Servidor A" uvicorn main:app --host 127.0.0.1 --port 5000

```

**Comando de execução (Servidor B):**

```bash
NOME_INSTANCIA="Servidor B" uvicorn main:app --host 127.0.0.1 --port 5000

```

---

## 3. Plano de Experimentos e Testes de Carga

Os comandos abaixo devem ser executados a partir da **TX-GRAFANA (VM 4)** ou de um terminal externo na mesma rede para gerar o tráfego HTTP controlado e validar os cenários no dashboard.

### Cenário 1: Funcionamento normal (Round Robin)

**Objetivo:** Demonstrar a alternância de respostas e distribuição 50/50 pelo balanceador.

* **Comando:**

```bash
siege -c 30 -t 3M http://10.10.0.10/

```

* **Evidência no Grafana:** O painel "Processed connections" ou "Requests per second" (Nginx Exporter) exibirá as linhas de `TX-SRV-A` e `TX-SRV-B` recebendo o mesmo volume de tráfego simultaneamente.

### Cenário 2: Aumento de carga (Stress de CPU)

**Objetivo:** Elevar o uso de processamento atingindo a rota `/stress` (cálculo de números primos).

* **Comando:**

```bash
ab -n 1000 -c 50 http://10.10.0.10/stress?limite=100000

```

* **Evidência no Grafana:** O painel de "CPU Load" (Node Exporter) exibirá um pico acentuado de uso de CPU em ambos os nós de backend.

### Cenário 3: Falha e Recuperação de um backend (Alta Disponibilidade)

**Objetivo:** Interromper um nó temporariamente para validar o redirecionamento automático pelo Nginx, e restaurá-lo em seguida para confirmar o reequilíbrio da carga.

* **Passo 1 (Carga):** Inicie uma carga contínua a partir da VM 4:

```bash
siege -c 20 -t 3M http://10.10.0.10/

```

* **Passo 2 (Falha):** No terminal do **TX-SRV-B (VM 3)**, simule a queda da aplicação matando a porta 5000:

```bash
sudo fuser -k 5000/tcp

```

* **Passo 3 (Recuperação):** Ainda no **TX-SRV-B**, reinicie a aplicação para simular o retorno do servidor à rede:

```bash
NOME_INSTANCIA="Servidor B" uvicorn main:app --host 127.0.0.1 --port 5000

```

* **Evidência no Grafana:**
* *Durante a falha:* O tráfego processado pelo `TX-SRV-B` cairá para 0 e a linha do `TX-SRV-A` dobrará de volume para absorver a carga. A taxa de disponibilidade do sistema no `siege` continuará em 100%.
* *Após a recuperação:* O Nginx identificará o retorno do backend e o gráfico voltará a mostrar o tráfego dividido perfeitamente (50/50).

### Cenário 4: Estratégia alternativa (Pesos/Weight)

**Objetivo:** Alterar o algoritmo de balanceamento e comparar com a configuração inicial.

* **Passo 1:** No terminal do **TX-BALANCEADOR (VM 1)**, edite o arquivo de configuração:

```bash
sudo nano /etc/nginx/conf.d/balanceador.conf

```

* **Passo 2:** Altere o bloco `upstream` para aplicar pesos diferentes (75% / 25%):

```nginx
upstream servidores_backend {
    server 10.10.0.11:80 weight=3;
    server 10.10.0.12:80 weight=1;
}

```

* **Passo 3:** Recarregue as configurações do Nginx a quente (sem derrubar o tráfego atual):

```bash
sudo nginx -s reload

```

* **Evidência no Grafana:** Ao rodar novamente o `siege`, o gráfico mostrará o `TX-SRV-A` recebendo aproximadamente o triplo de conexões em comparação ao `TX-SRV-B`.
