-module(sensor).
-export([start/1,add_remote/1,send_msg/4,send_msg_via/6,set_next_hop/3,stop_sensor/1]).

start(Sensor) -> register(Sensor,spawn(fun() -> loop(Sensor, #{}) end)).

add_remote(RemoteMachine) ->
    net_adm:ping(RemoteMachine).
send_msg(Sensor,Server,RemoteMachine,Message)->
    Sensor ! {send,Server,RemoteMachine,Message},
    io:format("Sensor ~p sent message to server: ~p~n", [Sensor, Message]).

% New function to send message via another sensor
send_msg_via(Sensor, ViaSensor, ViaSensorNode, Server, RemoteMachine, Message) ->
    Sensor ! {send_via, ViaSensor, ViaSensorNode, Server, RemoteMachine, Message},
    io:format("[INIT] Sensor ~p initiating message via ~p@~p to server: ~p~n", [Sensor, ViaSensor, ViaSensorNode, Message]).

% Function to set next hop for routing to server
set_next_hop(Sensor, NextHopSensor, NextHopNode) ->
    Sensor ! {set_next_hop, NextHopSensor, NextHopNode},
    io:format("[CONFIG] Sensor ~p configured to route to server via ~p@~p~n", [Sensor, NextHopSensor, NextHopNode]).

stop_sensor(Sensor) ->
    Sensor ! {stop_sensor}.


loop(SensorName, Config) ->
    receive
        {set_next_hop, NextHopSensor, NextHopNode} ->
            NewConfig = Config#{next_hop_sensor => NextHopSensor, next_hop_node => NextHopNode},
            io:format("[CONFIG] Sensor ~p configured to route to server via ~p@~p~n", [SensorName, NextHopSensor, NextHopNode]),
            loop(SensorName, NewConfig);
        
        {send,Server,RemoteMachine,Message} ->
            % Direct send to server
            FormattedMessage = io_lib:format("~p: ~s", [SensorName, Message]),
            io:format("[DIRECT] Sensor ~p sending directly to server: ~s~n", [SensorName, Message]),
            {Server,RemoteMachine} ! {self(), lists:flatten(FormattedMessage)},
            receive 
                {_,_} -> 
                    io:format("[ACK] Sensor ~p received acknowledgment from server~n", [SensorName])
            end,
            loop(SensorName, Config);
        
        {send_via, ViaSensor, ViaSensorNode, Server, RemoteMachine, Message} ->
            % Send message via another sensor
            io:format("[ROUTING] Sensor ~p routing message via ~p@~p to server: ~s~n", [SensorName, ViaSensor, ViaSensorNode, Message]),
            {ViaSensor, ViaSensorNode} ! {route_message, SensorName, Server, RemoteMachine, Message},
            loop(SensorName, Config);
        
        {route_message, OriginSensor, Server, RemoteMachine, Message} ->
            % Check if this sensor has direct connection to server or needs to forward
            case maps:get(next_hop_sensor, Config, none) of
                none ->
                    % Direct connection to server
                    FormattedMessage = io_lib:format("~p: ~s (relayed from ~p)", [SensorName, Message, OriginSensor]),
                    io:format("[RELAY] Sensor ~p relaying message from ~p to server: ~s~n", [SensorName, OriginSensor, Message]),
                    {Server,RemoteMachine} ! {self(), lists:flatten(FormattedMessage)},
                    receive 
                        {_, _} -> 
                            io:format("[RELAY-ACK] Sensor ~p received response from server, forwarding to ~p~n", [SensorName, OriginSensor])
                    end;
                NextHopSensor ->
                    % Forward to next hop
                    NextHopNode = maps:get(next_hop_node, Config),
                    io:format("[FORWARD] Sensor ~p forwarding message from ~p via ~p@~p to server: ~s~n", [SensorName, OriginSensor, NextHopSensor, NextHopNode, Message]),
                    {NextHopSensor, NextHopNode} ! {route_message, OriginSensor, Server, RemoteMachine, Message}
            end,
            loop(SensorName, Config);
        
        {stop_sensor} ->
            io:format("[STOP] Sensor ~p exiting...~n", [SensorName])
    end.