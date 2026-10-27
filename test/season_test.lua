-- COMBO_WICK hub SEASON TEST (not live). Opens a test window with the new features.
_G.__SEASON_SRC = [======[-- ============================================================================
-- Anti-cheat guard — MUST run FIRST. Locks the metatables of the anti-cheat's
-- guarded tables (found by the {gmatch, GetFullName} constant signature) so its
-- __newindex kick can't fire. Wrapped in a function so its guard-clause returns
-- don't exit the module, and scoped by universe id so it ONLY runs in the games
-- that need it (never touching others). Add a game.GameId to enable it there.
-- ============================================================================
local _CW_ANTIKICK_GAMES = { [10563114921] = true }  -- Steal An Egg (universe / game.GameId)
local function _cwAntiKick()
    local SIGNATURE = { "gmatch", "GetFullName" }
    local _filtergc    = filtergc or (getgenv and getgenv().filtergc)
    local _getgc       = getgc or (getgenv and getgenv().getgc)
    local _getupvalues = getupvalues or (debug and debug.getupvalues) or (getgenv and getgenv().getupvalues)
    local _getconsts   = getconstants or (debug and debug.getconstants) or getconstant
    local _setrawmt    = setrawmetatable or (getgenv and getgenv().setrawmetatable)
    local _dbgsetmt    = debug and debug.setmetatable
    local _setmt       = setmetatable

    local function setMeta(tbl, mt)
        if _setrawmt then return (pcall(_setrawmt, tbl, mt)) end
        if _dbgsetmt then return (pcall(_dbgsetmt, tbl, mt)) end
        return (pcall(_setmt, tbl, mt))
    end

    if not _getupvalues then return end
    if not (_setrawmt or _dbgsetmt or _setmt) then return end

    local seen = setmetatable({}, { __mode = "k" })
    local function guardMeta() return { __newindex = function() end } end

    local function findCandidates()
        local cands = {}
        if _filtergc then
            local ok, res = pcall(_filtergc, "function", { Constants = SIGNATURE })
            if ok then
                if type(res) == "function" then cands[#cands + 1] = res
                elseif type(res) == "table" then for _, f in ipairs(res) do cands[#cands + 1] = f end end
            end
        end
        if #cands == 0 and _getgc and _getconsts then
            local ok, gc = pcall(_getgc, true)
            if not ok or type(gc) ~= "table" then ok, gc = pcall(_getgc) end
            if type(gc) == "table" then
                for _, obj in ipairs(gc) do
                    if type(obj) == "function" then
                        local okc, consts = pcall(_getconsts, obj)
                        if okc and type(consts) == "table" then
                            local have = {}
                            for _, c in ipairs(consts) do if type(c) == "string" then have[c] = true end end
                            local all = true
                            for _, need in ipairs(SIGNATURE) do if not have[need] then all = false break end end
                            if all then cands[#cands + 1] = obj end
                        end
                    end
                end
            end
        end
        return cands
    end

    local function apply()
        for _, fn in ipairs(findCandidates()) do
            local ok, ups = pcall(_getupvalues, fn)
            if ok and type(ups) == "table" then
                for _, up in pairs(ups) do
                    if typeof(up) == "table" and not seen[up] then
                        if setMeta(up, guardMeta()) then seen[up] = true end
                    end
                end
            end
        end
    end

    apply()
    local ok, lp = pcall(function() return game:GetService("Players").LocalPlayer end)
    if ok and lp then
        lp.CharacterAdded:Connect(function() task.wait(1.5); apply() end)
    end
end

pcall(function()
    if _CW_ANTIKICK_GAMES[game.GameId] then _cwAntiKick() end
end)

local M = {}

local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
do
    local t = tick()
    while not LocalPlayer and (tick() - t) < 10 do task.wait(); LocalPlayer = Players.LocalPlayer end
end

local _jsonDecode_ref   = HttpService.JSONDecode

-- Some executors (notably Wave) hand back response bodies with JSON structural characters
-- URL-encoded (%7D for }, %7B for {, %22 for ", ...), which makes JSONDecode fail on an
-- otherwise-valid response and surfaces as "invalid key"/"server unreachable". Repair those
-- before decoding. No-op on clean bodies.
local function _fixBody(b)
    if type(b) ~= "string" then return b end
    if b:find("%%7[BbDd]") or b:find("%%5[BbDd]") or b:find("%%22") then
        b = b:gsub("%%7[Bb]", "{"):gsub("%%7[Dd]", "}"):gsub("%%5[Bb]", "["):gsub("%%5[Dd]", "]"):gsub("%%22", '"'):gsub("%%3[Aa]", ":"):gsub("%%2[Cc]", ",")
    end
    return b
end
-- Decode the raw body first; repair with _fixBody only if that fails. Responses that carry
-- whole script bodies (key validate inline, get_free_script) may legitimately contain "%22"
-- etc. inside a script — repairing those up front would corrupt the script or the JSON.
local function _decodeRaw(b)
    local ok, v = pcall(_jsonDecode_ref, HttpService, b)
    if ok and type(v) == "table" then return true, v end
    return pcall(_jsonDecode_ref, HttpService, _fixBody(b))
end
local _jsonEncode_ref   = HttpService.JSONEncode
local rawequal_original = rawequal
-- EXECUTOR COMPAT: executors name the HTTP function differently and return different field names
-- (StatusCode/Body vs status_code/body). Pick whichever exists; normalise every response.
local function _pickRequest()
    return request or (syn and syn.request) or http_request
        or (http and http.request) or (fluxus and fluxus.request)
end
local _request          = _pickRequest()
local function _req(opts)
    local res = _request(opts)
    if type(res) ~= "table" then return res end
    local ok, out = pcall(function()
        return {
            StatusCode = res.StatusCode or res.status_code or res.Status or res.status or res.statusCode,
            Body       = res.Body or res.body,
            Headers    = res.Headers or res.headers,
            Success    = res.Success,
        }
    end)
    return ok and out or res
end
-- Some executors only have toclipboard / setrbxclipboard — give the loader + mains a setclipboard.
pcall(function()
    if type(setclipboard) ~= "function" then
        local cb = toclipboard or setrbxclipboard or (Clipboard and Clipboard.set)
        if type(cb) == "function" and getgenv then getgenv().setclipboard = cb end
    end
end)

-- Offloaded architecture: session-check + game-map run DIRECTLY on Supabase
-- (PostgREST/RPC — NOT edge functions, so no 500k cap and no Vercel invocations).
-- Vercel (APP_BASE) is hit only for the token-protected fallback script.
local SUPABASE_URL      = "https://fdxrmmcppkngeexkwdjd.supabase.co"
local SUPABASE_ANON     = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZkeHJtbWNwcGtuZ2VleGt3ZGpkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgxODQwMDgsImV4cCI6MjEwMzc2MDAwOH0.SS0L_YvK01RGDQETsoHNOVlatJow1cV0co7WalYHx_I"
local CHECK_URL         = SUPABASE_URL .. "/rest/v1/rpc/check_hwid"
local MAP_QUERY_URL     = SUPABASE_URL .. "/rest/v1/allowed_games"
local APP_BASE          = "https://hwid-rouge.vercel.app"
local FREE_SCRIPT_URL   = APP_BASE .. "/api/public/script"
-- Free-session script bodies straight from Supabase (RPC, session-token gated, URL never sent).
-- hwid-rouge (FREE_SCRIPT_URL) is only the fallback if this fails.
local FREE_BODY_RPC     = SUPABASE_URL .. "/rest/v1/rpc/get_free_script"
local CHECK_KEY_URL     = "https://v0-remix-of-roblox-executor-system.vercel.app/api/check-hwid?hwid="
local CHRONICLE_URL     = "https://combo0-chroncile.vercel.app/api/roblox?gameId="
-- Suggestions/feedback: primary = old Lovable edge function; fallback = Vercel proxy.
local FEEDBACK_URL_LOVABLE = "https://zgqjncrelglxcawifdeb.supabase.co/functions/v1/public-feedback"
local FEEDBACK_URL_VERCEL  = "https://v0-secure-discord-proxy.vercel.app/api/v2sender"

M.KEY_URL        = "https://keys.combowick.com/verify/provider-select"
M.EXIST_URL      = "https://raw.githubusercontent.com/checkurasshole/combowick-loader/main/combowick_main.lua"
-- Each translated main sets M.LANG at its very top. Reloads (free session ended) and the
-- teleport re-arm load THAT language's main (GitHub vault copy: no Vercel request), so a player
-- who picked Spanish stays in Spanish. Unknown/missing LANG -> the English EXIST_URL as before.
M.MAIN_IDS = {
    ["en"] = "bd65bef36e64d58178cb4d73036f14ba",
    ["pt"] = "42efc1fdec952615e80608b20370fb21",
    ["ru"] = "e8537e887be05836904df5672a244c49",
    ["ko"] = "8187edf54d928770947bc7b1f8d41f7f",
    ["zh-CN"] = "01e83de5f315e8a7afcc49c56e2564c3",
    ["de"] = "bc9eb04e347a0e56999eb0fc4e91627b",
    ["fr"] = "efaa3c01ed4f5c34461d00a0044f3d1b",
    ["th"] = "e85cd907e49ffe115f74ce54753cdde9",
    ["vi"] = "9ec4d1027951c92271f1e59fec3fecf6",
    ["es"] = "82fe9d000e27141b7b11f676f4f3459a",
    ["id"] = "3a480620b03628d02f12ad37a2c739d6",
    ["fil"] = "763a5160393e681defecff6ec74d5df8",
    ["ar"] = "6237b5236293273f115aeea9c6a105a2",
}
function M.mainUrl()
    local id = M.LANG and M.MAIN_IDS[M.LANG]
    if id then return "https://raw.githubusercontent.com/checkurasshole/Script/main/vault/" .. id .. ".lua" end
    return M.EXIST_URL
end
M.LOADER_VERSION = "modular-1.0"
M.DISCORD_INVITE = "https://discord.gg/9FWBQnVXCy"

-- NEW per-game multi-script backend (executor) + selector GUI.
-- VALIDATE_URL is the ONLY Vercel call in the key path (privileged HWID+game bind,
-- single call on submit — not a poll). It returns the game's scripts in the response.
M.VALIDATE_URL   = "https://v0-remix-of-roblox-executor-system.vercel.app/api/roblox-validate-hwid"
M.SELECTOR_URL   = "https://raw.githubusercontent.com/combowick-hub/combowick-selector/main/selector.lua"

local VALID_STATUSES = {allowed=true,session_active=true,cooldown=true,banned=true,game_not_allowed=true,key_required=true,throttled=true,disabled=true,error=true}

if not bit32 then
    bit32 = {}
    function bit32.bxor(a, b)
        local res, bitval = 0, 1
        while a > 0 or b > 0 do
            if (a % 2 + b % 2) % 2 == 1 then res = res + bitval end
            bitval = bitval * 2
            a = math.floor(a / 2)
            b = math.floor(b / 2)
        end
        return res
    end
end
local MASTER_KEY = "checkdeezfuckingnuts"
local b64chars   = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64Encode(data)
    return ((data:gsub('.', function(x)
        local r, bits = '', x:byte()
        for i = 8, 1, -1 do r = r .. (bits % 2^i - bits % 2^(i-1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c * 2 + (x:sub(i,i) == '1' and 1 or 0) end
        return b64chars:sub(c+1, c+1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end
local function xorEncrypt(text, key)
    local result, keyLen = {}, #key
    for i = 1, #text do
        table.insert(result, string.char(bit32.bxor(string.byte(text, i), string.byte(key, ((i-1) % keyLen) + 1))))
    end
    return table.concat(result)
end
local function encrypt(plain, key) return base64Encode(xorEncrypt(plain, key or MASTER_KEY)) end
local function trim(s) return (tostring(s or ""):gsub("^%s*(.-)%s*$", "%1")) end
local function cleanKey(s)
    s = tostring(s or "")
    s = s:gsub("\226\128\139", ""):gsub("\226\128\140", ""):gsub("\226\128\141", ""):gsub("\239\187\191", ""):gsub("\194\160", "")
    s = s:gsub("%s", "")
    s = s:gsub("%c", "")
    return s
end
M.encrypt  = encrypt
M.trim     = trim
M.cleanKey = cleanKey

local ENFORCE_ANTIHOOK = false

local function isReplaced(fn)
    if type(fn) ~= "function" then return false end
    local isC   = iscclosure
    local dinfo = debug and debug.info
    if not (isC and dinfo) then return false end
    local ok, c = pcall(isC, fn)
    if not ok or c ~= false then return false end
    local sok, src = pcall(dinfo, fn, "s")
    return (sok and type(src) == "string" and src ~= "[C]" and #src > 0) or false
end
local function looksTampered()
    return isReplaced(loadstring) or isReplaced(_request)
end
local function stillTrusted()
    return rawequal_original(HttpService.JSONDecode, _jsonDecode_ref)
       and rawequal_original(HttpService.JSONEncode, _jsonEncode_ref)
       and _request == _pickRequest()
end
local function safeToLoad()
    if not stillTrusted() then return false end
    if ENFORCE_ANTIHOOK and looksTampered() then return false end
    return true
end
M.looksTampered = looksTampered
M.stillTrusted  = stillTrusted
M.safeToLoad    = safeToLoad

-- Vault Core DISABLED. The old Vault (checkurasshole/MainModule) auto-ran the
-- premium/chronicle script (e.g. INK) for whitelisted HWIDs on load — hijacking the
-- new flow in every game. The new system uses validateKeyNew + the selector instead,
-- so we don't load the Vault at all here.
local Core, VaultModule, execPremiumScript = nil, nil, nil
M.Core              = Core
M.VaultModule       = VaultModule
M.execPremiumScript = execPremiumScript

local function localGetHWID()
    local ok, id = pcall(function() return game:GetService("RbxAnalyticsService"):GetClientId() end)
    if ok and type(id) == "string" and id ~= "" then return id end
    return tostring(LocalPlayer and LocalPlayer.UserId or 0)
end
local hwid
if Core and Core.getHWID then
    local ok, id = pcall(Core.getHWID)
    if ok and type(id) == "string" and id ~= "" then hwid = id end
end
hwid = hwid or localGetHWID()
M.hwid          = hwid
M.encryptedHWID = encrypt(hwid, MASTER_KEY)

function M.formatTime(seconds)
    seconds = tonumber(seconds) or 0
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then return string.format("%dh %02dm %02ds", h, m, s) end
    return string.format("%dm %02ds", m, s)
end

local function checkSession(hw)
    if not rawequal_original(HttpService.JSONDecode, _jsonDecode_ref) then return nil end
    if not _request then return nil end
    local t = tick()
    local ok, res = pcall(function()
        return _req({
            Url = CHECK_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"]  = "application/json",
                ["apikey"]        = SUPABASE_ANON,
                ["Authorization"] = "Bearer " .. SUPABASE_ANON,
            },
            Body = _jsonEncode_ref(HttpService, {p_hwid = tostring(hw), p_game_id = tostring(game.PlaceId), p_universe_id = tostring(game.GameId), p_has_flag = (getgenv and getgenv().cb_f == true) or false, p_src = tostring((getgenv and getgenv().cb_src) or ""), p_cb_game = tostring((getgenv and getgenv().cb_game) or ""), p_user_id = tostring(LocalPlayer and LocalPlayer.UserId or "")}),
        })
    end)
    if not ok or not res then return nil end
    if (tick() - t) < 0.005 then return nil end
    if res.StatusCode ~= 200 then return nil end
    local dok, data = pcall(_jsonDecode_ref, HttpService, _fixBody(res.Body))
    if not dok or type(data) ~= "table" then return nil end
    if type(data.status) ~= "string" or not VALID_STATUSES[data.status] then return nil end
    if not stillTrusted() then return nil end
    return data
end
M.checkSession = checkSession

-- The script URL is no longer read client-side (anon can't see script_url). The mains still call
-- getScriptForGame -> loadFreeScript, so this returns a marker that loadFreeScript resolves via
-- loadFreeById (Supabase rpc/get_free_script first, hwid-rouge fallback) — no URL reaches the client.
local function getScriptForGame(token)
    return FREE_SCRIPT_URL
end
M.getScriptForGame = getScriptForGame

local function loadFreeScript(url, token)
    if not safeToLoad() then return false end
    if url == FREE_SCRIPT_URL and M.loadFreeById then return M.loadFreeById(nil, token) end
    local ok, s = pcall(function()
        return _req({Url = url, Method = "GET", Headers = token and {["X-Session-Token"] = token} or {}})
    end)
    if not ok or not s or s.StatusCode ~= 200 then return false end
    local chunk = loadstring(s.Body)
    if not chunk then return false end
    pcall(chunk)
    return true
end
M.loadFreeScript = loadFreeScript

local function checkKey(encHwid)
    if not _request then return nil end
    local ok, res = pcall(function()
        return _req({Url = CHECK_KEY_URL .. encHwid, Method = "GET", Headers = {["Content-Type"] = "application/json"}})
    end)
    if not ok or not res or res.StatusCode ~= 200 then return nil end
    local dok, data = pcall(_jsonDecode_ref, HttpService, _fixBody(res.Body))
    if not dok or type(data) ~= "table" then return nil end
    if not stillTrusted() then return nil end
    return data
end
M.checkKey = checkKey

local function withRetry(fn, arg)
    if not _request then return fn(arg) end
    for attempt = 1, 3 do
        local r = fn(arg)
        if r ~= nil then return r end
        if not stillTrusted() then return nil end
        if attempt < 3 then task.wait(1.5 * attempt) end
    end
    return nil
end
M.withRetry = withRetry

local function getChronicleScript(gameId)
    if not _request then return nil end
    local ok, res = pcall(function()
        return _req({Url = CHRONICLE_URL .. tostring(gameId), Method = "GET", Headers = {["Content-Type"] = "application/json"}})
    end)
    if not ok or not res or res.StatusCode ~= 200 then return nil end
    local dok, data = pcall(_jsonDecode_ref, HttpService, _fixBody(res.Body))
    if not dok or type(data) ~= "table" then return nil end
    local raw = data[tostring(gameId)]
    if type(raw) == "table" then return raw[1]
    elseif type(raw) == "string" and #raw > 0 then return raw end
    return nil
end
M.getChronicleScript = getChronicleScript

local function runUrl(url)
    if not url then return false end
    if not safeToLoad() then return false end
    if _request then
        local ok, res = pcall(function() return _req({Url = url, Method = "GET"}) end)
        if ok and res and res.StatusCode == 200 and res.Body and #res.Body > 0 then
            local chunk = loadstring(res.Body)
            if chunk then pcall(chunk); return true end
        end
    end
    local ok, s = pcall(function() return game:HttpGet(url) end)
    if ok and s and #s > 0 then local chunk = loadstring(s); if chunk then pcall(chunk); return true end end
    return false
end
M.runUrl = runUrl

local function reloadExist()
    local ok, s = pcall(function() return game:HttpGet(M.mainUrl()) end)
    if ok and s and #s > 0 then local c = loadstring(s); if c then pcall(c) end end
end
M.reloadExist = reloadExist

-- Slide-in "Free Session Ended" popup shown when a free session's timer expires.
-- Auto-dismisses after 20s (progress bar), then calls onDone.
function M.showExpiredPopup(onDone)
    local done = false
    local function finish() if done then return end; done = true; if onDone then pcall(onDone) end end
    local ok = pcall(function()
        local parent = game:GetService("CoreGui")
        if gethui then local h = gethui(); if h then parent = h end end

        local ScreenGui = Instance.new("ScreenGui")
        ScreenGui.Name = "CW_Expired"
        ScreenGui.ResetOnSpawn = false
        ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        ScreenGui.Parent = parent

        local Frame = Instance.new("Frame")
        Frame.Size = UDim2.fromOffset(280, 110)
        Frame.Position = UDim2.new(0.5, -140, 0, -120)
        Frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
        Frame.BorderSizePixel = 0
        Frame.Parent = ScreenGui
        Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 14)
        local Stroke = Instance.new("UIStroke", Frame)
        Stroke.Color = Color3.fromRGB(80, 80, 100); Stroke.Thickness = 1

        local Title = Instance.new("TextLabel", Frame)
        Title.Size = UDim2.new(1, -20, 0, 28); Title.Position = UDim2.fromOffset(10, 10)
        Title.BackgroundTransparency = 1; Title.Text = M.EXPIRED_TITLE or "Free Session Ended"
        Title.TextColor3 = Color3.fromRGB(255, 255, 255); Title.TextSize = 14
        Title.Font = Enum.Font.GothamBold; Title.TextXAlignment = Enum.TextXAlignment.Left

        local Sub = Instance.new("TextLabel", Frame)
        Sub.Size = UDim2.new(1, -20, 0, 34); Sub.Position = UDim2.fromOffset(10, 36)
        Sub.BackgroundTransparency = 1
        Sub.Text = M.EXPIRED_SUB or "Tap “Have a key?” to unlock,\nor get one to continue without cooldowns."
        Sub.TextColor3 = Color3.fromRGB(180, 180, 200); Sub.TextSize = 12
        Sub.Font = Enum.Font.Gotham; Sub.TextXAlignment = Enum.TextXAlignment.Left; Sub.TextWrapped = true

        local Bar = Instance.new("Frame", Frame)
        Bar.Size = UDim2.new(1, -20, 0, 3); Bar.Position = UDim2.fromOffset(10, 96)
        Bar.BackgroundColor3 = Color3.fromRGB(100, 100, 200); Bar.BorderSizePixel = 0
        Instance.new("UICorner", Bar).CornerRadius = UDim.new(1, 0)

        Frame:TweenPosition(UDim2.new(0.5, -140, 0, 20), Enum.EasingDirection.Out, Enum.EasingStyle.Quint, 0.4, true)
        local ts = game:GetService("TweenService")
        ts:Create(Bar, TweenInfo.new(20, Enum.EasingStyle.Linear), {Size = UDim2.new(0, 0, 0, 3)}):Play()

        task.delay(20, function()
            pcall(function()
                Frame:TweenPosition(UDim2.new(0.5, -140, 0, -120), Enum.EasingDirection.In, Enum.EasingStyle.Quint, 0.4, true)
            end)
            task.wait(0.5)
            pcall(function() ScreenGui:Destroy() end)
            finish()
        end)
    end)
    if not ok then finish() end
end

local function postFeedback(url, ftype, msg, sessionToken)
    if not _request then return false, "no_request" end
    local ok, res = pcall(function()
        return _req({
            Url = url, Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = _jsonEncode_ref(HttpService, {
                type = ftype, message = msg, hwid = M.encryptedHWID,
                placeId = tostring(game.PlaceId), username = LocalPlayer and LocalPlayer.Name or "?",
                version = M.LOADER_VERSION, sessionToken = sessionToken or "",
            }),
        })
    end)
    if not ok or not res then return false, "network" end
    if type(res) == "string" then return false, "unreachable" end   -- executor returned a TLS/connect error string
    if type(res) ~= "table" then return false, "network" end
    local code = res.StatusCode or res.status_code or res.Status or res.status
    if type(code) == "number" and code ~= 200 and code ~= 201 and code ~= 204 then
        return false, "http_" .. tostring(code)
    end
    local body = res.Body or res.body
    if type(body) ~= "string" or body == "" then return false, "bad_response" end
    local dok, data = pcall(_jsonDecode_ref, HttpService, _fixBody(body))
    if not dok or type(data) ~= "table" then return false, "bad_response" end
    if data.success == true then return true end
    return false, tostring(data.error or "unknown")
end

-- Content rejections that would repeat identically on the fallback — don't retry those.
local FEEDBACK_FINAL_ERRORS = {empty=true, no_links=true, too_long=true, rate_limited=true, banned=true}

function M.sendFeedback(ftype, msg, sessionToken)
    -- Primary: old Lovable edge function. Fallback: Vercel proxy (only on transport failure).
    local ok, err = postFeedback(FEEDBACK_URL_LOVABLE, ftype, msg, sessionToken)
    if ok then return true end
    if FEEDBACK_FINAL_ERRORS[err] then return false, err end
    local ok2, err2 = postFeedback(FEEDBACK_URL_VERCEL, ftype, msg, sessionToken)
    if ok2 then return true end
    return false, err2 or err
end

function M.queueOnTeleport()
    if _G.COMBOWICK_QUEUED then return end
    local qot = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
    if type(qot) ~= "function" then return end
    -- SOURCE-FLAG PROPAGATION: the re-armed copy runs in a fresh env on the next server
    -- (getgenv doesn't survive the teleport here). If THIS run was a cb_f/free run, bake the
    -- flag back into the queued payload — otherwise the server rule (require_free_flag) sees
    -- no flag and bumps the teleported free user to the key path. Only propagate when the
    -- flag was actually set this run, so a bare/key run never gets upgraded to free.
    local flagPrefix = ""
    local tieGame = nil
    pcall(function()
        if getgenv and getgenv().cb_f == true then
            flagPrefix = "getgenv().cb_f = true; "
            local cbg = getgenv().cb_game
            if cbg ~= nil and tostring(cbg) ~= "" then
                flagPrefix = flagPrefix .. string.format("getgenv().cb_game = %q; ", tostring(cbg))
                tieGame = tostring(cbg)
            end
        end
    end)
    local body = string.format('%spcall(function() loadstring(game:HttpGet(%q))() end)', flagPrefix, M.mainUrl())
    -- GAME-TIE: a keyless (cb_game) run only re-arms for the SAME game. Teleport into any OTHER
    -- game => the queued copy does nothing at all (no session check, no GUI, no cooldown) — the
    -- user has to run our script there to unlock it. Same game (server hop) => it resumes free.
    -- A bare/key run has no cb_game, so it re-arms everywhere as before.
    local payload
    if tieGame then
        payload = string.format('task.wait(1); if tostring(game.GameId) == %q then %s end', tieGame, body)
    else
        payload = string.format('task.wait(1); %s', body)
    end
    if pcall(qot, payload) then _G.COMBOWICK_QUEUED = true end
end

function M.tryVaultWhitelist()
    if not (VaultModule and VaultModule.isClientIdWhitelisted) then return false end
    local wok, whitelisted = pcall(VaultModule.isClientIdWhitelisted, hwid, M.encryptedHWID)
    if not (wok and whitelisted) then return false end
    local vok, versionValid, _vmsg, fetchedToken = pcall(VaultModule.checkVersionAndToken)
    if not (vok and versionValid) then return false end
    _G.VaultInitialized  = true
    _G.VaultVersionToken = fetchedToken
    if VaultModule.startSessionMonitoring then pcall(VaultModule.startSessionMonitoring, hwid) end
    if getgenv then pcall(function() getgenv().VaultReady = true end) end
    if safeToLoad() and execPremiumScript then pcall(execPremiumScript) end
    return true
end

function M.tryHwidKey()
    -- single attempt (no withRetry): CHECK_KEY_URL failures are permanent, so retrying
    -- just stalls free-user startup ~4.5s. One shot: works if alive, fails fast if not.
    local kr = checkKey(M.encryptedHWID)
    if kr and kr.success == true then
        local scriptUrl = getChronicleScript(game.PlaceId)
        if scriptUrl and runUrl(scriptUrl) then return true end
    end
    return false
end

-- Central teardown for a free script's GUI when its session ends. A free script only
-- has to expose its Obsidian Library via a global — getgenv().Library (preferred) or
-- _G.__stealLib / _G.Library / _G.COMBOWICK_LIB — and the loader closes it here. So a
-- free script no longer needs its own session-timer + Library:Unload logic.
function M.unloadFreeGui()
    pcall(function() if _G.__CW_CLEAN then _G.__CW_CLEAN() end end)
    local function tryUnload(L)
        if type(L) == "table" and type(L.Unload) == "function" then pcall(function() L:Unload() end) end
    end
    pcall(function() if getgenv then tryUnload(getgenv().Library) end end)
    for _, name in ipairs({ "__stealLib", "Library", "COMBOWICK_LIB", "__combowickLib" }) do
        pcall(function() tryUnload(_G[name]) end)
    end
end

-- ===== Info tab: user card + live session info + socials, added to the free-session GUI.
-- Lives here (the key-system module) so ONE update hits every free session. Links are
-- centralized in M.DISCORD_INVITE / M.WEBSITE_URL — change them here, every game updates.
M.DISCORD_INVITE = "https://discord.gg/9FWBQnVXCy"
M.WEBSITE_URL    = "https://keys.combowick.com"
function M.buildInfoTab(Library)
    if type(Library) ~= "table" then return end
    local Window = Library.Window
    if not Window or type(Window.AddTab) ~= "function" then return end
    if type(Library.Tabs) == "table" and Library.Tabs["Info"] then return end -- already has one
    -- one Info tab + one live loop per session (kills stale loops on re-exec/teleport)
    M._infoGen = (M._infoGen or 0) + 1
    local myGen = M._infoGen
    local ok, InfoTab = pcall(function() return Window:AddTab("Info", "user") end)
    if not ok or type(InfoTab) ~= "table" then return end

    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer
    local function notify(m) pcall(function() Library:Notify({ Title = "COMBO_WICK", Description = tostring(m), Time = 4 }) end) end

    local UserBox = InfoTab:AddLeftGroupbox("User")
    pcall(function() UserBox:AddImage("cw_avatar", { Image = "rbxthumb://type=AvatarHeadShot&id=" .. lp.UserId .. "&w=150&h=150", Height = 96 }) end)
    pcall(function() UserBox:AddLabel("User: " .. lp.DisplayName .. " (@" .. lp.Name .. ")") end)
    pcall(function() UserBox:AddLabel("UserId: " .. tostring(lp.UserId)) end)
    local execName = "Unknown"
    pcall(function() if identifyexecutor then local n, v = identifyexecutor(); execName = tostring(n) .. (v and (" " .. tostring(v)) or "") end end)
    pcall(function() UserBox:AddLabel("Executor: " .. execName) end)
    local sessLbl; pcall(function() sessLbl = UserBox:AddLabel("Session: 0s") end)

    local gameLbl, playerLbl, pingLbl   -- (Session box removed; the live loop below skips nil labels)

    local LinkBox = InfoTab:AddLeftGroupbox("Links")
    pcall(function() LinkBox:AddButton({ Text = "Copy Discord", Func = function() pcall(function() setclipboard(M.DISCORD_INVITE) end); notify("Discord copied!") end }) end)
    if M.addCustomBox then pcall(M.addCustomBox, InfoTab, Library) end
    pcall(function() LinkBox:AddButton({ Text = "Copy Website", Func = function() pcall(function() setclipboard(M.withCreator and M.withCreator(M.WEBSITE_URL) or M.WEBSITE_URL) end); notify("Website copied!") end }) end)

    -- game name (async, best-effort)
    task.spawn(function()
        local ok2, info = pcall(function() return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId) end)
        if gameLbl then pcall(function() gameLbl:SetText("Game: " .. ((ok2 and info and info.Name) or "Unknown")) end) end
    end)

    -- live updates: polls every 2s, NO event connections. Self-kills on session end,
    -- GUI unload (SetText errors), or a newer session (generation guard) — no leak/stack.
    task.spawn(function()
        local Stats = game:GetService("Stats")
        local start = os.clock()
        while M._infoGen == myGen and _G.COMBOWICK_ACTIVE ~= false do
            local alive = pcall(function()
                local secs = math.floor(os.clock() - start)
                local mm, ss = math.floor(secs / 60), secs % 60
                if sessLbl   then sessLbl:SetText("Session: " .. (mm > 0 and (mm .. "m " .. ss .. "s") or (ss .. "s"))) end
                if playerLbl then playerLbl:SetText("Players: " .. #Players:GetPlayers() .. "/" .. tostring(Players.MaxPlayers)) end
                if pingLbl then
                    local p = "-"
                    pcall(function() p = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
                    pingLbl:SetText("Ping: " .. tostring(p) .. " ms")
                end
            end)
            if not alive then break end
            task.wait(2)
        end
    end)
end

-- Fetch this game's free-session script list (metadata only — names/timers/ids; the
-- protected body NEVER comes through here). Used to build the free-session picker.
local function listFreeScripts()
    if not _request then return {} end
    local ok, res = pcall(function()
        return _req({
            Url = SUPABASE_URL .. "/rest/v1/rpc/list_free_scripts",
            Method = "POST",
            Headers = {
                ["Content-Type"]  = "application/json",
                ["apikey"]        = SUPABASE_ANON,
                ["Authorization"] = "Bearer " .. SUPABASE_ANON,
            },
            Body = _jsonEncode_ref(HttpService, { p_game_id = tostring(game.PlaceId), p_universe_id = tostring(game.GameId) }),
        })
    end)
    if not ok or not res or res.StatusCode ~= 200 then return {} end
    local dok, data = pcall(_jsonDecode_ref, HttpService, _fixBody(res.Body))
    if not dok or type(data) ~= "table" then return {} end
    return data
end
M.listFreeScripts = listFreeScripts

-- Load one free-session script by id through the token-gated endpoint. The server
-- returns the body (a protected vault script served inline/verbatim, or a URL script
-- fetched + obfuscated) — only for a live session, never as a public URL.
local function freeBodyFromSupabase(id, token)
    if not _request or type(token) ~= "string" then return nil end
    local ok, res = pcall(function()
        return _req({
            Url = FREE_BODY_RPC,
            Method = "POST",
            Headers = {
                ["Content-Type"]  = "application/json",
                ["apikey"]        = SUPABASE_ANON,
                ["Authorization"] = "Bearer " .. SUPABASE_ANON,
            },
            Body = _jsonEncode_ref(HttpService, { p_token = token, p_id = id and tostring(id) or nil }),
        })
    end)
    if not ok or not res or res.StatusCode ~= 200 then return nil, "network" end
    local dok, data = _decodeRaw(res.Body)
    if not dok or type(data) ~= "table" then return nil, "network" end
    if data.ok == true and type(data.body) == "string" and #data.body > 0 then return data.body end
    return nil, tostring(data.reason or "unknown")
end

-- Reasons where hwid-rouge could still succeed. Anything else (invalid_token, game_not_allowed,
-- no_script, not_found) would only get hwid-rouge's generic placeholder, so we stop instead.
local FREE_FALLBACK_OK = { network = true, use_fallback = true, source_failed = true }

local function loadFreeById(id, token)
    if not safeToLoad() then return false end
    local body, why = freeBodyFromSupabase(id, token)
    if body then
        local chunk = loadstring(body)
        if chunk then pcall(chunk); return true end
        return false   -- the script itself doesn't compile; hwid-rouge would serve the same body
    end
    if not FREE_FALLBACK_OK[why] then return false end
    -- fallback: hwid-rouge token endpoint (Vercel) — only when Supabase itself failed
    local url = FREE_SCRIPT_URL .. (id and ("?s=" .. HttpService:UrlEncode(tostring(id))) or "")
    local ok, s = pcall(function()
        return _req({ Url = url, Method = "GET", Headers = token and { ["X-Session-Token"] = token } or {} })
    end)
    if not ok or not s or s.StatusCode ~= 200 or type(s.Body) ~= "string" or #s.Body == 0 then return false end
    local chunk = loadstring(s.Body)
    if not chunk then return false end
    pcall(chunk)
    return true
end
M.loadFreeById = loadFreeById

-- Shared free-session lifecycle: mark active, show the key upsell, count down THIS
-- script's timer, then unload its GUI + show the expired popup.
local function beginFreeSession(timerSeconds)
    _G.COMBOWICK_FREE   = true
    _G.COMBOWICK_ACTIVE = true
    pcall(M.showKeyPrompt)   -- give key buyers a way out without waiting the timer
    -- Add our Info + Games tabs to the game script's window. Keep watching for 3 min and decorate
    -- EVERY new window (some scripts build theirs twice). Shared across loader runs: only the newest
    -- watcher stays alive, and a window is decorated at most once (keyed by the window itself).
    _G.__CW_WGEN = (_G.__CW_WGEN or 0) + 1
    local myGen = _G.__CW_WGEN
    _G.__CW_DONE = _G.__CW_DONE or setmetatable({}, { __mode = "k" })
    task.spawn(function()
        for _ = 1, 720 do
            if _G.__CW_WGEN ~= myGen then return end
            local L = getgenv and getgenv().Library
            local W = type(L) == "table" and L.Window
            if W and not _G.__CW_DONE[W] then
                _G.__CW_DONE[W] = true
                pcall(M.buildInfoTab, L)
                task.delay(1, function() pcall(function() if M.decorateScriptWindow then M.decorateScriptWindow(L) elseif M.addScriptGamesBox then M.addScriptGamesBox(L) end end) end)
            end
            task.wait(0.25)
        end
    end)
    local remaining = math.max(0, math.floor(tonumber(timerSeconds) or 0))
    task.spawn(function()
        while remaining > 0 and _G.COMBOWICK_ACTIVE do
            _G.__CW_FX_SESSION_LEFT = remaining
            if M.onSessionTick then pcall(M.onSessionTick, remaining) end
            task.wait(1); remaining = remaining - 1
        end
        _G.__CW_FX_SESSION_LEFT = 0
        _G.COMBOWICK_ACTIVE = false
        pcall(M.unloadFreeGui)   -- close the free script's GUI (it exposed its Library globally)
        if M._keyPromptGui then pcall(function() M._keyPromptGui:Destroy() end); _G.COMBOWICK_KEYPROMPT = false end
        M.showExpiredPopup(function() reloadExist() end)
    end)
end
M.beginFreeSession = beginFreeSession

function M.tryFreeSession(preCheck)
    if type(preCheck) ~= "table" then return false end
    if not ((preCheck.status == "session_active" or preCheck.status == "allowed") and not preCheck.disabled) then return false end
    local token = preCheck.session_token
    if type(token) ~= "string" or #token < 20 then return false end

    -- SOURCE GATING (keyless-vs-key by loadstring): when the server rule is ON
    -- (preCheck.require_flag), the free session only runs if THIS loadstring set
    -- getgenv().cb_f = true — that's our funnel/keyless string. A bare loadstring
    -- (e.g. pasted on ScriptBlox/Rscripts) has no flag, so it falls through to the
    -- key path. Rule OFF (or missing) => free session behaves as before, everywhere.
    if preCheck.require_flag == true then
        local hasFlag = false
        pcall(function() if getgenv and getgenv().cb_f == true then hasFlag = true end end)
        if not hasFlag then return false end
    end
    -- GAME-TIE enforcement lives SERVER-SIDE in check_hwid (soft/required, SQL-controlled): the
    -- loader sends getgenv().cb_game as p_cb_game and honors the returned status. A mismatched or
    -- (once required) missing cb_game comes back as key_required, handled below — so no separate
    -- client gate is needed and the soft->required flip is a one-line server change.
    local serverRemaining = tonumber(preCheck.remaining) or 0
    if serverRemaining <= 0 then serverRemaining = 600 end

    -- Per-script window = min(server session remaining, this script's own timer).
    -- Blank/absent per-script timer => the whole server session.
    local function timerFor(s)
        local t = tonumber(s and s.session_seconds)
        if t and t > 0 then return math.min(serverRemaining, t) end
        return serverRemaining
    end

    local scripts = listFreeScripts()

    -- 2+ free scripts => show the picker. On pick, load THAT script via the token
    -- endpoint and run its own countdown (both scripts share the one session).
    if type(scripts) == "table" and #scripts >= 2 then
        local ok = M.showSelector(scripts, {
            onSelect = function(s)
                if loadFreeById(s.id, token) then beginFreeSession(timerFor(s)) end
            end,
        })
        if ok then
            _G.COMBOWICK_FREE = true   -- picker shown; lifecycle starts on pick
            return true
        end
        -- picker failed to load -> fall through to loading the first one directly
    end

    -- Exactly one free script (or the picker couldn't load): run the first directly.
    if type(scripts) == "table" and #scripts >= 1 then
        local s = scripts[1]
        if loadFreeById(s.id, token) then beginFreeSession(timerFor(s)); return true end
    end

    -- Games with no fs_scripts yet: the server picks the row's script_url itself (no URL to the client).
    if not loadFreeById(nil, token) then return false end
    beginFreeSession(serverRemaining)
    return true
end

-- ============================================================================
-- NEW KEY PATH — validate against the executor backend and load the game's scripts
-- ============================================================================

-- Validate a key + get the game's enabled scripts. Returns the parsed table on
-- success, or (nil, errCode[, data]) on failure. errCode "wrong_game" = key is
-- bound to a different game.
function M.validateKeyNew(key)
    key = cleanKey(key)
    if key == "" then return nil, "empty" end
    if not _request then return nil, "no_request" end
    local url = M.VALIDATE_URL
        .. "?key="      .. HttpService:UrlEncode(key)
        .. "&hwid="     .. HttpService:UrlEncode(tostring(M.hwid))
        .. "&place_id=" .. tostring(game.PlaceId)
        .. "&user_id="  .. HttpService:UrlEncode(tostring(LocalPlayer and LocalPlayer.UserId or 0))
        .. "&src="      .. HttpService:UrlEncode(tostring((getgenv and getgenv().cb_src) or ""))
        .. "&inline=1"  -- server returns script BODIES (no repo URLs) so an HTTP spy can't lift a keyless link
    local ok, res = pcall(function()
        return _req({ Url = url, Method = "GET", Headers = { ["Content-Type"] = "application/json" } })
    end)
    if not ok or type(res) ~= "table" then return nil, "network" end
    local body = res.Body or res.body
    if type(body) ~= "string" or body == "" then return nil, "bad_response" end
    local dok, data = _decodeRaw(body)
    if not dok or type(data) ~= "table" then return nil, "bad_response" end
    if data.success ~= true then
        return nil, tostring(data.code or data.message or "invalid"), data
    end
    return data
end

-- Load the selector module and show the picker (auto-runs when only one script).
-- opts.onSelect(script) — when given, the picker calls it instead of running a URL
-- itself (used by the free path to load the pick through the token-gated endpoint).
function M.showSelector(scripts, opts)
    if type(scripts) ~= "table" or #scripts == 0 then return false end
    if not safeToLoad() then return false end
    local ok, Sel = pcall(function() return loadstring(game:HttpGet(M.SELECTOR_URL))() end)
    if ok and type(Sel) == "table" and type(Sel.show) == "function" then
        pcall(Sel.show, scripts, opts)
        pcall(function() if M.watchScriptGamesBox then M.watchScriptGamesBox() end end)
        return true
    end
    return false
end

-- Local key persistence so a returning user auto-loads without re-entering.
local KEY_FILE = "combowick_key.txt"
function M.loadSavedKey()
    local ok, k = pcall(function()
        if not readfile then return nil end
        if isfile then
            if isfile(KEY_FILE) then return readfile(KEY_FILE) end
            return nil
        end
        local okR, content = pcall(readfile, KEY_FILE) -- executors without isfile
        if okR then return content end
        return nil
    end)
    if ok and type(k) == "string" then return cleanKey(k) end
    return ""
end
function M.saveKeyLocal(key)
    pcall(function() if writefile then writefile(KEY_FILE, tostring(key)) end end)
end
function M.clearSavedKey()
    pcall(function() if delfile then delfile(KEY_FILE) end end)
end

-- Startup auto-load: if a saved key still validates for THIS game, show the selector.
-- Returns true (and loads) when a valid key + scripts exist; false otherwise.
function M.tryNewKey()
    local key = M.loadSavedKey()
    if key == "" then return false end
    local data = M.validateKeyNew(key)
    if type(data) ~= "table" then return false end
    local scripts = data.scripts or {}
    if #scripts == 0 then return false end
    return M.showSelector(scripts)
end

-- Floating "Have a key?" prompt shown DURING a free session so paying customers aren't
-- forced to wait out the free timer to reach key entry. Right-edge, vertically centered,
-- draggable, emerald accent (matches the selector). Labels come from the translated main
-- (M.KEY_* fields) with English fallbacks. Tap -> a small key box -> validate -> selector.
function M.showKeyPrompt()
    if _G.COMBOWICK_KEYPROMPT then return end
    _G.COMBOWICK_KEYPROMPT = true

    local UIS    = game:GetService("UserInputService")
    local ACCENT = Color3.fromRGB(52, 211, 153)
    local touch  = UIS.TouchEnabled and not UIS.KeyboardEnabled

    local ok = pcall(function()
        local parent = game:GetService("CoreGui")
        if gethui then local h = gethui(); if h then parent = h end end

        local gui = Instance.new("ScreenGui")
        gui.Name = "CW_KeyPrompt"
        gui.ResetOnSpawn = false
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.DisplayOrder = 9999
        gui.IgnoreGuiInset = true
        gui.Parent = parent
        M._keyPromptGui = gui

        local scale = Instance.new("UIScale", gui)
        scale.Scale = touch and 1.25 or 1

        local pill = Instance.new("TextButton")
        pill.Name = "Pill"
        pill.AnchorPoint = Vector2.new(1, 0.5)
        pill.Position = UDim2.new(1, 80, 0.5, 0)
        pill.Size = UDim2.fromOffset(150, 40)
        pill.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
        pill.BackgroundTransparency = 0.08
        pill.AutoButtonColor = false
        pill.Text = ""
        pill.Parent = gui
        Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 12)
        local stroke = Instance.new("UIStroke", pill)
        stroke.Color = Color3.fromRGB(255, 255, 255); stroke.Thickness = 2; stroke.Transparency = 0
        -- Moving multi-color border (rotating gradient) like the language selector.
        local sgrad = Instance.new("UIGradient", stroke)
        sgrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(52, 211, 153)),
            ColorSequenceKeypoint.new(0.35, Color3.fromRGB(59, 130, 246)),
            ColorSequenceKeypoint.new(0.70, Color3.fromRGB(168, 85, 247)),
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(52, 211, 153)),
        })
        task.spawn(function()
            while gui and gui.Parent do
                sgrad.Rotation = (sgrad.Rotation + 4) % 360
                task.wait(0.03)
            end
        end)

        local label = Instance.new("TextLabel", pill)
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, -12, 1, 0)
        label.Position = UDim2.fromOffset(6, 0)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 14
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.Text = M.KEY_PROMPT or "🔑 Have a key?"

        task.delay(2, function()
            pcall(function()
                pill:TweenPosition(UDim2.new(1, -12, 0.5, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quint, 0.5, true)
            end)
        end)

        -- Drag support (distinguish a real drag from a tap so the box only opens on a tap).
        local dragging, dragStart, startPos, moved = false, nil, nil, false
        pill.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true; moved = false; dragStart = input.Position; startPos = pill.Position
            end
        end)
        -- These two live on the GLOBAL UserInputService, so they DON'T die when the GUI
        -- is destroyed (unlike pill.InputBegan above). Capture them and disconnect on
        -- Destroying — otherwise every re-exec/teleport stacks duplicate handlers (leak).
        local connChanged = UIS.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                if delta.Magnitude > 6 then moved = true end
                pill.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
        local connEnded = UIS.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)
        gui.Destroying:Connect(function()
            pcall(function() connChanged:Disconnect() end)
            pcall(function() connEnded:Disconnect() end)
        end)

        local box
        local function openBox()
            if box then box.Visible = true; return end
            box = Instance.new("Frame")
            box.AnchorPoint = Vector2.new(0.5, 0.5)
            box.Position = UDim2.new(0.5, 0, 0.5, 0)
            box.Size = UDim2.fromOffset(320, 184)
            box.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
            box.Parent = gui
            Instance.new("UICorner", box).CornerRadius = UDim.new(0, 14)
            local bs = Instance.new("UIStroke", box); bs.Color = ACCENT; bs.Thickness = 1.5; bs.Transparency = 0.2

            local title = Instance.new("TextLabel", box)
            title.BackgroundTransparency = 1
            title.Position = UDim2.fromOffset(16, 14); title.Size = UDim2.new(1, -50, 0, 24)
            title.Font = Enum.Font.GothamBold; title.TextSize = 16; title.TextXAlignment = Enum.TextXAlignment.Left
            title.TextColor3 = Color3.fromRGB(255, 255, 255)
            title.Text = M.KEY_BOX_TITLE or "Enter your key"

            local close = Instance.new("TextButton", box)
            close.Size = UDim2.fromOffset(28, 28); close.AnchorPoint = Vector2.new(1, 0); close.Position = UDim2.new(1, -10, 0, 10)
            close.BackgroundTransparency = 1; close.Text = "✕"; close.Font = Enum.Font.GothamBold; close.TextSize = 16
            close.TextColor3 = Color3.fromRGB(160, 160, 170)
            close.MouseButton1Click:Connect(function() box.Visible = false end)

            local inputFrame = Instance.new("Frame", box)
            inputFrame.Position = UDim2.fromOffset(16, 54); inputFrame.Size = UDim2.new(1, -32, 0, 42)
            inputFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
            Instance.new("UICorner", inputFrame).CornerRadius = UDim.new(0, 10)
            local ifs = Instance.new("UIStroke", inputFrame); ifs.Color = Color3.fromRGB(50, 50, 60); ifs.Thickness = 1

            local tb = Instance.new("TextBox", inputFrame)
            tb.BackgroundTransparency = 1; tb.Size = UDim2.new(1, -20, 1, 0); tb.Position = UDim2.fromOffset(10, 0)
            tb.Font = Enum.Font.Gotham; tb.TextSize = 14; tb.TextColor3 = Color3.fromRGB(255, 255, 255)
            tb.PlaceholderText = M.KEY_BOX_PLACEHOLDER or "Paste your key here…"
            tb.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
            tb.ClearTextOnFocus = false; tb.TextXAlignment = Enum.TextXAlignment.Left; tb.Text = ""

            local status = Instance.new("TextLabel", box)
            status.BackgroundTransparency = 1; status.Position = UDim2.fromOffset(16, 102); status.Size = UDim2.new(1, -32, 0, 20)
            status.Font = Enum.Font.Gotham; status.TextSize = 12; status.TextXAlignment = Enum.TextXAlignment.Left
            status.TextColor3 = Color3.fromRGB(255, 120, 120); status.Text = ""

            local submit = Instance.new("TextButton", box)
            submit.AnchorPoint = Vector2.new(0.5, 1); submit.Position = UDim2.new(0.5, 0, 1, -14); submit.Size = UDim2.new(1, -32, 0, 40)
            submit.BackgroundColor3 = ACCENT; submit.Text = M.KEY_BOX_SUBMIT or "Unlock"
            submit.Font = Enum.Font.GothamBold; submit.TextSize = 15; submit.TextColor3 = Color3.fromRGB(10, 20, 16)
            Instance.new("UICorner", submit).CornerRadius = UDim.new(0, 10)

            submit.MouseButton1Click:Connect(function()
                local key = cleanKey(tb.Text)
                if key == "" then return end
                status.TextColor3 = Color3.fromRGB(180, 180, 190)
                status.Text = M.KEY_BOX_CHECKING or "Checking…"
                task.spawn(function()
                    -- Retry on transient NETWORK errors only (Vercel cold-starts can make the
                    -- first validate call time out → a scary "server unreachable"). Up to 3 tries
                    -- with backoff; stop immediately on any definitive answer (valid / wrong game /
                    -- device / expired / invalid) so we never mask a real result.
                    local data, err
                    for attempt = 1, 3 do
                        data, err = M.validateKeyNew(key)
                        if type(data) == "table" then break end
                        local ne = type(err) == "string" and err:lower() or ""
                        if not (ne:find("network") or ne:find("request") or ne:find("response") or ne:find("unreachable")) then break end
                        if attempt < 3 then
                            pcall(function() status.Text = (M.KEY_BOX_RETRYING or "Reaching the server…") end)
                            task.wait(1.2 * attempt)
                        end
                    end
                    if type(data) == "table" and type(data.scripts) == "table" and #data.scripts > 0 then
                        M.saveKeyLocal(key)
                        _G.COMBOWICK_KEYPROMPT = false
                        pcall(function() gui:Destroy() end)
                        M.showSelector(data.scripts)
                    elseif type(data) == "table" then
                        -- VALID key, but no script is configured for THIS game (common with all-access
                        -- keys). Amber, not red — the key is fine; the game just isn't supported yet.
                        -- Save it so it auto-loads once they're in a supported game.
                        pcall(function() M.saveKeyLocal(key) end)
                        status.TextColor3 = Color3.fromRGB(255, 196, 120)
                        status.Text = M.KEY_BOX_NOSCRIPT or "Key valid — no script for this game yet. Try a supported game."
                    else
                        status.TextColor3 = Color3.fromRGB(255, 120, 120)
                        -- Distinguish the FOUR failure reasons so a valid-but-rejected key (or a network
                        -- hiccup) doesn't read as a bad key — the #1 support-ticket confusion.
                        local e = type(err) == "string" and err:lower() or ""
                        if err == "wrong_game" then status.Text = M.KEY_BOX_WRONGGAME or "This key is for a different game."
                        elseif e:find("device") then status.Text = M.KEY_BOX_WRONGDEVICE or "This key is locked to another device."
                        elseif e:find("expire") then status.Text = M.KEY_BOX_EXPIRED or "This key has expired — grab a new one."
                        elseif e:find("network") or e:find("request") or e:find("response") or e:find("unreachable") or e == "empty" then
                            status.TextColor3 = Color3.fromRGB(255, 196, 120)
                            status.Text = M.KEY_BOX_NETWORK or "Couldn't verify your key — check your connection and try again."
                        else status.Text = M.KEY_BOX_INVALID or "That key is not valid. Check it and try again." end
                    end
                end)
            end)
        end

        pill.MouseButton1Click:Connect(function()
            if not moved then openBox() end
        end)
    end)
    if not ok then _G.COMBOWICK_KEYPROMPT = false end
end


do
M.UI_TEXT = {
    en = {
        info_tab = "Info", you = "You", welcome = "Welcome back, <b>%s</b>", age = "Account age: %d days", server = "Server",
        copy_job = "Copy Job ID", job_copied = "Job ID copied.", rejoin = "Rejoin", rejoining = "Rejoining...",
        hop = "Server Hop", hop_tip = "Jump to another server of this game.", hop_finding = "Finding another server...", hop_none = "No other server found right now.",
        links = "Links", discord = "Copy Discord", discord_copied = "Discord link copied.", website = "Copy Website", website_copied = "Website link copied.",
        players = "Players", ping = "Ping", here_for = "In server",
        more_games = "More Games", f_upd = "Updated", upd_today = "Updated today", upd_1 = "Updated yesterday", upd_n = "Updated %d days ago",
        games_tab = "Games", browse = "Supported Games", details = "Game Info", loading = "Loading games...", show = "Show",
        f_all = "All", f_free = "Free", f_key = "Key", f_new = "New this week", pick = "Games", pick_tip = "Newest games are at the top. Type to search.",
        pick_one = "Pick a game on the left", free_yes = "Free session available", key_only = "Key required", playing = "playing now",
        players_loading = "Checking players...", added_today = "Added today", added_1 = "Added yesterday", added_n = "Added %d days ago",
        here = "You're playing this", games_word = "games", free_word = "free",
        search_games = "Search games...", no_results = "No games match your search.", theme = "Theme", theme_locked = "Premium perk — unlock with a key", theme_changed = "Theme changed to %s",
        copy_link = "Copy Game Link", link_copied = "Game link copied. Paste it in your browser.",
        copy_script = "Copy Script", copy_script_tip = "One script for every supported game.", script_copied = "Script copied. Run it in any supported game.",
        join = "Join Game", join_blocked = "This game blocks teleports. Join link copied: paste it in your browser to jump straight in.", pick_first = "Pick a game first.",
        load_fail = "Couldn't load the game list. Reopen the script to retry.",
        effects = "Effects", gold = "Gold Theme", shine = "Shine Speed", season = "Seasonal Decor", banner_copied = "Link copied",
    },
    es = {
        info_tab = "Info", you = "Tú", welcome = "Bienvenido de nuevo, <b>%s</b>", age = "Antigüedad de la cuenta: %d días", server = "Servidor",
        copy_job = "Copiar Job ID", job_copied = "Job ID copiado.", rejoin = "Reunirse", rejoining = "Volviendo a unirse...",
        hop = "Cambiar servidor", hop_tip = "Salta a otro servidor de este juego.", hop_finding = "Buscando otro servidor...", hop_none = "No hay otro servidor disponible ahora.",
        links = "Enlaces", discord = "Copiar Discord", discord_copied = "Enlace de Discord copiado.", website = "Copiar web", website_copied = "Enlace de la web copiado.",
        players = "Jugadores", ping = "Ping", here_for = "En el servidor",
        more_games = "Más juegos", f_upd = "Actualizados", upd_today = "Actualizado hoy", upd_1 = "Actualizado ayer", upd_n = "Actualizado hace %d días",
        games_tab = "Juegos", browse = "Juegos compatibles", details = "Info del juego", loading = "Cargando juegos...", show = "Mostrar",
        f_all = "Todos", f_free = "Gratis", f_key = "Clave", f_new = "Nuevos esta semana", pick = "Juegos", pick_tip = "Los juegos más nuevos están arriba. Escribe para buscar.",
        pick_one = "Elige un juego a la izquierda", free_yes = "Sesión gratis disponible", key_only = "Requiere clave", playing = "jugando ahora",
        players_loading = "Consultando jugadores...", added_today = "Añadido hoy", added_1 = "Añadido ayer", added_n = "Añadido hace %d días",
        here = "Estás jugando este", games_word = "juegos", free_word = "gratis",
        copy_link = "Copiar enlace del juego", link_copied = "Enlace copiado. Pégalo en tu navegador.",
        copy_script = "Copiar script", copy_script_tip = "Un solo script para todos los juegos compatibles.", script_copied = "Script copiado. Úsalo en cualquier juego compatible.",
        join = "Unirse al juego", join_blocked = "Roblox no permite unirse desde aquí. Se copió el enlace del juego.", pick_first = "Primero elige un juego.",
        load_fail = "No se pudo cargar la lista de juegos. Vuelve a abrir el script.",
        effects = "Efectos", gold = "Tema dorado", shine = "Velocidad del brillo", season = "Decoración de temporada", banner_copied = "Enlace copiado",
    },
    pt = {
        info_tab = "Info", you = "Você", welcome = "Bem-vindo de volta, <b>%s</b>", age = "Idade da conta: %d dias", server = "Servidor",
        copy_job = "Copiar Job ID", job_copied = "Job ID copiado.", rejoin = "Reentrar", rejoining = "Reentrando...",
        hop = "Trocar servidor", hop_tip = "Vá para outro servidor deste jogo.", hop_finding = "Procurando outro servidor...", hop_none = "Nenhum outro servidor encontrado agora.",
        links = "Links", discord = "Copiar Discord", discord_copied = "Link do Discord copiado.", website = "Copiar site", website_copied = "Link do site copiado.",
        players = "Jogadores", ping = "Ping", here_for = "No servidor",
        more_games = "Mais jogos", f_upd = "Atualizados", upd_today = "Atualizado hoje", upd_1 = "Atualizado ontem", upd_n = "Atualizado há %d dias",
        games_tab = "Jogos", browse = "Jogos suportados", details = "Info do jogo", loading = "Carregando jogos...", show = "Mostrar",
        f_all = "Todos", f_free = "Grátis", f_key = "Chave", f_new = "Novos da semana", pick = "Jogos", pick_tip = "Os jogos mais novos ficam no topo. Digite para buscar.",
        pick_one = "Escolha um jogo à esquerda", free_yes = "Sessão grátis disponível", key_only = "Precisa de chave", playing = "jogando agora",
        players_loading = "Verificando jogadores...", added_today = "Adicionado hoje", added_1 = "Adicionado ontem", added_n = "Adicionado há %d dias",
        here = "Você está jogando este", games_word = "jogos", free_word = "grátis",
        copy_link = "Copiar link do jogo", link_copied = "Link copiado. Cole no seu navegador.",
        copy_script = "Copiar script", copy_script_tip = "Um script para todos os jogos suportados.", script_copied = "Script copiado. Use em qualquer jogo suportado.",
        join = "Entrar no jogo", join_blocked = "O Roblox bloqueia entrar por aqui. O link do jogo foi copiado.", pick_first = "Escolha um jogo primeiro.",
        load_fail = "Não foi possível carregar a lista. Abra o script de novo.",
        effects = "Efeitos", gold = "Tema dourado", shine = "Velocidade do brilho", season = "Decoração da temporada", banner_copied = "Link copiado",
    },
    ru = {
        info_tab = "Инфо", you = "Вы", welcome = "С возвращением, <b>%s</b>", age = "Возраст аккаунта: %d дн.", server = "Сервер",
        copy_job = "Копировать Job ID", job_copied = "Job ID скопирован.", rejoin = "Перезайти", rejoining = "Перезаход...",
        hop = "Сменить сервер", hop_tip = "Перейти на другой сервер этой игры.", hop_finding = "Ищем другой сервер...", hop_none = "Других серверов сейчас нет.",
        links = "Ссылки", discord = "Копировать Discord", discord_copied = "Ссылка на Discord скопирована.", website = "Копировать сайт", website_copied = "Ссылка на сайт скопирована.",
        players = "Игроки", ping = "Пинг", here_for = "На сервере",
        more_games = "Другие игры", f_upd = "Обновлённые", upd_today = "Обновлено сегодня", upd_1 = "Обновлено вчера", upd_n = "Обновлено %d дн. назад",
        games_tab = "Игры", browse = "Поддерживаемые игры", details = "Об игре", loading = "Загрузка игр...", show = "Показать",
        f_all = "Все", f_free = "Бесплатно", f_key = "Ключ", f_new = "Новые за неделю", pick = "Игры", pick_tip = "Новые игры сверху. Начните вводить для поиска.",
        pick_one = "Выберите игру слева", free_yes = "Доступна бесплатная сессия", key_only = "Нужен ключ", playing = "играют сейчас",
        players_loading = "Проверяем игроков...", added_today = "Добавлено сегодня", added_1 = "Добавлено вчера", added_n = "Добавлено %d дн. назад",
        here = "Вы играете в неё", games_word = "игр", free_word = "бесплатно",
        copy_link = "Копировать ссылку", link_copied = "Ссылка скопирована. Вставьте её в браузер.",
        copy_script = "Копировать скрипт", copy_script_tip = "Один скрипт для всех поддерживаемых игр.", script_copied = "Скрипт скопирован. Запустите его в любой поддерживаемой игре.",
        join = "Войти в игру", join_blocked = "Roblox не даёт войти отсюда. Ссылка на игру скопирована.", pick_first = "Сначала выберите игру.",
        load_fail = "Не удалось загрузить список игр. Откройте скрипт снова.",
        effects = "Эффекты", gold = "Золотая тема", shine = "Скорость блеска", season = "Сезонный декор", banner_copied = "Ссылка скопирована",
    },
    ko = {
        info_tab = "정보", you = "내 정보", welcome = "다시 오신 걸 환영해요, <b>%s</b>", age = "계정 나이: %d일", server = "서버",
        copy_job = "Job ID 복사", job_copied = "Job ID를 복사했어요.", rejoin = "재접속", rejoining = "재접속 중...",
        hop = "서버 이동", hop_tip = "이 게임의 다른 서버로 이동해요.", hop_finding = "다른 서버를 찾는 중...", hop_none = "지금은 다른 서버가 없어요.",
        links = "링크", discord = "디스코드 복사", discord_copied = "디스코드 링크를 복사했어요.", website = "웹사이트 복사", website_copied = "웹사이트 링크를 복사했어요.",
        players = "플레이어", ping = "핑", here_for = "접속 시간",
        more_games = "다른 게임", f_upd = "업데이트", upd_today = "오늘 업데이트됨", upd_1 = "어제 업데이트됨", upd_n = "%d일 전 업데이트됨",
        games_tab = "게임", browse = "지원 게임", details = "게임 정보", loading = "게임 불러오는 중...", show = "보기",
        f_all = "전체", f_free = "무료", f_key = "키", f_new = "이번 주 신규", pick = "게임", pick_tip = "최신 게임이 맨 위에 있어요. 입력해서 검색하세요.",
        pick_one = "왼쪽에서 게임을 고르세요", free_yes = "무료 세션 가능", key_only = "키 필요", playing = "명 플레이 중",
        players_loading = "플레이어 확인 중...", added_today = "오늘 추가됨", added_1 = "어제 추가됨", added_n = "%d일 전 추가됨",
        here = "지금 이 게임을 하고 있어요", games_word = "개 게임", free_word = "무료",
        copy_link = "게임 링크 복사", link_copied = "링크를 복사했어요. 브라우저에 붙여넣으세요.",
        copy_script = "스크립트 복사", copy_script_tip = "모든 지원 게임에 쓰는 스크립트 하나.", script_copied = "스크립트를 복사했어요. 지원 게임에서 실행하세요.",
        join = "게임 참가", join_blocked = "여기서는 Roblox가 참가를 막아요. 대신 게임 링크를 복사했어요.", pick_first = "먼저 게임을 고르세요.",
        load_fail = "게임 목록을 불러오지 못했어요. 스크립트를 다시 실행하세요.",
        effects = "효과", gold = "골드 테마", shine = "반짝임 속도", season = "시즌 장식", banner_copied = "링크 복사됨",
    },
    ["zh-CN"] = {
        info_tab = "信息", you = "你", welcome = "欢迎回来，<b>%s</b>", age = "账号年龄：%d 天", server = "服务器",
        copy_job = "复制 Job ID", job_copied = "已复制 Job ID。", rejoin = "重新加入", rejoining = "正在重新加入...",
        hop = "换服务器", hop_tip = "跳到这个游戏的另一个服务器。", hop_finding = "正在寻找其他服务器...", hop_none = "暂时没有其他服务器。",
        links = "链接", discord = "复制 Discord", discord_copied = "已复制 Discord 链接。", website = "复制网站", website_copied = "已复制网站链接。",
        players = "玩家", ping = "延迟", here_for = "在线时间",
        more_games = "更多游戏", f_upd = "最近更新", upd_today = "今天更新", upd_1 = "昨天更新", upd_n = "%d 天前更新",
        games_tab = "游戏", browse = "支持的游戏", details = "游戏信息", loading = "正在加载游戏...", show = "显示",
        f_all = "全部", f_free = "免费", f_key = "需要卡密", f_new = "本周新增", pick = "游戏", pick_tip = "最新的游戏在最上面。输入即可搜索。",
        pick_one = "在左侧选择一个游戏", free_yes = "可免费使用", key_only = "需要卡密", playing = "人正在玩",
        players_loading = "正在获取人数...", added_today = "今天新增", added_1 = "昨天新增", added_n = "%d 天前新增",
        here = "你正在玩这个", games_word = "个游戏", free_word = "个免费",
        copy_link = "复制游戏链接", link_copied = "已复制链接，请粘贴到浏览器。",
        copy_script = "复制脚本", copy_script_tip = "一个脚本支持所有游戏。", script_copied = "已复制脚本，在任意支持的游戏中运行。",
        join = "加入游戏", join_blocked = "Roblox 不允许从这里加入，已为你复制游戏链接。", pick_first = "请先选择一个游戏。",
        load_fail = "无法加载游戏列表，请重新运行脚本。",
        effects = "特效", gold = "金色主题", shine = "光泽速度", season = "节日装饰", banner_copied = "链接已复制",
    },
    de = {
        info_tab = "Info", you = "Du", welcome = "Willkommen zurück, <b>%s</b>", age = "Kontoalter: %d Tage", server = "Server",
        copy_job = "Job-ID kopieren", job_copied = "Job-ID kopiert.", rejoin = "Neu beitreten", rejoining = "Trete neu bei...",
        hop = "Server wechseln", hop_tip = "Wechsle zu einem anderen Server dieses Spiels.", hop_finding = "Suche anderen Server...", hop_none = "Gerade kein anderer Server gefunden.",
        links = "Links", discord = "Discord kopieren", discord_copied = "Discord-Link kopiert.", website = "Webseite kopieren", website_copied = "Webseiten-Link kopiert.",
        players = "Spieler", ping = "Ping", here_for = "Auf dem Server",
        more_games = "Mehr Spiele", f_upd = "Aktualisiert", upd_today = "Heute aktualisiert", upd_1 = "Gestern aktualisiert", upd_n = "Vor %d Tagen aktualisiert",
        games_tab = "Spiele", browse = "Unterstützte Spiele", details = "Spielinfo", loading = "Lade Spiele...", show = "Anzeigen",
        f_all = "Alle", f_free = "Kostenlos", f_key = "Key", f_new = "Neu diese Woche", pick = "Spiele", pick_tip = "Neueste Spiele stehen oben. Tippe zum Suchen.",
        pick_one = "Wähle links ein Spiel", free_yes = "Kostenlose Sitzung verfügbar", key_only = "Key nötig", playing = "spielen gerade",
        players_loading = "Prüfe Spieler...", added_today = "Heute hinzugefügt", added_1 = "Gestern hinzugefügt", added_n = "Vor %d Tagen hinzugefügt",
        here = "Du spielst das gerade", games_word = "Spiele", free_word = "kostenlos",
        copy_link = "Spiel-Link kopieren", link_copied = "Link kopiert. Füge ihn im Browser ein.",
        copy_script = "Script kopieren", copy_script_tip = "Ein Script für alle unterstützten Spiele.", script_copied = "Script kopiert. Starte es in einem unterstützten Spiel.",
        join = "Spiel beitreten", join_blocked = "Roblox blockiert das Beitreten von hier. Spiel-Link wurde kopiert.", pick_first = "Wähle zuerst ein Spiel.",
        load_fail = "Spieleliste konnte nicht geladen werden. Starte das Script neu.",
        effects = "Effekte", gold = "Gold-Theme", shine = "Glanz-Tempo", season = "Saison-Deko", banner_copied = "Link kopiert",
    },
    fr = {
        info_tab = "Infos", you = "Toi", welcome = "Content de te revoir, <b>%s</b>", age = "Âge du compte : %d jours", server = "Serveur",
        copy_job = "Copier le Job ID", job_copied = "Job ID copié.", rejoin = "Rejoindre à nouveau", rejoining = "Reconnexion...",
        hop = "Changer de serveur", hop_tip = "Aller sur un autre serveur de ce jeu.", hop_finding = "Recherche d'un autre serveur...", hop_none = "Aucun autre serveur pour le moment.",
        links = "Liens", discord = "Copier Discord", discord_copied = "Lien Discord copié.", website = "Copier le site", website_copied = "Lien du site copié.",
        players = "Joueurs", ping = "Ping", here_for = "Sur le serveur",
        more_games = "Plus de jeux", f_upd = "Mis à jour", upd_today = "Mis à jour aujourd'hui", upd_1 = "Mis à jour hier", upd_n = "Mis à jour il y a %d jours",
        games_tab = "Jeux", browse = "Jeux pris en charge", details = "Infos du jeu", loading = "Chargement des jeux...", show = "Afficher",
        f_all = "Tous", f_free = "Gratuit", f_key = "Clé", f_new = "Nouveaux cette semaine", pick = "Jeux", pick_tip = "Les jeux les plus récents sont en haut. Tape pour chercher.",
        pick_one = "Choisis un jeu à gauche", free_yes = "Session gratuite disponible", key_only = "Clé requise", playing = "joueurs en ce moment",
        players_loading = "Vérification des joueurs...", added_today = "Ajouté aujourd'hui", added_1 = "Ajouté hier", added_n = "Ajouté il y a %d jours",
        here = "Tu joues à ce jeu", games_word = "jeux", free_word = "gratuits",
        copy_link = "Copier le lien du jeu", link_copied = "Lien copié. Colle-le dans ton navigateur.",
        copy_script = "Copier le script", copy_script_tip = "Un seul script pour tous les jeux pris en charge.", script_copied = "Script copié. Lance-le dans un jeu pris en charge.",
        join = "Rejoindre le jeu", join_blocked = "Roblox bloque l'accès depuis ici. Le lien du jeu a été copié.", pick_first = "Choisis d'abord un jeu.",
        load_fail = "Impossible de charger la liste des jeux. Relance le script.",
        effects = "Effets", gold = "Thème doré", shine = "Vitesse de l'éclat", season = "Déco de saison", banner_copied = "Lien copié",
    },
    th = {
        info_tab = "ข้อมูล", you = "คุณ", welcome = "ยินดีต้อนรับกลับ <b>%s</b>", age = "อายุบัญชี: %d วัน", server = "เซิร์ฟเวอร์",
        copy_job = "คัดลอก Job ID", job_copied = "คัดลอก Job ID แล้ว", rejoin = "เข้าใหม่", rejoining = "กำลังเข้าใหม่...",
        hop = "ย้ายเซิร์ฟ", hop_tip = "ไปเซิร์ฟเวอร์อื่นของเกมนี้", hop_finding = "กำลังหาเซิร์ฟเวอร์อื่น...", hop_none = "ตอนนี้ไม่พบเซิร์ฟเวอร์อื่น",
        links = "ลิงก์", discord = "คัดลอก Discord", discord_copied = "คัดลอกลิงก์ Discord แล้ว", website = "คัดลอกเว็บไซต์", website_copied = "คัดลอกลิงก์เว็บไซต์แล้ว",
        players = "ผู้เล่น", ping = "ปิง", here_for = "อยู่ในเซิร์ฟ",
        more_games = "เกมอื่น ๆ", f_upd = "อัปเดตแล้ว", upd_today = "อัปเดตวันนี้", upd_1 = "อัปเดตเมื่อวาน", upd_n = "อัปเดตเมื่อ %d วันก่อน",
        games_tab = "เกม", browse = "เกมที่รองรับ", details = "ข้อมูลเกม", loading = "กำลังโหลดเกม...", show = "แสดง",
        f_all = "ทั้งหมด", f_free = "ฟรี", f_key = "ใช้คีย์", f_new = "ใหม่สัปดาห์นี้", pick = "เกม", pick_tip = "เกมใหม่ล่าสุดอยู่ด้านบน พิมพ์เพื่อค้นหา",
        pick_one = "เลือกเกมทางซ้าย", free_yes = "เล่นฟรีได้", key_only = "ต้องใช้คีย์", playing = "คนกำลังเล่น",
        players_loading = "กำลังเช็กผู้เล่น...", added_today = "เพิ่มวันนี้", added_1 = "เพิ่มเมื่อวาน", added_n = "เพิ่มเมื่อ %d วันก่อน",
        here = "คุณกำลังเล่นเกมนี้", games_word = "เกม", free_word = "ฟรี",
        copy_link = "คัดลอกลิงก์เกม", link_copied = "คัดลอกลิงก์แล้ว วางในเบราว์เซอร์ได้เลย",
        copy_script = "คัดลอกสคริปต์", copy_script_tip = "สคริปต์เดียวใช้ได้ทุกเกมที่รองรับ", script_copied = "คัดลอกสคริปต์แล้ว รันในเกมที่รองรับได้เลย",
        join = "เข้าเกม", join_blocked = "Roblox ไม่ให้เข้าจากตรงนี้ จึงคัดลอกลิงก์เกมให้แทน", pick_first = "เลือกเกมก่อน",
        load_fail = "โหลดรายชื่อเกมไม่ได้ ลองรันสคริปต์ใหม่",
        effects = "เอฟเฟกต์", gold = "ธีมทอง", shine = "ความเร็วประกาย", season = "ของตกแต่งตามเทศกาล", banner_copied = "คัดลอกลิงก์แล้ว",
    },
    vi = {
        info_tab = "Thông tin", you = "Bạn", welcome = "Chào mừng trở lại, <b>%s</b>", age = "Tuổi tài khoản: %d ngày", server = "Máy chủ",
        copy_job = "Sao chép Job ID", job_copied = "Đã sao chép Job ID.", rejoin = "Vào lại", rejoining = "Đang vào lại...",
        hop = "Đổi máy chủ", hop_tip = "Chuyển sang máy chủ khác của game này.", hop_finding = "Đang tìm máy chủ khác...", hop_none = "Hiện chưa có máy chủ khác.",
        links = "Liên kết", discord = "Sao chép Discord", discord_copied = "Đã sao chép link Discord.", website = "Sao chép trang web", website_copied = "Đã sao chép link trang web.",
        players = "Người chơi", ping = "Ping", here_for = "Trong máy chủ",
        more_games = "Thêm game", f_upd = "Đã cập nhật", upd_today = "Cập nhật hôm nay", upd_1 = "Cập nhật hôm qua", upd_n = "Cập nhật %d ngày trước",
        games_tab = "Game", browse = "Game được hỗ trợ", details = "Thông tin game", loading = "Đang tải game...", show = "Hiển thị",
        f_all = "Tất cả", f_free = "Miễn phí", f_key = "Cần key", f_new = "Mới tuần này", pick = "Game", pick_tip = "Game mới nhất ở trên cùng. Gõ để tìm.",
        pick_one = "Chọn một game bên trái", free_yes = "Có phiên miễn phí", key_only = "Cần key", playing = "đang chơi",
        players_loading = "Đang kiểm tra người chơi...", added_today = "Thêm hôm nay", added_1 = "Thêm hôm qua", added_n = "Thêm %d ngày trước",
        here = "Bạn đang chơi game này", games_word = "game", free_word = "miễn phí",
        copy_link = "Sao chép link game", link_copied = "Đã sao chép link. Dán vào trình duyệt nhé.",
        copy_script = "Sao chép script", copy_script_tip = "Một script cho mọi game được hỗ trợ.", script_copied = "Đã sao chép script. Chạy trong game được hỗ trợ.",
        join = "Vào game", join_blocked = "Roblox chặn vào game từ đây. Đã sao chép link game.", pick_first = "Hãy chọn game trước.",
        load_fail = "Không tải được danh sách game. Chạy lại script nhé.",
        effects = "Hiệu ứng", gold = "Giao diện vàng", shine = "Tốc độ ánh sáng", season = "Trang trí theo mùa", banner_copied = "Đã sao chép liên kết",
    },
    id = {
        info_tab = "Info", you = "Kamu", welcome = "Selamat datang kembali, <b>%s</b>", age = "Umur akun: %d hari", server = "Server",
        copy_job = "Salin Job ID", job_copied = "Job ID disalin.", rejoin = "Masuk ulang", rejoining = "Masuk ulang...",
        hop = "Ganti server", hop_tip = "Pindah ke server lain di game ini.", hop_finding = "Mencari server lain...", hop_none = "Belum ada server lain sekarang.",
        links = "Tautan", discord = "Salin Discord", discord_copied = "Link Discord disalin.", website = "Salin website", website_copied = "Link website disalin.",
        players = "Pemain", ping = "Ping", here_for = "Di server",
        more_games = "Game lainnya", f_upd = "Diperbarui", upd_today = "Diperbarui hari ini", upd_1 = "Diperbarui kemarin", upd_n = "Diperbarui %d hari lalu",
        games_tab = "Game", browse = "Game yang didukung", details = "Info game", loading = "Memuat game...", show = "Tampilkan",
        f_all = "Semua", f_free = "Gratis", f_key = "Pakai key", f_new = "Baru minggu ini", pick = "Game", pick_tip = "Game terbaru ada di atas. Ketik untuk mencari.",
        pick_one = "Pilih game di kiri", free_yes = "Sesi gratis tersedia", key_only = "Butuh key", playing = "sedang main",
        players_loading = "Mengecek pemain...", added_today = "Ditambahkan hari ini", added_1 = "Ditambahkan kemarin", added_n = "Ditambahkan %d hari lalu",
        here = "Kamu sedang main ini", games_word = "game", free_word = "gratis",
        copy_link = "Salin link game", link_copied = "Link disalin. Tempel di browser kamu.",
        copy_script = "Salin script", copy_script_tip = "Satu script untuk semua game yang didukung.", script_copied = "Script disalin. Jalankan di game yang didukung.",
        join = "Masuk game", join_blocked = "Roblox memblokir masuk dari sini. Link game sudah disalin.", pick_first = "Pilih game dulu.",
        load_fail = "Gagal memuat daftar game. Jalankan ulang script.",
        effects = "Efek", gold = "Tema emas", shine = "Kecepatan kilau", season = "Dekorasi musiman", banner_copied = "Link disalin",
    },
    fil = {
        info_tab = "Info", you = "Ikaw", welcome = "Welcome back, <b>%s</b>", age = "Edad ng account: %d araw", server = "Server",
        copy_job = "Kopyahin ang Job ID", job_copied = "Nakopya ang Job ID.", rejoin = "Sumali ulit", rejoining = "Sumasali ulit...",
        hop = "Lumipat ng server", hop_tip = "Lumipat sa ibang server ng larong ito.", hop_finding = "Naghahanap ng ibang server...", hop_none = "Walang ibang server sa ngayon.",
        links = "Mga link", discord = "Kopyahin ang Discord", discord_copied = "Nakopya ang Discord link.", website = "Kopyahin ang website", website_copied = "Nakopya ang website link.",
        players = "Players", ping = "Ping", here_for = "Nasa server",
        more_games = "Iba pang laro", f_upd = "Na-update", upd_today = "Na-update ngayon", upd_1 = "Na-update kahapon", upd_n = "Na-update %d araw na ang nakalipas",
        games_tab = "Mga Laro", browse = "Suportadong laro", details = "Info ng laro", loading = "Nilo-load ang mga laro...", show = "Ipakita",
        f_all = "Lahat", f_free = "Libre", f_key = "May key", f_new = "Bago ngayong linggo", pick = "Mga Laro", pick_tip = "Nasa taas ang mga bagong laro. Mag-type para maghanap.",
        pick_one = "Pumili ng laro sa kaliwa", free_yes = "May libreng session", key_only = "Kailangan ng key", playing = "naglalaro ngayon",
        players_loading = "Tinitingnan ang players...", added_today = "Idinagdag ngayon", added_1 = "Idinagdag kahapon", added_n = "Idinagdag %d araw na ang nakalipas",
        here = "Ito ang nilalaro mo", games_word = "laro", free_word = "libre",
        copy_link = "Kopyahin ang link ng laro", link_copied = "Nakopya ang link. I-paste sa browser mo.",
        copy_script = "Kopyahin ang script", copy_script_tip = "Isang script para sa lahat ng suportadong laro.", script_copied = "Nakopya ang script. Patakbuhin sa kahit anong suportadong laro.",
        join = "Sumali sa laro", join_blocked = "Hinaharang ng Roblox ang pagsali mula rito. Nakopya na lang ang link ng laro.", pick_first = "Pumili muna ng laro.",
        load_fail = "Hindi ma-load ang listahan ng laro. Patakbuhin ulit ang script.",
        effects = "Effects", gold = "Gold Theme", shine = "Bilis ng kinang", season = "Seasonal na dekorasyon", banner_copied = "Nakopya ang link",
    },
    ar = {
        info_tab = "معلومات", you = "أنت", welcome = "أهلاً بعودتك، <b>%s</b>", age = "عمر الحساب: %d يوم", server = "السيرفر",
        copy_job = "نسخ Job ID", job_copied = "تم نسخ Job ID.", rejoin = "إعادة الدخول", rejoining = "جارٍ إعادة الدخول...",
        hop = "تغيير السيرفر", hop_tip = "الانتقال إلى سيرفر آخر في هذه اللعبة.", hop_finding = "جارٍ البحث عن سيرفر آخر...", hop_none = "لا يوجد سيرفر آخر حالياً.",
        links = "روابط", discord = "نسخ رابط ديسكورد", discord_copied = "تم نسخ رابط ديسكورد.", website = "نسخ رابط الموقع", website_copied = "تم نسخ رابط الموقع.",
        players = "اللاعبون", ping = "البنق", here_for = "في السيرفر",
        more_games = "ألعاب أخرى", f_upd = "المحدّثة", upd_today = "حُدّثت اليوم", upd_1 = "حُدّثت أمس", upd_n = "حُدّثت قبل %d يوم",
        games_tab = "الألعاب", browse = "الألعاب المدعومة", details = "معلومات اللعبة", loading = "جارٍ تحميل الألعاب...", show = "عرض",
        f_all = "الكل", f_free = "مجاني", f_key = "بمفتاح", f_new = "جديد هذا الأسبوع", pick = "الألعاب", pick_tip = "أحدث الألعاب في الأعلى. اكتب للبحث.",
        pick_one = "اختر لعبة من اليسار", free_yes = "جلسة مجانية متاحة", key_only = "يتطلب مفتاحاً", playing = "يلعبون الآن",
        players_loading = "جارٍ التحقق من اللاعبين...", added_today = "أُضيفت اليوم", added_1 = "أُضيفت أمس", added_n = "أُضيفت قبل %d يوم",
        here = "أنت تلعب هذه اللعبة", games_word = "لعبة", free_word = "مجانية",
        copy_link = "نسخ رابط اللعبة", link_copied = "تم نسخ الرابط. الصقه في متصفحك.",
        copy_script = "نسخ السكربت", copy_script_tip = "سكربت واحد لكل الألعاب المدعومة.", script_copied = "تم نسخ السكربت. شغّله في أي لعبة مدعومة.",
        join = "دخول اللعبة", join_blocked = "روبلوكس يمنع الدخول من هنا. تم نسخ رابط اللعبة بدلاً من ذلك.", pick_first = "اختر لعبة أولاً.",
        load_fail = "تعذّر تحميل قائمة الألعاب. أعد تشغيل السكربت.",
        effects = "التأثيرات", gold = "الثيم الذهبي", shine = "سرعة اللمعان", season = "زينة المواسم", banner_copied = "تم نسخ الرابط",
    },
}

-- ============================================================================
-- LOADER UI EXTRAS (2026-10-09): Info (home) tab, Games tab, gold theme.
-- The translated mains set M.LANG; text comes from M.UI_TEXT[M.LANG] with English fallback.
-- Mains call these through pcall + nil checks, so an older module just skips them.
-- ============================================================================
local function uiText()
    local all = M.UI_TEXT or {}
    local t = all[M.LANG or "en"] or {}
    local en = all.en or {}
    return function(k) return t[k] or en[k] or k end
end
local UI_GOLD, UI_GREY, UI_GREEN, UI_PURPLE = "#f0b928", "#9ca3af", "#4ade80", "#a78bfa"
local function uiCol(c, s) return '<font color="' .. c .. '">' .. s .. "</font>" end
local function uiCopy(s) local f = setclipboard or toclipboard or (syn and syn.write_clipboard) if f then pcall(f, s) return true end return false end
local function uiGet(url, headers)
    if _request then
        local ok, r = pcall(function() return _req({ Url = url, Method = "GET", Headers = headers or {} }) end)
        if ok and r and r.StatusCode == 200 then return r.Body end
        return nil
    end
    local ok, b = pcall(function() return game:HttpGet(url) end)
    return ok and b or nil
end
local function uiDecode(s) local ok, v = pcall(_jsonDecode_ref, HttpService, _fixBody and _fixBody(s or "") or (s or "")) return ok and v or nil end
local function uiClean(n)
    n = tostring(n or ""):gsub("%b[]", ""):gsub("%b()", "")
    n = n:gsub("[\240-\244][\128-\191]*", ""):gsub("[\226][\128-\191][\128-\191]", "")
    n = n:gsub("^[%s%-|:]+", ""):gsub("[%s%-|:]+$", "")
    return (n:gsub("%s+", " "))
end
local function uiShort(n) if n >= 1e6 then return string.format("%.1fM", n / 1e6) elseif n >= 1e3 then return string.format("%.1fK", n / 1e3) end return tostring(n) end
local function uiNotify(Library, m) pcall(function() Library:Notify({ Title = "COMBOWICK", Description = m, Time = 4 }) end) end

-- ---------- Info (home) tab ----------
function M.buildHomeTab(Library, Window)
    local tr = uiText()
    local Players, TeleportService, Stats = game:GetService("Players"), game:GetService("TeleportService"), game:GetService("Stats")
    local lp = Players.LocalPlayer
    local function dur(s)
        s = math.max(0, math.floor(s))
        local h, m, sec = math.floor(s / 3600), math.floor(s / 60) % 60, s % 60
        if h > 0 then return string.format("%dh %dm", h, m) elseif m > 0 then return string.format("%dm %ds", m, sec) end
        return sec .. "s"
    end
    local Tab = Window:AddTab(tr("info_tab"), "circle-user")

    local Me = Tab:AddLeftGroupbox(tr("you"), "user")
    pcall(function() Me:AddImage("CW_InfoAvatar", { Image = "rbxthumb://type=AvatarHeadShot&id=" .. lp.UserId .. "&w=150&h=150", Height = 72, ScaleType = Enum.ScaleType.Fit }) end)
    Me:AddLabel(string.format(tr("welcome"), uiCol(UI_GOLD, lp.DisplayName)), true)
    local execName = "Unknown"
    pcall(function() if identifyexecutor then local n, v = identifyexecutor(); execName = tostring(n) .. (v and (" " .. tostring(v)) or "") end end)
    Me:AddLabel(uiCol(UI_GREY, "@" .. lp.Name .. "  ·  " .. execName), true)
    Me:AddLabel(uiCol(UI_GREY, string.format(tr("age"), lp.AccountAge or 0)), true)

    local Links = Tab:AddLeftGroupbox(tr("links"), "link")
    Links:AddButton({ Text = tr("discord"), Func = function() uiCopy(M.DISCORD_INVITE); uiNotify(Library, tr("discord_copied")) end })
    Links:AddButton({ Text = tr("website"), Func = function() uiCopy(M.withCreator and M.withCreator(M.WEBSITE_URL) or M.WEBSITE_URL); uiNotify(Library, tr("website_copied")) end })
    if M.addCustomBox then pcall(M.addCustomBox, Tab, Library) end

    return Tab
end

-- ---------- Games list (shared by the loader's Games tab and the box inside game scripts) ----------
-- Data: ONE Supabase RPC call with the public anon key (no Vercel), cached on the device for 1h.
M.GAMES_RPC_URL  = "https://yrlxosurmcpxrlmxckke.supabase.co/rest/v1/rpc/cw_games_list"
M.GAMES_RPC_ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlybHhvc3VybWNweHJsbXhja2tlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA0MjQ2NzQsImV4cCI6MjA2NjAwMDY3NH0.F6y_yw26UOJPGDFyhBQ0u__QNf0FPzL2uwbuGhntWYQ"
local GAMES_CACHE, GAMES_TTL, NEW_DAYS = "combowick_games_v5.json", 3600, 7
local GAMES_HIDE = { ["9271746647"] = true } -- internal test game
local gamesMem
local function gamesDaysAgo(iso)
    local y, mo, d = tostring(iso or ""):match("^(%d+)-(%d+)-(%d+)")
    if not y then return nil end
    return math.max(0, math.floor((os.time() - os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })) / 86400 + 0.5))
end
local function loadGames()
    if gamesMem then return gamesMem end
    local cached
    pcall(function() if isfile and readfile and isfile(GAMES_CACHE) then cached = uiDecode(readfile(GAMES_CACHE)) end end)
    if cached and type(cached.t) == "number" and os.time() - cached.t < GAMES_TTL and type(cached.games) == "table" and #cached.games > 0 then
        gamesMem = cached.games
        return gamesMem
    end
    local body
    if _request then
        local ok, r = pcall(function()
            return _req({ Url = M.GAMES_RPC_URL, Method = "POST", Body = "{}", Headers = {
                ["Content-Type"] = "application/json", apikey = M.GAMES_RPC_ANON, Authorization = "Bearer " .. M.GAMES_RPC_ANON } })
        end)
        if ok and r and r.StatusCode == 200 then body = r.Body end
    end
    local rows = uiDecode(body)
    if type(rows) ~= "table" or #rows == 0 then return nil end
    local out, seen = {}, {}
    for _, g in ipairs(rows) do
        local u = tostring(g.u or "")
        if u ~= "" and not seen[u] and not GAMES_HIDE[u] then
            seen[u] = true
            out[#out + 1] = { u = u, p = tostring(g.p), n = uiClean(g.n), free = g.f == true, added = g.a, upd = g.d }
        end
    end
    gamesMem = out
    pcall(function() if writefile then writefile(GAMES_CACHE, HttpService:JSONEncode({ t = os.time(), games = out })) end end)
    return out
end
local liveCache = {}
local function livePlayers(u)
    local c = liveCache[u]
    if c and os.clock() - c.t < 60 then return c.n end
    local d = uiDecode(uiGet("https://games.roblox.com/v1/games?universeIds=" .. u))
    local n = d and d.data and d.data[1] and tonumber(d.data[1].playing)
    if n then liveCache[u] = { n = n, t = os.clock() } end
    return n
end

-- Builds the list UI into one or two groupboxes. opts.id = unique option prefix, opts.compact = script box.
local function gamesUI(Library, Left, Right, opts)
    local tr = uiText()
    local TeleportService, Players = game:GetService("TeleportService"), game:GetService("Players")
    local IQ = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/checkurasshole/Script/main/IQ"))()'
    local id = opts.id
    local games, byName, filter, selected, showToken = {}, {}, "All", nil, 0
    local function isNew(g) local d = gamesDaysAgo(g.added) return d ~= nil and d < NEW_DAYS end
    local function isUpd(g) local d = gamesDaysAgo(g.upd) return d ~= nil and d < NEW_DAYS end

    local lHeader = Left:AddLabel(uiCol(UI_GREY, tr("loading")), true)
    local refresh
    local container = Left.Container
    local searchText = ""
    local function inew(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        if parent then o.Parent = parent end
        return o
    end
    -- scheme colors (follow whatever theme is active)
    local function sc(name, fallback) local v = Library.Scheme and Library.Scheme[name] return (typeof(v) == "Color3") and v or fallback end

    -- FILTER CHIPS (full mode): All / New / Updated — replaces the old Show dropdown
    local chipBtns = {}
    local function styleChips()
        for key, b in pairs(chipBtns) do
            local on = (filter == key)
            b.BackgroundColor3 = on and sc("AccentColor", Color3.fromRGB(240, 185, 40)) or sc("MainColor", Color3.fromRGB(28, 28, 28))
            b.TextColor3 = on and Color3.fromRGB(10, 10, 10) or Color3.fromRGB(190, 190, 195)
            local st = b:FindFirstChildOfClass("UIStroke"); if st then st.Transparency = on and 1 or 0.4 end
        end
    end
    if not opts.compact and container then
        local row = inew("Frame", { Name = "CW_Chips", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1 }, container)
        inew("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, row)
        local defs = { { "All", tr("f_all") }, { "New", tr("f_new") }, { "Upd", tr("f_upd") } }
        for i, d in ipairs(defs) do
            local b = inew("TextButton", { Name = d[1], AutoButtonColor = false, BackgroundColor3 = sc("MainColor", Color3.fromRGB(28, 28, 28)), Text = d[2], Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(190, 190, 195), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i }, row)
            inew("UIPadding", { PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11) }, b)
            inew("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
            inew("UIStroke", { Color = sc("OutlineColor", Color3.fromRGB(45, 45, 45)), Transparency = 0.4 }, b)
            chipBtns[d[1]] = b
            b.MouseButton1Click:Connect(function() filter = d[1]; styleChips(); if refresh then refresh() end end)
        end
    end

    -- SEARCH (a text box, not a dropdown)
    pcall(function()
        Left:AddInput(id .. "Search", { Text = "", Placeholder = tr("search_games"), Finished = false, Callback = function(v)
            searchText = tostring(v or ""):lower(); if refresh then refresh() end
        end })
    end)

    -- CARD LIST (scrolls inside the groupbox). Shimmer placeholders show until data + thumbnails load.
    local shimmerGrads = {}   -- { grad = UIGradient, img = ImageLabel|nil, cover = Frame }
    local shimmerConn
    local holder, cardList
    local function stopShimmerLoop() if shimmerConn then shimmerConn:Disconnect(); shimmerConn = nil end end
    -- thumbnails only load while the Games tab is on screen: don't animate (or even scan) while it's hidden
    local function onScreen(o)
        while o and o:IsA("GuiObject") do if not o.Visible then return false end; o = o.Parent end
        return o ~= nil and (not o:IsA("ScreenGui") or o.Enabled)
    end
    local function startShimmerLoop()
        if shimmerConn then return end
        local RS = game:GetService("RunService")
        local t, acc = 0, 0
        shimmerConn = RS.RenderStepped:Connect(function(dt)
            t = t + dt; acc = acc + dt
            if acc < 1 / 30 then return end -- 30 fps is plenty for a loading shimmer
            acc = 0
            if not (holder and onScreen(holder)) then return end
            local any = false
            for i = #shimmerGrads, 1, -1 do
                local s = shimmerGrads[i]
                if not s.cover or not s.cover.Parent then table.remove(shimmerGrads, i)
                elseif s.img and s.img.IsLoaded then
                    s.cover.Visible = false; table.remove(shimmerGrads, i)
                else
                    any = true
                    s.grad.Offset = Vector2.new(((t * 1.1) % 2) - 1, 0)
                end
            end
            if not any and #shimmerGrads == 0 then stopShimmerLoop() end
        end)
    end
    if container then
        holder = inew("Frame", { Name = "CW_Cards", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 10), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 }, container)
        cardList = inew("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
    end
    local function addShimmer(parent, size, pos, round)
        local cover = inew("Frame", { BackgroundColor3 = Color3.fromRGB(34, 34, 36), BorderSizePixel = 0, Size = size, Position = pos or UDim2.fromScale(0, 0), ClipsDescendants = true, ZIndex = 5 }, parent)
        inew("UICorner", { CornerRadius = UDim.new(0, round or 6) }, cover)
        local sweep = inew("Frame", { BackgroundColor3 = Color3.fromRGB(70, 70, 74), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 5 }, cover)
        local g = inew("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }), Offset = Vector2.new(-1, 0) }, sweep)
        return cover, g
    end

    local img, lName, lStatus, show, render
    img    = Right:AddImage(id .. "Icon", { Image = "rbxasset://textures/ui/GuiImagePlaceholder.png", Height = opts.compact and 56 or 86, ScaleType = Enum.ScaleType.Fit })
    lName   = Right:AddLabel(uiCol(UI_GREY, tr("pick_one")), true)
    lStatus = Right:AddLabel("", true)

    render = function(g, players)
        local lines = {
            uiCol(UI_GREY, players and (uiShort(players) .. " " .. tr("playing")) or tr("players_loading")),
        }
        local du = gamesDaysAgo(g.upd)
        if du then lines[#lines + 1] = uiCol(UI_GOLD, du == 0 and tr("upd_today") or du == 1 and tr("upd_1") or string.format(tr("upd_n"), du)) end
        local d = gamesDaysAgo(g.added)
        if d then lines[#lines + 1] = uiCol(UI_GREY, d == 0 and tr("added_today") or d == 1 and tr("added_1") or string.format(tr("added_n"), d)) end
        if tostring(game.GameId) == g.u then lines[#lines + 1] = uiCol(UI_GREEN, tr("here")) end
        lStatus:SetText(table.concat(lines, "\n"))
    end
    show = function(g)
        selected = g
        if not g then return end
        showToken = showToken + 1
        local my = showToken
        pcall(function() img:SetImage("rbxthumb://type=GameIcon&id=" .. g.u .. "&w=150&h=150") end)
        lName:SetText("<b>" .. g.n .. "</b>")
        render(g, nil)
        task.spawn(function() local n = livePlayers(g.u) if my == showToken then pcall(render, g, n or 0) end end)
    end

    -- card selection highlight (follows the active accent)
    local selCard
    local function highlight(card)
        if selCard and selCard.Parent then
            local st = selCard:FindFirstChildOfClass("UIStroke"); if st then st.Color = sc("OutlineColor", Color3.fromRGB(45, 45, 45)); st.Thickness = 1; st.Transparency = 0 end
        end
        selCard = card
        if card then
            local st = card:FindFirstChildOfClass("UIStroke"); if st then st.Color = sc("AccentColor", Color3.fromRGB(240, 185, 40)); st.Thickness = 1.6; st.Transparency = 0 end
        end
    end
    -- recolor the chips + selected highlight whenever the theme applies (also corrects the
    -- cards-built-before-theme race, alongside the pill registry)
    if holder then pcall(function() M.registerTheme(holder, function() pcall(styleChips); if selCard then pcall(highlight, selCard) end end) end) end

    local function buildCard(g, order)
        local card = inew("Frame", { Name = "Card", BackgroundColor3 = sc("MainColor", Color3.fromRGB(26, 26, 26)), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = order }, holder)
        inew("UICorner", { CornerRadius = UDim.new(0, 7) }, card)
        inew("UIStroke", { Color = sc("OutlineColor", Color3.fromRGB(45, 45, 45)) }, card)
        -- thumbnail (shimmer until the image loads)
        local thumb = inew("ImageLabel", { BackgroundColor3 = Color3.fromRGB(20, 20, 20), BorderSizePixel = 0, Position = UDim2.fromOffset(7, 6), Size = UDim2.fromOffset(40, 40), ScaleType = Enum.ScaleType.Crop, Image = "rbxthumb://type=GameIcon&id=" .. g.u .. "&w=150&h=150" }, card)
        inew("UICorner", { CornerRadius = UDim.new(0, 6) }, thumb)
        local cover, grad = addShimmer(card, UDim2.fromOffset(40, 40), UDim2.fromOffset(7, 6), 6)
        shimmerGrads[#shimmerGrads + 1] = { grad = grad, img = thumb, cover = cover }
        -- name
        inew("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(56, 6), Size = UDim2.new(1, -66, 0, 20), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.fromRGB(240, 240, 242), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, Text = g.n ~= "" and g.n or g.p }, card)
        -- sub line: badge(s)
        local sub, col = nil, nil
        if tostring(game.GameId) == g.u then sub, col = tr("here"), Color3.fromRGB(90, 220, 130)
        elseif isUpd(g) then local du = gamesDaysAgo(g.upd); sub, col = (du == 0 and tr("upd_today") or du == 1 and tr("upd_1") or string.format(tr("upd_n"), du)), Color3.fromRGB(240, 200, 90)
        elseif isNew(g) then local d = gamesDaysAgo(g.added); sub, col = (d == 0 and tr("added_today") or d == 1 and tr("added_1") or string.format(tr("added_n"), d)), Color3.fromRGB(240, 200, 90)
        elseif g.free then sub, col = tr("free_yes"), Color3.fromRGB(150, 150, 156)
        end
        if sub then
            inew("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(56, 27), Size = UDim2.new(1, -66, 0, 16), Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = col, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, Text = sub }, card)
        end
        -- NEW / UPD pill (top-right)
        local pill = (isUpd(g) and "UPD") or (isNew(g) and "NEW") or nil
        if pill then
            local p = inew("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 7), Size = UDim2.fromOffset(34, 15), BackgroundColor3 = sc("AccentColor", Color3.fromRGB(240, 185, 40)), BorderSizePixel = 0 }, card)
            -- always-accent → register so Obsidian repaints it when the theme applies (cards can build
            -- before the gold theme runs on a fast cache hit, which otherwise leaves pills purple)
            pcall(function() Library:AddToRegistry(p, { BackgroundColor3 = "AccentColor" }) end)
            inew("UICorner", { CornerRadius = UDim.new(1, 0) }, p)
            inew("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = Color3.fromRGB(10, 10, 10), Text = pill }, p)
        end
        -- click target
        local btn = inew("TextButton", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "", ZIndex = 6 }, card)
        btn.MouseButton1Click:Connect(function() highlight(card); show(g) end)
        -- hover grows the card (its own accent stroke doubles as the glow); press bounce + click sound
        pcall(function() if M.addHover then M.addHover(Library, btn, card, { grow = 1.025, press = 0.975, glow = false }) end end)
        return card
    end

    -- PAGED card list: only the first PAGE matches are built; "Show more" adds the next PAGE.
    -- (building all 160+ cards = thousands of instances + 160 thumbnail loads = a big hitch on open)
    local PAGE = 12
    local MORE_TXT = { en = "Show more", es = "Ver más", pt = "Ver mais", id = "Lihat lagi", fil = "Ipakita pa", vi = "Xem thêm", th = "ดูเพิ่มเติม",
        ru = "Показать ещё", de = "Mehr anzeigen", fr = "Voir plus", ko = "더 보기", ["zh-CN"] = "显示更多", ar = "عرض المزيد" }
    local matches, built, moreBtn, buildGen = {}, 0, nil, 0
    local function buildMore(n)
        buildGen = buildGen + 1
        local myGen = buildGen
        if moreBtn then moreBtn:Destroy(); moreBtn = nil end
        local stop = math.min(#matches, built + n)
        for i = built + 1, stop do
            buildCard(matches[i], i)
            if (i - built) % 6 == 0 then task.wait(); if myGen ~= buildGen then return end end
        end
        built = stop
        local left = #matches - built
        if left > 0 then
            moreBtn = inew("TextButton", { Name = "CW_More", AutoButtonColor = false, BackgroundColor3 = sc("MainColor", Color3.fromRGB(28, 28, 28)), Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 100000,
                Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = sc("AccentColor", Color3.fromRGB(240, 185, 40)),
                Text = string.format("%s  (%d)", MORE_TXT[M.LANG or "en"] or MORE_TXT.en, left) }, holder)
            inew("UICorner", { CornerRadius = UDim.new(0, 7) }, moreBtn)
            inew("UIStroke", { Color = sc("OutlineColor", Color3.fromRGB(45, 45, 45)) }, moreBtn)
            moreBtn.MouseButton1Click:Connect(function() M.playSound("toggle"); buildMore(PAGE) end)
        end
        if #shimmerGrads > 0 then startShimmerLoop() end
        pcall(function() Left:Resize() end)
    end

    refresh = function()
        if not holder then return end
        stopShimmerLoop()
        buildGen = buildGen + 1 -- cancels a "Show more" still building
        for _, c in ipairs(holder:GetChildren()) do if c ~= cardList then c:Destroy() end end
        table.clear(shimmerGrads); selCard = nil; moreBtn = nil
        local want = nil
        local here = tostring(game.GameId)
        table.clear(matches); built = 0
        for _, g in ipairs(games) do
            local pass = (filter == "All") or (filter == "New" and isNew(g)) or (filter == "Upd" and isUpd(g))
            if pass and searchText ~= "" then pass = tostring(g.n):lower():find(searchText, 1, true) ~= nil end
            if pass then
                matches[#matches + 1] = g
                if not want or g.u == here then want = g end
            end
        end
        local shown = #matches
        lHeader:SetText(string.format("<b>%d</b> %s", shown, tr("games_word")))
        if shown == 0 then
            inew("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Color3.fromRGB(150, 150, 156), Text = tr("no_results"), LayoutOrder = 1, Parent = holder })
        end
        buildMore(PAGE)
        -- keep a current selection visible
        if want and (not selected or not selCard) then
            for _, c in ipairs(holder:GetChildren()) do
                if c:IsA("Frame") and c.Name == "Card" and c.LayoutOrder == 1 then highlight(c) end
            end
            show(want)
        end
    end
    pcall(function() Library:OnUnload(stopShimmerLoop) end)
    local function needPick()
        if selected then return false end
        uiNotify(Library, tr("pick_first"))
        return true
    end
    Right:AddButton({ Text = tr("copy_link"), Func = function()
        if needPick() then return end
        uiCopy("https://www.roblox.com/games/" .. selected.p); uiNotify(Library, tr("link_copied"))
    end })
    if not opts.compact and not opts.noScript then
        Right:AddButton({ Text = tr("copy_script"), Tooltip = tr("copy_script_tip"), Func = function()
            uiCopy(IQ); uiNotify(Library, tr("script_copied"))
        end })
    end
    Right:AddButton({ Text = tr("join"), Func = function()
        if needPick() then return end
        local g = selected
        -- Teleport works only for same-creator / third-party-enabled games; cross-creator games are
        -- blocked by Roblox server-side ("Unauthorized"). On that block, show the launch-link card
        -- (the legit cross-creator join route — same as clicking a game link).
        local failed, done = false, false
        local c
        c = TeleportService.TeleportInitFailed:Connect(function(_, result)
            failed = true
            if not done then done = true; pcall(function() c:Disconnect() end)
                if M.showJoinCard then M.showJoinCard(Library, g.n ~= "" and g.n or g.p, g.p, g.u) else uiCopy("https://www.roblox.com/games/start?placeId=" .. g.p); uiNotify(Library, tr("join_blocked")) end
            end
        end)
        pcall(function() TeleportService:Teleport(tonumber(g.p), Players.LocalPlayer) end)
        task.delay(8, function() if not done then done = true; pcall(function() c:Disconnect() end) end end)
    end })
    task.spawn(function()
        local list = loadGames()
        if list then
            games = list
            pcall(refresh)   -- refresh builds the cards and auto-selects the current/first game
        else
            pcall(function() lHeader:SetText(uiCol(UI_GREY, tr("load_fail"))) end)
        end
    end)
end

function M.buildGamesTab(Library, Window)
    local tr = uiText()
    local Tab = Window:AddTab(tr("games_tab"), "gamepad-2")
    gamesUI(Library, Tab:AddLeftGroupbox(tr("browse"), "list"), Tab:AddRightGroupbox(tr("details"), "info"), { id = "CW_Games" })
    return Tab
end

-- Own "Games" tab inside a game script's window (same layout as the loader's Games tab).
-- Called automatically once the script's Library window is up (free session + key path).
function M.addScriptGamesBox(Library)
    if type(Library) ~= "table" or Library.__cwGamesBox then return end
    local Window = Library.Window
    if not Window or type(Window.AddTab) ~= "function" then return end
    _G.__CW_GDONE = _G.__CW_GDONE or setmetatable({}, { __mode = "k" })
    if _G.__CW_GDONE[Window] then return end
    _G.__CW_GDONE[Window] = true
    local tr = uiText()
    if type(Library.Tabs) == "table" and Library.Tabs[tr("games_tab")] then return end
    Library.__cwGamesBox = true
    local Tab = Window:AddTab(tr("games_tab"), "gamepad-2")
    gamesUI(Library, Tab:AddLeftGroupbox(tr("browse"), "list"), Tab:AddRightGroupbox(tr("details"), "info"), { id = "CW_SGames", noScript = true })
    -- sidebar: slot "Games" right under the script's Suggestions tab (sidebar sorts by LayoutOrder)
    pcall(function()
        local main = Library.ScreenGui and Library.ScreenGui:FindFirstChild("Main")
        if not main then return end
        local SUGG = { ["Suggestions"] = 1, ["Suggestions / Help"] = 1, ["Sugerencias"] = 1, ["Sugestões"] = 1, ["Предложения"] = 1, ["제안"] = 1,
            ["建议"] = 1, ["Vorschläge"] = 1, ["ข้อเสนอแนะ"] = 1, ["Góp ý"] = 1, ["Saran"] = 1, ["Mungkahi"] = 1, ["الاقتراحات"] = 1, ["اقتراحات"] = 1 }
        local sug
        for _, d in ipairs(main:GetDescendants()) do
            if d:IsA("TextLabel") and (SUGG[d.Text] or d.Text:lower():find("^sugg")) then
                local b = d:FindFirstAncestorWhichIsA("TextButton")
                if b and b.Parent and b.Parent:FindFirstChildOfClass("UIListLayout") then sug = b break end
            end
        end
        if not sug then return end
        local gamesBtn
        for _, c in ipairs(sug.Parent:GetChildren()) do
            if c:IsA("TextButton") then
                for _, d in ipairs(c:GetDescendants()) do if d:IsA("TextLabel") and d.Text == tr("games_tab") then gamesBtn = c end end
            end
        end
        if not gamesBtn then return end
        local o = sug.LayoutOrder
        for _, c in ipairs(sug.Parent:GetChildren()) do
            if c:IsA("GuiObject") and c ~= gamesBtn and c.LayoutOrder > o then c.LayoutOrder = c.LayoutOrder + 1 end
        end
        gamesBtn.LayoutOrder = o + 1
    end)
end
-- wait for a freshly loaded game script's window, then add the box (no-op if it never shows)
function M.watchScriptGamesBox()
    _G.__CW_KGEN = (_G.__CW_KGEN or 0) + 1
    local myGen = _G.__CW_KGEN
    task.spawn(function()
        for _ = 1, 360 do -- up to 3 min; decorate every new script window (some scripts rebuild theirs)
            task.wait(0.5)
            if _G.__CW_KGEN ~= myGen then return end
            local L = getgenv and getgenv().Library
            if type(L) == "table" and L.Window and type(L.Tabs) == "table" and not L.__cwGamesBox then
                task.wait(1) -- let the script finish building its own tabs first
                pcall(function() if M.decorateScriptWindow then M.decorateScriptWindow(L) else M.addScriptGamesBox(L) end end)
            end
        end
    end)
end

-- ---------- decorate a game script's own window: Games tab + gold theme (+ effects box in its Settings tab) ----------
function M.decorateScriptWindow(L)
    if type(L) ~= "table" then return end
    pcall(M.addScriptGamesBox, L)
    local settings
    if type(L.Tabs) == "table" then
        settings = L.Tabs["Settings"] or L.Tabs["UI Settings"]
        if not settings then for n, t in pairs(L.Tabs) do if type(n) == "string" and n:lower():find("setting") then settings = t break end end end
    end
    pcall(M.addGoldTheme, L, settings)
end

-- ---------- gold theme ----------
-- flowing gold border, breathing glow, shimmering title, gold accent, open/close motion,
-- Obsidian's own animations on. Adds an "Effects" box (toggle + speed) to the given tab.
-- "Holy light" title effect: a light beam sweeps across the name, the letters get a glowing gold
-- outline that flares as the light passes, and little star glints twinkle above/below the name.
-- Everything lives INSIDE the title label (its parent is an auto-layout row).
-- makeHoly(title, glowCol, warmCol) -> { step, destroy, recolor }   x = shine position (-1.2 .. 1.2)
local function makeHoly(title, glowCol, warmCol)
    local z = title.ZIndex
    local made = {}
    local function new(class, props)
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        made[#made + 1] = o
        return o
    end
    local GOLD, WARM, WHITE = glowCol or Color3.fromRGB(255, 196, 40), warmCol or Color3.fromRGB(255, 232, 150), Color3.new(1, 1, 1)

    -- glow: a soft gold outline hugging the letters (text stays crisp)
    local glow = new("UIStroke", { Name = "CW_HolyGlow", Color = GOLD, Thickness = 2, Transparency = 0.7, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, LineJoinMode = Enum.LineJoinMode.Round, Parent = title })

    -- light beam with a brighter core, sweeping across the WHOLE logo box (the cell around the name),
    -- not just the text label. The box auto-lays out its children, so the beam lives in the box's
    -- parent (no layout there) and is pinned to the box's rect every frame. Falls back to the label.
    local box, host = title, title
    pcall(function()
        local p = title.Parent
        local pp = p and p.Parent
        if p and p:IsA("GuiObject") and pp and pp:IsA("GuiObject")
            and not pp:FindFirstChildWhichIsA("UIListLayout") and not pp:FindFirstChildWhichIsA("UIGridLayout") then
            box, host = p, pp
        end
    end)
    local fxZ = math.max(z, box.ZIndex) + 1
    local holder = new("Frame", { Name = "CW_HolyFX", BackgroundTransparency = 1, ClipsDescendants = true, Size = UDim2.fromScale(1, 1), ZIndex = fxZ, Parent = host })
    local function pinToBox()
        if box == host then return end
        local d = box.AbsolutePosition - host.AbsolutePosition
        holder.Position = UDim2.fromOffset(d.X, d.Y)
        holder.Size = UDim2.fromOffset(box.AbsoluteSize.X, box.AbsoluteSize.Y)
    end
    pinToBox()
    local beam = new("Frame", { Name = "Beam", BorderSizePixel = 0, BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 54, 3, 0), Rotation = 18, ZIndex = fxZ, Parent = holder })
    new("UIGradient", {
        Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, GOLD), ColorSequenceKeypoint.new(0.5, WHITE), ColorSequenceKeypoint.new(1, GOLD) }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.8), NumberSequenceKeypoint.new(0.5, 0.25),
            NumberSequenceKeypoint.new(0.7, 0.8), NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = beam,
    })
    local core = new("Frame", { Name = "Core", BorderSizePixel = 0, BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 8, 3, 0), Rotation = 18, ZIndex = fxZ + 1, Parent = holder })
    new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.1), NumberSequenceKeypoint.new(1, 1) }), Parent = core })

    -- star glints: "+" shaped (two thin crossed bars), above/below the name, not on the letters
    local sparkLayer = new("Frame", { Name = "CW_HolySparks", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z + 3, Parent = title })
    local sparks = {}
    for i = 1, 6 do
        local s = new("Frame", { Name = "Spark", BackgroundTransparency = 1, Size = UDim2.fromOffset(9, 9), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = z + 3, Parent = sparkLayer })
        local a = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 1), ZIndex = z + 3, Parent = s })
        local b = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 1, 1, 0), ZIndex = z + 3, Parent = s })
        local dot = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(3, 3), ZIndex = z + 3, Parent = s })
        new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dot })
        local sc = new("UIScale", { Scale = 0, Parent = s })
        sparks[i] = { f = s, sc = sc, parts = { a, b, dot }, t0 = -math.random() * 2, life = 0.6 }
    end
    local function placeSpark(sp, nearX)
        local w, h = sparkLayer.AbsoluteSize.X, sparkLayer.AbsoluteSize.Y
        local tb = title.TextBounds
        local left, right = (w - tb.X) / 2, (w + tb.X) / 2
        local px = nearX and math.clamp(nearX + (math.random() - 0.5) * 24, left, right) or (left + math.random() * (right - left))
        -- just above or just below the letters
        local above = math.random() < 0.5
        local py = h / 2 + (above and -1 or 1) * (tb.Y / 2 + 3 + math.random() * 4)
        sp.f.Position = UDim2.fromOffset(px, py)
        local c = (math.random() < 0.6) and WHITE or WARM
        for _, p in ipairs(sp.parts) do p.BackgroundColor3 = c end
    end

    local H = {}
    function H.step(dt, x, t)
        pinToBox()
        local w, h = holder.AbsoluteSize.X, holder.AbsoluteSize.Y
        local bx = w / 2 + x * (w * 0.6)
        beam.Position = UDim2.fromOffset(bx, h / 2)
        core.Position = beam.Position
        local visible = math.abs(x) < 1.15
        beam.Visible, core.Visible = visible, visible
        local near = math.max(0, 1 - math.abs(x) / 0.9) -- 1 while the light is over the name
        glow.Transparency = 0.72 - 0.5 * near - 0.06 * math.sin(t * 3)
        glow.Thickness = 1.5 + 1.5 * near
        for _, sp in ipairs(sparks) do
            local age = t - sp.t0
            if age > sp.life then
                sp.t0 = t + math.random() * (near > 0.2 and 0.08 or 1.0)
                sp.life = 0.5 + math.random() * 0.35
                placeSpark(sp, near > 0.2 and bx or nil)
                sp.sc.Scale = 0
            elseif age >= 0 then
                sp.sc.Scale = math.sin((age / sp.life) * math.pi) * (0.8 + 0.6 * near)
            end
        end
    end
    function H.recolor(glowCol, warmCol) GOLD, WARM = glowCol or GOLD, warmCol or WARM; glow.Color = GOLD end
    function H.destroy() for _, o in ipairs(made) do pcall(function() o:Destroy() end) end end
    return H
end

-- ===================== PREMIUM FX =====================
-- Floating logo toggle button, gold dust, watermark HUD, gold toast.
-- All toggleable in the Effects box, persisted to combowick_fx.json, rebuilt per window.
local FX_FILE = "combowick_fx.json"
M.FX = { float = true, dust = true, hud = true, splash = true, sound = true, season = true, theme = "Gold" }
M.FX_POS = {}   -- dragged positions of the floating button / HUD, saved with the toggles
pcall(function()
    if isfile and isfile(FX_FILE) then
        local ok, v = pcall(function() return HttpService:JSONDecode(readfile(FX_FILE)) end)
        if ok and type(v) == "table" then
            for k, val in pairs(v) do if type(M.FX[k]) == "boolean" and type(val) == "boolean" then M.FX[k] = val end end
            if type(v.theme) == "string" then M.FX.theme = v.theme end
            if type(v.pos) == "table" then M.FX_POS = v.pos end
        end
    end
end)
local function fxSave()
    pcall(function()
        if not writefile then return end
        local out = { pos = M.FX_POS }
        for k, v in pairs(M.FX) do out[k] = v end
        writefile(FX_FILE, HttpService:JSONEncode(out))
    end)
end
local function fxParent()
    local p = game:GetService("CoreGui")
    pcall(function() if gethui then local h = gethui(); if h then p = h end end end)
    return p
end
-- ===================== THEME PALETTES =====================
-- Gold is the default/free theme. Ruby/Emerald/Ice are a Premium-only perk (key holders only).
-- Each palette drives the gold-theme border/halo/title, the FX button/HUD/dust, and the toast.
local function c3(t) return Color3.fromRGB(t[1], t[2], t[3]) end
M.THEMES = {
    { key = "Gold",    label = "Gold",    premium = false, g1 = {150,105,15},  g2 = {240,185,40},  hot = {255,240,180}, shine = {255,236,160}, glint = {255,252,235}, accent = {240,185,40},  tgold = {255,204,51},  thot = {255,236,140}, warm = {255,232,150}, dust = {240,200,90},  btn = {240,195,60},  dot = {240,190,55} },
    { key = "Ruby",    label = "Ruby",    premium = true,  g1 = {120,14,30},   g2 = {235,55,80},   hot = {255,200,210}, shine = {255,150,170}, glint = {255,225,232}, accent = {235,55,80},   tgold = {255,80,110},  thot = {255,180,195}, warm = {255,180,195}, dust = {240,95,125},  btn = {240,85,115},  dot = {235,65,95} },
    { key = "Emerald", label = "Emerald", premium = true,  g1 = {10,80,48},    g2 = {40,210,120},  hot = {205,255,222}, shine = {160,255,200}, glint = {232,255,242}, accent = {40,210,120},  tgold = {60,225,140},  thot = {175,255,208}, warm = {180,255,210}, dust = {90,235,150},  btn = {70,225,145},  dot = {55,215,135} },
    { key = "Ice",     label = "Ice",     premium = true,  g1 = {16,72,122},   g2 = {80,190,255},  hot = {210,238,255}, shine = {170,222,255}, glint = {236,248,255}, accent = {80,190,255},  tgold = {95,200,255},  thot = {185,228,255}, warm = {190,228,255}, dust = {120,205,255}, btn = {95,198,255},  dot = {80,190,255} },
}
local function themeByKey(k) for _, p in ipairs(M.THEMES) do if p.key == k then return p end end return M.THEMES[1] end
-- live palette (Color3) refreshed by applyTheme; everything reads these
local PAL = {}
local function applyPAL(k)
    local p = themeByKey(k)
    for _, f in ipairs({ "g1","g2","hot","shine","glint","accent","tgold","thot","warm","dust","btn","dot" }) do PAL[f] = c3(p[f]) end
    PAL.key = p.key
end
applyPAL(type(M.FX.theme) == "string" and M.FX.theme or "Gold")
-- a sweeping gold->white->gold gradient from the current palette (rebuilt on theme change)
local function fxSeq()
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, PAL.g1), ColorSequenceKeypoint.new(0.40, PAL.g2), ColorSequenceKeypoint.new(0.48, PAL.hot),
        ColorSequenceKeypoint.new(0.50, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.52, PAL.hot), ColorSequenceKeypoint.new(0.60, PAL.g2),
        ColorSequenceKeypoint.new(1.00, PAL.g1),
    })
