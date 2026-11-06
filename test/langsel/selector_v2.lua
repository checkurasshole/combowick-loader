-- COMBO_WICK Language Selector v2. Live copies: checkurasshole/combowick-loader/lang_selector.lua (IQ) and
-- checkurasshole/Script/langselector-module.lua (the game-script wrappers). Edit lang-selector-v2/selector_v2.lua.
-- Same API as v1 so IQ keeps working: LanguageSelector.new(), sel:Init(scripts) -> true if it handled loading,
-- sel:CreateGUI(), and sel.generateScriptsHash can still be overridden (IQ pins it).
-- In a game script (loaded after IQ already picked): no 2nd picker / 2nd countdown — the IQ language loads right
-- away, and if the game doesn't have it, English loads with a "not in this game · change" note (the saved
-- choice stays, so the key menu and other games keep the player's language).
-- Fixes vs v1: scrolling never picks (tap-only + select-then-continue), suggested language from the player's
-- Roblox locale, one saved choice for every game (old per-game saves migrate), "change" opens the picker BEFORE
-- anything loads, X continues instead of loading nothing, "remember" is respected.
-- Look: COMBO_WICK hub style (Code font, thin gold edge with a running gold streak, flag tiles).
-- Mobile: no blur, edge animated at 30 fps, fewer dust specks (tween-driven), flags cached on disk, all loops stop on close.

local LanguageSelector = {}
LanguageSelector.__index = LanguageSelector

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local SAVE_FILE = "COMBOWICK_Language.json" -- one choice for every game
local AUTOLOAD_SECONDS = 3
-- touch without a mouse = phone/tablet (some Android phones report a keyboard, so don't rely on KeyboardEnabled)
local MOBILE = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local FONT = Enum.Font.Code -- same as the COMBO_WICK hub (Obsidian)
local DISCORD_INVITE = "https://discord.gg/ufrz9Zaqs8"
local LOGO_URL = "https://cdn.discordapp.com/icons/934631259861319733/a_3c6b0ba4deedbc36b995e33a02d0948c.png?size=64"

local C = {
    bg = Color3.fromRGB(15, 15, 18),
    tile = Color3.fromRGB(22, 22, 26),
    tileOn = Color3.fromRGB(30, 27, 19),
    gold = Color3.fromRGB(245, 183, 0),
    goldSoft = Color3.fromRGB(245, 197, 66),
    goldHot = Color3.fromRGB(255, 205, 60),
    text = Color3.fromRGB(235, 235, 240),
    sub = Color3.fromRGB(140, 140, 155),
}

-- key in IQ's map -> { native name, english name }
local DISPLAY = {
    ["English"] = { "English", "English" },
    ["Spanish"] = { "Español", "Spanish" },
    ["Portuguese"] = { "Português", "Portuguese" },
    ["Indonesian"] = { "Indonesia", "Indonesian" },
    ["Filipino"] = { "Filipino", "Filipino" },
    ["Vietnamese"] = { "Tiếng Việt", "Vietnamese" },
    ["Thai"] = { "ไทย", "Thai" },
    ["Russian"] = { "Русский", "Russian" },
    ["German"] = { "Deutsch", "German" },
    ["French"] = { "Français", "French" },
    ["Korean"] = { "한국어", "Korean" },
    ["Chinese (Simplified)"] = { "简体中文", "Chinese" },
    ["Arabic (العربية)"] = { "العربية", "Arabic" },
}
-- most-used first (Arabic/Chinese are no longer the first tiles thumbs land on)
local ORDER = { "English", "Spanish", "Portuguese", "Indonesian", "Filipino", "Vietnamese", "Thai", "Russian", "German", "French", "Korean", "Chinese (Simplified)", "Arabic (العربية)" }
local LOCALE = {
    en = "English", es = "Spanish", pt = "Portuguese", id = "Indonesian", ms = "Indonesian", fil = "Filipino", tl = "Filipino",
    vi = "Vietnamese", th = "Thai", ru = "Russian", uk = "Russian", de = "German", fr = "French", ko = "Korean",
    zh = "Chinese (Simplified)", ar = "Arabic (العربية)",
}
local FLAG = {
    ["English"] = "us", ["Spanish"] = "es", ["Portuguese"] = "br", ["Indonesian"] = "id", ["Filipino"] = "ph",
    ["Vietnamese"] = "vn", ["Thai"] = "th", ["Russian"] = "ru", ["German"] = "de", ["French"] = "fr",
    ["Korean"] = "kr", ["Chinese (Simplified)"] = "cn", ["Arabic (العربية)"] = "sa",
}
-- the window's own words switch to the language you pick (players see right away that it works)
local UI = {
    ["English"] = { "language", "remember", "continue", "detected", "loading", "change" },
    ["Spanish"] = { "idioma", "recordar", "continuar", "detectado", "cargando", "cambiar" },
    ["Portuguese"] = { "idioma", "lembrar", "continuar", "detectado", "carregando", "mudar" },
    ["Indonesian"] = { "bahasa", "ingat", "lanjut", "terdeteksi", "memuat", "ganti" },
    ["Filipino"] = { "wika", "tandaan", "magpatuloy", "natukoy", "naglo-load", "palitan" },
    ["Vietnamese"] = { "ngôn ngữ", "ghi nhớ", "tiếp tục", "phát hiện", "đang tải", "đổi" },
    ["Thai"] = { "ภาษา", "จดจำ", "ต่อไป", "ตรวจพบ", "กำลังโหลด", "เปลี่ยน" },
    ["Russian"] = { "язык", "запомнить", "продолжить", "определён", "загрузка", "сменить" },
    ["German"] = { "sprache", "merken", "weiter", "erkannt", "lädt", "ändern" },
    ["French"] = { "langue", "retenir", "continuer", "détecté", "chargement", "changer" },
    ["Korean"] = { "언어", "기억하기", "계속", "감지됨", "로딩 중", "변경" },
    ["Chinese (Simplified)"] = { "语言", "记住", "继续", "检测到", "加载中", "更改" },
    ["Arabic (العربية)"] = { "اللغة", "تذكر", "متابعة", "تم الاكتشاف", "جارٍ التحميل", "تغيير" },
}
-- "<language> isn't in this game · using <fallback>" (shown in the player's own language)
local NOT_HERE = {
    ["English"] = "isn't in this game · using",
    ["Spanish"] = "no está en este juego · usando",
    ["Portuguese"] = "não tem neste jogo · usando",
    ["Indonesian"] = "tidak ada di game ini · memakai",
    ["Filipino"] = "wala sa larong ito · gamit ang",
    ["Vietnamese"] = "không có trong game này · dùng",
    ["Thai"] = "ไม่มีในเกมนี้ · ใช้",
    ["Russian"] = "нет в этой игре · используем",
    ["German"] = "gibt es in diesem Spiel nicht · nutze",
    ["French"] = "pas dispo dans ce jeu · on utilise",
    ["Korean"] = "이 게임에는 없어요 · 사용:",
    ["Chinese (Simplified)"] = "此游戏暂不支持 · 使用",
    ["Arabic (العربية)"] = "غير متوفرة في هذه اللعبة · نستخدم",
}
-- other spellings game wrappers use for the same language
local ALIAS = {
    ["Arabic"] = "Arabic (العربية)", ["العربية"] = "Arabic (العربية)",
    ["Chinese"] = "Chinese (Simplified)", ["Chinese Simplified"] = "Chinese (Simplified)",
    ["Tagalog"] = "Filipino", ["Bahasa Indonesia"] = "Indonesian",
}
local function ui(lang, i) return ((UI[lang] or UI["English"])[i]) end
local function native(lang) return (DISPLAY[lang] or { lang })[1] end

-- ---------- small helpers ----------
local function guiParent()
    local ok, h = pcall(function() return gethui and gethui() end)
    if ok and h then return h end
    local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and cg then return cg end
    return player:WaitForChild("PlayerGui")
end
local function canFile() return typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function" end
local function corner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 6); c.Parent = p; return c end
local function stroke(p, col, th, tr) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th or 1; s.Transparency = tr or 0; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = p; return s end
local function tween(o, t, props, style) local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quart, Enum.EasingDirection.Out), props); tw:Play(); return tw end
local function txt(p, s, size, col, xa)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1; l.Text = s; l.TextSize = size; l.TextColor3 = col or C.text
    l.Font = FONT; l.TextXAlignment = xa or Enum.TextXAlignment.Left; l.TextYAlignment = Enum.TextYAlignment.Center
    l.TextTruncate = Enum.TextTruncate.AtEnd; l.Parent = p
    return l
