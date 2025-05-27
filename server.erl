-module(server).
-export([start/1]).

start(Server) -> register(Server,spawn(fun() -> 
    process_flag(trap_exit, true),
    loop(#{}) % Iniciar com mapa vazio para armazenar PID->Nome
end)).

loop(SensorMap) ->
    receive
        {From, stop} -> 
            io:format("Received from ~p message to stop!~n",[From]),
            From ! {self(),server_disconnect};
        {From, Msg} -> 
            % Extrair nome do sensor e mensagem da mensagem formatada
            {SensorName, UserMessage} = extract_sensor_info(Msg),
            io:format("Received from ~p: ~s~n",[SensorName, UserMessage]),
            monitor(process, From),
            % Armazenar mapeamento PID -> Nome
            NewSensorMap = maps:put(From, SensorName, SensorMap),
            % Enviar de volta apenas a mensagem do usuário
            From ! {self(), UserMessage},
            loop(NewSensorMap);
        {'DOWN', _Ref, process, Pid, Reason} ->
            % Obter nome do sensor do mapa
            SensorName = maps:get(Pid, SensorMap, unknown_sensor),
            io:format("Sensor ~p failed! Reason: ~p~n", [SensorName, Reason]),
            % Remover do mapa
            NewSensorMap = maps:remove(Pid, SensorMap),
            loop(NewSensorMap)
    end.



% Extrair nome do sensor e mensagem da mensagem formatada
extract_sensor_info(Msg) ->
    case string:split(Msg, ": ", leading) of
        [SensorName, UserMessage] -> {list_to_atom(SensorName), UserMessage};
        _ -> {unknown_sensor, Msg}
    end.