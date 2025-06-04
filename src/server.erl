
-module(server).
-export([start/0, loop/1, log_to_csv/3]).

start() ->
    
    init_csv_file(),
    register(server, spawn(fun() -> loop(#{sensors => [], data => []}) end)),
    Message = "Server started.",
    io:format("~s~n", [Message]),
    log_to_csv("INFO", "SERVER_START", Message).


loop(State = #{sensors := Sensors, data := Data}) ->
    receive
       
        {register, SensorPid} ->
            Ref = erlang:monitor(process, SensorPid),
            Message = io_lib:format("Sensor ~p registado com monitor ~p.", [SensorPid, Ref]),
            io:format("~s~n", [Message]),
            log_to_csv("INFO", "SENSOR_REGISTER", lists:flatten(Message)),
            loop(State#{sensors := [SensorPid|Sensors]});

       
        {data, SensorName, SensorPid, Value} ->
            Message = io_lib:format("~p recebeu do Sensor ~p ~p: ~p", [server, SensorName, SensorPid, Value]),
            io:format("~s~n", [Message]),
            log_to_csv("DATA", "SENSOR_DATA", lists:flatten(Message)),
            loop(State#{data := [{SensorName, SensorPid, Value}|Data]});


        {'DOWN', _Ref, process, SensorPid, Reason} ->
            Message = io_lib:format("Sensor ~p caiu: ~p", [SensorPid, Reason]),
            io:format("~s~n", [Message]),
            log_to_csv("ERROR", "SENSOR_DOWN", lists:flatten(Message)),
            Remaining = lists:delete(SensorPid, Sensors),
           
            [S ! {sensor_down, SensorPid} || S <- Remaining],
            loop(State#{sensors := Remaining});

        Other ->
            Message = io_lib:format("Server recebeu mensagem desconhecida: ~p", [Other]),
            io:format("~s~n", [Message]),
            log_to_csv("WARNING", "UNKNOWN_MESSAGE", lists:flatten(Message)),
            loop(State)
    end.


init_csv_file() ->
    FileName = "server_output.csv",
    Header = "Timestamp,Type,Category,Message\n",
    file:write_file(FileName, Header).

log_to_csv(Type, Category, Message) ->
    FileName = "server_output.csv",
    {{Year, Month, Day}, {Hour, Minute, Second}} = calendar:local_time(),
    Timestamp = io_lib:format("~4..0w-~2..0w-~2..0w ~2..0w:~2..0w:~2..0w", 
                             [Year, Month, Day, Hour, Minute, Second]),
    
    CleanMessage = re:replace(Message, "[\r\n]+", " ", [global, {return, list}]),
    EscapedMessage = re:replace(CleanMessage, "\"", "\"\"", [global, {return, list}]),
    
    Line = io_lib:format("\"~s\",\"~s\",\"~s\",\"~s\"\n", 
                        [lists:flatten(Timestamp), Type, Category, EscapedMessage]),
    file:write_file(FileName, Line, [append]).