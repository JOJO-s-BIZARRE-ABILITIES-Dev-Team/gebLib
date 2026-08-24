local previous = gebLib._Runtime
if previous and previous.Reset then
    previous.Reset("reload")
end

local Runtime = {
    HookName = "gebLib.Runtime.Frame",
    Entries = {},
    Owners = {},
    Iterating = false,
}

gebLib._Runtime = Runtime

local unpackValues = unpack or table.unpack

local function pack(...)
    return {n = select("#", ...), ...}
end

local function report(label, err)
    local message = "[gebLib] " .. tostring(label) .. " failed: " .. tostring(err) .. "\n"
    if ErrorNoHalt then
        ErrorNoHalt(message)
    else
        print(message)
    end
end

local function removeHookWhenIdle()
    if next(Runtime.Entries) == nil and hook and hook.Remove then
        hook.Remove("Think", Runtime.HookName)
    end
end

local function compactOwners()
    local owners = Runtime.Owners
    local write = 1

    for read = 1, #owners do
        local owner = owners[read]
        local entry = Runtime.Entries[owner]
        if entry then
            owners[write] = owner
            entry.index = write
            write = write + 1
        end
    end

    for index = write, #owners do owners[index] = nil end
    removeHookWhenIdle()
end

function Runtime.Invoke(owner, label, callback, onFailure, ...)
    if not callback then return true end

    local arguments = pack(...)
    local results
    local ok, err = xpcall(function()
        results = pack(callback(unpackValues(arguments, 1, arguments.n)))
    end, debug and debug.traceback or tostring)

    if not ok then
        report(label, err)
        if onFailure then
            local cleanupOk, cleanupError = pcall(onFailure, owner, err)
            if not cleanupOk then report(tostring(label) .. " cleanup", cleanupError) end
        end
        return false
    end

    return true, unpackValues(results, 1, results.n)
end

function Runtime.Unregister(owner)
    local entry = Runtime.Entries[owner]
    if not entry then return false end

    Runtime.Entries[owner] = nil
    if not Runtime.Iterating then compactOwners() end
    return true
end

function Runtime.Tick()
    Runtime.Iterating = true
    local limit = #Runtime.Owners

    for index = 1, limit do
        local owner = Runtime.Owners[index]
        local entry = Runtime.Entries[owner]

        if entry then
            local ok, keep = Runtime.Invoke(owner, entry.label, entry.step, entry.onFailure, owner)
            if not ok or keep == false then Runtime.Entries[owner] = nil end
        end
    end

    Runtime.Iterating = false
    compactOwners()
end

function Runtime.Register(owner, label, step, onFailure, onReload)
    if type(owner) ~= "table" then error("runtime owner must be a table", 2) end
    if type(step) ~= "function" then error("runtime step must be a function", 2) end

    local entry = Runtime.Entries[owner]
    if entry then
        entry.label = label
        entry.step = step
        entry.onFailure = onFailure
        entry.onReload = onReload
        return owner
    end

    entry = {
        label = label,
        step = step,
        onFailure = onFailure,
        onReload = onReload,
        index = #Runtime.Owners + 1,
    }
    Runtime.Entries[owner] = entry
    Runtime.Owners[entry.index] = owner

    if hook and hook.Add then hook.Add("Think", Runtime.HookName, Runtime.Tick) end
    return owner
end

function Runtime.Reset(reason)
    local entries = Runtime.Entries
    Runtime.Entries = {}

    if hook and hook.Remove then hook.Remove("Think", Runtime.HookName) end

    for owner, entry in pairs(entries) do
        local cleanup = entry.onReload or entry.onFailure
        if cleanup then
            local ok, err = pcall(cleanup, owner, reason or "reset")
            if not ok then report(tostring(entry.label) .. " cleanup", err) end
        end
    end

    Runtime.Owners = {}
    Runtime.Iterating = false
end

return Runtime
