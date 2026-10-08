local Players          = game:GetService("Players")
local CoreGui          = game:GetService("CoreGui")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")
local TextService      = game:GetService("TextService")
local GuiService       = game:GetService("GuiService")
local u2, v2, rgb = UDim2.new, Vector2.new, Color3.fromRGB
local colors = {
    primary    = rgb(255, 105, 0),
    success    = rgb(34, 197, 94),
    danger     = rgb(220, 50, 50),
    bg1        = rgb(26, 13, 5),
    bg2        = rgb(38, 19, 8),
    bg3        = rgb(53, 27, 12),
    bg4        = rgb(70, 36, 16),
    text       = rgb(255, 250, 245),
    textDim    = rgb(224, 205, 190),
    textDimmer = rgb(180, 160, 145),
    border     = rgb(90, 45, 20),
}
local isMobile    = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local WINDOW_SIZE = isMobile and v2(420, 280) or v2(560, 360)
local MIN_SIZE    = isMobile and v2(380, 250) or v2(440, 300)
local MAX_SIZE    = isMobile and v2(800, 600) or v2(1100, 760)
local SIDEBAR_W, HEADER_H, TOPBAR_H, SECTION_H = 120, 34, 28, 30
local PANEL_T, SECTION_T = 0.1, 0.3
local FONT = { title = 15, header = 12, normal = 11, small = 10 }
local BOLD, MEDIUM, REGULAR = Enum.Font.GothamBold, Enum.Font.GothamMedium, Enum.Font.Gotham
local LEFT = Enum.TextXAlignment.Left
local TEXT_DEFAULTS = { BorderSizePixel = 0, BackgroundTransparency = 1, Font = BOLD, TextSize = FONT.small, TextColor3 = colors.text }
local DEFAULTS = {
    Frame          = { BorderSizePixel = 0 },
    ScrollingFrame = { BorderSizePixel = 0, BackgroundTransparency = 1, ScrollBarThickness = 0, CanvasSize = u2(0, 0, 0, 0) },
    ImageLabel     = { BorderSizePixel = 0, BackgroundTransparency = 1 },
    ImageButton    = { BorderSizePixel = 0, AutoButtonColor = false },
    TextLabel      = { TextXAlignment = LEFT },
    TextButton     = { Text = "", AutoButtonColor = false },
    TextBox        = { Text = "", TextXAlignment = LEFT, ClearTextOnFocus = false, PlaceholderColor3 = colors.textDimmer },
}
for class, props in pairs(DEFAULTS) do
    if class:find("^Text") then
        for k, v in pairs(TEXT_DEFAULTS) do props[k] = v end
    end
end
local function new(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(DEFAULTS[class] or {}) do inst[k] = v end
    for k, v in pairs(props) do
        if k ~= "Parent" then inst[k] = v end
    end
    for _, child in ipairs(children or {}) do child.Parent = inst end
    inst.Parent = props.Parent
    return inst
end
local function corner(radius)
    return new("UICorner", { CornerRadius = radius and UDim.new(0, radius) or UDim.new(1, 0) })
end
local function stroke(color, transparency, thickness)
    return new("UIStroke", { Color = color or colors.border, Transparency = transparency or 0.4, Thickness = thickness or 1 })
end
local function fadeEnds(rotation)
    return new("UIGradient", {
        Rotation = rotation or 0,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
        }),
    })
end
local function cancelThread(thread)
    if thread then pcall(task.cancel, thread) end
end
local function safeCall(context, fn, ...)
    if not fn then return true end
    local ok, err = pcall(fn, ...)
    if not ok then warn(("[LynxGUI] %s error: %s"):format(context, tostring(err))) end
    return ok
end
local function fireCallback(context, fn, ...)
    if fn then task.spawn(safeCall, context, fn, ...) end
end
local function isPress(input)
    local t = input.UserInputType
    return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end
local function onHover(guiObject, enter, leave)
    if isMobile then return end
    guiObject.MouseEnter:Connect(enter)
    guiObject.MouseLeave:Connect(leave)
end
local function getGuiParent()
    local ok, hidden = pcall(function() return gethui and gethui() end)
    if ok and typeof(hidden) == "Instance" then return hidden end
    local probe = Instance.new("ScreenGui")
    local canUseCore = pcall(function() probe.Parent = CoreGui end)
    probe:Destroy()
    if canUseCore then return CoreGui end
    while not Players.LocalPlayer do task.wait() end   
    return Players.LocalPlayer:WaitForChild("PlayerGui")
end
local function getScreenSize(gui)
    local size = gui.AbsoluteSize
    if size.X < 100 and workspace.CurrentCamera then size = workspace.CurrentCamera.ViewportSize end
    return size.X < 100 and v2(1920, 1080) or size
end
local function toKey(title)
    return (tostring(title):gsub("[%s%.]+", "_"))
end
local function textHeight(text, size, font, width)
    if text == "" then return 0 end
    return math.ceil(TextService:GetTextSize(text, size, font, v2(width, 10000)).Y)
end
local function formatRichText(text)
    if type(text) ~= "string" or text == "" then return "" end
    return (text:gsub('<font color="rgb%s*%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)">', function(r, g, b)
        local function clamp(n) return math.clamp(math.floor(tonumber(n) or 0), 0, 255) end
        return ('<font color="#%02X%02X%02X">'):format(clamp(r), clamp(g), clamp(b))
    end))
end
local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do copy[deepCopy(k, seen)] = deepCopy(v, seen) end
    return copy
end
local function isList(t)
    if type(t) ~= "table" then return false end
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
    end
    return true
