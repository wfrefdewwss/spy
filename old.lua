-- RemoteSpyLibrary.lua
-- Enhanced Edition: Full origin tracing

local RemoteSpyLibrary = {}
RemoteSpyLibrary.__index = RemoteSpyLibrary

-- Config
local CONFIG = {
    MaxQueueSize = 500,
    DefaultEnabled = true,
    CaptureReturnValues = true,
    EnableStats = true,
}

-- Internal state
local game_meta = getrawmetatable(game)
local game_namecall = game_meta.__namecall
local namecall_queue = {}
local is_hooked = false
local self_ref = nil
local module_caller_script = nil
local remote_stats = {}
local call_history = {}

-- =========================================
-- UTILITY FUNCTIONS (Public API)
-- =========================================

function RemoteSpyLibrary:GetPath(obj)
    if not obj or obj == game then return "nil -- Invalid" end
    local parts = {}
    while obj ~= game do
        if not obj then return "nil -- Path broken" end
        table.insert(parts, 1, obj.Parent == game and obj.ClassName or tostring(obj))
        obj = obj.Parent
    end
    local path = "game:GetService(\"" .. parts[1] .. "\")"
    for i = 2, #parts do
        local part = parts[i]
        path = path .. (part:match("^[%a_][%w_]*$") and "." .. part or "[\"" .. part:gsub('"', '\\"') .. "\"]")
    end
    return path
end

function RemoteSpyLibrary:GetScriptInfo(script)
    if not script or typeof(script) ~= "Instance" or not script:IsA("LuaSourceContainer") then
        return {
            name = "Unknown",
            path = "nil -- Not a script",
            source = "N/A",
            isModule = false,
            isLocal = false,
            isServer = false,
            fullName = "N/A"
        }
    end
    
    return {
        name = script.Name,
        path = self:GetPath(script),
        source = script:GetFullName(),
        isModule = script:IsA("ModuleScript"),
        isLocal = script:IsA("LocalScript"),
        isServer = script:IsA("Script"),
        fullName = script:GetFullName()
    }
end

function RemoteSpyLibrary:GetType(val)
    local typeMap = {
        EnumItem = function() return "Enum." .. tostring(val.EnumType) .. "." .. val.Name end,
        Instance = function() return self_ref:GetPath(val) end,
        CFrame = function() return "CFrame.new(" .. tostring(val) .. ")" end,
        Vector3 = function() return "Vector3.new(" .. tostring(val) .. ")" end,
        BrickColor = function() return "BrickColor.new(\"" .. tostring(val) .. "\")" end,
        Color3 = function() return "Color3.new(" .. tostring(val) .. ")" end,
        string = function() return "\"" .. tostring(val):gsub('"', '\\"') .. "\"" end,
        Ray = function() return "Ray.new(Vector3.new(" .. tostring(val.Origin) .. "), Vector3.new(" .. tostring(val.Direction) .. "))" end,
        table = function() return self_ref:TableToString(val) end
    }
    local handler = typeMap[typeof(val)]
    return handler and handler() or tostring(val)
end

function RemoteSpyLibrary:TableToString(t, depth)
    depth = depth or 0
    if depth > 10 then return "\"<max depth>\"" end
    local parts = {}
    for k, v in pairs(t) do
        local key = type(k) == "number" and "[" .. k .. "]" or "[\"" .. k .. "\"]"
        local val = type(v) == "table" and self_ref:TableToString(v, depth + 1) or self_ref:GetType(v)
        table.insert(parts, key .. " = " .. val)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

function RemoteSpyLibrary:GenerateScript(obj, method, args, callerInfo, moduleInfo)
    local path = self:GetPath(obj)
    local script = "-- RemoteSpy Log\n"
    script = script .. "-- Remote Path: " .. path .. "\n"
    
    if callerInfo then
        script = script .. "-- Caller Script: " .. callerInfo.name .. "\n"
        script = script .. "-- Caller Path: " .. callerInfo.path .. "\n"
        script = script .. "-- Caller Type: " .. (callerInfo.isModule and "ModuleScript" or callerInfo.isLocal and "LocalScript" or "Script") .. "\n"
    end
    
    if moduleInfo then
        script = script .. "-- Module Script: " .. moduleInfo.name .. "\n"
        script = script .. "-- Module Path: " .. moduleInfo.path .. "\n"
    end
    
    script = script .. "-- Timestamp: " .. tick() .. "\n\n"
    
    for i, v in ipairs(args) do
        script = script .. "local Arg_" .. i .. " = " .. self:GetType(v) .. "\n"
    end
    
    script = script .. "\nlocal Remote = " .. path .. "\n\n"
    script = script .. "Remote:" .. method .. "(" .. table.concat({"Arg_1", "Arg_2", "Arg_3", "Arg_4", "Arg_5"}, ", "):gsub(", Arg_[0-9]+$", "") .. ")"
    return script
