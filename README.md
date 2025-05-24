# Reactor Control System

Simple, secure control system for Mekanism nuclear reactors in ComputerCraft with touchscreen controls.

## Quick Start

1. **Download installer on each computer:**
```
wget https://raw.githubusercontent.com/Flyy-y/reactor_control/main/installer.lua installer
```

2. **Run installer:**
```
installer
```

3. **Follow prompts to:**
   - Set/enter private key (must be same on all computers)
   - Choose component type
   - Auto-configure settings

## Components

- **Server**: Brain of the system (1 required)
- **Reactor Controller**: Controls a reactor (1 per reactor)
- **Battery Controller**: Monitors energy storage (optional)
- **Display**: Shows status on monitor with touchscreen controls (optional)

## Safety Features

Reactors automatically shut down if:
- Temperature > 1200K
- Battery > 80% full
- Coolant < 95%
- Waste > 5%
- Damage detected

## Requirements

- ComputerCraft computers with wireless modems
- Mekanism Fission Reactor with Logic Adapter
- Mekanism Induction Matrix (for battery monitoring)

## Controls

### Keyboard
- Press **Q** to shutdown any component
- Press **E** on reactor controller for emergency SCRAM

### Touchscreen (on Display)
- **START/SCRAM** buttons for each reactor
- **-1/+1** buttons to adjust burn rate
- **SCRAM ALL** - Emergency stop all reactors
- **START ALL** - Start all reactors

## Troubleshooting

**"No reactor/battery found"**
→ Check peripheral connections

**Components not communicating**
→ Verify all use same private key

**Need help?**
→ Check the full documentation in PLAN.md