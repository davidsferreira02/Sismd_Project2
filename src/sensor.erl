%% sensor.erl
%% Processo sensor que envia leituras periodicamente e faz reencaminhamento se necessário.
-module(sensor).
-export([start/2, stop/1]).

% Constante para o intervalo de envio (3 segundos)
-define(INTERVAL, 3000).

% Helper function to find server on local or remote node
% Only sensors with direct server connection (like s1) should find server directly
find_server(Name, Neighbors) ->
    HasDirectServerConnection = lists:member(server, Neighbors),
    case HasDirectServerConnection of
        true ->
            case whereis(server) of
                undefined ->
                    % Try to find server on the 'server' node
                    case rpc:call('server@MacBook-Pro-de-David-2', erlang, whereis, [server]) of
                        {badrpc, _} -> undefined;
                        undefined -> undefined;
                        RemoteServerPid -> RemoteServerPid
                    end;
                LocalServerPid -> LocalServerPid
            end;
        false ->
            io:format("[~p] 🚫 Não tem conexão direta com servidor, deve usar relay através de ~p~n", [Name, Neighbors]),
            undefined
    end.

start(Name, Neighbors) ->
    process_flag(trap_exit, true),
    Pid = spawn(fun() -> loop(Name, ?INTERVAL, Neighbors) end),
    register(Name, Pid),
    % Try to find server only if this sensor has direct connection
    ServerPid = find_server(Name, Neighbors),
    
    case ServerPid of
        undefined ->
            io:format("Server not found on any node~n");
        _ ->
            link(ServerPid),
            ServerPid ! {register, Pid}
    end,
    io:format("[~p] 🚀 Sensor iniciado com vizinhos: ~p (intervalo: ~pms)~n", [Name, Neighbors, ?INTERVAL]),
    Pid.

stop(Name) ->
    case whereis(Name) of
        undefined -> {error, not_found};
        Pid -> Pid ! stop, ok
    end.

loop(Name, Interval, Neighbors) ->
    Val = rand:uniform(100),
    
    % Try to find server only if this sensor has direct connection
    ServerPid = find_server(Name, Neighbors),
    
    case ServerPid of
        undefined ->
            io:format("[~p] Servidor não encontrado, tentando reenvio através dos vizinhos ~p~n", [Name, Neighbors]),
            case try_relay(Neighbors, {data, Name, self(), Val}) of
                ok -> io:format("[~p] ✓ Dados (valor: ~p) reenviados pela rede com sucesso~n", [Name, Val]);
                {error, no_path} -> io:format("[~p] ✗ Falha ao reenviar dados (valor: ~p) - nenhum caminho disponível~n", [Name, Val])
            end;
        _ ->
            io:format("[~p] → [server] Enviando dados diretamente (valor: ~p)~n", [Name, Val]),
            ServerPid ! {data, Name, self(), Val}
    end,

    receive
        {sensor_down, DeadPid} ->
            io:format("[~p] ⚠ Notificação: sensor ~p caiu~n", [Name, DeadPid]);
        {'EXIT', server, Why} ->
            io:format("[~p] ⚠ Servidor caiu! Motivo: ~p~n", [Name, Why]);
        {relay, Msg} ->
            io:format("[~p] 📨 Recebido pedido de relay: ~p~n", [Name, Msg]),
            % Try to send to server only if this sensor has direct connection
            ServerPid2 = find_server(Name, Neighbors),
            case ServerPid2 of
                undefined -> 
                    io:format("[~p] ↗️ Não tenho conexão direta, reenviando para vizinhos ~p~n", [Name, Neighbors]),
                    try_relay(Neighbors, Msg);
                _ -> 
                    io:format("[~p] → [server] 🔄 Fazendo relay da mensagem: ~p~n", [Name, Msg]),
                    ServerPid2 ! Msg
            end;
        stop ->
            io:format("[~p] ⏹ Parando sensor...~n", [Name]),
            exit(normal)
    after Interval ->
        ok
    end,

    loop(Name, Interval, Neighbors).

% Find a neighbor process, checking both local and remote nodes
find_neighbor(NeighborName) ->
    % First try local node
    case whereis(NeighborName) of
        undefined ->
            % Try to find on remote node with same name as the neighbor
            NodeName = list_to_atom(atom_to_list(NeighborName) ++ "@MacBook-Pro-de-David-2"),
            case rpc:call(NodeName, erlang, whereis, [NeighborName]) of
                {badrpc, Reason} -> 
                    io:format("⚠️ Erro RPC ao contactar nó ~p: ~p~n", [NodeName, Reason]),
                    undefined;
                undefined -> 
                    io:format("⚠️ Vizinho ~p não encontrado no nó ~p~n", [NeighborName, NodeName]),
                    undefined;
                RemotePid -> 
                    io:format("✅ Vizinho ~p encontrado no nó ~p~n", [NeighborName, NodeName]),
                    RemotePid
            end;
        LocalPid -> 
            io:format("✅ Vizinho ~p encontrado localmente~n", [NeighborName]),
            LocalPid
    end.

try_relay([], _) ->
    {error, no_path};
try_relay([N|Ns], Msg) ->
    case find_neighbor(N) of
        undefined -> 
            io:format("⚠️ Vizinho ~p não encontrado, tentando próximo...~n", [N]),
            try_relay(Ns, Msg);
        NPid      -> 
            io:format("📤 → [~p] Enviando mensagem para relay: ~p~n", [N, Msg]),
            NPid ! {relay, Msg}, 
            ok
    end.