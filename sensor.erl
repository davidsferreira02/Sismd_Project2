-module(sensor).
-export([start/1,add_remote/1,send_msg/4,send_msg_via/6,set_direct_server_connection/2,set_next_hop/3,stop_sensor/1,discover_sensors/1]).

start(Sensor) -> register(Sensor,spawn(fun() -> loop(Sensor, #{has_direct_server_connection => false}) end)).

add_remote(RemoteMachine) ->
    net_adm:ping(RemoteMachine).

send_msg(Sensor,Server,RemoteMachine,Message)->
    Sensor ! {send,Server,RemoteMachine,Message},
    io:format("Sensor ~p sent message to server: ~p~n", [Sensor, Message]).

% New function to send message via another sensor
send_msg_via(Sensor, ViaSensor, ViaSensorNode, Server, RemoteMachine, Message) ->
    Sensor ! {send_via, ViaSensor, ViaSensorNode, Server, RemoteMachine, Message},
    io:format("[INIT] Sensor ~p initiating message via ~p@~p to server: ~p~n", [Sensor, ViaSensor, ViaSensorNode, Message]).

% Function to set direct server connection flag
set_direct_server_connection(Sensor, HasDirectConnection) ->
    Sensor ! {set_direct_connection, HasDirectConnection},
    io:format("[CONFIG] Sensor ~p direct server connection flag set to: ~p~n", [Sensor, HasDirectConnection]).

% Function to set next hop for routing to server
set_next_hop(Sensor, NextHopSensor, NextHopNode) ->
    Sensor ! {set_next_hop, NextHopSensor, NextHopNode},
    io:format("[CONFIG] Sensor ~p configured to route to server via ~p@~p~n", [Sensor, NextHopSensor, NextHopNode]).

stop_sensor(Sensor) ->
    Sensor ! {stop_sensor}.

% Function to discover available sensors with direct server connection
discover_sensors(CurrentSensor) ->
    % Get all connected nodes
    Nodes = nodes(),
    AvailableSensors = lists:foldl(fun(Node, Acc) ->
        % Check if node has a sensor process and if it has direct server connection
        case rpc:call(Node, erlang, whereis, [CurrentSensor]) of
            undefined ->
                % Try to find any registered sensor on this node
                case rpc:call(Node, erlang, registered, []) of
                    {badrpc, _} -> Acc;
                    RegisteredProcesses ->
                        % Look for sensor processes (assuming they start with 'sensor')
                        SensorProcesses = lists:filter(fun(ProcessName) ->
                            ProcessNameStr = atom_to_list(ProcessName),
                            string:find(ProcessNameStr, "sensor") =/= nomatch
                        end, RegisteredProcesses),
                        
                        % Check each sensor process for direct server connection
                        lists:foldl(fun(SensorName, InnerAcc) ->
                            case rpc:call(Node, SensorName, get_config, []) of
                                {ok, Config} ->
                                    HasDirectConnection = maps:get(has_direct_server_connection, Config, false),
                                    if HasDirectConnection ->
                                        [{SensorName, Node} | InnerAcc];
                                    true -> InnerAcc
                                    end;
                                _ -> InnerAcc
                            end
                        end, Acc, SensorProcesses)
                end;
            _ -> Acc
        end
    end, [], Nodes),
    AvailableSensors.

% Check if a specific sensor process is available on a node
check_sensor_availability(SensorName, Node) ->
    try
        case rpc:call(Node, erlang, whereis, [SensorName]) of
            undefined -> false;
            Pid when is_pid(Pid) -> 
                % Additional check: try to ping the process
                try
                    {SensorName, Node} ! {self(), get_config},
                    receive
                        {ok, _Config} -> true
                    after 1000 ->
                        false
                    end
                catch
                    _:_ -> false
                end;
            _ -> false
        end
    catch
        _:_ -> false
    end.

% Simplified function to discover alternative sensor with direct server connection
discover_alternative_sensor(CurrentSensor) ->
    Nodes = nodes(),
    io:format("[DISCOVERY] Sensor ~p scanning ~p nodes for alternatives...~n", [CurrentSensor, length(Nodes)]),
    % Try to find any sensor with direct server connection on available nodes
    case find_direct_sensor_simple(Nodes, CurrentSensor) of
        {ok, {SensorName, Node}} ->
            io:format("[DISCOVERY] Sensor ~p found alternative ~p@~p with direct connection~n", [CurrentSensor, SensorName, Node]),
            {ok, {SensorName, Node}};
        not_found ->
            io:format("[DISCOVERY] Sensor ~p could not find any alternative sensors~n", [CurrentSensor]),
            {error, no_sensors_found}
    end.

% Simplified helper function to find a sensor with direct server connection
find_direct_sensor_simple([], _CurrentSensor) ->
    not_found;
find_direct_sensor_simple([Node|RestNodes], CurrentSensor) ->
    % Try common sensor names on each node
    io:format("[DISCOVERY] Checking node ~p for available sensors...~n", [Node]),
    CommonSensorNames = [sensor1, sensor2, sensor3, sensor4, sensor5],
    case try_sensors_on_node(CommonSensorNames, Node, CurrentSensor) of
        {ok, SensorName} ->
            {ok, {SensorName, Node}};
        not_found ->
            find_direct_sensor_simple(RestNodes, CurrentSensor)
    end.

% Try to contact sensors on a specific node
try_sensors_on_node([], _Node, _CurrentSensor) ->
    not_found;
try_sensors_on_node([SensorName|RestSensors], Node, CurrentSensor) when SensorName =/= CurrentSensor ->
    try
        {SensorName, Node} ! {self(), get_config},
        receive
            {ok, Config} ->
                HasDirectConnection = maps:get(has_direct_server_connection, Config, false),
                if HasDirectConnection ->
                    {ok, SensorName};
                true ->
                    try_sensors_on_node(RestSensors, Node, CurrentSensor)
                end
        after 1000 ->
            try_sensors_on_node(RestSensors, Node, CurrentSensor)
        end
    catch
        _:_ ->
            try_sensors_on_node(RestSensors, Node, CurrentSensor)
    end;
try_sensors_on_node([_SensorName|RestSensors], Node, CurrentSensor) ->
    % Skip current sensor
    try_sensors_on_node(RestSensors, Node, CurrentSensor).


loop(SensorName, Config) ->
    receive
        {From, get_config} ->
            From ! {ok, Config},
            loop(SensorName, Config);
            
        {set_direct_connection, HasDirectConnection} ->
            NewConfig = Config#{has_direct_server_connection => HasDirectConnection},
            io:format("[CONFIG] Sensor ~p direct server connection flag updated to: ~p~n", [SensorName, HasDirectConnection]),
            loop(SensorName, NewConfig);
        
        {set_next_hop, NextHopSensor, NextHopNode} ->
            NewConfig = Config#{next_hop_sensor => NextHopSensor, next_hop_node => NextHopNode},
            io:format("[CONFIG] Sensor ~p configured to route to server via ~p@~p~n", [SensorName, NextHopSensor, NextHopNode]),
            loop(SensorName, NewConfig);
        
        {send,Server,RemoteMachine,Message} ->
            % Direct send to server
            HasDirectConnection = maps:get(has_direct_server_connection, Config, true),
            FormattedMessage = io_lib:format("~p: ~s", [SensorName, Message]),
            io:format("[DIRECT] Sensor ~p sending directly to server: ~s (direct connection: ~p)~n", [SensorName, Message, HasDirectConnection]),
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
            % Check if this sensor has direct connection to server or can forward to next hop
            HasDirectConnection = maps:get(has_direct_server_connection, Config, false),
            NextHopSensor = maps:get(next_hop_sensor, Config, none),
            NextHopNode = maps:get(next_hop_node, Config, none),
            
            case {HasDirectConnection, NextHopSensor} of
                {true, _} ->
                    % Direct connection to server
                    FormattedMessage = io_lib:format("~p: ~s (relayed from ~p)", [SensorName, Message, OriginSensor]),
                    io:format("[RELAY] Sensor ~p relaying message from ~p to server: ~s (direct connection: true)~n", [SensorName, OriginSensor, Message]),
                    {Server,RemoteMachine} ! {self(), lists:flatten(FormattedMessage)},
                    receive 
                        {_, _} -> 
                            io:format("[RELAY-ACK] Sensor ~p received response from server, forwarding to ~p~n", [SensorName, OriginSensor])
                    end;
                {false, none} ->
                    % No direct connection and no next hop configured - try to discover available sensors
                    io:format("[DISCOVERY] Sensor ~p has no next hop, discovering sensors with direct server connection...~n", [SensorName]),
                    case discover_alternative_sensor(SensorName) of
                        {ok, {AlternativeSensor, AlternativeNode}} ->
                            io:format("[DISCOVERY] Sensor ~p found alternative sensor ~p@~p, forwarding message~n", [SensorName, AlternativeSensor, AlternativeNode]),
                            {AlternativeSensor, AlternativeNode} ! {route_message, OriginSensor, Server, RemoteMachine, Message};
                        {error, no_sensors_found} ->
                            io:format("[ERROR] Sensor ~p could not find any sensors with direct server connection for message from ~p~n", [SensorName, OriginSensor])
                    end;
                {false, NextHop} when NextHopNode =/= none ->
                    % Try to forward to configured next hop - check both node connectivity and sensor process availability
                    case {net_adm:ping(NextHopNode), check_sensor_availability(NextHop, NextHopNode)} of
                        {pong, true} ->
                            % Next hop is available, forward message
                            io:format("[FORWARD] Sensor ~p forwarding message from ~p via ~p@~p to server: ~s (direct connection: false)~n", [SensorName, OriginSensor, NextHop, NextHopNode, Message]),
                            {NextHop, NextHopNode} ! {route_message, OriginSensor, Server, RemoteMachine, Message};
                        {pong, false} ->
                            % Node is reachable but sensor process is not available
                            io:format("[FAILURE] Next hop sensor ~p@~p process not available, discovering alternative sensors...~n", [NextHop, NextHopNode]),
                            case discover_alternative_sensor(SensorName) of
                                {ok, {AlternativeSensor, AlternativeNode}} ->
                                    io:format("[RECOVERY] Sensor ~p using alternative sensor ~p@~p after sensor process failure~n", [SensorName, AlternativeSensor, AlternativeNode]),
                                    % Update configuration with new next hop
                                    NewConfig = Config#{next_hop_sensor => AlternativeSensor, next_hop_node => AlternativeNode},
                                    {AlternativeSensor, AlternativeNode} ! {route_message, OriginSensor, Server, RemoteMachine, Message},
                                    loop(SensorName, NewConfig);
                                {error, no_sensors_found} ->
                                    io:format("[ERROR] Sensor ~p could not find alternative sensors after sensor process failure for message from ~p~n", [SensorName, OriginSensor])
                            end;
                        {pang, _} ->
                            % Node not reachable, try to discover alternative sensors
                            io:format("[FAILURE] Next hop node ~p@~p not reachable, discovering alternative sensors...~n", [NextHop, NextHopNode]),
                            case discover_alternative_sensor(SensorName) of
                                {ok, {AlternativeSensor, AlternativeNode}} ->
                                    io:format("[RECOVERY] Sensor ~p using alternative sensor ~p@~p after node failure~n", [SensorName, AlternativeSensor, AlternativeNode]),
                                    % Update configuration with new next hop
                                    NewConfig = Config#{next_hop_sensor => AlternativeSensor, next_hop_node => AlternativeNode},
                                    {AlternativeSensor, AlternativeNode} ! {route_message, OriginSensor, Server, RemoteMachine, Message},
                                    loop(SensorName, NewConfig);
                                {error, no_sensors_found} ->
                                    io:format("[ERROR] Sensor ~p could not find alternative sensors after node failure for message from ~p~n", [SensorName, OriginSensor])
                            end
                    end
            end,
            loop(SensorName, Config);
        
        {stop_sensor} ->
            io:format("[STOP] Sensor ~p exiting...~n", [SensorName])
    end.