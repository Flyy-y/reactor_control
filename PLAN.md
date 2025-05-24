# Mekanism Reactor Control System - Implementation Plan

## System Architecture

The system consists of multiple ComputerCraft computers communicating via wireless modems:

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│   Display   │     │  Central Server  │     │   Display   │
│  Computer   │◄────┤                  ├────►│  Computer   │
└─────────────┘     │  - Control Logic │     └─────────────┘
                    │  - Data Storage  │
                    │  - Decision Making│
                    └────────┬─────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│    Reactor    │   │    Reactor    │   │    Battery    │
│  Controller 1 │   │  Controller 2 │   │  Controller   │
│               │   │               │   │               │
│ - Data Reader │   │ - Data Reader │   │ - Data Reader │
│ - Control Exec│   │ - Control Exec│   │ - Status Mon. │
└───────┬───────┘   └───────┬───────┘   └───────┬───────┘
        │                    │                    │
        ▼                    ▼                    ▼
   [Reactor 1]          [Reactor 2]      [Induction Cell]
```

## Network Protocol

All communication uses a standardized message format:

```lua
{
    type = "request|response|broadcast",
    sender = "computer_id",
    target = "computer_id|all",
    command = "command_name",
    data = { ... },
    timestamp = os.epoch("utc")
}
```

### Message Types

1. **Reactor Status Update** (reactor → server)
```lua
{
    type = "broadcast",
    command = "reactor_status",
    data = {
        reactor_id = 1,
        active = true,
        temperature = 350,
        burnRate = 10,
        fuel = 950,
        waste = 50,
        coolant = 9500,
        damage = 0
    }
}
```

2. **Battery Status Update** (battery → server)
```lua
{
    type = "broadcast",
    command = "battery_status",
    data = {
        energy_stored = 1000000000,
        energy_capacity = 2000000000,
        percent_full = 50,
        input_rate = 1000,
        output_rate = 500
    }
}
```

3. **Control Command** (server → reactor)
```lua
{
    type = "request",
    command = "reactor_control",
    data = {
        action = "activate|scram|set_burn_rate",
        value = 10
    }
}
```

## Safety Rules (Server Logic)

The reactor will only run if ALL conditions are met:
- Temperature < 1200K
- Battery < 80% full
- Coolant > 95% of capacity
- Waste < 5% of capacity
- Fuel available
- No damage to reactor

## Implementation Steps

### Phase 1: Core Infrastructure
1. **Network Protocol Module** (`network.lua`)
   - Message serialization/deserialization
   - Wireless modem wrapper
   - Reliable message delivery
   - Message routing

2. **Configuration System** (`config/`)
   - Server config
   - Reactor controller config
   - Battery controller config
   - Display config

### Phase 2: Component Implementation

1. **Central Server** (`server/main.lua`)
   - Initialize wireless modem
   - Listen for status updates
   - Process safety rules
   - Send control commands
   - Store historical data
   - Handle display requests

2. **Reactor Controller** (`reactor/main.lua`)
   - Connect to reactor peripheral
   - Read reactor status periodically
   - Broadcast status to server
   - Execute control commands from server
   - Local emergency shutdown logic

3. **Battery Controller** (`battery/main.lua`)
   - Connect to induction cell
   - Read energy levels
   - Broadcast status to server
   - Monitor charge/discharge rates

4. **Display Computer** (`display/main.lua`)
   - Connect to monitor peripheral
   - Request data from server
   - Format and display:
     - Reactor statuses
     - Battery level
     - System alerts
     - Historical graphs

### Phase 3: Advanced Features

1. **Auto-Update System**
   - Modify updater to handle component-specific files
   - Different update channels for each component
   - Coordinated updates to prevent system downtime

2. **Data Persistence**
   - Historical data storage on server
   - Configuration persistence
   - State recovery after reboot

3. **Monitoring & Alerts**
   - Temperature warnings
   - Low fuel alerts
   - High waste warnings
   - Battery critical levels
   - Network connectivity issues

### Phase 4: User Interface

1. **Display Features**
   - Multi-reactor dashboard
   - Real-time graphs
   - Alert notifications
   - Control panel (if authorized)

2. **Terminal Interface**
   - Server console commands
   - Remote management
   - Debug/diagnostic tools

## File Structure

```
/reactor_control/
├── PLAN.md
├── README.md
├── shared/
│   ├── network.lua
│   ├── protocol.lua
│   └── updater.lua
├── server/
│   ├── main.lua
│   ├── rules.lua
│   ├── storage.lua
│   └── config.lua
├── reactor/
│   ├── main.lua
│   ├── reactor_api.lua
│   └── config.lua
├── battery/
│   ├── main.lua
│   ├── battery_api.lua
│   └── config.lua
├── display/
│   ├── main.lua
│   ├── ui.lua
│   └── config.lua
└── startup/
    ├── server_startup.lua
    ├── reactor_startup.lua
    ├── battery_startup.lua
    └── display_startup.lua
```

## Configuration Management

Each component will have its own config file:

### Server Config
```lua
{
    modem_channel = 100,
    reactor_channels = {101, 102},
    battery_channel = 103,
    display_channel = 104,
    update_interval = 5,
    safety_rules = {
        max_temp = 1200,
        max_battery_percent = 80,
        min_coolant_percent = 95,
        max_waste_percent = 5
    }
}
```

### Reactor Config
```lua
{
    reactor_id = 1,
    server_channel = 100,
    broadcast_channel = 101,
    update_interval = 2,
    emergency_shutdown_temp = 1400
}
```

## Testing Strategy

1. **Unit Tests**
   - Test each safety rule independently
   - Test network message handling
   - Test peripheral connections

2. **Integration Tests**
   - Test reactor-server communication
   - Test multi-reactor coordination
   - Test failover scenarios

3. **System Tests**
   - Full system startup/shutdown
   - Emergency scenarios
   - Network failure recovery

## Deployment Guide

1. Install server computer with wireless modem
2. Install reactor controllers near reactors
3. Install battery controller near induction cell
4. Install display computers with monitors
5. Configure all components with correct channels
6. Run startup scripts
7. Verify communication
8. Test safety systems

## Next Steps

1. Create shared network module
2. Implement server core functionality
3. Create reactor controller
4. Create battery controller
5. Build display system
6. Test integrated system
7. Document usage and maintenance