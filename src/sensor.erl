
-module(sensor).
-export([start/2, stop/1, add_neighbor/2, remove_neighbor/2, list_neighbors/1]).

-define(INTERVAL, 3000).


find_server(Name, Neighbors) ->
    HasDirectServerConnection = lists:member(server, Neighbors),
    case HasDirectServerConnection of
        true ->
            case whereis(server) of
                undefined ->                
                case rpc:call('server@MacBook-Pro-de-David-2', erlang, whereis, [server], 1000) of
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
    Pid = spawn(fun() -> loop(Name, ?INTERVAL, Neighbors, []) end), 
    register(Name, Pid),

    ServerPid = find_server(Name, Neighbors),
    
    case ServerPid of
        undefined ->
            io:format("Server not found on any node~n");
        _ ->
            link(ServerPid),
            ServerPid ! {register, Pid}
    end,
    
    
    notify_neighbors_of_birth(Name, Neighbors),
    
   
    Pid ! start_timer,
    
    io:format("[~p] 🚀 Sensor iniciado com vizinhos: ~p (intervalo: ~pms)~n", [Name, Neighbors, ?INTERVAL]),
    Pid.

stop(Name) ->
    case whereis(Name) of
        undefined -> {error, not_found};
        Pid -> 
            
            Pid ! {notify_death_and_stop},
            ok
    end.


add_neighbor(SensorName, Neighbor) ->
    case whereis(SensorName) of
        undefined -> {error, sensor_not_found};
        Pid -> 
            Pid ! {add_neighbor, Neighbor},
            io:format("[~p] ➕ Adicionando vizinho: ~p~n", [SensorName, Neighbor]),
            
            case find_neighbor(Neighbor) of
                undefined -> 
                    io:format("[~p] ⚠️ Não foi possível encontrar sensor ~p para adicionar conexão bidirecional~n", [SensorName, Neighbor]);
                NeighborPid -> 
                    NeighborPid ! {add_neighbor_silent, SensorName},
                    io:format("[~p] ↔️ Conexão bidirecional estabelecida com ~p~n", [SensorName, Neighbor])
            end,
            ok
    end.


remove_neighbor(SensorName, Neighbor) ->
    case whereis(SensorName) of
        undefined -> {error, sensor_not_found};
        Pid -> 
            Pid ! {remove_neighbor, Neighbor},
            io:format("[~p] ➖ Removendo vizinho: ~p~n", [SensorName, Neighbor]),
           
            case find_neighbor(Neighbor) of
                undefined -> 
                    io:format("[~p] ⚠️ Não foi possível encontrar sensor ~p para remover conexão bidirecional~n", [SensorName, Neighbor]);
                NeighborPid -> 
                    NeighborPid ! {remove_neighbor_silent, SensorName},
                    io:format("[~p] ↔️ Conexão bidirecional removida com ~p~n", [SensorName, Neighbor])
            end,
            ok
    end.

list_neighbors(SensorName) ->
    case whereis(SensorName) of
        undefined -> {error, sensor_not_found};
        Pid -> 
            Pid ! {list_neighbors, self()},
            receive
                {neighbors, Neighbors} -> {ok, Neighbors}
            after 1000 ->
                {error, timeout}
            end
    end.


notify_neighbors_of_death(Name, Neighbors) ->
    io:format("[~p] 💀 Notificando vizinhos ~p que vou morrer...~n", [Name, Neighbors]),
    lists:foreach(fun(Neighbor) ->
        case find_neighbor(Neighbor) of
            undefined -> 
                io:format("[~p] ⚠️ Não foi possível encontrar vizinho ~p para notificar morte~n", [Name, Neighbor]);
            NeighborPid -> 
                io:format("[~p] → [~p] Enviando notificação de morte~n", [Name, Neighbor]),
                NeighborPid ! {sensor_died, Name}
        end
    end, Neighbors).


notify_neighbors_of_birth(Name, Neighbors) ->
    io:format("[~p] 🐣 Notificando vizinhos ~p que nasci...~n", [Name, Neighbors]),
    lists:foreach(fun(Neighbor) ->
        case find_neighbor(Neighbor) of
            undefined -> 
                io:format("[~p] ⚠️ Não foi possível encontrar vizinho ~p para notificar nascimento~n", [Name, Neighbor]);
            NeighborPid -> 
                io:format("[~p] → [~p] Enviando notificação de nascimento~n", [Name, Neighbor]),
                NeighborPid ! {sensor_born, Name}
        end
    end, Neighbors).

