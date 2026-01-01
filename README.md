# RemoteSpyLibrary

![Lua](https://img.shields.io/badge/Lua-2C2D72?style=for-the-badge&logo=lua&logoColor=white)
![Roblox](https://img.shields.io/badge/Roblox-%23000000.svg?style=for-the-badge&logo=roblox&logoColor=white)

A high-performance Roblox library for intercepting and analyzing RemoteEvents and RemoteFunctions with complete origin tracing and script caller detection.

---

## Project Overview

RemoteSpyLibrary is a personal project designed to provide deep visibility into Roblox remote communication. The library hooks into the `__namecall` metamethod to capture every RemoteEvent and RemoteFunction invocation, then traces the complete execution context including which script fired the remote and which script loaded the library.

### Current Implementation

The library captures:
- RemoteEvent and RemoteFunction invocations
- All arguments passed (including nested tables, Vector3, CFrame, etc.)
- Return values from RemoteFunctions
- Full instance paths using optimized GetPath utility
- Script caller information (name, path, script type)
- Module loader information
- Automatic script generation for replaying captured calls

### Planned Development

This library serves as the foundation for a larger suite of Roblox debugging and reverse engineering tools. Future enhancements will include:
- GUI integration with real-time visualization
- Remote filtering and blocking capabilities
- Statistical analysis of remote usage patterns
- Export plugins for logging to external services
- Memory usage optimization for long-running sessions
- Support for additional Roblox instance types

---

## Installation

### Direct Load (Recommended)

```lua
local RemoteSpyLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/wfrefdewwss/spy/main/old.lua", true))()
```

### Local File

Save the library as `RemoteSpyLibrary.lua`:

```lua
local RemoteSpyLib = loadfile("RemoteSpyLibrary.lua")()
```

---

## Basic Usage

### Three-Line Setup

```lua
-- Load library
local RemoteSpyLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/wfrefdewwss/spy/main/old.lua", true))()

-- Create instance and set handler
local spy = RemoteSpyLib.new():onRemote(function(data)
    print(string.format("Remote fired: %s:%s()", data.object.Name, data.method))
end)

-- Start capture
spy:Start()
```

### Handling Remote Events

```lua
spy:onRemote(function(data)
    -- Remote information
    print("Remote Name:", data.object.Name)
    print("Method:", data.method)
    print("Path:", data.path)
    
    -- Caller script (who fired the remote)
    print("Caller Script:", data.callerInfo.name)
    print("Caller Path:", data.callerInfo.path)
    print("Is ModuleScript:", data.callerInfo.isModule)
    
    -- Module loader (who loaded this library)
    print("Module Script:", data.moduleCaller.name)
    print("Module Path:", data.moduleCaller.path)
    
    -- Arguments and generated code
    print("Argument Count:", #data.args)
    print("Generated Script:", data.script)
    
    -- RemoteFunction return value
    if data.returnValue then
        print("Return Value:", data.returnValue)
    end
end)
```

---

## Callback Data Structure

The callback receives a comprehensive data table:

```lua
{
    object = RemoteEvent/RemoteFunction instance,
    method = "FireServer" or "InvokeServer",
    args = { ... }, -- Array of arguments
    script = string, -- Generated executable Lua code
    caller = Instance, -- The script instance that fired the remote
    path = string, -- Full path to remote (e.g., game.ReplicatedStorage.RemoteEvent)
    timestamp = number, -- When the remote fired (tick())
    
    callerInfo = {
        name = string, -- Script name
        path = string, -- Full path to script
        source = string, -- GetFullName() result
        isModule = boolean, -- Is it a ModuleScript?
        isLocal = boolean, -- Is it a LocalScript?
        isServer = boolean, -- Is it a Script?
        fullName = string -- Complete instance name
    },
    
    moduleCaller = {
        -- Same structure as callerInfo, but for the script that loaded RemoteSpyLibrary
        name = string,
        path = string,
        -- ... etc
    },
    
    returnValue = any -- RemoteFunction return value (if captured)
}
```

---

## Advanced Features

### Method Chaining

```lua
local spy = RemoteSpyLib.new()
    :onRemote(function(data)
        -- Handler logic
    end)
    :Start() -- Fluent start

-- Control later
spy:SetEnabled(false) -- Pause
spy:Stop()           -- Full stop and unhook
```

### Access Module Caller Info

```lua
local spy = RemoteSpyLib.new()
local info = spy:GetModuleInfo()

print("Library loaded by:", info.name)
print("Module path:", info.path)
print("Script type:", info.isModule and "ModuleScript" or "LocalScript")
```

### Retrieve Call History

```lua
spy:onRemote(function(data)
    -- Process current call
end)

-- Get last 100 remote calls
local history = spy:GetHistory(100)
for _, call in ipairs(history) do
    print(call.object.Name, "fired by", call.callerInfo.name)
end

-- Clear stored history
spy:ClearHistory()
```

### Remote Statistics

```lua
-- Stats for specific remote
local stats = spy:GetStats("DamageRemote")
print("Call count:", stats.count)
print("Last called:", stats.lastCalled)

-- All remotes
local allStats = spy:GetStats()
for name, data in pairs(allStats) do
    print(string.format("%s: %d calls", name, data.count))
end
```

---

## Utility API

All utility functions are exposed for custom scripts:

```lua
local spy = RemoteSpyLib.new()

-- Get path to any instance
local path = spy:GetPath(game.Workspace.Baseplate)
print(path) -- game.Workspace.Baseplate

-- Get detailed script info
local info = spy:GetScriptInfo(game.Players.LocalPlayer.PlayerScripts.LocalScript)
print("Name:", info.name)      -- "LocalScript"
print("Path:", info.path)      -- "game.Players.LocalPlayer.PlayerScripts.LocalScript"
print("Is ModuleScript:", info.isModule)  -- false
print("Full Name:", info.fullName) -- "LocalScript"

-- Convert values to string representation
local str = spy:GetType(Vector3.new(1, 2, 3))
print(str) -- Vector3.new(1, 2, 3)

-- Format tables recursively
local tbl = spy:TableToString({player = "John", pos = Vector3.new(0, 10, 0)})
print(tbl) -- {["player"] = "John", ["pos"] = Vector3.new(0, 10, 0)}
```

---

## Complete Example: Full Trace Logger

```lua
-- Load library
local RemoteSpyLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/wfrefdewwss/spy/main/old.lua", true))()

-- Create spy instance
local spy = RemoteSpyLib.new()

-- Set up callback
spy:onRemote(function(data)
    -- Print complete trace to console
    print(string.format("\n[REMOTE] %s:%s()", data.object.Name, data.method))
    print(string.format("[CALLER] Script: %s (%s)", data.callerInfo.name, 
        data.callerInfo.isModule and "ModuleScript" or data.callerInfo.isLocal and "LocalScript" or "Script"))
    print(string.format("[CALLER] Path: %s", data.callerInfo.path))
    print(string.format("[MODULE] Loaded by: %s", data.moduleCaller.name))
    print(string.format("[MODULE] Path: %s", data.moduleCaller.path))
    print(string.rep("=", 60))
    
    -- Access details
    print("Generated Script:")
    print(data.script)
end)

-- Start capture
spy:Start()

print("RemoteSpyLibrary active - monitoring remote events")
```

---

## Compatibility

- **Roblox Executors**: Synapse X, Script-Ware, KRNL, Fluxus, Delta, Electron, Oxygen U
- **Requirements**: `getrawmetatable`, `setreadonly` or `make_writeable`, `getnamecallmethod`
- **Limitations**: Some games with advanced anti-cheat may block metamethod hooking

---

## Memory Management

The library includes automatic safeguards:
- Queue size limited to 500 entries (prevents memory overflow)
- Manual cleanup via `spy:ClearHistory()`
- Clean unhooking on `spy:Stop()`

---

## License

Public domain. Use freely in any project. No attribution required.

---

## Troubleshooting

**No remotes logged?**
- Verify your executor supports `__namecall` hooking
- Test with a known remote-heavy game
- Check console (F9) for errors
- Use the test code example to verify hook activation

**Incorrect paths?**
- Ensure the library is loaded correctly
- Check that `game` service exists and is accessible

**Performance issues?**
- Reduce callback complexity
- Avoid heavy processing in the onRemote handler
- Use `spy:SetEnabled(false)` to pause temporarily

---

**Project Repository**: https://github.com/wfrefdewwss/spy