end
local function mergeTables(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" and not isList(v) and not isList(target[k]) then
            mergeTables(target[k], v)
        else
            target[k] = deepCopy(v)
        end
    end
end
local Library = {
    flags         = {},
    pages         = {},
    ConfigSystem  = {},
    _navButtons   = {},
    _connections  = {},
    _searchIndex  = {},
    _connSeq      = 0,
    _initialized  = false,
}
function Library:AddConnection(name, connection)
    local old = self._connections[name]
    if old then pcall(function() old:Disconnect() end) end
    self._connections[name] = connection
    return connection
end
function Library:_nextConnId()
    self._connSeq = self._connSeq + 1
    return self._connSeq
end
local CONFIG_FOLDER = "LynxGUI_Configs"
local LEGACY_FILE   = CONFIG_FOLDER .. "/lynx_config.json"
local LEGACY_BACKUP = CONFIG_FOLDER .. "/lynx_config.backup.json"
local COMPONENT_PREFIXES = { "Toggles", "Dropdowns", "MultiDropdowns", "Inputs" }
local Config        = Library.ConfigSystem
local CurrentConfig, DefaultConfig = {}, {}
local CallbackRegistry = {}
local isDirty, saveThread, lastSaveError = false, nil, nil
local configId, migratedFromLegacy = nil, false
local function resolveConfigId()
    if configId then return configId end
    local id = game.GameId
    if not id or id == 0 then id = game.PlaceId end
    return tostring(id)
end
local function configFile()
    return ("%s/config_%s.json"):format(CONFIG_FOLDER, (resolveConfigId():gsub("[^%w_%-]", "_")))
end
local function readJson(path)
    local exists = false
    local ok, data = pcall(function()
        exists = isfile(path)
        if not exists then return nil end
        local raw = readfile(path)
        return raw ~= "" and HttpService:JSONDecode(raw) or nil
    end)
    return ok and type(data) == "table" and data or nil, exists
end
function Config.SetConfigId(id)
    configId = id ~= nil and tostring(id) or nil
end
function Config.GetFileName()
    return configFile()
end
function Config.SetDefaults(defaults)
    DefaultConfig = deepCopy(defaults or {})
end
function Config.Save()
    return pcall(function()
        if isfolder and makefolder and not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
        writefile(configFile(), HttpService:JSONEncode(CurrentConfig))
    end)
end
local function takeLegacyConfig()
    local legacy = readJson(LEGACY_FILE)
    if not legacy then return nil end
    pcall(function()
        writefile(LEGACY_BACKUP, readfile(LEGACY_FILE))
        delfile(LEGACY_FILE)
    end)
    return legacy
end
function Config.Load()
    CurrentConfig = deepCopy(DefaultConfig)
    migratedFromLegacy = false
    local loaded, exists = readJson(configFile())
    if not loaded and not exists then
        loaded = takeLegacyConfig()
        migratedFromLegacy = loaded ~= nil
    end
    if loaded then
        mergeTables(CurrentConfig, loaded)
    elseif exists then
        warn("[LynxGUI] File config tidak bisa dibaca, sementara memakai nilai default.")
    end
    return CurrentConfig
end
local function pruneLegacyKeys()
    if not migratedFromLegacy then return end
    migratedFromLegacy = false
    for _, prefix in ipairs(COMPONENT_PREFIXES) do
        local group = CurrentConfig[prefix]
        if type(group) == "table" then
            for key in pairs(group) do
                if not CallbackRegistry[prefix .. "." .. tostring(key)] then group[key] = nil end
            end
        end
    end
    Config.Save()
end
function Config.Get(path, default)
    if not path then return default end
    local value = CurrentConfig
    for key in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return default end
        value = value[key]
    end
    if value == nil then return default end
    return value
end
function Config.Set(path, value)
    if not path then return end
    local keys = {}
    for key in path:gmatch("[^.]+") do keys[#keys + 1] = key end
    if #keys == 0 then return end
    local target = CurrentConfig
    for i = 1, #keys - 1 do
        if type(target[keys[i]]) ~= "table" then target[keys[i]] = {} end
        target = target[keys[i]]
    end
    target[keys[#keys]] = value
end
function Config.Reset()
    CurrentConfig = deepCopy(DefaultConfig)
    Config.Save()
end
function Config.Delete()
    isDirty = false
    cancelThread(saveThread)
    saveThread = nil
    pcall(function()
        if isfile(configFile()) then delfile(configFile()) end
    end)
end
local function markDirty()
    if _G.AutoSaveEnabled == false then return end
    isDirty = true
    if saveThread then return end
    saveThread = task.delay(2, function()
        saveThread = nil
        if not isDirty then return end
        isDirty = false
        local ok, err = Config.Save()
        if not ok and err ~= lastSaveError then
            warn("[LynxGUI] Config gagal disimpan: " .. tostring(err))
        end
        lastSaveError = not ok and err or nil
    end)
end
local function sameValue(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end
local function saveValue(path, value)
    if not path or sameValue(Config.Get(path), value) then return end
    Config.Set(path, value)
    markDirty()
end
local function registerCallback(path, callback, kind, default, updateVisual)
    if not path then return end
    if CallbackRegistry[path] then
        warn(("[LynxGUI] Judul komponen duplikat -> config '%s' dipakai lebih dari sekali; nilainya akan saling menimpa. Pakai judul yang unik."):format(path))
    end
    CallbackRegistry[path] = { path = path, callback = callback, kind = kind, default = default, updateVisual = updateVisual }
    if Library._initialized then
        local value = Config.Get(path, default)
        if updateVisual then safeCall("updateVisual @" .. path, updateVisual, value) end
        fireCallback("callback @" .. path, callback, value)
    end
end
local function executeConfigCallbacks()
    for _, entry in pairs(CallbackRegistry) do
        if entry.updateVisual then
            safeCall("updateVisual @" .. entry.path, entry.updateVisual, Config.Get(entry.path, entry.default))
        end
    end
    for _, wantToggle in ipairs({ false, true }) do
        for _, entry in pairs(CallbackRegistry) do
            if entry.callback and (entry.kind == "toggle") == wantToggle then
                fireCallback("callback @" .. entry.path, entry.callback, Config.Get(entry.path, entry.default))
            end
        end
    end
end
_G.AutoSaveEnabled = true
function _G.GetConfigValue(key, default) return Config.Get(key, default) end
local SAVEABLE = { ["nil"] = true, boolean = true, number = true, string = true, table = true }
function _G.SaveConfigValue(key, value)
    if not SAVEABLE[type(value)] then
        warn(("[LynxGUI] SaveConfigValue('%s'): tipe %s tidak bisa disimpan; ubah ke angka/string/tabel dulu."):format(tostring(key), typeof(value)))
        return
    end
    Config.Set(key, value)
    markDirty()
end
function _G.GetFullConfig() return CurrentConfig end
function Library:Cleanup()
    if isDirty then
        isDirty = false
        Config.Save()
    end
    cancelThread(saveThread)
    saveThread = nil
    cancelThread(self._initWatchdog)
    self._initWatchdog = nil
    for _, conn in pairs(self._connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(self._connections)
    table.clear(CallbackRegistry)
    table.clear(self.flags)
    table.clear(self.pages)
    table.clear(self._navButtons)
    table.clear(self._searchIndex)
    self._gui, self._win, self._currentPage = nil, nil, nil
    self._pageParking, self._dropParking = nil, nil
    self._dropdown, self._openDropdown = nil, nil
    self._pendingWindow = nil
    self._connSeq = 0
    self._initialized = false
    self:_resetNotify()
end
local DRAG_THRESHOLD = isMobile and 12 or 6   
local function pixelPosition(guiObject, screen)
    local p = guiObject.Position
    return v2(p.X.Scale * screen.X + p.X.Offset, p.Y.Scale * screen.Y + p.Y.Offset)
end
local DRAG_END = { [Enum.UserInputState.End] = true, [Enum.UserInputState.Cancel] = true }
local function trackDrag(handle, onStart, onMove, onEnd)
    local finishActive
    handle.InputBegan:Connect(function(input)
        if not isPress(input) then return end
        if finishActive then finishActive(true) end
        local startPos, moved, conns = input.Position, false, {}
        local function finish(cancelled)
            if finishActive ~= finish then return end
            finishActive = nil
            for _, conn in ipairs(conns) do conn:Disconnect() end
            if onEnd then onEnd(moved or cancelled) end
        end
        local function cancel() finish(true) end
        finishActive = finish
        if onStart then onStart() end
        conns = {
            UserInputService.InputChanged:Connect(function(i)
                if i ~= input and i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
                local delta = i.Position - startPos
                if delta.Magnitude > DRAG_THRESHOLD then moved = true end
                onMove(delta)
            end),
            input.Changed:Connect(function()
                if DRAG_END[input.UserInputState] then finish(false) end
            end),
            UserInputService.InputEnded:Connect(function(i)
                if i == input or (i.UserInputType == input.UserInputType and i.UserInputType ~= Enum.UserInputType.Touch) then
                    finish(false)
                end
            end),
            GuiService.MenuOpened:Connect(cancel),
            UserInputService.WindowFocusReleased:Connect(cancel),
        }
    end)
end
function Library:CreateWindow(config)
    config = config or {}
    local name = config.Name or "LynxGUI"
    self:Cleanup()
    self._guiParent = self._guiParent or getGuiParent()
    local existing = self._guiParent:FindFirstChild(name)
    if existing then existing:Destroy() end
    local gui = new("ScreenGui", {
        Name = name, Parent = self._guiParent, IgnoreGuiInset = true, ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 2147483647,
    })
    self._gui = gui
    gui.Destroying:Connect(function()
        if self._gui == gui then self:Cleanup() end
    end)
    local screen = getScreenSize(gui)
    local minSize = v2(math.min(MIN_SIZE.X, screen.X - 20), math.min(MIN_SIZE.Y, screen.Y - 20))
    local startW = math.min(WINDOW_SIZE.X, screen.X - 20)
    local startH = math.min(WINDOW_SIZE.Y, screen.Y - 20)
    local win = new("Frame", {
        Parent = gui, ZIndex = 3,
        Size = u2(0, startW, 0, startH), Position = u2(0.5, -startW / 2, 0.5, -startH / 2),
        BackgroundColor3 = colors.bg1, BackgroundTransparency = PANEL_T,
    }, { corner(7) })
    self._win = win
    self._sidebar = new("Frame", {
        Parent = win, ZIndex = 4, ClipsDescendants = true, BackgroundTransparency = 1,
        Size = u2(0, SIDEBAR_W, 1, -HEADER_H), Position = u2(0, 0, 0, HEADER_H),
    })
    new("Frame", {
        Parent = self._sidebar, ZIndex = 4, Size = u2(0, 1, 1, 0), Position = u2(1, 0, 0, 0),
        BackgroundColor3 = colors.border, BackgroundTransparency = 0.42,
    })
    self._navContainer = new("ScrollingFrame", {
        Parent = self._sidebar, ZIndex = 5, Size = u2(1, -10, 1, -39), Position = u2(0, 5, 0, 34),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
    }, { new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })
    local header = new("TextButton", { Parent = win, ZIndex = 5, Size = u2(1, 0, 0, HEADER_H) })
    new("Frame", {
        Parent = header, ZIndex = 5, Size = u2(1, -20, 0, 1), Position = u2(0, 10, 1, -1),
        BackgroundColor3 = colors.border, BackgroundTransparency = 0.62,
    })
    new("Frame", {
        Parent = header, ZIndex = 6, Size = u2(0, 28, 0, 2), Position = u2(0.5, -14, 0, 4),
        BackgroundColor3 = colors.primary, BackgroundTransparency = 0.35,
    }, { corner(2) })
    new("TextLabel", {
        Parent = header, ZIndex = 6, Text = config.Title or "LynX", Size = u2(0, 80, 1, 0), Position = u2(0, 12, 0, 0),
        TextSize = FONT.title, TextColor3 = colors.primary,
    })
    new("ImageLabel", {
        Parent = header, ZIndex = 6, Image = "rbxassetid://104332967321169", ImageColor3 = colors.primary,
        Size = u2(0, 16, 0, 16), Position = u2(0, 58, 0.5, -8),
    })
    new("Frame", {
        Parent = header, ZIndex = 6, Size = u2(0, 1, 0, 16), Position = u2(0, 82, 0.5, -8),
        BackgroundColor3 = colors.border, BackgroundTransparency = 0.2,
    })
    new("TextLabel", {
        Parent = header, ZIndex = 6, Text = config.Subtitle or "", Size = u2(0, 200, 1, 0), Position = u2(0, 96, 0, 0),
        TextColor3 = colors.textDim,
    })
    local minStroke = stroke()
    local minBtn = new("TextButton", {
        Parent = header, ZIndex = 7, Size = u2(0, 22, 0, 22), Position = u2(1, -28, 0.5, -11),
        BackgroundColor3 = colors.bg2, BackgroundTransparency = SECTION_T,
    }, { corner(5), minStroke })
    local minLine = new("Frame", {
        Parent = minBtn, ZIndex = 8, AnchorPoint = v2(0.5, 0.5), Position = u2(0.5, 0, 0.5, 0),
        Size = u2(0, 10, 0, 2), BackgroundColor3 = colors.primary,
    }, { corner() })
    local function setMinHover(on)
        minBtn.BackgroundColor3 = on and colors.bg3 or colors.bg2
        minStroke.Color = on and colors.primary or colors.border
        minStroke.Transparency = on and 0.1 or 0.4
        minLine.Size = u2(0, on and 12 or 10, 0, 2)
    end
    onHover(minBtn, function() setMinHover(true) end, function() setMinHover(false) end)
    local discordLink, discordText = "https://discord.gg/lynxx", "discord.gg/lynxx"
    local discordTextW = math.ceil(TextService:GetTextSize(discordText, FONT.small, BOLD, v2(1000, 100)).X)
    local discordW = discordTextW + 42
    local discordBtn = new("TextButton", {
        Parent = header, ZIndex = 7, Size = u2(0, discordW, 0, 22), Position = u2(1, -(34 + discordW), 0.5, -11),
    })
    new("ImageLabel", {
        Parent = discordBtn, ZIndex = 8, Image = "rbxthumb://type=Asset&id=84640740142415&w=150&h=150",
        ImageColor3 = colors.primary, Size = u2(0, 15, 0, 15), Position = u2(0, 8, 0.5, -7.5),
    })
    new("Frame", {
        Parent = discordBtn, ZIndex = 8, Size = u2(0, 1, 0, 12), Position = u2(0, 28, 0.5, -6),
        BackgroundColor3 = colors.primary, BackgroundTransparency = 0.45,
    }, { fadeEnds(90) })
    local discordLabel = new("TextLabel", {
        Parent = discordBtn, ZIndex = 8, Text = discordText, TextColor3 = colors.primary,
        TextTruncate = Enum.TextTruncate.AtEnd, Size = u2(0, discordTextW + 2, 1, 0), Position = u2(0, 33, 0, 0),
    })
    onHover(discordBtn,
        function() discordLabel.TextColor3 = colors.text end,
        function() discordLabel.TextColor3 = colors.primary end)
    discordBtn.MouseButton1Click:Connect(function()
        local clip = setclipboard or toclipboard or writeclipboard
            or (Clipboard and Clipboard.set) or (clipboard and clipboard.set)
        if clip and pcall(clip, discordLink) then
            self:MakeNotify({ Title = "Discord", Description = "Invite link disalin ke clipboard!" })
        else
            self:MakeNotify({ Title = "Discord", Description = discordLink, Delay = 6 })
        end
    end)
    self._contentBg = new("Frame", {
        Parent = win, ZIndex = 4, ClipsDescendants = true, BackgroundTransparency = 1,
        Size = u2(1, -(SIDEBAR_W + 6), 1, -(HEADER_H + 3)), Position = u2(0, SIDEBAR_W + 3, 0, HEADER_H + 1),
    })
    -- Hidden tabs and closed dropdowns are parked outside the window: Roblox re-lays out every
    -- descendant of a moved frame, Visible=false or not, so keeping them in `win` makes dragging
    -- cost scale with the number of features. The parking frames mirror the real sizes so text
    -- wrapping and dropdown rows are already correct when they move back in.
    local parking = new("Frame", { Parent = gui, Name = "Parking", Visible = false, BackgroundTransparency = 1 })
    self._pageParking = parking
    self._dropParking = new("Frame", { Parent = parking, BackgroundTransparency = 1 })
    local resizing = false
    local function syncParking()
        local content, winSize = self._contentBg.AbsoluteSize, win.AbsoluteSize
        parking.Size = u2(0, content.X, 0, content.Y)
        self._dropParking.Size = u2(0, 160, 0, math.max(0, winSize.Y - HEADER_H - 16))
    end
    syncParking()
    self._contentBg:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if not resizing then syncParking() end
    end)
    local topBar = new("Frame", {
        Parent = self._contentBg, ZIndex = 5, BackgroundTransparency = 1,
        Size = u2(1, -4, 0, TOPBAR_H), Position = u2(0, 2, 0, 2),
    })
    new("Frame", {
        Parent = topBar, ZIndex = 6, Size = u2(0, 3, 0, 16), Position = u2(0, 0, 0.5, -8),
        BackgroundColor3 = colors.primary,
    }, { corner() })
    self._pageTitle = new("TextLabel", {
        Parent = topBar, ZIndex = 6, Text = "Dashboard", TextSize = FONT.header,
        Size = u2(1, -16, 1, 0), Position = u2(0, 10, 0, 0),
    })
    new("Frame", {
        Parent = topBar, ZIndex = 5, Size = u2(1, -10, 0, 1), Position = u2(0, 5, 1, -1),
        BackgroundColor3 = colors.border, BackgroundTransparency = 0.7,
    })
    local dragStart, dragScreen, dragSize
    trackDrag(header, function()
        dragScreen, dragSize = gui.AbsoluteSize, win.AbsoluteSize
        dragStart = pixelPosition(win, dragScreen)
    end, function(delta)
        local x = math.clamp(dragStart.X + delta.X, 80 - dragSize.X, math.max(80 - dragSize.X, dragScreen.X - 80))
        local y = math.clamp(dragStart.Y + delta.Y, 0, math.max(0, dragScreen.Y - HEADER_H))
        win.Position = u2(0, math.floor(x + 0.5), 0, math.floor(y + 0.5))
    end)
    local resizeHandle = new("TextButton", {
        Parent = win, ZIndex = 100, AnchorPoint = v2(1, 1), Size = u2(0, 18, 0, 18), Position = u2(1, 0, 1, 0),
    })
    -- Dot triangle instead of rotated bars: any GuiObject with Rotation ~= 0 inside the window
    -- makes every drag frame take Roblox's slow render path (~0.4 ms/frame measured).
    for _, grip in ipairs({ { -3, -3 }, { -7, -3 }, { -11, -3 }, { -3, -7 }, { -7, -7 }, { -3, -11 } }) do
        new("Frame", {
            Parent = resizeHandle, ZIndex = 101, AnchorPoint = v2(1, 1),
            Size = u2(0, 2, 0, 2), Position = u2(1, grip[1], 1, grip[2]),
            BackgroundColor3 = colors.textDim, BackgroundTransparency = 0.35,
        })
    end
    local sizeStart
    trackDrag(resizeHandle, function()
        sizeStart, resizing = win.AbsoluteSize, true
    end, function(delta)
        win.Size = u2(
            0, math.clamp(sizeStart.X + delta.X, minSize.X, MAX_SIZE.X),
            0, math.clamp(sizeStart.Y + delta.Y, minSize.Y, MAX_SIZE.Y)
        )
    end, function()
        resizing = false
        syncParking()
    end)
    local icon, iconPos = nil, u2(0, 20, 0, 100)
    minBtn.MouseButton1Click:Connect(function()
        if icon then return end
        win.Visible = false
        icon = new("ImageButton", {
            Parent = gui, ZIndex = 50, Active = true, Size = u2(0, 40, 0, 40), Position = iconPos,
            BackgroundColor3 = colors.bg2, Image = "rbxassetid://118176705805619", ScaleType = Enum.ScaleType.Fit,
        }, { corner(6) })
        local iconStart, iconScreen
        trackDrag(icon, function()
            iconScreen = gui.AbsoluteSize
            iconStart = pixelPosition(icon, iconScreen)
        end, function(delta)
            icon.Position = u2(
                0, math.floor(math.clamp(iconStart.X + delta.X, 0, math.max(0, iconScreen.X - 40)) + 0.5),
                0, math.floor(math.clamp(iconStart.Y + delta.Y, 0, math.max(0, iconScreen.Y - 40)) + 0.5)
            )
        end, function(moved)
            if not icon then return end
            iconPos = icon.Position
            if moved then return end
            icon:Destroy()
            icon = nil
            win.Visible = true
        end)
    end)
    self:_createSearchBar()
    return self
end
function Library:_createSearchBar()
    local SEARCH_W, SEARCH_H = SIDEBAR_W - 12, 22
    local ROW_H, ROW_GAP, LIST_PAD, MAX_PANEL_H = 32, 3, 4, 168
    local searchStroke = stroke()
    local container = new("Frame", {
        Parent = self._sidebar, Name = "SearchBar", ZIndex = 7,
        Size = u2(0, SEARCH_W, 0, SEARCH_H), Position = u2(0, 6, 0, 6),
        BackgroundColor3 = colors.bg2, BackgroundTransparency = SECTION_T,
    }, { corner(5), searchStroke })
    new("ImageLabel", {
        Parent = container, ZIndex = 8, Image = "rbxassetid://109869955247116", ImageColor3 = colors.textDimmer,
        Size = u2(0, 14, 0, 14), Position = u2(0, 6, 0.5, -7),
    })
    local searchBox = new("TextBox", {
        Parent = container, ZIndex = 9, PlaceholderText = "Search feature...",
        Size = u2(1, -46, 1, 0), Position = u2(0, 26, 0, 0),
    })
    local clearBtn = new("TextButton", {
        Parent = container, ZIndex = 9, Visible = false, Text = "×", TextSize = 14, TextColor3 = colors.textDimmer,
        Size = u2(0, 16, 0, 16), Position = u2(1, -20, 0.5, -8),
    })
    local panel = new("Frame", {
        Parent = self._win, Name = "SearchResults", ZIndex = 60, Visible = false,
        Size = u2(0, SEARCH_W, 0, ROW_H + LIST_PAD * 2), Position = u2(0, 6, 0, HEADER_H + SEARCH_H + 9),
        BackgroundColor3 = colors.bg2, BackgroundTransparency = PANEL_T,
    }, { corner(5), stroke(nil, 0.35) })
    local list = new("ScrollingFrame", {
        Parent = panel, ZIndex = 61, Size = u2(1, -6, 1, -6), Position = u2(0, 3, 0, 3),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
    }, {
        new("UIListLayout", { Padding = UDim.new(0, ROW_GAP), SortOrder = Enum.SortOrder.LayoutOrder }),
        new("UIPadding", { PaddingRight = UDim.new(0, 1) }),
    })
    local emptyLabel = new("TextLabel", {
        Parent = panel, ZIndex = 62, Visible = false, Text = "No features found", TextColor3 = colors.textDimmer,
        Size = u2(1, -16, 1, 0), Position = u2(0, 8, 0, 0),
    })
    local function highlight(frame)
        local old = frame:FindFirstChild("__SearchHL")
        if old then old:Destroy() end
        local hl = new("UIStroke", { Parent = frame, Name = "__SearchHL", Color = colors.primary, Thickness = 2 })
        task.delay(1, function()
            if not hl.Parent then return end
            local tween = TweenService:Create(hl, TweenInfo.new(0.45), { Transparency = 1 })
            tween.Completed:Connect(function() hl:Destroy() end)
            tween:Play()
        end)
    end
    local function goToFeature(entry)
        panel.Visible = false
        searchBox.Text = ""
        if entry.pageName then self:_switchPage(entry.pageName) end
        safeCall("search expand", entry.expand)
        task.defer(function()
            local frame = entry.frame
            if not frame.Parent then return end
            task.wait()   
            local page = self.pages[entry.pageName]
            if page then
                local content = page.content
                local y = frame.AbsolutePosition.Y - content.AbsolutePosition.Y + content.CanvasPosition.Y
                content.CanvasPosition = v2(0, math.max(0, y - 4))
            end
            highlight(frame)
        end)
    end
    local rows = {}
    local function getRow(i)
        if rows[i] then return rows[i] end
        local button = new("TextButton", {
            Parent = list, ZIndex = 62, Size = u2(1, 0, 0, ROW_H),
            BackgroundColor3 = colors.bg3, BackgroundTransparency = SECTION_T,
        }, { corner(4) })
        new("Frame", {
            Parent = button, ZIndex = 63, Size = u2(0, 3, 1, -8), Position = u2(0, 0, 0, 4),
            BackgroundColor3 = colors.primary,
        }, { corner() })
        local row = { button = button }
        row.name = new("TextLabel", {
            Parent = button, ZIndex = 63, TextTruncate = Enum.TextTruncate.AtEnd,
            Size = u2(1, -14, 0, 15), Position = u2(0, 9, 0, 4),
        })
        row.meta = new("TextLabel", {
            Parent = button, ZIndex = 63, Font = MEDIUM, TextSize = 9, TextColor3 = colors.textDimmer,
            TextTruncate = Enum.TextTruncate.AtEnd, Size = u2(1, -14, 0, 11), Position = u2(0, 9, 0, 18),
        })
        onHover(button,
            function() button.BackgroundColor3 = colors.bg4 end,
            function() button.BackgroundColor3 = colors.bg3 end)
        button.MouseButton1Click:Connect(function()
            if row.entry then goToFeature(row.entry) end
        end)
        rows[i] = row
        return row
    end
    local function doSearch(query)
        query = query:lower():match("^%s*(.-)%s*$")
        local count = 0
        if query ~= "" then
            for _, entry in ipairs(self._searchIndex) do
                if entry.frame.Parent and entry.lname:find(query, 1, true) then
                    count = count + 1
                    local row = getRow(count)
                    row.entry = entry
                    row.name.Text = entry.name
                    row.meta.Text = entry.sectionTitle ~= "" and (entry.pageName .. " • " .. entry.sectionTitle) or entry.pageName
                    row.button.LayoutOrder = count
                    row.button.BackgroundColor3 = colors.bg3
                    row.button.Visible = true
                end
            end
        end
        for i = count + 1, #rows do
            rows[i].button.Visible = false
            rows[i].entry = nil
        end
        emptyLabel.Visible = count == 0
        local contentH = count * ROW_H + math.max(0, count - 1) * ROW_GAP + LIST_PAD * 2
        panel.Size = u2(0, SEARCH_W, 0, count == 0 and (ROW_H + LIST_PAD * 2) or math.min(contentH, MAX_PANEL_H))
        panel.Visible = query ~= ""
    end
    local searchThread
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local text = searchBox.Text
        cancelThread(searchThread)
        searchThread = nil
        clearBtn.Visible = text ~= ""
        if text == "" then return doSearch("") end
        searchThread = task.delay(0.1, function()
            searchThread = nil
            doSearch(text)
        end)
    end)
    searchBox.Focused:Connect(function()
        searchStroke.Color, searchStroke.Transparency = colors.primary, 0.1
    end)
    searchBox.FocusLost:Connect(function()
        searchStroke.Color, searchStroke.Transparency = colors.border, 0.4
    end)
    clearBtn.MouseButton1Click:Connect(function() searchBox.Text = "" end)
    onHover(clearBtn,
        function() clearBtn.TextColor3 = colors.primary end,
        function() clearBtn.TextColor3 = colors.textDimmer end)
end
function Library:CreatePage(name, title, imageId, order)
    if self.pages[name] then
        warn(("[LynxGUI] Nama tab duplikat -> '%s'. Tab lama akan tertimpa; pakai nama tab yang unik."):format(tostring(name)))
    end
    local page = new("Frame", {
        Parent = self._pageParking, ZIndex = 5, Visible = false, ClipsDescendants = true, BackgroundTransparency = 1,
        Size = u2(1, -12, 1, -(TOPBAR_H + 10)), Position = u2(0, 6, 0, TOPBAR_H + 6),
    })
    local content = new("ScrollingFrame", {
        Parent = page, ZIndex = 5, Size = u2(1, 0, 1, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
    }, {
        new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
        new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingRight = UDim.new(0, 4) }),
    })
    self.pages[name] = { frame = page, title = title, content = content }
    local btn = new("TextButton", {
        Parent = self._navContainer, ZIndex = 6, LayoutOrder = order or 999,
        Size = u2(1, 0, 0, 28), BackgroundColor3 = colors.bg2, BackgroundTransparency = 1,
    }, { corner(5) })
    self._navButtons[name] = {
        btn = btn,
        indicator = new("Frame", {
            Parent = btn, ZIndex = 7, Visible = false, Size = u2(0, 3, 0, 16), Position = u2(0, 0, 0.5, -8),
            BackgroundColor3 = colors.primary,
        }, { corner() }),
        icon = new("ImageLabel", {
            Parent = btn, ZIndex = 7, Image = imageId or "", ImageColor3 = colors.textDim,
            Size = u2(0, 15, 0, 15), Position = u2(0, 8, 0.5, -7),
        }),
        label = new("TextLabel", {
            Parent = btn, ZIndex = 7, Text = name, TextSize = FONT.normal, TextColor3 = colors.textDim,
            Size = u2(1, -35, 1, 0), Position = u2(0, 28, 0, 0),
        }),
    }
    btn.MouseButton1Click:Connect(function() self:_switchPage(name) end)
    return content
end
function Library:SetFirstPage(name, title)
    if title and self.pages[name] then self.pages[name].title = title end
    self:_switchPage(name)
end
function Library:_switchPage(name)
    if self._currentPage == name or not self.pages[name] then return end
    self._currentPage = name
    for pageName, page in pairs(self.pages) do
        local active = pageName == name
        page.frame.Visible = active
        page.frame.Parent = active and self._contentBg or self._pageParking
    end
    for pageName, nav in pairs(self._navButtons) do
        local active = pageName == name
        nav.btn.BackgroundTransparency = active and SECTION_T or 1
        nav.icon.ImageColor3 = active and colors.primary or colors.textDim
        nav.label.TextColor3 = active and colors.text or colors.textDim
        nav.indicator.Visible = active
    end
    self._pageTitle.Text = self.pages[name].title or name
end
function Library:CreateCategory(parent, title, startOpen)
    local frame = new("Frame", {
        Parent = parent, ZIndex = 6, Size = u2(1, 0, 0, SECTION_H),
        BackgroundColor3 = colors.bg2, BackgroundTransparency = SECTION_T,
    }, { corner(4), new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })
    local header = new("TextButton", { Parent = frame, ZIndex = 7, LayoutOrder = 1, Size = u2(1, 0, 0, SECTION_H) })
    new("TextLabel", {
        Parent = header, ZIndex = 8, Text = title, TextSize = FONT.normal,
        Size = u2(1, -32, 1, 0), Position = u2(0, 10, 0, 0),
    })
    local arrow = new("TextLabel", {
        Parent = header, ZIndex = 8, Text = "▼", TextColor3 = colors.primary,
        TextXAlignment = Enum.TextXAlignment.Center, Size = u2(0, 18, 1, 0), Position = u2(1, -24, 0, 0),
    })
    local layout = new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder })
    local content = new("Frame", {
        Parent = frame, ZIndex = 7, LayoutOrder = 2, BackgroundTransparency = 1,
        Size = u2(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
    }, {
        new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 6) }),
        layout,
    })
    local isOpen = startOpen == true
    local function updateHeight()
        local h = isOpen and (SECTION_H + layout.AbsoluteContentSize.Y + 6) or SECTION_H
        frame.Size = u2(1, 0, 0, h)
    end
    local function setOpen(state)
        isOpen = state
        content.Visible = state
        arrow.Text = state and "▲" or "▼"
        updateHeight()
    end
    setOpen(isOpen)
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateHeight)
    header.MouseButton1Click:Connect(function() setOpen(not isOpen) end)
    return content, function()
        if not isOpen then setOpen(true) end
    end
