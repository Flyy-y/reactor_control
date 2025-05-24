-- Master startup script for ComputerCraft
-- Copy this file to the computer's root directory as 'startup.lua'
-- Then copy the appropriate component startup script based on computer role

print("=== Reactor Control System ===")
print("Select component to run:")
print("1. Server")
print("2. Reactor Controller") 
print("3. Battery Controller")
print("4. Display")
print("5. Exit")

write("Choice: ")
local choice = read()

if choice == "1" then
    shell.run("/reactor_control/startup/server_startup.lua")
elseif choice == "2" then
    shell.run("/reactor_control/startup/reactor_startup.lua")
elseif choice == "3" then
    shell.run("/reactor_control/startup/battery_startup.lua")
elseif choice == "4" then
    shell.run("/reactor_control/startup/display_startup.lua")
else
    print("Exiting...")
end