end
-- theme hooks: each live window (gold theme + FX) registers a rebuild fn keyed by its window (weak)
local themeHooks = setmetatable({}, { __mode = "k" })
function M.registerTheme(key, fn) if key and type(fn) == "function" then themeHooks[key] = fn; pcall(fn) end end
function M.applyTheme(k)
    if not k then return end
    applyPAL(k); M.FX.theme = PAL.key; fxSave()
    for _, fn in pairs(themeHooks) do pcall(fn) end
end
local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function freshScreen(name, order, ignoreInset)
    local par = fxParent()
    local old = par:FindFirstChild(name); if old then pcall(function() old:Destroy() end) end
    return mk("ScreenGui", { Name = name, ResetOnSpawn = false, IgnoreGuiInset = ignoreInset and true or false, DisplayOrder = order or 50, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, par)
end
-- Global input connections made by the FX overlays. Overlays are rebuilt for every new window, so
-- these MUST be dropped on rebuild — otherwise every rebuild stacks more listeners on every mouse move.
local fxConns = {}
local function fxClearConns()
    for _, c in ipairs(fxConns) do pcall(function() c:Disconnect() end) end
    table.clear(fxConns)
end
-- drag `frame`; onTap() fires if released as a tap (moved < 6px), onMoved(absPos) after a real drag
local function makeDraggable(frame, onTap, onMoved)
    local UIS = game:GetService("UserInputService")
    local dragging, startPos, startAbs, moved = false, nil, nil, 0
    fxConns[#fxConns + 1] = frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            -- position relative to the frame's own ScreenGui: AbsolutePosition leaves out the top-bar inset,
            -- so on an IgnoreGuiInset screen (the HUD) using it raw made the frame jump up ~58px on press
            local sg = frame:FindFirstAncestorOfClass("ScreenGui")
            dragging = true; moved = 0; startPos = input.Position
            startAbs = frame.AbsolutePosition - (sg and sg.AbsolutePosition or Vector2.zero)
        end
    end)
    fxConns[#fxConns + 1] = UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - startPos
            moved = math.max(moved, math.abs(d.X) + math.abs(d.Y))
            local ap = frame.AnchorPoint
            local sz = frame.AbsoluteSize
            frame.Position = UDim2.fromOffset(startAbs.X + d.X + ap.X * sz.X, startAbs.Y + d.Y + ap.Y * sz.Y)
        end
    end)
    fxConns[#fxConns + 1] = UIS.InputEnded:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
            if moved < 6 then
                if onTap then pcall(onTap) end
            elseif onMoved then
                pcall(onMoved, frame.Position)
            end
        end
    end)
end
local function savedPos(key, default)
    local p = M.FX_POS[key]
    if type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) then return UDim2.fromOffset(tonumber(p[1]), tonumber(p[2])) end
    return default