end
function Library:CreateToggle(parent, label, configPath, callback, disableSave, defaultValue)
    local path = not disableSave and configPath or nil
    local flagKey = configPath or label
    local frame = new("Frame", { Parent = parent, ZIndex = 7, Size = u2(1, 0, 0, 28), BackgroundTransparency = 1 })
    new("TextLabel", { Parent = frame, ZIndex = 8, Text = label, Size = u2(1, -45, 1, 0) })
    local track = new("Frame", {
        Parent = frame, ZIndex = 8, Size = u2(0, 34, 0, 18), Position = u2(1, -34, 0.5, -9),
        BackgroundColor3 = colors.bg3,
    }, { corner() })
    local knob = new("Frame", {
        Parent = track, ZIndex = 9, Size = u2(0, 14, 0, 14), Position = u2(0, 2, 0.5, -7),
        BackgroundColor3 = colors.textDim,
    }, { corner() })
    local button = new("TextButton", { Parent = track, ZIndex = 10, Size = u2(1, 0, 1, 0) })
    local on = Config.Get(path, defaultValue or false)
    local function apply(value)
        on = value == true
        track.BackgroundColor3 = on and colors.primary or colors.bg3
        knob.Position = on and u2(1, -16, 0.5, -7) or u2(0, 2, 0.5, -7)
        knob.BackgroundColor3 = on and colors.text or colors.textDim
        self.flags[flagKey] = on
    end
    apply(on)
    button.MouseButton1Click:Connect(function()
        apply(not on)
        saveValue(path, on)
        fireCallback("toggle '" .. tostring(label) .. "'", callback, on)
    end)
    registerCallback(path, callback, "toggle", defaultValue or false, apply)
    return {
        frame = frame,
        set = function(value)
            apply(value)
            saveValue(path, on)
        end,
        get = function() return on end,
    }
