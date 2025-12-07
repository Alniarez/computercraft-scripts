package.path = package.path .. ";./?.lua"

-- Get all requirements
local peripherals = require("peripherals")
local monitor = require("advanced_monitor")

-- Do any initialization
local RUNNING = true
monitor.initialize(peripherals)

-- Splash art example
local art = {
    "______ _____  ________  ___",
    "|  _  \\  _  ||  _  |  \\/  |",
    "| | | | | | || | | | .  . |",
    "| | | | | | || | | | |\\/| |",
    "| |/ /\\ \\_/ /\\ \\_/ / |  | |",
    "|___/  \\___/  \\___/\\_|  |_/"
}

monitor.drawSplash(art, colors.red)

sleep(1)

-- Set a title
monitor.setTitle("Game DOOM")

-- Create the tabs (tabs are mandatory for now, a default "Home" tab is created if you don't make one)
local GAME = "Game"
local MAP = "Map"
local PLAYERS = "Player list"

monitor.addTab(GAME, colors.blue)
monitor.addTab(MAP, colors.orange)
monitor.addTab(PLAYERS, colors.cyan)

--Select a tab
monitor.switchTab(GAME)


-- Write to a tab
monitor.printToTab(GAME, "The story so far")

monitor.printToTab(PLAYERS, "Player      Score      Frags      Deaths")
monitor.printToTab(PLAYERS, "Your mom       77         42           3")
monitor.printToTab(PLAYERS, "Uncle Rico     34         14           9")
monitor.printToTab(PLAYERS, "You             2          0          27")


-- Example menu
monitor.addMenu("Menu", {
    { label = "New game", callback = function()
    end },
    { label = "Exit", callback = function()
        monitor.showDialog(
                "Are you sure?",
                colors.blue,
                {
                    { label = "Yes", callback = function()
                        monitor.showDialog({ "Goodbye!" })
                        sleep(2)
                        monitor.clear()
                        monitor.drawSplash({ "It's now safe to turn off", "     your computer" }, colors.black, colors.orange)
                        RUNNING = false
                    end },

                    { label = "No", callback = function()
                        monitor.closeDialog()
                    end }
                }
        )
    end }
})

monitor.addMenu("Cheats", {
    { label = "Infinite ammo", callback = function()
        monitor.showDialog("You cheater! >;(", colors.red)
    end },
    { label = "God mode", callback = function()
        monitor.showDialog("You cheater! :(", colors.red)
    end },
})

monitor.addMenu("Help", {
    { label = "About", callback = function()
        monitor.showDialog("About this script!")
    end },
    { label = "Contact", callback = function()
    end },
})



-- More print into screen because I want it to look a bit pretty
local map = {
    "###################################",
    "# @       #       M         +     #",
    "# ######  #  #######  ####  ###   #",
    "#      #  #      M #     #     #  #",
    "###### #  ######## #  #### ### #  #",
    "#    # #       +   #     # #   #  #",
    "# ## # ########### ####### # ###  #",
    "# ## #     +     #         #   +  #",
    "# ## ####### ### ########### ######",
    "# ##       #   #       M    #     #",
    "# ######## # # ####### ###### ### #",
    "#        # # #       #        # # #",
    "### ###### # ######## ######## # #E",
    "#   +      #        +          #  #",
    "###################################",
}

for _, row in ipairs(map) do
    monitor.printToTab(MAP, row)
end


-- THREAD 1: handle touch input
local function handleTouches()
    while RUNNING do
        local event, side, x, y = os.pullEvent("monitor_touch")
        monitor.handleTouch(x, y)
    end
end

-- THREAD 2: Example of non interactive logic
local story = {
    "You're a marine, one of Earth's toughest, hardened in combat and trained for",
    "action. Three years ago you assaulted a superior officer for ordering his",
    "soldiers to fire upon civilians. He and his body cast were shipped to Pearl",
    "Harbor, while you were transferred to Mars, home of the Union Aerospace",
    "Corporation.",
    "",
    "The UAC is a multi-planetary conglomerate with radioactive waste facilities",
    "on Mars and its two moons, Phobos and Deimos. With no action for fifty million",
    "miles, your day consisted of suckin' dust and watchin' restricted flicks in",
    "the rec room.",
    "",
    "For the last four years the military, UAC's biggest supplier, has used the",
    "remote facilities on Phobos and Deimos to conduct various secret projects,",
    "including research on inter-dimensional space travel. So far they have been",
    "able to open gateways between Phobos and Deimos, throwing a few gadgets into",
    "one and watching them come out the other. Recently however, the Gateways have",
    "grown dangerously unstable. Military \"volunteers\" entering them have either",
    "disappeared or been stricken with a strange form of insanity-babbling",
    "vulgarities, bludgeoning anything that breathes, and finally suffering an",
    "untimely death of full-body explosion. Matching heads with torsos to send home",
    "to the folks became a full-time job. Latest military reports state that the",
    "research is suffering a small set-back, but everything is under control.",
    "",
    "A few hours ago, Mars received a garbled message from Phobos. \"We require",
    "immediate military support. Something fraggin' evil is coming out of the",
    "Gateways! Computer systems have gone berserk!\" The rest was incoherent. Soon",
    "afterwards, Deimos simply vanished from the sky. Since then, attempts to",
    "establish contact with either moon have been unsuccessful.",
    "",
    "You and your buddies, the only combat troop for fifty million miles were sent",
    "up pronto to Phobos. You were ordered to secure the perimeter of the base",
    "while the rest of the team went inside. For several hours, your radio picked",
    "up the sounds of combat: guns firing, men yelling orders, screams, bones",
    "cracking, then finally, silence. Seems your buddies are dead.",
    "",
    "It's Up To You",
    "Things aren't looking too good. You'll never navigate off the planet on your",
    "own. Plus, all the heavy weapons have been taken by the assault team leaving",
    "you with only a pistol. If only you could get your hands around a plasma rifle",
    "or even a shotgun you could take a few down on your way out. Whatever killed",
    "your buddies deserves a couple of pellets in the forehead. Securing your",
    "helmet, you exit the landing pod. Hopefully you can find more substantial",
    "firepower somewhere within the station.",
    "",
    "As you walk through the main entrance of the base, you hear animal-like",
    "growls echoing throughout the distant corridors. They know you're here.",
    "There's no turning back now.",
}

local function updateGame()
    local storyIndex = 1

    while RUNNING do
        if not (storyIndex > #story) then
            -- Write the current line
            monitor.printToTab(GAME, story[storyIndex])

            -- Advance index
            storyIndex = storyIndex + 1
        end

        sleep(1)
    end
end

parallel.waitForAny(handleTouches, updateGame)