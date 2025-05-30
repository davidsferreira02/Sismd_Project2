# Sistema de Rede de Sensores Distribuída em Erlang

## Visão Geral do Projeto

Este projeto implementa um sistema distribuído de sensores usando Erlang, onde sensores podem comunicar com um servidor central diretamente ou através de outros sensores numa rede mesh com capacidades de failover automático e mecanismo de cascata.

### Características Principais

- **Roteamento Multi-hop**: Sensores podem encaminhar mensagens através de outros sensores para alcançar o servidor
- **Conexões Diretas ao Servidor**: Alguns sensores comunicam diretamente com o servidor
- **Failover Automático com Cascata**: Quando um sensor falha, o sistema automaticamente tenta outros vizinhos
- **Conexões Bidirecionais**: Garantia de que se A é vizinho de B, então B é vizinho de A
- **Registo em CSV**: O servidor exporta todas as mensagens para um ficheiro CSV
- **Deteção de Loops**: Sistema previne loops infinitos no encaminhamento de mensagens

## Arquitetura

### Componentes

1. **Servidor (`server.erl`)**:
   - Ponto central de recolha de dados
   - Regista todas as mensagens dos sensores com timestamps
   - Exporta dados para ficheiro CSV (`server_output.csv`)
   - Monitoriza conexões dos sensores

2. **Sensor (`sensor.erl`)**:
   - Pode operar com conexão direta ao servidor ou encaminhar através de outros sensores
   - Descoberta automática de rotas alternativas quando falhas ocorrem
   - Envio periódico de dados (a cada 3 segundos)
   - Gestão dinâmica de vizinhos (adicionar/remover)

### Topologia da Rede

O sistema suporta várias topologias:

```
Conexão Direta:
s1 ──────► server
s4 ──────► server

Roteamento Multi-hop:
s3 ──► s2 ──► s1 ──► server

Topologia Mista com Failover:
s3 ──► s1 ──► server
 │     X (falha)
 └──► s2 ──► server (rota alternativa)
```

## Código - Explicação Detalhada

### Servidor (`server.erl`)

O servidor é responsável por:

```erlang
% Iniciar o servidor
start() ->
    init_csv_file(),  % Cria ficheiro CSV com cabeçalho
    register(server, spawn(fun() -> loop(#{sensors => [], data => []}) end)),
    log_to_csv("INFO", "SERVER_START", "Server started.").
```

**Funcionalidades principais:**
- **Registo de Sensores**: Quando um sensor se conecta, o servidor cria um monitor
- **Receção de Dados**: Processa mensagens `{data, SensorName, SensorPid, Value}`
- **Registo CSV**: Cada evento é gravado em `server_output.csv` com timestamp
- **Gestão de Falhas**: Deteta quando sensores falham e notifica outros sensores

### Sensor (`sensor.erl`)

Cada sensor tem as seguintes capacidades:

```erlang
% Iniciar um sensor com lista de vizinhos
start(Name, Neighbors) ->
    Pid = spawn(fun() -> loop(Name, 3000, Neighbors) end),
    register(Name, Pid).
```

**Funcionalidades principais:**

1. **Descoberta do Servidor**: 
   ```erlang
   find_server(Name, Neighbors) ->
       HasDirectServerConnection = lists:member(server, Neighbors),
       % Se 'server' está na lista de vizinhos, tenta conexão direta
   ```

2. **Envio de Dados**:
   - Se tem conexão direta: envia diretamente ao servidor
   - Se não tem: usa mecanismo de relay através dos vizinhos

3. **Mecanismo de Relay com Cascata**:
   ```erlang
   try_relay_all([N|Ns], Msg, FailedNeighbors) ->
       case find_neighbor(N) of
           undefined -> 
               % Tenta próximo vizinho
               try_relay_all(Ns, Msg, [N|FailedNeighbors]);
           NPid -> 
               % Envia para vizinho disponível
               NPid ! {relay, Msg}, ok
       end.
   ```

4. **Gestão Bidirecional de Vizinhos**:
   ```erlang
   add_neighbor(SensorName, Neighbor) ->
       % Adiciona Neighbor como vizinho de SensorName
       % E automaticamente adiciona SensorName como vizinho de Neighbor
   ```

5. **Deteção de Loops**:
   ```erlang
   handle_relay_with_path(Name, Neighbors, Msg, Path) ->
       case lists:member(Name, Path) of
           true -> % Loop detectado, para o relay
           false -> % Continua o relay adicionando Name ao path
       end.
   ```

## Como Executar o Sistema

### Pré-requisitos

- Erlang/OTP instalado
- Múltiplas janelas de terminal
- macOS (comandos otimizados para macOS)

