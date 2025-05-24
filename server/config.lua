return {
    privateKey = "YOUR_PRIVATE_KEY_HERE",  -- Replace with your actual private key
    modem_channel = 100,
    reactor_channels = {101, 102, 103, 104},
    battery_channel = 110,
    display_channels = {120, 121, 122},
    
    update_interval = 5,
    heartbeat_timeout = 30,
    
    safety_rules = {
        max_temperature = 1200,
        max_battery_percent = 80,
        min_coolant_percent = 95,
        max_waste_percent = 5,
        min_fuel_percent = 10,
        max_damage_percent = 0
    },
    
    auto_control = {
        enabled = true,
        min_burn_percent = 0.1,  -- 0.1% of max burn rate when battery > 80%
        max_burn_percent = 80,   -- 80% of max burn rate when battery < 10%
        battery_high = 80,       -- Battery % to start reducing burn rate
        battery_low = 10,        -- Battery % to start increasing burn rate
        ramp_rate = 0.5          -- mB/t change per update cycle
    },
    
    alerts = {
        temperature_warning = 1000,
        temperature_critical = 1100,
        waste_warning = 3,
        fuel_warning = 20,
        battery_warning = 90,
        coolant_warning = 97
    },
    
    logging = {
        enabled = true,
        max_entries = 1000,
        file = "server.log"
    },
    
    data_retention = {
        history_size = 500,
        save_interval = 60
    }
}