end
function Library:_initDropdownSystem()
    if self._dropdown then return self._dropdown end
    local overlay = new("Frame", {
        Parent = self._win, Name = "DropdownOverlay", ZIndex = 150, Visible = false, ClipsDescendants = true,
        Size = u2(1, 0, 1, -HEADER_H), Position = u2(0, 0, 0, HEADER_H),
        BackgroundColor3 = colors.bg1, BackgroundTransparency = 0.95,
    })
    local closer = new("TextButton", { Parent = overlay, ZIndex = 151, Size = u2(1, 0, 1, 0) })
    local panel = new("Frame", {
        Parent = overlay, Name = "DropdownPanel", ZIndex = 152, ClipsDescendants = true, AnchorPoint = v2(1, 0.5),
        Size = u2(0, 160, 1, -16), Position = u2(1, -11, 0.5, 0),
        BackgroundColor3 = colors.bg2, BackgroundTransparency = 0.09,
    }, { corner(6), stroke(nil, 0.45) })
    closer.Activated:Connect(function() self:_hideDropdown() end)
    self._dropdown = { overlay = overlay, panel = panel }
    return self._dropdown
end
function Library:_showDropdown(container)
    local dropdown = self:_initDropdownSystem()
    if self._openDropdown and self._openDropdown ~= container then
        self._openDropdown.Visible = false
        self._openDropdown.Parent = self._dropParking
    end
    self._openDropdown = container
    container.Parent = dropdown.panel
    container.Visible = true
    dropdown.overlay.Visible = true