end
-- keep an overlay fully on screen (a drag past the edge got saved off-screen = the HUD "vanished" for good)
local function keepOnScreen(frame)
    local sg = frame:FindFirstAncestorOfClass("ScreenGui")
    local vp = sg and sg.AbsoluteSize
    if not vp or vp.X < 50 then return false end
    local ap, sz, pos = frame.AnchorPoint, frame.AbsoluteSize, frame.Position
    local x = pos.X.Scale * vp.X + pos.X.Offset - ap.X * sz.X
    local y = pos.Y.Scale * vp.Y + pos.Y.Offset - ap.Y * sz.Y
    local nx = math.clamp(x, 4, math.max(4, vp.X - sz.X - 4))
    local ny = math.clamp(y, 4, math.max(4, vp.Y - sz.Y - 4))
    if math.abs(nx - x) < 0.5 and math.abs(ny - y) < 0.5 then return false end
    frame.Position = UDim2.fromOffset(math.floor(nx + ap.X * sz.X), math.floor(ny + ap.Y * sz.Y))
    return true
end
local function rememberPos(key, frame)
    return function(pos)
        if frame and keepOnScreen(frame) then pos = frame.Position end
        M.FX_POS[key] = { pos.X.Offset, pos.Y.Offset }; fxSave()
    end