end
-- non-Latin scripts read better in Gotham than in the monospace hub font
local function fitFont(l) l.Font = tostring(l.Text):match("[\128-\255]") and Enum.Font.GothamMedium or FONT end

-- one shared click sound, reused across runs (no new Sound per execution)
local function click()
    pcall(function()
        local ss = game:GetService("SoundService")
        local s = ss:FindFirstChild("CW_LangClick")
        if not s then
            s = Instance.new("Sound"); s.Name = "CW_LangClick"; s.SoundId = "rbxasset://sounds/electronicpingshort.wav"; s.Volume = 0.25; s.Parent = ss
        end
        s:Play()
    end)
end

-- A real TAP: down and up on the same thing without moving (scrolling never counts).
local function onTap(btn, fn)
    local downPos, downAt
    btn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            downPos, downAt = Vector2.new(i.Position.X, i.Position.Y), os.clock()
        end
    end)
    btn.InputEnded:Connect(function(i)
        if not downPos then return end
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            local moved = (Vector2.new(i.Position.X, i.Position.Y) - downPos).Magnitude
            local held = os.clock() - downAt
            downPos = nil
            -- a cancelled touch (scroll/another GUI took it) never counts; slow taps from kids still do
            if i.UserInputState == Enum.UserInputState.End and moved <= 10 and held <= 1.5 then fn() end
        end
    end)
end

-- images (flags, logo): downloaded once to the executor workspace and shown with getcustomasset;
-- whatever is behind them (2-letter badge) stays visible if anything fails
-- one download at a time (13 parallel HttpGets can freeze executors where HttpGet blocks)
local imgQueue, imgBusy = {}, false
local function runQueue()
    if imgBusy then return end
    imgBusy = true
    task.spawn(function()
        while #imgQueue > 0 do pcall(table.remove(imgQueue, 1)) end
        imgBusy = false
    end)
end
local function webImage(img, url, file, onShown)
    if not (typeof(getcustomasset) == "function" and canFile()) then return end
    table.insert(imgQueue, function()
        local path = "combowick_flags/" .. file
        local ok = pcall(function()
            if not isfile(path) then
                pcall(function() if makefolder and not (isfolder and isfolder("combowick_flags")) then makefolder("combowick_flags") end end)
                local data = game:HttpGet(url)
                if type(data) ~= "string" or #data < 100 or data:sub(2, 4) ~= "PNG" then error("bad png") end
                writefile(path, data)
            elseif #readfile(path) < 100 then -- a half-written file from a crash: re-download next time
                delfile(path); error("partial file")
            end
            local id = getcustomasset(path)
            if type(id) ~= "string" or id == "" then error("no asset id") end -- some mobile executors return ""
            if img.Parent then img.Image = id; img.ImageTransparency = 0; if onShown then onShown() end end
        end)
        if not ok then pcall(function() if isfile(path) and delfile then delfile(path) end end) end
    end)
    runQueue()
end
local function setFlag(img, badge, key)
    local cc = FLAG[key]
    badge.Text = cc and cc:upper() or "?"
    if cc then webImage(img, "https://flagcdn.com/w80/" .. cc .. ".png", cc .. ".png", function() badge.Visible = false end) end
