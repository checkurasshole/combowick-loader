if _G.COMBOWICK_ACTIVE then return end

local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

pcall(function() if not game:IsLoaded() then game.Loaded:Wait() end end)
do
    local t = tick()
    while not LocalPlayer and (tick() - t) < 10 do task.wait(); LocalPlayer = Players.LocalPlayer end
end
if not LocalPlayer then return end
if not game.PlaceId or game.PlaceId == 0 then return end

local MODULE_URL = "https://raw.githubusercontent.com/checkurasshole/combowick-loader/main/combowick_module.lua"
local repo       = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"

local M
do
    -- Cache-buster bucketed to 5 min: executors/CDN cache game:HttpGet per-URL. A unique
    -- param every run would re-download the whole module each inject (wasteful). Bucketing
    -- to floor(os.time()/300) keeps it a CDN HIT within any 5-min window while still picking
    -- up a module push within <=5 min automatically.
    local ok, m = pcall(function() return loadstring(game:HttpGet(MODULE_URL .. "?cb=" .. tostring(math.floor(os.time()/300))))() end)
    if ok and type(m) == "table" then M = m end
end
if not M then
    warn("[COMBOWICK] module failed to load from " .. tostring(MODULE_URL))
    return
end

-- [i18n] Translated builds set M.EXPIRED_TITLE / M.EXPIRED_SUB + the M.KEY_* strings
-- below in their language. English keeps these values; the module has matching fallbacks.
M.KEY_PROMPT         = "🔑 Have a key?"
M.KEY_BOX_TITLE      = "Enter your key"
M.KEY_BOX_PLACEHOLDER = "Paste your key here…"
M.KEY_BOX_SUBMIT     = "Unlock"
M.KEY_BOX_CHECKING   = "Checking…"
M.KEY_BOX_INVALID    = "That key is not valid. Check it and try again."
M.KEY_BOX_WRONGGAME  = "This key is for a different game."

-- COVERAGE-FIRST (anti-haunt): decide whether this game is one we actually support BEFORE
-- anything visible or persistent. Kills the #1 complaint — the loader popping up in unrelated
-- games (Blade Ball, Brookhaven, …) a player teleported into and can't dismiss.
local preCheck = M.withRetry(M.checkSession, M.hwid)
preCheck = preCheck or { status = "error", remaining = 0, disabled = false }
local gameUnsupported = preCheck.status == "game_not_allowed"
local gameKeyRequired = preCheck.key_available == true         -- supported paid/key game
local gameConfidentlyUnsupported = gameUnsupported and not gameKeyRequired

-- Persist across teleports ONLY inside games we support (and only when we're sure — not on a
-- network error). In an uncovered game we never re-arm, so the loader stops following players.
if not gameConfidentlyUnsupported and preCheck.status ~= "error" then M.queueOnTeleport() end

-- Uncovered game with no key path: don't show the bar. Close any prior GUI and bail silently
-- so we never ambush players in games we don't support.
if gameConfidentlyUnsupported then
    pcall(function() if getgenv and getgenv().Library then getgenv().Library:Unload() end end)
    return
end

-- Returning key user with a saved key for THIS game: load its scripts (auto-run 1, picker 2+).
if M.tryNewKey() then return end

-- Free session (supported, non-key-locked games only).
if not gameUnsupported then
    if M.tryFreeSession(preCheck) then return end
end

do
    pcall(function() if getgenv and getgenv().Library then getgenv().Library:Unload() end end)
    local targets = {}
    if gethui then local ok, h = pcall(gethui); if ok and h then table.insert(targets, h) end end
    table.insert(targets, game:GetService("CoreGui"))
    for _, target in ipairs(targets) do
        for _, v in ipairs(target:GetChildren()) do
            local n = v.Name
            if n == "Obsidian" or n == "ObsidianLoading" or n == "LinoriaGui" then pcall(v.Destroy, v) end
        end
    end
end

local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
local Options      = Library.Options

local VaultModule       = M.VaultModule
local execPremiumScript = M.execPremiumScript

local function safeSet(lbl, text) pcall(function() lbl:SetText(text) end) end