end

function RemoteSpyLibrary:GetModuleCaller()
    if module_caller_script then
        return self:GetScriptInfo(module_caller_script)
    end
    return {
        name = "Unknown",
        path = "nil -- Could not determine",
        source = "N/A",
        isModule = false,
        isLocal = false,
        isServer = false,
        fullName = "N/A"
    }
end

-- =========================================
-- CORE PROCESSING
-- =========================================

local function processQueue()
    while #namecall_queue > 0 do
        -- Check queue size limit
        if #namecall_queue > CONFIG.MaxQueueSize then
            table.remove(namecall_queue, 1)
        end
        
        local data = table.remove(namecall_queue, 1)
        local remote = data.object
        
        -- Get full script info
        local callerInfo = self_ref:GetScriptInfo(data.caller)
        local moduleInfo = self_ref:GetModuleCaller()
        
        -- Generate enhanced script
        data.script = self_ref:GenerateScript(remote, data.method, data.args, callerInfo, moduleInfo)
        data.callerInfo = callerInfo
        data.moduleCaller = moduleInfo
        data.path = self_ref:GetPath(remote)
        
        -- Update stats
        if CONFIG.EnableStats then
            remote_stats[remote.Name] = remote_stats[remote.Name] or {count = 0, lastCalled = 0}
            remote_stats[remote.Name].count = remote_stats[remote.Name].count + 1
            remote_stats[remote.Name].lastCalled = tick()
        end
        
        -- Store in history
        table.insert(call_history, data)
        
        -- User callback
        if self_ref.config.Callback then
            pcall(self_ref.config.Callback, data)
        end
    end
end

-- Hook function
local function onNamecall(obj, ...)
    local method = getnamecallmethod()
    local args = {...}
    local timestamp = tick()
    
    if obj.Name ~= "CharacterSoundEvent" and method:match("Server") and self_ref.config.Enabled then
        local returnValue = nil
        
        -- Capture return values for RemoteFunctions
        if obj.ClassName == "RemoteFunction" and method == "InvokeServer" and self_ref.config.CaptureReturnValues then
            local success, result = pcall(function() return obj:InvokeServer(unpack(args)) end)
            if success then returnValue = result end
        end
        
        -- Get calling environment
        local caller = getfenv(2).script
        
        -- Queue for processing
        table.insert(namecall_queue, {
            object = obj,
            method = method,
            args = args,
            returnValue = returnValue,
            timestamp = timestamp,
            caller = caller -- Store the script that fired this
        })
    end
    
    return game_namecall(obj, ...)
end

-- =========================================
-- PUBLIC API
-- =========================================

function RemoteSpyLibrary.new(opts)
    opts = opts or {}
    local self = setmetatable({}, RemoteSpyLibrary)
    self.config = {
        Enabled = opts.enabled ~= nil and opts.enabled or CONFIG.DefaultEnabled,
        CaptureReturnValues = opts.captureReturns ~= nil and opts.captureReturns or CONFIG.CaptureReturnValues,
        Callback = nil,
    }
    self_ref = self
    
    -- Capture the script that required this module
    module_caller_script = getfenv(2).script
    self.moduleCallerInfo = self:GetScriptInfo(module_caller_script)
    
    return self
end

function RemoteSpyLibrary:Start()
    if is_hooked then return self end
    
    if setreadonly then
        setreadonly(game_meta, false)
    elseif make_writeable then
        make_writeable(game_meta)
    end
    
    game_meta.__namecall = onNamecall
    is_hooked = true
    
    self.connection = game:GetService("RunService").Stepped:Connect(processQueue)
    return self
end

function RemoteSpyLibrary:Stop()
    if not is_hooked then return self end
    
    game_meta.__namecall = game_namecall
    is_hooked = false
    
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
    
    namecall_queue = {}
    return self
end

function RemoteSpyLibrary:SetEnabled(enabled)
    self.config.Enabled = enabled
    return self
end

function RemoteSpyLibrary:onRemote(callback)
    self.config.Callback = callback
    return self
end

-- =========================================
-- ADDITIONAL UTILITY METHODS
-- =========================================

function RemoteSpyLibrary:GetModuleInfo()
    return self.moduleCallerInfo
end

function RemoteSpyLibrary:ClearHistory()
    call_history = {}
    remote_stats = {}
    return self
end

function RemoteSpyLibrary:GetHistory(limit)
    limit = limit or 100
    local startIdx = math.max(1, #call_history - limit + 1)
    local result = {}
    for i = startIdx, #call_history do
        table.insert(result, call_history[i])
    end
    return result
end

function RemoteSpyLibrary:GetStats(remoteName)
    if remoteName then
        return remote_stats[remoteName] or {count = 0, lastCalled = 0}
    end
    return remote_stats
end

-- =========================================
-- RETURN MODULE
-- =========================================

return RemoteSpyLibrary