end
-- games that ship their own FPS/ping watermark: don't stack ours on top (Rivals: "fps · ms · kills")
M.NO_HUD_GAMES = { [6035872082] = true }

-- gold toast (bottom-center)
function M.toast(text, seconds)
    pcall(function()
        local TS = game:GetService("TweenService")
        local sg = freshScreen("CW_FX_Toast", 900, true)
        local card = mk("Frame", { BackgroundColor3 = Color3.fromRGB(18, 18, 18), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 80), Size = UDim2.fromOffset(10, 36), AutomaticSize = Enum.AutomaticSize.X }, sg)
        mk("UICorner", { CornerRadius = UDim.new(0, 8) }, card)
        local st = mk("UIStroke", { Thickness = 1.5, Color = Color3.new(1, 1, 1) }, card)
        mk("UIGradient", { Color = fxSeq() }, st)
        mk("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, card)
        mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.fromRGB(240, 200, 80), Text = tostring(text) }, card)
        TS:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 1, -16) }):Play()
        task.delay(seconds or 3, function()
            pcall(function() TS:Create(card, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 1, 80) }):Play() end)
            task.wait(0.35); pcall(function() sg:Destroy() end)
        end)
    end)
end

-- JOIN CARD: shown when a cross-creator game blocks in-game teleport (Roblox's own protection).
-- The launch link is the legit cross-creator join route (same as clicking a game link); we copy it
-- and show it big + selectable so mobile users can paste it into their browser to join.
function M.showJoinCard(Library, name, placeId, universeId)
    pcall(function()
        local TS = game:GetService("TweenService")
        local function acc() local c = Library and Library.Scheme and Library.Scheme.AccentColor return (typeof(c) == "Color3") and c or Color3.fromRGB(240, 185, 40) end
        local link = "https://www.roblox.com/games/start?placeId=" .. tostring(placeId)
        pcall(function() if setclipboard then setclipboard(link) end end)
        local sg = freshScreen("CW_FX_JoinCard", 950, true)
        local dim = mk("Frame", { BackgroundColor3 = Color3.fromRGB(6, 6, 8), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Active = true }, sg)
        local card = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(330, 232), BackgroundColor3 = Color3.fromRGB(16, 16, 18), BorderSizePixel = 0 }, sg)
        local cs = mk("UIScale", { Scale = 0.7 }, card)
        mk("UICorner", { CornerRadius = UDim.new(0, 12) }, card)
        local st = mk("UIStroke", { Thickness = 1.6, Color = Color3.new(1, 1, 1) }, card)
        mk("UIGradient", { Color = fxSeq() }, st)
        mk("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, card)
        local icon = mk("ImageLabel", { BackgroundColor3 = Color3.fromRGB(10, 10, 10), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(56, 56), ScaleType = Enum.ScaleType.Crop, Image = "rbxthumb://type=GameIcon&id=" .. tostring(universeId) .. "&w=150&h=150" }, card)
        mk("UICorner", { CornerRadius = UDim.new(0, 10) }, icon)
        mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 62), Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.fromRGB(245, 245, 248), TextTruncate = Enum.TextTruncate.AtEnd, Text = tostring(name) }, card)
        mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 84), Size = UDim2.new(1, 0, 0, 32), Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true, TextColor3 = Color3.fromRGB(165, 165, 172), Text = "This game blocks in-game teleport. Link copied — paste it in your browser to join:" }, card)
        -- selectable link box (long-press to copy on mobile if clipboard didn't take)
        local box = mk("TextBox", { Position = UDim2.new(0, 0, 0, 120), Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.fromRGB(26, 26, 28), BorderSizePixel = 0, Font = Enum.Font.Code, TextSize = 11, TextColor3 = Color3.fromRGB(225, 225, 230), ClearTextOnFocus = false, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left, Text = link }, card)
        mk("UICorner", { CornerRadius = UDim.new(0, 7) }, box)
        mk("UIStroke", { Color = Color3.fromRGB(45, 45, 48) }, box)
        mk("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)
        local function btn(txt, xScale, wScale, accent)
            local b = mk("TextButton", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(xScale, 0, 1, 0), Size = UDim2.new(wScale, -4, 0, 34), AutoButtonColor = false, BackgroundColor3 = accent and acc() or Color3.fromRGB(30, 30, 33), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = accent and Color3.fromRGB(12, 12, 12) or Color3.fromRGB(235, 235, 240), Text = txt }, card)
            mk("UICorner", { CornerRadius = UDim.new(0, 7) }, b)
            if not accent then mk("UIStroke", { Color = Color3.fromRGB(48, 48, 52) }, b) end
            return b
        end
        local close = btn("Close", 0, 0.5, false)
        local copy = btn("Copy Link", 0.5, 0.5, true)
        local function shut()
            pcall(function() TS:Create(cs, TweenInfo.new(0.2), { Scale = 0.75 }):Play(); TS:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play() end)
            task.delay(0.22, function() pcall(function() sg:Destroy() end) end)
        end
        close.MouseButton1Click:Connect(shut)
        dim.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then shut() end end)
        copy.MouseButton1Click:Connect(function()
            pcall(function() if setclipboard then setclipboard(link) end end)
            pcall(function() box:CaptureFocus(); box.SelectionStart = 1; box.CursorPosition = #link + 1 end)
            if M.toast then M.toast("Link copied", 2) end
        end)
        pcall(function() if M.addHover then M.addHover(Library, copy, copy, { grow = 1.04, press = 0.96 }); M.addHover(Library, close, close, { grow = 1.04, press = 0.96 }) end end)
        TS:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.35 }):Play()
        TS:Create(cs, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
        if M.playSound then M.playSound("open") end
    end)
