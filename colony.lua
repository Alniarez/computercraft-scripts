package.path = package.path .. ";./?.lua"

-- Get all requirements
local peripherals = require("peripherals")
local monitor = require("advanced_monitor")

-- Do any initialization
local RUNNING = true
local RESTART = false

monitor.initialize(peripherals)
--peripherals.listPeripherals();

local playerDetector, playerDetectorError = peripherals.getPeripheralByType("player_detector")
local colonyIntegrator, colonyIntegratorError = peripherals.getPeripheralByType("colony_integrator")

if playerDetector == nil then
    monitor.showDialog("Missing " .. playerDetectorError, colors.red)
    return
end

if colonyIntegrator == nil then
    monitor.showDialog("Missing " .. colonyIntegratorError, colors.red)
    return
end

-- Script variables
local COLONY = "Citizens"
local VISITORS = "Visitors"
local NEEDS = "Needs"
local currentState = COLONY

-- Startup
local config = {}
config.activityRadius = 40
config.noPlayerCount = 20 -- 20 loops without player activity shuts the system down
config.name = "Colony Dashboard v0.1"
config.skillsPerLine = 6
config.showCitizenSkill = false
config.fastUpdate = false

local art = {
    "  ___  _____  __    _____  _  _  _  _",
    " / __)(  _  )(  )  (  _  )( \\( )( \\/ )",
    "( (__  )(_)(  )(__  )(_)(  )  (  \\  /",
    " \\___)(_____)(____)(_____)(_)\\_) (__)",
    " ____    __    ___  _   _  ____  _____    __    ____  ____",
    "(  _ \\  /__\\  / __)( )_( )(  _ \\(  _  )  /__\\  (  _ \\(  _ \\",
    " )(_) )/(__)\\ \\__ \\ ) _ (  ) _ < )(_)(  /(__)\\  )   / )(_) )",
    "(____/(__)(__)(___/(_) (_)(____/(_____)(__)(__)(_)\\_)(____/",
    "                                                Version 0.1",
    "",
    "                      Loading..."
}

monitor.clear()

monitor.drawSplash(art, colors.cyan)
sleep(2)

monitor.setTitle("Colony dashboard")

monitor.addTab(COLONY, colors.cyan)
monitor.addTab(VISITORS, colors.lime)
monitor.addTab(NEEDS, colors.orange)

-- Setup menus
monitor.addMenu("Program", {
    { label = "-----", callback = function()
    end },
    { label = "Exit", callback = function()
        monitor.showDialog(
                "Are you sure?",
                colors.blue,
                {
                    { label = "Yes", callback = function()
                        shutdown()
                    end },
                    { label = "No", callback = function()
                        monitor.closeDialog()
                    end }
                }
        )
    end },
})

monitor.addMenu("Options", {
    { label = "-----", callback = function()
    end },
    { label = "Toggle Citizen stats", callback = function()
        config.showCitizenSkill = not config.showCitizenSkill
    end },
    { label = "Toggle fast refresh mode", callback = function()
        config.fastUpdate = not config.fastUpdate
    end },
})

monitor.addMenu("Help", {
    { label = "-----", callback = function()
    end },
    { label = "About", callback = function()
        monitor.showDialog(config.name)
    end },
})

---Shutdown
local function shutdown()
    monitor.showDialog({ "Goodbye!" })
    sleep(2)
    monitor.clear()
    monitor.drawSplash({ "It's now safe to turn off", "     your computer" }, colors.black, colors.orange)
    RUNNING = false
end

local function dumpToString(t, indent, visited, out)
    indent = indent or 0
    visited = visited or {}
    out = out or {}

    if visited[t] then
        table.insert(out, string.rep(" ", indent) .. "*RECURSION*")
        return table.concat(out, "\n")
    end
    visited[t] = true

    for k, v in pairs(t) do
        local prefix = string.rep(" ", indent) .. tostring(k) .. ": "

        if type(v) == "table" then
            table.insert(out, prefix .. "{")
            dumpToString(v, indent + 2, visited, out)
            table.insert(out, string.rep(" ", indent) .. "}")
        else
            table.insert(out, prefix .. tostring(v))
        end
    end

    return table.concat(out, "\n")
end


