from fastapi import FastAPI
from datetime import datetime
import os
import math

app = FastAPI()

# Captura o nome do servidor através de uma variável de ambiente.
# Isso permite usar o mesmo código no Servidor A e no Servidor B.
SERVER_NAME = os.getenv("SERVER_NAME", "Servidor Desconhecido")

@app.get("/")
def read_root():
    """
    Rota principal: informa qual instância respondeu e retorna data/hora[cite: 2].
    """
    return {
        "instancia": SERVER_NAME,
        "data_hora": datetime.now().isoformat(),
        "mensagem": "Requisição recebida com sucesso via Nginx Balanceador."
    }

@app.get("/health")
def health_check():
    """
    Rota de verificação de saúde[cite: 2].
    """
    return {"status": "UP", "instancia": SERVER_NAME}

@app.get("/stress")
def cpu_stress(limite: int = 50000):
    """
    Rota de carga artificial: calcula números primos até o 'limite' especificado.
    Objetivo: provocar alto consumo de CPU temporário e aumento na latência de resposta[cite: 2].
    """
    def is_prime(n):
        if n <= 1:
            return False
        for i in range(2, int(math.sqrt(n)) + 1):
            if n % i == 0:
                return False
        return True

    primos = []
    # Processamento pesado proposital[cite: 2]
    for i in range(2, limite):
        if is_prime(i):
            primos.append(i)

    return {
        "instancia": SERVER_NAME,
        "mensagem": f"Cálculo concluído. Encontrados {len(primos)} números primos.",
        "limite_utilizado": limite
    }