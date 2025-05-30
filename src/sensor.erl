%% sensor.erl
%% Processo sensor que envia leituras periodicamente e faz reencaminhamento se necessário.
-module(sensor).
-export([start/3, stop/1]).

% Helper function to find server on local or remote node
find_server() ->
    case whereis(server) of
        undefined ->
            % Try to find server on the 'server' node
            case rpc:call('server@MacBook-Pro-de-David-2', erlang, whereis, [server]) of
                {badrpc, _} -> undefined;
                undefined -> undefined;
                RemoteServerPid -> RemoteServerPid
            end;
        LocalServerPid -> LocalServerPid
    end.

start(Name, Interval, Neighbors) ->
    process_flag(trap_exit, true),
    Pid = spawn(fun() -> loop(Name, Interval, Neighbors) end),
    register(Name, Pid),
    % Try to find server on local node first, then on server node
    ServerPid = find_server(),
    
    case ServerPid of
        undefined ->
            io:format("Server not found on any node~n");
        _ ->
            link(ServerPid),
            ServerPid ! {register, Pid}
    end,
    io:format("[~p] 🚀 Sensor iniciado com vizinhos: ~p (intervalo: ~pms)~n", [Name, Neighbors, Interval]),
    Pid.

stop(Name) ->
    case whereis(Name) of
        undefined -> {error, not_found};
        Pid -> Pid ! stop, ok
    end.

loop(Name, Interval, Neighbors) ->
    Val = rand:uniform(100),
    
    % Try to find server on local node first, then on server node
    ServerPid = find_server(),
    
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
            io:format("[~p] Recebido pedido de relay: ~p~n", [Name, Msg]),
            % Try to send to server on local node first, then on server node
            ServerPid2 = find_server(),
            case ServerPid2 of
                undefined -> 
                    io:format("[~p] ✗ Não é possível fazer relay - servidor não encontrado~n", [Name]);
                _ -> 
                    io:format("[~p] → [server] Fazendo relay da mensagem: ~p~n", [Name, Msg]),
                    ServerPid2 ! Msg
            end;
        stop ->
            io:format("[~p] ⏹ Parando sensor...~n", [Name]),
            exit(normal)
    after Interval ->
        ok
    end,

    loop(Name, Interval, Neighbors).

try_relay([], _) ->
    {error, no_path};
try_relay([N|Ns], Msg) ->
    case whereis(N) of
        undefined -> 
            io:format("Vizinho ~p não encontrado, tentando próximo...~n", [N]),
            try_relay(Ns, Msg);
        NPid      -> 
            io:format("→ [~p] Enviando mensagem para relay: ~p~n", [N, Msg]),
            NPid ! {relay, Msg}, 
            ok
    end.