end

-- ---------- object ----------
function LanguageSelector.new()
    local self = setmetatable({}, LanguageSelector)
    self.scripts = {}
    self.remember = true
    self.savedLanguage = nil
    self.SCRIPT_ID = nil
    self.conns = {}
    self.gui = nil
    self.alive = 0 -- bumps on every cleanup so old loops stop
    return self
end

-- kept for IQ (it overrides this to pin the old save key); v2 uses it only to find old per-game saves
function LanguageSelector:generateScriptsHash()
    local keys = {}
    for k in pairs(self.scripts) do table.insert(keys, k) end
    table.sort(keys)
    local s = ""
    for _, k in ipairs(keys) do local id = tostring(self.scripts[k]):match("/script/([^/]+)$"); if id then s = s .. id end end
    local h = 0
    for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 1000000000 end
    return tostring(h)
end

function LanguageSelector:track(c) table.insert(self.conns, c); return c end
function LanguageSelector:cleanup()
    self.alive = self.alive + 1
    for _, c in ipairs(self.conns) do pcall(function() c:Disconnect() end) end
    self.conns = {}
    if self.gui then pcall(function() self.gui:Destroy() end); self.gui = nil end
    if self.blur then local bl = self.blur; self.blur = nil; pcall(function() tween(bl, 0.25, { Size = 0 }).Completed:Connect(function() bl:Destroy() end) end) end
end

function LanguageSelector:suggested()
    local codes = {}
    pcall(function() table.insert(codes, player.LocaleId) end)
    pcall(function() table.insert(codes, game:GetService("LocalizationService").RobloxLocaleId) end)
    pcall(function() table.insert(codes, game:GetService("LocalizationService").SystemLocaleId) end)
    -- first non-English match wins (Roblox often reports en-us by default while the device is es-mx etc.)
    local english
    for _, code in ipairs(codes) do
        local key = LOCALE[(tostring(code or ""):lower()):match("^(%a+)") or ""]
        if key and self.scripts[key] then
            if key ~= "English" then return key end
            english = key
        end
    end
    return english or (self.scripts["English"] and "English") or self:orderedKeys()[1]
end

function LanguageSelector:orderedKeys()
    local out, seen = {}, {}
    for _, k in ipairs(ORDER) do if self.scripts[k] then table.insert(out, k); seen[k] = true end end
    local rest = {}
    for k in pairs(self.scripts) do if not seen[k] then table.insert(rest, k) end end
    table.sort(rest)
    for _, k in ipairs(rest) do table.insert(out, k) end
    return out
end

function LanguageSelector:readSave()
    if not canFile() then return nil end
    local function read(f)
        if not isfile(f) then return nil end
        local ok, d = pcall(function() return HttpService:JSONDecode(readfile(f)) end)
        return ok and type(d) == "table" and d or nil
    end
    if isfile(SAVE_FILE) then return read(SAVE_FILE) end -- (a corrupt global save must NOT bring back an old v1 language)
    -- migrate a v1 per-game save (LanguageSelector_<GameId>_<hash>_SavedSettings.json)
    local old = read("LanguageSelector_" .. tostring(game.GameId) .. "_" .. tostring(self.SCRIPT_ID) .. "_SavedSettings.json")
    if old and old.language then
        local m = { language = old.language, remember = true, v = 2 }
        pcall(writefile, SAVE_FILE, HttpService:JSONEncode(m))
        return m
    end
    return nil
end

-- a language that failed to load must not stay saved (or every run would auto-load the broken one)
function LanguageSelector:forgetLanguage(lang)
    if not canFile() then return end
    local d = self:readSave()
    if d and d.language == lang then pcall(writefile, SAVE_FILE, HttpService:JSONEncode({ remember = self.remember, v = 2 })) end
    if self.savedLanguage == lang then self.savedLanguage = nil end
end

function LanguageSelector:writeSave(lang)
    if not canFile() then return end
    if self.remember and lang then
        pcall(writefile, SAVE_FILE, HttpService:JSONEncode({ language = lang, remember = true, v = 2, time = os.time() }))
    else
        pcall(writefile, SAVE_FILE, HttpService:JSONEncode({ remember = false, v = 2 }))
    end
end

-- the real load (overridable for tests)
function LanguageSelector:loadScript(lang)
    local url = self.scripts[lang]
    if not url then return end
    _G["SelectedLanguage_" .. tostring(self.SCRIPT_ID)] = lang
    _G["LanguagePreference_" .. tostring(self.SCRIPT_ID)] = lang
    task.spawn(function()
        -- download (one retry), then compile, then run — a failure shows "couldn't load · retry" instead of nothing
        local src
        for attempt = 1, 2 do
            local ok, res = pcall(function() return game:HttpGet(url) end)
            if ok and type(res) == "string" and #res > 0 then src = res; break end
            if attempt == 1 then task.wait(1.5) end
        end
        if not src then warn("[COMBO_WICK] couldn't download the " .. lang .. " script"); self:forgetLanguage(lang); self:showLoadError(lang); return end
        local fn, cerr = loadstring(src)
        if not fn then warn("[COMBO_WICK] " .. lang .. " script didn't compile: " .. tostring(cerr)); self:forgetLanguage(lang); self:showLoadError(lang); return end
        -- switching language: close the menu the previous language opened (scripts expose getgenv().Library)
        if self.loadedLanguage and self.loadedLanguage ~= lang then
            pcall(function()
                local L = getgenv and getgenv().Library
                if type(L) == "table" and type(L.Unload) == "function" then L:Unload() end
            end)
        end
        self.loadedLanguage = lang
        local ok, err = pcall(fn)
        if not ok then warn("[COMBO_WICK] " .. lang .. " script error: " .. tostring(err)) end
    end)
end

