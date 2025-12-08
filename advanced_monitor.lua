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
MonitorModule.tabs = {}          -- { name = { lines = line, color = ... } }
                                 -- TODO: line type should be a list of parts, each part being = { text = string, color = string}
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
    -- RESET ALL OTHER VARIABLES
    MonitorModule.monitor = nil
    -- menus
    MonitorModule.menuItems = {}
    MonitorModule.menuOrder = {}
    MonitorModule.menuHitboxes = {}
    MonitorModule.dropdownHitboxes = {}
    MonitorModule.openDropdown = nil
    -- tabs
    MonitorModule.tabs = {}
    MonitorModule.tabOrder = {}
    MonitorModule.currentTab = nil
    -- dialog
    MonitorModule.activeDialog = nil
    MonitorModule.dialogHitboxes = {}
end

function MonitorModule.ensureDefaultTab()
    if #MonitorModule.tabOrder == 0 then
        MonitorModule.addTab("Home", colors.black)
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
            color = color or colors.white,
            width = 0, -- << NEW widest line
            hscroll = 0, -- horizontal scroll offset
            vscroll = 0    -- vertical scroll offset
        }
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
    local tab = MonitorModule.tabs[name]
    tab.hscroll = 0
    tab.vscroll = 0
    MonitorModule.render()
end

--- Clears a tab's content
function MonitorModule.clearTab(tabName)
    if not MonitorModule.tabs[tabName] then
        error("Tab does not exist: " .. tabName)
    end

    local tab = MonitorModule.tabs[tabName]

    -- Clear the content of the tab
    tab.lines = {}
    tab.width = 0

    -- Only re-render active tab
    if tabName == MonitorModule.currentTab then
        MonitorModule.render()
    end
end