send_sensor_data(Name, Neighbors) ->
    Val = rand:uniform(100),
    
  
    ServerPid = find_server(Name, Neighbors),
    
    case ServerPid of
        undefined ->
            io:format("[~p] Servidor não encontrado, tentando reenvio através dos vizinhos ~p~n", [Name, Neighbors]),
            case try_relay(Neighbors, {data, Name, self(), Val}) of
                ok -> io:format("[~p] ✓ Dados (valor: ~p) reenviados pela rede com sucesso~n", [Name, Val]);
                {error, no_path} -> io:format("[~p] ✗ Falha ao reenviar dados (valor: ~p) - nenhum caminho disponível~n", [Name, Val]);
                {error, no_neighbors} -> io:format("[~p] ✗ Falha ao reenviar dados (valor: ~p) - nenhum vizinho disponível~n", [Name, Val])
            end;
        _ ->
            io:format("[~p] → [server] Enviando dados diretamente (valor: ~p)~n", [Name, Val]),
            ServerPid ! {data, Name, self(), Val}
    end.

loop(Name, Interval, Neighbors, KnownBy) ->
    receive
        start_timer ->
           
            send_sensor_data(Name, Neighbors),
            erlang:send_after(Interval, self(), send_data),
            loop(Name, Interval, Neighbors, KnownBy);
        send_data ->
            
            send_sensor_data(Name, Neighbors),
            erlang:send_after(Interval, self(), send_data),
            loop(Name, Interval, Neighbors, KnownBy);
        {sensor_down, DeadPid} ->
            io:format("[~p] ⚠ Notificação: sensor ~p caiu~n", [Name, DeadPid]),
            loop(Name, Interval, Neighbors, KnownBy);
        {'EXIT', server, Why} ->
            io:format("[~p] ⚠ Servidor caiu! Motivo: ~p~n", [Name, Why]),
            loop(Name, Interval, Neighbors, KnownBy);
        {relay, Msg} ->
            io:format("[~p] 📨 Recebido pedido de relay: ~p~n", [Name, Msg]),
            handle_relay(Name, Neighbors, Msg),
            loop(Name, Interval, Neighbors, KnownBy);
        {relay_with_path, Msg, Path} ->
            io:format("[~p] 📨 Recebido pedido de relay com caminho ~p: ~p~n", [Name, Path, Msg]),
            handle_relay_with_path(Name, Neighbors, Msg, Path),
            loop(Name, Interval, Neighbors, KnownBy);
        {add_neighbor, Neighbor} ->
            UpdatedNeighbors = case lists:member(Neighbor, Neighbors) of
                true -> 
                    io:format("[~p] ⚠️ Vizinho ~p já existe na lista~n", [Name, Neighbor]),
                    Neighbors;
                false -> 
                    NewNeighbors = [Neighbor | Neighbors],
                    io:format("[~p] ✅ Vizinho ~p adicionado. Novos vizinhos: ~p~n", [Name, Neighbor, NewNeighbors]),
                    NewNeighbors
            end,
            loop(Name, Interval, UpdatedNeighbors, KnownBy);
        {remove_neighbor, Neighbor} ->
            UpdatedNeighbors = case lists:member(Neighbor, Neighbors) of
                false -> 
                    io:format("[~p] ⚠️ Vizinho ~p não existe na lista~n", [Name, Neighbor]),
                    Neighbors;
                true -> 
                    NewNeighbors = lists:delete(Neighbor, Neighbors),
                    io:format("[~p] ✅ Vizinho ~p removido. Novos vizinhos: ~p~n", [Name, Neighbor, NewNeighbors]),
                    NewNeighbors
            end,
            loop(Name, Interval, UpdatedNeighbors, KnownBy);
        {add_neighbor_silent, Neighbor} ->
          
            UpdatedNeighbors = case lists:member(Neighbor, Neighbors) of
                true -> Neighbors;
                false -> [Neighbor | Neighbors]
            end,
            loop(Name, Interval, UpdatedNeighbors, KnownBy);
        {remove_neighbor_silent, Neighbor} ->
        
            UpdatedNeighbors = lists:delete(Neighbor, Neighbors),
            loop(Name, Interval, UpdatedNeighbors, KnownBy);
        {list_neighbors, From} ->
            From ! {neighbors, Neighbors},
            loop(Name, Interval, Neighbors, KnownBy);
        {sensor_born, NewSensor} ->
            io:format("[~p] 🐣 Vizinho ~p nasceu, adicionando à lista de quem me conhece~n", [Name, NewSensor]),
            UpdatedKnownBy = case lists:member(NewSensor, KnownBy) of
                true -> KnownBy;
                false -> [NewSensor | KnownBy]
            end,
            io:format("[~p] ✅ Lista de quem me conhece atualizada: ~p~n", [Name, UpdatedKnownBy]),
            loop(Name, Interval, Neighbors, UpdatedKnownBy);
        {sensor_died, DeadSensor} ->
            io:format("[~p] 💀 Vizinho ~p morreu, removendo da lista de vizinhos e de quem me conhece~n", [Name, DeadSensor]),
            UpdatedNeighbors = lists:delete(DeadSensor, Neighbors),
            UpdatedKnownBy = lists:delete(DeadSensor, KnownBy),
            io:format("[~p] ✅ Lista de vizinhos atualizada: ~p~n", [Name, UpdatedNeighbors]),
            io:format("[~p] ✅ Lista de quem me conhece atualizada: ~p~n", [Name, UpdatedKnownBy]),
            loop(Name, Interval, UpdatedNeighbors, UpdatedKnownBy);
        {notify_death_and_stop} ->
            io:format("[~p] ⏹ Notificando vizinhos e quem me conhece que vou morrer...~n", [Name]),
         
            AllToNotify = lists:usort(Neighbors ++ KnownBy),
            notify_neighbors_of_death(Name, AllToNotify),
            exit(normal);
        stop ->
            io:format("[~p] ⏹ Parando sensor...~n", [Name]),
            exit(normal)
    end.

