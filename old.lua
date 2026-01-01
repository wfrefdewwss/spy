-- RemoteSpyLibrary.lua
-- Drop this in a GitHub gist, raw link it, and you're golden

local RemoteSpyLibrary = {}
RemoteSpyLibrary.__index = RemoteSpyLibrary

-- Config
local CONFIG = {
    MaxQueueSize = 500,  -- Drop old logs if you're lagging
    DefaultEnabled = true,
    FilterEvents = true,
    FilterFunctions = true,
    NameFilter = ""
}

-- Locals
local game_meta = getrawmetatable(game)
local game_namecall = game_meta.__namecall
local namecall_queue = {}
local is_hooked = false
local options = {}
local onRemoteCallback = nil

-- Utils
local function GetPath(obj)
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

local function GetType(val)
    local typeMap = {
        EnumItem = function() return "Enum." .. tostring(val.EnumType) .. "." .. val.Name end,
        Instance = GetPath,
        CFrame = function() return "CFrame.new(" .. tostring(val) .. ")" end,
        Vector3 = function() return "Vector3.new(" .. tostring(val) .. ")" end,
        BrickColor = function() return "BrickColor.new(\"" .. tostring(val) .. "\")" end,
        Color3 = function() return "Color3.new(" .. tostring(val) .. ")" end,
        string = function() return "\"" .. tostring(val):gsub('"', '\\"') .. "\"" end,
        Ray = function() return "Ray.new(Vector3.new(" .. tostring(val.Origin) .. "), Vector3.new(" .. tostring(val.Direction) .. "))" end
    }
    local handler = typeMap[typeof(val)]
    return handler and handler() or tostring(val)
end

local function tableToString(t)
    local parts = {}
    for k, v in pairs(t) do
        local key = type(k) == "number" and "[" .. k .. "]" or "[\"" .. k .. "\"]"
        local val = type(v) == "table" and tableToString(v) or GetType(v)
        table.insert(parts, key .. " = " .. val)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function generateScript(obj, method, args)
    local script = "-- RemoteSpy Log\n-- Path: " .. GetPath(obj) .. "\n\n"
    for i, v in ipairs(args) do
        script = script .. "local A_" .. i .. " = " .. (type(v) == "table" and tableToString(v) or GetType(v)) .. "\n"
    end
    script = script .. "\nlocal Event = " .. GetPath(obj) .. "\n\n"
    script = script .. "Event:" .. method .. "(" .. table.concat({"A_1", "A_2", "A_3", "A_4", "A_5"}, ", "):gsub(", A_[0-9]+$", "") .. ")"
    return script
end

local function processQueue()
    while #namecall_queue > 0 do
        if #namecall_queue > CONFIG.MaxQueueSize then
            -- Drop oldest entries if queue is too backed up
            table.remove(namecall_queue, 1)
        end
        
        local data = table.remove(namecall_queue, 1)
        local shouldLog = true
        
        -- Apply filters
        if not options.FilterEvents and data.method == "FireServer" then shouldLog = false end
        if not options.FilterFunctions and data.method == "InvokeServer" then shouldLog = false end
        if options.NameFilter ~= "" and not data.object.Name:lower():find(options.NameFilter:lower(), 1, true) then
            shouldLog = false
        end
        
        if shouldLog and onRemoteCallback then
            onRemoteCallback({
                object = data.object,
                method = data.method,
                args = data.args,
                script = data.script,
                caller = data.caller,
                returnValue = data.returnValue,
                timestamp = tick()
            })
        end
    end
end

-- Hook
local function onNamecall(obj, ...)
    local method = getnamecallmethod()
    local args = {...}
    
    if obj.Name ~= "CharacterSoundEvent" and method:match("Server") and options.Enabled then
        local returnValue = nil
        if obj.ClassName == "RemoteFunction" and method == "InvokeServer" then
            local success, result = pcall(function() return obj:InvokeServer(unpack(args)) end)
            if success then returnValue = result end
        end
        
        local caller = getfenv(2).script
        table.insert(namecall_queue, {
            object = obj,
            method = method,
            args = args,
            script = generateScript(obj, method, args),
            caller = caller,
            returnValue = returnValue
        })
    end
    
    return game_namecall(obj, ...)
end

-- Public API
function RemoteSpyLibrary.new(opts)
    opts = opts or {}
    local self = setmetatable({}, RemoteSpyLibrary)
    
    options = {
        Enabled = opts.enabled ~= nil and opts.enabled or CONFIG.DefaultEnabled,
        FilterEvents = opts.filterEvents ~= nil and opts.filterEvents or CONFIG.FilterEvents,
        FilterFunctions = opts.filterFunctions ~= nil and opts.filterFunctions or CONFIG.FilterFunctions,
        NameFilter = opts.nameFilter or CONFIG.NameFilter
    }
    
    onRemoteCallback = opts.onRemoteFired
    
    return self
end

function RemoteSpyLibrary:Start()
    if is_hooked then return end
    
    -- Make metatable writable
    if setreadonly then
        setreadonly(game_meta, false)
    elseif make_writeable then
        make_writeable(game_meta)
    end
    
    game_meta.__namecall = onNamecall
    is_hooked = true
    
    -- Start queue processor
    self.connection = game:GetService("RunService").Stepped:Connect(processQueue)
end

function RemoteSpyLibrary:Stop()
    if not is_hooked then return end
    
    game_meta.__namecall = game_namecall
    is_hooked = false
    
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
    
    namecall_queue = {}
end

function RemoteSpyLibrary:SetEnabled(enabled)
    options.Enabled = enabled
end

function RemoteSpyLibrary:SetFilters(includeEvents, includeFuncs, nameFilter)
    options.FilterEvents = includeEvents
    options.FilterFunctions = includeFuncs
    options.NameFilter = nameFilter or ""
end

function RemoteSpyLibrary:SetCallback(callback)
    onRemoteCallback = callback
end

function RemoteSpyLibrary:GetQueueSize()
    return #namecall_queue
end

function RemoteSpyLibrary:ClearQueue()
    namecall_queue = {}
end

-- Return the module
return RemoteSpyLibrary