local Window = Library:CreateWindow({
    Title = "COMBOWICK", Footer = "Free Version", NotifySide = "Right",
    ShowCustomCursor = false, AutoShow = true, Size = UDim2.fromOffset(560, 340),
})
local Tabs = {
    Main    = Window:AddTab("Main",        "user"),
    Key     = Window:AddTab("Premium Key", "key"),
    Suggest = Window:AddTab("Suggestions", "message-square"),
    UI      = Window:AddTab("UI Settings", "settings"),
}

if M.looksTampered() then
    Library:Notify({Title="⚠️ Tampering", Description="Modified functions were detected in your executor.", Time=6})
end

local preRemaining = tonumber(preCheck.remaining) or 0
local preStatus      = preCheck.status
local gameDisabled   = preCheck.disabled == true
local gameUnsupported = preStatus == "game_not_allowed"
local gameKeyRequired = preCheck.key_available == true   -- game IS supported (has a key script), just needs a key

local InfoGroup = Tabs.Main:AddLeftGroupbox("Free Session", "info")
local lSession  = InfoGroup:AddLabel(
    (not gameDisabled and (preStatus == "allowed" or preStatus == "session_active") and preRemaining > 0)
        and string.format("Session time: %s", M.formatTime(preRemaining)) or "Session time: —", true)
local lCooldown = InfoGroup:AddLabel(
    (preStatus == "cooldown" and preRemaining > 0)
        and string.format("Cooldown: %s", M.formatTime(preRemaining)) or "Cooldown: —", true)
if gameKeyRequired then
    InfoGroup:AddLabel("🔑 This game is PREMIUM — enter your key in the 'Premium Key' tab to load it.", true)
elseif gameUnsupported then
    InfoGroup:AddLabel("🚫 This game is not supported yet.", true)
elseif gameDisabled then
    InfoGroup:AddLabel("⛔ The free version is not available in this game.", true)
else
    InfoGroup:AddLabel("The free version is not available in every game.", true)
end
InfoGroup:AddDivider()
InfoGroup:AddLabel("Upgrade to an 11-hour key to remove the cooldown.", true)
InfoGroup:AddButton({
    Text = "Copy Key Link", Tooltip = "combowick-keys.vercel.app/verify/provider-select",
    Func = function()
        pcall(function() setclipboard(M.KEY_URL) end)
        Library:Notify({Title="COMBOWICK", Description="Link copied. Paste it into your browser.", Time=4})
    end,
})
local StatusGroup = Tabs.Main:AddRightGroupbox("Status", "shield")
local statusLabel = StatusGroup:AddLabel("Checking...", true)
local timerLabel  = StatusGroup:AddLabel("", true)
local hintLabel   = StatusGroup:AddLabel("", true)


local savedKey = M.loadSavedKey()
local keyInputValue = savedKey