end

-- INTRO SPLASH (once per session): the COMBO_WICK logo scales in with a light sweep and a burst of
-- gold particles over a dim backdrop, then clears to reveal the hub. Skippable by tap. Theme-aware.
function M.playSplash(onDone)
    local function finish() if onDone then pcall(onDone) end end
    if _G.__CW_SPLASH_DONE or not M.FX.splash then return finish() end
    _G.__CW_SPLASH_DONE = true
    local ok = pcall(function()
        local TS, RS = game:GetService("TweenService"), game:GetService("RunService")
        local sg = freshScreen("CW_FX_Splash", 1000, true)
        local back = mk("Frame", { BackgroundColor3 = Color3.fromRGB(8, 8, 10), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, sg)
        local holder = mk("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 110), ClipsDescendants = false }, sg)
        local scale = mk("UIScale", { Scale = 0.55 }, holder)
        -- particle layer (behind the text)
        local player = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1 }, holder)
        local parts = {}
        for i = 1, 20 do
            local p = mk("Frame", { BackgroundColor3 = (i % 3 == 0) and PAL.hot or PAL.g2, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), ZIndex = 1, BackgroundTransparency = 1 }, player)
            mk("UICorner", { CornerRadius = UDim.new(1, 0) }, p)
            local a = math.random() * 6.283
            parts[i] = { f = p, vx = math.cos(a) * (0.5 + math.random()), vy = math.sin(a) * (0.5 + math.random()), x = 0, y = 0 }
        end
        -- title with a sweeping white-hot shine
        local title = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBlack, Text = "COMBO_WICK", TextSize = 46, TextColor3 = Color3.new(1, 1, 1), ZIndex = 3 }, holder)
        local tgrad = mk("UIGradient", { Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.0, PAL.tgold), ColorSequenceKeypoint.new(0.4, PAL.thot), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(0.6, PAL.thot), ColorSequenceKeypoint.new(1.0, PAL.tgold) }), Offset = Vector2.new(-1, 0) }, title)
        mk("UIStroke", { Color = PAL.g2, Thickness = 1.5, Transparency = 0.4 }, title)
        local tag = mk("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(300, 18), Font = Enum.Font.GothamMedium, Text = "SCRIPTS", TextSize = 13, TextColor3 = PAL.g2, TextTransparency = 1, ZIndex = 3 }, title)
        local tagStroke = mk("UIStroke", { Color = PAL.g2, Transparency = 1 }, tag)

        TS:Create(back, TweenInfo.new(0.35), { BackgroundTransparency = 0.2 }):Play()
        TS:Create(scale, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
        task.delay(0.35, function() pcall(function() TS:Create(tag, TweenInfo.new(0.4), { TextTransparency = 0.15 }):Play(); TS:Create(tagStroke, TweenInfo.new(0.4), { Transparency = 0.5 }):Play() end) end)

        local done, t, conn = false, 0, nil
        local function cleanup()
            if done then return end
            done = true
            if conn then conn:Disconnect() end
            pcall(function()
                TS:Create(back, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
                TS:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1.12 }):Play()
                TS:Create(title, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
            end)
            task.delay(0.32, function() pcall(function() sg:Destroy() end) end)
            finish()
        end
        conn = RS.RenderStepped:Connect(function(dt)
            if not sg.Parent then if conn then conn:Disconnect() end return end
            t = t + dt
            tgrad.Offset = Vector2.new(math.clamp((t - 0.15) / 0.55 * 2.4 - 1.2, -1.2, 1.2), 0)
            local burst = math.min(1, t / 0.5)
            for _, p in ipairs(parts) do
                p.x = p.x + p.vx * dt * 70; p.y = p.y + p.vy * dt * 70; p.vy = p.vy + dt * 1.2
                p.f.Position = UDim2.new(0.5, p.x, 0.5, p.y)
                p.f.BackgroundTransparency = math.clamp(1 - burst, 0, 1) + math.clamp((t - 0.6) / 0.7, 0, 1)
            end
        end)
        back.Active = true
        back.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then cleanup() end
        end)
        task.delay(1.45, cleanup)
    end)
    if not ok then finish() end
end

-- Discord server logo as a local asset (downloaded once, then read from disk). nil if the executor can't.
local LOGO_FILE = "COMBOWICK_logo.png"
local LOGO_URL = "https://cdn.discordapp.com/icons/934631259861319733/a_3c6b0ba4deedbc36b995e33a02d0948c.png?size=128"
function M.logoAsset()
    if M._logo ~= nil then return M._logo or nil end
    local ok, asset = pcall(function()
        local gca = getcustomasset or (syn and syn.getsynasset)
        if not (gca and writefile and readfile and isfile) then return nil end
        local function good(s) return type(s) == "string" and #s > 200 and s:sub(2, 4) == "PNG" end
        if not (isfile(LOGO_FILE) and good(readfile(LOGO_FILE))) then
            local body = game:HttpGet(LOGO_URL)
            if not good(body) then return nil end
            writefile(LOGO_FILE, body)
        end
        local a = gca(LOGO_FILE)
        return (type(a) == "string" and a ~= "") and a or nil
    end)
    M._logo = (ok and asset) or false
    return M._logo or nil
end

