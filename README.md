# Erlang Sensor Network Routing System

## Project Overview

This project implements a distributed sensor network routing system using Erlang. The system consists of sensors that can communicate with a central server either directly or through other sensors, creating a mesh network with automatic failover capabilities.

### Key Features

- **Multi-hop Routing**: Sensors can route messages through other sensors to reach the server
- **Direct Server Connections**: Some sensors can communicate directly with the server
- **Automatic Failover**: When a sensor fails, the system automatically discovers alternative routes
- **Data Persistence**: The server stores all sensor data with timestamps and exports to CSV
- **Network Discovery**: Sensors can discover available alternatives when routes fail
- **Real-time Monitoring**: The server provides statistics and analysis capabilities

## Architecture

### Components

1. **Server (`server.erl`)**: 
   - Central data collection point
   - Stores sensor messages with timestamps
   - Provides data analysis and export capabilities
   - Monitors sensor connections and handles failures

2. **Sensor (`sensor.erl`)**:
   - Can operate with direct server connection or route through other sensors
   - Automatically discovers alternative routes when failures occur
   - Configurable routing paths and connection settings

### Network Topology

The system supports various network topologies:

```
Direct Connection:
Sensor1 ──────► Server
Sensor4 ──────► Server

Multi-hop Routing:
Sensor3 ──► Sensor2 ──► Sensor1 ──► Server

Mixed Topology:
Sensor3 ──► Sensor2 ──► Sensor1 ──► Server
            │           Sensor4 ──► Server
            └──────────► Server (fallback)
```

## Setup Instructions

### Prerequisites

- Erlang/OTP installed on your system
- Multiple terminal windows for running different nodes
- macOS environment (commands optimized for macOS)

### Installation

1. Clone or download the project files to your workspace:
   ```
   /Users/davidferreira/Universidade/Isep/1Ano/2Semestre/Sismd/Project2/
   ```

2. Ensure you have the following files:
   - `server.erl` - Server implementation
   - `sensor.erl` - Sensor implementation
   - `quick_test.txt` - Testing instructions
   - `test_failure_recovery.txt` - Failure recovery tests

## Testing Guide

### Initial Cleanup

Before starting any test, clean up any existing Erlang processes:

```bash
pkill -f erl
```

### Basic Setup

#### 1. Start the Server (Terminal 1)

```bash
erl -sname server_node
```

In the Erlang shell:
```erlang
c(server).
server:start(my_server).
```

#### 2. Start Sensor 1 - Direct Server Connection (Terminal 2)

```bash
erl -sname sensor1_node
```

In the Erlang shell:
```erlang
c(sensor).
sensor:start(sensor1).
sensor:add_remote('server_node@MacBook-Pro-de-David-2').
sensor:set_direct_server_connection(sensor1, true).
```

#### 3. Start Sensor 2 - Routes via Sensor 1 (Terminal 3)

```bash
erl -sname sensor2_node
```

In the Erlang shell:
```erlang
c(sensor).
sensor:start(sensor2).
sensor:add_remote('sensor1_node@MacBook-Pro-de-David-2').
sensor:set_next_hop(sensor2, sensor1, 'sensor1_node@MacBook-Pro-de-David-2').
```

#### 4. Start Sensor 3 - Routes via Sensor 2 (Terminal 4)

```bash
erl -sname sensor3_node
```

In the Erlang shell:
```erlang
c(sensor).
sensor:start(sensor3).
sensor:add_remote('sensor2_node@MacBook-Pro-de-David-2').
sensor:set_next_hop(sensor3, sensor2, 'sensor2_node@MacBook-Pro-de-David-2').
```

#### 5. Start Sensor 4 - Alternative Direct Connection (Terminal 5)

```bash
erl -sname sensor4_node
```

In the Erlang shell:
```erlang
c(sensor).
sensor:start(sensor4).
sensor:add_remote('server_node@MacBook-Pro-de-David-2').
sensor:set_direct_server_connection(sensor4, true).
```

**Note**: Replace `MacBook-Pro-de-David-2` with your actual machine hostname. You can find it by running `hostname` in your terminal.

### Test Scenarios

#### Test 1: Two-Hop Routing (sensor2 → sensor1 → server)

In sensor2 terminal:
```erlang
sensor:send_msg_via(sensor2, sensor1, 'sensor1_node@MacBook-Pro-de-David-2', my_server, 'server_node@MacBook-Pro-de-David-2', "Temperature 25C").
```

**Expected Output**:
```
[INIT] Sensor sensor2 initiating message via sensor1@sensor1_node@MacBook-Pro-de-David-2 to server: Temperature 25C
[ROUTING] Sensor sensor2 routing message via sensor1@sensor1_node@MacBook-Pro-de-David-2 to server: Temperature 25C
[RELAY] Sensor sensor1 relaying message from sensor2 to server: Temperature 25C (direct connection: true)
[RELAY-ACK] Sensor sensor1 received response from server, forwarding to sensor2
Server receives: "sensor1: Temperature 25C (relayed from sensor2)"
```

#### Test 2: Three-Hop Routing (sensor3 → sensor2 → sensor1 → server)

In sensor3 terminal:
```erlang
sensor:send_msg_via(sensor3, sensor2, 'sensor2_node@MacBook-Pro-de-David-2', my_server, 'server_node@MacBook-Pro-de-David-2', "Humidity 65%").
```

