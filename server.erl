-module(server).
-export([start/1, demo_analysis/1]).

start(Server) -> register(Server,spawn(fun() -> 
    process_flag(trap_exit, true),
    % Load existing data from file if available
    DataStore = load_data_from_file("sensor_data.dat"),
    loop(#{}, DataStore) % Start with empty sensor map and loaded/empty data store
end)).

loop(SensorMap, DataStore) ->
    receive
        {From, stop} -> 
            io:format("Received from ~p message to stop!~n",[From]),
            % Save data before stopping
            save_data_to_file(DataStore),
            From ! {self(),server_disconnect};
        {From, get_sensor_data, SensorName} ->
            % Query function to get data for specific sensor
            SensorData = get_sensor_data_internal(SensorName, DataStore),
            From ! {self(), sensor_data, SensorData},
            loop(SensorMap, DataStore);
        {From, get_all_data} ->
            % Query function to get all stored data
            From ! {self(), all_data, DataStore},
            loop(SensorMap, DataStore);
        {From, get_statistics, SensorName} ->
            % Query function to get statistics for a sensor
            Stats = get_statistics_internal(SensorName, DataStore),
            From ! {self(), statistics, Stats},
            loop(SensorMap, DataStore);
        {From, save_data} ->
            % Manual save function
            save_data_to_file(DataStore),
            From ! {self(), data_saved},
            loop(SensorMap, DataStore);
        {From, Msg} -> 
            % Extract sensor name and message from formatted message
            {SensorName, UserMessage} = extract_sensor_info(Msg),
            % Store the data with timestamp
            Timestamp = calendar:universal_time(),
            DataEntry = #{sensor => SensorName, 
                         message => UserMessage, 
                         timestamp => Timestamp,
                         pid => From},
            NewDataStore = store_data(DataEntry, DataStore),
            io:format("Received from ~p: ~s (stored at ~p)~n",[SensorName, UserMessage, Timestamp]),
            monitor(process, From),
            % Store PID -> Name mapping
            NewSensorMap = maps:put(From, SensorName, SensorMap),
            % Send back only the user message
            From ! {self(), UserMessage},
            % Auto-save data periodically (every 10 entries)
            if length(NewDataStore) rem 10 == 0 ->
                save_data_to_file(NewDataStore);
            true -> ok
            end,
            loop(NewSensorMap, NewDataStore);
        {'DOWN', _Ref, process, Pid, Reason} ->
            % Get sensor name from map
            SensorName = maps:get(Pid, SensorMap, unknown_sensor),
            io:format("Sensor ~p failed! Reason: ~p~n", [SensorName, Reason]),
            
            % Only store disconnection event if we know the sensor name
            NewDataStore = case SensorName of
                unknown_sensor -> 
                    io:format("Warning: Unknown sensor disconnected with PID ~p~n", [Pid]),
                    DataStore; % Don't store unknown disconnections
                _ ->
                    % Store disconnection event
                    Timestamp = calendar:universal_time(),
                    DisconnectEntry = #{sensor => SensorName,
                                      message => io_lib:format("DISCONNECTED: ~p", [Reason]),
                                      timestamp => Timestamp,
                                      pid => Pid},
                    store_data(DisconnectEntry, DataStore)
            end,
            
            % Remove from map
            NewSensorMap = maps:remove(Pid, SensorMap),
            loop(NewSensorMap, NewDataStore)
    end.



% Extrair nome do sensor e mensagem da mensagem formatada
extract_sensor_info(Msg) ->
    case string:split(Msg, ": ", leading) of
        [SensorName, UserMessage] -> {list_to_atom(SensorName), UserMessage};
        _ -> {unknown_sensor, Msg}
    end.

% Data Storage Functions
store_data(DataEntry, DataStore) ->
    [DataEntry | DataStore].

% Query Functions
get_sensor_data_internal(SensorName, DataStore) ->
    lists:filter(fun(Entry) -> 
        maps:get(sensor, Entry) == SensorName 
    end, DataStore).

get_all_data(ServerPid) ->
    ServerPid ! {self(), get_all_data},
    receive
        {ServerPid, all_data, Data} -> Data
    after 5000 ->
        timeout
    end.

get_statistics(ServerPid, SensorName) ->
    ServerPid ! {self(), get_statistics, SensorName},
    receive
        {ServerPid, statistics, Stats} -> Stats
    after 5000 ->
        timeout
    end.



get_statistics_internal(SensorName, DataStore) ->
    SensorData = get_sensor_data_internal(SensorName, DataStore),
    case SensorData of
        [] -> 
            #{sensor => SensorName, 
              total_messages => 0, 
              first_message => none, 
              last_message => none,
              message_frequency => []};
        _ ->
            TotalMessages = length(SensorData),
            Timestamps = [maps:get(timestamp, Entry) || Entry <- SensorData],
            SortedTimestamps = lists:sort(Timestamps),
            FirstMessage = hd(SortedTimestamps),
            LastMessage = lists:last(SortedTimestamps),
            
            % Calculate message frequency per hour
            MessageFreq = calculate_message_frequency(SensorData),
            
            #{sensor => SensorName,
              total_messages => TotalMessages,
              first_message => FirstMessage,
              last_message => LastMessage,
              message_frequency => MessageFreq,
              recent_messages => lists:sublist(SensorData, 5)}
    end.

