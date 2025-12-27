-- colony dashboard
-- version: 1.2
--
-- changelog:
-- 1.2 Added average stats
-- 1.1 Added AE2
-- 1.0 Initial release

package.path = package.path .. ";./?.lua"

-- Get all requirements
local peripherals = require("peripherals")
local monitor = require("advanced_monitor")

-- Do any initialization
local RUNNING = true
local ME_DRIVE = false

monitor.initialize(peripherals)
--peripherals.listPeripherals();

local playerDetector, playerDetectorError = peripherals.getPeripheralByType("player_detector")
local colonyIntegrator, colonyIntegratorError = peripherals.getPeripheralByType("colony_integrator")
local meBridge, meBridgeError = peripherals.getPeripheralByType("me_bridge")

if playerDetector == nil then
    monitor.showDialog("Missing " .. playerDetectorError, colors.red)
    return
end

if colonyIntegrator == nil then
    monitor.showDialog("Missing " .. colonyIntegratorError, colors.red)
    return
end

if meBridge == nil then
    monitor.showDialog("Missing " .. meBridgeError, colors.red)
else
    ME_DRIVE = true
end

-- Debug function
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

local function dumpToPrintable(t, indent, visited, out)
    indent = indent or 0
    visited = visited or {}
    out = out or {}

    local function pad(n)
        return string.rep(" ", n)
    end

    -- recursion guard
    if visited[t] then
        table.insert(out, pad(indent) .. "*RECURSION*")
        return out
    end
    visited[t] = true

    for k, v in pairs(t) do
        local key = tostring(k)
        local prefix = pad(indent) .. key .. ": "

        if type(v) == "table" then
            -- opening brace
            table.insert(out, prefix .. "{")

            -- recurse deeper
            dumpToPrintable(v, indent + 2, visited, out)

            -- closing brace
            table.insert(out, pad(indent) .. "}")

        else
            -- primitive value
            table.insert(out, prefix .. tostring(v))
        end
    end

    return out
end

-- Script variables
local COLONY = "Colony"
local CITIZENS = "Citizens"
local VISITORS = "Visitors"
local NEEDS = "Needs"
local WORK_ORDERS = "Work Orders"
local BUILDER = "Builders"
local DEBUG = "Debug"
local LOG_TAB = "Log"
local currentState = COLONY

------------------------------------------------------
-- AE2 Helper (cached ME item count)
------------------------------------------------------
local AE2Helper = {
    cache = {},
    CACHE_TTL = 5000,
}

local function queryMEItem(me, name)
    if not me or not name then
        return 0
    end

    local count = 0

    if me.getItem then
        local ok, res = pcall(me.getItem, { name = name })
        if ok and res and res.count then
            count = res.count
        end
    end

    return count
end

function AE2Helper.getCount(me, name)
    if not me or not name then
        return 0
    end

    local now = os.epoch("utc")
    local entry = AE2Helper.cache[name]

    if entry and (now - entry.time) < AE2Helper.CACHE_TTL then
        return entry.count
    end

    local count = queryMEItem(me, name)

    AE2Helper.cache[name] = {
        count = count,
        time = now,
    }

    return count
end

------------------------------------------------------
-- Colony helper
------------------------------------------------------
local ColonyHelper = {}

