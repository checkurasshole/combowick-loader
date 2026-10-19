-- COMBO_WICK language-selector TEST mock "hub" (stands in for a real loader main; test only)
-- Behaves like the real main where it matters: unloads the previous menu via getgenv().Library, builds a menu,
-- exposes getgenv().Library. Records every load so the test can catch double loads / wrong languages.
local G = getgenv()
local lang = "?"
pcall(function() lang = tostring(_G["SelectedLanguage_" .. tostring(G.__CW_LANG_SEL.SCRIPT_ID)]) end)
pcall(function() if G.Library and G.Library.Unload then G.Library:Unload() end end)
G.__MOCK_LOADS = (G.__MOCK_LOADS or 0) + 1
G.__MOCK_LOG = (G.__MOCK_LOG or "") .. lang .. ";"
local parent = (gethui and gethui()) or game:GetService("CoreGui")
local sg = Instance.new("ScreenGui"); sg.Name = "CW_MOCK_HUB"; sg.ResetOnSpawn = false; sg.Parent = parent
local l = Instance.new("TextLabel")
l.Size = UDim2.fromOffset(280, 56); l.Position = UDim2.new(0, 20, 0.5, -28); l.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
l.TextColor3 = Color3.new(1, 1, 1); l.TextSize = 18; l.Font = Enum.Font.Code
l.Text = "MOCK HUB: " .. lang .. "  (load #" .. G.__MOCK_LOADS .. ")"; l.Parent = sg
G.Library = { Unload = function() pcall(function() sg:Destroy() end) end }