end
function Library:_hideDropdown()
    if self._openDropdown then
        self._openDropdown.Visible = false
        self._openDropdown.Parent = self._dropParking
    end
    self._openDropdown = nil
    if self._dropdown then self._dropdown.overlay.Visible = false end
end
local function normalizeOption(opt)
    local label, value = tostring(opt), opt
    if type(opt) == "table" and opt.Label and opt.Value ~= nil then
        label, value = tostring(opt.Label), opt.Value
    end
    return { label = label, value = value, lower = label:lower() }
end
function Library:_createBaseDropdown(parent, title, _imageId, items, configPath, onSelect, uniqueId, defaultValue, isMulti)
    local dropdown = self:_initDropdownSystem()
    local ROW_H, ROW_GAP, MIN_POOL, MAX_POOL, MAX_LABELS = 26, 3, 12, 48, 3
    local ROW_STRIDE = ROW_H + ROW_GAP
    local defaultText = isMulti and "Select Options" or "Select Option"
    local frame = new("Frame", {
        Parent = parent, Name = uniqueId or (isMulti and "MultiDropdown" or "Dropdown"), ZIndex = 7,
        Size = u2(1, 0, 0, 28), BackgroundTransparency = 1,
    })
    new("TextLabel", {
        Parent = frame, ZIndex = 8, Text = title or (isMulti and "Multi Select" or "Dropdown"), Size = u2(0.5, 0, 1, 0),
    })
    local selectFrame = new("Frame", {
        Parent = frame, ZIndex = 8, AnchorPoint = v2(1, 0.5), Position = u2(1, 0, 0.5, 0), Size = u2(0.48, 0, 0, 22),
        BackgroundColor3 = colors.bg2, BackgroundTransparency = SECTION_T,
    }, { corner(4), stroke(nil, 0.5) })
    local selectedLabel = new("TextLabel", {
        Parent = selectFrame, ZIndex = 9, Text = defaultText, TextColor3 = colors.textDim,
        TextTruncate = Enum.TextTruncate.AtEnd, AnchorPoint = v2(0, 0.5), Position = u2(0, 8, 0.5, 0), Size = u2(1, -24, 1, 0),
    })
    new("ImageLabel", {
        Parent = selectFrame, ZIndex = 9, Image = "rbxassetid://6031091004", ImageColor3 = colors.primary,
        AnchorPoint = v2(1, 0.5), Position = u2(1, -6, 0.5, 0), Size = u2(0, 11, 0, 11),
    })
    local openButton = new("TextButton", { Parent = frame, ZIndex = 10, Size = u2(1, 0, 1, 0) })
    local container = new("Frame", { Parent = self._dropParking, ZIndex = 153, Visible = false, Size = u2(1, 0, 1, 0), BackgroundTransparency = 1 })
    local searchBox = new("TextBox", {
        Parent = container, ZIndex = 154, PlaceholderText = "Search...",
        Size = u2(1, -8, 0, 24), Position = u2(0, 4, 0, 4),
        BackgroundColor3 = colors.bg2, BackgroundTransparency = SECTION_T,
    }, { corner(4), stroke(nil, 0.5), new("UIPadding", { PaddingLeft = UDim.new(0, 8) }) })
    local scroll = new("ScrollingFrame", {
        Parent = container, ZIndex = 154, Size = u2(1, -8, 1, -36), Position = u2(0, 4, 0, 32),
    })
    local function copyValue(v)
        if not isMulti then return v end
        local out = {}
        if type(v) == "table" then
            for i = 1, #v do out[i] = v[i] end
        end
        return out
    end
    local DropdownFunc = { Value = copyValue(Config.Get(configPath, defaultValue)), Options = items or {} }
    local allOptions, filtered, selectedSet, labelByValue = {}, {}, {}, {}
    local rows, lastCanvasH, needsRefresh, searchThread, viewH = {}, nil, false, nil, 0
    local function isOpen() return self._openDropdown == container end
    local function emit(value)
        if not onSelect then return end
        if isMulti then
            fireCallback("dropdown '" .. tostring(title) .. "'", onSelect, copyValue(value))
        else
            fireCallback("dropdown '" .. tostring(title) .. "'", onSelect, value ~= nil and tostring(value) or "")
        end
    end
    local function setOptions(list)
        DropdownFunc.Options = table.clone(type(list) == "table" and list or {})
        table.clear(allOptions)
        table.clear(labelByValue)
        for _, opt in ipairs(DropdownFunc.Options) do
            local option = normalizeOption(opt)
            allOptions[#allOptions + 1] = option
            if labelByValue[option.value] == nil then labelByValue[option.value] = option.label end
        end
    end
    local function applyFilter()
        local query = searchBox.Text:lower()
        table.clear(filtered)
        for _, opt in ipairs(allOptions) do
            if query == "" or opt.lower:find(query, 1, true) then filtered[#filtered + 1] = opt end
        end
    end
    local function updateSelection()
        table.clear(selectedSet)
        if isMulti then
            for _, v in ipairs(DropdownFunc.Value) do selectedSet[v] = true end
        elseif DropdownFunc.Value ~= nil then
            selectedSet[DropdownFunc.Value] = true
        end
        local text
        if isMulti then
            local labels, count = {}, 0
            for _, v in ipairs(DropdownFunc.Value) do
                if labelByValue[v] then
                    count = count + 1
                    if count <= MAX_LABELS then labels[count] = labelByValue[v] end
                end
            end
            if count > 0 then
                text = table.concat(labels, ", ") .. (count > MAX_LABELS and (" (+%d)"):format(count - MAX_LABELS) or "")
            end
        elseif DropdownFunc.Value ~= nil then
            text = labelByValue[DropdownFunc.Value] or tostring(DropdownFunc.Value)
        end
        selectedLabel.Text = text or defaultText
    end
    local function paintRow(row, opt, force)
        local selected = selectedSet[opt.value] == true
        if not force and row.opt == opt and row.selected == selected then return end
        row.opt, row.selected = opt, selected
        row.choose.Size = selected and u2(0, 3, 0, 16) or u2(0, 0, 0, 0)
        row.frame.BackgroundColor3 = selected and colors.bg3 or colors.bg2
        row.frame.BackgroundTransparency = selected and PANEL_T or 0.5
        row.text.TextColor3 = selected and colors.text or colors.textDim
        row.text.Text = opt.label
    end
    local function onRowClick(row)
        local opt = row.index and filtered[row.index]
        if not opt then return end
        if not isMulti then return DropdownFunc:Set(opt.value) end
        local newList, removed = {}, false
        for _, v in ipairs(DropdownFunc.Value) do
            if v == opt.value then removed = true else newList[#newList + 1] = v end
        end
        if not removed then newList[#newList + 1] = opt.value end
        DropdownFunc:Set(newList)
    end
    local function buildRow()
        local rowFrame = new("Frame", {
            Parent = scroll, ZIndex = 155, Visible = false, Size = u2(1, 0, 0, ROW_H),
            BackgroundColor3 = colors.bg2, BackgroundTransparency = 0.5,
        }, { corner(3) })
        local row = {
            frame = rowFrame,
            text = new("TextLabel", {
                Parent = rowFrame, ZIndex = 156, TextTruncate = Enum.TextTruncate.AtEnd,
                Size = u2(1, -16, 1, 0), Position = u2(0, 8, 0, 0),
            }),
            choose = new("Frame", {
                Parent = rowFrame, ZIndex = 156, AnchorPoint = v2(0, 0.5), Position = u2(0, 2, 0.5, 0),
                Size = u2(0, 0, 0, 0), BackgroundColor3 = colors.primary,
            }, { corner(3) }),
        }
        local button = new("TextButton", { Parent = rowFrame, ZIndex = 157, Size = u2(1, 0, 1, 0) })
        onHover(rowFrame, function()
            if row.index then rowFrame.BackgroundColor3 = colors.bg4 end
        end, function()
            if row.opt then paintRow(row, row.opt, true) end
        end)
        button.Activated:Connect(function() onRowClick(row) end)
        rows[#rows + 1] = row
    end
    local function refreshVisible()
        if #rows == 0 then return end
        if viewH <= 0 then viewH = scroll.AbsoluteSize.Y end
        if viewH <= 0 then
            needsRefresh = true
            return
        end
        needsRefresh = false
        local total = #filtered
        local canvasH = math.max(0, total * ROW_STRIDE - ROW_GAP)
        if lastCanvasH ~= canvasH then
            lastCanvasH = canvasH
            scroll.CanvasSize = u2(0, 0, 0, canvasH)
        end
        local first = math.max(1, math.floor(scroll.CanvasPosition.Y / ROW_STRIDE) + 1)
        local capacity = math.min(math.floor(viewH / ROW_STRIDE) + 2, MAX_POOL)
        while #rows < capacity do buildRow() end
        local last = math.min(total, first + capacity - 1)
        for i, row in ipairs(rows) do
            local index = first + i - 1
            local visible = index <= last
            row.index = visible and index or nil
            if visible then
                local y = (index - 1) * ROW_STRIDE
                if row.y ~= y then
                    row.y = y
                    row.frame.Position = u2(0, 0, 0, y)
                end
                paintRow(row, filtered[index])
            end
            if row.visible ~= visible then
                row.visible = visible
                row.frame.Visible = visible
            end
        end
    end
    local function ensureRows()
        if #rows > 0 then return end
        viewH = scroll.AbsoluteSize.Y
        local count = viewH > 0 and math.max(MIN_POOL, math.floor(viewH / ROW_STRIDE) + 2) or MIN_POOL
        for _ = 1, math.min(count, MAX_POOL) do buildRow() end
        scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshVisible)
        scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            viewH = scroll.AbsoluteSize.Y
            if isOpen() then refreshVisible() end
        end)
    end
    local function refresh()
        updateSelection()
        if isOpen() then refreshVisible() end
    end
    function DropdownFunc:Set(value)
        DropdownFunc.Value = copyValue(value)
        saveValue(configPath, copyValue(DropdownFunc.Value))
        refresh()
        emit(DropdownFunc.Value)
    end
    function DropdownFunc:SetValue(value) DropdownFunc:Set(value) end
    function DropdownFunc:GetValue() return copyValue(DropdownFunc.Value) end
    function DropdownFunc:Clear()
        setOptions({})
        DropdownFunc.Value = copyValue(nil)
        applyFilter()
        scroll.CanvasPosition = v2(0, 0)
        refresh()
    end
    function DropdownFunc:AddOption(opt)
        local option = normalizeOption(opt)
        local query = searchBox.Text:lower()
        table.insert(DropdownFunc.Options, opt)
        allOptions[#allOptions + 1] = option
        if labelByValue[option.value] == nil then labelByValue[option.value] = option.label end
        if query == "" or option.lower:find(query, 1, true) then filtered[#filtered + 1] = option end
        refresh()
    end
    function DropdownFunc:SetValues(list, selecting)
        setOptions(list)
        DropdownFunc.Value = copyValue(selecting)
        saveValue(configPath, copyValue(DropdownFunc.Value))
        applyFilter()
        scroll.CanvasPosition = v2(0, 0)
        refresh()
        emit(DropdownFunc.Value)
    end
    function DropdownFunc:Refresh(list)
        setOptions(list)
        if isMulti then
            local valid = {}
            for _, v in ipairs(DropdownFunc.Value) do
                if labelByValue[v] ~= nil then valid[#valid + 1] = v end
            end
            DropdownFunc.Value = valid
        elseif DropdownFunc.Value ~= nil and labelByValue[DropdownFunc.Value] == nil then
            DropdownFunc.Value = nil
        end
        saveValue(configPath, copyValue(DropdownFunc.Value))
        applyFilter()
        refresh()
    end
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        cancelThread(searchThread)
        searchThread = task.delay(searchBox.Text == "" and 0 or 0.08, function()
            searchThread = nil
            applyFilter()
            scroll.CanvasPosition = v2(0, 0)
            refreshVisible()
        end)
    end)
    openButton.Activated:Connect(function()
        ensureRows()
        searchBox.Text = ""
        applyFilter()
        scroll.CanvasPosition = v2(0, 0)
        self:_showDropdown(container)
        task.defer(function()
            refreshVisible()
            if needsRefresh then task.defer(refreshVisible) end
        end)
    end)
    setOptions(items)
    applyFilter()
    updateSelection()
    registerCallback(configPath, onSelect and emit, isMulti and "multidropdown" or "dropdown",
        isMulti and (defaultValue or {}) or defaultValue,
        function(value)
            DropdownFunc.Value = copyValue(value)
            refresh()
        end)
    if uniqueId then self.flags[uniqueId] = DropdownFunc end
    return frame
end
function Library:CreateDropdown(parent, title, imageId, items, configPath, onSelect, uniqueId, defaultValue)
    return self:_createBaseDropdown(parent, title, imageId, items, configPath, onSelect, uniqueId, defaultValue, false)
end
function Library:CreateMultiDropdown(parent, title, imageId, items, configPath, onSelect, uniqueId, defaultValues)
    return self:_createBaseDropdown(parent, title, imageId, items, configPath, onSelect, uniqueId, defaultValues, true)
end
local function resolveInput(text)
    text = text == nil and "" or tostring(text)
    if #text > 15 and text:match("^%d+$") then return text end
    local number = tonumber(text)
    if number and number == number and math.abs(number) ~= math.huge then return number end
    return text
end
function Library:CreateInput(parent, label, configPath, defaultValue, callback, placeholder)
    local frame = new("Frame", { Parent = parent, ZIndex = 7, Size = u2(1, 0, 0, 28), BackgroundTransparency = 1 })
    new("TextLabel", { Parent = frame, ZIndex = 8, Text = label, Size = u2(0.52, 0, 1, 0) })
    local box = new("Frame", {
        Parent = frame, ZIndex = 8, Size = u2(0.45, 0, 0, 24), Position = u2(0.55, 0, 0.5, -12),
        BackgroundColor3 = colors.bg3, BackgroundTransparency = PANEL_T,
    }, { corner(4) })
    local initial = Config.Get(configPath, defaultValue)
    local textBox = new("TextBox", {
        Parent = box, ZIndex = 9, TextTruncate = Enum.TextTruncate.AtEnd,
        Text = initial ~= nil and tostring(initial) or "",
        PlaceholderText = (placeholder and placeholder ~= "") and tostring(placeholder) or "Enter Value",
        Size = u2(1, -16, 1, 0), Position = u2(0, 8, 0, 0),
    })
    local context = "input '" .. tostring(label) .. "'"
    local function commit(raw)
        local value = resolveInput(raw)
        textBox.Text = tostring(value)
        saveValue(configPath, value)
        fireCallback(context, callback, value)
    end
    textBox.FocusLost:Connect(function() commit(textBox.Text) end)
    if configPath then
        registerCallback(configPath, callback and function(value)
            callback(resolveInput(value))
        end, "input", defaultValue, function(value)
            if value == nil then value = defaultValue end
            textBox.Text = value ~= nil and tostring(value) or ""
        end)
    else
        fireCallback(context, callback, resolveInput(initial))
    end
    return {
        frame = frame,
        set = commit,
        get = function() return resolveInput(textBox.Text) end,
    }
end
function Library:CreateButton(parent, label, callback)
    local frame = new("Frame", { Parent = parent, ZIndex = 8, Size = u2(1, 0, 0, 28), BackgroundTransparency = 1 })
    local button = new("TextButton", {
        Parent = frame, ZIndex = 9, Text = label, TextSize = FONT.normal, AutoButtonColor = true,
        Size = u2(1, 0, 1, 0), BackgroundColor3 = colors.bg3, BackgroundTransparency = PANEL_T,
    }, { corner(5) })
    local busy = false
    button.MouseButton1Click:Connect(function()
        if busy then return end
        busy = true
        fireCallback("button '" .. tostring(label) .. "'", callback)
        task.delay(0.1, function() busy = false end)
    end)
    return frame
end
function Library:CreateParagraph(parent, config)
    local GAP, PADDING_V = 6, 20
    local frame = new("Frame", {
        Parent = parent, ZIndex = 7, Size = u2(1, 0, 0, PADDING_V),
        BackgroundColor3 = colors.bg2, BackgroundTransparency = 0.5,
    }, {
        corner(5), stroke(nil, 0.65),
        new("UIPadding", {
            PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
            PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
        }),
        new("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder }),
    })
    local function makeLabel(order, font, size, color, minHeight)
        return new("TextLabel", {
            Parent = frame, ZIndex = 8, LayoutOrder = order, Font = font, TextSize = size, TextColor3 = color,
            TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, RichText = config.RichText ~= false,
            Size = u2(1, 0, 0, minHeight),
        })
    end
    local titleLabel = makeLabel(1, BOLD, FONT.normal, colors.primary, 14)
    local contentLabel = makeLabel(2, MEDIUM, FONT.small, colors.textDim, 12)
    local minHeights = { [titleLabel] = 14, [contentLabel] = 12 }
    local pending = false
    local function reflow()
        if pending then return end
        pending = true
        task.defer(function()
            pending = false
            if not frame.Parent then return end
            local total, shown = PADDING_V, 0
            for _, lbl in ipairs({ titleLabel, contentLabel }) do
                if lbl.Visible then
                    local h = math.max(lbl.TextBounds.Y, minHeights[lbl])
                    lbl.Size = u2(1, 0, 0, h)
                    total = total + h
                    shown = shown + 1
                end
            end
            frame.Size = u2(1, 0, 0, total + math.max(0, shown - 1) * GAP)
        end)
    end
    local function setText(lbl, text)
        lbl.Text = formatRichText(text)
        lbl.Visible = lbl.Text ~= ""
        reflow()
    end
    titleLabel:GetPropertyChangedSignal("TextBounds"):Connect(reflow)
    contentLabel:GetPropertyChangedSignal("TextBounds"):Connect(reflow)
    setText(titleLabel, config.Title)
    setText(contentLabel, config.Content)
    return {
        _frame = frame,
        _titleLabel = titleLabel,
        _contentLabel = contentLabel,
        SetTitle = function(_, text) setText(titleLabel, text) end,
        SetContent = function(_, text) setText(contentLabel, text) end,
        GetTitle = function() return titleLabel.Text end,
        GetContent = function() return contentLabel.Text end,
    }
end
function Library:Init()
    self:Initialize()
end
function Library:Initialize()
    if self._initialized then return end
    self._initialized = true
    cancelThread(self._initWatchdog)
    self._initWatchdog = nil
    if self._pendingWindow then
        safeCall("Config tab", self._createConfigTab, self, self._pendingWindow)
        self._pendingWindow = nil
    end
    pruneLegacyKeys()
    executeConfigCallbacks()
    self:AddConnection("playerRemoving", Players.PlayerRemoving:Connect(function(player)
        if player ~= Players.LocalPlayer or not isDirty then return end
        cancelThread(saveThread)
        saveThread = nil
        isDirty = false
        Config.Save()
    end))
end
local NOTIFY = {
    WIDTH = isMobile and 220 or 250, MARGIN = 14, MAX_QUEUE = 10,
    TEXT_X = 19, PAD_R = 10, PAD_Y = 8, TITLE_H = 14,
    GAP = 0.1,         
    FAST_RATE = 1.6,   
}
NOTIFY.TEXT_W = NOTIFY.WIDTH - NOTIFY.TEXT_X - NOTIFY.PAD_R
function Library:MakeNotify(config)
    config = config or {}
    if not self._gui then return end
    local delay = tonumber(config.Delay)
    if not delay or delay ~= delay then delay = 3 end   
    local item = {
        title   = tostring(config.Title or "Notification"),
        desc    = tostring(config.Description or ""),
        content = tostring(config.Content or ""),
        color   = typeof(config.Color) == "Color3" and config.Color or colors.primary,
        delay   = math.clamp(delay, 1, 60),
    }
    item.key = item.title .. "\0" .. item.desc .. "\0" .. item.content
    self._notifQueue = self._notifQueue or {}
    local queue, current = self._notifQueue, self._notifCurrent
    if current and current.key == item.key then
        current.remaining, current.tick = current.total, os.clock()
        return self:_scheduleNotify()
    end
    local last = queue[#queue]
    if last and last.key == item.key then return end
    if #queue >= NOTIFY.MAX_QUEUE then table.remove(queue, 1) end
    queue[#queue + 1] = item
    if current then
        self:_scheduleNotify()   
    else
        self:_showNextNotify()
    end
end
function Library:_resetNotify()
    self._notifGen = (self._notifGen or 0) + 1
    if self._notifQueue then table.clear(self._notifQueue) end
    local state, ui = self._notifCurrent, self._notifUI
    self._notifCurrent, self._notifUI = nil, nil
    if state then cancelThread(state.timer) end
    if ui and ui.gui.Parent then pcall(function() ui.gui:Destroy() end) end
end
function Library:_getNotifyUI()
    local ui = self._notifUI
    if ui and ui.gui.Parent then return ui end
    if not self._gui then return nil end
    local guiName = self._gui.Name .. "_Notify"
    local stale = self._guiParent:FindFirstChild(guiName)
    if stale then stale:Destroy() end
    local midY = NOTIFY.PAD_Y + NOTIFY.TITLE_H / 2
    ui = { hovered = false }
    ui.gui = new("ScreenGui", {
        Name = guiName, Parent = self._guiParent, IgnoreGuiInset = true, ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 2147483647,
    })
    ui.card = new("Frame", {
        Parent = ui.gui, Name = "Card", Active = true, Visible = false, AnchorPoint = v2(1, 1),
        Size = u2(0, NOTIFY.WIDTH, 0, 30), Position = u2(1, -NOTIFY.MARGIN, 1, -NOTIFY.MARGIN),
        BackgroundColor3 = colors.bg1, BackgroundTransparency = PANEL_T,
    }, { corner(7) })
    ui.bar = new("Frame", {
        Parent = ui.card, ZIndex = 2, AnchorPoint = v2(0, 0.5), Size = u2(0, 3, 1, -16), Position = u2(0, 8, 0.5, 0),
        BackgroundColor3 = colors.primary,
    }, { corner() })
    ui.title = new("TextLabel", {
        Parent = ui.card, ZIndex = 2, TextSize = FONT.normal, TextTruncate = Enum.TextTruncate.AtEnd,
        Size = u2(0, NOTIFY.TEXT_W - 36, 0, NOTIFY.TITLE_H), Position = u2(0, NOTIFY.TEXT_X, 0, NOTIFY.PAD_Y),
    })
    local function bodyLabel(font, color)
        return new("TextLabel", {
            Parent = ui.card, ZIndex = 2, Visible = false, Font = font, TextColor3 = color,
            TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
        })
    end
    ui.desc = bodyLabel(MEDIUM, colors.textDim)
    ui.content = bodyLabel(REGULAR, colors.textDimmer)
    ui.queueLabel = new("TextLabel", {
        Parent = ui.card, ZIndex = 2, Visible = false, TextSize = 9, TextColor3 = colors.textDimmer,
        TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = v2(1, 0.5),
        Size = u2(0, 20, 0, NOTIFY.TITLE_H), Position = u2(1, -26, 0, midY),
    })
    ui.closeBtn = new("TextButton", {
        Parent = ui.card, ZIndex = 3, Text = "×", TextSize = 14, TextColor3 = colors.textDimmer,
        AnchorPoint = v2(1, 0.5), Size = u2(0, 18, 0, 18), Position = u2(1, -6, 0, midY),
    })
    onHover(ui.card, function()
        ui.hovered = true
        self:_scheduleNotify()
    end, function()
        if not ui.hovered then return end
        ui.hovered = false
        self:_scheduleNotify()
    end)
    ui.closeBtn.MouseButton1Click:Connect(function() self:_hideNotify() end)
    onHover(ui.closeBtn,
        function() ui.closeBtn.TextColor3 = colors.text end,
        function() ui.closeBtn.TextColor3 = colors.textDimmer end)
    ui.gui.Destroying:Connect(function()
        if self._notifUI == ui then self:_resetNotify() end
    end)
    self._notifUI = ui
    return ui
end
function Library:_showNextNotify()
    local queue = self._notifQueue
    if self._notifCurrent or not queue or #queue == 0 then return end
    local ui = self:_getNotifyUI()
    if not ui then return table.clear(queue) end
    local item = table.remove(queue, 1)
    local y = NOTIFY.PAD_Y + NOTIFY.TITLE_H
    local function placeBody(lbl, text, font)
        local h = textHeight(text, FONT.small, font, NOTIFY.TEXT_W)
        lbl.Visible = h > 0
        if h == 0 then return end
        lbl.Text = text
        lbl.Size = u2(0, NOTIFY.TEXT_W, 0, h)
        lbl.Position = u2(0, NOTIFY.TEXT_X, 0, y + 2)
        y = y + 2 + h
    end
    ui.title.Text = item.title
    ui.bar.BackgroundColor3 = item.color
    placeBody(ui.desc, item.desc, MEDIUM)
    placeBody(ui.content, item.content, REGULAR)
    ui.card.Size = u2(0, NOTIFY.WIDTH, 0, y + NOTIFY.PAD_Y)
    ui.queueLabel.Visible = false
    ui.hovered = false
    ui.closeBtn.TextColor3 = colors.textDimmer
    self._notifCurrent = { key = item.key, total = item.delay, remaining = item.delay, rate = 0, tick = os.clock() }
    ui.card.Visible = true
    self:_scheduleNotify()
end
function Library:_scheduleNotify()
    local state, ui = self._notifCurrent, self._notifUI
    if not state or not ui then return end
    local now = os.clock()
    state.remaining = state.remaining - (now - state.tick) * state.rate
    state.tick = now
    cancelThread(state.timer)
    state.timer = nil
    local pending = self._notifQueue and #self._notifQueue or 0
    ui.queueLabel.Text = "+" .. pending
    ui.queueLabel.Visible = pending > 0
    if state.remaining <= 0 then return self:_hideNotify() end
    state.rate = ui.hovered and 0 or (pending > 0 and NOTIFY.FAST_RATE or 1)
    if state.rate == 0 then return end
    state.timer = task.delay(state.remaining / state.rate, function()
        state.timer = nil
        if self._notifCurrent == state then self:_hideNotify() end
    end)
end
function Library:_hideNotify()
    local state = self._notifCurrent
    if not state then return end
    self._notifCurrent = nil
    cancelThread(state.timer)
    local ui = self._notifUI
    if ui and ui.gui.Parent then ui.card.Visible = false end
    local gen = self._notifGen
    task.delay(NOTIFY.GAP, function()
        if self._notifGen == gen then self:_showNextNotify() end
    end)
end
local function addConfirmButton(section, title, confirmColor, onConfirm)
    local frame, timeout
    local function restore()
        cancelThread(timeout)
        timeout = nil
        local button = frame:FindFirstChildWhichIsA("TextButton")
        button.Text, button.BackgroundColor3 = title, colors.bg3
    end
    frame = section:AddButton({
        Title = title,
        Callback = function()
            if timeout then
                restore()
                return onConfirm()
            end
            local button = frame:FindFirstChildWhichIsA("TextButton")
            button.Text, button.BackgroundColor3 = "Klik lagi untuk konfirmasi!", confirmColor
            timeout = task.delay(3, function()
                timeout = nil
                restore()
            end)
        end,
    })
end
function Library:_createConfigTab(window)
    local tab = window:AddTab({ Name = "Config", Icon = "loop" })
    tab:AddSection("Auto Save"):AddToggle({
        Title = "Auto Save Config",
        Default = true,
        NoSave = true,
        Callback = function(on)
            _G.AutoSaveEnabled = on
            self:MakeNotify({ Title = "Auto Save", Description = on and "Auto Save diaktifkan" or "Auto Save dinonaktifkan", Delay = 2 })
        end,
    })
    local section = tab:AddSection("Config Management")
    section:AddButton({
        Title = "Save Config Now",
        Callback = function()
            local ok = Config.Save()
            self:MakeNotify({
                Title = "Config",
                Description = ok and "Config berhasil disimpan!" or "Gagal menyimpan config.",
                Color = ok and colors.success or colors.danger,
                Delay = 2,
            })
        end,
    })
    addConfirmButton(section, "Reset to Default", rgb(255, 100, 0), function()
        Config.Reset()
        executeConfigCallbacks()
        self:MakeNotify({ Title = "Config", Description = "Semua settingan direset ke default!", Color = colors.danger })
    end)
    section:AddParagraph({
        Title = "⚠️ Perhatian",
        Content = "Setelah melakukan Reset to Default, beberapa settingan seperti Toggle dan nilai Input akan langsung ter-update di UI.\n\n"
            .. "Namun untuk settingan yang mempengaruhi karakter, kecepatan, atau fitur aktif lainnya — kamu perlu Rejoin / Respawn agar perubahan berlaku sepenuhnya.\n\n"
            .. "File config disimpan otomatis setiap 2 detik jika Auto Save aktif. Pastikan Auto Save ON sebelum keluar game agar settinganmu tidak hilang.\n\n"
            .. "Setiap game punya file config sendiri. Game ini: " .. Config.GetFileName(),
    })
    addConfirmButton(section, "Delete Config File", rgb(200, 30, 30), function()
        Config.Delete()
        self:MakeNotify({ Title = "Config", Description = "File config telah dihapus.", Color = colors.danger, Delay = 2 })
    end)
end
local ICONS = {
    player    = "rbxassetid://12120698352",
    web       = "rbxassetid://137601480983962",
    bag       = "rbxassetid://8601111810",
    shop      = "rbxassetid://4985385964",
    cart      = "rbxassetid://128874923961846",
    plug      = "rbxassetid://137601480983962",
    settings  = "rbxassetid://70386228443175",
    loop      = "rbxassetid://122032243989747",
    gps       = "rbxassetid://78381660144034",
    compas    = "rbxassetid://125300760963399",
    gamepad   = "rbxassetid://84173963561612",
    boss      = "rbxassetid://13132186360",
    scroll    = "rbxassetid://114127804740858",
    menu      = "rbxassetid://6340513838",
    crosshair = "rbxassetid://12614416478",
    user      = "rbxassetid://108483430622128",
    stat      = "rbxassetid://12094445329",
    eyes      = "rbxassetid://14321059114",
    sword     = "rbxassetid://82472368671405",
    discord   = "rbxassetid://94434236999817",
    star      = "rbxassetid://107005941750079",
    skeleton  = "rbxassetid://17313330026",
    payment   = "rbxassetid://18747025078",
    scan      = "rbxassetid://109869955247116",
    alert     = "rbxassetid://73186275216515",
    question  = "rbxassetid://17510196486",
    idea      = "rbxassetid://16833255748",
    strom     = "rbxassetid://13321880293",
    water     = "rbxassetid://100076212630732",
    dcs       = "rbxassetid://15310731934",
    start     = "rbxassetid://108886429866687",
    next      = "rbxassetid://12662718374",
    rod       = "rbxassetid://103247953194129",
    fish      = "rbxassetid://97167558235554",
    send      = "rbxassetid://122775063389583",
    home      = "rbxassetid://86450224791749",
}
local function configPath(prefix, title)
    local path = prefix .. toKey(title)
    local legacy = prefix .. tostring(title):gsub("%s+", "_")
    if legacy ~= path and Config.Get(path) == nil and Config.Get(legacy) ~= nil then
        Config.Set(path, Config.Get(legacy))
    end
    return path
end
local function createSection(lib, page, tabName, sectionTitle, isOpen)
    local container, expand = lib:CreateCategory(page, sectionTitle, isOpen)
    local Section = { _container = container, _library = lib, _layoutOrder = 0 }
    local function place(frame, name)
        Section._layoutOrder = Section._layoutOrder + 1
        frame.LayoutOrder = Section._layoutOrder
        if name then
            table.insert(lib._searchIndex, {
                name = tostring(name), lname = tostring(name):lower(), frame = frame,
                pageName = tabName, sectionTitle = sectionTitle, expand = expand,
            })
        end
    end
    function Section:AddToggle(cfg)
        cfg = cfg or {}
        local title, callback = cfg.Title or "Toggle", cfg.Callback
        local path = not cfg.NoSave and configPath("Toggles.", title) or nil
        local toggle = lib:CreateToggle(container, title, path, callback, cfg.NoSave, cfg.Default or false)
        place(toggle.frame, title)
        return {
            SetValue = function(_, value)
                toggle.set(value)
                fireCallback("toggle '" .. tostring(title) .. "'", callback, toggle.get())
            end,
            GetValue = function() return toggle.get() end,
        }
    end
    function Section:AddDropdown(cfg)
        cfg = cfg or {}
        local title, options = cfg.Title or "Dropdown", cfg.Options or {}
        local id = toKey(title)
        local path = not cfg.NoSave and configPath(cfg.Multi and "MultiDropdowns." or "Dropdowns.", title) or nil
        local frame = lib:_createBaseDropdown(container, title, nil, options, path, cfg.Callback, id, cfg.Default, cfg.Multi == true)
        place(frame, title)
        local dropdown = lib.flags[id]
        return {
            _options = options,
            Value = dropdown:GetValue(),
            SetOptions = function(self, list)
                self._options = list
                dropdown:Refresh(list)
            end,
            GetOptions = function(self) return self._options end,
            SetValue = function(self, value)
                dropdown:SetValue(value)
                self.Value = dropdown:GetValue()
            end,
            GetValue = function() return dropdown:GetValue() end,
        }
    end
    function Section:AddInput(cfg)
        cfg = cfg or {}
        local title = cfg.Title or "Input"
        local path = not cfg.NoSave and configPath("Inputs.", title) or nil
        local input = lib:CreateInput(container, title, path, cfg.Default or "", cfg.Callback, cfg.Placeholder)
        place(input.frame, title)
        return {
            _frame = input.frame,
            SetValue = function(_, value) input.set(value) end,
            GetValue = function() return input.get() end,
        }
    end
    function Section:AddButton(cfg)
        cfg = cfg or {}
        local title = cfg.Title or "Button"
        local frame = lib:CreateButton(container, title, cfg.Callback)
        place(frame, title)
        return frame
    end
    function Section:AddParagraph(cfg)
        local paragraph = lib:CreateParagraph(container, cfg or {})
        place(paragraph._frame)
        return paragraph
    end
    return Section
end
function Library:Window(config)
    config = config or {}
    self:CreateWindow({ Name = "LynxGui", Title = config.Title or "LynX", Subtitle = config.Footer or "" })
    if config.ConfigId ~= nil then Config.SetConfigId(config.ConfigId) end
    Config.Load()
    local lib = self
    local Window = { _library = lib, _tabs = {}, _tabOrder = 0 }
    lib._pendingWindow = Window
    lib._initWatchdog = task.delay(6, function()
        lib._initWatchdog = nil
        if not lib._initialized then
            warn("[LynxGUI] Library:Init() belum dipanggil. Tambahkan 'Library:Init()' di baris paling bawah script supaya fitur yang ON dari config benar-benar berjalan.")
        end
    end)
    function Window:AddTab(tabConfig)
        tabConfig = tabConfig or {}
        local tabName = tostring(tabConfig.Name or "Tab")
        local icon = type(tabConfig.Icon) == "string" and ICONS[tabConfig.Icon:lower()] or ""
        self._tabOrder = self._tabOrder + 1
        local page = lib:CreatePage(tabName, tabName, icon, self._tabOrder)
        local Tab = { _page = page, _library = lib, _sections = {} }
        function Tab:AddSection(sectionTitle, isOpen)
            local section = createSection(lib, page, tabName, tostring(sectionTitle or "Section"), isOpen)
            table.insert(self._sections, section)
            return section
        end
        if self._tabOrder == 1 then lib:SetFirstPage(tabName) end
        table.insert(self._tabs, Tab)
        return Tab
    end
    return Window
end
return Library
