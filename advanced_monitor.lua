-- advanced_monitor.lua

local MonitorModule = {}

-- monitor variables
MonitorModule.peripherals = nil
MonitorModule.monitor = nil


-- menus
MonitorModule.menuItems = {}        -- { name = { dropdown = { {label, callback}, ... } } }
MonitorModule.menuOrder = {}   -- maintains menu order
MonitorModule.menuHitboxes = {}     -- menu bar clickable zones
MonitorModule.dropdownHitboxes = {} -- dropdown clickable zones
MonitorModule.openDropdown = nil    -- name of currently open dropdown

-- tabs
MonitorModule.tabs = {}          -- { name = { lines = {}, color = ... } } TODO: formating for content? color, bg, etc
MonitorModule.tabOrder = {}      -- ordered list of tab names
MonitorModule.currentTab = nil   -- currently active tab

-- dialog
MonitorModule.activeDialog = nil       -- { lines = {...}, bgColor, buttons = {...} }
MonitorModule.dialogHitboxes = {}      -- For buttons


----------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------

function MonitorModule.initialize(peripherals_input)
    MonitorModule.peripherals = peripherals_input
end

function MonitorModule.ensureDefaultTab()
    if #MonitorModule.tabOrder == 0 then
        MonitorModule.addTab("Home", colors.black)
        term.write("Added default Home tab")
    end
end

function MonitorModule.getMonitor()
    if MonitorModule.monitor then
        return MonitorModule.monitor
    end

    if not MonitorModule.peripherals then
        error("MonitorModule not initialized: no peripherals module provided")
    end

    local mon, err = MonitorModule.peripherals.getPeripheralByType("monitor")
    if not mon then
        error(err)
    end

    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)

    MonitorModule.monitor = mon
    return mon
end

----------------------------------------------------------
-- TITLE
----------------------------------------------------------