-- floating button + gold dust + watermark HUD (rebuilt per window; overlays are global singletons)
function M.setupPremiumFX(Library, FX)
    local keyWin = Library.ScreenGui
    if not keyWin then return end
    local RS, TS, Stats = game:GetService("RunService"), game:GetService("TweenService"), game:GetService("Stats")
    local main = keyWin:FindFirstChild("Main")
    if _G.__CW_FX_CONN then pcall(function() _G.__CW_FX_CONN:Disconnect() end) end
    fxClearConns()

    local function isOpen() return main and main.Parent and main.Visible end
    -- use Obsidian's own toggle (keeps its state, cursor + the gold theme's pop animation in sync)
    local function toggleWindow()
        local ok = pcall(function() Library:Toggle() end)
        if not ok and main and main.Parent then
            main.Visible = not main.Visible
            pcall(function() Library.Toggled = main.Visible end)
        end
    end

    -- FLOATING LOGO BUTTON (mobile-friendly toggle). Default: left edge, middle of the screen —
    -- clear of the Roblox top bar, the mobile thumbstick (bottom-left) and jump button (bottom-right).
    local floatSG = freshScreen("CW_FX_Float", 80, false)
    local btn = mk("TextButton", { AnchorPoint = Vector2.new(0, 0.5), Position = savedPos("float", UDim2.new(0, 14, 0.42, 0)), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = Color3.fromRGB(16, 16, 16), AutoButtonColor = false, Text = "" }, floatSG)
    mk("UICorner", { CornerRadius = UDim.new(1, 0) }, btn)
    local bst = mk("UIStroke", { Thickness = 2, Color = Color3.new(1, 1, 1) }, btn)
    local bgrad = mk("UIGradient", { Color = fxSeq() }, bst)
    local blbl = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBlack, Text = "CW", TextSize = 18, TextColor3 = PAL.btn }, btn)
    makeDraggable(btn, toggleWindow, rememberPos("float", btn))
    task.delay(0.2, function() pcall(keepOnScreen, btn) end)
    -- server logo on the button (cached to disk once); "CW" text stays as the fallback
    task.spawn(function()
        local asset = M.logoAsset()
        if not asset or not btn.Parent then return end
        local img = mk("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -6, 1, -6), Image = asset, ScaleType = Enum.ScaleType.Crop }, btn)
        mk("UICorner", { CornerRadius = UDim.new(1, 0) }, img)
        blbl.Visible = false
    end)

    -- GOLD DUST (only while the hub is open — it's decoration for the window, not for gameplay)
    local dustSG = freshScreen("CW_FX_Dust", 30, true)
    local dust = {}
    for i = 1, 14 do
        local d = mk("Frame", { BackgroundColor3 = PAL.dust, BorderSizePixel = 0, Size = UDim2.fromOffset(3, 3), Position = UDim2.fromScale(math.random(), math.random()), BackgroundTransparency = 0.5 }, dustSG)
        mk("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
        dust[i] = { f = d, x = math.random(), y = math.random(), vy = 0.01 + math.random() * 0.02, sway = math.random() * 6.283 }
    end

    -- WATERMARK HUD — same look as the Rivals hub's: top-left just under Roblox's buttons, dark pill,
    -- spinning gold edge, shining COMBO_WICK, then "60 fps  ·  45 ms  ·  key" in warm grey.
    local hudSG = freshScreen("CW_FX_HUD", 70, true)
    -- the Rivals hub's gold; other (Premium) themes use their own palette
    local RIVALS_SHINE = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 82, 12)), ColorSequenceKeypoint.new(0.3, Color3.fromRGB(212, 160, 32)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 246, 210)), ColorSequenceKeypoint.new(0.7, Color3.fromRGB(212, 160, 32)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 82, 12)),
    })
    local function hudShine() return PAL.key == "Gold" and RIVALS_SHINE or fxSeq() end
    -- "hud3": fresh position key, so every saved spot (incl. ones dragged off-screen) resets to the new default
    local hud = mk("Frame", { Position = savedPos("hud3", UDim2.fromOffset(14, 58)), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromRGB(14, 12, 9), BackgroundTransparency = 0.15, BorderSizePixel = 0 }, hudSG)
    mk("UICorner", { CornerRadius = UDim.new(0, 6) }, hud)
    local hst = mk("UIStroke", { Thickness = 1.2, Color = Color3.new(1, 1, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, hud)
    local hgrad = mk("UIGradient", { Color = hudShine() }, hst)
    mk("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, hud)
    mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, hud)
    local brand = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), Text = "COMBO_WICK", LayoutOrder = 1 }, hud)
    local bgr = mk("UIGradient", { Color = hudShine() }, brand)
    -- recolor the floating button, HUD and dust when the theme changes (Premium themes)
    M.registerTheme(keyWin, function()
        pcall(function() bgrad.Color = fxSeq(); hgrad.Color = hudShine(); bgr.Color = hudShine() end)
        pcall(function() blbl.TextColor3 = PAL.btn end)
        pcall(function() for _, p in ipairs(dust) do p.f.BackgroundColor3 = PAL.dust end end)
    end)
    local hlbl = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(200, 190, 170), Text = "", LayoutOrder = 2 }, hud)
    makeDraggable(hud, nil, rememberPos("hud3", hud))
    task.delay(1, function() pcall(keepOnScreen, hud) end) -- after the text has sized it

    -- phones: Obsidian adds its own "Toggle" + "Lock" buttons (top-left). With our CW button that was 3
    -- buttons on screen, so while the CW button is on they're hidden; turning it off brings them back.
    local function syncObsidianButtons()
        pcall(function()
            local roots = {}
            if typeof(Library.Floats) == "Instance" then roots[1] = Library.Floats
            else for _, c in ipairs(keyWin:GetChildren()) do if c:IsA("Frame") and c.Name ~= "Main" then roots[#roots + 1] = c end end end
            for _, r in ipairs(roots) do
                for _, b in ipairs(r:GetChildren()) do
                    if b:IsA("TextButton") and (b.Text == "Toggle" or b.Text == "Lock" or b.Text == "Unlock") then
                        if M.FX.float then
                            if b.Visible then b:SetAttribute("CW_Hid", true); b.Visible = false end
                        elseif b:GetAttribute("CW_Hid") then
                            b:SetAttribute("CW_Hid", nil); b.Visible = true -- only ones WE hid (a script may hide them itself)
                        end
                    end
                end
            end
        end)
    end
    syncObsidianButtons()
    task.delay(1, syncObsidianButtons) -- some scripts build their window a moment later

    local hudAllowed = not M.NO_HUD_GAMES[game.GameId]
    floatSG.Enabled = M.FX.float; hudSG.Enabled = M.FX.hud and hudAllowed; dustSG.Enabled = M.FX.dust and isOpen() and true or false
    _G.__CW_FX_APPLY = function(k, v)
        if k == "float" then pcall(function() floatSG.Enabled = v end); syncObsidianButtons()
        elseif k == "dust" then pcall(function() dustSG.Enabled = v and isOpen() and true or false end)
        elseif k == "hud" then pcall(function() hudSG.Enabled = v and hudAllowed end) end
    end

    local rot, fps, t, acc, frames, lastTxt, dustAcc = 0, 60, 0, 0, 0, -1, 0
    local conn
    conn = RS.RenderStepped:Connect(function(dt)
        if not hudSG.Parent then conn:Disconnect(); return end
        t = t + dt
        frames = frames + 1; acc = acc + dt
        if acc >= 0.5 then fps = math.floor(frames / acc + 0.5); frames = 0; acc = 0 end
        local open = isOpen()

        if floatSG.Enabled then
            rot = (rot + dt * 80) % 360
            bgrad.Rotation = rot
            bst.Transparency = open and 0.1 or (0.1 + 0.25 * math.sin(t * 5))   -- pulse = "tap me to reopen"
        end

        -- dust: only while the window is open; ~30 updates/s is plenty for slow drifting specks
        local wantDust = M.FX.dust and open and true or false
        if dustSG.Enabled ~= wantDust then dustSG.Enabled = wantDust end
        if wantDust then
            dustAcc = dustAcc + dt
            if dustAcc >= 1 / 30 then
                local step = dustAcc; dustAcc = 0
                for _, p in ipairs(dust) do
                    p.y = p.y - p.vy * step * 3
                    if p.y < -0.05 then p.y = 1.05; p.x = math.random() end
                    p.f.Position = UDim2.fromScale(p.x + math.sin(t * 0.6 + p.sway) * 0.01, p.y)
                    p.f.BackgroundTransparency = 0.4 + 0.3 * math.sin(t * 1.5 + p.sway)
                end
            end
        end

        if hudSG.Enabled then
            hgrad.Rotation = (t * 110) % 360                      -- gold running around the edge
            bgr.Offset = Vector2.new(math.sin(t * 1.6) * 0.6, 0)  -- shine sliding over the name
            if (t - lastTxt) > 0.5 then
                lastTxt = t
                local ping = 0
                if not pcall(function() ping = LocalPlayer:GetNetworkPing() * 1000 end) then
                    pcall(function() ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
                end
                local m = _G.COMBOWICK_FREE and "free" or "key"
                local left = _G.__CW_FX_SESSION_LEFT
                if _G.COMBOWICK_FREE and type(left) == "number" and left > 0 then
                    m = m .. string.format(" %d:%02d", math.floor(left / 60), left % 60)
                end
                local txt = string.format("%d fps  ·  %d ms  ·  %s", fps, math.floor(ping + 0.5), m)
                if hlbl.Text ~= txt then hlbl.Text = txt end
            end
        end
    end)
    _G.__CW_FX_CONN = conn
    pcall(function() Library:OnUnload(function() if conn then conn:Disconnect() end end) end)

    -- toggles in EVERY window's Effects box (game scripts get their own Settings tab), once per window
    _G.__CW_FX_TOGGLED = _G.__CW_FX_TOGGLED or setmetatable({}, { __mode = "k" })
    if FX and not _G.__CW_FX_TOGGLED[Library] then
        _G.__CW_FX_TOGGLED[Library] = true
        pcall(function()
            FX:AddToggle("CW_FX_Float", { Text = "Floating Logo", Default = M.FX.float, Callback = function(v) M.FX.float = v; if _G.__CW_FX_APPLY then _G.__CW_FX_APPLY("float", v) end; fxSave() end })
            FX:AddToggle("CW_FX_HUD", { Text = "Watermark HUD", Default = M.FX.hud, Callback = function(v) M.FX.hud = v; if _G.__CW_FX_APPLY then _G.__CW_FX_APPLY("hud", v) end; fxSave() end })
            FX:AddToggle("CW_FX_Dust", { Text = "Gold Dust", Default = M.FX.dust, Callback = function(v) M.FX.dust = v; if _G.__CW_FX_APPLY then _G.__CW_FX_APPLY("dust", v) end; fxSave() end })
            FX:AddToggle("CW_FX_Splash", { Text = "Intro Splash", Default = M.FX.splash, Callback = function(v) M.FX.splash = v; fxSave() end })
            FX:AddToggle("CW_FX_Sound", { Text = "UI Sounds", Default = M.FX.sound, Callback = function(v) M.FX.sound = v; fxSave() end })
        end)
    end
end

-- ===================== UI SOUNDS =====================
-- Subtle clicks on open / close / toggle. Built-in rbxasset files (ship with every client → no
-- moderation, instant). Toggleable via Effects. One pooled Sound per kind, parented to SoundService.
local SND = {
    open   = { id = "rbxasset://sounds/switch.wav",     vol = 0.35, speed = 1.18 },
    close  = { id = "rbxasset://sounds/switch.wav",     vol = 0.30, speed = 0.82 },
    toggle = { id = "rbxasset://sounds/clickfast.wav",  vol = 0.28, speed = 1.00 },
    hover  = { id = "rbxasset://sounds/clickfast.wav",  vol = 0.10, speed = 1.35 },
}
local sndPool = {}
function M.playSound(kind)
    if not M.FX.sound then return end
    local def = SND[kind]; if not def then return end
    pcall(function()
        local SS = game:GetService("SoundService")
        local s = sndPool[kind]
        if not s or not s.Parent then
            s = Instance.new("Sound"); s.Name = "CW_Snd_" .. kind; s.SoundId = def.id
            s.Volume = def.vol; s.PlaybackSpeed = def.speed; s.Parent = SS
            sndPool[kind] = s
        end
        if SS.PlayLocalSound then SS:PlayLocalSound(s) else s:Play() end
    end)
end

-- ===================== BUTTON HOVER / PRESS FEEDBACK =====================
-- Grow + gold glow on hover, a small press bounce, and a soft click sound. Decorates real buttons
-- (skips transparent overlays and the big container buttons). Also handles cards (scale the card).
local function accentNow(Library) local c = Library.Scheme and Library.Scheme.AccentColor return (typeof(c) == "Color3") and c or Color3.fromRGB(240, 185, 40) end
local function ensureScale(o) local s = o:FindFirstChildOfClass("UIScale") if not s then s = Instance.new("UIScale"); s.Parent = o end return s end
local TS_HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TS_BOUNCE = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- addHover(trigger, scaleTarget, opts): opts.grow (hover scale), opts.glow (add gold stroke), opts.sound
local function addHover(Library, trigger, scaleTarget, opts, bucket)
    opts = opts or {}
    local TS = game:GetService("TweenService")
    local sc = ensureScale(scaleTarget)
    local grow = opts.grow or 1.05
    local glow
    if opts.glow then
        glow = Instance.new("UIStroke")
        glow.Color = accentNow(Library); glow.Thickness = 1.4; glow.Transparency = 1; glow.Parent = scaleTarget
    end
    local hovering = false
    local function to(scale) TS:Create(sc, TS_HOVER, { Scale = scale }):Play() end
    local conns = {
        trigger.MouseEnter:Connect(function()
            hovering = true; to(grow)
            if glow then glow.Color = accentNow(Library); TS:Create(glow, TS_HOVER, { Transparency = opts.glowT or 0.3 }):Play() end
            if opts.hoverSound then M.playSound("hover") end
        end),
        trigger.MouseLeave:Connect(function()
            hovering = false; to(1)
            if glow then TS:Create(glow, TS_HOVER, { Transparency = 1 }):Play() end
        end),
        trigger.MouseButton1Down:Connect(function() TS:Create(sc, TS_HOVER, { Scale = (opts.press or 0.95) }):Play() end),
        trigger.MouseButton1Up:Connect(function() TS:Create(sc, TS_BOUNCE, { Scale = hovering and grow or 1 }):Play() end),
        trigger.MouseButton1Click:Connect(function() if opts.sound ~= false then M.playSound("toggle") end end),
    }
    if bucket then for _, c in ipairs(conns) do bucket[#bucket + 1] = c end end
end
M.addHover = addHover

-- decorate every real action button in the window (grow + glow + press + click sound)
function M.decorateButtons(Library)
    local main = Library.ScreenGui and Library.ScreenGui:FindFirstChild("Main")
    if not main then return end
    _G.__CW_BTN = _G.__CW_BTN or setmetatable({}, { __mode = "k" })
    local bucket = {}
    local function wanted(b)
        if not b:IsA("TextButton") and not b:IsA("ImageButton") then return false end
        if _G.__CW_BTN[b] then return false end
        if b.Name == "Card" then return false end
        -- skip transparent overlays (e.g. the card click target, tab hit-boxes)
        local okBG = b:IsA("TextButton") and b.BackgroundTransparency < 0.95
        if not okBG then return false end
        -- skip very tall elements (containers), keep real buttons
        if b.AbsoluteSize.Y > 44 then return false end
        return true
    end
    local function decorate(b)
        if not wanted(b) then return end
        _G.__CW_BTN[b] = true
        pcall(addHover, Library, b, b, { grow = 1.045, glow = true, press = 0.95 }, bucket)
    end
    for _, b in ipairs(main:GetDescendants()) do decorate(b) end
    -- new buttons (card picks, lazily built tabs) get decorated too, for ~20s after load
    local gen = (_G.__CW_BTN_GEN or 0) + 1; _G.__CW_BTN_GEN = gen
    local conn
    conn = main.DescendantAdded:Connect(function(d) if _G.__CW_BTN_GEN ~= gen then conn:Disconnect(); return end pcall(decorate, d) end)
    bucket[#bucket + 1] = conn
    task.delay(20, function() if _G.__CW_BTN_GEN == gen then pcall(function() conn:Disconnect() end) end end)
    pcall(function() Library:OnUnload(function() for _, c in ipairs(bucket) do pcall(function() c:Disconnect() end) end end) end)
end

-- ===================== SEASONAL DECOR =====================
-- Small hand-drawn decorations around the hub window for the time of year (Halloween first).
-- Everything is built from plain Frames (no uploaded images), parented to the window's Main frame
-- so it hides with the hub, animated by ONE throttled loop that idles while the hub is closed.
-- The gold theme stays exactly as it is; seasons only add pieces around it.
-- Pick: server override (M.SEASON_OVERRIDE / _G.__CW_SEASON, "off" = none) > date window (UTC).
M.SEASONS = {
    { key = "halloween", from = { 10, 1 }, to = { 11, 2 } },
    { key = "christmas", from = { 12, 1 }, to = { 1, 6 } },
    { key = "valentine", from = { 2, 1 }, to = { 2, 15 } },
    { key = "easter", easter = true },   -- the week before Easter Sunday through Easter Monday
}
function M.seasonNow()
    local o = M.SEASON_OVERRIDE or rawget(_G, "__CW_SEASON")
    if o == "off" then return nil end
    if type(o) == "string" then return o end
    local d = os.date("!*t")
    local n = d.month * 100 + d.day
    for _, s in ipairs(M.SEASONS) do
        local from, to = s.from, s.to
        if s.easter then
            -- Gregorian Easter (anonymous algorithm), window = Easter - 7 days .. Easter + 1 day
            local y = d.year
            local a, b, c = y % 19, math.floor(y / 100), y % 100
            local h = (19 * a + b - math.floor(b / 4) - math.floor((b - math.floor((b + 8) / 25) + 1) / 3) + 15) % 30
            local l = (32 + 2 * (b % 4) + 2 * math.floor(c / 4) - h - c % 4) % 7
            local m = math.floor((a + 11 * h + 22 * l) / 451)
            local em, ed = math.floor((h + l - 7 * m + 114) / 31), (h + l - 7 * m + 114) % 31 + 1
            local e = os.time({ year = y, month = em, day = ed, hour = 12 })
            local s0, s1 = os.date("*t", e - 7 * 86400), os.date("*t", e + 86400)
            from, to = { s0.month, s0.day }, { s1.month, s1.day }
        end
        local a, b = from[1] * 100 + from[2], to[1] * 100 + to[2]
        if (a <= b and n >= a and n <= b) or (a > b and (n >= a or n <= b)) then return s.key end
    end
    return nil
end

local function sNew(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    pcall(function() o.Interactable = false end)   -- pure decoration: never steals clicks/drags from the hub
    if parent then o.Parent = parent end
    return o
end
local function sDot(parent, x, y, d, col, tr, z)
    local f = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(d, d), BackgroundColor3 = col, BackgroundTransparency = tr or 0, BorderSizePixel = 0, ZIndex = z or 1 }, parent)
    sNew("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
    return f
end
-- a straight stroke from (x1,y1) to (x2,y2) in the parent's offset space
local function sLine(parent, x1, y1, x2, y2, w, col, tr, z)
    local dx, dy = x2 - x1, y2 - y1
    return sNew("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
        Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 0.5, w), Rotation = math.deg(math.atan2(dy, dx)),
        BackgroundColor3 = col, BackgroundTransparency = tr or 0, BorderSizePixel = 0, ZIndex = z or 1,
    }, parent)
end
-- 0-size anchor holder placed at a point of the window (scale coords), children drawn around it
local function sPin(parent, sx, ox, sy, oy, z)
    return sNew("Frame", { Name = "CW_Season", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Position = UDim2.new(sx, ox, sy, oy), ZIndex = z or 5 }, parent)
end

local SILK = Color3.fromRGB(232, 228, 220)
local INK = Color3.fromRGB(16, 12, 20)

-- corner cobweb: radials fanning out of the corner + sagging rings between them. Static (0 cost/frame).
-- flipX/flipY mirror it into the other corners.
local function drawWeb(holder, R, flipX, flipY, z)
    local sx, sy = flipX and -1 or 1, flipY and -1 or 1
    local angles = { 2, 19, 37, 54, 71, 88 }
    local lens = { R, R * 0.86, R * 0.97, R * 0.9, R * 0.95, R * 0.84 }
    local pts = {}
    for i, a in ipairs(angles) do
        local r = math.rad(a)
        pts[i] = { math.cos(r), math.sin(r), lens[i] }
        sLine(holder, 0, 0, sx * math.cos(r) * lens[i], sy * math.sin(r) * lens[i], 1, SILK, 0.55, z)
    end
    for _, f in ipairs({ 0.24, 0.43, 0.62, 0.81 }) do
        for i = 1, #pts - 1 do
            local a, b = pts[i], pts[i + 1]
            local ra, rb = f * a[3], f * b[3]
            local ax, ay = a[1] * ra, a[2] * ra
            local bx, by = b[1] * rb, b[2] * rb
            -- midpoint sags toward the corner: that droop is what makes it read as silk, not a grid
            local mx, my = (ax + bx) / 2 * 0.86, (ay + by) / 2 * 0.86
            sLine(holder, sx * ax, sy * ay, sx * mx, sy * my, 1, SILK, 0.6, z)
            sLine(holder, sx * mx, sy * my, sx * bx, sy * by, 1, SILK, 0.6, z)
        end
    end
end

-- spider: abdomen + head + 8 two-part legs + 2 ember eyes. Returns its root frame (center = body).
local function drawSpider(parent, z)
    local root = sNew("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = z }, parent)
    local ab = sDot(root, 0, 3, 13, INK, 0, z + 1)            -- abdomen
    sNew("UIStroke", { Color = Color3.fromRGB(240, 185, 40), Thickness = 1, Transparency = 0.55 }, ab)
    sDot(root, 0, -5, 7, INK, 0, z + 1)                       -- head
    sDot(root, -2, -6, 1.8, Color3.fromRGB(255, 120, 40), 0, z + 2)
    sDot(root, 2, -6, 1.8, Color3.fromRGB(255, 120, 40), 0, z + 2)
    for side = -1, 1, 2 do
        for i, k in ipairs({ { -6, -11 }, { -2, -5 }, { 2, 3 }, { 5, 10 } }) do
            -- knee sits out and up, foot comes back down: the classic spider stance
            local hx, hy = side * 2.5, -2 + i * 1.2
            local kx, ky = side * ((i == 2 or i == 3) and 9 or 8), k[1]
            local fx, fy = side * ((i == 1 or i == 4) and 11 or 13), k[2]
            sLine(root, hx, hy, kx, ky, 1.5, INK, 0, z)
            sLine(root, kx, ky, fx, fy, 1.2, INK, 0, z)
        end
    end
    root.Rotation = 180   -- drawn head-up; spiders hang by the back end, so flip it
    return root
end

-- jack-o'-lantern sitting on the window's top edge; returns { root, glow parts } for the flicker
local function drawPumpkin(parent, z)
    local root = sNew("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = z }, parent)
    local DARK, MID, LITE = Color3.fromRGB(176, 78, 14), Color3.fromRGB(214, 104, 22), Color3.fromRGB(236, 128, 34)
    local function lobe(x, w, col, zz)
        local f = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(w, 19), BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = zz }, root)
        sNew("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
        return f
    end
    lobe(-6, 13, DARK, z); lobe(6, 13, DARK, z); lobe(-3, 12, MID, z + 1); lobe(3, 12, MID, z + 1); lobe(0, 10, LITE, z + 2)
    local stem = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(0.5, -17), Size = UDim2.fromOffset(3, 6), Rotation = 12, BackgroundColor3 = Color3.fromRGB(86, 96, 40), BorderSizePixel = 0, ZIndex = z + 3 }, root)
    sNew("UICorner", { CornerRadius = UDim.new(0, 1) }, stem)
    local FIRE = Color3.fromRGB(255, 214, 92)
    local glow = {}
    for _, x in ipairs({ -4, 4 }) do   -- carved triangle eyes (a solid triangle glyph, lit from inside)
        glow[#glow + 1] = sNew("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, -11), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, Text = "▲", Font = Enum.Font.GothamBlack, TextSize = 10, TextColor3 = FIRE, ZIndex = z + 4 }, root)
    end
    local mouth = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(0, -5.5), Size = UDim2.fromOffset(11, 3), BackgroundColor3 = FIRE, BorderSizePixel = 0, ZIndex = z + 4 }, root)
    sNew("UICorner", { CornerRadius = UDim.new(1, 0) }, mouth)
    -- two teeth notches cut back in with the pumpkin colour
    sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(-2, -7), Size = UDim2.fromOffset(2, 2), BackgroundColor3 = LITE, BorderSizePixel = 0, ZIndex = z + 5 }, root)
    sNew("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(2.5, -4), Size = UDim2.fromOffset(2, 2), BackgroundColor3 = LITE, BorderSizePixel = 0, ZIndex = z + 5 }, root)
    glow[#glow + 1] = mouth
    return root, glow
end

-- bat silhouette: body + ears + two jagged wings that flap (the wing holders rotate)
local function drawBat(parent, z)
    local root = sNew("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = z }, parent)
    sDot(root, 0, 1, 7, INK, 0, z + 1)
    sDot(root, 0, -3.5, 5, INK, 0, z + 1)
    sLine(root, -1.6, -5, -2.4, -8, 1.4, INK, 0, z + 1)
    sLine(root, 1.6, -5, 2.4, -8, 1.4, INK, 0, z + 1)
    local wings = {}
    for side = -1, 1, 2 do
        local w = sNew("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Position = UDim2.fromOffset(side * 2, -1), ZIndex = z }, root)
        -- leading edge (arm) + three finger bones; the gaps between finger tips give the scalloped edge
        sLine(w, 0, 0, side * 9, -5, 2.6, INK, 0, z)
        sLine(w, side * 9, -5, side * 16, -2, 2, INK, 0, z)
        sLine(w, 0, 1, side * 7, 3, 3.2, INK, 0, z)
        sLine(w, side * 6, -2, side * 13, 2, 2.6, INK, 0, z)
        sLine(w, side * 3, 0, side * 9, 1, 3.4, INK, 0, z)
        wings[side] = w
    end
    return root, wings
end

-- little ghost: domed sheet with a scalloped hem, two oval eyes and an "o" mouth
local function drawGhost(parent, z)
    local SHEET = Color3.fromRGB(238, 236, 244)
    local root = sNew("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = z }, parent)
    local body = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(0, -12), Size = UDim2.fromOffset(20, 22), BackgroundColor3 = SHEET, BorderSizePixel = 0, ZIndex = z }, root)
    sNew("UICorner", { CornerRadius = UDim.new(0, 10) }, body)
    sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(0, -2), Size = UDim2.fromOffset(20, 10), BackgroundColor3 = SHEET, BorderSizePixel = 0, ZIndex = z }, root)   -- squares the lower half
    for _, x in ipairs({ -7, 0, 7 }) do sDot(root, x, 9, 7, SHEET, 0, z) end                                -- hem bumps
    local eyes = { sDot(root, -3.5, -3, 3, INK, 0, z + 1), sDot(root, 3.5, -3, 3, INK, 0, z + 1) }
    for _, e in ipairs(eyes) do e.Size = UDim2.fromOffset(3, 4.5) end
    local mouth = sDot(root, 0, 2.5, 3.5, INK, 0, z + 1)
    sNew("UIStroke", { Color = Color3.fromRGB(150, 140, 175), Thickness = 1, Transparency = 0.5 }, body)
    return root, eyes, mouth
end

-- ---------- Halloween ----------
local function buildHalloween(main, D)
    local Z = 6
    local function winW() local sc = main:FindFirstChildOfClass("UIScale"); return main.AbsoluteSize.X / ((sc and sc.Scale) or 1) end
    -- web in the top-left corner (a few faint strands over the logo corner) + two dew drops that catch the light
    local webPin = sPin(main, 0, 1, 0, 1, Z)
    drawWeb(webPin, 58, false, false, Z)
    local dew = { sDot(webPin, 31, 13, 2.5, Color3.new(1, 1, 1), 0.3, Z + 1), sDot(webPin, 14, 33, 2, Color3.new(1, 1, 1), 0.3, Z + 1) }
    D.parts[#D.parts + 1] = webPin

    -- spider hanging off the bottom edge on its thread; bobs, now and then lowers itself for a look,
    -- and scurries back up when you hover it
    local sPinF = sPin(main, 0.74, 0, 1, 0, Z)
    local thread = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(1, 30), BackgroundColor3 = SILK, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = Z }, sPinF)
    local spider = drawSpider(sPinF, Z + 1)
    local hit = Instance.new("Frame")
    hit.BackgroundTransparency = 1; hit.AnchorPoint = Vector2.new(0.5, 0.5); hit.Size = UDim2.fromOffset(30, 30); hit.ZIndex = Z + 5; hit.Parent = sPinF
    D.parts[#D.parts + 1] = sPinF
    local drop, want, scared, lower, nextLower = 30, 30, 0, 0, 12 + math.random() * 10
    D.conns[#D.conns + 1] = hit.MouseEnter:Connect(function() scared = 2.6; lower = 0 end)

    -- pumpkin sitting on the top edge, right side, candle flicker in its carved face
    local pPin = sPin(main, 1, -36, 0, 0, Z)
    local halo = {}   -- candle glow: two stacked faint discs fake a soft radial falloff
    for i, d in ipairs({ 40, 28 }) do halo[i] = sDot(pPin, 0, -14, d, Color3.fromRGB(255, 130, 30), 0.94, Z - 1) end
    local pRoot, glow = drawPumpkin(pPin, Z)
    sNew("UIScale", { Scale = 1.5 }, pRoot)
    D.parts[#D.parts + 1] = pPin

    -- ghost: lives in a clipped slot on the window's left edge, so it slides out from BEHIND the window,
    -- looks around for a few seconds, blinks, and ducks back. Hover = it hides straight away.
    local slot = sNew("Frame", { Name = "CW_Season", BackgroundTransparency = 1, ClipsDescendants = true, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0, -1, 0.62, 0), Size = UDim2.fromOffset(34, 44), ZIndex = Z }, main)
    local gRoot, gEyes, gMouth = drawGhost(slot, Z)
    local gHit = Instance.new("Frame"); gHit.BackgroundTransparency = 1; gHit.Size = UDim2.fromScale(1, 1); gHit.ZIndex = Z + 3; gHit.Parent = slot
    D.parts[#D.parts + 1] = slot
    local gx, gWant, gTimer, gNext = 50, 50, 0, 6 + math.random() * 6
    D.conns[#D.conns + 1] = gHit.MouseEnter:Connect(function() if gTimer > 0 then gTimer = 0; gNext = 25 + math.random() * 20 end end)

    -- bats: none exist between flybys (zero cost); 1-3 cross above the window every 20-40 s
    local bats = {}
    local nextBat = 4 + math.random() * 4
    local function spawnFlock()
        local fromLeft = math.random() < 0.5
        local n = math.random() < 0.55 and 1 or math.random(2, 3)
        local y = -48 - math.random(0, 16)   -- above the sale tab
        local dur = 3.4 + math.random() * 1.2
        for i = 1, n do
            local holder = sPin(main, fromLeft and 0 or 1, fromLeft and -30 or 30, 0, y, Z + 2)
            local root, wings = drawBat(holder, Z + 2)
            sNew("UIScale", { Scale = (i == 1 and 1 or 0.72) * (0.85 + math.random() * 0.3) }, root)
            bats[#bats + 1] = { holder = holder, wings = wings, t = -(i - 1) * (0.22 + math.random() * 0.2), dur = dur * (0.95 + math.random() * 0.1),
                dir = fromLeft and 1 or -1, y0 = y + (i - 1) * (math.random(0, 1) == 0 and -9 or 9), amp = 5 + math.random() * 7, ph = math.random() * 6, fl = 19 + math.random() * 6 }
        end
    end

    local t = 0
    return function(dt)
        t = t + dt
        -- spider
        if lower > 0 then lower = lower - dt end
        nextLower = nextLower - dt
        if nextLower <= 0 then lower = 2.4; nextLower = 22 + math.random() * 18 end
        if scared > 0 then scared = scared - dt; want = 4
        elseif lower > 0 then want = 58
        else want = 30 + 4 * math.sin(t * 1.1) end
        drop = drop + (want - drop) * math.min(1, dt * (scared > 0 and 9 or (lower > 0 and 1.6 or 2.5)))
        thread.Size = UDim2.fromOffset(1, drop)
        spider.Position = UDim2.fromOffset(math.sin(t * 0.7) * 1.2, drop + 6)
        hit.Position = spider.Position
        -- candle: irregular flicker (two sines + a little noise), never fully dark
        local f = 0.12 + 0.12 * (math.sin(t * 9.3) * 0.5 + math.sin(t * 4.1 + 1.7) * 0.5) + math.random() * 0.06
        f = math.max(0, f)
        for _, g in ipairs(glow) do if g.ClassName == "TextLabel" then g.TextTransparency = f else g.BackgroundTransparency = f end end
        for _, h in ipairs(halo) do h.BackgroundTransparency = 0.9 + f * 0.25 end
        -- dew: each drop glints briefly on its own slow cycle
        for i, d in ipairs(dew) do d.BackgroundTransparency = 0.25 + 0.7 * (1 - math.max(0, math.sin(t * 0.9 + i * 2.4)) ^ 6) end
        -- ghost
        if gTimer > 0 then
            gTimer = gTimer - dt
            gWant = 23   -- right side stays tucked behind the window edge: a peek, not a stroll
            if gTimer <= 0 then gNext = 30 + math.random() * 30 end
        else
            gWant = 50
            gNext = gNext - dt
            if gNext <= 0 then gTimer = 4.5 end
        end
        gx = gx + (gWant - gx) * math.min(1, dt * (gWant < 30 and 2.2 or 5))
        gRoot.Position = UDim2.fromOffset(gx, 22 + math.sin(t * 2) * 2)
        local blink = (t % 3.1) < 0.12
        for i, e in ipairs(gEyes) do e.Size = UDim2.fromOffset(3, blink and 1 or 4.5); e.Position = UDim2.fromOffset(i == 1 and -3.5 or 3.5, -3) end
        gMouth.Size = UDim2.fromOffset(3.5, 3.5 + math.max(0, math.sin(t * 1.7)) * 1.5)
        -- bats
        if #bats == 0 then
            nextBat = nextBat - dt
            if nextBat <= 0 then spawnFlock() end
        else
            local W = winW()
            for i = #bats, 1, -1 do
                local b = bats[i]
                b.t = b.t + dt
                local p = math.max(0, b.t / b.dur)
                b.holder.Position = UDim2.new(b.dir > 0 and 0 or 1, b.dir * (-30 + p * (W + 60)), 0, b.y0 + math.sin(p * 7 + b.ph) * b.amp)
                local flap = math.sin(b.t * b.fl)
                b.wings[-1].Rotation = flap * 28
                b.wings[1].Rotation = -flap * 28
                if p >= 1 then b.holder:Destroy(); table.remove(bats, i) end
            end
            if #bats == 0 then nextBat = 20 + math.random() * 20 end
        end
    end
end

-- ---------- Christmas ----------
local SNOW = Color3.fromRGB(246, 249, 255)
local SNOW_SH = Color3.fromRGB(196, 212, 236)

-- holly sprig: two leaves (rotated pointed ovals with a vein) + three berries
local function drawHolly(parent, z)
    local root = sNew("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = z }, parent)
    local LEAF, VEIN = Color3.fromRGB(34, 120, 62), Color3.fromRGB(70, 160, 95)
    for _, l in ipairs({ { -8, 1, -28 }, { 8, 1, 28 }, { 0, 9, 90 } }) do
        local f = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(l[1], l[2]), Size = UDim2.fromOffset(18, 8), Rotation = l[3], BackgroundColor3 = LEAF, BorderSizePixel = 0, ZIndex = z }, root)
        sNew("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
        sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.8, 0, 0, 1), BackgroundColor3 = VEIN, BorderSizePixel = 0, ZIndex = z }, f)
    end
    for _, b in ipairs({ { -2.5, -1 }, { 2.5, -1.5 }, { 0, 3 } }) do
        local d = sDot(root, b[1], b[2], 5.5, Color3.fromRGB(205, 32, 44), 0, z + 1)
        sDot(d, 3.6, 1.8, 1.6, Color3.new(1, 1, 1), 0.35, z + 2)   -- shine
    end
    return root
end

-- small tiered tree with a star; returns root, ornament dots, star label
local function drawTree(parent, z)
    local root = sNew("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = z }, parent)
    local G1, G2 = Color3.fromRGB(26, 96, 52), Color3.fromRGB(38, 128, 68)
    sNew("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.fromRGB(110, 70, 40), BorderSizePixel = 0, ZIndex = z }, root)
    -- tiers bottom -> top, each a little narrower; the lighter top strip of each tier gives depth
    for i, tier in ipairs({ { 22, -3 }, { 17, -9 }, { 12, -15 }, { 7, -20 } }) do
        local f = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(0, tier[2]), Size = UDim2.fromOffset(tier[1], 8), BackgroundColor3 = i % 2 == 0 and G2 or G1, BorderSizePixel = 0, ZIndex = z + i }, root)
        sNew("UICorner", { CornerRadius = UDim.new(0, 3) }, f)
        sNew("Frame", { Position = UDim2.fromOffset(2, 1), Size = UDim2.new(1, -4, 0, 2), BackgroundColor3 = SNOW, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = z + i }, f)   -- snow on the branch
    end
    local orn = {}
    local COLS = { Color3.fromRGB(235, 60, 60), Color3.fromRGB(255, 200, 60), Color3.fromRGB(90, 170, 255), Color3.fromRGB(235, 60, 60), Color3.fromRGB(255, 200, 60) }
    for i, p in ipairs({ { -6, -6 }, { 5, -7 }, { -3, -13 }, { 4, -18 }, { 0, -9 } }) do
        orn[i] = sDot(root, p[1], p[2], 3, COLS[i], 0, z + 6)
    end
    local star = sNew("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(0, -29), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1, Text = "★", Font = Enum.Font.GothamBlack, TextSize = 12, TextColor3 = Color3.fromRGB(255, 214, 80), ZIndex = z + 7 }, root)
    return root, orn, star
end

local function buildChristmas(main, D)
    local Z = 6
    local function winW() local sc = main:FindFirstChildOfClass("UIScale"); return main.AbsoluteSize.X / ((sc and sc.Scale) or 1) end

    -- snow lying on the top edge: overlapping drifts (scale-positioned, so it follows window resizes)
    local cap = sNew("Frame", { Name = "CW_Season", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), ZIndex = Z }, main)
    local rnd = Random.new(7)   -- fixed seed: the same snow shape every time, no jitter between opens
    local x = 0
    while x < 1 do
        local w = rnd:NextInteger(26, 46)
        local h = rnd:NextInteger(5, 11)
        local f = sNew("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(x, -4, 0, 3), Size = UDim2.fromOffset(w, h), BackgroundColor3 = SNOW, BorderSizePixel = 0, ZIndex = Z + 1 }, cap)
        sNew("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
        sNew("UIGradient", { Rotation = 90, Color = ColorSequence.new(SNOW, SNOW_SH) }, f)
        x = x + w / 560 * 0.78
    end
    -- a few short icicles hanging off the snow, clear of the title and the tree
    for _, ic in ipairs({ { 0.065, 9 }, { 0.09, 6 }, { 0.36, 5 }, { 0.8, 7 }, { 0.82, 4 } }) do
        local f = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(ic[1], 0, 1, 0), Size = UDim2.fromOffset(3, ic[2]), BackgroundColor3 = Color3.fromRGB(215, 235, 255), BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = Z }, cap)
        sNew("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
    end
    D.parts[#D.parts + 1] = cap

    -- holly on the top-left corner
    local hPin = sPin(main, 0, 6, 0, 4, Z + 2)
    drawHolly(hPin, Z + 2)
    D.parts[#D.parts + 1] = hPin

    -- little tree standing on the top edge, right side; the star twinkles, ornaments glow in turn
    local tPin = sPin(main, 1, -36, 0, 1, Z + 1)
    local tRoot, orn, star = drawTree(tPin, Z + 1)
    sNew("UIScale", { Scale = 1.35 }, tRoot)
    D.parts[#D.parts + 1] = tPin

    -- string of lights draped under the bottom edge: sagging wire spans + a bulb at each hook,
    -- chasing twinkle. Rebuilt when the window is resized (the sag is drawn in pixels).
    local lights = sNew("Frame", { Name = "CW_Season", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, 0, 1, 1), Size = UDim2.new(1, 0, 0, 0), ZIndex = Z }, main)
    D.parts[#D.parts + 1] = lights
    local bulbs = {}
    local BULB = { Color3.fromRGB(240, 70, 70), Color3.fromRGB(70, 210, 120), Color3.fromRGB(255, 200, 60), Color3.fromRGB(90, 170, 255) }
    local WIRE = Color3.fromRGB(30, 50, 34)
    local builtW = 0
    local function buildLights()
        for _, c in ipairs(lights:GetChildren()) do c:Destroy() end
        table.clear(bulbs)
        local W = winW(); builtW = W
        local n = math.max(6, math.floor(W / 42))
        local span = W / n
        for i = 0, n - 1 do
            local x0 = i * span
            -- each span sags in a shallow curve: 4 straight pieces along y = 4 * sag * u * (1 - u)
            local sag = 9
            local px, py = x0, 0
            for k = 1, 4 do
                local u = k / 4
                local nx, ny = x0 + span * u, 4 * sag * u * (1 - u)
                sLine(lights, px, py, nx, ny, 1.2, WIRE, 0, Z)
                px, py = nx, ny
            end
            -- bulb hangs from the lowest point of the span
            local bx, by = x0 + span / 2, sag + 1
            local col = BULB[i % #BULB + 1]
            sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(bx, by - 1), Size = UDim2.fromOffset(3, 3), BackgroundColor3 = Color3.fromRGB(70, 74, 70), BorderSizePixel = 0, ZIndex = Z + 1 }, lights)   -- socket
            local glow = sDot(lights, bx, by + 6, 14, col, 0.85, Z)
            local b = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(bx, by + 1.5), Size = UDim2.fromOffset(5, 8), BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = Z + 1 }, lights)
            sNew("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
            bulbs[#bulbs + 1] = { b = b, g = glow, i = i }
        end
    end
    buildLights()

    -- snowfall: 12 flakes recycled forever, drifting over and around the window (scale coords)
    local flakes = {}
    local fl = sNew("Frame", { Name = "CW_Season", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Z + 3 }, main)
    D.parts[#D.parts + 1] = fl
    for i = 1, 12 do
        local d = math.random(2, 4)
        local f = sDot(fl, 0, 0, d, SNOW, 0.15 + math.random() * 0.35, Z + 3)
        flakes[i] = { f = f, x = math.random() * 1.1 - 0.05, y = math.random() * 1.2 - 0.15, v = 0.03 + math.random() * 0.04 + d * 0.008, ph = math.random() * 6, sw = 0.006 + math.random() * 0.01 }
    end

    local t, sizeCheck = 0, 0
    return function(dt)
        t = t + dt
        sizeCheck = sizeCheck + dt
        if sizeCheck > 0.5 then sizeCheck = 0; if math.abs(winW() - builtW) > 6 then buildLights() end end
        -- lights: a soft chase down the string, each bulb dims and brightens in turn
        for _, L in ipairs(bulbs) do
            local k = 0.5 + 0.5 * math.sin(t * 2.6 - L.i * 1.1)
            L.b.BackgroundTransparency = 0.35 * (1 - k)
            L.g.BackgroundTransparency = 0.95 - 0.13 * k
        end
        -- tree: ornaments glow in turn, star twinkles (size + brightness)
        for i, o in ipairs(orn) do o.BackgroundTransparency = 0.45 * (0.5 + 0.5 * math.sin(t * 2 + i * 1.3)) end
        local s = 0.5 + 0.5 * math.sin(t * 3.3)
        star.TextSize = 11 + s * 3
        star.TextTransparency = 0.15 * (1 - s)
        -- snow
        for _, p in ipairs(flakes) do
            p.y = p.y + p.v * dt
            if p.y > 1.15 then p.y = -0.12; p.x = math.random() * 1.1 - 0.05 end
            p.f.Position = UDim2.fromScale(p.x + math.sin(t * 0.9 + p.ph) * p.sw, p.y)
        end
    end
end

-- ---------- Valentine's ----------
local PINK, ROSE, BLUSH = Color3.fromRGB(240, 96, 140), Color3.fromRGB(214, 40, 84), Color3.fromRGB(255, 196, 214)

-- heart: a 45-degree square with two circles on its upper edges. Size ~ s px wide.
local function drawHeart(parent, s, col, tr, z)
    local root = sNew("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = z }, parent)
    local q = s * 0.5
    local sq = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(0, q * 0.32), Size = UDim2.fromOffset(q, q), Rotation = 45, BackgroundColor3 = col, BackgroundTransparency = tr or 0, BorderSizePixel = 0, ZIndex = z }, root)
    local a = sDot(root, -q * 0.36, -q * 0.05, q, col, tr, z)
    local b = sDot(root, q * 0.36, -q * 0.05, q, col, tr, z)
    return root, { sq, a, b }
end

-- gift bow: two loops, a knot and two tails
local function drawBow(parent, z)
    local root = sNew("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = z }, parent)
    for side = -1, 1, 2 do
        local loop = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(side * 7, -2), Size = UDim2.fromOffset(14, 9), Rotation = side * -18, BackgroundColor3 = PINK, BorderSizePixel = 0, ZIndex = z }, root)
        sNew("UICorner", { CornerRadius = UDim.new(1, 0) }, loop)
        sNew("UIStroke", { Color = ROSE, Thickness = 1.5 }, loop)
        sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(6, 3), BackgroundColor3 = ROSE, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = z }, loop)   -- inner fold
        sLine(root, side * 1.5, 2, side * 7, 12, 3.2, ROSE, 0, z - 1)                                                                                   -- tail
    end
    sDot(root, 0, -1, 7, ROSE, 0, z + 1)
    return root
end

-- love letter: envelope with its flap and a heart seal
local function drawLetter(parent, z)
    local root = sNew("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = z }, parent)
    local env = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(24, 16), Rotation = -8, BackgroundColor3 = Color3.fromRGB(250, 242, 232), BorderSizePixel = 0, ZIndex = z }, root)
    sNew("UICorner", { CornerRadius = UDim.new(0, 2) }, env)
    sNew("UIStroke", { Color = Color3.fromRGB(200, 180, 170), Thickness = 1 }, env)
    sLine(env, 0, 0, 12, 9, 1, Color3.fromRGB(200, 180, 170), 0, z)
    sLine(env, 24, 0, 12, 9, 1, Color3.fromRGB(200, 180, 170), 0, z)
    local seal = drawHeart(env, 8, ROSE, 0, z + 1)
    seal.Position = UDim2.fromOffset(12, 9)
    return root, seal
