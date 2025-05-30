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
    io:format("Sensor ~p iniciado.~n", [Name]),
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
            case try_relay(Neighbors, {data, Name, self(), Val}) of
                ok -> io:format("~p reenviou pela rede.~n", [Name]);
                {error, no_path} -> io:format("~p não conseguiu enviar.~n", [Name])
            end;
        _ ->
            ServerPid ! {data, Name, self(), Val}
    end,

    receive
        {sensor_down, DeadPid} ->
            io:format("~p notificado que ~p caiu.~n", [Name, DeadPid]);
        {'EXIT', server, Why} ->
            io:format("~p detectou server caído: ~p~n", [Name, Why]);
        {relay, Msg} ->
            % Try to send to server on local node first, then on server node
            ServerPid2 = find_server(),
            case ServerPid2 of
                undefined -> io:format("~p cannot relay, server not found~n", [Name]);
                _ -> ServerPid2 ! Msg
            end;
        stop ->
            io:format("~p será parado.~n", [Name]),
            exit(normal)
    after Interval ->
        ok
    end,

    loop(Name, Interval, Neighbors).

try_relay([], _) ->
    {error, no_path};
try_relay([N|Ns], Msg) ->
    case whereis(N) of
        undefined -> try_relay(Ns, Msg);
        NPid      -> NPid ! {relay, Msg}, ok
    end.