-- RemoteSpyLibrary.lua
-- Advanced Edition: Simple API, hidden power

local RemoteSpyLibrary = {}
RemoteSpyLibrary.__index = RemoteSpyLibrary

-- Default config
local CONFIG = {
    MaxQueueSize = 500,
    AutoClearCount = 1000,
    DefaultEnabled = true,
    CaptureReturnValues = true,
    EnableStats = true,
    EnableExport = false,
    Blocklist = {},
    Allowlist = {},
    FilterEvents = true,
    FilterFunctions = true,
    NameFilter = "",
    ArgTypeFilter = nil, -- function to filter by arg types
    Callback = nil,
    ExportPlugin = nil,
    OnBlock = nil, -- callback when remote is blocked
}

-- Internal state
local game_meta = getrawmetatable(game)
local game_namecall = game_meta.__namecall
local namecall_queue = {}
local is_hooked = false
local remote_stats = {}
local call_history = {}
local self_ref = nil

-- =========================================
-- UTILITY FUNCTIONS (Now public)
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

function RemoteSpyLibrary:GenerateScript(obj, method, args)
    local path = self:GetPath(obj)
    local script = "-- RemoteSpy Log\n-- Path: " .. path .. "\n-- Timestamp: " .. tick() .. "\n\n"
    
    for i, v in ipairs(args) do
        script = script .. "local Arg_" .. i .. " = " .. self:GetType(v) .. "\n"
    end
    
    script = script .. "\nlocal Remote = " .. path .. "\n\n"
    script = script .. "Remote:" .. method .. "(" .. table.concat({"Arg_1", "Arg_2", "Arg_3", "Arg_4", "Arg_5"}, ", "):gsub(", Arg_[0-9]+$", "") .. ")"
    return script
end

-- =========================================
-- STATISTICS TRACKING
-- =========================================

function RemoteSpyLibrary:GetStats(remoteName)
    if remoteName then
        return remote_stats[remoteName] or {count = 0, lastCalled = 0, avgExecTime = 0}
    end
    return remote_stats
end

function RemoteSpyLibrary:ResetStats(remoteName)
    if remoteName then
        remote_stats[remoteName] = nil
    else
        remote_stats = {}
    end
end

function RemoteSpyLibrary:GetTopRemotes(limit)
    limit = limit or 10
    local sorted = {}
    for name, stats in pairs(remote_stats) do
        table.insert(sorted, {name = name, count = stats.count, last = stats.lastCalled})
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    return {unpack(sorted, 1, limit)}
end

-- =========================================
-- EXPORT PLUGINS
-- =========================================

local ExportPlugins = {
    clipboard = function(data)
        local copy = Clipboard and Clipboard.set or Synapse and Synapse.Copy or setclipboard
        if copy then copy(data.script) end
    end,
    
    webhook = function(data, config)
        local http = game:GetService("HttpService")
        local payload = http:JSONEncode({
            content = string.format("RemoteSpy Log: %s:%s", data.object.Name, data.method),
            embeds = {{
                title = data.object.Name,
                description = "```lua\n" .. data.script .. "\n```",
                color = data.object.ClassName == "RemoteEvent" and 65280 or 65535,
                timestamp = DateTime.now():ToIsoDate(),
                fields = {
                    {name = "Path", value = data.path, inline = false},
                    {name = "Caller", value = tostring(data.caller), inline = true}
                }
            }}
        })
        
        syn.request({
            Url = config.url,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = payload
        })
    end,
    
    file = function(data, config)
        if not writefile then return end
        local filename = string.format("%s_%s_%d.lua", data.object.Name, data.method, tick())
        writefile(filename, data.script)
    end
}

function RemoteSpyLibrary:withExport(plugin, config)
    if ExportPlugins[plugin] then
        self.config.ExportPlugin = {name = plugin, func = ExportPlugins[plugin], config = config}
    end
    return self
end

function RemoteSpyLibrary:Export(data)
    if self.config.ExportPlugin then
        self.config.ExportPlugin.func(data, self.config.ExportPlugin.config)
    end
end

-- =========================================
-- BLOCKING & INTERCEPTION
-- =========================================

function RemoteSpyLibrary:SetBlocklist(list)
    self.config.Blocklist = list or {}
    return self
end

function RemoteSpyLibrary:SetAllowlist(list)
    self.config.Allowlist = list or {}
    return self
end

function RemoteSpyLibrary:withBlocklist(...)
    local list = type(...) == "table" and ... or {...}
    return self:SetBlocklist(list)
end

function RemoteSpyLibrary:withAllowlist(...)
    local list = type(...) == "table" and ... or {...}
    return self:SetAllowlist(list)
end

function RemoteSpyLibrary:ShouldBlock(remote)
    local name = remote.Name
    
    -- Allowlist takes precedence
    if #self.config.Allowlist > 0 then
        for _, allowed in ipairs(self.config.Allowlist) do
            if name:match(allowed) then return false end
        end
        return true
    end
    
    -- Check blocklist
    for _, blocked in ipairs(self.config.Blocklist) do
        if name:match(blocked) then return true end
    end
    
    return false
end

function RemoteSpyLibrary:SetInterceptor(fn)
    self.config.Interceptor = fn
    return self
end

-- =========================================
-- FLUENT API BUILDER
-- =========================================