function LanguageSelector:showLoadError(lang)
    local g = self:newGui("CW_LanguageError")
    local gen = self.alive
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0); f.Size = UDim2.fromOffset(330, 52); f.Position = UDim2.new(0.5, 0, 0, -70)
    f.BackgroundColor3 = C.bg; f.Parent = g
    corner(f, 6); self:runningEdge(f, 1.6)
    local brand = txt(f, "COMBO_WICK", 12, C.gold); brand.Position = UDim2.fromOffset(14, 7); brand.Size = UDim2.fromOffset(120, 14)
    local t = txt(f, "couldn't load " .. native(lang), 14, Color3.fromRGB(255, 120, 120)); t.Position = UDim2.fromOffset(14, 22); t.Size = UDim2.new(1, -130, 0, 22); fitFont(t)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(1, 0.5); b.Size = UDim2.fromOffset(96, 30); b.Position = UDim2.new(1, -11, 0.5, 0); b.BackgroundColor3 = C.gold; b.AutoButtonColor = false
    b.Text = "retry"; b.TextColor3 = C.bg; b.Font = FONT; b.TextSize = 14; b.Parent = f
    corner(b, 4)
    tween(f, 0.35, { Position = UDim2.new(0.5, 0, 0, 16) }, Enum.EasingStyle.Quint)
    local done = false
    onTap(b, function() if done or self.alive ~= gen then return end; done = true; click(); self:cleanup(); self:loadScript(lang) end)
end

function LanguageSelector:pick(lang)
    if not (lang and self.scripts[lang]) then return end
    self.savedLanguage = lang
    self:writeSave(lang)
    self:cleanup()
    local gen = self.alive -- a newer screen / re-executed IQ bumps this and cancels the toast below
    self:loadScript(lang)
    task.delay(1.5, function() if self.alive == gen then self:showChangeToast(lang) end end)
end

-- continue/close from the picker: the language that is ALREADY loaded just closes (no hub reload)
function LanguageSelector:continueWith(lang)
    if self.loadedLanguage and lang == self.loadedLanguage then self:cleanup() else self:pick(lang) end
end

-- ---------- Init (same contract as v1) ----------
function LanguageSelector:Init(scripts)
    self.scripts = scripts or {}
    self.SCRIPT_ID = self:generateScriptsHash() -- from the wrapper's own keys (finds old v1 saves)
    -- one spelling per language from here on ("Arabic" in some wrappers = "Arabic (العربية)" in IQ)
    local norm = {}
    for k, v in pairs(self.scripts) do norm[ALIAS[k] or k] = v end
    self.scripts = norm
    -- a selector that already loaded something this session (IQ -> the hub) = we're the game script's picker
    local prev
    pcall(function() prev = getgenv and getgenv().__CW_LANG_SEL end)
    local nested = type(prev) == "table" and prev ~= self and prev.loadedLanguage ~= nil and prev.SCRIPT_ID ~= self.SCRIPT_ID
    pcall(function() if prev then prev:cleanup() end end)
    pcall(function() if getgenv then getgenv().__CW_LANG_SEL = self end end)
    local save = self:readSave()
    if save then self.remember = save.remember ~= false end
    local lang = (self.remember and save and save.language) or (nested and prev.loadedLanguage) or nil
    lang = lang and (ALIAS[lang] or lang)
    if not lang then return false end
    if self.scripts[lang] then
        self.savedLanguage = lang
        if nested then self:quickLoad(lang) else self:showAutoLoad(lang) end
        return true
    end
    -- this game doesn't have the player's language: English (else the closest one), WITHOUT overwriting the save
    local fb = (self.scripts["English"] and "English") or self:suggested()
    if not fb then return false end
    self:quickLoad(fb, lang)
    return true
end

-- load now (no countdown), then the small "change" toast — or the "not in this game" note when it's a fallback
function LanguageSelector:quickLoad(lang, missing)
    self:cleanup()
    local gen = self.alive
    self:loadScript(lang)
    task.delay(1.5, function()
        if self.alive ~= gen then return end
        if missing then self:showFallbackToast(missing, lang) else self:showChangeToast(lang) end
    end)
end

-- ---------- shared visuals ----------
function LanguageSelector:newGui(name)
    self:cleanup()
    -- sweep leftovers from older runs/versions (no getgenv, or a v1/v2 picker still open)
    pcall(function()
        for _, r in ipairs({ guiParent(), game:GetService("CoreGui") }) do
            for _, c in ipairs(r:GetChildren()) do
                if c:IsA("ScreenGui") and (c.Name:sub(1, 11) == "CW_Language" or c.Name == "LanguageSelectorGUI" or c.Name == "ResetNotificationGUI") then c:Destroy() end
            end
        end
        local lb = game:GetService("Lighting"):FindFirstChild("CW_LangBlur"); if lb then lb:Destroy() end
    end)
    local g = Instance.new("ScreenGui")
    g.Name = name; g.ResetOnSpawn = false; g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; g.DisplayOrder = 999
    pcall(function() g.IgnoreGuiInset = true end)
    -- low-identity executors can't parent to CoreGui: fall back to PlayerGui instead of erroring (= no picker at all)
    if not pcall(function() g.Parent = guiParent() end) then g.Parent = player:WaitForChild("PlayerGui") end
    self.gui = g
    local sc = Instance.new("UIScale"); sc.Parent = g
    local camConn
    local function fit()
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
        sc.Scale = math.clamp(math.min(vp.X / 500, vp.Y / 420), 0.55, 1)
    end
    local function hook()
        if camConn then camConn:Disconnect() end
        if workspace.CurrentCamera then camConn = self:track(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)) end
        fit()
    end
    hook()
    self:track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)) -- autoexec: camera may not exist yet
    return g
end