### Passo 1: Limpeza Inicial

```bash
pkill -f erl    # Mata todos os processos Erlang
```

### Passo 2: Iniciar o Servidor (Terminal 1)

```bash
cd /Users/davidferreira/Universidade/Isep/1Ano/2Semestre/Sismd/Project2/src
erl -sname server
```

No shell Erlang:
```erlang
c(server).
server:start().
```

### Passo 3: Iniciar Sensores

#### Terminal 2 - Sensor s1 (com conexão direta ao servidor):
```bash
erl -sname s1
```
```erlang
c(sensor).
sensor:start(s1, [server]).
```

#### Terminal 3 - Sensor s2 (sem conexão direta):
```bash
erl -sname s2
```
```erlang
c(sensor).
sensor:start(s2, []).
```

#### Terminal 4 - Sensor s3 (conhece s1 e s2):
```bash
erl -sname s3
```
```erlang
c(sensor).
sensor:start(s3, [s2, s1]).
```

#### Terminal 5 - Sensor s4 (inicialmente sem vizinhos):
```bash
erl -sname s4
```
```erlang
c(sensor).
sensor:start(s4, []).
```

### Passo 4: Gestão Dinâmica de Vizinhos

Adicionar vizinhos dinamicamente:
```erlang
% s3 adiciona s1 como vizinho (conexão bidirecional automática)
sensor:add_neighbor(s3, s1).

% s4 adiciona s2 como vizinho
sensor:add_neighbor(s4, s2).

% Listar vizinhos de um sensor
sensor:list_neighbors(s3).

% Remover vizinho
sensor:remove_neighbor(s3, s1).
```

## Cenários de Teste

### Teste 1: Funcionamento Normal

Com a configuração:
- s1 → servidor (direto)
- s3 → s2 → s1 → servidor

**Resultado esperado**:
```
[s3] Servidor não encontrado, tentando reenvio através dos vizinhos [s2,s1]
✅ Vizinho s2 encontrado no nó 's2@MacBook-Pro-de-David-2'
📤 → [s2] Enviando mensagem para relay: {data,s3,<0.97.0>,87}
[s3] ✓ Dados (valor: 87) reenviados pela rede com sucesso
```

### Teste 2: Failover Automático

1. s3 está conectado a s1 e s2
2. s2 falha (fechar terminal)
3. s3 automaticamente usa s1

**Resultado esperado**:
```
⚠️ Erro RPC ao contactar nó 's2@MacBook-Pro-de-David-2': timeout
⚠️ Vizinho s2 não encontrado, tentando próximo...
✅ Vizinho s1 encontrado no nó 's1@MacBook-Pro-de-David-2'
📤 → [s1] Enviando mensagem para relay: {data,s3,<0.97.0>,13}
[s3] ✓ Dados (valor: 13) reenviados pela rede com sucesso
```

### Teste 3: Isolamento Completo

Se s3 perde todos os vizinhos:
```
[s3] ✗ Falha ao reenviar dados (valor: 42) - nenhum caminho disponível
```

## Ficheiros Gerados

- **`server_output.csv`**: Registo de todas as atividades do servidor
  ```csv
  Timestamp,Type,Category,Message
  "2025-05-31 14:30:15","INFO","SERVER_START","Server started."
  "2025-05-31 14:30:20","DATA","SENSOR_DATA","server recebeu do Sensor s1 <0.97.0>: 45"
  ```

## API de Funções

### Servidor
- `server:start()` - Inicia o servidor
- `log_to_csv(Type, Category, Message)` - Regista evento no CSV

### Sensor
- `sensor:start(Name, Neighbors)` - Inicia sensor com lista de vizinhos
- `sensor:stop(Name)` - Para um sensor
- `sensor:add_neighbor(SensorName, Neighbor)` - Adiciona vizinho (bidirecional)
- `sensor:remove_neighbor(SensorName, Neighbor)` - Remove vizinho (bidirecional)
- `sensor:list_neighbors(SensorName)` - Lista vizinhos atuais

## Características Avançadas

### Conexões Bidirecionais Automáticas
Quando executa `sensor:add_neighbor(s3, s1)`:
- s1 é adicionado à lista de vizinhos de s3
- s3 é automaticamente adicionado à lista de vizinhos de s1

### Deteção de Loops
O sistema previne loops infinitos mantendo um registo do caminho percorrido por cada mensagem.

### Registo Completo
Todas as atividades são registadas no CSV:
- Início/paragem de sensores
- Dados recebidos
- Falhas de conexão
- Eventos de relay

Este sistema demonstra conceitos fundamentais de sistemas distribuídos incluindo tolerância a falhas, descoberta automática, e comunicação multi-hop em ambiente Erlang.
