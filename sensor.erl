-module(sensor).
-export([start/1,add_remote/1,send_msg/4,stop_sensor/1]).

start(Sensor) -> register(Sensor,spawn(fun() -> loop(Sensor) end)).

add_remote(RemoteMachine) ->
    net_adm:ping(RemoteMachine).
send_msg(Sensor,Server,RemoteMachine,Message)->
    Sensor ! {send,Server,RemoteMachine,Message},
    io:format("Sensor ~p sent message to server: ~p~n", [Sensor, Message]).
stop_sensor(Sensor) ->
    Sensor ! {stop_sensor}.


loop(SensorName) ->
    receive
        {send,Server,RemoteMachine,Message} ->
            % Incluir apenas o nome do sensor no início da mensagem
            FormattedMessage = io_lib:format("~p: ~s", [SensorName, Message]),
            {Server,RemoteMachine} ! {self(), lists:flatten(FormattedMessage)},
            receive 
                {_,_} -> ok % Removido io:format para não imprimir resposta
            end,
            loop(SensorName);
        {stop_sensor} ->
            io:format("Sensor ~p exiting...~n", [SensorName])
    end.