function RemoteSpyLibrary.new(opts)
    opts = opts or {}
    local self = setmetatable({}, RemoteSpyLibrary)
    self.config = {
        Enabled = opts.enabled ~= nil and opts.enabled or CONFIG.DefaultEnabled,
        FilterEvents = opts.filterEvents ~= nil and opts.filterEvents or CONFIG.FilterEvents,
        FilterFunctions = opts.filterFunctions ~= nil and opts.filterFunctions or CONFIG.FilterFunctions,
        NameFilter = opts.nameFilter or CONFIG.NameFilter,
        ArgTypeFilter = opts.argTypeFilter or CONFIG.ArgTypeFilter,
        MaxQueueSize = opts.maxQueue or CONFIG.MaxQueueSize,
        AutoClearCount = opts.autoClear or CONFIG.AutoClearCount,
        CaptureReturnValues = opts.captureReturns ~= nil and opts.captureReturns or CONFIG.CaptureReturnValues,
        EnableStats = opts.stats ~= nil and opts.stats or CONFIG.EnableStats,
        Blocklist = {},
        Allowlist = {},
        Callback = nil,
        ExportPlugin = nil,
        Interceptor = nil,
        OnBlock = nil,
    }
    self_ref = self
    return self
end

function RemoteSpyLibrary:withFilters(filters)
    self.config.FilterEvents = filters.events
    self.config.FilterFunctions = filters.functions
    self.config.NameFilter = filters.names or ""
    self.config.ArgTypeFilter = filters.argTypes
    return self
end

function RemoteSpyLibrary:withAutoClear(count)
    self.config.AutoClearCount = count
    return self
end

function RemoteSpyLibrary:withStats(enabled)
    self.config.EnableStats = enabled ~= nil and enabled or true
    return self
end

function RemoteSpyLibrary:onRemote(callback)
    self.config.Callback = callback
    return self
end

-- =========================================
-- CORE PROCESSING
-- =========================================

local function processQueue()
    while #namecall_queue > 0 do
        local data = table.remove(namecall_queue, 1)
        local remote = data.object
        
        -- Auto-cleanup history
        if #call_history >= self_ref.config.AutoClearCount then
            call_history = {unpack(call_history, -500)} -- Keep last 500
        end
        
        -- Check if blocked
        if self_ref:ShouldBlock(remote) then
            if self_ref.config.OnBlock then
                self_ref.config.OnBlock(data)
            end
            return -- Block the call
        end
        
        -- Apply name filter
        if self_ref.config.NameFilter ~= "" and not remote.Name:lower():find(self_ref.config.NameFilter:lower(), 1, true) then
            return
        end
        
        -- Apply arg type filter
        if self_ref.config.ArgTypeFilter then
            local match = false
            for _, arg in ipairs(data.args) do
                if self_ref.config.ArgTypeFilter(typeof(arg)) then match = true end
            end
            if not match then return end
        end
        
        -- Update stats
        if self_ref.config.EnableStats then
            remote_stats[remote.Name] = remote_stats[remote.Name] or {count = 0, lastCalled = 0, execTimes = {}}
            local stats = remote_stats[remote.Name]
            stats.count = stats.count + 1
            stats.lastCalled = tick()
            stats.execTimes[#stats.execTimes + 1] = tick() - data.timestamp
            if #stats.execTimes > 100 then table.remove(stats.execTimes, 1) end
            stats.avgExecTime = stats.execTimes[#stats.execTimes] -- Simplified
        end
        
        -- Store in history
        table.insert(call_history, data)
        
        -- User callback
        if self_ref.config.Callback then
            data.path = self_ref:GetPath(remote)
            pcall(self_ref.config.Callback, data)
        end
        
        -- Export if enabled
        if self_ref.config.ExportPlugin then
            pcall(self_ref.Export, self_ref, data)
        end
    end
end

-- Hook
local function onNamecall(obj, ...)
    local method = getnamecallmethod()
    local args = {...}
    local timestamp = tick()
    
    -- Intercept if configured
    if self_ref.config.Interceptor then
        local modifiedArgs, shouldBlock = self_ref.config.Interceptor(obj, method, args)
        if shouldBlock then return end
        args = modifiedArgs or args
    end
    
    if obj.Name ~= "CharacterSoundEvent" and method:match("Server") and self_ref.config.Enabled then
        local returnValue = nil
        if obj.ClassName == "RemoteFunction" and method == "InvokeServer" and self_ref.config.CaptureReturnValues then
            local success, result = pcall(function() return obj:InvokeServer(unpack(args)) end)
            if success then returnValue = result end
        end
        
        table.insert(namecall_queue, {
            object = obj,
            method = method,
            args = args,
            returnValue = returnValue,
            timestamp = timestamp,
            caller = getfenv(2).script
        })
    end
    
    return game_namecall(obj, ...)
end

-- =========================================
-- CONTROL METHODS
-- =========================================

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

function RemoteSpyLibrary:ClearHistory()
    call_history = {}
    remote_stats = {}
    return self
end

function RemoteSpyLibrary:GetHistory(limit)
    limit = limit or 100
    return {unpack(call_history, -limit)}
end

-- =========================================
-- EXPORT
-- =========================================

return RemoteSpyLibrary