find_neighbor(NeighborName) ->

    case whereis(NeighborName) of
        undefined ->
    
            NodeName = list_to_atom(atom_to_list(NeighborName) ++ "@MacBook-Pro-de-David-2"),
            case rpc:call(NodeName, erlang, whereis, [NeighborName], 1000) of
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


try_relay(Neighbors, Msg) ->
    try_relay_all(Neighbors, Msg, []).

try_relay_all([], _, FailedNeighbors) ->
    case FailedNeighbors of
        [] -> {error, no_neighbors};
        _ -> 
            io:format("⚠️ Todos os vizinhos falharam: ~p~n", [FailedNeighbors]),
            {error, no_path}
    end;
try_relay_all([N|Ns], Msg, FailedNeighbors) ->
    case find_neighbor(N) of
        undefined -> 
            io:format("⚠️ Vizinho ~p não encontrado (possivelmente morreu), tentando próximo...~n", [N]),
            try_relay_all(Ns, Msg, [N|FailedNeighbors]);
        NPid      -> 
            io:format("📤 → [~p] Enviando mensagem para relay: ~p~n", [N, Msg]),
            NPid ! {relay, Msg}, 
            ok
    end.

handle_relay(Name, Neighbors, Msg) ->
   
    ServerPid = find_server(Name, Neighbors),
    case ServerPid of
        undefined -> 
            io:format("[~p] ↗️ Não tenho conexão direta, reenviando para vizinhos ~p~n", [Name, Neighbors]),
            case try_relay_with_path(Neighbors, Msg, [Name]) of
                ok -> io:format("[~p] ✓ Relay bem sucedido através dos vizinhos~n", [Name]);
                {error, no_path} -> io:format("[~p] ✗ Falha no relay - nenhum caminho disponível~n", [Name])
            end;
        _ -> 
            io:format("[~p] → [server] 🔄 Fazendo relay da mensagem: ~p~n", [Name, Msg]),
            ServerPid ! Msg
    end.

handle_relay_with_path(Name, Neighbors, Msg, Path) ->

    case lists:member(Name, Path) of
        true ->
            io:format("[~p] 🔄 Loop detectado no caminho ~p, parando relay~n", [Name, Path]);
        false ->
            ServerPid = find_server(Name, Neighbors),
            case ServerPid of
                undefined -> 
                    NewPath = [Name | Path],
                    io:format("[~p] ↗️ Não tenho conexão direta, reenviando para vizinhos ~p (caminho: ~p)~n", [Name, Neighbors, NewPath]),
                    case try_relay_with_path(Neighbors, Msg, NewPath) of
                        ok -> io:format("[~p] ✓ Relay bem sucedido através dos vizinhos~n", [Name]);
                        {error, no_path} -> io:format("[~p] ✗ Falha no relay - nenhum caminho disponível~n", [Name])
                    end;
                _ -> 
                    io:format("[~p] → [server] 🔄 Fazendo relay da mensagem: ~p (caminho: ~p)~n", [Name, Msg, Path]),
                    ServerPid ! Msg
            end
    end.


try_relay_with_path(Neighbors, Msg, Path) ->
    try_relay_with_path_all(Neighbors, Msg, Path, []).

try_relay_with_path_all([], _, _, FailedNeighbors) ->
    case FailedNeighbors of
        [] -> {error, no_neighbors};
        _ -> 
            io:format("⚠️ Todos os vizinhos falharam: ~p~n", [FailedNeighbors]),
            {error, no_path}
    end;
try_relay_with_path_all([N|Ns], Msg, Path, FailedNeighbors) ->
  
    case lists:member(N, Path) of
        true ->
            io:format("⚠️ Vizinho ~p já está no caminho ~p, ignorando para evitar loop~n", [N, Path]),
            try_relay_with_path_all(Ns, Msg, Path, [N|FailedNeighbors]);
        false ->
            case find_neighbor(N) of
                undefined -> 
                    io:format("⚠️ Vizinho ~p não encontrado (possivelmente morreu), tentando próximo...~n", [N]),
                    try_relay_with_path_all(Ns, Msg, Path, [N|FailedNeighbors]);
                NPid      -> 
                    io:format("📤 → [~p] Enviando mensagem para relay com caminho ~p: ~p~n", [N, Path, Msg]),
                    NPid ! {relay_with_path, Msg, Path}, 
                    ok
            end
    end.