calculate_message_frequency(SensorData) ->
    % Group messages by hour and count them
    HourlyGroups = lists:foldl(fun(Entry, Acc) ->
        {{Year, Month, Day}, {Hour, _, _}} = maps:get(timestamp, Entry),
        HourKey = {Year, Month, Day, Hour},
        Count = maps:get(HourKey, Acc, 0),
        maps:put(HourKey, Count + 1, Acc)
    end, #{}, SensorData),
    
    % Convert to list and sort by time
    HourlyList = maps:to_list(HourlyGroups),
    lists:sort(HourlyList).

% Persistent Storage Functions
save_data_to_file(DataStore) ->
    case file:write_file("sensor_data.dat", term_to_binary(DataStore)) of
        ok -> 
            io:format("Data saved to sensor_data.dat (~p entries)~n", [length(DataStore)]),
            ok;
        {error, Reason} -> 
            io:format("Error saving data: ~p~n", [Reason]),
            error
    end.

load_data_from_file(Filename) ->
    case file:read_file(Filename) of
        {ok, Binary} ->
            try binary_to_term(Binary) of
                DataStore when is_list(DataStore) -> 
                    io:format("Loaded ~p entries from ~s~n", [length(DataStore), Filename]),
                    DataStore;
                _ -> 
                    io:format("Invalid data format in ~s, starting fresh~n", [Filename]),
                    []
            catch
                _:_ -> 
                    io:format("Error reading data from ~s, starting fresh~n", [Filename]),
                    []
            end;
        {error, enoent} ->
            io:format("No existing data file found, starting fresh~n"),
            [];
        {error, Reason} ->
            io:format("Error loading data: ~p, starting fresh~n", [Reason]),
            []
    end.

% Interactive Analysis Functions (callable from server terminal)
demo_analysis(ServerName) ->
    io:format("=== Data Analysis Demo ===~n"),
    
    % Get all stored data
    AllData = get_all_data(whereis(ServerName)),
    io:format("Total entries stored: ~p~n", [length(AllData)]),
    
    % Get unique sensors (only active ones, excluding disconnected)
    Sensors = get_active_sensors(AllData),
    io:format("Active sensors: ~p~n", [Sensors]),
    
    % Show statistics for each sensor
    lists:foreach(fun(Sensor) ->
        Stats = get_statistics(whereis(ServerName), Sensor),
        io:format("~n--- Statistics for ~p ---~n", [Sensor]),
        print_statistics(Stats)
    end, Sensors),
    
    % Export data to CSV
    case export_to_csv(AllData, "sensor_export.csv") of
        ok -> io:format("~nData exported to sensor_export.csv~n");
        _ -> io:format("~nFailed to export data~n")
    end.

% Helper functions for analysis
get_unique_sensors(Data) ->
    SensorSet = lists:foldl(fun(Entry, Acc) ->
        Sensor = maps:get(sensor, Entry),
        sets:add_element(Sensor, Acc)
    end, sets:new(), Data),
    sets:to_list(SensorSet).

% Get only active sensors (exclude those that have disconnected)
get_active_sensors(Data) ->
    % Get all sensors that have sent messages
    AllSensors = get_unique_sensors(Data),
    
    % Filter out sensors that have disconnection messages as their last message
    lists:filter(fun(Sensor) ->
        SensorData = lists:filter(fun(Entry) -> 
            maps:get(sensor, Entry) == Sensor 
        end, Data),
        
        case SensorData of
            [] -> false;
            _ -> 
                % Sort by timestamp to get the latest message
                SortedData = lists:sort(fun(A, B) ->
                    maps:get(timestamp, A) =< maps:get(timestamp, B)
                end, SensorData),
                
                LatestEntry = lists:last(SortedData),
                LatestMessage = maps:get(message, LatestEntry),
                
                % Check if latest message is a disconnection
                case LatestMessage of
                    Msg when is_list(Msg) ->
                        not lists:prefix("DISCONNECTED", Msg);
                    _ -> true
                end
        end
    end, AllSensors).

print_statistics(Stats) ->
    maps:fold(fun(Key, Value, _) ->
        case Key of
            message_frequency -> 
                io:format("  Message frequency: ~p entries~n", [length(Value)]);
            recent_messages -> 
                io:format("  Recent messages: ~p entries~n", [length(Value)]);
            _ -> 
                io:format("  ~p: ~p~n", [Key, Value])
        end
    end, ok, Stats).

% Utility Functions for Data Export
export_to_csv(DataStore, Filename) ->
    Header = "Sensor,Message,Timestamp,PID\n",
    Rows = lists:map(fun(Entry) ->
        Sensor = maps:get(sensor, Entry),
        Message = maps:get(message, Entry),
        Timestamp = format_timestamp(maps:get(timestamp, Entry)),
        PID = maps:get(pid, Entry),
        io_lib:format("~p,~s,~s,~p~n", [Sensor, Message, Timestamp, PID])
    end, lists:reverse(DataStore)),
    
    Content = [Header | Rows],
    file:write_file(Filename, Content).

format_timestamp({{Year, Month, Day}, {Hour, Min, Sec}}) ->
    io_lib:format("~4..0w-~2..0w-~2..0w ~2..0w:~2..0w:~2..0w", 
                  [Year, Month, Day, Hour, Min, Sec]).