------------------------------------------------------
-- Format general overview
------------------------------------------------------
function ColonyHelper.formatOverview(colony)
    local out = {}

    ------------------------------------------------------
    -- SAFE FETCHES
    ------------------------------------------------------
    local name = colony.getColonyName() or "Unknown Colony"
    local attack = colony.isUnderAttack()
    local citizens = colony.amountOfCitizens() or 0
    local maxCit = colony.maxOfCitizens() or 0
    local happiness = colony.getHappiness() or 0
    local list = colony.getCitizens() or {}

    ------------------------------------------------------
    -- DERIVED COUNTS
    ------------------------------------------------------
    local working = 0
    local idle = 0
    local sick = 0

    for _, c in ipairs(list) do
        -- Working / Idle
        if c.work and c.work.type then
            if not c.isIdle then
                working = working + 1
            else
                idle = idle + 1
            end
        else
            idle = idle + 1
        end

        -- Sick
        if c.health and c.maxHealth and c.maxHealth > 0 then
            if (c.health / c.maxHealth) < 0.5 then
                sick = sick + 1
            end
        end
        if c.state and c.state:lower():find("sick") then
            sick = sick + 1
        end
    end

    ------------------------------------------------------
    -- COLOR HELPERS
    ------------------------------------------------------
    local function happinessColor(h)
        if h >= 7 then
            return colors.green
        end
        if h >= 4 then
            return colors.yellow
        end
        return colors.red
    end

    ------------------------------------------------------
    -- PRETTY ALIGNMENT SETTINGS
    ------------------------------------------------------
    local labelW = 12  -- All labels padded to same width

    local function L(label)
        return label .. string.rep(" ", math.max(0, labelW - #label))
    end

    ------------------------------------------------------
    -- OUTPUT LINES
    ------------------------------------------------------

    -- Colony name (headline)
    table.insert(out, {
        { text = "Colony: ", color = colors.white },
        { text = tostring(name), color = colors.cyan }
    })
    table.insert(out, {}) -- blank line

    -- Citizens
    table.insert(out, {
        { text = L("Citizens:"), color = colors.white },
        { text = citizens .. " / " .. maxCit, color = colors.cyan }
    })

    -- Happiness
    table.insert(out, {
        { text = L("Happiness:"), color = colors.white },
        { text = string.format("%.1f", happiness), color = happinessColor(happiness) }
    })

    -- Working
    table.insert(out, {
        { text = L("Working:"), color = colors.white },
        { text = tostring(working), color = colors.green }
    })

    -- Idle
    table.insert(out, {
        { text = L("Idle:"), color = colors.white },
        { text = tostring(idle), color = colors.yellow }
    })

    -- Sick
    table.insert(out, {
        { text = L("Sick:"), color = colors.white },
        { text = tostring(sick), color = sick > 0 and colors.red or colors.green }
    })

    ------------------------------------------------------
    -- ATTACK WARNING
    ------------------------------------------------------
    if attack then
        table.insert(out, {})
        table.insert(out, {
            { text = "!!! COLONY UNDER ATTACK !!!", color = colors.red }
        })
        table.insert(out, {})
    end

    return out
end

------------------------------------------------------
-- Format colony citizen
------------------------------------------------------
function ColonyHelper.formatCitizen(citizen)
    local stateColor = colors.white
    if citizen.state == "Sick" then
        stateColor = colors.red
    end

    local job = "None"
    if citizen.work and citizen.work.type then
        job = citizen.work.type
    end

    local avg = ColonyHelper.getAverageSkill(citizen.skills)

    return {
        { text = citizen.name, color = colors.orange },
        { text = " | ", color = colors.lightGray },

        { text = job, color = colors.white },
        { text = " | ", color = colors.lightGray },

        { text = citizen.state or "Unknown", color = stateColor },
        { text = " | ", color = colors.lightGray },

        { text = "Avg: ", color = colors.white },
        { text = tostring(avg), color = ColonyHelper.skillColor(avg) }
    }
end

------------------------------------------------------
-- Format skills into something nicer
------------------------------------------------------
function ColonyHelper.formatSkills(skills, perLine, tabulation)
    local items = {}

    -- Build sortable items
    for name, data in pairs(skills) do
        table.insert(items, {
            abbr = string.sub(name, 1, 3),
            level = tonumber(data.level) or 0
        })
    end

    table.sort(items, function(a, b)
        return a.abbr < b.abbr
    end)

    ------------------------------------------------------
    -- Build segmented lines
    ------------------------------------------------------
    local result = {}
    local i = 1
    local tab = tonumber(tabulation) or 0

    while i <= #items do
        local lineParts = {}

        if tab > 0 then
            -- Add tabulation
            table.insert(lineParts, {
                text = string.rep(" ", tab),
                color = colors.white
            })
        end

        local last = math.min(i + perLine - 1, #items)

        for idx = i, last do
            local entry = items[idx]

            -- "Ath:"
            table.insert(lineParts, {
                text = entry.abbr .. ":",
                color = colors.white
            })

            -- Level number with color
            table.insert(lineParts, {
                text = tostring(entry.level),
                color = ColonyHelper.skillColor(entry.level)
            })

            -- Separator ", "
            if idx < last then
                table.insert(lineParts, {
                    text = ", ",
                    color = colors.white
                })
            end
        end

        table.insert(result, lineParts)
        i = last + 1
    end

    return result
end

------------------------------------------------------
-- Compute average skill level
------------------------------------------------------
function ColonyHelper.getAverageSkill(skills)
    if not skills then
        return 0
    end

    local total = 0
    local count = 0

    for _, skill in pairs(skills) do
        if skill and type(skill.level) == "number" then
            total = total + skill.level
            count = count + 1
        end
    end

    if count == 0 then
        return 0
    end

    return math.floor((total / count) + 0.5)
end

------------------------------------------------------
-- Skill color gradient
------------------------------------------------------
function ColonyHelper.skillColor(lv, max)
    max = max or 60
    local pct = (lv / max) * 100

    if pct <= 10 then
        return colors.white
    end
    if pct <= 20 then
        return colors.lightGray
    end
    if pct <= 30 then
        return colors.gray
    end
    if pct <= 40 then
        return colors.yellow
    end
    if pct <= 50 then
        return colors.orange
    end
    if pct <= 60 then
        return colors.red
    end
    if pct <= 70 then
        return colors.purple
    end
    if pct <= 85 then
        return colors.blue
    end
    return colors.lime
end

------------------------------------------------------
-- Format recruit costs
-----------------------------------------------------
function ColonyHelper.formatRecruitCost(costs, tabulation)
    local result = {}

    if not costs then
        return result
    end

    -- Normalize: single cost table -> list with one element
    local list
    if type(costs[1]) == "table" then
        -- already a list of cost tables
        list = costs
    else
        -- single cost object
        list = { costs }
    end

    local tab = tonumber(tabulation) or 0
    local indent = string.rep(" ", tab)

    for _, cost in ipairs(list) do
        local count = cost.count or 1
        local name = cost.displayName or cost.name or "Unknown"

        local line = {}

        -- optional indentation
        if tab > 0 then
            table.insert(line, {
                text = indent,
                color = colors.white,
            })
        end

        table.insert(line, {
            text = "Recruit: ",
            color = colors.green,
        })

        -- colored count
        table.insert(line, {
            text = tostring(count) .. "x ",
            color = colors.lightGray,
        })

        -- item name
        table.insert(line, {
            text = name,
            color = colors.white,
        })

        table.insert(result, line)
    end

    return result
end

------------------------------------------------------
-- Format WORK ORDERS (IN PROGRESS)
------------------------------------------------------
function ColonyHelper.formatWorkOrders(colony)
    local out = {}

    if not colony or not colony.getWorkOrders then
        return {
            { { text = "Colony API unavailable.", color = colors.red } }
        }
    end

    local orders = colony.getWorkOrders() or {}

    if #orders == 0 then
        return {
            { { text = "No work orders found.", color = colors.gray } }
        }
    end

    local shownAny = false

    for _, order in ipairs(orders) do
        local orderId = order.id
        if not orderId then
            -- Skip malformed orders
        else
            local ok, resources = pcall(colony.getWorkOrderResources, orderId)

            if ok and resources and #resources > 0 then
                --------------------------------------------------
                -- Check if this order actually needs materials
                --------------------------------------------------
                local hasNeeds = false
                for _, r in ipairs(resources) do
                    if (r.needed or 0) > 0 then
                        hasNeeds = true
                        break
                    end
                end

                if hasNeeds then
                    shownAny = true

                    --------------------------------------------------
                    -- Work order header
                    --------------------------------------------------
                    local title =
                    order.buildingName
                            or order.type
                            or "Work Order"

                    local levelInfo = ""
                    if order.targetLevel then
                        levelInfo = " → L" .. tostring(order.targetLevel)
                    end

                    table.insert(out, {
                        { text = title .. levelInfo, color = colors.cyan }
                    })

                    --------------------------------------------------
                    -- Resource lines
                    --------------------------------------------------
                    for _, r in ipairs(resources) do
                        local need = r.needed or 0
                        if need > 0 then
                            local name = r.displayName or r.item or "Unknown"

                            local statusColor
                            if r.available then
                                statusColor = colors.green
                            elseif r.delivering then
                                statusColor = colors.yellow
                            else
                                statusColor = colors.red
                            end

                            table.insert(out, {
                                { text = "    " },
                                { text = tostring(need) .. "x ", color = statusColor },
                                { text = name, color = colors.white }
                            })
                        end
                    end

                    table.insert(out, {}) -- blank line between orders
                end
            end
        end
    end

    if not shownAny then
        table.insert(out, {
            { text = "No work orders with material requirements.", color = colors.gray }
        })
    end

    return out
end

--------------------------------------------------
-- Format BUILDER NEEDS
--------------------------------------------------
function ColonyHelper.formatBuilderNeeds(colony)
    local out = {}

    local orders = colony.getWorkOrders() or {}

    if #orders == 0 then
        return {
            { { text = "No work orders found.", color = colors.gray } }
        }
    end

    for _, order in ipairs(orders) do
        --------------------------------------------------
        -- Work order header
        --------------------------------------------------
        local title =
        order.buildingName
                or order.target
                or order.name
                or "Work Order"

        table.insert(out, {
            { text = "Work Order: ", color = colors.lightGray },
            { text = title, color = colors.cyan }
        })

        --------------------------------------------------
        -- Builder position (required by API)
        --------------------------------------------------
        local builderPos = order.builder

        if not builderPos
                or type(builderPos) ~= "table"
                or builderPos.x == nil
                or builderPos.y == nil
                or builderPos.z == nil
        then
            table.insert(out, {
                { text = "    No builder position available.", color = colors.gray }
            })
            table.insert(out, {})
        else
            --------------------------------------------------
            -- Query builder material needs
            --------------------------------------------------
            local resources = colony.getBuilderResources(builderPos)

            if not resources or #resources == 0 then
                table.insert(out, {
                    { text = "    Builder active, no material requests yet.", color = colors.gray }
                })
                table.insert(out, {})
            else
                --------------------------------------------------
                -- Render builder materials (CORRECT FIELDS)
                --------------------------------------------------
                for _, it in ipairs(resources) do
                    local name = it.displayName or "Unknown"

                    local need       = it.needs or 0
                    local have       = it.available or 0
                    local delivering = it.delivering or 0

                    -- Skip entries that truly do nothing
                    if need > 0 then
                        local color
                        if have >= need then
                            color = colors.green
                        elseif have + delivering > 0 then
                            color = colors.yellow
                        else
                            color = colors.red
                        end

                        table.insert(out, {
                            { text = "    " },
                            { text = have .. " / " .. need .. " ", color = color },
                            { text = name, color = colors.white },
                        })
                    end
                end


                table.insert(out, {})
            end
        end
    end


    return out
end





------------------------------------------------------
-- Format NEEDS list (THIS WAS WRONG)
------------------------------------------------------
function ColonyHelper.formatNeeds(requests)
    local out = {}
    requests = requests or {}
    local needs = {}

    ------------------------------------------------------
    -- Group items by building + registry name
    ------------------------------------------------------
    for _, req in ipairs(requests) do
        local building = req.target or "Unknown"
        local needed = req.count or 1

        -- Every request has an items[] table with descriptors
        local it = req.items and req.items[1]
        if it then
            local reg = it.name or "unknown"
            local name = it.displayName or reg

            needs[building] = needs[building] or {}

            local entry = needs[building][reg]
            if not entry then
                entry = {
                    building = building,
                    reg = reg,
                    item = name,
                    count = 0
                }
                needs[building][reg] = entry
            end

            entry.count = entry.count + needed
        end
    end

    ------------------------------------------------------
    -- Flatten and sort
    ------------------------------------------------------
    local list = {}
    for _, items in pairs(needs) do
        for _, e in pairs(items) do
            table.insert(list, e)
        end
    end

    table.sort(list, function(a, b)
        if a.building == b.building then
            return a.item < b.item
        end
        return a.building < b.building
    end)

    ------------------------------------------------------
    -- Build output lines
    ------------------------------------------------------
    if #list == 0 then
        table.insert(out, {
            { text = "No current needs.", color = colors.green }
        })
        return out
    end

    local lastBuilding = nil

    for _, ln in ipairs(list) do
        if ln.building ~= lastBuilding then
            if lastBuilding then
                table.insert(out, {})
            end

            table.insert(out, {
                { text = ln.building, color = colors.cyan }
            })

            lastBuilding = ln.building
        end

        table.insert(out, {
            { text = "    " },
            { text = tostring(ln.count) .. "x ", color = colors.white },
            { text = ln.item, color = colors.white }
        })
    end

    return out
end


------------------------------------------------------
-- Format NEEDS list with AE2 READY/PARTIAL/MISSING
------------------------------------------------------
function ColonyHelper.formatNeedWithME(requests, me)
    local out = {}
    requests = requests or {}
    local needs = {}

    ------------------------------------------------------
    -- Group items
    ------------------------------------------------------
    for _, req in ipairs(requests) do
        local building = req.target or "Unknown"
        local needed = req.count or 1

        local it = req.items and req.items[1]
        if it then
            local reg = it.name or "unknown"
            local name = it.displayName or reg

            needs[building] = needs[building] or {}

            local entry = needs[building][reg]
            if not entry then
                entry = {
                    building = building,
                    reg = reg,
                    item = name,
                    count = 0
                }
                needs[building][reg] = entry
            end

            entry.count = entry.count + needed
        end
    end

    ------------------------------------------------------
    -- Flatten + sort
    ------------------------------------------------------
    local list = {}
    for _, items in pairs(needs) do
        for _, e in pairs(items) do
            table.insert(list, e)
        end
    end

    table.sort(list, function(a, b)
        if a.building == b.building then
            return a.item < b.item
        end
        return a.building < b.building
    end)

    if #list == 0 then
        table.insert(out, {
            { text = "No current needs.", color = colors.green }
        })
        return out
    end

    ------------------------------------------------------
    -- Build visual output with ME availability
    ------------------------------------------------------
    local lastBuilding = nil

    for _, ln in ipairs(list) do
        if ln.building ~= lastBuilding then
            if lastBuilding then
                table.insert(out, {})
            end

            table.insert(out, {
                { text = ln.building, color = colors.cyan }
            })

            lastBuilding = ln.building
        end

        local need = ln.count
        local have = AE2Helper.getCount(me, ln.reg)

        local statusText
        local statusColor

        if have >= need then
            statusText = "[READY]"
            statusColor = colors.green
        elseif have > 0 then
            statusText = "[PARTIAL: " .. have .. "/" .. need .. "]"
            statusColor = colors.yellow
        else
            statusText = "[MISSING]"
            statusColor = colors.red
        end

        table.insert(out, {
            { text = "    " },
            { text = need .. "x ", color = colors.white },
            { text = ln.item, color = colors.white },
            { text = "  " },
            { text = statusText, color = statusColor }
        })
    end

    return out
end


------------------------------------------------------
-- Export all currently needed items from ME to any
-- adjacent inventory, with confirmation dialog.
------------------------------------------------------
function ColonyHelper.exportNeedsFromME(colony, me, monitor)
    if not colony or not me then
        monitor.showDialog("Colony or ME bridge missing.", colors.red)
        return
    end

    --------------------------------------------------
    -- 1. Collect total needs per registry name (correct)
    --------------------------------------------------
    local requests = colony.getRequests() or {}
    local needed = {}

    for _, req in ipairs(requests) do
        local neededCount = req.count or 1
        local it = req.items and req.items[1]

        if it and it.name then
            local reg = it.name
            needed[reg] = (needed[reg] or 0) + neededCount
        end
    end

    if next(needed) == nil then
        monitor.showDialog("No current needs.", colors.green)
        return
    end

    --------------------------------------------------
    -- 2. Build export list based on what ME has
    --------------------------------------------------
    local exportList = {}
    local totalCount = 0

    for reg, need in pairs(needed) do
        local have = AE2Helper.getCount(me, reg)
        if have > 0 then
            local toExport = math.min(have, need)
            table.insert(exportList, { name = reg, amount = toExport })
            totalCount = totalCount + toExport
        end
    end

    if totalCount == 0 then
        monitor.showDialog("ME system has none of the needed items.", colors.red)
        return
    end

    --------------------------------------------------
    -- Helper: try exporting to one side with both
    -- known AP signatures.
    --------------------------------------------------
    local function tryExport(name, amount, side)
        if not me.exportItem then
            return 0
        end

        -- Signature 1: exportItem({name=..., count=...}, "side")
        local ok, res = pcall(me.exportItem, { name = name, count = amount }, side)
        if ok and type(res) == "number" and res > 0 then
            monitor.printToTab(LOG_TAB, name.." x"..amount)
            return res
        end

        -- Signature 2: exportItem({name=...}, "side", count)
        ok, res = pcall(me.exportItem, { name = name }, side, amount)
        if ok and type(res) == "number" and res > 0 then
            monitor.printToTab(LOG_TAB, name.." x"..amount)
            return res
        end

        return 0
    end

    --------------------------------------------------
    -- 3. Confirmation dialog
    --------------------------------------------------
    local msg = "Export " .. totalCount .. " items from ME?"
    monitor.showDialog({ msg }, colors.blue, {
        {
            label = "Yes",
            callback = function()
                monitor.closeDialog()

                monitor.printToTab(LOG_TAB, "Exporting items:")

                local sides = { "north", "south", "east", "west", "up", "down" }
                local exportedTot = 0

                -- 4. Perform exports to any adjacent inventories
                for _, entry in ipairs(exportList) do
                    local remaining = entry.amount

                    for _, side in ipairs(sides) do
                        if remaining <= 0 then
                            break
                        end
                        local moved = tryExport(entry.name, remaining, side)
                        if moved > 0 then
                            remaining = remaining - moved
                            exportedTot = exportedTot + moved
                        end
                    end
                end

                if exportedTot == 0 then
                    monitor.showDialog("No adjacent inventory accepted items.", colors.red)
                else
                    monitor.showDialog("Exported " .. exportedTot .. " items.", colors.green)
                end
                monitor.printToTab(LOG_TAB, "")
            end,
        },
        {
            label = "No",
            callback = function()
                monitor.closeDialog()
            end,
        },
    })
end

------------------------------------------------------
-- Export ALL builder-required materials from ME
------------------------------------------------------
function ColonyHelper.exportAllBuilderMaterialsFromME(colony, me, monitor)
    if not colony or not me then
        monitor.showDialog("Colony or ME bridge missing.", colors.red)
        return
    end

    --------------------------------------------------
    -- Collect all builders from work orders
    --------------------------------------------------
    local orders = colony.getWorkOrders() or {}
    local builders = {}

    for _, order in ipairs(orders) do
        if order.builder
                and order.builder.x
                and order.builder.y
                and order.builder.z
        then
            local key = order.builder.x .. ":" .. order.builder.y .. ":" .. order.builder.z
            builders[key] = order.builder
        end
    end

    if next(builders) == nil then
        monitor.showDialog("No active builders found.", colors.gray)
        return
    end

    --------------------------------------------------
    -- Aggregate material needs across all builders
    --------------------------------------------------
    local needed = {}

    for _, pos in pairs(builders) do
        local resources = colony.getBuilderResources(pos)
        if resources then
            for _, r in ipairs(resources) do
                local need = r.needs or 0
                local have = r.available or 0

                if need > have then
                    local missing = need - have
                    local item = r.item and r.item.name

                    if item then
                        needed[item] = (needed[item] or 0) + missing
                    end
                end
            end
        end
    end

    if next(needed) == nil then
        monitor.showDialog("All builders already have required materials.", colors.green)
        return
    end

    --------------------------------------------------
    -- Build export list from ME availability
    --------------------------------------------------
    local exportList = {}
    local total = 0

    for item, amount in pairs(needed) do
        local have = AE2Helper.getCount(me, item)
        if have > 0 then
            local toExport = math.min(have, amount)
            table.insert(exportList, { name = item, amount = toExport })
            total = total + toExport
        end
    end

    if total == 0 then
        monitor.showDialog("ME system has none of the required items.", colors.red)
        return
    end

    --------------------------------------------------
    -- Confirmation dialog
    --------------------------------------------------
    monitor.showDialog(
            "Export " .. total .. " building items from ME?",
            colors.blue,
            {
                {
                    label = "Yes",
                    callback = function()
                        monitor.closeDialog()

                        local sides = { "north", "south", "east", "west", "up", "down" }
                        local exported = 0

                        for _, entry in ipairs(exportList) do
                            local remaining = entry.amount

                            for _, side in ipairs(sides) do
                                if remaining <= 0 then break end

                                local ok, moved = pcall(me.exportItem,
                                        { name = entry.name, count = remaining },
                                        side
                                )

                                if ok and type(moved) == "number" and moved > 0 then
                                    monitor.printToTab(LOG_TAB, entry.name.." x"..moved)
                                    remaining = remaining - moved
                                    exported = exported + moved
                                end
                            end
                        end

                        monitor.showDialog(
                                "Exported " .. exported .. " items.",
                                colors.green
                        )
                    end
                },
                {
                    label = "No",
                    callback = function()
                        monitor.closeDialog()
                    end
                }
            }
    )
end


-- Startup
local config = {}
config.activityRadius = 40
config.noPlayerCount = 20 -- 20 loops without player activity shuts the system down
config.name = "Colony Dashboard v1.2"
config.skillsPerLine = 6
config.showCitizenSkill = true
config.fastUpdate = false
config.art = {
    "  ___  _____  __    _____  _  _  _  _",
    " / __)(  _  )(  )  (  _  )( \\( )( \\/ )",
    "( (__  )(_)(  )(__  )(_)(  )  (  \\  /",
    " \\___)(_____)(____)(_____)(_)\\_) (__)",
    " ____    __    ___  _   _  ____  _____    __    ____  ____",
    "(  _ \\  /__\\  / __)( )_( )(  _ \\(  _  )  /__\\  (  _ \\(  _ \\",
    " )(_) )/(__)\\ \\__ \\ ) _ (  ) _ < )(_)(  /(__)\\  )   / )(_) )",
    "(____/(__)(__)(___/(_) (_)(____/(_____)(__)(__)(_)\\_)(____/",
    "                                                Version 1.2",
    "",
    "                      Loading..."
}

monitor.clear()

monitor.drawSplash(config.art, colors.cyan)

sleep(2)

monitor.setTitle("Colony dashboard")

monitor.addTab(COLONY, colors.lightGray)
monitor.addTab(CITIZENS, colors.brown)
monitor.addTab(VISITORS, colors.lime)
monitor.addTab(NEEDS, colors.orange)
--monitor.addTab(WORK_ORDERS, colors.blue)
monitor.addTab(BUILDER, colors.red)
--monitor.addTab(DEBUG, colors.white)
monitor.addTab(LOG_TAB, colors.white)

-- Setup menus
local programMenu = {
    { label = "-----", callback = function()
    end },
}

-- Insert ME export option BEFORE Exit
if ME_DRIVE then
    table.insert(programMenu, {
        label = "Export Needs from ME system",
        callback = function()
            ColonyHelper.exportNeedsFromME(colonyIntegrator, meBridge, monitor)
        end
    })
    table.insert(programMenu, {
        label = "Export Building materials from ME system",
        callback = function()
            ColonyHelper.exportAllBuilderMaterialsFromME(colonyIntegrator, meBridge, monitor)
        end
    })
end

table.insert(programMenu, {
    label = "Clear log",
    callback = function()
        monitor.clearTab(LOG_TAB)
    end
})

-- Add exit entry (always last)
table.insert(programMenu, {
    label = "Exit",
    callback = function()
        monitor.showDialog(
                "Are you sure?",
                colors.blue,
                {
                    { label = "Yes", callback = function()
                        monitor.showDialog({ "Goodbye!" })
                        sleep(2)
                        monitor.clear()
                        monitor.drawSplash({
                            "It's now safe to turn off",
                            "     your computer"
                        }, colors.black, colors.orange)
                        RUNNING = false
                    end },
                    { label = "No", callback = function()
                        monitor.closeDialog()
                    end }
                }
        )
    end
})

monitor.addMenu("Program", programMenu)
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

---handle touch
local function handleTouches()
    while RUNNING do
        local event, side, x, y = os.pullEvent("monitor_touch")
        monitor.handleTouch(x, y)
    end
end

---colonyLogic
local function colonyLogic()
    local sleepTime = 1
    local players = {}
    local noPlayerCount = 0
    local tick = 0
    local oldState

    while RUNNING do
        currentState = monitor.currentTab;

        if oldState ~= currentState then
            tick = 0
        end
        oldState = currentState

        -- only if the current state changes, once every 5 ticks or 1 tick on fast mode (seconds)
        if tick == 0 then

            ----------------------------------------------------------
            -- COLONY tab logic
            ----------------------------------------------------------
            if currentState == COLONY then
                local overview = ColonyHelper.formatOverview(colonyIntegrator)
                monitor.clearTab(COLONY)
                monitor.printToTab(COLONY, overview)
            end

            ----------------------------------------------------------
            -- CITIZEN tab logic
            ----------------------------------------------------------
            if currentState == CITIZENS then
                local citizens = colonyIntegrator.getCitizens()
                monitor.clearTab(CITIZENS)
                for _, citizen in ipairs(citizens) do
                    monitor.printToTab(CITIZENS, ColonyHelper.formatCitizen(citizen))
                    if config.showCitizenSkill then
                        monitor.printToTab(CITIZENS, ColonyHelper.formatSkills(citizen.skills, config.skillsPerLine, 2))
                    end
                end
            end
            ----------------------------------------------------------
            -- Visitors tab logic
            ----------------------------------------------------------
            if currentState == VISITORS then
                local visitors = colonyIntegrator.getVisitors()
                monitor.clearTab(VISITORS)
                for _, visitor in ipairs(visitors) do
                    local avg = ColonyHelper.getAverageSkill(visitor.skills)

                    monitor.printToTab(VISITORS, {
                        { text = visitor.name, color = colors.orange },
                        { text = " | ", color = colors.lightGray },
                        { text = "Avg: ", color = colors.white },
                        { text = tostring(avg), color = ColonyHelper.skillColor(avg) }
                    })
                    monitor.printToTab(VISITORS, ColonyHelper.formatSkills(visitor.skills, config.skillsPerLine, 2))
                    monitor.printToTab(VISITORS, ColonyHelper.formatRecruitCost(visitor.recruitCost, 4))
                end
            end

            ----------------------------------------------------------
            -- NEEDS tab logic TODO: REMOVE
            ----------------------------------------------------------
            if currentState == NEEDS then

                local requests = colonyIntegrator.getRequests() or {}
                if not ME_DRIVE then
                    --------------------------------------------------
                    -- No ME system: plain needs display
                    --------------------------------------------------
                    local needs = ColonyHelper.formatNeeds(requests)

                    monitor.clearTab(NEEDS)
                    monitor.printToTab(NEEDS, needs)

                else
                    --------------------------------------------------
                    -- ME system available: AE2-aware needs display
                    --------------------------------------------------
                    local needs = ColonyHelper.formatNeedWithME(requests, meBridge)

                    monitor.clearTab(NEEDS)
                    monitor.printToTab(NEEDS, needs)
                end
            end

            ----------------------------------------------------------
            -- WORK ORDERS tab logic
            ----------------------------------------------------------
            if currentState == WORK_ORDERS then
                local workOrders = ColonyHelper.formatWorkOrders(colonyIntegrator)
                monitor.clearTab(WORK_ORDERS)
                monitor.printToTab(WORK_ORDERS, workOrders)
            end
            ----------------------------------------------------------
            -- BUILDER NEEDS tab logic
            ----------------------------------------------------------
            if currentState == BUILDER then
                local workOrders = ColonyHelper.formatBuilderNeeds(colonyIntegrator)
                monitor.clearTab(BUILDER)
                monitor.printToTab(BUILDER, workOrders)
            end


            -- Logic end
        end
        if currentState == DEBUG then
            --local requests = colonyIntegrator.getRequests() or {}
            --local debug = dumpToPrintable(colonyIntegrator)

            monitor.clearTab(DEBUG)
            --monitor.printToTab(DEBUG, debug)

            local orders = colonyIntegrator.getWorkOrders()
            monitor.clearTab(DEBUG)

            monitor.printToTab(DEBUG, {
                { text = "getWorkOrders():", color = colors.cyan }
            })

            monitor.printToTab(DEBUG, dumpToPrintable(orders))

            -- Inspect first work order resources explicitly
            if orders and orders[1] and orders[1].id then
                monitor.printToTab(DEBUG, {})
                monitor.printToTab(DEBUG, {
                    { text = "getWorkOrderResources(" .. orders[1].id .. "):", color = colors.cyan }
                })

                local ok, res = pcall(colonyIntegrator.getWorkOrderResources, orders[1].id)
                if ok then
                    monitor.printToTab(DEBUG, dumpToPrintable(res))
                else
                    monitor.printToTab(DEBUG, {
                        { text = "Error calling getWorkOrderResources()", color = colors.red }
                    })
                end
            else
                monitor.printToTab(DEBUG, {
                    { text = "No valid work order ID found.", color = colors.red }
                })
            end

        end
        ----------------------------------------------------------
        -- Player detection
        ----------------------------------------------------------
        players = playerDetector.getPlayersInRange(config.activityRadius)

        if #players > 0 then
            --for k, v in ipairs(players) do
            --    print(v .. " is nearby")
            --end
            -- monitor.print("Player nearby")

            noPlayerCount = 0
            sleepTime = 1

        else
            sleepTime = 15
            noPlayerCount = noPlayerCount + 1
            monitor.showDialog("No player nearby, sleeping for a moment", colors.yellow)
        end

        -- Update ticks
        if not config.fastUpdate then
            tick = tick + 1
            if tick > 4 then
                tick = 0
            end
        end

        -- stop the program if no player for extended time
        if noPlayerCount > config.noPlayerCount then
            RUNNING = false
        end

        sleep(sleepTime)
    end
end

parallel.waitForAny(handleTouches, colonyLogic)