local function formatSkills(skills, perLine)
    local parts = {}

    -- Convert into compact "Ath:10" etc.
    local items = {}
    for k, v in pairs(skills) do
        table.insert(items, string.sub(k, 1, 3) .. ":" .. tostring(v.level))
    end

    table.sort(items) -- optional but keeps output consistent

    -- Chunk into lines
    local lines = {}
    for i = 1, #items, perLine do
        table.insert(lines, table.concat(items, ", ", i, math.min(i + perLine - 1, #items)))
    end

    return lines
end

---handle touch
local function handleTouches()
    while RUNNING do
        local event, side, x, y = os.pullEvent("monitor_touch")
        monitor.handleTouch(x, y)
    end
end

---colonyLofic
local function colonyLogic()
    local sleepTime = 5
    local players = {}
    local noPlayerCount = 0
    while RUNNING do
        currentState = monitor.currentTab;
        ----------------------------------------------------------
        -- COLONY tab logic
        ----------------------------------------------------------
        if currentState == COLONY then
            monitor.clearTab(COLONY)

            local citizens = colonyIntegrator.getCitizens()

            for _, citizen in ipairs(citizens) do

                local job = "None"
                if citizen.work and citizen.work.type then
                    job = citizen.work.type
                end

                local line = string.format(
                        "%s | Job: %s | State: %s",
                        citizen.name,
                        job,
                        citizen.state or "Unknown"
                )

                monitor.printToTab(COLONY, line)

                if config.showCitizenSkill then
                    local skillLines = formatSkills(citizen.skills, config.skillsPerLine)
                    for _, line in ipairs(skillLines) do
                        monitor.printToTab(COLONY, "    "..line)
                    end
                end
            end

        end
        ----------------------------------------------------------
        -- Visitors tab logic
        ----------------------------------------------------------
        if currentState == VISITORS then
            monitor.clearTab(VISITORS)

            local visitors = colonyIntegrator.getVisitors()

            for _, visitor in ipairs(visitors) do
                monitor.printToTab(VISITORS, visitor.name)

                local skillLines = formatSkills(visitor.skills, config.skillsPerLine) -- 5 skills per line

                for _, line in ipairs(skillLines) do
                    monitor.printToTab(VISITORS, "    "..line)
                end

            end
        end
        ----------------------------------------------------------
        -- NEEDS tab logic
        ----------------------------------------------------------
        if currentState == NEEDS then
            monitor.clearTab(NEEDS)

            local requests = colonyIntegrator.getRequests() or {}
            local needs = {}

            -- Aggregate per building + registry name + display name
            for _, req in ipairs(requests) do
                local target = req.target or "Unknown"
                if req.items then
                    for _, it in ipairs(req.items) do
                        local reg   = it.name or "unknown"
                        local name  = it.displayName or reg
                        local count = it.count or 1
                        needs[target] = needs[target] or {}
                        local entry = needs[target][reg]
                        if not entry then
                            entry = {
                                building = target,
                                reg      = reg,
                                item     = name,
                                count    = 0
                            }
                            needs[target][reg] = entry
                        end
                        entry.count = entry.count + count
                    end
                end
            end

            local lines = {}
            for _, items in pairs(needs) do
                for _, entry in pairs(items) do
                    table.insert(lines, entry)
                end
            end

            table.sort(lines, function(a, b)
                if a.building == b.building then
                    return a.item < b.item
                else
                    return a.building < b.building
                end
            end)

            if #lines == 0 then
                monitor.printToTab(NEEDS, "No current needs.")
            else
                for _, ln in ipairs(lines) do
                    local line = ln.count .. "x " .. ln.item .. " | " .. ln.building
                    monitor.printToTab(NEEDS, line)
                end

            end

        end -- end needs

        ----------------------------------------------------------
        -- Player detection
        ----------------------------------------------------------
        players = playerDetector.getPlayersInRange(config.activityRadius)

        monitor.closeDialog()

        if #players > 0 then
            --for k, v in ipairs(players) do
            --    print(v .. " is nearby")
            --end
            -- monitor.print("Player nearby")

            noPlayerCount = 0
            if config.fastUpdate then
                sleepTime = 1
            else
                sleepTime = 5
            end
        else
            sleepTime = 15
            noPlayerCount = noPlayerCount + 1
            monitor.showDialog("No player nearby, sleeping for a moment", colors.yellow)
        end

        if noPlayerCount > config.noPlayerCount then
            RUNNING = false
        end


        sleep(sleepTime)
    end
end

parallel.waitForAny(handleTouches, colonyLogic)
shutdown()