-- thin gold edge + a bright gold streak running around it (30 fps on phones)
function LanguageSelector:runningEdge(frame, thickness)
    stroke(frame, C.gold, 1, 0.72)
    local glow = Instance.new("UIStroke")
    glow.Thickness = thickness or 1.6; glow.Color = Color3.new(1, 1, 1); glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; glow.Parent = frame
    local gr = Instance.new("UIGradient")
    gr.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, C.gold), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 240, 180)), ColorSequenceKeypoint.new(1, C.gold) })
    gr.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.40, 1), NumberSequenceKeypoint.new(0.48, 0.15),
        NumberSequenceKeypoint.new(0.50, 0), NumberSequenceKeypoint.new(0.52, 0.15), NumberSequenceKeypoint.new(0.60, 1), NumberSequenceKeypoint.new(1, 1),
    })
    gr.Parent = glow
    local rot, acc, step = 0, 0, MOBILE and (1 / 30) or 0
    self:track(RunService.Heartbeat:Connect(function(dt)
        rot = (rot + dt * 110) % 360
        acc = acc + dt
        if acc >= step then acc = 0; gr.Rotation = rot end
    end))
end

-- faint gold dust drifting up behind the content (tween-driven, no per-frame script work)
function LanguageSelector:dust(frame)
    local gen = self.alive
    local layer = Instance.new("Frame"); layer.Size = UDim2.fromScale(1, 1); layer.BackgroundTransparency = 1; layer.ClipsDescendants = true; layer.ZIndex = 0; layer.Parent = frame
    for _ = 1, (MOBILE and 5 or 10) do
        local d = Instance.new("Frame"); local s = math.random(2, 3)
        d.Size = UDim2.fromOffset(s, s); d.BorderSizePixel = 0; d.BackgroundColor3 = C.goldSoft; d.BackgroundTransparency = 1; d.ZIndex = 0; d.Parent = layer
        corner(d, s)
        task.spawn(function()
            task.wait(math.random() * 3)
            while d.Parent and self.alive == gen do
                local x = math.random()
                d.Position = UDim2.new(x, 0, 1, 4); d.BackgroundTransparency = 0.55 + math.random() * 0.3
                local t = 6 + math.random() * 5
                local tw = TweenService:Create(d, TweenInfo.new(t, Enum.EasingStyle.Linear), { Position = UDim2.new(math.clamp(x + (math.random() - 0.5) * 0.15, 0, 1), 0, 0, -6), BackgroundTransparency = 1 })
                tw:Play(); tw.Completed:Wait()
            end
        end)
    end
end

-- ---------- "loading: X · change" (players can switch BEFORE anything loads) ----------
function LanguageSelector:showAutoLoad(lang)
    local g = self:newGui("CW_LanguageAutoLoad")
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0); f.Size = UDim2.fromOffset(330, 52); f.Position = UDim2.new(0.5, 0, 0, -70)
    f.BackgroundColor3 = C.bg; f.Parent = g
    corner(f, 6); self:runningEdge(f, 1.6)
    local brand = txt(f, "COMBO_WICK", 12, C.gold); brand.Position = UDim2.fromOffset(14, 7); brand.Size = UDim2.fromOffset(120, 14)
    local t = txt(f, ui(lang, 5) .. ": " .. native(lang), 14, C.text); t.Position = UDim2.fromOffset(14, 22); t.Size = UDim2.new(1, -130, 0, 22); fitFont(t)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(1, 0.5); b.Size = UDim2.fromOffset(96, 30); b.Position = UDim2.new(1, -11, 0.5, 0); b.BackgroundColor3 = C.gold; b.AutoButtonColor = false
    b.Text = ui(lang, 6); b.TextColor3 = C.bg; b.Font = FONT; b.TextSize = 14; b.Parent = f; fitFont(b)
    corner(b, 4)
    local bar = Instance.new("Frame"); bar.Size = UDim2.new(1, -12, 0, 2); bar.Position = UDim2.new(0, 6, 1, -4); bar.BackgroundColor3 = C.gold; bar.BorderSizePixel = 0; bar.Parent = f
    tween(f, 0.35, { Position = UDim2.new(0.5, 0, 0, 16) }, Enum.EasingStyle.Quint)
    tween(bar, AUTOLOAD_SECONDS, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)
    local decided = false
    local gen = self.alive -- re-executing IQ (or opening the picker) bumps this → the countdown below never fires a 2nd load
    onTap(b, function() if decided or self.alive ~= gen then return end; decided = true; click(); self:CreateGUI() end)
    task.delay(AUTOLOAD_SECONDS, function()
        if decided or self.alive ~= gen then return end
        decided = true
        self:cleanup()
        self:loadScript(lang)
    end)
end