**Expected Output**:
```
[INIT] Sensor sensor3 initiating message via sensor2@sensor2_node@MacBook-Pro-de-David-2 to server: Humidity 65%
[ROUTING] Sensor sensor3 routing message via sensor2@sensor2_node@MacBook-Pro-de-David-2 to server: Humidity 65%
[FORWARD] Sensor sensor2 forwarding message from sensor3 via sensor1@sensor1_node@MacBook-Pro-de-David-2 to server: Humidity 65% (direct connection: false)
[RELAY] Sensor sensor1 relaying message from sensor3 to server: Humidity 65% (direct connection: true)
[RELAY-ACK] Sensor sensor1 received response from server, forwarding to sensor3
Server receives: "sensor1: Humidity 65% (relayed from sensor3)"
```

#### Test 3: Failure Recovery

**Step 1**: Simulate sensor1 failure in sensor1 terminal:
```erlang
sensor:stop_sensor(sensor1).
```

**Step 2**: Test automatic recovery in sensor3 terminal:
```erlang
sensor:send_msg_via(sensor3, sensor2, 'sensor2_node@MacBook-Pro-de-David-2', my_server, 'server_node@MacBook-Pro-de-David-2', "Pressure 1013 hPa").
```

**Expected Output**:
```
[STOP] Sensor sensor1 exiting...
[INIT] Sensor sensor3 initiating message via sensor2@sensor2_node@MacBook-Pro-de-David-2 to server: Pressure 1013 hPa
[ROUTING] Sensor sensor3 routing message via sensor2@sensor2_node@MacBook-Pro-de-David-2 to server: Pressure 1013 hPa
[FAILURE] Next hop sensor1@sensor1_node@MacBook-Pro-de-David-2 failed, discovering alternative sensors...
[DISCOVERY] Sensor sensor2 scanning X nodes for alternatives...
[DISCOVERY] Checking node sensor4_node@MacBook-Pro-de-David-2 for available sensors...
[DISCOVERY] Sensor sensor2 found alternative sensor4@sensor4_node@MacBook-Pro-de-David-2 with direct connection
[RECOVERY] Sensor sensor2 using alternative sensor sensor4@sensor4_node@MacBook-Pro-de-David-2 after node failure
```

### Data Analysis and Verification

#### View Server Data

In the server terminal:
```erlang
server:demo_analysis(my_server).
```

This will display:
- Total number of stored messages
- Statistics for each active sensor
- Message frequency analysis
- Export data to `sensor_export.csv`

#### Manual Data Queries

Get all data:
```erlang
AllData = server:get_all_data(whereis(my_server)).
```

Get statistics for a specific sensor:
```erlang
Stats = server:get_statistics(whereis(my_server), sensor1).
```

### Files Generated

After testing, the following files will be created:
- `sensor_data.dat` - Binary data storage
- `sensor_export.csv` - CSV export of all sensor data

## API Reference

### Server Functions

- `server:start(ServerName)` - Start the server process
- `server:demo_analysis(ServerName)` - Run data analysis and export
- `server:get_all_data(ServerPid)` - Get all stored data
- `server:get_statistics(ServerPid, SensorName)` - Get sensor statistics

### Sensor Functions

- `sensor:start(SensorName)` - Start a sensor process
- `sensor:add_remote(RemoteNode)` - Connect to a remote node
- `sensor:set_direct_server_connection(Sensor, Boolean)` - Configure direct server access
- `sensor:set_next_hop(Sensor, NextSensor, NextNode)` - Configure routing path
- `sensor:send_msg_via(Sensor, ViaSensor, ViaNode, Server, ServerNode, Message)` - Send message via another sensor
- `sensor:stop_sensor(Sensor)` - Stop a sensor process
- `sensor:discover_sensors(Sensor)` - Discover available sensors

## Troubleshooting

### Common Issues

1. **Node Connection Problems**:
   - Ensure all nodes can ping each other
   - Check hostname resolution (`hostname` command)
   - Verify firewall settings

2. **Sensor Not Found**:
   - Ensure sensor processes are started and registered
   - Check node names match exactly
   - Verify network connectivity

3. **Message Routing Failures**:
   - Check sensor configuration (direct connection vs. routing)
   - Verify next hop sensors are available
   - Ensure proper node naming

### Debug Commands

Check registered processes:
```erlang
registered().
```

Check connected nodes:
```erlang
nodes().
```

Ping a remote node:
```erlang
net_adm:ping('node_name@hostname').
```

Check process status:
```erlang
whereis(sensor_name).
```

## Advanced Features

### Automatic Discovery

The system includes intelligent sensor discovery that:
- Scans all connected nodes for available sensors
- Identifies sensors with direct server connections
- Automatically updates routing configuration when failures occur
- Provides fallback mechanisms for network resilience

### Data Persistence

The server automatically:
- Saves data every 10 messages
- Loads existing data on startup
- Exports data to CSV format
- Maintains message timestamps and source tracking

### Monitoring and Analytics

Built-in analysis features:
- Message frequency calculation
- Sensor activity statistics
- Connection status monitoring
- Historical data analysis

This system demonstrates key concepts in distributed systems including fault tolerance, automatic discovery, and multi-hop communication in an Erlang environment.