local KeyGroup = Tabs.Key:AddLeftGroupbox("Enter Your Key")
KeyGroup:AddInput("KeyInput", {
    Default          = savedKey,
    Numeric          = false,
    Finished         = false,
    ClearTextOnFocus = false,
    Text             = "Key 🔑",
    Placeholder      = "Paste your key here...",
    Callback         = function(v) keyInputValue = v end,
})
local function submitKey(key)
    key = M.cleanKey(key)
    if key == "" then
        Library:Notify({Title="⚠️ No Key Entered", Description="Please enter your key.", Time=3})
        return
    end
    Library:Notify({Title="🔑 Checking", Description="Validating your key...", Time=2})

    -- NEW backend: validate the key + get this game's scripts in one call.
    local data, err = M.validateKeyNew(key)
    if type(data) ~= "table" then
        local msg = "That key is not valid. Please check it and try again."
        if err == "wrong_game" then
            msg = "This key is for a different game. Get a key for this game."
        elseif err == "network" or err == "no_request" then
            msg = "Network error. Please try again."
        end
        Library:Notify({Title="❌ Invalid Key", Description=msg, Time=5})
        return
    end

    local scripts = data.scripts or {}
    if #scripts == 0 then
        Library:Notify({Title="🔓 Key Valid", Description="No scripts are set for this game yet.", Time=5})
        return
    end

    -- Valid — remember the key for next time, close this GUI, show the selector.
    M.saveKeyLocal(key)
    Library:Notify({
        Title = "🔓 Key Valid",
        Description = (#scripts == 1) and "Loading script..." or "Choose a script...",
        Time = 3,
    })
    task.wait(0.4)
    pcall(function() Library:Unload() end)
    M.showSelector(scripts)
end

local function readKeyFromBox()
    local raw
    pcall(function()
        local holder = Options and Options.KeyInput and Options.KeyInput.Holder
        local box = holder and holder:FindFirstChildOfClass("TextBox")
        if box then raw = box.Text end
    end)
    local key = M.cleanKey(raw)
    if key == "" then key = M.cleanKey(Options and Options.KeyInput and Options.KeyInput.Value) end
    if key == "" then key = M.cleanKey(keyInputValue) end
    return key
end

KeyGroup:AddButton({
    Text = "✅ Submit Key",
    Func = function() submitKey(readKeyFromBox()) end,
})
KeyGroup:AddButton({
    Text = "🔗 Get Key",
    Func = function()
        pcall(function() setclipboard(M.KEY_URL) end)
        Library:Notify({Title="Copied", Description="Key link copied.", Time=2})
    end,
})

local HWIDGroup = Tabs.Key:AddRightGroupbox("Your HWID")
HWIDGroup:AddLabel(M.hwid, true)
HWIDGroup:AddButton({
    Text = "📋 Copy HWID",
    Func = function()
        pcall(function() setclipboard(M.hwid) end)
        Library:Notify({Title="Copied", Description="HWID copied.", Time=2})
    end,
})
HWIDGroup:AddButton({
    Text = "🔒 Copy Encrypted HWID",
    Func = function()
        pcall(function() setclipboard(M.encryptedHWID) end)
        Library:Notify({Title="Copied", Description="Encrypted HWID copied.", Time=2})
    end,
})

local FEEDBACK_COOLDOWN, lastFeedback = 20, 0
local ERRMAP = {
    empty = "The message is empty.", no_links = "Links are not allowed.",
    too_long = "The message is too long (500 characters maximum).", rate_limited = "You have reached the limit of 3 messages. Please try again later.",
    busy = "The server is busy. Please try again.", banned = "You are not allowed to send feedback.",
    discord_error = "Sending failed. Please try again.", network = "Network error.",
    no_request = "Your executor cannot send requests.", bad_response = "The server returned an unexpected response.",
    unreachable = "Your executor cannot reach the server (TLS error). Please try a different executor.",
}
local FG = Tabs.Suggest:AddLeftGroupbox("Suggestions / Help", "message-square")
FG:AddDropdown("FeedbackType", {Text = "Type", Values = {"Suggestion", "Bug", "Help"}, Default = "Suggestion", Callback = function() end})
FG:AddInput("FeedbackMsg", {Default = "", Numeric = false, Finished = false, ClearTextOnFocus = false, Text = "Message", Placeholder = "Type your message (500 characters maximum, no links)"})
local fbStatus = FG:AddLabel("", true)
FG:AddButton({
    Text = "📨 Send",
    Func = function()
        local now = tick()
        if now - lastFeedback < FEEDBACK_COOLDOWN then
            safeSet(fbStatus, string.format("Please wait %d seconds before sending again.", math.ceil(FEEDBACK_COOLDOWN - (now - lastFeedback))))
            return
        end
        local ftype = tostring((Options.FeedbackType and Options.FeedbackType.Value) or "Suggestion"):lower()
        local msg   = M.trim((Options.FeedbackMsg and Options.FeedbackMsg.Value) or "")
        if msg == "" then safeSet(fbStatus, "The message is empty."); return end
        if #msg > 500 then safeSet(fbStatus, "The message is too long (500 characters maximum)."); return end
        local low = msg:lower()
        if low:find("http", 1, true) or low:find("discord.gg", 1, true) or low:find("www.", 1, true) or low:find(".gg/", 1, true) then
            safeSet(fbStatus, "Links are not allowed."); return
        end
        safeSet(fbStatus, "Sending...")
        task.spawn(function()
            local sok, err = M.sendFeedback(ftype, msg, (preCheck and preCheck.session_token) or "")
            if sok then
                lastFeedback = tick()
                safeSet(fbStatus, "✅ Sent. Thank you!")
                pcall(function() Options.FeedbackMsg:SetValue("") end)
                Library:Notify({Title = "COMBOWICK", Description = "Your feedback was sent. Thank you!", Time = 3})
            else
                safeSet(fbStatus, ERRMAP[err] or ("Failed to send: " .. tostring(err)))
            end
        end)
    end,
})
FG:AddLabel("Maximum 3 messages per hour. No links or mentions.", true)

local HelpGroup = Tabs.Suggest:AddRightGroupbox("Help / FAQ", "life-buoy")
HelpGroup:AddButton({
    Text = "💬 Join Discord",
    Tooltip = M.DISCORD_INVITE,
    Func = function()
        pcall(function() setclipboard(M.DISCORD_INVITE) end)
        Library:Notify({Title = "COMBOWICK", Description = "Discord link copied. Paste it into your browser.", Time = 4})
    end,
})
HelpGroup:AddDivider()
HelpGroup:AddLabel("❓ How do I get premium?\nGet a key at combowick-keys.vercel.app/verify, then paste it into the Premium Key tab. One tap is enough.", true)
HelpGroup:AddLabel("⏳ Why am I on cooldown?\nThe free version has a waiting period between sessions. An 11-hour key removes it completely.", true)
HelpGroup:AddLabel("🎮 It is not working in my game.\nThe free version is not available in every game. Check our Discord for the list of supported games.", true)
HelpGroup:AddLabel("🔑 What is my HWID?\nIt is your hardware ID. Copy it from the Premium Key tab if support asks for it.", true)

task.spawn(function()
    safeSet(statusLabel, "Authenticating...")

    local result = M.withRetry(M.checkSession, M.hwid)

    if result == nil then
        safeSet(statusLabel, "Status: Failed")
        Library:Notify({Title="COMBOWICK", Description="The session check failed.", Time=5})

    elseif result.status == "allowed" or result.status == "session_active" then
        -- SOURCE GATE (keyless-vs-key by loadstring): when the server rule is ON
        -- (result.require_flag), the free version only runs if THIS loadstring set
        -- getgenv().cb_f = true (our funnel/keyless string). A bare loadstring
        -- (ScriptBlox/Rscripts) has no flag -> show "key required", no free.
        local hasFlag = false
        pcall(function() if getgenv and getgenv().cb_f == true then hasFlag = true end end)
        if result.require_flag == true and not hasFlag then
            safeSet(statusLabel, "🔑 Key required")
            safeSet(hintLabel, "This copy needs a key. Free access is only via our official links.")
            Library:Notify({Title="COMBOWICK", Description="A key is required here. Grab one from the Premium Key tab.", Time=6})
            return
        end
        if result.disabled then
            safeSet(statusLabel, "⛔ Game Disabled")
            safeSet(hintLabel, "The free version is not available here. Get a key.")
            Library:Notify({Title="COMBOWICK", Description="The free version is disabled for this game. Please use a key.", Time=6})
            return
        end
        local token = result.session_token
        if type(token) ~= "string" or #token < 20 then
            safeSet(statusLabel, "Status: Failed")
        else
            safeSet(statusLabel, "Status: Authenticated")
            Library:Notify({Title="COMBOWICK", Description="You are authenticated.", Time=3})
            _G.COMBOWICK_FREE   = true
            _G.COMBOWICK_ACTIVE = true
            local remaining = tonumber(result.remaining) or 0
            task.spawn(function()
                while remaining > 0 do
                    local fmt = M.formatTime(remaining)
                    safeSet(timerLabel, string.format("Time remaining: %s", fmt))
                    safeSet(lSession, string.format("Session time: %s", fmt))
                    task.wait(1); remaining = remaining - 1
                end
                safeSet(timerLabel, "The session has expired.")
                safeSet(lSession, "Session time: expired")
                _G.COMBOWICK_ACTIVE = false
                pcall(M.unloadFreeGui)   -- close the free script's GUI (exposed its Library globally)
                if M._keyPromptGui then pcall(function() M._keyPromptGui:Destroy() end); _G.COMBOWICK_KEYPROMPT = false end
                pcall(function() Library:Unload() end)
                M.showExpiredPopup(function() M.reloadExist() end)
            end)
            local scriptUrl = M.getScriptForGame(token)
            if M.loadFreeScript(scriptUrl, token) then task.wait(2); pcall(function() Library:Unload() end); pcall(M.showKeyPrompt) end
        end

    elseif result.status == "cooldown" then
        local remaining = tonumber(result.remaining) or 0
        safeSet(statusLabel, "On Cooldown")
        safeSet(hintLabel, "Get an 11-hour key, or wait for the cooldown to finish.")
        Library:Notify({Title="COMBOWICK", Description="You are on cooldown. Get a key to skip the wait.", Time=6})
        task.spawn(function()
            while remaining > 0 do
                local fmt = M.formatTime(remaining)
                safeSet(timerLabel, string.format("Cooldown: %s", fmt))
                safeSet(lCooldown, string.format("Cooldown: %s", fmt))
                task.wait(1); remaining = remaining - 1
            end
            safeSet(timerLabel, "The cooldown has finished.")
            safeSet(lCooldown, "Cooldown: finished")
            safeSet(hintLabel, "")
            Library:Notify({Title="COMBOWICK", Description="The cooldown has finished. Reloading...", Time=3})
            pcall(function() Library:Unload() end)
            task.wait(0.5)
            M.reloadExist()
        end)

    elseif result.status == "throttled" then
        local remaining = tonumber(result.remaining) or 0
        safeSet(statusLabel, "Too Many Requests")
        safeSet(hintLabel, "Too many requests. Please wait.")
        Library:Notify({Title="COMBOWICK", Description="Too many requests. Please wait a moment.", Time=5})
        task.spawn(function()
            while remaining > 0 do
                safeSet(timerLabel, string.format("Retry in %s", M.formatTime(remaining)))
                task.wait(1); remaining = remaining - 1
            end
            safeSet(timerLabel, "Reloading...")
            safeSet(hintLabel, "")
            pcall(function() Library:Unload() end)
            task.wait(0.5)
            M.reloadExist()
        end)

    elseif result.status == "disabled" then
        safeSet(statusLabel, "Service Paused")
        safeSet(hintLabel, "COMBOWICK is temporarily offline.")
        Library:Notify({Title="COMBOWICK", Description="The service is currently disabled. Please try again later.", Time=6})

    elseif result.status == "banned" then
        safeSet(statusLabel, "Banned")
        Library:Notify({Title="COMBOWICK", Description="You are banned.", Time=5})

    elseif result.status == "game_not_allowed" then
        if result.key_available then
            safeSet(statusLabel, "🔑 Premium Key Required")
            safeSet(hintLabel, "This game IS supported — enter your key in the 'Premium Key' tab to load it.")
            Library:Notify({Title="COMBOWICK", Description="This game is premium. Enter your key in the Premium Key tab to load it.", Time=6})
            pcall(function() Tabs.Key:Show() end)
        else
            safeSet(statusLabel, "🚫 Game Not Supported")
            safeSet(hintLabel, "This game is not supported yet. Premium keys still work if a script is available.")
            Library:Notify({Title="COMBOWICK", Description="This game is not supported yet.", Time=6})
        end

    else
        safeSet(statusLabel, "Error")
        safeSet(hintLabel, "Could not reach the server. Please run the script again.")
        Library:Notify({Title="COMBOWICK", Description=tostring(result.message or "An unknown error occurred."), Time=5})
    end
end)

local MenuGroup = Tabs.UI:AddLeftGroupbox("Menu", "wrench")
MenuGroup:AddToggle("ShowCustomCursor", {Text="Custom Cursor", Default=false, Callback=function(v) Library.ShowCustomCursor = v end})
MenuGroup:AddLabel("Menu keybind"):AddKeyPicker("MenuKeybind", {Default="RightShift", NoUI=true, Text="Menu keybind"})
MenuGroup:AddButton({Text="Unload", Func=function() pcall(function() Library:Unload() end) end})
Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({"MenuKeybind"})
ThemeManager:SetFolder("COMBOWICK")
SaveManager:SetFolder("COMBOWICK/game")
SaveManager:BuildConfigSection(Tabs.UI)
ThemeManager:ApplyToTab(Tabs.UI)
SaveManager:LoadAutoloadConfig()

-- Premium game (has a key script but no free session): open the loader straight on
-- the Premium Key tab so users see they CAN use it with a key, instead of reading
-- "not supported" and leaving.
if gameKeyRequired then pcall(function() Tabs.Key:Show() end) end