-- ---------- small "language: X · change" after loading (the new language's loader unloads the old menu itself) ----------
function LanguageSelector:showChangeToast(lang)
    if self.gui then return end
    local g = self:newGui("CW_LanguageToast")
    local f = Instance.new("Frame")
    -- phones: top-center (bottom-right is where the jump button is); PC: bottom-right
    local shownPos = MOBILE and UDim2.new(0.5, 0, 0, 16) or UDim2.new(1, -16, 1, -16)
    local hiddenPos = MOBILE and UDim2.new(0.5, 0, 0, -70) or UDim2.new(1, 280, 1, -16)
    f.AnchorPoint = MOBILE and Vector2.new(0.5, 0) or Vector2.new(1, 1); f.Size = UDim2.fromOffset(250, 42); f.Position = hiddenPos
    f.BackgroundColor3 = C.bg; f.Parent = g
    corner(f, 6); self:runningEdge(f, 1.4)
    local t = txt(f, ui(lang, 1) .. ": " .. native(lang), 13, C.text); t.Position = UDim2.fromOffset(12, 0); t.Size = UDim2.new(1, -100, 1, 0); fitFont(t)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(1, 0.5); b.Size = UDim2.fromOffset(78, 26); b.Position = UDim2.new(1, -8, 0.5, 0); b.BackgroundColor3 = C.tile; b.AutoButtonColor = false
    b.Text = ui(lang, 6); b.TextColor3 = C.goldSoft; b.Font = FONT; b.TextSize = 13; b.Parent = f; fitFont(b)
    corner(b, 4); stroke(b, C.gold, 1, 0.5)
    tween(f, 0.35, { Position = shownPos }, Enum.EasingStyle.Quint)
    local done = false
    local gen = self.alive
    onTap(b, function() if not done and self.alive == gen then done = true; click(); self:CreateGUI() end end)
    task.delay(8, function()
        if done or not f.Parent or self.alive ~= gen then return end
        done = true
        local tw = tween(f, 0.3, { Position = hiddenPos })
        tw.Completed:Connect(function() if self.gui == g then self:cleanup() end end)
    end)
end

-- ---------- "Arabic isn't in this game · using English  [change]" ----------
function LanguageSelector:showFallbackToast(missing, used)
    if self.gui then return end
    local g = self:newGui("CW_LanguageToast")
    local f = Instance.new("Frame")
    local shownPos = MOBILE and UDim2.new(0.5, 0, 0, 16) or UDim2.new(1, -16, 1, -16)
    local hiddenPos = MOBILE and UDim2.new(0.5, 0, 0, -80) or UDim2.new(1, 400, 1, -16)
    f.AnchorPoint = MOBILE and Vector2.new(0.5, 0) or Vector2.new(1, 1); f.Size = UDim2.fromOffset(350, 54); f.Position = hiddenPos
    f.BackgroundColor3 = C.bg; f.Parent = g
    corner(f, 6); self:runningEdge(f, 1.4)
    local brand = txt(f, "COMBO_WICK", 11, C.gold); brand.Position = UDim2.fromOffset(12, 5); brand.Size = UDim2.fromOffset(120, 13)
    local t = txt(f, native(missing) .. " " .. (NOT_HERE[missing] or NOT_HERE["English"]) .. " " .. native(used), 13, C.text)
    t.Position = UDim2.fromOffset(12, 18); t.Size = UDim2.new(1, -110, 0, 32); t.TextWrapped = true; t.TextTruncate = Enum.TextTruncate.None
    t.TextScaled = true; fitFont(t)
    local tsc = Instance.new("UITextSizeConstraint"); tsc.MaxTextSize = 13; tsc.MinTextSize = 9; tsc.Parent = t
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(1, 0.5); b.Size = UDim2.fromOffset(84, 28); b.Position = UDim2.new(1, -9, 0.5, 0); b.BackgroundColor3 = C.tile; b.AutoButtonColor = false
    b.Text = ui(missing, 6); b.TextColor3 = C.goldSoft; b.Font = FONT; b.TextSize = 13; b.Parent = f; fitFont(b)
    corner(b, 4); stroke(b, C.gold, 1, 0.5)
    tween(f, 0.35, { Position = shownPos }, Enum.EasingStyle.Quint)
    local done = false
    local gen = self.alive
    onTap(b, function() if not done and self.alive == gen then done = true; click(); self:CreateGUI() end end)
    task.delay(10, function()
        if done or not f.Parent or self.alive ~= gen then return end
        done = true
        local tw = tween(f, 0.3, { Position = hiddenPos })
        tw.Completed:Connect(function() if self.gui == g then self:cleanup() end end)
    end)
end

-- ---------- the picker ----------
function LanguageSelector:CreateGUI()
    local g = self:newGui("CW_LanguageSelector")
    local sug = self:suggested()
    local selected = (self.savedLanguage and self.scripts[self.savedLanguage]) and self.savedLanguage or sug

    local dim = Instance.new("Frame")
    dim.Size = UDim2.fromScale(1, 1); dim.BackgroundColor3 = Color3.new(0, 0, 0); dim.BackgroundTransparency = 1; dim.BorderSizePixel = 0; dim.Parent = g
    tween(dim, 0.3, { BackgroundTransparency = MOBILE and 0.4 or 0.5 })
    if not MOBILE then -- blur is the heaviest effect on weak phones
        pcall(function()
            local blur = Instance.new("BlurEffect"); blur.Size = 0; blur.Name = "CW_LangBlur"; blur.Parent = game:GetService("Lighting")
            self.blur = blur; tween(blur, 0.3, { Size = 12 })
        end)
    end

    local W, H = 470, 382
    local win = Instance.new("Frame")
    win.AnchorPoint = Vector2.new(0.5, 0.5); win.Size = UDim2.fromOffset(W, H); win.Position = UDim2.fromScale(0.5, 0.53)
    win.BackgroundColor3 = C.bg; win.BackgroundTransparency = 1; win.Parent = g
    corner(win, 6)
    self:runningEdge(win, 1.8)
    self:dust(win)
    local wsc = Instance.new("UIScale"); wsc.Scale = 0.96; wsc.Parent = win
    tween(win, 0.3, { BackgroundTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Quint)
    tween(wsc, 0.3, { Scale = 1 }, Enum.EasingStyle.Quint)

    -- top bar (drag handle)
    local top = Instance.new("Frame"); top.Size = UDim2.new(1, 0, 0, 34); top.BackgroundTransparency = 1; top.ZIndex = 2; top.Parent = win
    -- server logo (falls back to a plain gold ring if it can't download)
    local logo = Instance.new("ImageLabel"); logo.Size = UDim2.fromOffset(22, 22); logo.Position = UDim2.new(0, 12, 0.5, -11)
    logo.BackgroundColor3 = C.tile; logo.ImageTransparency = 1; logo.ScaleType = Enum.ScaleType.Crop; logo.Parent = top
    corner(logo, 11); stroke(logo, C.gold, 1, 0.4)
    webImage(logo, LOGO_URL, "cw_logo.png")
    local brand = txt(top, "COMBO_WICK", 15, C.gold); brand.Position = UDim2.fromOffset(42, 0); brand.Size = UDim2.fromOffset(100, 34); brand.TextTruncate = Enum.TextTruncate.None
    local crumb = txt(top, "/  language", 14, C.sub); crumb.Position = UDim2.fromOffset(140, 0); crumb.Size = UDim2.fromOffset(150, 34)
    -- discord: copies the invite (free promo every time someone picks a language)
    local dc = Instance.new("TextButton")
    dc.AnchorPoint = Vector2.new(1, 0.5); dc.Size = UDim2.fromOffset(84, 22); dc.Position = UDim2.new(1, -42, 0.5, 0)
    dc.BackgroundColor3 = C.tile; dc.AutoButtonColor = false; dc.Text = "discord"; dc.TextColor3 = C.goldSoft; dc.Font = FONT; dc.TextSize = 13; dc.Parent = top
    corner(dc, 4); stroke(dc, C.gold, 1, 0.55)
    onTap(dc, function()
        click()
        local ok = pcall(function() (setclipboard or toclipboard)(DISCORD_INVITE) end)
        dc.Text = ok and "copied!" or "ufrz9Zaqs8"
        task.delay(2.5, function() if dc.Parent then dc.Text = "discord" end end)
    end)
    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(34, 34); close.Position = UDim2.new(1, -38, 0, 0); close.BackgroundTransparency = 1
    close.Text = "x"; close.TextColor3 = C.sub; close.Font = FONT; close.TextSize = 16; close.AutoButtonColor = false; close.Parent = top
    self:track(close.MouseEnter:Connect(function() close.TextColor3 = C.gold end))
    self:track(close.MouseLeave:Connect(function() close.TextColor3 = C.sub end))
    local div = Instance.new("Frame"); div.Size = UDim2.new(1, 0, 0, 1); div.Position = UDim2.new(0, 0, 1, 0); div.BorderSizePixel = 0
    div.BackgroundColor3 = C.gold; div.BackgroundTransparency = 0.82; div.Parent = top
    do
        -- follow only the finger/mouse that grabbed the bar (a 2nd finger on the joystick/camera must not move it)
        local dragInput, startPos, startAt
        self:track(top.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragInput, startAt, startPos = i, i.Position, win.Position end
        end))
        self:track(UserInputService.InputChanged:Connect(function(i)
            if not dragInput then return end
            local mine = (dragInput.UserInputType == Enum.UserInputType.Touch and i == dragInput)
                or (dragInput.UserInputType == Enum.UserInputType.MouseButton1 and i.UserInputType == Enum.UserInputType.MouseMovement)
            if mine then
                local d = i.Position - startAt
                win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end))
        self:track(UserInputService.InputEnded:Connect(function(i)
            if i == dragInput or (dragInput and i.UserInputType == Enum.UserInputType.MouseButton1 and dragInput.UserInputType == Enum.UserInputType.MouseButton1) then dragInput = nil end
        end))
    end

    -- flag tiles
    local grid = Instance.new("ScrollingFrame")
    grid.Position = UDim2.fromOffset(12, 44); grid.Size = UDim2.new(1, -24, 1, -44 - 52); grid.ZIndex = 2
    grid.BackgroundTransparency = 1; grid.BorderSizePixel = 0; grid.ScrollBarThickness = 2; grid.ScrollBarImageColor3 = C.gold; grid.ScrollBarImageTransparency = 0.3
    grid.CanvasSize = UDim2.new(); grid.AutomaticCanvasSize = Enum.AutomaticSize.Y; grid.ScrollingDirection = Enum.ScrollingDirection.Y; grid.Parent = win
    local gl = Instance.new("UIGridLayout"); gl.CellSize = UDim2.new(1 / 3, -7, 0, 48); gl.CellPadding = UDim2.fromOffset(6, 6); gl.SortOrder = Enum.SortOrder.LayoutOrder; gl.Parent = grid
    local gp = Instance.new("UIPadding"); gp.PaddingRight = UDim.new(0, 6); gp.PaddingTop = UDim.new(0, 3); gp.PaddingBottom = UDim.new(0, 3); gp.Parent = grid

    local tiles, order, cont, rem, det = {}, {}, nil, nil, nil
    local function words()
        crumb.Text = "/  " .. ui(selected, 1); fitFont(crumb)
        if rem then rem.Text = ui(selected, 2); fitFont(rem) end
        if det then det.Text = ui(selected, 4) .. ": " .. native(sug); fitFont(det) end
        if cont then cont.Text = ui(selected, 3) .. "  >"; fitFont(cont) end
    end
    local function paint(pop)
        for key, t in pairs(tiles) do
            local on = key == selected
            t.tile.BackgroundColor3 = on and C.tileOn or C.tile
            t.st.Transparency = on and 0.05 or 0.88
            t.name.TextColor3 = on and C.goldSoft or C.text
            tween(t.bar, 0.18, { Size = on and UDim2.new(1, -16, 0, 2) or UDim2.new(0, 0, 0, 2) })
            if on and pop then t.flagScale.Scale = 1.25; tween(t.flagScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back) end
        end
        words()
    end
    local function choose(key) if not key or key == selected then return end; selected = key; click(); paint(true) end

    local keys = { sug }
    for _, k in ipairs(self:orderedKeys()) do if k ~= sug then table.insert(keys, k) end end
    for i, key in ipairs(keys) do
        local d = DISPLAY[key] or { key, "" }
        local tile = Instance.new("TextButton")
        tile.Name = key; tile.LayoutOrder = i; tile.AutoButtonColor = false; tile.Text = ""; tile.BackgroundColor3 = C.tile; tile.ZIndex = 2; tile.Parent = grid
        corner(tile, 4)
        local st = stroke(tile, C.gold, 1, 0.88)
        local holder = Instance.new("Frame"); holder.Size = UDim2.fromOffset(22, 22); holder.Position = UDim2.new(0, 10, 0.5, -11)
        holder.BackgroundColor3 = Color3.fromRGB(45, 44, 50); holder.Parent = tile; corner(holder, 11)
        local flagScale = Instance.new("UIScale"); flagScale.Parent = holder
        local badge = txt(holder, "", 9, C.goldSoft, Enum.TextXAlignment.Center); badge.Size = UDim2.fromScale(1, 1)
        local img = Instance.new("ImageLabel"); img.Size = UDim2.fromScale(1, 1); img.BackgroundTransparency = 1; img.ScaleType = Enum.ScaleType.Crop
        img.ImageTransparency = 1; img.Parent = holder; corner(img, 11)
        setFlag(img, badge, key)
        local hasSub = d[2] ~= "" and d[2] ~= d[1]
        local nm = txt(tile, d[1], 14, C.text); nm.Position = UDim2.fromOffset(40, hasSub and 6 or 0); nm.Size = UDim2.new(1, -46, 0, hasSub and 20 or 48)
        if d[1]:match("[\128-\255]") then nm.Font = Enum.Font.GothamMedium; nm.TextSize = 13 end
        if hasSub then local en = txt(tile, d[2]:lower(), 11, C.sub); en.Position = UDim2.fromOffset(40, 25); en.Size = UDim2.new(1, -46, 0, 16) end
        if key == sug then local star = txt(tile, "*", 14, C.gold, Enum.TextXAlignment.Center); star.Size = UDim2.fromOffset(14, 14); star.Position = UDim2.new(1, -16, 0, 3) end
        local bar = Instance.new("Frame"); bar.AnchorPoint = Vector2.new(0.5, 1); bar.Position = UDim2.new(0.5, 0, 1, 0); bar.Size = UDim2.new(0, 0, 0, 2)
        bar.BorderSizePixel = 0; bar.BackgroundColor3 = C.gold; bar.Parent = tile
        tiles[key] = { tile = tile, st = st, name = nm, bar = bar, flagScale = flagScale }
        order[i] = key
        if not MOBILE then
            self:track(tile.MouseEnter:Connect(function() if key ~= selected then st.Transparency = 0.55; tile.BackgroundColor3 = Color3.fromRGB(27, 27, 32) end end))
            self:track(tile.MouseLeave:Connect(function() if key ~= selected then st.Transparency = 0.88; tile.BackgroundColor3 = C.tile end end))
        end
        onTap(tile, function() choose(key) end) -- selecting never loads; continue does
    end

    -- bottom bar
    local bot = Instance.new("Frame"); bot.Size = UDim2.new(1, -24, 0, 40); bot.Position = UDim2.new(0, 12, 1, -46); bot.BackgroundTransparency = 1; bot.ZIndex = 2; bot.Parent = win
    local bdiv = Instance.new("Frame"); bdiv.Size = UDim2.new(1, 24, 0, 1); bdiv.Position = UDim2.new(0, -12, 0, -4); bdiv.BorderSizePixel = 0
    bdiv.BackgroundColor3 = C.gold; bdiv.BackgroundTransparency = 0.82; bdiv.Parent = bot
    local remB = Instance.new("TextButton"); remB.Size = UDim2.fromOffset(130, 40); remB.BackgroundTransparency = 1; remB.Text = ""; remB.Parent = bot
    local box = Instance.new("Frame"); box.Size = UDim2.fromOffset(14, 14); box.Position = UDim2.new(0, 2, 0.5, -7); box.Parent = remB; corner(box, 3)
    stroke(box, C.gold, 1, 0.3)
    local tick = txt(box, "", 12, C.bg, Enum.TextXAlignment.Center); tick.Size = UDim2.fromScale(1, 1)
    rem = txt(remB, "remember", 13, C.text); rem.Position = UDim2.fromOffset(24, 0); rem.Size = UDim2.new(1, -24, 1, 0)
    local function paintBox() box.BackgroundColor3 = self.remember and C.gold or C.tile; tick.Text = self.remember and "v" or "" end
    paintBox()
    onTap(remB, function() self.remember = not self.remember; click(); paintBox(); if not self.remember then self:writeSave(nil) end end)
    det = txt(bot, "", 12, C.sub, Enum.TextXAlignment.Center); det.Size = UDim2.new(1, -290, 1, 0); det.Position = UDim2.fromOffset(136, 0)
    cont = Instance.new("TextButton")
    cont.AnchorPoint = Vector2.new(1, 0.5); cont.Size = UDim2.fromOffset(140, 30); cont.Position = UDim2.new(1, 0, 0.5, 0)
    cont.BackgroundColor3 = C.gold; cont.AutoButtonColor = false; cont.TextColor3 = C.bg; cont.Font = FONT; cont.TextSize = 15; cont.Parent = bot
    corner(cont, 4)
    if not MOBILE then
        self:track(cont.MouseEnter:Connect(function() tween(cont, 0.12, { BackgroundColor3 = C.goldHot }) end))
        self:track(cont.MouseLeave:Connect(function() tween(cont, 0.12, { BackgroundColor3 = C.gold }) end))
    end
    local function go() click(); self:continueWith(selected) end
    onTap(cont, go)
    onTap(close, go) -- closing continues with the selected language (v1 loaded nothing)

    -- keyboard (PC): arrows move, Enter continues, Esc closes (= continue)
    self:track(UserInputService.InputBegan:Connect(function(i, processed)
        if processed then return end
        local idx = table.find(order, selected) or 1
        local k = i.KeyCode
        if k == Enum.KeyCode.Right then choose(order[math.min(#order, idx + 1)])
        elseif k == Enum.KeyCode.Left then choose(order[math.max(1, idx - 1)])
        elseif k == Enum.KeyCode.Down then choose(order[math.min(#order, idx + 3)])
        elseif k == Enum.KeyCode.Up then choose(order[math.max(1, idx - 3)])
        elseif k == Enum.KeyCode.Return or k == Enum.KeyCode.KeypadEnter then go()
        elseif k == Enum.KeyCode.Escape and self.loadedLanguage then self:cleanup() end
    end))

    paint(false)
    return g
end

return LanguageSelector
