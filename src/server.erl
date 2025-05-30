%% server.erl
%% Servidor central do sistema de sensores distribuído.
-module(server).
-export([start/0, loop/1]).

%% Inicia o servidor e regista-o como 'server'.
start() ->
    register(server, spawn(fun() -> loop(#{sensors => [], data => []}) end)),
    io:format("Server started.~n").

%% Estado: mapa com lista de sensores e histórico de dados.
loop(State = #{sensors := Sensors, data := Data}) ->
    receive
        %% Cadastro de novo sensor
        {register, SensorPid} ->
            Ref = erlang:monitor(process, SensorPid),
            io:format("Sensor ~p registado com monitor ~p.~n", [SensorPid, Ref]),
            loop(State#{sensors := [SensorPid|Sensors]});

        %% Recebe leitura de sensor
        {data, SensorName, SensorPid, Value} ->
            io:format("~p recebeu do Sensor ~p ~p: ~p~n", [server, SensorName, SensorPid, Value]),
            loop(State#{data := [{SensorName, SensorPid, Value}|Data]});

        %% Sensor caiu inesperadamente
        {'DOWN', _Ref, process, SensorPid, Reason} ->
            io:format("Sensor ~p caiu: ~p~n", [SensorPid, Reason]),
            Remaining = lists:delete(SensorPid, Sensors),
            %% Notifica restantes
            [S ! {sensor_down, SensorPid} || S <- Remaining],
            loop(State#{sensors := Remaining});

        Other ->
            io:format("Server recebeu mensagem desconhecida: ~p~n", [Other]),
            loop(State)
    end.