function MonitorModule.setTitle(text)
    local mon = MonitorModule.getMonitor()
    local w, _ = mon.getSize()

    mon.setCursorPos(1, 1)
    mon.clearLine()

    local x = math.floor((w - #text) / 2) + 1

    mon.setCursorPos(x, 1)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.yellow)
    mon.write(text)

    mon.setTextColor(colors.white)
end

----------------------------------------------------------
-- MENU SYSTEM
-- todo: update and delete menu entries
----------------------------------------------------------
function MonitorModule.addMenu(name, entries)
    MonitorModule.menuItems[name] = {
        dropdown = entries or {}
    }

    -- Keep insertion order
    table.insert(MonitorModule.menuOrder, name)

    MonitorModule.render()
end

----------------------------------------------------------
-- TAB SYSTEM
----------------------------------------------------------

--- Add a new tab
function MonitorModule.addTab(name, color)
    if not MonitorModule.tabs[name] then
        MonitorModule.tabs[name] = {
            lines = {},
            color = color or colors.white
        }

        -- preserve insertion order
        table.insert(MonitorModule.tabOrder, name)
    end

    if not MonitorModule.currentTab then
        MonitorModule.currentTab = name
    end

    MonitorModule.render()
end

--- Switch to an existing tab
function MonitorModule.switchTab(name)
    if not MonitorModule.tabs[name] then
        error("Tab does not exist: " .. name)
    end

    MonitorModule.currentTab = name
    MonitorModule.render()
end

--- Add a line to a specific tab
function MonitorModule.printToTab(tabName, text)
    if not MonitorModule.tabs[tabName] then
        error("Tab does not exist: " .. tabName)
    end

    local tab = MonitorModule.tabs[tabName]
    table.insert(tab.lines, tostring(text))

    if tabName == MonitorModule.currentTab then
        MonitorModule.render()
    end
end

--- Add line to current tab
function MonitorModule.print(text)
    if not MonitorModule.currentTab then
        MonitorModule.ensureDefaultTab()
    end
    MonitorModule.printToTab(MonitorModule.currentTab, text)
end

----------------------------------------------------------
-- RENDER ENGINE
----------------------------------------------------------
function MonitorModule.render()
    MonitorModule.ensureDefaultTab()
    local mon = MonitorModule.getMonitor()
    local w, h = mon.getSize()

    ----------------------------------------------------
    -- 1. MENU BAR (line 2)
    ----------------------------------------------------
    MonitorModule.menuHitboxes = {}

    mon.setCursorPos(1, 2)
    mon.clearLine()

    local xpos = 1
    for _, name in ipairs(MonitorModule.menuOrder) do
        local menu = MonitorModule.menuItems[name]
        local label = "[" .. name .. "]"
        local len = #label

        MonitorModule.menuHitboxes[name] = { x1 = xpos, x2 = xpos + len - 1 }

        mon.setCursorPos(xpos, 2)

        if MonitorModule.openDropdown == name then
            -- MENU OPEN → greyed text
            mon.setBackgroundColor(colors.black)
            mon.setTextColor(colors.lightGray)
        else
            mon.setBackgroundColor(colors.black)
            mon.setTextColor(colors.cyan)
        end

        mon.write(label)
        xpos = xpos + len + 1
    end

    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)

    ----------------------------------------------------
    -- 3. TABS (always on line 3)
    ----------------------------------------------------
    local tabLine = 3
    MonitorModule.tabHitboxes = {}

    mon.setCursorPos(1, tabLine)
    mon.clearLine()

    local xpos = 1
    for _, name in ipairs(MonitorModule.tabOrder) do
        local tabData = MonitorModule.tabs[name]
        local tabColor = tabData.color or colors.white

        ------------------------------------------------
        -- ACTIVE TAB
        ------------------------------------------------
        if MonitorModule.currentTab == name then
            -- Format: "> Tab <"
            local text = "> " .. name .. " <"

            -- Hitbox
            local len = #text
            MonitorModule.tabHitboxes[name] = { x1 = xpos, x2 = xpos + len - 1 }

            mon.setCursorPos(xpos, tabLine)

            -- Background of active tab
            mon.setBackgroundColor(colors.gray)

            -- Write "> " in tab color
            mon.setTextColor(tabColor)
            mon.write("> ")

            -- Write tab name in normal white
            mon.setTextColor(colors.black)
            mon.write(name)

            -- Write " <" in tab color
            mon.setTextColor(tabColor)
            mon.write(" <")

            xpos = xpos + len + 1
        else
            ------------------------------------------------
            -- INACTIVE TAB
            ------------------------------------------------
            local text = " " .. name .. " "
            local len = #text
            MonitorModule.tabHitboxes[name] = { x1 = xpos, x2 = xpos + len - 1 }

            mon.setCursorPos(xpos, tabLine)

            mon.setBackgroundColor(colors.black)
            mon.setTextColor(tabColor)       -- INACTIVE TAB USES ITS COLOR

            mon.write(text)

            xpos = xpos + len + 1
        end
    end

    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)


    ----------------------------------------------------
    -- 4. TAB CONTENT + COLORED PADDING (1 cell).
    -- TODO: Scroll???
    ----------------------------------------------------
    local tab = MonitorModule.tabs[MonitorModule.currentTab]
    local contentTop = 4

    -- Fallback color if no tab or no color
    local borderColor = (tab and tab.color) or colors.white

    -- --- Draw colored border --------------------------------
    mon.setBackgroundColor(borderColor)
    mon.setTextColor(colors.black)

    -- Top border
    mon.setCursorPos(1, contentTop)
    mon.write(string.rep(" ", w))

    -- Bottom border
    mon.setCursorPos(1, h)
    mon.write(string.rep(" ", w))

    -- Left + right borders
    for y = contentTop + 1, h - 1 do
        mon.setCursorPos(1, y)
        mon.write(" ")        -- left border
        mon.setCursorPos(w, y)
        mon.write(" ")        -- right border
    end

    -- --- Clear inner area (inside the border) ---------------
    local innerX1 = 2
    local innerX2 = w - 1
    local innerY1 = contentTop + 1
    local innerY2 = h - 1
    local innerWidth = innerX2 - innerX1 + 1

    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)

    for y = innerY1, innerY2 do
        mon.setCursorPos(innerX1, y)
        mon.write(string.rep(" ", innerWidth))
    end

    -- --- Draw tab content inside the inner area -------------
    if tab then
        local y = innerY1
        for _, line in ipairs(tab.lines) do
            if y > innerY2 then
                break
            end
            local text = tostring(line)
            if #text > innerWidth then
                text = text:sub(1, innerWidth) -- clip to fit inside padding
            end
            mon.setCursorPos(innerX1, y)
            mon.write(text)
            y = y + 1
        end
    end

    ----------------------------------------------------
    -- 5. DRAW DROPDOWN LAST (on top of tabs + content)
    ----------------------------------------------------
    MonitorModule.dropdownHitboxes = {}

    if MonitorModule.openDropdown then
        local menu = MonitorModule.menuItems[MonitorModule.openDropdown]
        if menu and menu.dropdown then
            local x = MonitorModule.menuHitboxes[MonitorModule.openDropdown].x1
            local y = 3   -- dropdown appears under menu bar

            ------------------------------------------------
            -- Compute max width of all menu items
            ------------------------------------------------
            local maxWidth = 0
            for _, entry in ipairs(menu.dropdown) do
                if #entry.label > maxWidth then
                    maxWidth = #entry.label
                end
            end
            maxWidth = maxWidth + 2 -- padding

            ------------------------------------------------
            -- DRAW SHADOW FIRST
            ------------------------------------------------
            mon.setBackgroundColor(colors.gray)
            mon.setTextColor(colors.gray)

            local shadowX = x + 1
            local shadowY = y + 1
            for i = 1, #menu.dropdown do
                mon.setCursorPos(shadowX, shadowY)
                mon.write(string.rep(" ", maxWidth))
                shadowY = shadowY + 1
            end

            ------------------------------------------------
            -- DRAW DROPDOWN BOX
            ------------------------------------------------
            for i, entry in ipairs(menu.dropdown) do
                local label = entry.label

                -- Register hitbox
                table.insert(MonitorModule.dropdownHitboxes, {
                    x1 = x,
                    x2 = x + maxWidth - 1,
                    y = y,
                    callback = entry.callback,
                })

                mon.setCursorPos(x, y)
                mon.setBackgroundColor(colors.blue)
                mon.setTextColor(colors.white)

                local padding = maxWidth - (#label + 1)
                mon.write(" " .. label .. string.rep(" ", padding))

                y = y + 1
            end

            mon.setBackgroundColor(colors.black)
            mon.setTextColor(colors.white)
        end
    end


    ----------------------------------------------------
    -- 6. DIALOG WINDOW (drawn above everything)
    ----------------------------------------------------
    if MonitorModule.activeDialog then
        local dlg = MonitorModule.activeDialog
        local lines = dlg.lines
        local bg = dlg.bgColor
        local buttons = dlg.buttons or {}

        local mon = MonitorModule.monitor
        local w, h = mon.getSize()

        ----------------------------------------------------
        -- Compute box size (same as before)
        ----------------------------------------------------
        local textWidth = 0
        for _, line in ipairs(lines) do
            if #line > textWidth then
                textWidth = #line
            end
        end

        local btnWidthTotal = 0
        for i, btn in ipairs(buttons) do
            btnWidthTotal = btnWidthTotal + (#btn.label + 4)
            if i < #buttons then
                btnWidthTotal = btnWidthTotal + 1
            end
        end

        local contentWidth = math.max(textWidth, btnWidthTotal)

        local padding = 2
        local boxW = contentWidth + padding * 2
        local boxH = #lines + padding * 2
        if #buttons > 0 then
            boxH = boxH + 2
        end

        ----------------------------------------------------
        -- Center the box
        ----------------------------------------------------
        local startX = math.floor((w - boxW) / 2) + 1
        local startY = math.floor((h - boxH) / 2) + 1

        MonitorModule.dialogHitboxes = {}
        MonitorModule.dialogHitbox = {
            x1 = startX, y1 = startY,
            x2 = startX + boxW - 1,
            y2 = startY + boxH - 1
        }

        ----------------------------------------------------
        -- DRAW SHADOW FIRST  (offset 1,1)
        ----------------------------------------------------
        mon.setBackgroundColor(colors.gray)
        mon.setTextColor(colors.gray)

        local shadowX = startX + 1
        local shadowY = startY + 1

        for y = 0, boxH - 1 do
            mon.setCursorPos(shadowX, shadowY + y)
            mon.write(string.rep(" ", boxW))
        end

        ----------------------------------------------------
        -- DRAW BACKGROUND BOX (same as before)
        ----------------------------------------------------
        mon.setBackgroundColor(bg)
        mon.setTextColor(colors.white)

        for y = 0, boxH - 1 do
            mon.setCursorPos(startX, startY + y)
            mon.write(string.rep(" ", boxW))
        end

        ----------------------------------------------------
        -- Draw centered text
        ----------------------------------------------------
        local y = startY + padding
        for _, line in ipairs(lines) do
            local x = startX + math.floor((boxW - #line) / 2)
            mon.setCursorPos(x, y)
            mon.write(line)
            y = y + 1
        end

        ----------------------------------------------------
        -- Draw buttons
        ----------------------------------------------------
        if #buttons > 0 then
            local buttonY = startY + boxH - padding - 1
            local btnX = startX + math.floor((boxW - btnWidthTotal) / 2)

            for _, btn in ipairs(buttons) do
                local label = btn.label
                local width = #label + 4

                mon.setCursorPos(btnX, buttonY)
                mon.setBackgroundColor(colors.lightGray)
                mon.setTextColor(colors.black)
                mon.write("[ " .. label .. " ]")

                table.insert(MonitorModule.dialogHitboxes, {
                    x1 = btnX,
                    x2 = btnX + width - 1,
                    y = buttonY,
                    callback = btn.callback
                })

                btnX = btnX + width + 1
            end
        end

        ----------------------------------------------------
        -- Reset
        ----------------------------------------------------
        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.white)
    end


    -- Reset
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
end

--- Clear
function MonitorModule.clear()
    local mon = MonitorModule.getMonitor()
    mon.clear()
end

--- Slash display
function MonitorModule.drawSplash(lines, bgColor, textColor)
    local mon = MonitorModule.getMonitor()
    bgColor = bgColor or colors.blue
    textColor = textColor or colors.white
    local w, h = mon.getSize()

    ----------------------------------------------------
    -- Compute block size based on scaled characters
    ----------------------------------------------------
    local blockHeight = #lines
    local blockWidth = 0
    for _, line in ipairs(lines) do
        if #line > blockWidth then
            blockWidth = #line
        end
    end

    local padding = 1
    local paddedWidth = blockWidth + padding * 2
    local paddedHeight = blockHeight + padding * 2

    ----------------------------------------------------
    -- Center box using scaled monitor size
    ----------------------------------------------------
    local startY = math.floor((h - paddedHeight) / 2) + 1
    local startX = math.floor((w - paddedWidth) / 2) + 1

    ----------------------------------------------------
    -- Draw background box
    ----------------------------------------------------
    mon.setBackgroundColor(bgColor)
    mon.setTextColor(textColor)

    for i = 0, paddedHeight - 1 do
        mon.setCursorPos(startX, startY + i)
        mon.write(string.rep(" ", paddedWidth))
    end

    ----------------------------------------------------
    -- Draw ASCII text
    ----------------------------------------------------
    for i, line in ipairs(lines) do
        mon.setCursorPos(startX + padding, startY + padding + i - 1)
        mon.write(line)
    end

    ----------------------------------------------------
    -- Reset colors + scale
    ----------------------------------------------------
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.setTextScale(1)
end

--- Dialog display
function MonitorModule.showDialog(messageOrLines, bgColor, buttons)
    bgColor = bgColor or colors.blue

    -- Normalize message into a list of lines
    local lines
    if type(messageOrLines) == "string" then
        lines = {}
        for line in messageOrLines:gmatch("[^\n]+") do
            table.insert(lines, line)
        end
    else
        lines = messageOrLines
    end

    MonitorModule.activeDialog = {
        lines = lines,
        bgColor = bgColor,
        buttons = buttons or {}
    }

    MonitorModule.render()
end

function MonitorModule.closeDialog()
    MonitorModule.activeDialog = nil
    MonitorModule.render()
end


----------------------------------------------------------
-- INTERACTIONS
----------------------------------------------------------
function MonitorModule.handleTouch(x, y)

    ------------------------------------------------
    -- 1. DIALOG CLICKS
    ------------------------------------------------
    if MonitorModule.activeDialog then
        for _, box in ipairs(MonitorModule.dialogHitboxes) do
            if y == box.y and x >= box.x1 and x <= box.x2 then
                local callback = box.callback
                MonitorModule.closeDialog()
                if callback then
                    callback()
                end
                return
            end
        end

        -- Otherwise click closes dialog
        MonitorModule.closeDialog()
        return
    end

    ------------------------------------------------
    -- 2. MENU BAR CLICKS (always active)
    ------------------------------------------------
    if y == 2 then
        for name, box in pairs(MonitorModule.menuHitboxes) do
            if x >= box.x1 and x <= box.x2 then

                -- Toggle dropdown
                if MonitorModule.openDropdown == name then
                    MonitorModule.openDropdown = nil
                else
                    MonitorModule.openDropdown = name
                end

                MonitorModule.render()
                return
            end
        end
    end

    ------------------------------------------------
    -- 3. DROPDOWN OPEN → ONLY dropdown can be clicked
    ------------------------------------------------
    if MonitorModule.openDropdown then

        -- Click on a dropdown entry
        for _, box in ipairs(MonitorModule.dropdownHitboxes) do
            if y == box.y and x >= box.x1 and x <= box.x2 then
                box.callback()
                MonitorModule.openDropdown = nil
                MonitorModule.render()
                return
            end
        end

        -- Click outside closes dropdown
        MonitorModule.openDropdown = nil
        MonitorModule.render()
        return
    end


    ------------------------------------------------
    -- 4. TABS (only active when no dropdown open)
    ------------------------------------------------
    if y == 3 then
        -- ← tabs are ALWAYS on line 3 now
        for name, box in pairs(MonitorModule.tabHitboxes) do
            if x >= box.x1 and x <= box.x2 then
                MonitorModule.switchTab(name)
                return
            end
        end
    end

end

----------------------------------------------------------
return MonitorModule
----------------------------------------------------------