function MonitorModule.printToTab(tabName, value)
    local tab = MonitorModule.tabs[tabName]
    if not tab then
        error("Tab does not exist: " .. tostring(tabName))
    end

    -------------------------------------------------------------------------
    -- Helpers
    -------------------------------------------------------------------------
    local function toSegment(v)
        if type(v) == "table" and type(v.text) == "string" then
            return { text = v.text, color = v.color or colors.white }
        elseif type(v) == "string" then
            return { text = v, color = colors.white }
        else
            error("Invalid segment: " .. tostring(v))
        end
    end

    local function toLine(v)
        -- string → one segment line
        if type(v) == "string" then
            return { toSegment(v) }
        end

        -- single segment table → one segment line
        if type(v) == "table" and type(v.text) == "string" then
            return { toSegment(v) }
        end

        -- table of segments / strings → multi-segment line
        if type(v) == "table" then
            local line = {}
            for _, seg in ipairs(v) do
                table.insert(line, toSegment(seg))
            end
            return line
        end

        error("Invalid line: " .. tostring(v))
    end

    -------------------------------------------------------------------------
    -- Normalize input into list of lines
    -------------------------------------------------------------------------
    local lines = {}

    if type(value) == "string" then
        table.insert(lines, toLine(value))

    elseif type(value) == "table" then
        -- single segment at top level
        if type(value.text) == "string" then
            table.insert(lines, toLine(value))
        else
            local first = value[1]
            if first == nil then
                return          -- empty table: nothing to print
            end

            -- list of plain strings → many one-segment lines
            if type(first) == "string" then
                for _, s in ipairs(value) do
                    table.insert(lines, toLine(s))
                end

                -- list of lines: { {seg,...}, {seg,...}, ... }
            elseif type(first) == "table"
                    and type(first[1]) == "table"
                    and type(first[1].text) == "string" then

                for _, line in ipairs(value) do
                    table.insert(lines, toLine(line))
                end

                -- otherwise: treat whole table as a single multi-segment line
            else
                table.insert(lines, toLine(value))
            end
        end
    else
        error("Unsupported input to printToTab: " .. tostring(value))
    end

    -------------------------------------------------------------------------
    -- Append lines and update width
    -------------------------------------------------------------------------
    for _, lineParts in ipairs(lines) do
        table.insert(tab.lines, lineParts)

        local totalLen = 0
        for _, seg in ipairs(lineParts) do
            totalLen = totalLen + #seg.text
        end
        if totalLen > tab.width then
            tab.width = totalLen
        end
    end

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

    -- Force-clear menu bar (fixes dropdown shadow artifacts)
    mon.setCursorPos(1, 2)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.write(string.rep(" ", w))

    local xpos = 1
    for _, name in ipairs(MonitorModule.menuOrder) do
        local label = "[" .. name .. "]"
        local len = #label

        MonitorModule.menuHitboxes[name] = { x1 = xpos, x2 = xpos + len - 1 }

        mon.setCursorPos(xpos, 2)

        if MonitorModule.openDropdown == name then
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
    -- 2. TABS (line 3)
    ----------------------------------------------------
    local tabLine = 3
    MonitorModule.tabHitboxes = {}

    -- CLEAR TAB LINE (fixes leftover blue background)
    mon.setCursorPos(1, tabLine)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.write(string.rep(" ", w))

    xpos = 1
    for _, name in ipairs(MonitorModule.tabOrder) do
        local tabData = MonitorModule.tabs[name]
        local tabColor = tabData.color or colors.white

        if MonitorModule.currentTab == name then
            local text = "> " .. name .. " <"
            local len = #text

            MonitorModule.tabHitboxes[name] = { x1 = xpos, x2 = xpos + len - 1 }

            mon.setCursorPos(xpos, tabLine)
            mon.setBackgroundColor(colors.gray)

            mon.setTextColor(tabColor)
            mon.write("> ")

            mon.setTextColor(colors.black)
            mon.write(name)

            mon.setTextColor(tabColor)
            mon.write(" <")

            xpos = xpos + len + 1
        else
            local text = " " .. name .. " "
            local len = #text

            MonitorModule.tabHitboxes[name] = { x1 = xpos, x2 = xpos + len - 1 }

            mon.setCursorPos(xpos, tabLine)
            mon.setBackgroundColor(colors.black)
            mon.setTextColor(tabColor)
            mon.write(text)

            xpos = xpos + len + 1
        end
    end

    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)

    ----------------------------------------------------
    -- 3. TAB CONTENT BORDER
    ----------------------------------------------------
    local tab = MonitorModule.tabs[MonitorModule.currentTab]
    local contentTop = 4

    local borderColor = (tab and tab.color) or colors.white

    -- Top border
    mon.setCursorPos(1, contentTop)
    mon.setBackgroundColor(borderColor)
    mon.write(string.rep(" ", w))

    -- Bottom border
    mon.setCursorPos(1, h)
    mon.write(string.rep(" ", w))

    -- Left + right borders (but do NOT override scroll buttons)
    for y = contentTop + 1, h - 1 do
        -- left border
        if y ~= (contentTop + 1) and y ~= (h - 1) then
            mon.setCursorPos(1, y)
            mon.write(" ")
        end

        -- right border
        mon.setCursorPos(w, y)
        mon.write(" ")
    end

    ----------------------------------------------------
    -- 4. CLEAR INNER AREA
    ----------------------------------------------------
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

    ----------------------------------------------------
    -- 5. DRAW TAB CONTENT (with both scrolls, multi-segment lines)
    ----------------------------------------------------
    if tab then
        local y = innerY1
        local startLine = 1 + tab.vscroll
        local endLine = #tab.lines

        for i = startLine, endLine do
            if y > innerY2 then
                break
            end

            local line = tab.lines[i]

            ------------------------------------------------------------------
            -- Normalize: string → { {text=..., color=white} }
            ------------------------------------------------------------------
            local parts
            if type(line) == "string" then
                parts = { { text = line, color = colors.white } }
            else
                parts = line
            end

            ------------------------------------------------------------------
            -- Horizontal scrolling logic
            ------------------------------------------------------------------
            local hskip = tab.hscroll
            local x = innerX1

            for _, seg in ipairs(parts) do
                local segText = seg.text or ""
                local segColor = seg.color or colors.white
                local segLen = #segText

                -- Skip characters removed by left scroll
                if hskip >= segLen then
                    hskip = hskip - segLen
                else
                    -- Take the visible part of this segment after horizontal skip
                    local visibleText = segText:sub(hskip + 1)
                    hskip = 0

                    -- Trim right side if needed for innerWidth
                    if x + #visibleText - 1 > innerX2 then
                        visibleText = visibleText:sub(1, innerX2 - x + 1)
                    end

                    if #visibleText > 0 then
                        mon.setCursorPos(x, y)
                        mon.setTextColor(segColor)
                        mon.write(visibleText)
                        x = x + #visibleText
                    end

                    -- Stop if we've filled the inner width
                    if x > innerX2 then
                        break
                    end
                end
            end

            y = y + 1
        end
    end

    -- reset drawing colors and store inner sizes for scrollbars
    mon.setTextColor(colors.white)
    mon.setBackgroundColor(colors.black)
    MonitorModule.innerWidth = innerWidth
    MonitorModule.innerHeight = innerY2 - innerY1 + 1

    ----------------------------------------------------
    -- 6. HORIZONTAL SCROLL BUTTONS (bottom)
    ----------------------------------------------------
    local bottomY = h
    local scrollColor = (tab and tab.color) or colors.white

    local leftLabel = " < "
    local rightLabel = " > "

    -- left button
    local leftX = 2
    mon.setCursorPos(leftX, bottomY)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(scrollColor)
    mon.write(leftLabel)

    MonitorModule.scrollLeftHitbox = {
        x1 = leftX,
        x2 = leftX + #leftLabel - 1,
        y = bottomY
    }

    -- right button
    local rightX = w - (#rightLabel + 1)
    mon.setCursorPos(rightX, bottomY)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(scrollColor)
    mon.write(rightLabel)

    MonitorModule.scrollRightHitbox = {
        x1 = rightX,
        x2 = rightX + #rightLabel - 1,
        y = bottomY
    }

    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)

    ----------------------------------------------------
    -- 6b. HORIZONTAL SCROLLBAR (fixed 7-cell thumb)
    ----------------------------------------------------
    local maxHScroll = 0
    if tab then
        maxHScroll = math.max(0, tab.width - MonitorModule.innerWidth)
    end

    if tab and maxHScroll > 0 then
        local barY = h                       -- bottom border line
        local barX1 = 2 + #leftLabel         -- after "<"
        local barX2 = rightX - 1             -- before ">"
        local barWidth = barX2 - barX1 + 1

        -- Thumb is always 7 characters: 1 black + 5 white + 1 black
        local thumbWidth = 7

        -- Movable range
        local movable = barWidth - thumbWidth
        if movable < 0 then
            movable = 0
        end

        -- Thumb position based on hscroll
        local thumbPos = 0
        if maxHScroll > 0 then
            thumbPos = math.floor((tab.hscroll / maxHScroll) * movable)
        end

        local thumbStart = barX1 + thumbPos
        local thumbEnd = thumbStart + thumbWidth - 1

        ------------------------------------------------
        -- Draw scrollbar track (border color)
        ------------------------------------------------
        for xx = barX1, barX2 do
            mon.setCursorPos(xx, barY)
            mon.setBackgroundColor(borderColor)
            mon.write(" ")
        end

        ------------------------------------------------
        -- Draw thumb (1 black, 5 white, 1 black)
        ------------------------------------------------
        local x = thumbStart

        -- left black cell
        mon.setCursorPos(x, barY)
        mon.setBackgroundColor(colors.black)
        mon.write(" ")
        x = x + 1

        -- 5 white cells
        for i = 1, 5 do
            mon.setCursorPos(x, barY)
            mon.setBackgroundColor(colors.white)
            mon.write(" ")
            x = x + 1
        end

        -- right black cell
        mon.setCursorPos(x, barY)
        mon.setBackgroundColor(colors.black)
        mon.write(" ")
    end


    ----------------------------------------------------
    -- 7. VERTICAL SCROLL BUTTONS (on left border)
    ----------------------------------------------------
    local upLabel = "^"
    local downLabel = "v"

    local scrollX = 1
    local upY = innerY1
    local downY = innerY2

    -- Choose text color that contrasts the border
    local arrowTextColor = colors.black
    if borderColor == colors.black then
        arrowTextColor = scrollColor  -- fallback
    end

    -- UP BUTTON
    mon.setCursorPos(scrollX, upY)
    mon.setBackgroundColor(arrowTextColor)
    mon.setTextColor(borderColor)
    mon.write(upLabel)

    MonitorModule.scrollUpHitbox = {
        x1 = scrollX,
        x2 = scrollX,
        y = upY
    }

    -- DOWN BUTTON
    mon.setCursorPos(scrollX, downY)
    mon.setBackgroundColor(arrowTextColor)
    mon.setTextColor(borderColor)
    mon.write(downLabel)

    MonitorModule.scrollDownHitbox = {
        x1 = scrollX,
        x2 = scrollX,
        y = downY
    }

    ----------------------------------------------------
    -- 7b. VERTICAL SCROLLBAR (fixed 7-cell thumb)
    ----------------------------------------------------
    local totalLines = tab and #tab.lines or 0
    local visibleLines = MonitorModule.innerHeight
    local maxVScroll = math.max(0, totalLines - visibleLines)

    -- Only draw a scrollbar if there is something to scroll
    if tab and maxVScroll > 0 then
        local barX = 1
        local barY1 = innerY1 + 1          -- below ^
        local barY2 = innerY2 - 1          -- above v
        local barHeight = barY2 - barY1 + 1

        -- Thumb height: exactly 7 rows
        local thumbHeight = 7
        local topBlack = 1
        local midWhite = 5
        local bottomBlack = 1

        -- Range thumb can move
        local movable = barHeight - thumbHeight
        if movable < 0 then
            movable = 0
        end

        -- Thumb position proportional to vscroll
        local thumbOffset = 0
        if maxVScroll > 0 then
            thumbOffset = math.floor((tab.vscroll / maxVScroll) * movable)
        end

        local thumbTop = barY1 + thumbOffset
        local thumbBottom = thumbTop + thumbHeight - 1

        ------------------------------------------------
        -- Draw full scrollbar background (border color)
        ------------------------------------------------
        for yy = barY1, barY2 do
            mon.setCursorPos(barX, yy)
            mon.setBackgroundColor(borderColor)
            mon.write(" ")
        end

        ------------------------------------------------
        -- Draw fixed 7-cell thumb
        ------------------------------------------------
        local row = thumbTop

        -- 1 black cell
        mon.setCursorPos(barX, row)
        mon.setBackgroundColor(colors.black)
        mon.write(" ")
        row = row + 1

        -- 5 white cells
        for i = 1, midWhite do
            mon.setCursorPos(barX, row)
            mon.setBackgroundColor(colors.white)
            mon.write(" ")
            row = row + 1
        end

        -- 1 black cell
        mon.setCursorPos(barX, row)
        mon.setBackgroundColor(colors.black)
        mon.write(" ")
    end

    ----------------------------------------------------
    -- 8. DROPDOWN MENU (draw last)
    ----------------------------------------------------
    MonitorModule.dropdownHitboxes = {}

    if MonitorModule.openDropdown then
        local menu = MonitorModule.menuItems[MonitorModule.openDropdown]
        if menu and menu.dropdown then
            local x = MonitorModule.menuHitboxes[MonitorModule.openDropdown].x1
            local y = 3

            -- find widest label
            local maxWidth = 0
            for _, entry in ipairs(menu.dropdown) do
                maxWidth = math.max(maxWidth, #entry.label)
            end
            maxWidth = maxWidth + 2

            -- shadow
            mon.setBackgroundColor(colors.gray)
            mon.setTextColor(colors.gray)

            local shadowX = x + 1
            local shadowY = y + 1
            for i = 1, #menu.dropdown do
                mon.setCursorPos(shadowX, shadowY)
                mon.write(string.rep(" ", maxWidth))
                shadowY = shadowY + 1
            end

            -- dropdown
            for i, entry in ipairs(menu.dropdown) do
                mon.setCursorPos(x, y)
                mon.setBackgroundColor(colors.blue)
                mon.setTextColor(colors.white)

                local padding = maxWidth - (#entry.label + 1)
                mon.write(" " .. entry.label .. string.rep(" ", padding))

                table.insert(MonitorModule.dropdownHitboxes, {
                    label = entry.label,
                    x1 = x,
                    x2 = x + maxWidth - 1,
                    y = y,
                    callback = entry.callback
                })

                y = y + 1
            end
        end
    end

    ----------------------------------------------------
    -- 9. DIALOG (always topmost)
    ----------------------------------------------------
    if MonitorModule.activeDialog then
        local dlg = MonitorModule.activeDialog
        MonitorModule.dialogHitboxes = {}

        local lines = dlg.lines
        local buttons = dlg.buttons
        local bg = dlg.bgColor or colors.blue

        local w, h = mon.getSize()

        ------------------------------------------------
        -- Compute dialog box size
        ------------------------------------------------
        local textWidth = 0
        for _, line in ipairs(lines) do
            if #line > textWidth then
                textWidth = #line
            end
        end

        local buttonWidth = 0
        for _, b in ipairs(buttons) do
            if #b.label > buttonWidth then
                buttonWidth = #b.label
            end
        end

        local boxWidth = math.max(textWidth, buttonWidth) + 4  -- padding
        local boxHeight = #lines + ((#buttons > 0) and 3 or 2)

        local startX = math.floor((w - boxWidth) / 2) + 1
        local startY = math.floor((h - boxHeight) / 2) + 1
        local endX = startX + boxWidth - 1

        ------------------------------------------------
        -- Draw shadow
        ------------------------------------------------
        mon.setBackgroundColor(colors.gray)
        for y = startY + 1, startY + boxHeight do
            mon.setCursorPos(startX + 1, y)
            mon.write(string.rep(" ", boxWidth))
        end

        ------------------------------------------------
        -- Draw box background
        ------------------------------------------------
        mon.setBackgroundColor(bg)
        for y = startY, startY + boxHeight - 1 do
            mon.setCursorPos(startX, y)
            mon.write(string.rep(" ", boxWidth))
        end

        ------------------------------------------------
        -- Draw dialog text
        ------------------------------------------------
        mon.setTextColor(colors.white)
        local y = startY + 1
        for _, line in ipairs(lines) do
            mon.setCursorPos(startX + 2, y)
            mon.write(line)
            y = y + 1
        end

        ------------------------------------------------
        -- Draw buttons
        ------------------------------------------------
        if #buttons > 0 then
            y = startY + boxHeight - 2
            local btnX = startX + 2

            for _, b in ipairs(buttons) do
                local label = "[" .. b.label .. "]"
                mon.setCursorPos(btnX, y)
                mon.setBackgroundColor(colors.white)
                mon.setTextColor(colors.black)
                mon.write(label)

                table.insert(MonitorModule.dialogHitboxes, {
                    x1 = btnX,
                    x2 = btnX + #label - 1,
                    y = y,
                    callback = b.callback
                })

                btnX = btnX + #label + 1
            end
        end

        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.white)
    end
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
-- SCROLL
----------------------------------------------------------
function MonitorModule.scrollLeft()
    local current = MonitorModule.currentTab
    if not current then
        return
    end

    local tab = MonitorModule.tabs[current]
    if not tab then
        return
    end

    if tab.hscroll > 0 then
        tab.hscroll = tab.hscroll - 1
        MonitorModule.render()
    end
end

function MonitorModule.scrollRight()
    local current = MonitorModule.currentTab
    if not current then
        return
    end

    local tab = MonitorModule.tabs[current]
    local maxScroll = math.max(0, tab.width - MonitorModule.innerWidth)

    if tab.hscroll < maxScroll then
        tab.hscroll = tab.hscroll + 1
        MonitorModule.render()
    end
end

function MonitorModule.scrollUp()
    local current = MonitorModule.currentTab
    if not current then
        return
    end

    local tab = MonitorModule.tabs[current]
    if tab.vscroll > 0 then
        tab.vscroll = tab.vscroll - 1
        MonitorModule.render()
    end
end

function MonitorModule.scrollDown()
    local current = MonitorModule.currentTab
    if not current then
        return
    end

    local tab = MonitorModule.tabs[current]
    local visibleLines = MonitorModule.innerHeight
    local maxScroll = math.max(0, #tab.lines - visibleLines)

    if tab.vscroll < maxScroll then
        tab.vscroll = tab.vscroll + 1
        MonitorModule.render()
    end
end


----------------------------------------------------------
-- INTERACTIONS
----------------------------------------------------------
function MonitorModule.handleTouch(x, y)
    ------------------------------------------------------------------
    -- 1. DIALOG CLICKS
    ------------------------------------------------------------------
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

        -- Click anywhere else closes dialog
        MonitorModule.closeDialog()
        return
    end

    ------------------------------------------------------------------
    -- 2. MENU BAR CLICKS (always active)
    ------------------------------------------------------------------
    if y == 2 then
        for name, box in pairs(MonitorModule.menuHitboxes) do
            if x >= box.x1 and x <= box.x2 then
                -- Toggle dropdown for this menu
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


    ------------------------------------------------------------------
    -- 4. SCROLL BUTTONS (horizontal / vertical)
    ------------------------------------------------------------------

    -- Horizontal left button
    if MonitorModule.scrollLeftHitbox
            and y == MonitorModule.scrollLeftHitbox.y
            and x >= MonitorModule.scrollLeftHitbox.x1
            and x <= MonitorModule.scrollLeftHitbox.x2 then
        MonitorModule.scrollLeft()
        return
    end

    -- Horizontal right button
    if MonitorModule.scrollRightHitbox
            and y == MonitorModule.scrollRightHitbox.y
            and x >= MonitorModule.scrollRightHitbox.x1
            and x <= MonitorModule.scrollRightHitbox.x2 then
        MonitorModule.scrollRight()
        return
    end

    -- Vertical up button
    if MonitorModule.scrollUpHitbox
            and y == MonitorModule.scrollUpHitbox.y
            and x >= MonitorModule.scrollUpHitbox.x1
            and x <= MonitorModule.scrollUpHitbox.x2 then
        MonitorModule.scrollUp()
        return
    end

    -- Vertical down button
    if MonitorModule.scrollDownHitbox
            and y == MonitorModule.scrollDownHitbox.y
            and x >= MonitorModule.scrollDownHitbox.x1
            and x <= MonitorModule.scrollDownHitbox.x2 then
        MonitorModule.scrollDown()
        return
    end

    ------------------------------------------------------------------
    -- 5. SCROLLBAR TRACK CLICKS (page scroll behaviour)
    ------------------------------------------------------------------
    local tab = MonitorModule.tabs[MonitorModule.currentTab]
    if tab then
        local mon = MonitorModule.monitor
        local w, h = mon.getSize()

        --------------------------------------------------------------
        -- Horizontal scrollbar track
        --------------------------------------------------------------
        local leftLabel = " < "
        local rightLabel = " > "
        local bottomY = h
        local leftEnd = 2 + #leftLabel              -- after "<"
        local rightStart = w - (#rightLabel + 1)    -- before ">"

        local maxHScroll = math.max(0, tab.width - MonitorModule.innerWidth)
        if maxHScroll > 0 then
            local barX1 = leftEnd
            local barX2 = rightStart - 1
            local barWidth = barX2 - barX1 + 1

            local thumbWidth = 7                     -- fixed thumb size
            local movable = barWidth - thumbWidth
            if movable < 0 then
                movable = 0
            end

            local thumbPos = math.floor((tab.hscroll / maxHScroll) * movable)
            local thumbStart = barX1 + thumbPos
            local thumbEnd = thumbStart + thumbWidth - 1

            -- Click left of thumb
            if y == bottomY and x >= barX1 and x < thumbStart then
                MonitorModule.scrollLeft()
                return
            end

            -- Click right of thumb
            if y == bottomY and x > thumbEnd and x <= barX2 then
                MonitorModule.scrollRight()
                return
            end
        end

        --------------------------------------------------------------
        -- Vertical scrollbar track
        --------------------------------------------------------------
        local innerY1 = 5               -- must match render() (contentTop + 1)
        local innerY2 = h - 1
        local barY1 = innerY1 + 1       -- below ^
        local barY2 = innerY2 - 1       -- above v

        local totalLines = #tab.lines
        local visibleLines = MonitorModule.innerHeight
        local maxVScroll = math.max(0, totalLines - visibleLines)

        if maxVScroll > 0 then
            local thumbHeight = 7       -- fixed thumb size
            local movable = (barY2 - barY1 + 1) - thumbHeight
            if movable < 0 then
                movable = 0
            end

            local thumbOffset = math.floor((tab.vscroll / maxVScroll) * movable)
            local thumbTop = barY1 + thumbOffset
            local thumbBottom = thumbTop + thumbHeight - 1

            -- Click above thumb
            if x == 1 and y >= barY1 and y < thumbTop then
                MonitorModule.scrollUp()
                return
            end

            -- Click below thumb
            if x == 1 and y > thumbBottom and y <= barY2 then
                MonitorModule.scrollDown()
                return
            end
        end
    end

    ------------------------------------------------------------------
    -- 6. TAB CLICKS
    ------------------------------------------------------------------
    if y == 3 then
        for name, box in pairs(MonitorModule.tabHitboxes) do
            if x >= box.x1 and x <= box.x2 then
                MonitorModule.switchTab(name)
                return
            end
        end
    end
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

----------------------------------------------------------
return MonitorModule
----------------------------------------------------------