end

local function buildValentine(main, D)
    local Z = 6
    local function winW() local sc = main:FindFirstChildOfClass("UIScale"); return main.AbsoluteSize.X / ((sc and sc.Scale) or 1) end
    -- ribbon wrapped round the top-left corner like a present, bow on the corner
    local rib = sPin(main, 0, 0, 0, 0, Z)
    sLine(rib, -2, 34, 34, -2, 5, PINK, 0, Z)
    sLine(rib, -2, 34, 34, -2, 1, BLUSH, 0.3, Z)   -- satin highlight
    local bow = drawBow(rib, Z + 2); bow.Position = UDim2.fromOffset(16, 16)
    D.parts[#D.parts + 1] = rib

    -- love letter on the top edge, right side; its seal pulses like a heartbeat
    local lPin = sPin(main, 1, -38, 0, 2, Z)
    local lRoot, seal = drawLetter(lPin, Z)
    sNew("UIScale", { Scale = 1.3 }, lRoot)
    local sealScale = sNew("UIScale", { Scale = 1 }, seal)
    D.parts[#D.parts + 1] = lPin

    -- garland of little hearts under the bottom edge on a thin cord (rebuilt on resize)
    local gar = sNew("Frame", { Name = "CW_Season", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, 1), Size = UDim2.new(1, 0, 0, 0), ZIndex = Z }, main)
    D.parts[#D.parts + 1] = gar
    local hearts, builtW = {}, 0
    local function buildGarland()
        for _, c in ipairs(gar:GetChildren()) do c:Destroy() end
        table.clear(hearts)
        local W = winW(); builtW = W
        local n = math.max(5, math.floor(W / 56))
        local span = W / n
        for i = 0, n - 1 do
            local x0, sag = i * span, 9
            local px, py = x0, 0
            for k = 1, 4 do
                local u = k / 4
                local nx, ny = x0 + span * u, 4 * sag * u * (1 - u)
                sLine(gar, px, py, nx, ny, 1, BLUSH, 0.2, Z)
                px, py = nx, ny
            end
            local hs = (i % 2 == 0) and 16 or 13
            -- the heart hangs from the low point of the cord by a short thread, pivoting at the top
            local hang = sNew("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(x0 + span / 2, sag), Size = UDim2.fromOffset(0, 0), ZIndex = Z + 1 }, gar)
            sLine(hang, 0, 0, 0, 4, 1, BLUSH, 0.2, Z)
            local h = drawHeart(hang, hs, (i % 2 == 0) and ROSE or PINK, 0, Z + 1)
            h.Position = UDim2.fromOffset(0, 4 + hs * 0.42)
            hearts[#hearts + 1] = { h = hang, i = i }
        end
    end
    buildGarland()

    -- a few hearts float up from the bottom edge and fade out (8 recycled)
    local fl = sNew("Frame", { Name = "CW_Season", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Z + 3 }, main)
    D.parts[#D.parts + 1] = fl
    local floaters = {}
    for i = 1, 6 do
        local h, parts = drawHeart(fl, math.random(7, 11), (i % 2 == 0) and PINK or ROSE, 0.4, Z + 3)
        floaters[i] = { h = h, parts = parts, x = math.random(), y = 1 + math.random() * 0.3, v = 0.05 + math.random() * 0.04, ph = math.random() * 6 }
    end

    local t, sizeCheck = 0, 0
    return function(dt)
        t = t + dt
        sizeCheck = sizeCheck + dt
        if sizeCheck > 0.5 then sizeCheck = 0; if math.abs(winW() - builtW) > 6 then buildGarland() end end
        -- heartbeat: two quick beats then a rest
        local c = t % 1.4
        sealScale.Scale = 1 + 0.25 * (math.max(0, math.sin(c / 0.18 * math.pi)) * (c < 0.18 and 1 or 0) + math.max(0, math.sin((c - 0.26) / 0.18 * math.pi)) * ((c > 0.26 and c < 0.44) and 1 or 0))
        -- garland sways a little
        for _, H in ipairs(hearts) do
            H.h.Rotation = math.sin(t * 1.6 + H.i * 0.9) * 10
        end
        -- floaters rise from the bottom and fade over the lower third
        for _, p in ipairs(floaters) do
            p.y = p.y - p.v * dt
            if p.y < 0.62 then p.y = 1.02 + math.random() * 0.25; p.x = 0.05 + math.random() * 0.9 end
            local a = math.clamp((p.y - 0.62) / 0.3, 0, 1)   -- 1 at the bottom, 0 when it has risen a third of the way
            local tr = 1 - 0.6 * a * math.clamp((1.02 - p.y) / 0.06, 0, 1)
            for _, q in ipairs(p.parts) do q.BackgroundTransparency = tr end
            p.h.Position = UDim2.fromScale(p.x + math.sin(t * 1.2 + p.ph) * 0.01, p.y)
            p.h.Rotation = math.sin(t * 1.5 + p.ph) * 12
        end
    end
end

-- ---------- Easter ----------
local EGG_COLS = { { Color3.fromRGB(150, 200, 255), Color3.fromRGB(255, 255, 255) }, { Color3.fromRGB(255, 180, 210), Color3.fromRGB(255, 230, 120) },
    { Color3.fromRGB(190, 160, 255), Color3.fromRGB(255, 255, 255) }, { Color3.fromRGB(255, 220, 110), Color3.fromRGB(110, 200, 140) } }

local function drawEgg(parent, col, stripe, rot, z)
    local e = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(13, 16), Rotation = rot or 0, BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = z }, parent)
    sNew("UICorner", { CornerRadius = UDim.new(0.5, 0) }, e)
    sNew("Frame", { Position = UDim2.fromScale(0, 0.45), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = stripe, BorderSizePixel = 0, ZIndex = z }, e)
    for _, x in ipairs({ 0.3, 0.7 }) do sDot(e, 0, 0, 2, stripe, 0, z).Position = UDim2.fromScale(x, 0.25) end
    return e
end

-- bunny head with long ears (one floppy), drawn so y=0 is the chin; peeks up from behind an edge
local function drawBunny(parent, z)
    local FUR, IN = Color3.fromRGB(240, 236, 230), Color3.fromRGB(255, 186, 200)
    local root = sNew("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = z }, parent)
    local ears = {}
    for side = -1, 1, 2 do
        local ear = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(side * 4, -14), Size = UDim2.fromOffset(7, 18), Rotation = side * 10, BackgroundColor3 = FUR, BorderSizePixel = 0, ZIndex = z }, root)
        sNew("UICorner", { CornerRadius = UDim.new(1, 0) }, ear)
        local inner = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(0, 3, 1, -5), BackgroundColor3 = IN, BorderSizePixel = 0, ZIndex = z }, ear)
        sNew("UICorner", { CornerRadius = UDim.new(1, 0) }, inner)
        ears[side] = ear
    end
    local head = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(20, 17), BackgroundColor3 = FUR, BorderSizePixel = 0, ZIndex = z + 1 }, root)
    sNew("UICorner", { CornerRadius = UDim.new(0.5, 0) }, head)
    local eyes = { sDot(root, -4, -9, 2.6, INK, 0, z + 2), sDot(root, 4, -9, 2.6, INK, 0, z + 2) }
    sDot(root, 0, -5.5, 2.6, IN, 0, z + 2)                                   -- nose
    sDot(root, -6.5, -5, 3.5, IN, 0.5, z + 2); sDot(root, 6.5, -5, 3.5, IN, 0.5, z + 2)   -- cheeks
    return root, ears, eyes
end

-- butterfly: two wing pairs that flap by squashing horizontally
local function drawButterfly(parent, z)
    local root = sNew("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = z }, parent)
    local wings = {}
    for side = -1, 1, 2 do
        local w = sNew("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = z }, root)
        local up = sDot(w, side * 4, -2.5, 8, Color3.fromRGB(255, 170, 60), 0, z); up.Size = UDim2.fromOffset(8, 7)
        local lo = sDot(w, side * 3, 3, 6, Color3.fromRGB(255, 120, 150), 0, z); lo.Size = UDim2.fromOffset(6, 5)
        sDot(w, side * 4.5, -3, 2.5, Color3.new(1, 1, 1), 0.2, z + 1)
        wings[side] = { w = w, parts = { { up, side * 4, -2.5, 8, 7 }, { lo, side * 3, 3, 6, 5 } } }
    end
    sNew("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(2, 9), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = z + 2 }, root)
    return root, wings
end

local function buildEaster(main, D)
    local Z = 6
    -- grass growing along the top edge with eggs hidden in it (static, seeded so it never jumps)
    local turf = sNew("Frame", { Name = "CW_Season", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), ZIndex = Z }, main)
    D.parts[#D.parts + 1] = turf
    local rnd = Random.new(11)
    local G = { Color3.fromRGB(86, 170, 80), Color3.fromRGB(110, 196, 96), Color3.fromRGB(70, 146, 70) }
    local blades = {}
    for i = 0, 72 do
        local holder = sNew("Frame", { BackgroundTransparency = 1, Position = UDim2.new(i / 72, rnd:NextInteger(-2, 2), 0, 2), Size = UDim2.fromOffset(0, 0), ZIndex = Z }, turf)
        local h = rnd:NextInteger(7, 14)
        local lean = rnd:NextNumber(-22, 22)
        local b = sNew("Frame", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(3, h), Rotation = lean, BackgroundColor3 = G[rnd:NextInteger(1, 3)], BorderSizePixel = 0, ZIndex = Z }, holder)
        sNew("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
        if i % 4 == 0 then blades[#blades + 1] = { b = b, r = lean, i = i } end
    end
    for k, e in ipairs({ { 0.05, -12 }, { 0.085, 14 }, { 0.955, -8 } }) do   -- clear of the sale tab and the bunny
        local holder = sNew("Frame", { BackgroundTransparency = 1, Position = UDim2.new(e[1], 0, 0, 3), Size = UDim2.fromOffset(0, 0), ZIndex = Z + 1 }, turf)
        local c = EGG_COLS[k]
        drawEgg(holder, c[1], c[2], e[2], Z + 1)
    end

    -- bunny: pops up from behind the top edge (clipped slot), wiggles its ears, blinks, drops back down
    local slot = sNew("Frame", { Name = "CW_Season", BackgroundTransparency = 1, ClipsDescendants = true, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.88, 0, 0, 0), Size = UDim2.fromOffset(40, 44), ZIndex = Z - 1 }, main)
    local bRoot, ears, eyes = drawBunny(slot, Z - 1)
    local bHit = Instance.new("Frame"); bHit.BackgroundTransparency = 1; bHit.Size = UDim2.fromScale(1, 1); bHit.ZIndex = Z + 3; bHit.Parent = slot
    D.parts[#D.parts + 1] = slot
    local by, bWant, bTimer, bNext = 80, 80, 0, 5 + math.random() * 5
    D.conns[#D.conns + 1] = bHit.MouseEnter:Connect(function() if bTimer > 0 then bTimer = 0; bNext = 20 + math.random() * 15 end end)

    -- one butterfly wanders around the window's upper half now and then
    local bf
    local nextBf = 8 + math.random() * 8
    local function spawnBf()
        local holder = sPin(main, 0, -20, 0.2, 0, Z + 4)
        local root, wings = drawButterfly(holder, Z + 4)
        sNew("UIScale", { Scale = 1.35 }, root)
        bf = { holder = holder, wings = wings, t = 0, dur = 7 + math.random() * 3, dir = math.random() < 0.5 and 1 or -1, y = 0.08 + math.random() * 0.3, ph = math.random() * 6 }
    end

    local t = 0
    return function(dt)
        t = t + dt
        -- grass: every third blade sways in a slow breeze
        for _, B in ipairs(blades) do B.b.Rotation = B.r + math.sin(t * 1.3 + B.i * 0.4) * 6 end
        -- bunny
        if bTimer > 0 then
            bTimer = bTimer - dt
            bWant = 37   -- face clears the grass
            if bTimer <= 0 then bNext = 22 + math.random() * 20 end
        else
            bWant = 80
            bNext = bNext - dt
            if bNext <= 0 then bTimer = 5 end
        end
        by = by + (bWant - by) * math.min(1, dt * (bWant < 60 and 3 or 6))
        bRoot.Position = UDim2.fromOffset(20, by)
        ears[-1].Rotation = -10 + math.max(0, math.sin(t * 5)) * 8 * ((t % 2.4) < 0.8 and 1 or 0)
        ears[1].Rotation = 24 + math.sin(t * 1.4) * 4   -- the floppy one
        local blink = (t % 2.7) < 0.12
        for _, e in ipairs(eyes) do e.Size = UDim2.fromOffset(2.6, blink and 0.8 or 2.6) end
        -- butterfly
        if not bf then
            nextBf = nextBf - dt
            if nextBf <= 0 then spawnBf() end
        else
            bf.t = bf.t + dt
            local p = bf.t / bf.dur
            local x = bf.dir > 0 and p or (1 - p)
            bf.holder.Position = UDim2.new(x * 1.1 - 0.05, 0, bf.y + math.sin(bf.t * 1.7 + bf.ph) * 0.08, math.sin(bf.t * 5) * 3)
            local k = 0.25 + 0.75 * math.abs(math.sin(bf.t * 14))
            for _, side in ipairs({ -1, 1 }) do
                for _, w in ipairs(bf.wings[side].parts) do w[1].Size = UDim2.fromOffset(w[4] * k, w[5]); w[1].Position = UDim2.fromOffset(w[2] * k, w[3]) end
            end
            if p >= 1 then bf.holder:Destroy(); bf = nil; nextBf = 18 + math.random() * 15 end
        end
    end
end

local SEASON_BUILDERS = { halloween = buildHalloween, christmas = buildChristmas, valentine = buildValentine, easter = buildEaster }

-- addSeasonal(Library) -> ctl { set(on), destroy() }   (persisted on/off = M.FX.season)
function M.addSeasonal(Library, forceKey)
    local key = forceKey or M.seasonNow()
    local build = key and SEASON_BUILDERS[key]
    if not build then return nil end
    local main = Library.ScreenGui and Library.ScreenGui:FindFirstChild("Main")
    if not main then return nil end
    local RunService = game:GetService("RunService")
    local UIS = game:GetService("UserInputService")
    local D = { parts = {}, conns = {} }
    local ctl = { key = key, on = false }
    local step, conn
    local function clear()
        if conn then conn:Disconnect(); conn = nil end
        for _, c in ipairs(D.conns) do pcall(function() c:Disconnect() end) end
        for _, p in ipairs(D.parts) do pcall(function() p:Destroy() end) end
        for _, c in ipairs(main:GetChildren()) do if c.Name == "CW_Season" then pcall(function() c:Destroy() end) end end
        D.parts, D.conns = {}, {}
    end
    function ctl.set(on)
        ctl.on = on and true or false
        clear()
        if not ctl.on then return end
        step = build(main, D)
        -- phones: 30 fps is plenty for a bobbing spider; desktops every frame
        local cap = (UIS.TouchEnabled and not UIS.MouseEnabled) and (1 / 30) or 0
        local acc = 0
        conn = RunService.RenderStepped:Connect(function(dt)
            if not main.Visible then return end
            acc = acc + dt
            if acc < cap then return end
            local d = acc; acc = 0
            pcall(step, math.min(d, 0.1))
        end)
    end
    function ctl.destroy() ctl.on = false; clear() end
    pcall(function() Library:OnUnload(ctl.destroy) end)
    ctl.set(M.FX.season ~= false)
    return ctl
end

-- ---------- sale / announcement tab ----------
-- A small tab standing on the window's top edge: "TITLE · detail · 5h 12m". Tap = copy the link.
-- cfg = { title = "WEEKEND BLOWOUT", text = "40% off keys", url = "https://keys.combowick.com", ends = unix }
-- (ends optional: no countdown; tab removes itself when it passes). Returns { destroy }.
local function fmtLeft(s)
    s = math.max(0, math.floor(s))
    local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %02dm", h, m) end
    return string.format("%dm %02ds", m, s % 60)
end
function M.addBanner(Library, cfg)
    if type(cfg) ~= "table" or type(cfg.title) ~= "string" then return nil end
    if cfg.ends and os.time() >= cfg.ends then return nil end
    local main = Library.ScreenGui and Library.ScreenGui:FindFirstChild("Main")
    if not main then return nil end
    local old = main:FindFirstChild("CW_Banner"); if old then old:Destroy() end
    local TS = game:GetService("TweenService")
    local function accent() return (Library.Scheme and typeof(Library.Scheme.AccentColor) == "Color3") and Library.Scheme.AccentColor or Color3.fromRGB(240, 185, 40) end
    local gold = accent()
    local font = (Library.Scheme and typeof(Library.Scheme.Font) == "Font") and Library.Scheme.Font or Font.fromEnum(Enum.Font.Code)
    local BG = Color3.fromRGB(15, 15, 15)
    local tab = Instance.new("TextButton")
    tab.Name = "CW_Banner"; tab.AutoButtonColor = false; tab.Text = ""; tab.BackgroundColor3 = BG; tab.BorderSizePixel = 0
    tab.AnchorPoint = Vector2.new(0.5, 1); tab.Position = UDim2.new(0.5, 0, 0, 1); tab.Size = UDim2.fromOffset(200, 22); tab.ZIndex = 8
    Instance.new("UICorner", tab).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke"); stroke.Color = gold; stroke.Thickness = 1; stroke.Transparency = 0.15; stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; stroke.Parent = tab
    -- squares off the bottom corners so it reads as a tab growing out of the window, not a floating pill
    local foot = Instance.new("Frame"); foot.BorderSizePixel = 0; foot.BackgroundColor3 = BG; foot.AnchorPoint = Vector2.new(0, 1)
    foot.Position = UDim2.new(0, 0, 1, 0); foot.Size = UDim2.new(1, 0, 0, 7); foot.ZIndex = 8; foot.Parent = tab
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1; lbl.RichText = true; lbl.FontFace = font; lbl.TextSize = 13; lbl.TextColor3 = Color3.new(1, 1, 1)
    lbl.Size = UDim2.new(1, 0, 1, 0); lbl.Position = UDim2.fromOffset(0, 1); lbl.ZIndex = 9; lbl.Parent = tab
    local shine = Instance.new("UIGradient")
    shine.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.45, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 246, 210)), ColorSequenceKeypoint.new(0.55, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)) })
    shine.Offset = Vector2.new(-1, 0); shine.Parent = lbl
    local function toHex(c) return string.format("#%02x%02x%02x", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255)) end
    local hex = toHex(gold)
    local function esc(s) return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
    local alive = true
    local function render()
        local parts = { '<font color="' .. hex .. '"><b>' .. esc(cfg.title) .. '</b></font>' }
        if cfg.text then parts[#parts + 1] = esc(cfg.text) end
        if cfg.ends then parts[#parts + 1] = '<font color="#9ca3af">' .. fmtLeft(cfg.ends - os.time()) .. '</font>' end
        lbl.Text = table.concat(parts, '<font color="#6b7280">  ·  </font>')
        tab.Size = UDim2.fromOffset(math.max(120, lbl.TextBounds.X + 22), 22)
    end
    render()
    tab.MouseEnter:Connect(function() TS:Create(stroke, TweenInfo.new(0.15), { Transparency = 0, Thickness = 1.6 }):Play() end)
    tab.MouseLeave:Connect(function() TS:Create(stroke, TweenInfo.new(0.2), { Transparency = 0.15, Thickness = 1 }):Play() end)
    tab.MouseButton1Click:Connect(function()
        local url = M.withCreator and M.withCreator(cfg.url or "https://keys.combowick.com") or (cfg.url or "https://keys.combowick.com")
        local ok = pcall(function() (setclipboard or toclipboard)(url) end)
        local copied = "Link copied"
        pcall(function() copied = uiText()("banner_copied") end)   -- module language (plain English in the harness)
        if M.toast then M.toast(ok and (copied .. ": " .. url) or url, 3) end
        if M.playSound then pcall(M.playSound, "click") end
    end)
    tab.Parent = main
    -- follow the hub accent (gold, or a Premium theme); hooks fire again once the gold theme has applied
    if M.registerTheme then M.registerTheme(tab, function() gold = accent(); hex = toHex(gold); stroke.Color = gold; render() end) end
    task.spawn(function()
        local n = 0
        while alive and tab.Parent do
            task.wait(1); n = n + 1
            if cfg.ends and os.time() >= cfg.ends then break end
            if main.Visible then
                render()
                -- a light sweep across the text every 5 s, so it gets noticed without blinking at you
                if n % 5 == 0 then shine.Offset = Vector2.new(-1, 0); TS:Create(shine, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { Offset = Vector2.new(1, 0) }):Play() end
            end
        end
        if tab.Parent then tab:Destroy() end
    end)
    local ctl = { destroy = function() alive = false; pcall(function() tab:Destroy() end) end }
    pcall(function() Library:OnUnload(ctl.destroy) end)
    return ctl
end

-- ---------- server announcement (announce.json next to the loader) ----------
-- { "season": "halloween" | "off" | null, "banner": { "title": "...", "text": "...", "url": "...", "ends": unix } }
-- Fetched once per session in the background; nothing waits on it and a missing file just means no banner.
M.ANNOUNCE_URL = "https://raw.githubusercontent.com/checkurasshole/combowick-loader/main/announce.json"
function M.applyAnnouncement(Library, getSeason, setSeason)
    task.spawn(function()
        local ann = rawget(_G, "__CW_ANNOUNCE_TEST")
        if type(ann) ~= "table" then
            ann = rawget(_G, "__CW_ANN")
            if ann == nil then
                local ok, body = pcall(function() return game:HttpGet(M.ANNOUNCE_URL .. "?t=" .. math.floor(os.time() / 300)) end)
                local ok2, v = false, nil
                if ok and type(body) == "string" and body:sub(1, 1) == "{" then ok2, v = pcall(function() return game:GetService("HttpService"):JSONDecode(body) end) end
                ann = (ok2 and type(v) == "table") and v or false
                _G.__CW_ANN = ann
            end
        end
        if type(ann) ~= "table" then return end
        if type(ann.season) == "string" and ann.season ~= M.SEASON_OVERRIDE then
            M.SEASON_OVERRIDE = ann.season
            local cur = getSeason and getSeason()
            if not (cur and cur.key == M.seasonNow()) then
                if cur then pcall(cur.destroy) end
                local c = M.addSeasonal(Library)
                if setSeason then setSeason(c) end
            end
        end
        if type(ann.banner) == "table" then M.addBanner(Library, ann.banner) end
    end)
end


-- ===================== TIME-LEFT UPSELL =====================
-- Free sessions: a small gold card at 30 / 10 / 2 minutes left (live countdown, the running sale if
-- there is one, "Get a key" copies the store link). The "session ended" popup uses the same card.
-- English only until it goes live (then translate with the rest of UI_TEXT).
M.PREMIUM_URL = "https://keys.combowick.com/premium-keys"   -- (M.KEY_URL is the FREE key link, used by the loader)
M.UPSELL_AT = { 1800, 600, 120 }
M.UPSELL_TEXT = {
    ends_in = "Free session ends in %s", ended = "Free session ended",
    pitch = "A key means no timer, no cooldowns, and every game.",
    ended_pitch = "Get a key to keep playing with no timer, or come back when your cooldown is over.",
    get = "Get a key", later = "Later", ok = "OK", copied = "Store link copied. Paste it in your browser.",
}
-- ===================== CREATOR CODE =====================
-- A creator's code makes every "Get a key" link in the hub open the store with ?code=XXX: the buyer gets
-- 10% off and the creator gets credit. Set by the player (Creator Code box) or by a creator's loadstring:
--   getgenv().cw_creator = "ZEN"  loadstring(game:HttpGet(".../IQ"))()
-- Saved to a file so it still counts when they buy days later. Checked against the store before saving.
M.CREATOR_FILE = "combowick_creator.txt"
local CODE_RPC = "https://sqahviibykrzlwnulgmw.supabase.co/rest/v1/rpc/check_creator_code"
local STORE_ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNxYWh2aWlieWtyemx3bnVsZ213Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgyODAxNjQsImV4cCI6MjEwMzg1NjE2NH0.mvRGR-d3EOcy8bBlCTDwIHEF4ELIU9PfVXDi8NSALlA"   -- public anon key of the store (same one the website uses)
local creatorCache
local function creatorRequest(code)
    local req = (syn and syn.request) or (http and http.request) or http_request or request
    if not req then return nil end
    local ok, res = pcall(req, {
        Url = CODE_RPC, Method = "POST",
        Headers = { ["Content-Type"] = "application/json", apikey = STORE_ANON, Authorization = "Bearer " .. STORE_ANON },
        Body = game:GetService("HttpService"):JSONEncode({ p_code = code }),
    })
    if not ok or type(res) ~= "table" then return nil end
    local ok2, data = pcall(function() return game:GetService("HttpService"):JSONDecode(res.Body or res.body or "") end)
    if ok2 and type(data) == "table" and data.valid then return data end
    if ok2 and type(data) == "table" and data.valid == false then return false end
    return nil
end
local function cleanCode(c) c = tostring(c or ""):upper():gsub("[^A-Z0-9_-]", "") return (#c >= 3 and #c <= 20) and c or nil end
function M.creatorCode()
    if creatorCache == nil then
        creatorCache = false
        pcall(function() if isfile and isfile(M.CREATOR_FILE) then creatorCache = cleanCode(readfile(M.CREATOR_FILE)) or false end end)
    end
    return creatorCache or nil
end
-- returns code, discount_pct on success; nil, reason on failure ("invalid" / "offline")
function M.setCreatorCode(code)
    local c = cleanCode(code)
    if not c then return nil, "invalid" end
    local r = creatorRequest(c)
    if r == nil then return nil, "offline" end
    if r == false then return nil, "invalid" end
    creatorCache = r.code
    pcall(function() if writefile then writefile(M.CREATOR_FILE, r.code) end end)
    return r.code, tonumber(r.discount_pct) or 10
end
function M.clearCreatorCode()
    creatorCache = false
    pcall(function() if delfile and isfile and isfile(M.CREATOR_FILE) then delfile(M.CREATOR_FILE) end end)
end
-- store link with the creator code on it (the website remembers ?code= and applies it at checkout)
function M.withCreator(url)
    local c = M.creatorCode()
    if not c or type(url) ~= "string" then return url end
    return url .. (url:find("?", 1, true) and "&" or "?") .. "code=" .. c
end
-- a creator's loadstring sets getgenv().cw_creator: adopt it once (newest creator wins), in the background
task.spawn(function()
    local tag
    pcall(function() tag = getgenv and getgenv().cw_creator end)
    tag = cleanCode(tag)
    if tag and tag ~= M.creatorCode() then pcall(M.setCreatorCode, tag) end
end)

local function upGold()
    local ok, c = pcall(function() return PAL.accent end)   -- live theme colour inside the module; plain gold in the harness
    return (ok and typeof(c) == "Color3") and c or Color3.fromRGB(240, 185, 40)
end
local function upSale()
    local ann = rawget(_G, "__CW_ANNOUNCE_TEST") or rawget(_G, "__CW_ANN")
    local b = type(ann) == "table" and ann.banner
    if type(b) ~= "table" or type(b.title) ~= "string" then return nil end
    if b.ends and os.time() >= b.ends then return nil end
    return b
end
local function upLeft(s)
    s = math.max(0, math.floor(s))
    local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
    if d > 0 then return d .. "d " .. h .. "h" end
    if h > 0 then return h .. "h " .. m .. "m" end
    return m .. "m"
end
local function mmss(s) s = math.max(0, math.floor(s)); return string.format("%d:%02d", math.floor(s / 60), s % 60) end

-- card(opts) -> close(). opts: { title(fn->string, re-run each second), body, primary, secondary, life, onClose, slideFrom }
local function upCard(opts)
    local TS = game:GetService("TweenService")
    local par = game:GetService("CoreGui")
    pcall(function() if gethui then local h = gethui(); if h then par = h end end end)
    local old = par:FindFirstChild("CW_Upsell"); if old then pcall(function() old:Destroy() end) end
    local sg = Instance.new("ScreenGui")
    sg.Name = "CW_Upsell"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true; sg.DisplayOrder = 10000   -- above the hub window (Obsidian sits very high); sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local gold = upGold()
    local W = 300
    local card = Instance.new("Frame")
    card.AnchorPoint = Vector2.new(1, 0); card.Position = UDim2.new(1, W + 20, 0, 70); card.Size = UDim2.fromOffset(W, 0); card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = Color3.fromRGB(15, 15, 15); card.BorderSizePixel = 0; card.Parent = sg
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
    local st = Instance.new("UIStroke"); st.Color = gold; st.Thickness = 1.5; st.Transparency = 0.1; st.Parent = card
    local pad = Instance.new("UIPadding"); pad.PaddingTop = UDim.new(0, 12); pad.PaddingBottom = UDim.new(0, 12); pad.PaddingLeft = UDim.new(0, 16); pad.PaddingRight = UDim.new(0, 12); pad.Parent = card
    local list = Instance.new("UIListLayout"); list.Padding = UDim.new(0, 6); list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = card
    local function label(text, size, col, bold, order)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1; l.RichText = true; l.TextWrapped = true; l.TextXAlignment = Enum.TextXAlignment.Left
        l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham; l.TextSize = size; l.TextColor3 = col
        l.Size = UDim2.new(1, 0, 0, 0); l.AutomaticSize = Enum.AutomaticSize.Y; l.Text = text; l.LayoutOrder = order; l.Parent = card
        return l
    end
    local hex = string.format("#%02x%02x%02x", math.floor(gold.R * 255), math.floor(gold.G * 255), math.floor(gold.B * 255))
    local title = label(opts.title(hex), 15, Color3.new(1, 1, 1), true, 1)
    label(opts.body, 12, Color3.fromRGB(170, 170, 178), false, 2)
    local sale = upSale()
    local saleLbl
    if sale then
        saleLbl = label("", 12, Color3.new(1, 1, 1), true, 3)
        local function saleText()
            local s = '<font color="' .. hex .. '">' .. sale.title .. '</font>' .. (sale.text and ("  ·  " .. sale.text) or "")
            if sale.ends then s = s .. '<font color="#9ca3af">  ·  ends in ' .. upLeft(sale.ends - os.time()) .. '</font>' end
            return s
        end
        saleLbl.Text = saleText()
        opts.saleText = saleText
    end
    -- buttons row
    local row = Instance.new("Frame"); row.BackgroundTransparency = 1; row.Size = UDim2.new(1, 0, 0, 30); row.LayoutOrder = 4; row.Parent = card
    local rl = Instance.new("UIListLayout"); rl.FillDirection = Enum.FillDirection.Horizontal; rl.Padding = UDim.new(0, 8); rl.Parent = row
    local closed = false
    local function close()
        if closed then return end; closed = true
        pcall(function() TS:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = UDim2.new(1, W + 20, 0, 70) }):Play() end)
        task.delay(0.35, function() pcall(function() sg:Destroy() end) end)
        if opts.onClose then pcall(opts.onClose) end
    end
    local function button(text, primary, fn)
        local b = Instance.new("TextButton")
        b.AutoButtonColor = false; b.Text = text; b.Font = Enum.Font.GothamBold; b.TextSize = 13
        b.Size = UDim2.new(primary and 0.62 or 0.38, -4, 1, 0)
        b.BackgroundColor3 = primary and gold or Color3.fromRGB(28, 28, 28); b.TextColor3 = primary and Color3.fromRGB(20, 16, 6) or Color3.fromRGB(200, 200, 205)
        b.Parent = row
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        if not primary then local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(55, 55, 60); s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = b end
        b.MouseEnter:Connect(function() TS:Create(b, TweenInfo.new(0.12), { BackgroundTransparency = 0.12 }):Play() end)
        b.MouseLeave:Connect(function() TS:Create(b, TweenInfo.new(0.15), { BackgroundTransparency = 0 }):Play() end)
        b.MouseButton1Click:Connect(function() if M.playSound then pcall(M.playSound, "click") end; pcall(fn) end)
        return b
    end
    button(M.UPSELL_TEXT.get, true, function()
        pcall(function() (setclipboard or toclipboard)(M.withCreator(M.PREMIUM_URL)) end)
        if M.toast then M.toast(M.UPSELL_TEXT.copied, 3.5) end
        close()
    end)
    button(opts.secondary or M.UPSELL_TEXT.later, false, close)
    -- thin bar at the bottom that runs down while the card stays up
    local bar = Instance.new("Frame"); bar.BackgroundColor3 = gold; bar.BackgroundTransparency = 0.4; bar.BorderSizePixel = 0
    bar.Size = UDim2.new(1, 0, 0, 2); bar.LayoutOrder = 5; bar.Parent = card
    sg.Parent = par
    TS:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.new(1, -16, 0, 70) }):Play()
    if M.playSound then pcall(M.playSound, "open") end
    local life = opts.life or 15
    TS:Create(bar, TweenInfo.new(life, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) }):Play()
    task.spawn(function()
        local t0 = os.clock()
        while not closed and os.clock() - t0 < life do
            task.wait(1)
            pcall(function() title.Text = opts.title(hex) end)
            if saleLbl then pcall(function() saleLbl.Text = opts.saleText() end) end
        end
        close()
    end)
    return close
end

-- shown at each threshold of a free session (called every second by the session loop)
function M.showUpsell(left)
    return upCard({
        title = function(hex) return string.format(M.UPSELL_TEXT.ends_in, '<font color="' .. hex .. '">' .. mmss(rawget(_G, "__CW_FX_SESSION_LEFT") or left) .. "</font>") end,
        body = M.UPSELL_TEXT.pitch, life = 15,
    })
end
local upsellStart, upsellDone, upsellLast
function M.onSessionTick(left)
    -- the timer jumping UP means a new session started: re-arm every warning
    if not upsellLast or left > upsellLast then upsellStart = left; upsellDone = {} end
    upsellLast = left
    for _, at in ipairs(M.UPSELL_AT) do
        -- only thresholds the session actually passes through (a 5-minute session gets just the 2-minute one)
        if not upsellDone[at] and left <= at and upsellStart > at + 30 then upsellDone[at] = true; pcall(M.showUpsell, left); break end
    end
end

-- the end-of-session popup, now the same gold card (replaces the old purple one)
function M.showExpiredPopup(onDone)
    local done = false
    local function finish() if done then return end; done = true; if onDone then pcall(onDone) end end
    local ok = pcall(function()
        upCard({
            title = function() return M.EXPIRED_TITLE or M.UPSELL_TEXT.ended end,
            body = M.EXPIRED_SUB or M.UPSELL_TEXT.ended_pitch,
            secondary = M.UPSELL_TEXT.ok, life = 20, onClose = finish,
        })
    end)
    if not ok then finish() end
end

-- "Custom Scripts" box for the Info tab: most players don't know we build scripts for their own game.
M.CUSTOM_TEXT = {
    title = "Custom Scripts",
    pitch = "Want a script made for <b>your</b> game? Custom scripts from <b>$20</b>, built before any free request.",
    button = "Get a price on Discord", copied = "Discord link copied. Join and open a ticket.",
}
function M.addCustomBox(Tab, Library)
    local box = Tab:AddRightGroupbox(M.CUSTOM_TEXT.title, "hammer")
    local gold = upGold()
    local hex = string.format("#%02x%02x%02x", math.floor(gold.R * 255), math.floor(gold.G * 255), math.floor(gold.B * 255))
    box:AddLabel((M.CUSTOM_TEXT.pitch:gsub("<b>", '<font color="' .. hex .. '"><b>'):gsub("</b>", "</b></font>")), true)
    box:AddButton({ Text = M.CUSTOM_TEXT.button, Func = function()
        pcall(function() (setclipboard or toclipboard)(M.DISCORD_INVITE) end)
        if M.toast then M.toast(M.CUSTOM_TEXT.copied, 3.5) end
    end })
    pcall(M.addCreatorBox, Tab, Library)
    return box
end

-- "Creator Code" box: enter a YouTuber's code once -> every key link in the hub carries it (10% off)
M.CREATOR_TEXT = {
    title = "Creator Code",
    none = "Got a code from a YouTuber? Enter it for <b>10% off</b> your key.",
    on = "Code <b>%s</b> is on: <b>%d%% off</b> when you get a key.",
    placeholder = "Creator code", save = "Save code", saved = "Creator code %s saved: %d%% off your key.",
    removed = "Creator code removed.", invalid = "That code doesn't exist.", offline = "Couldn't check the code. Try again.",
    get = "Get a key with this code", copied = "Store link copied. Paste it in your browser.",
}
function M.addCreatorBox(Tab, Library)
    local T = M.CREATOR_TEXT
    local box = Tab:AddRightGroupbox(T.title, "ticket")
    local gold = upGold()
    local hex = string.format("#%02x%02x%02x", math.floor(gold.R * 255), math.floor(gold.G * 255), math.floor(gold.B * 255))
    local function paint(s) return (s:gsub("<b>", '<font color="' .. hex .. '"><b>'):gsub("</b>", "</b></font>")) end
    local pct = 10
    local status = box:AddLabel("", true)
    local function refresh()
        local c = M.creatorCode()
        pcall(function() status:SetText(paint(c and string.format(T.on, c, pct) or T.none)) end)
    end
    refresh()
    local input = box:AddInput("CW_CreatorCode", { Text = "", Default = M.creatorCode() or "", Placeholder = T.placeholder, Finished = false, ClearTextOnFocus = false, Callback = function() end })
    box:AddButton({ Text = T.save, Func = function()
        local v = ""
        pcall(function() v = (Library.Options and Library.Options.CW_CreatorCode and Library.Options.CW_CreatorCode.Value) or (input and input.Value) or "" end)
        task.spawn(function()
            if v:gsub("%s", "") == "" then
                M.clearCreatorCode(); refresh()
                if M.toast then M.toast(T.removed, 2.5) end
                return
            end
            local code, res = M.setCreatorCode(v)
            if code then
                pct = res or 10; refresh()
                if M.toast then M.toast(string.format(T.saved, code, pct), 3) end
            elseif M.toast then
                M.toast(res == "offline" and T.offline or T.invalid, 3)
            end
        end)
    end })
    box:AddButton({ Text = T.get, Func = function()
        pcall(function() (setclipboard or toclipboard)(M.withCreator(M.PREMIUM_URL)) end)
        if M.toast then M.toast(T.copied, 3) end
    end })
    return box
end


function M.addGoldTheme(Library, SettingsTab)
    local tr = uiText()
    local Win = Library.Window or Library
    _G.__CW_GOLDDONE = _G.__CW_GOLDDONE or setmetatable({}, { __mode = "k" })
    if _G.__CW_GOLDDONE[Win] then return nil end
    _G.__CW_GOLDDONE[Win] = true
    local RunService, TweenService = game:GetService("RunService"), game:GetService("TweenService")
    local main = Library.ScreenGui and Library.ScreenGui:FindFirstChild("Main")
    if not main then return nil end
    -- all three gradients are rebuilt from the active palette (PAL) so the Theme picker can recolor live
    local function goldSeq() return ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, PAL.g1), ColorSequenceKeypoint.new(0.20, PAL.g2), ColorSequenceKeypoint.new(0.32, PAL.shine),
        ColorSequenceKeypoint.new(0.38, PAL.glint), ColorSequenceKeypoint.new(0.46, PAL.shine), ColorSequenceKeypoint.new(0.60, PAL.g2),
        ColorSequenceKeypoint.new(0.80, PAL.g1), ColorSequenceKeypoint.new(1.00, PAL.g1),
    }) end
    local function borderSeq() return ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, PAL.g2), ColorSequenceKeypoint.new(0.36, PAL.g2), ColorSequenceKeypoint.new(0.44, PAL.shine),
        ColorSequenceKeypoint.new(0.50, PAL.glint), ColorSequenceKeypoint.new(0.56, PAL.shine), ColorSequenceKeypoint.new(0.64, PAL.g2),
        ColorSequenceKeypoint.new(1.00, PAL.g2),
    }) end
    local function titleSeq() return ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, PAL.tgold), ColorSequenceKeypoint.new(0.30, PAL.tgold), ColorSequenceKeypoint.new(0.42, PAL.thot),
        ColorSequenceKeypoint.new(0.50, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.58, PAL.thot),
        ColorSequenceKeypoint.new(0.70, PAL.tgold), ColorSequenceKeypoint.new(1.00, PAL.tgold),
    }) end
    local stroke
    for _, s in ipairs(main:GetChildren()) do if s:IsA("UIStroke") and s.Thickness <= 1.01 then stroke = s break end end
    if not stroke then stroke = Instance.new("UIStroke"); stroke.Thickness = 1; stroke.Parent = main end
    local origStroke = { Color = stroke.Color, Thickness = stroke.Thickness, Transparency = stroke.Transparency }
    -- border: solid accent with a wide white-hot streak, so the rotation reads as light travelling
    -- around the edge (the old soft band looked static; a dark base made the 2px border look muddy)
    local borderGrad = Instance.new("UIGradient"); borderGrad.Color = borderSeq()
    local halo = Instance.new("Frame")
    halo.Name = "CW_GoldGlow"; halo.BackgroundTransparency = 1; halo.BorderSizePixel = 0
    halo.Size = UDim2.new(1, 10, 1, 10); halo.Position = UDim2.fromOffset(-5, -5); halo.ZIndex = 0
    local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, (Library.CornerRadius or 4) + 5); hc.Parent = halo
    local haloStroke = Instance.new("UIStroke"); haloStroke.Thickness = 5; haloStroke.Color = PAL.g2; haloStroke.Parent = halo
    local haloGrad = Instance.new("UIGradient"); haloGrad.Color = goldSeq(); haloGrad.Parent = haloStroke
    local title
    for _, d in ipairs(main:GetDescendants()) do if d:IsA("TextLabel") and d.TextSize >= 18 and d.Text ~= "" then title = d break end end
    if title and title.Text == "COMBOWICK" then
        title.Text = "COMBO_WICK" -- brand name, same as the game scripts
        -- "COMBO_WICK" is wider: shrink the font just enough to fit the title box
        task.spawn(function()
            for _ = 1, 3 do
                task.wait()
                local w, maxW = title.TextBounds.X, title.AbsoluteSize.X - 8
                if w > 0 and maxW > 0 then
                    if w <= maxW then break end
                    title.TextSize = math.max(12, math.floor(title.TextSize * maxW / w))
                end
            end
        end)
    end
    local origTitleColor = title and title.TextColor3
    local origTitleStroke = title and { c = title.TextStrokeColor3, tr = title.TextStrokeTransparency }
    -- title: bright accent with a wide white-hot shine sweeping across, plus a glow that flares as it passes
    local titleGrad = Instance.new("UIGradient")
    titleGrad.Color = titleSeq()
    -- gold accent + the loader's black palette (game scripts often ship their own navy/blue theme)
    local LOOK = {
        AccentColor = PAL.accent,
        BackgroundColor = Color3.fromRGB(15, 15, 15),
        MainColor = Color3.fromRGB(25, 25, 25),
        OutlineColor = Color3.fromRGB(40, 40, 40),
        FontColor = Color3.fromRGB(255, 255, 255),
    }
    local origScheme = {}
    if Library.Scheme then for k in pairs(LOOK) do origScheme[k] = Library.Scheme[k] end end
    local function applyScheme(on)
        if not Library.Scheme then return end
        for k, v in pairs(LOOK) do
            local want = on and v or origScheme[k]
            if want ~= nil then
                Library.Scheme[k] = want
                -- keep ThemeManager's "Themes" box swatches (Accent color etc.) showing the real colors
                pcall(function()
                    local opt = Library.Options and Library.Options[k]
                    if opt and opt.SetValueRGB and opt.Value ~= want then opt:SetValueRGB(want) end
                end)
            end
        end
        pcall(function() Library:UpdateColorsUsingRegistry() end)
    end
    local function setAccent(c) applyScheme(c ~= nil and c ~= origScheme.AccentColor) end
    local origAnims = {}
    local function setAnims(on)
        if type(Library.Animations) ~= "table" then return end
        for k, v in pairs(Library.Animations) do
            -- ToggleWindow stays off: Obsidian's window fade tweens EVERY element of every tab on each
            -- open/close (thousands of tweens in one frame = the CW-button lag on mobile). popIn/easeOut
            -- below already animate the open/close cheaply with one UIScale tween.
            if k == "ToggleWindow" then
                if on then if origAnims[k] == nil then origAnims[k] = v end; Library.Animations[k] = false
                elseif origAnims[k] ~= nil then Library.Animations[k] = origAnims[k] end
            elseif on then if origAnims[k] == nil then origAnims[k] = v end; Library.Animations[k] = true
            elseif origAnims[k] ~= nil then Library.Animations[k] = origAnims[k] end
        end
        -- crisper, direction-aware tab slide (Obsidian's built-in PlayTabAnimation reads these)
        if on then
            pcall(function()
                Library.TabSwipeFrom = "auto"       -- slide up/down depending on which tab you came from
                Library.TabSwipeOffset = 36
                Library.TabTransitionInfo = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
            end)
        end
    end
    local function scaleObj() local sc = main:FindFirstChildOfClass("UIScale") if not sc then sc = Instance.new("UIScale"); sc.Parent = main end return sc end
    local function popIn() local sc = scaleObj(); sc.Scale = 0.9; TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play() end
    local function easeOut() TweenService:Create(scaleObj(), TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.94 }):Play() end

    local ctl = { on = false, deg = 60 }
    local conn, rot, t, lastToggled = nil, 0, 0, Library.Toggled
    local holy
    local function stop()
        if conn then conn:Disconnect(); conn = nil end
        borderGrad.Parent = nil; halo.Parent = nil; titleGrad.Parent = nil
        stroke.Color, stroke.Thickness, stroke.Transparency = origStroke.Color, origStroke.Thickness, origStroke.Transparency
        if title and origTitleColor then title.TextColor3 = origTitleColor end
        if title and origTitleStroke then title.TextStrokeColor3 = origTitleStroke.c; title.TextStrokeTransparency = origTitleStroke.tr end
        if holy then pcall(holy.destroy); holy = nil end
        applyScheme(false); setAnims(false)
        local sc = main:FindFirstChildOfClass("UIScale") if sc then sc.Scale = 1 end
    end
    function ctl.set(on)
        ctl.on = on and true or false
        if not ctl.on then return stop() end
        stroke.Color, stroke.Thickness, stroke.Transparency = Color3.new(1, 1, 1), 2, 0
        borderGrad.Parent = stroke; halo.Parent = main
        if title then title.TextColor3 = Color3.new(1, 1, 1); titleGrad.Parent = title end
        if title and not holy then local ok, h = pcall(makeHoly, title, PAL.g2, PAL.warm) if ok then holy = h end end
        applyScheme(true); setAnims(true)
        -- applyScheme's registry refresh repaints the stroke with OutlineColor (dark grey), which
        -- multiplied the gold gradient down to near-invisible. Re-whiten it after (and every frame).
        stroke.Color, stroke.Thickness, stroke.Transparency = Color3.new(1, 1, 1), 2, 0
        lastToggled = Library.Toggled
        if not conn then
            local WHITE = Color3.new(1, 1, 1)
            -- phones: animate the gold at 30 fps (every change re-renders the window; half the work, looks the same)
            local UIS = game:GetService("UserInputService")
            local step = (UIS.TouchEnabled and not UIS.MouseEnabled) and (1 / 30) or 0
            local acc = 0
            conn = RunService.RenderStepped:Connect(function(dt)
                t = t + dt
                if Library.Toggled ~= lastToggled then lastToggled = Library.Toggled; if lastToggled then popIn(); M.playSound("open") else easeOut(); M.playSound("close") end end
                -- hub hidden: nothing below is visible, so don't spend frames on it (big win on phones)
                if not main.Visible then return end
                acc = acc + dt
                if acc < step then return end
                dt = acc; acc = 0
                rot = (rot + dt * ctl.deg) % 360
                borderGrad.Rotation = rot; haloGrad.Rotation = rot
                if stroke.Color ~= WHITE then stroke.Color = WHITE end
                haloStroke.Transparency = 0.72 + 0.16 * math.sin(t * 2.1)
                -- shine sweeps across the name in 1s, every 2.6s; the gold glow flares while it crosses
                local p = (t % 2.6) / 1.0
                local x = p <= 1 and (p * 2.4 - 1.2) or 1.2
                titleGrad.Offset = Vector2.new(x, 0)
                if holy then pcall(holy.step, dt, x, t) end
            end)
        end
    end
    pcall(function() Library:OnUnload(stop) end)
    -- recolor every gold-theme surface from the active palette when the Theme picker changes it
    local function rebuildTheme()
        borderGrad.Color = borderSeq(); haloGrad.Color = goldSeq(); haloStroke.Color = PAL.g2; titleGrad.Color = titleSeq()
        LOOK.AccentColor = PAL.accent
        if holy then pcall(holy.recolor, PAL.g2, PAL.warm) end
        if ctl.on then applyScheme(true); stroke.Color = Color3.new(1, 1, 1) end
    end
    M.registerTheme(main, rebuildTheme)
    local seasonCtl = M.addSeasonal and M.addSeasonal(Library)
    pcall(M.applyAnnouncement, Library, function() return seasonCtl end, function(c) seasonCtl = c end)
    if SettingsTab then
        pcall(function()
            local FX = SettingsTab:AddRightGroupbox(tr("effects"), "sparkles")
            FX:AddToggle("CW_GoldTheme", { Text = tr("gold"), Default = true, Callback = function(v) ctl.set(v) end })
            if seasonCtl then FX:AddToggle("CW_SeasonFX", { Text = tr("season"), Default = seasonCtl.on, Callback = function(v) M.FX.season = v; if seasonCtl then seasonCtl.set(v) end; fxSave() end }) end
            FX:AddSlider("CW_GoldSpeed", { Text = tr("shine"), Default = 60, Min = 15, Max = 240, Rounding = 0, Callback = function(v) ctl.deg = tonumber(v) or ctl.deg end })
            -- THEME PICKER (Premium perk): free sessions are locked to Gold; key users pick any.
            local themeVals = {}
            for _, p in ipairs(M.THEMES) do themeVals[#themeVals + 1] = p.premium and (p.label .. " ★") or p.label end
            local labelToKey = {}
            for i, p in ipairs(M.THEMES) do labelToKey[themeVals[i]] = p.key end
            local curLabel = themeVals[1]
            for i, p in ipairs(M.THEMES) do if p.key == PAL.key then curLabel = themeVals[i] end end
            local themeDd
            themeDd = FX:AddDropdown("CW_ThemePick", { Text = tr("theme"), Values = themeVals, Default = curLabel, Tooltip = tr("theme_locked"), Callback = function(v)
                local key = labelToKey[v] or "Gold"
                local p = themeByKey(key)
                if p.premium and _G.COMBOWICK_FREE then
                    -- locked for free users: bounce back to Gold and upsell
                    pcall(function() themeDd:SetValue(themeVals[1]) end)
                    if M.toast then M.toast(tr("theme_locked"), 4) end
                    return
                end
                M.applyTheme(key)
                if M.toast then M.toast(string.format(tr("theme_changed"), p.label), 2.5) end
            end })
            pcall(M.setupPremiumFX, Library, FX)
        end)
    else
        pcall(M.setupPremiumFX, Library, nil)
    end
    ctl.set(true)
    -- the gold theme applied its scheme directly (not via M.applyTheme), so fire the theme hooks once
    -- now to recolor anything that registered before the theme ran (e.g. Games cards on a cache hit)
    pcall(function() for _, fn in pairs(themeHooks) do pcall(fn) end end)
    pcall(M.decorateButtons, Library)   -- hover grow + gold glow + press bounce + click sound
    -- intro splash (once per session) then pop the window in; if it already played, pops in now
    M.playSplash(function() popIn() end)
    return ctl
end


end

return M
]======]
_G.__CW_ANNOUNCE_TEST = { banner = { title = "WEEKEND BLOWOUT", text = "40% off keys", url = "https://keys.combowick.com", ends = os.time() + 5 * 3600 + 12 * 60 } }
if _G.__SEASON_TEST and _G.__SEASON_TEST.banner then pcall(_G.__SEASON_TEST.banner.destroy) end

_G.__CW_SEASON = nil
-- TEST HARNESS (client only, never pushed): opens a COMBO_WICK-style Obsidian window in any place,
-- loads the hub-redesign module copy and applies the gold theme, so seasonal decor can be iterated.
local prev = _G.__SEASON_TEST
if prev then
    pcall(function() if prev.decor then prev.decor.destroy() end end)
    pcall(function() prev.Library:Unload() end)
    pcall(function() prev.Library.ScreenGui:Destroy() end)
end
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
_G.__OBS_SRC = _G.__OBS_SRC or game:HttpGet(repo .. "Library.lua")
local Library = loadstring(_G.__OBS_SRC)()
local Window = Library:CreateWindow({
    Title = "COMBOWICK", Footer = "Season test (not live)", NotifySide = "Right",
    ShowCustomCursor = false, AutoShow = true, Size = UDim2.fromOffset(560, 340),
})
local Tabs = {
    Main = Window:AddTab("Main", "user"),
    Key  = Window:AddTab("Premium Key", "key"),
    UI   = Window:AddTab("UI Settings", "settings"),
}
local g = Tabs.Main:AddLeftGroupbox("Free Session", "info")
g:AddLabel("Time left: 4h 12m", true)
g:AddButton({ Text = "Load Script", Func = function() end })
local g2 = Tabs.Main:AddRightGroupbox("Status", "activity")
g2:AddLabel("Game: Baseplate", true)
g2:AddToggle("T_Test", { Text = "Some toggle", Default = false })
pcall(function() Library.ScreenGui.Name = "CW_SeasonTest" end)
local M = loadstring(_G.__SEASON_SRC)()
M.FX.splash = false
_G.__SEASON_M = M
pcall(M.addGoldTheme, Library, Tabs.UI)
_G.__SEASON_TEST = { Library = Library, Window = Window, Tabs = Tabs, M = M }

pcall(function() _G.__SEASON_TEST.M.addCustomBox(_G.__SEASON_TEST.Tabs.Main, _G.__SEASON_TEST.Library) end)

-- demo: show the 10-minute warning card once, 4 seconds after opening
task.delay(4, function()
    local M = _G.__SEASON_TEST and _G.__SEASON_TEST.M
    if not M then return end
    _G.__CW_FX_SESSION_LEFT = 600
    task.spawn(function() for i = 600, 560, -1 do _G.__CW_FX_SESSION_LEFT = i; task.wait(1) end end)
    pcall(M.showUpsell, 600)
end)
