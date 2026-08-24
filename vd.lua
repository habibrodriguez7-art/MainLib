local Library = {}
Library.flags = {}
Library.pages = {}
Library._navButtons = {}
Library._currentPage = nil
Library._gui = nil
Library._win = nil
Library._sidebar = nil
Library._contentBg = nil
Library._pageTitle = nil
Library._navContainer = nil
Library._connections = {}
Library._searchIndex = {}
Library._saveThread = nil
Library._initialized = false
local CONFIG_FOLDER    = "LynxGUI_Configs"
local CONFIG_FILE      = CONFIG_FOLDER .. "/lynx_config.json"
local CurrentConfig    = {}
local DefaultConfig    = {}
local isDirty          = false
local CallbackRegistry = {}
local Players         = game:GetService("Players")
local CoreGui         = game:GetService("CoreGui")
local TweenService    = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService      = game:GetService("RunService")
local HttpService     = game:GetService("HttpService")
local localPlayer     = Players.LocalPlayer
local colors = {
    primary = Color3.fromRGB(255, 136, 0), -- Orange
    secondary = Color3.fromRGB(255, 180, 50),
    accent = Color3.fromRGB(255, 200, 100),
    success = Color3.fromRGB(34, 197, 94),
    bg1 = Color3.fromRGB(15, 10, 5),     -- Dark brown/orange tint
    bg2 = Color3.fromRGB(25, 16, 8),
    bg3 = Color3.fromRGB(40, 25, 12),
    bg4 = Color3.fromRGB(55, 35, 18),
    text = Color3.fromRGB(255, 250, 245),
    textDim = Color3.fromRGB(220, 205, 190),
    textDimmer = Color3.fromRGB(175, 150, 135),
    border = Color3.fromRGB(80, 50, 25),
}
-- Detect platform: mobile = touch primary with no mouse; PC = everything else.
-- Mobile keeps the original compact size; PC gets a larger default and a wider
-- resize ceiling so the window can stretch for desktop play.
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local windowSize, minWindowSize, maxWindowSize
if isMobile then
    windowSize    = UDim2.new(0, 420, 0, 280) -- sama persis seperti ukuran lama
    minWindowSize = Vector2.new(380, 250)
    maxWindowSize = Vector2.new(800, 600)
else -- PC / desktop
    windowSize    = UDim2.new(0, 560, 0, 360) -- lebih lebar & lebih tinggi
    minWindowSize = Vector2.new(440, 300)
    maxWindowSize = Vector2.new(1100, 760)    -- ceiling resize lebih besar
end
local sidebarWidth = 120
local headerHeight = 34
local topBarHeight = 28
local sectionHeaderHeight = 30
local panelTransparency = 0.1
local sectionTransparency = 0.30
local fontSize = {
    title = 15,
    subtitle = 11,
    header = 12,
    normal = 11,
    small = 10,
}

local function formatRichText(text)
    if type(text) ~= "string" or text == "" then
        return ""
    end
    return (text:gsub('<font color="rgb%s*%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)">', function(r, g, b)
        r = math.clamp(math.floor(tonumber(r) or 0), 0, 255)
        g = math.clamp(math.floor(tonumber(g) or 0), 0, 255)
        b = math.clamp(math.floor(tonumber(b) or 0), 0, 255)
        return string.format('<font color="#%02X%02X%02X">', r, g, b)
    end))
end

local function new(class, props)
    local inst = Instance.new(class)
    if props then
        local fontVal = props.Font
        local fontFaceVal = props.FontFace
        local parentVal = props.Parent
        
        for k, v in pairs(props) do
            if k ~= "Font" and k ~= "FontFace" and k ~= "Parent" then
                inst[k] = v
            end
        end
        if fontVal then inst.Font = fontVal end
        if fontFaceVal then inst.FontFace = fontFaceVal end
        if parentVal then inst.Parent = parentVal end
    end
    if (class == "TextLabel" or class == "TextButton" or class == "TextBox") and not props then
        inst.Font = Enum.Font.Gotham
    elseif (class == "TextLabel" or class == "TextButton" or class == "TextBox") and props then
        if props.Font == nil and props.FontFace == nil then
            inst.Font = Enum.Font.Gotham
        end
    end
    return inst
end
function Library:AddConnection(name, connection)
    if self._connections[name] then
        pcall(function() self._connections[name]:Disconnect() end)
    end
    self._connections[name] = connection
    return connection
end
function Library:Cleanup()
    if isDirty then
        pcall(function() Library.ConfigSystem.Save() end)
        isDirty = false
    end
    if self._connections then
        for _, conn in pairs(self._connections) do
            pcall(function() conn:Disconnect() end)
        end
        table.clear(self._connections)
    end
    if self._saveThread then
        pcall(function() task.cancel(self._saveThread) end)
        self._saveThread = nil
    end
    if CallbackRegistry then
        for k in pairs(CallbackRegistry) do
            CallbackRegistry[k] = nil
        end
    end
    if self.flags then table.clear(self.flags) end
    if self.pages then table.clear(self.pages) end
    if self._navButtons then table.clear(self._navButtons) end
    if self._searchIndex then table.clear(self._searchIndex) end
    self._dropdownOverlay = nil
    self._dropdownPanel = nil
    self._dropdownFolder = nil
    self._dropdownPageLayout = nil
    self._dropdownCount = 0
    if self._activeNotifs then
        for _, notif in ipairs(self._activeNotifs) do
            pcall(function()
                if notif and notif.Parent then notif:Destroy() end
            end)
        end
        table.clear(self._activeNotifs)
    end
    self._currentPage = nil
    self._initialized = false
end
local function DeepCopy(original, _seen)
    _seen = _seen or {}
    if type(original) ~= "table" then return original end
    if _seen[original] then return _seen[original] end
    local copy = {}
    _seen[original] = copy
    for k, v in pairs(original) do
        copy[DeepCopy(k, _seen)] = DeepCopy(v, _seen)
    end
    return copy
end
local function MergeTables(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
            MergeTables(target[k], v)
        else
            target[k] = v
        end
    end
end
local function EnsureFolderExists()
    if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
end
Library.ConfigSystem = {}
function Library.ConfigSystem.SetDefaults(defaults)
    DefaultConfig = DeepCopy(defaults)
end
function Library.ConfigSystem.Save()
    local ok, err = pcall(function()
        EnsureFolderExists()
        local encoded = HttpService:JSONEncode(CurrentConfig)
        writefile(CONFIG_FILE, encoded)
    end)
    return ok
end
function Library.ConfigSystem.Load()
    EnsureFolderExists()
    CurrentConfig = DeepCopy(DefaultConfig)
    if isfile(CONFIG_FILE) then
        local ok, err = pcall(function()
            local raw = readfile(CONFIG_FILE)
            if not raw or raw == "" then return end
            local loaded = HttpService:JSONDecode(raw)
            if type(loaded) == "table" then
                MergeTables(CurrentConfig, loaded)
            end
        end)
        if not ok then
            pcall(function() delfile(CONFIG_FILE) end)
            CurrentConfig = DeepCopy(DefaultConfig)
        end
    end
    return CurrentConfig
end
function Library.ConfigSystem.Get(path, default)
    if not path then return default end
    local value = CurrentConfig
    for key in string.gmatch(path, "[^.]+") do
        if type(value) ~= "table" then return default end
        value = value[key]
    end
    return value ~= nil and value or default
end
function Library.ConfigSystem.Set(path, value)
    if not path then return end
    local keys = {}
    for key in string.gmatch(path, "[^.]+") do table.insert(keys, key) end
    local target = CurrentConfig
    for i = 1, #keys - 1 do
        if type(target[keys[i]]) ~= "table" then target[keys[i]] = {} end
        target = target[keys[i]]
    end
    target[keys[#keys]] = value
end
function Library.ConfigSystem.Reset()
    CurrentConfig = DeepCopy(DefaultConfig)
    Library.ConfigSystem.Save()
end
function Library.ConfigSystem.Delete()
    if isfile(CONFIG_FILE) then
        delfile(CONFIG_FILE)
    end
end
local function MarkDirty()
    if _G.AutoSaveEnabled == false then return end
    isDirty = true
    if Library._saveThread then
        pcall(function() task.cancel(Library._saveThread) end)
        Library._saveThread = nil
    end
    Library._saveThread = task.delay(2, function()
        if not isDirty then
            Library._saveThread = nil
            return
        end
        local ok = pcall(function() Library.ConfigSystem.Save() end)
        isDirty = false
        Library._saveThread = nil
    end)
end
local function RegisterCallback(configPath, callback, componentType, defaultValue, updateVisualFn)
    if not configPath then return end
    CallbackRegistry[configPath] = {
        path         = configPath,
        callback     = callback,
        type         = componentType,
        default      = defaultValue,
        updateVisual = updateVisualFn,
    }
end

local function ExecuteConfigCallbacks()
    -- Phase 1: restore every component's saved value + visual state WITHOUT
    -- running any action callbacks. This guarantees that dropdown/input filter
    -- values are already in place before any toggle action runs.
    for _, entry in pairs(CallbackRegistry) do
        if entry.updateVisual then
            local value = Library.ConfigSystem.Get(entry.path, entry.default)
            pcall(entry.updateVisual, value)
        end
    end
    -- Phase 2: run action callbacks. Non-toggle components (dropdown, input,
    -- etc.) run first so their filters/selections are fully applied, then
    -- toggles run last -- a toggle like "Auto Favorite" therefore starts only
    -- after its dropdown filter has been restored, fixing the load-order bug
    -- where the toggle ran unfiltered on execute.
    local function runCallbacks(wantToggle)
        for _, entry in pairs(CallbackRegistry) do
            local isToggle = entry.type == "toggle"
            if entry.callback and isToggle == wantToggle then
                local value = Library.ConfigSystem.Get(entry.path, entry.default)
                pcall(entry.callback, value)
            end
        end
    end
    runCallbacks(false)
    runCallbacks(true)
end
_G.AutoSaveEnabled = true
function _G.GetConfigValue(key, default)
    return Library.ConfigSystem.Get(key, default)
end
function _G.SaveConfigValue(key, value)
    Library.ConfigSystem.Set(key, value)
    if _G.AutoSaveEnabled then
        MarkDirty()
    end
end
function _G.GetFullConfig()
    return CurrentConfig
end
function Library:CreateWindow(config)
    config = config or {}
    local name = config.Name or "LynxGUI"
    local title = config.Title or "LynX"
    local subtitle = config.Subtitle or ""
    table.clear(CallbackRegistry)
    table.clear(self.flags)
    table.clear(self.pages)
    table.clear(self._navButtons)
    self._searchIndex = self._searchIndex or {}
    table.clear(self._searchIndex)
    self._currentPage = nil
    local existingGUI = CoreGui:FindFirstChild(name)
    if existingGUI then
        existingGUI:Destroy()
        task.wait(0.1)
    end
    self._gui = new("ScreenGui", {
        Name = name,
        Parent = CoreGui,
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 2147483647
    })
    local function bringToFront()
        self._gui.DisplayOrder = 2147483647
    end
    self._win = new("Frame", {
        Parent = self._gui,
        Size = windowSize,
        Position = UDim2.new(0.5, -windowSize.X.Offset/2, 0.5, -windowSize.Y.Offset/2),
        BackgroundColor3 = colors.bg1,
        BackgroundTransparency = panelTransparency,
        BorderSizePixel = 0,
        ClipsDescendants = false,
        ZIndex = 3
    })
    new("UICorner", {Parent = self._win, CornerRadius = UDim.new(0, 7)})
    self._sidebar = new("Frame", {
        Parent = self._win,
        Size = UDim2.new(0, sidebarWidth, 1, -headerHeight),
        Position = UDim2.new(0, 0, 0, headerHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 4
    })
    local sidebarLine = new("Frame", {
        Parent = self._sidebar,
        Size = UDim2.new(0, 1, 1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = colors.border,
        BackgroundTransparency = 0.42,
        BorderSizePixel = 0,
        ZIndex = 4
    })
    local scriptHeader = new("TextButton", {
        Parent = self._win,
        Size = UDim2.new(1, 0, 0, headerHeight),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 5
    })
    local headerLine = new("Frame", {
        Parent = scriptHeader,
        Size = UDim2.new(1, -20, 0, 1),
        Position = UDim2.new(0, 10, 1, -1),
        BackgroundColor3 = colors.border,
        BackgroundTransparency = 0.62,
        BorderSizePixel = 0,
        ZIndex = 5
    })
    local headerDragHandle = new("Frame", {
        Parent = scriptHeader,
        Size = UDim2.new(0, 28, 0, 2),
        Position = UDim2.new(0.5, -14, 0, 4),
        BackgroundColor3 = colors.primary,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        ZIndex = 6
    })
    new("UICorner", {Parent = headerDragHandle, CornerRadius = UDim.new(0, 2)})
    new("TextLabel", {
        Parent = scriptHeader,
        Text = title,
        Size = UDim2.new(0, 80, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.title,
        TextColor3 = colors.primary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6
    })
    new("ImageLabel", {
        Parent = scriptHeader,
        Image = "rbxassetid://104332967321169",
        Size = UDim2.new(0, 16, 0, 16),
        Position = UDim2.new(0, 58, 0.5, -8),
        BackgroundTransparency = 1,
        ImageColor3 = colors.primary,
        ZIndex = 6
    })
    local separator = new("Frame", {
        Parent = scriptHeader,
        Size = UDim2.new(0, 1, 0, 16),
        Position = UDim2.new(0, 82, 0.5, -8),
        BackgroundColor3 = colors.border,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        ZIndex = 6
    })
    new("TextLabel", {
        Parent = scriptHeader,
        Text = subtitle,
        Size = UDim2.new(0, 200, 1, 0),
        Position = UDim2.new(0, 96, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.textDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6
    })
    local btnMinHeader = new("TextButton", {
        Parent = scriptHeader,
        Size = UDim2.new(0, 22, 0, 22),
        Position = UDim2.new(1, -28, 0.5, -11),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = sectionTransparency,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 7
    })
    new("UICorner", {Parent = btnMinHeader, CornerRadius = UDim.new(0, 5)})
    local btnMinStroke = new("UIStroke", {
        Parent = btnMinHeader,
        Color = colors.border,
        Thickness = 1,
        Transparency = 0.4
    })
    local minLine = new("Frame", {
        Parent = btnMinHeader,
        Size = UDim2.new(0, 10, 0, 2),
        Position = UDim2.new(0.5, -5, 0.5, -1),
        BackgroundColor3 = colors.primary,
        BorderSizePixel = 0,
        ZIndex = 8
    })
    new("UICorner", {Parent = minLine, CornerRadius = UDim.new(1, 0)})
    local function setMinimizeHover(hovering)
        btnMinHeader.BackgroundColor3 = hovering and colors.bg3 or colors.bg2
        btnMinStroke.Color = hovering and colors.primary or colors.border
        btnMinStroke.Transparency = hovering and 0.1 or 0.4
        minLine.Size = hovering and UDim2.new(0, 12, 0, 2) or UDim2.new(0, 10, 0, 2)
        minLine.Position = hovering and UDim2.new(0.5, -6, 0.5, -1) or UDim2.new(0.5, -5, 0.5, -1)
    end
    self:AddConnection("minimizeHoverIn", btnMinHeader.MouseEnter:Connect(function()
        setMinimizeHover(true)
    end))
    self:AddConnection("minimizeHoverOut", btnMinHeader.MouseLeave:Connect(function()
        setMinimizeHover(false)
    end))
    local discordLink = "https://discord.gg/lynxx"
    local discordText = "discord.gg/lynxx"
    local discordTextStart = 33
    local discordTextW = game:GetService("TextService"):GetTextSize(discordText, fontSize.small, Enum.Font.GothamBold, Vector2.new(1000, 100)).X
    local discordPillW = math.ceil(discordTextStart + discordTextW + 9)
    local btnDiscord = new("TextButton", {
        Parent = scriptHeader,
        Size = UDim2.new(0, discordPillW, 0, 22),
        Position = UDim2.new(1, -(34 + discordPillW), 0.5, -11),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 7
    })
    new("ImageLabel", {
        Parent = btnDiscord,
        Image = "rbxthumb://type=Asset&id=84640740142415&w=150&h=150",
        Size = UDim2.new(0, 15, 0, 15),
        Position = UDim2.new(0, 8, 0.5, -7.5),
        BackgroundTransparency = 1,
        ImageColor3 = colors.primary,
        ZIndex = 8
    })
    local discordSep = new("Frame", {
        Parent = btnDiscord,
        Size = UDim2.new(0, 1, 0, 12),
        Position = UDim2.new(0, 28, 0.5, -6),
        BackgroundColor3 = colors.primary,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        ZIndex = 8
    })
    new("UIGradient", {
        Parent = discordSep,
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(1, 1)
        })
    })
    local discordTitle = new("TextLabel", {
        Parent = btnDiscord,
        Text = discordText,
        Size = UDim2.new(0, math.ceil(discordTextW) + 2, 1, 0),
        Position = UDim2.new(0, discordTextStart, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.primary,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 8
    })
    local function setDiscordHover(hovering)
        discordTitle.TextColor3 = hovering and colors.text or colors.primary
    end
    local function copyDiscord()
        local clip = setclipboard or toclipboard or writeclipboard or (Clipboard and Clipboard.set) or (clipboard and clipboard.set)
        local ok = false
        if clip then ok = pcall(clip, discordLink) end
        if ok then
            self:MakeNotify({Title = "Discord", Description = "Invite link disalin ke clipboard!", Color = colors.primary})
        else
            self:MakeNotify({Title = "Discord", Description = discordLink, Color = colors.primary, Delay = 6})
        end
    end
    self:AddConnection("discordClick", btnDiscord.MouseButton1Click:Connect(copyDiscord))
    self:AddConnection("discordHoverIn", btnDiscord.MouseEnter:Connect(function()
        setDiscordHover(true)
    end))
    self:AddConnection("discordHoverOut", btnDiscord.MouseLeave:Connect(function()
        setDiscordHover(false)
    end))
    self._navContainer = new("ScrollingFrame", {
        Parent = self._sidebar,
        Size = UDim2.new(1, -10, 1, -39),
        Position = UDim2.new(0, 5, 0, 34),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 5
    })
    new("UIListLayout", {Parent = self._navContainer, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
    self._contentBg = new("Frame", {
        Parent = self._win,
        Size = UDim2.new(1, -(sidebarWidth + 6), 1, -(headerHeight + 3)),
        Position = UDim2.new(0, sidebarWidth + 3, 0, headerHeight + 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 4
    })
    local topBar = new("Frame", {
        Parent = self._contentBg,
        Size = UDim2.new(1, -4, 0, topBarHeight),
        Position = UDim2.new(0, 2, 0, 2),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5
    })
    local pageTitleAccent = new("Frame", {
        Parent = topBar,
        Size = UDim2.new(0, 3, 0, 16),
        Position = UDim2.new(0, 0, 0.5, -8),
        BackgroundColor3 = colors.primary,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ZIndex = 6
    })
    new("UICorner", {Parent = pageTitleAccent, CornerRadius = UDim.new(1, 0)})
    self._pageTitle = new("TextLabel", {
        Parent = topBar,
        Text = "Dashboard",
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.header,
        BackgroundTransparency = 1,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 6
    })
    new("Frame", {
        Parent = topBar,
        Size = UDim2.new(1, -10, 0, 1),
        Position = UDim2.new(0, 5, 1, -1),
        BackgroundColor3 = colors.border,
        BackgroundTransparency = 0.7,
        BorderSizePixel = 0,
        ZIndex = 5
    })
    local resizeHandle = new("TextButton", {
        Parent = self._win,
        Size = UDim2.new(0, 18, 0, 18),
        Position = UDim2.new(1, 0, 1, 0),
        AnchorPoint = Vector2.new(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 100
    })
    local function addResizeGripLine(offsetX, offsetY, length)
        local line = new("Frame", {
            Parent = resizeHandle,
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, offsetX, 1, offsetY),
            Size = UDim2.new(0, length, 0, 2),
            Rotation = -45,
            BackgroundColor3 = colors.textDim,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            ZIndex = 101
        })
        new("UICorner", {Parent = line, CornerRadius = UDim.new(1, 0)})
    end
    addResizeGripLine(-3, -3, 6)
    addResizeGripLine(-7, -3, 6)
    addResizeGripLine(-3, -7, 6)
    local minimized = false
    local icon = nil
    local savedIconPos = UDim2.new(0, 20, 0, 100)
    local savedWinPos = self._win.Position
    local savedWinSize = self._win.Size
    local minimizedIconSize = 40
    local function createMinimizedIcon()
        if icon then return end
        icon = new("ImageButton", {
            Parent = self._gui,
            Size = UDim2.new(0, minimizedIconSize, 0, minimizedIconSize),
            Position = savedIconPos,
            BackgroundColor3 = colors.bg2,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Image = "rbxassetid://118176705805619",
            ScaleType = Enum.ScaleType.Fit,
            AutoButtonColor = false,
            Active = true,
            ZIndex = 50
        })
        new("UICorner", {Parent = icon, CornerRadius = UDim.new(0, 6)})
        new("TextLabel", {
            Parent = icon,
            Text = "L",
            Size = UDim2.new(1, 0, 1, 0),
            Font = Enum.Font.GothamBold,
            TextSize = 22,
            BackgroundTransparency = 1,
            TextColor3 = colors.primary,
            Visible = icon.Image == "",
            ZIndex = 51
        })
        local iconConns = {}
        local iconDragging = false
        local iconDragStart = nil
        local iconStartPos = nil
        local iconDragMoved = false
        local dragThreshold = 6
        local function disconnectIconConns()
            for i = #iconConns, 1, -1 do
                local c = iconConns[i]
                iconConns[i] = nil
                pcall(function() c:Disconnect() end)
            end
        end
        local function restoreFromIcon()
            if not icon then return end
            bringToFront()
            self._win.Visible = true
            self._win.Size = savedWinSize
            self._win.Position = savedWinPos
            disconnectIconConns()
            icon:Destroy()
            icon = nil
            minimized = false
        end
        iconConns[#iconConns + 1] = icon.InputBegan:Connect(function(input)
            if iconDragging then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                iconDragging = true
                iconDragMoved = false
                iconDragStart = input.Position
                iconStartPos = icon.Position
            end
        end)
        iconConns[#iconConns + 1] = UserInputService.InputChanged:Connect(function(input)
            if not iconDragging or not icon or not icon.Parent or not iconStartPos or not iconDragStart then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - iconDragStart
                if delta.Magnitude > dragThreshold then
                    iconDragMoved = true
                end
                icon.Position = UDim2.new(
                    iconStartPos.X.Scale, iconStartPos.X.Offset + delta.X,
                    iconStartPos.Y.Scale, iconStartPos.Y.Offset + delta.Y
                )
            end
        end)
        iconConns[#iconConns + 1] = UserInputService.InputEnded:Connect(function(input)
            if not iconDragging then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                iconDragging = false
                if icon and icon.Parent then
                    savedIconPos = icon.Position
                    if not iconDragMoved then
                        restoreFromIcon()
                    end
                end
            end
        end)
        icon.Destroying:Connect(disconnectIconConns)
    end
    self:AddConnection("minimizeBtn", btnMinHeader.MouseButton1Click:Connect(function()
        if not minimized then
            savedWinPos = self._win.Position
            savedWinSize = self._win.Size
            self._win.Size = UDim2.new(0, 0, 0, 0)
            self._win.Position = UDim2.new(0.5, 0, 0.5, 0)
            self._win.Visible = false
            createMinimizedIcon()
            minimized = true
        end
    end))
    local dragging, dragStart, startPos = false, nil, nil
    local resizing = false
    local resizeStartPos, resizeStartSize = nil, nil
    local lastX, lastY = nil, nil
    local function onMove(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            if dragging and startPos and self._win then
                local nx = startPos.X.Offset + (input.Position - dragStart).X
                local ny = startPos.Y.Offset + (input.Position - dragStart).Y
                if lastX == nil or nx-lastX > 0.5 or nx-lastX < -0.5 or ny-lastY > 0.5 or ny-lastY < -0.5 then
                    lastX, lastY = nx, ny
                    self._win.Position = UDim2.new(startPos.X.Scale, nx, startPos.Y.Scale, ny)
                end
            elseif resizing and resizeStartPos and self._win then
                local d = input.Position - resizeStartPos
                local nw = math.clamp(resizeStartSize.X.Offset + d.X, minWindowSize.X, maxWindowSize.X)
                local nh = math.clamp(resizeStartSize.Y.Offset + d.Y, minWindowSize.Y, maxWindowSize.Y)
                if lastX == nil or nw ~= lastX or nh ~= lastY then
                    lastX, lastY = nw, nh
                    self._win.Size = UDim2.new(0, nw, 0, nh)
                end
            end
        end
    end
    local moveConn = nil
    local function ensureMoveConn()
        if not moveConn then
            moveConn = UserInputService.InputChanged:Connect(onMove)
            self:AddConnection("inputChanged", moveConn)
        end
    end
    local function releaseMoveConn()
        if moveConn and not dragging and not resizing then
            moveConn:Disconnect()
            moveConn = nil
        end
    end
    self:AddConnection("headerDragStart", scriptHeader.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            bringToFront()
            dragging, dragStart, startPos = true, input.Position, self._win.Position
            lastX, lastY = nil, nil 
            ensureMoveConn()
        end
    end))
    self:AddConnection("resizeDragStart", resizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            resizing, resizeStartPos, resizeStartSize = true, input.Position, self._win.Size
            lastX, lastY = nil, nil 
            ensureMoveConn()
        end
    end))
    self:AddConnection("inputEnded", UserInputService.InputEnded:Connect(function(input)
        if not dragging and not resizing then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            resizing = false
            releaseMoveConn()
        end
    end))
    self:_createSearchBar()
    self._gui.Destroying:Connect(function()
        self:Cleanup()
    end)
    return self
end
function Library:_createSearchBar()
    local searchW = sidebarWidth - 12
    local searchH = 22
    local searchContainer = new("Frame", {
        Parent = self._sidebar,
        Size = UDim2.new(0, searchW, 0, searchH),
        Position = UDim2.new(0, 6, 0, 6),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = sectionTransparency,
        BorderSizePixel = 0,
        ZIndex = 7,
        Name = "SearchBar"
    })
    new("UICorner", {Parent = searchContainer, CornerRadius = UDim.new(0, 5)})
    local searchStroke = new("UIStroke", {
        Parent = searchContainer,
        Color = colors.border,
        Thickness = 1,
        Transparency = 0.4
    })
    new("ImageLabel", {
        Parent = searchContainer,
        Image = "rbxassetid://109869955247116",
        Size = UDim2.new(0, 14, 0, 14),
        Position = UDim2.new(0, 6, 0.5, -7),
        BackgroundTransparency = 1,
        ImageColor3 = colors.textDimmer,
        ZIndex = 8
    })
    local searchBox = new("TextBox", {
        Parent = searchContainer,
        Size = UDim2.new(1, -46, 1, 0),
        Position = UDim2.new(0, 26, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = "Search feature...",
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.text,
        PlaceholderColor3 = colors.textDimmer,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        ZIndex = 9
    })
    local clearBtn = new("TextButton", {
        Parent = searchContainer,
        Size = UDim2.new(0, 16, 0, 16),
        Position = UDim2.new(1, -20, 0.5, -8),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Visible = false,
        ZIndex = 9
    })
    local clearLines = {}
    local function addClearLine(rot)
        local line = new("Frame", {
            Parent = clearBtn,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, 10, 0, 1.6),
            Rotation = rot,
            BackgroundColor3 = colors.textDimmer,
            BorderSizePixel = 0,
            ZIndex = 10
        })
        clearLines[#clearLines + 1] = line
    end
    addClearLine(45)
    addClearLine(-45)
    local function setClearColor(c)
        for _, line in ipairs(clearLines) do
            line.BackgroundColor3 = c
        end
    end
    local ROW_H, ROW_GAP, LIST_PAD, MAX_PANEL_H = 32, 3, 4, 168
    local resultsPanel = new("Frame", {
        Parent = self._win,
        Size = UDim2.new(0, searchW, 0, ROW_H + LIST_PAD * 2),
        Position = UDim2.new(0, 6, 0, headerHeight + searchH + 9),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = panelTransparency,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 60,
        Name = "SearchResults"
    })
    new("UICorner", {Parent = resultsPanel, CornerRadius = UDim.new(0, 5)})
    new("UIStroke", {Parent = resultsPanel, Color = colors.border, Thickness = 1, Transparency = 0.35})
    local resultsList = new("ScrollingFrame", {
        Parent = resultsPanel,
        Size = UDim2.new(1, -6, 1, -6),
        Position = UDim2.new(0, 3, 0, 3),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 61
    })
    new("UIListLayout", {Parent = resultsList, Padding = UDim.new(0, ROW_GAP), SortOrder = Enum.SortOrder.LayoutOrder})
    new("UIPadding", {Parent = resultsList, PaddingRight = UDim.new(0, 1)})
    local emptyLabel = new("TextLabel", {
        Parent = resultsPanel,
        Text = "No features found",
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.textDimmer,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Visible = false,
        ZIndex = 62
    })
    local rowPool = {}
    local searchThread = nil
    local function highlightFeature(frame)
        if not frame or not frame.Parent then return end
        local old = frame:FindFirstChild("__SearchHL")
        if old then old:Destroy() end
        local hl = new("UIStroke", {
            Parent = frame,
            Color = colors.primary,
            Thickness = 2,
            Transparency = 0,
            Name = "__SearchHL"
        })
        task.delay(1.0, function()
            if hl and hl.Parent then
                pcall(function()
                    local tw = TweenService:Create(hl, TweenInfo.new(0.45), {Transparency = 1})
                    tw.Completed:Connect(function()
                        if hl then hl:Destroy() end
                    end)
                    tw:Play()
                end)
            end
        end)
    end
    local function goToFeature(entry)
        resultsPanel.Visible = false
        searchBox.Text = ""
        clearBtn.Visible = false
        if entry.pageName then
            self:_switchPage(entry.pageName)
        end
        if entry.expand then pcall(entry.expand) end
        task.defer(function()
            local frame = entry.frame
            if not frame or not frame.Parent then return end
            task.wait()
            local pageData = entry.pageName and self.pages[entry.pageName]
            local content = pageData and pageData.content
            if content then
                local y = frame.AbsolutePosition.Y - content.AbsolutePosition.Y + content.CanvasPosition.Y
                content.CanvasPosition = Vector2.new(0, math.max(0, y - 4))
            end
            highlightFeature(frame)
        end)
    end
    local function buildRow()
        local row = new("TextButton", {
            Parent = resultsList,
            Size = UDim2.new(1, 0, 0, ROW_H),
            BackgroundColor3 = colors.bg3,
            BackgroundTransparency = sectionTransparency,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            Visible = false,
            ZIndex = 62
        })
        new("UICorner", {Parent = row, CornerRadius = UDim.new(0, 4)})
        local accent = new("Frame", {
            Parent = row,
            Size = UDim2.new(0, 3, 1, -8),
            Position = UDim2.new(0, 0, 0, 4),
            BackgroundColor3 = colors.primary,
            BorderSizePixel = 0,
            ZIndex = 63
        })
        new("UICorner", {Parent = accent, CornerRadius = UDim.new(1, 0)})
        local nameLabel = new("TextLabel", {
            Parent = row,
            Text = "",
            Size = UDim2.new(1, -14, 0, 15),
            Position = UDim2.new(0, 9, 0, 4),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = fontSize.small,
            TextColor3 = colors.text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 63
        })
        local metaLabel = new("TextLabel", {
            Parent = row,
            Text = "",
            Size = UDim2.new(1, -14, 0, 11),
            Position = UDim2.new(0, 9, 0, 18),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium,
            TextSize = 9,
            TextColor3 = colors.textDimmer,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 63
        })
        local data = {button = row, nameLabel = nameLabel, metaLabel = metaLabel, entry = nil}
        row.MouseEnter:Connect(function() row.BackgroundColor3 = colors.bg4 end)
        row.MouseLeave:Connect(function() row.BackgroundColor3 = colors.bg3 end)
        row.MouseButton1Click:Connect(function()
            if data.entry then goToFeature(data.entry) end
        end)
        return data
    end
    local function doSearch(query)
        query = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        clearBtn.Visible = (query ~= "")
        if query == "" then
            for _, r in ipairs(rowPool) do
                r.button.Visible = false
                r.entry = nil
            end
            resultsPanel.Visible = false
            emptyLabel.Visible = false
            return
        end
        local index = self._searchIndex or {}
        local order = 0
        for _, entry in ipairs(index) do
            if entry.frame and entry.frame.Parent and entry.lname and entry.lname:find(query, 1, true) then
                order = order + 1
                local r = rowPool[order]
                if not r then
                    r = buildRow()
                    rowPool[order] = r
                end
                r.entry = entry
                r.nameLabel.Text = entry.name
                local metaText = entry.pageName or ""
                if entry.sectionTitle and entry.sectionTitle ~= "" then
                    metaText = (metaText ~= "" and (metaText .. " • ") or "") .. entry.sectionTitle
                end
                r.metaLabel.Text = metaText
                r.button.LayoutOrder = order
                r.button.BackgroundColor3 = colors.bg3
                r.button.Visible = true
            end
        end
        for i = order + 1, #rowPool do
            rowPool[i].button.Visible = false
            rowPool[i].entry = nil
        end
        emptyLabel.Visible = (order == 0)
        local panelH
        if order == 0 then
            panelH = ROW_H + LIST_PAD * 2
        else
            local contentH = order * ROW_H + math.max(0, order - 1) * ROW_GAP + LIST_PAD * 2
            panelH = math.min(contentH, MAX_PANEL_H)
        end
        resultsPanel.Size = UDim2.new(0, searchW, 0, panelH)
        resultsPanel.Visible = true
    end
    self:AddConnection("searchTextChanged", searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local text = searchBox.Text
        if searchThread then
            pcall(function() task.cancel(searchThread) end)
            searchThread = nil
        end
        if text == "" then
            doSearch("")
            return
        end
        clearBtn.Visible = true
        searchThread = task.delay(0.1, function()
            searchThread = nil
            doSearch(text)
        end)
    end))
    self:AddConnection("searchFocused", searchBox.Focused:Connect(function()
        searchStroke.Color = colors.primary
        searchStroke.Transparency = 0.1
    end))
    self:AddConnection("searchFocusLost", searchBox.FocusLost:Connect(function()
        searchStroke.Color = colors.border
        searchStroke.Transparency = 0.4
    end))
    self:AddConnection("searchClear", clearBtn.MouseButton1Click:Connect(function()
        searchBox.Text = ""
    end))
    self:AddConnection("searchClearHoverIn", clearBtn.MouseEnter:Connect(function()
        setClearColor(colors.primary)
    end))
    self:AddConnection("searchClearHoverOut", clearBtn.MouseLeave:Connect(function()
        setClearColor(colors.textDimmer)
    end))
end
function Library:CreatePage(name, title, imageId, order)
    local page = new("Frame", {
        Parent = self._contentBg,
        Size = UDim2.new(1, -12, 1, -(topBarHeight + 10)),
        Position = UDim2.new(0, 6, 0, topBarHeight + 6),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ClipsDescendants = true,
        ZIndex = 5
    })
    local contentContainer = new("ScrollingFrame", {
        Parent = page,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 5
    })
    new("UIListLayout", {Parent = contentContainer, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder})
    new("UIPadding", {Parent = contentContainer, PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), PaddingRight = UDim.new(0, 4)})
    self.pages[name] = {frame = page, title = title, content = contentContainer}
    local btn = new("TextButton", {
        Parent = self._navContainer,
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = order or 999,
        ZIndex = 6
    })
    new("UICorner", {Parent = btn, CornerRadius = UDim.new(0, 5)})
    local indicator = new("Frame", {
        Parent = btn,
        Size = UDim2.new(0, 3, 0, 16),
        Position = UDim2.new(0, 0, 0.5, -8),
        BackgroundColor3 = colors.primary,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 7
    })
    new("UICorner", {Parent = indicator, CornerRadius = UDim.new(1, 0)})
    new("ImageLabel", {
        Parent = btn,
        Image = imageId or "",
        Size = UDim2.new(0, 15, 0, 15),
        Position = UDim2.new(0, 8, 0.5, -7),
        BackgroundTransparency = 1,
        ImageColor3 = colors.textDim,
        ZIndex = 7,
        Name = "Icon"
    })
    new("TextLabel", {
        Parent = btn,
        Text = name,
        Size = UDim2.new(1, -35, 1, 0),
        Position = UDim2.new(0, 28, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.normal,
        TextColor3 = colors.textDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 7,
        Name = "Label"
    })
    self._navButtons[name] = {btn = btn, indicator = indicator, page = page, title = title}
    self:AddConnection("navBtn_" .. name, btn.MouseButton1Click:Connect(function()
        self:_switchPage(name)
    end))
    return contentContainer
end
function Library:SetFirstPage(name, title)
    self:_switchPage(name)
end
function Library:_switchPage(pageName)
    if self._currentPage == pageName then return end
    for _, pageData in pairs(self.pages) do
        pageData.frame.Visible = false
    end
    for name, data in pairs(self._navButtons) do
        local isActive = name == pageName
        data.btn.BackgroundColor3 = isActive and colors.bg2 or colors.bg2
        data.btn.BackgroundTransparency = isActive and sectionTransparency or 1
        local icon = data.btn:FindFirstChild("Icon")
        if icon then
            icon.ImageColor3 = isActive and colors.primary or colors.textDim
        end
        local label = data.btn:FindFirstChild("Label")
        if label then
            label.TextColor3 = isActive and colors.text or colors.textDim
        end
        data.indicator.Visible = isActive
    end
    if self.pages[pageName] then
        self.pages[pageName].frame.Visible = true
        if self._pageTitle then
            self._pageTitle.Text = self.pages[pageName].title or pageName
        end
    end
    self._currentPage = pageName
end
function Library:CreateCategory(parent, title, startOpen, isLocked)
    startOpen = startOpen == true
    local categoryFrame = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, sectionHeaderHeight),
        AutomaticSize = Enum.AutomaticSize.None,
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = sectionTransparency,
        BorderSizePixel = 0,
        ClipsDescendants = false,
        ZIndex = 6
    })
    new("UICorner", {Parent = categoryFrame, CornerRadius = UDim.new(0, 4)})
    local categoryLayout = new("UIListLayout", {
        Parent = categoryFrame,
        Padding = UDim.new(0, 0),
        SortOrder = Enum.SortOrder.LayoutOrder
    })
    local header = new("TextButton", {
        Parent = categoryFrame,
        Size = UDim2.new(1, 0, 0, sectionHeaderHeight),
        LayoutOrder = 1,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 7
    })
    new("TextLabel", {
        Parent = header,
        Text = title,
        Size = UDim2.new(1, -32, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.normal,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8
    })
    local arrow = new("TextLabel", {
        Parent = header,
        Text = "▼",
        Size = UDim2.new(0, 18, 1, 0),
        Position = UDim2.new(1, -24, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.primary,
        ZIndex = 8
    })
    local contentWrapper = new("Frame", {
        Parent = categoryFrame,
        Size = UDim2.new(1, 0, 0, 0),
        LayoutOrder = 2,
        BackgroundTransparency = 1,
        Visible = startOpen,
        ZIndex = 7
    })
    local contentContainer = new("Frame", {
        Parent = contentWrapper,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        ZIndex = 7
    })
    
    if isLocked then
        new("ImageLabel", {
            Parent = header,
            Image = "rbxassetid://91807786360605",
            Size = UDim2.new(0, 14, 0, 14),
            Position = UDim2.new(1, -44, 0.5, -7),
            BackgroundTransparency = 1,
            ImageColor3 = colors.textDim,
            ZIndex = 8
        })
    end
    new("UIPadding", {
        Parent = contentContainer,
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 6)
    })
    local contentListLayout = new("UIListLayout", {Parent = contentContainer, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder})
    local isOpen = startOpen
    arrow.Rotation = startOpen and 180 or 0
    local function updateCategoryHeight()
        if not categoryFrame or not categoryFrame.Parent then return end
        local h = sectionHeaderHeight
        local contentH = 0
        if isOpen and contentWrapper.Visible then
            contentH = contentListLayout.AbsoluteContentSize.Y + 6
            if isLocked and contentH < 80 then
                contentH = 80
            end
            h = sectionHeaderHeight + contentH
        end
        categoryFrame.Size = UDim2.new(1, 0, 0, h)
        contentWrapper.Size = UDim2.new(1, 0, 0, contentH)
    end
    local function setOpen(state)
        isOpen = state
        contentWrapper.Visible = isOpen
        arrow.Rotation = isOpen and 180 or 0
        updateCategoryHeight()
    end
    contentListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCategoryHeight)
    task.defer(updateCategoryHeight)
    header.MouseButton1Click:Connect(function()
        setOpen(not isOpen)
    end)
    local function expand()
        if not isOpen then setOpen(true) end
    end
    local returnedContainer = contentContainer
    
    if isLocked then
        local blocker = new("TextButton", {
            Parent = contentWrapper,
            Size = UDim2.new(1, 0, 1, 0),
            Position = UDim2.new(0, 0, 0, 0),
            BackgroundTransparency = 0.4,
            BackgroundColor3 = colors.bg2,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 20
        })
        new("ImageLabel", {
            Parent = blocker,
            Image = "rbxassetid://91807786360605",
            Size = UDim2.new(0, 32, 0, 32),
            Position = UDim2.new(0.5, -16, 0.5, -24),
            BackgroundTransparency = 1,
            ImageColor3 = colors.primary,
            ZIndex = 21
        })
        new("TextLabel", {
            Parent = blocker,
            Text = "Buy Premium to unlock this feature",
            Size = UDim2.new(1, 0, 0, 20),
            Position = UDim2.new(0, 0, 0.5, 12),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = fontSize.small,
            TextColor3 = colors.text,
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 21
        })
    end
    
    return returnedContainer, expand
end
function Library:CreateToggle(parent, label, configPath, callback, disableSave, defaultValue)
    local frame = new("Frame", {Parent = parent, Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, ZIndex = 7})
    new("TextLabel", {
        Parent = frame,
        Text = label,
        Size = UDim2.new(1, -45, 1, 0),
        BackgroundTransparency = 1,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        ZIndex = 8
    })
    local toggleBg = new("Frame", {
        Parent = frame,
        Size = UDim2.new(0, 34, 0, 18),
        Position = UDim2.new(1, -34, 0.5, -9),
        BackgroundColor3 = colors.bg3,
        BorderSizePixel = 0,
        ZIndex = 8
    })
    new("UICorner", {Parent = toggleBg, CornerRadius = UDim.new(1, 0)})
    local toggleCircle = new("Frame", {
        Parent = toggleBg,
        Size = UDim2.new(0, 14, 0, 14),
        Position = UDim2.new(0, 2, 0.5, -7),
        BackgroundColor3 = colors.textDim,
        BorderSizePixel = 0,
        ZIndex = 9
    })
    new("UICorner", {Parent = toggleCircle, CornerRadius = UDim.new(1, 0)})
    local btn = new("TextButton", {Parent = toggleBg, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 10})
    local on = defaultValue or false
    if configPath and not disableSave then
        on = Library.ConfigSystem.Get(configPath, on)
    end
    local function updateVisual()
        toggleBg.BackgroundColor3 = on and colors.primary or colors.bg3
        toggleCircle.Position = on and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        toggleCircle.BackgroundColor3 = on and colors.text or colors.textDim
    end
    updateVisual()
    self:AddConnection("toggle_" .. label .. tostring(btn), btn.MouseButton1Click:Connect(function()
        on = not on
        updateVisual()
        if configPath and not disableSave then
            Library.ConfigSystem.Set(configPath, on)
            MarkDirty()
        end
        self.flags[configPath or label] = on
        if callback then callback(on) end
    end))
    if configPath and not disableSave then
        RegisterCallback(configPath, callback, "toggle", defaultValue or false, function(val)
            on = val
            updateVisual()
            self.flags[configPath or label] = on
        end)
    end
    self.flags[configPath or label] = on
    local toggleController = {
        frame = frame,
        set = function(val)
            on = val
            updateVisual()
            if configPath and not disableSave then
                Library.ConfigSystem.Set(configPath, on)
                MarkDirty()
            end
            Library.flags[configPath or label] = on
        end,
        get = function() return on end
    }
    return toggleController
end
Library._dropdownOverlay = nil
Library._dropdownPanel = nil
Library._dropdownFolder = nil
Library._dropdownPageLayout = nil
Library._dropdownCount = 0
function Library:_initDropdownSystem()
    if self._dropdownOverlay then return end
    self._dropdownOverlay = new("Frame", {
        Parent = self._win,
        Size = UDim2.new(1, 0, 1, -headerHeight),
        Position = UDim2.new(0, 0, 0, headerHeight),
        BackgroundColor3 = colors.bg1,
        BackgroundTransparency = 0.95,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Visible = false,
        ZIndex = 150,
        Name = "DropdownOverlay"
    })
    local closeOverlay = new("TextButton", {
        Parent = self._dropdownOverlay,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        ZIndex = 151
    })
    self._dropdownPanel = new("Frame", {
        Parent = self._dropdownOverlay,
        AnchorPoint = Vector2.new(1, 0.5),
        Size = UDim2.new(0, 160, 1, -16),
        Position = UDim2.new(1, 172, 0.5, 0),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = 0.09,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 152,
        Name = "DropdownPanel"
    })
    new("UICorner", {Parent = self._dropdownPanel, CornerRadius = UDim.new(0, 6)})
    new("UIStroke", {
        Parent = self._dropdownPanel,
        Color = colors.border,
        Thickness = 1,
        Transparency = 0.45
    })
    self._dropdownFolder = new("Frame", {
        Parent = self._dropdownPanel,
        Size = UDim2.new(1, -2, 1, 0),
        Position = UDim2.new(0, 1, 0, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 153,
        Name = "DropdownFolder"
    })
    self._dropdownPageLayout = new("UIPageLayout", {
        Parent = self._dropdownFolder,
        EasingDirection = Enum.EasingDirection.InOut,
        EasingStyle = Enum.EasingStyle.Quad,
        TweenTime = 0.01,
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Vertical,
        Name = "DropdownPageLayout"
    })
    self:AddConnection("dropdownOverlayClose", closeOverlay.Activated:Connect(function()
        if self._dropdownOverlay.Visible then
            self._dropdownOverlay.BackgroundTransparency = 0.95
            self._dropdownPanel.Position = UDim2.new(1, 172, 0.5, 0)
            self._dropdownOverlay.Visible = false
        end
    end))
end
function Library:_showDropdown(dropdownContainer)
    self:_initDropdownSystem()
    self._dropdownOverlay.Visible = true
    self._dropdownPageLayout:JumpTo(dropdownContainer)
    self._dropdownOverlay.BackgroundTransparency = 0.95
    self._dropdownPanel.Position = UDim2.new(1, -11, 0.5, 0)
end
function Library:_hideDropdown()
    if self._dropdownOverlay and self._dropdownOverlay.Visible then
        self._dropdownOverlay.BackgroundTransparency = 0.95
        self._dropdownPanel.Position = UDim2.new(1, 172, 0.5, 0)
        self._dropdownOverlay.Visible = false
    end
end
function Library:_createBaseDropdown(parent, title, imageId, items, configPath, onSelect, uniqueId, defaultValue, isMulti)
    self:_initDropdownSystem()
    local dropdownLayoutOrder = self._dropdownCount
    self._dropdownCount = self._dropdownCount + 1
    
    local dropdownFrame = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 7,
        Name = uniqueId or (isMulti and "MultiDropdown" or "Dropdown")
    })
    
    local dropdownButton = new("TextButton", {
        Parent = dropdownFrame,
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 8
    })
    
    local dropdownTitle = new("TextLabel", {
        Parent = dropdownFrame,
        Font = Enum.Font.GothamBold,
        Text = title or (isMulti and "Multi Select" or "Dropdown"),
        TextColor3 = colors.text,
        TextSize = fontSize.small,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(0.5, 0, 1, 0),
        ZIndex = 8
    })
    
    local selectFrame = new("Frame", {
        Parent = dropdownFrame,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = sectionTransparency,
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0.48, 0, 0, 22),
        LayoutOrder = dropdownLayoutOrder,
        ZIndex = 8
    })
    new("UICorner", {Parent = selectFrame, CornerRadius = UDim.new(0, 4)})
    new("UIStroke", {Parent = selectFrame, Color = colors.border, Thickness = 1, Transparency = 0.5})
    
    local defaultText = isMulti and "Select Options" or "Select Option"
    local optionLabel = new("TextLabel", {
        Parent = selectFrame,
        Font = Enum.Font.GothamBold,
        Text = defaultText,
        TextColor3 = colors.textDim,
        TextSize = fontSize.small,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 0.5, 0),
        Size = UDim2.new(1, -24, 1, 0),
        ZIndex = 9
    })
    
    new("ImageLabel", {
        Parent = selectFrame,
        Image = "rbxassetid://6031091004",
        ImageColor3 = colors.primary,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -6, 0.5, 0),
        Size = UDim2.new(0, 11, 0, 11),
        ZIndex = 9
    })
    
    local dropdownContainer = new("Frame", {
        Parent = self._dropdownFolder,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        LayoutOrder = dropdownLayoutOrder
    })
    
    local searchBox = new("TextBox", {
        Parent = dropdownContainer,
        PlaceholderText = "Search...",
        Font = Enum.Font.GothamBold,
        Text = "",
        TextSize = fontSize.small,
        TextColor3 = colors.text,
        PlaceholderColor3 = colors.textDimmer,
        BackgroundColor3 = colors.bg2,
        BackgroundTransparency = sectionTransparency,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -8, 0, 24),
        Position = UDim2.new(0, 4, 0, 4),
        ClearTextOnFocus = false,
        ZIndex = 154
    })
    new("UICorner", {Parent = searchBox, CornerRadius = UDim.new(0, 4)})
    new("UIStroke", {Parent = searchBox, Color = colors.border, Thickness = 1, Transparency = 0.5})
    new("UIPadding", {Parent = searchBox, PaddingLeft = UDim.new(0, 8)})
    
    local ROW_H, ROW_GAP = 26, 3
    local ROW_STRIDE = ROW_H + ROW_GAP
    local POOL_SIZE = 18

    local scrollSelect = new("ScrollingFrame", {
        Parent = dropdownContainer,
        Size = UDim2.new(1, -8, 1, -36),
        Position = UDim2.new(0, 4, 0, 32),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ZIndex = 154
    })

    local savedValue = configPath and Library.ConfigSystem.Get(configPath, defaultValue) or defaultValue
    if isMulti and type(savedValue) ~= "table" then savedValue = {} end

    local DropdownFunc = { Value = savedValue, Options = items }
    local allOptions = {}
    local filteredOptions = {}
    local selectedSet = {}
    local rowPool = {}
    local searchThread = nil
    local isOpen = false
    local needsRefresh = false
    local poolBuilt = false
    local optionsNormalized = false

    local function rebuildSelectedSet()
        table.clear(selectedSet)
        if isMulti then
            for _, v in ipairs(DropdownFunc.Value) do
                selectedSet[v] = true
            end
        elseif DropdownFunc.Value ~= nil then
            selectedSet[DropdownFunc.Value] = true
        end
    end

    local function normalizeListInto(srcList, dstList)
        table.clear(dstList)
        for _, opt in ipairs(srcList) do
            local label, value
            if typeof(opt) == "table" and opt.Label and opt.Value ~= nil then
                label, value = tostring(opt.Label), opt.Value
            else
                label, value = tostring(opt), opt
            end
            dstList[#dstList + 1] = {
                label = label,
                value = value,
                lower = string.lower(label),
            }
        end
    end

    local function applyFilter(query)
        if not query or query == "" then
            for i = 1, #allOptions do
                filteredOptions[i] = allOptions[i]
            end
            for i = #allOptions + 1, #filteredOptions do
                filteredOptions[i] = nil
            end
            return
        end
        table.clear(filteredOptions)
        for _, opt in ipairs(allOptions) do
            if string.find(opt.lower, query, 1, true) then
                filteredOptions[#filteredOptions + 1] = opt
            end
        end
    end

    local function ensureOptionsNormalized()
        if optionsNormalized then return end
        optionsNormalized = true
        normalizeListInto(items, allOptions)
        applyFilter("")
    end

    local function updateClosedLabel()
        ensureOptionsNormalized()
        if isMulti then
            local n = DropdownFunc.Value and #DropdownFunc.Value or 0
            if n == 0 then
                optionLabel.Text = defaultText
            else
                local labels = {}
                for _, v in ipairs(DropdownFunc.Value) do
                    for _, opt in ipairs(allOptions) do
                        if opt.value == v then
                            labels[#labels + 1] = opt.label
                            break
                        end
                    end
                end
                optionLabel.Text = (#labels == 0) and defaultText or table.concat(labels, ", ")
            end
        else
            local v = DropdownFunc.Value
            if v == nil then
                optionLabel.Text = defaultText
            else
                local foundLabel = nil
                for _, opt in ipairs(allOptions) do
                    if opt.value == v then
                        foundLabel = opt.label
                        break
                    end
                end
                optionLabel.Text = foundLabel or tostring(v)
            end
        end
    end

    local function paintRow(row, opt)
        local selected = selectedSet[opt.value] == true
        if selected then
            row.ChooseFrame.Size = UDim2.new(0, 3, 0, 16)
            row.BackgroundColor3 = colors.bg3
            row.BackgroundTransparency = panelTransparency
            row.OptionText.TextColor3 = colors.text
        else
            row.ChooseFrame.Size = UDim2.new(0, 0, 0, 0)
            row.BackgroundColor3 = colors.bg2
            row.BackgroundTransparency = 0.5
            row.OptionText.TextColor3 = colors.textDim
        end
        row.OptionText.Text = opt.label
    end

    local function refreshVisible()
        if not poolBuilt then return end
        local list = filteredOptions
        local total = #list
        local viewH = scrollSelect.AbsoluteSize.Y
        if viewH <= 0 then needsRefresh = true return end
        needsRefresh = false

        local canvasH = total * ROW_STRIDE
        if total > 0 then canvasH = canvasH - ROW_GAP end
        scrollSelect.CanvasSize = UDim2.new(0, 0, 0, canvasH)

        local scrollY = scrollSelect.CanvasPosition.Y
        local firstVisible = math.floor(scrollY / ROW_STRIDE) + 1
        if firstVisible < 1 then firstVisible = 1 end
        local maxVisible = math.floor(viewH / ROW_STRIDE) + 2
        local lastVisible = math.min(total, firstVisible + maxVisible - 1)

    for i = 1, #rowPool do
        local row = rowPool[i]
        local optIndex = firstVisible + i - 1
        if optIndex <= lastVisible then
            local opt = list[optIndex]
            row.Position = UDim2.new(0, 0, 0, (optIndex - 1) * ROW_STRIDE)
            paintRow(row, opt)
            row:SetAttribute("VirtualIndex", optIndex)
            row.Visible = true
        else
            row.Visible = false
            row:SetAttribute("VirtualIndex", nil)
        end
    end
end

local function ensurePoolBuilt()
    if poolBuilt then return end
    poolBuilt = true
    ensureOptionsNormalized()

    for i = 1, POOL_SIZE do
        local row = new("Frame", {
            Parent = scrollSelect,
            BackgroundColor3 = colors.bg2,
            BackgroundTransparency = 0.5,
            Size = UDim2.new(1, 0, 0, ROW_H),
            Position = UDim2.new(0, 0, 0, (i - 1) * ROW_STRIDE),
            Visible = false,
            ZIndex = 155
        })
        new("UICorner", {Parent = row, CornerRadius = UDim.new(0, 3)})
        new("TextLabel", {
            Parent = row,
            Font = Enum.Font.GothamBold,
            Text = "",
            TextSize = fontSize.small,
            TextColor3 = colors.text,
            Position = UDim2.new(0, 8, 0, 0),
            Size = UDim2.new(1, -16, 1, 0),
            BackgroundTransparency = 1,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Name = "OptionText",
            ZIndex = 156
        })
        local chooseFrame = new("Frame", {
            Parent = row,
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = colors.primary,
            Position = UDim2.new(0, 2, 0.5, 0),
            Size = UDim2.new(0, 0, 0, 0),
            Name = "ChooseFrame",
            ZIndex = 156
        })
        new("UICorner", {Parent = chooseFrame, CornerRadius = UDim.new(0, 3)})
        local btn = new("TextButton", {
            Parent = row,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = "",
            AutoButtonColor = false,
            ZIndex = 157
        })
        row.MouseEnter:Connect(function()
            if row:GetAttribute("VirtualIndex") then
                row.BackgroundColor3 = colors.bg4
            end
        end)
        row.MouseLeave:Connect(function()
            local optIndex = row:GetAttribute("VirtualIndex")
            if optIndex and filteredOptions[optIndex] then
                paintRow(row, filteredOptions[optIndex])
            end
        end)
        btn.Activated:Connect(function()
            local optIndex = row:GetAttribute("VirtualIndex")
            if not optIndex then return end
            local opt = filteredOptions[optIndex]
            if not opt then return end
            local value = opt.value
            if isMulti then
                local idx = table.find(DropdownFunc.Value, value)
                if not idx then
                    table.insert(DropdownFunc.Value, value)
                else
                    table.remove(DropdownFunc.Value, idx)
                end
                rebuildSelectedSet()
                DropdownFunc:Set(DropdownFunc.Value)
            else
                DropdownFunc.Value = value
                rebuildSelectedSet()
                DropdownFunc:Set(DropdownFunc.Value)
            end
        end)
        rowPool[i] = row
    end

    self:AddConnection("dropdownScroll_" .. dropdownLayoutOrder, scrollSelect:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        refreshVisible()
    end))

    self:AddConnection("dropdownResize_" .. dropdownLayoutOrder, scrollSelect:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if isOpen then refreshVisible() end
    end))
end

function DropdownFunc:Clear()
        allOptions = {}
        filteredOptions = {}
        DropdownFunc.Value = isMulti and {} or nil
        DropdownFunc.Options = {}
        rebuildSelectedSet()
        optionLabel.Text = defaultText
        scrollSelect.CanvasPosition = Vector2.new(0, 0)
        refreshVisible()
    end

    function DropdownFunc:AddOption(option)
        local label, value
        if typeof(option) == "table" and option.Label and option.Value ~= nil then
            label, value = tostring(option.Label), option.Value
        else
            label, value = tostring(option), option
        end
        allOptions[#allOptions + 1] = {
            label = label,
            value = value,
            lower = string.lower(label),
        }
        if searchBox.Text == "" or searchBox.Text == nil then
            filteredOptions[#filteredOptions + 1] = allOptions[#allOptions]
        end
    end

    function DropdownFunc:Set(Value)
        if isMulti and type(Value) ~= "table" then Value = {} end
        DropdownFunc.Value = Value
        rebuildSelectedSet()
        if configPath then
            Library.ConfigSystem.Set(configPath, Value)
            MarkDirty()
        end
        updateClosedLabel()
        if isOpen then refreshVisible() end
        if onSelect then
            if isMulti then
                onSelect(DropdownFunc.Value)
            else
                onSelect((DropdownFunc.Value ~= nil) and tostring(DropdownFunc.Value) or "")
            end
        end
    end

    function DropdownFunc:SetValue(val) self:Set(val) end
    function DropdownFunc:GetValue() return self.Value end

    function DropdownFunc:SetValues(newList, selecting)
        newList = newList or {}
        items = newList
        optionsNormalized = true
        normalizeListInto(newList, allOptions)
        DropdownFunc.Options = newList
        if isMulti then
            DropdownFunc.Value = {}
        else
            DropdownFunc.Value = nil
        end
        if selecting ~= nil then
            if isMulti and type(selecting) == "table" then
                DropdownFunc.Value = selecting
            elseif not isMulti then
                DropdownFunc.Value = selecting
            end
        end
        rebuildSelectedSet()
        applyFilter(string.lower(searchBox.Text or ""))
        scrollSelect.CanvasPosition = Vector2.new(0, 0)
        updateClosedLabel()
        refreshVisible()
        if onSelect then
            if isMulti then
                onSelect(DropdownFunc.Value)
            else
                onSelect((DropdownFunc.Value ~= nil) and tostring(DropdownFunc.Value) or "")
            end
        end
    end

    function DropdownFunc:Refresh(newList)
        local prevValue = DropdownFunc.Value
        items = newList
        optionsNormalized = true
        normalizeListInto(newList, allOptions)
        DropdownFunc.Options = newList
        if isMulti then
            local stillValid = {}
            if type(prevValue) == "table" then
                for _, v in ipairs(prevValue) do
                    for _, opt in ipairs(allOptions) do
                        if opt.value == v then
                            stillValid[#stillValid + 1] = v
                            break
                        end
                    end
                end
            end
            DropdownFunc.Value = stillValid
        else
            local found = false
            if prevValue ~= nil then
                for _, opt in ipairs(allOptions) do
                    if opt.value == prevValue then
                        found = true
                        break
                    end
                end
            end
            DropdownFunc.Value = found and prevValue or nil
        end
        rebuildSelectedSet()
        applyFilter(string.lower(searchBox.Text or ""))
        updateClosedLabel()
        if isOpen then refreshVisible() end
        if configPath then
            Library.ConfigSystem.Set(configPath, DropdownFunc.Value)
            MarkDirty()
        end
    end

    self:AddConnection("searchBox_" .. dropdownLayoutOrder, searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        if searchThread then
            pcall(function() task.cancel(searchThread) end)
            searchThread = nil
        end
        local query = string.lower(searchBox.Text)
        if query == "" then
            applyFilter("")
            refreshVisible()
            return
        end
        searchThread = task.delay(0.08, function()
            searchThread = nil
            applyFilter(query)
            scrollSelect.CanvasPosition = Vector2.new(0, 0)
            refreshVisible()
        end)
    end))

    self:AddConnection("dropdownOpen_" .. dropdownLayoutOrder, dropdownButton.Activated:Connect(function()
        ensurePoolBuilt()
        searchBox.Text = ""
        applyFilter("")
        scrollSelect.CanvasPosition = Vector2.new(0, 0)
        isOpen = true
        self:_showDropdown(dropdownContainer)
        task.defer(function()
            refreshVisible()
            if needsRefresh then
                task.defer(refreshVisible)
            end
        end)
    end))

    self:AddConnection("dropdownOverlayClose_" .. dropdownLayoutOrder, self._dropdownOverlay:GetPropertyChangedSignal("Visible"):Connect(function()
        if not self._dropdownOverlay.Visible and isOpen then
            isOpen = false
        end
    end))

    rebuildSelectedSet()
    updateClosedLabel()

    if configPath then
        local cbType = isMulti and "multidropdown" or "dropdown"
        local cbDef = isMulti and (defaultValue or {}) or defaultValue
        RegisterCallback(configPath, onSelect, cbType, cbDef, function(val)
            if isMulti and type(val) ~= "table" then val = {} end
            DropdownFunc.Value = val
            rebuildSelectedSet()
            updateClosedLabel()
            if isOpen then refreshVisible() end
        end)
    end
    
    if uniqueId then
        self.flags[uniqueId] = DropdownFunc
    end
    
    return dropdownFrame
end

function Library:CreateDropdown(parent, title, imageId, items, configPath, onSelect, uniqueId, defaultValue)
    return self:_createBaseDropdown(parent, title, imageId, items, configPath, onSelect, uniqueId, defaultValue, false)
end

function Library:CreateMultiDropdown(parent, title, imageId, items, configPath, onSelect, uniqueId, defaultValues)
    return self:_createBaseDropdown(parent, title, imageId, items, configPath, onSelect, uniqueId, defaultValues, true)
end

function Library:CreateInput(parent, label, configPath, defaultValue, callback)
    local frame = new("Frame", {Parent = parent, Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, ZIndex = 7})
    new("TextLabel", {
        Parent = frame,
        Text = label,
        Size = UDim2.new(0.52, 0, 1, 0),
        BackgroundTransparency = 1,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        ZIndex = 8
    })
    local inputBg = new("Frame", {
        Parent = frame,
        Size = UDim2.new(0.45, 0, 0, 24),
        Position = UDim2.new(0.55, 0, 0.5, -12),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = panelTransparency,
        BorderSizePixel = 0,
        ZIndex = 8
    })
    new("UICorner", {Parent = inputBg, CornerRadius = UDim.new(0, 4)})
    local initialValue = Library.ConfigSystem.Get(configPath, defaultValue)
    local inputBox = new("TextBox", {
        Parent = inputBg,
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        BackgroundTransparency = 1,
        Text = initialValue ~= nil and tostring(initialValue) or "",
        PlaceholderText = "Enter Value",
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.text,
        PlaceholderColor3 = colors.textDimmer,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        ZIndex = 9
    })
    local function resolveValue(text)
        if type(text) == "string" and #text > 15 and text:match("^%d+$") then
            return text
        end
        local num = tonumber(text)
        return num or text
    end
    self:AddConnection("input_" .. label .. tostring(inputBox), inputBox.FocusLost:Connect(function()
        local rawValue = inputBox.Text
        local value = resolveValue(rawValue)
        if configPath then
            Library.ConfigSystem.Set(configPath, value)
            MarkDirty()
        end
        if callback then callback(value) end
    end))
    RegisterCallback(configPath, callback, "input", defaultValue, function(val)
        inputBox.Text = tostring(val ~= nil and val or defaultValue or "")
    end)
    if callback then
        local resolved = resolveValue(tostring(initialValue))
        callback(resolved)
    end
    return frame
end

function Library:CreateBind(parent, label, configPath, defaultValue, callback)
    local frame = new("Frame", {Parent = parent, Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, ZIndex = 7})
    new("TextLabel", {
        Parent = frame,
        Text = label,
        Size = UDim2.new(0.52, 0, 1, 0),
        BackgroundTransparency = 1,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        ZIndex = 8
    })
    local btnBg = new("Frame", {
        Parent = frame,
        Size = UDim2.new(0.45, 0, 0, 24),
        Position = UDim2.new(0.55, 0, 0.5, -12),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = panelTransparency,
        BorderSizePixel = 0,
        ZIndex = 8
    })
    new("UICorner", {Parent = btnBg, CornerRadius = UDim.new(0, 4)})
    
    local initialValue = Library.ConfigSystem.Get(configPath, defaultValue)
    
    local bindBtn = new("TextButton", {
        Parent = btnBg,
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        BackgroundTransparency = 1,
        Text = initialValue ~= nil and tostring(initialValue) or "None",
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.small,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 9
    })
    
    local isBinding = false
    local bindConn = nil

    self:AddConnection("bind_" .. label .. tostring(bindBtn), bindBtn.MouseButton1Click:Connect(function()
        if isBinding then return end
        isBinding = true
        bindBtn.Text = "..."
        
        bindConn = game:GetService("UserInputService").InputBegan:Connect(function(input, gp)
            if input.UserInputType == Enum.UserInputType.Keyboard then
                local k = input.KeyCode
                if k == Enum.KeyCode.Unknown then return end
                
                isBinding = false
                if bindConn then bindConn:Disconnect(); bindConn = nil end
                
                local kName = k.Name
                if k == Enum.KeyCode.Escape then
                    kName = "None"
                end
                
                bindBtn.Text = kName
                
                if configPath then
                    Library.ConfigSystem.Set(configPath, kName)
                    MarkDirty()
                end
                if callback then callback(kName) end
            end
        end)
    end))
    
    RegisterCallback(configPath, callback, "bind", defaultValue, function(val)
        bindBtn.Text = tostring(val ~= nil and val or defaultValue or "None")
    end)
    
    if callback and initialValue ~= nil then
        callback(tostring(initialValue))
    end
    
    return frame
end
function Library:CreateButton(parent, label, callback)
    local btnFrame = new("Frame", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 8
    })
    new("UICorner", {Parent = btnFrame, CornerRadius = UDim.new(0, 5)})
    local button = new("TextButton", {
        Parent = btnFrame,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = colors.bg3,
        BackgroundTransparency = panelTransparency,
        Text = label,
        Font = Enum.Font.GothamBold,
        TextSize = fontSize.normal,
        TextColor3 = colors.text,
        AutoButtonColor = true,
        ZIndex = 9
    })
    new("UICorner", {Parent = button, CornerRadius = UDim.new(0, 5)})

    local isClicking = false

    self:AddConnection("btn_click_" .. label .. tostring(button), button.MouseButton1Click:Connect(function()
        if isClicking then return end
        isClicking = true

        if callback then
            task.spawn(function()
                pcall(callback)
            end)
        end

        task.delay(0.1, function()
            isClicking = false
        end)
    end))
    
    return btnFrame
end

function Library:Initialize()
    if self._initialized then return end
    self._initialized = true
    ExecuteConfigCallbacks()
    if self._pendingWindowObj then
        pcall(function()
            self:_createConfigTab(self._pendingWindowObj)
        end)
        self._pendingWindowObj = nil
    end
    self:AddConnection("playerRemoving", Players.PlayerRemoving:Connect(function(plr)
        if plr == localPlayer then
            if Library._saveThread then
                pcall(function() task.cancel(Library._saveThread) end)
                Library._saveThread = nil
            end
            isDirty = false
            pcall(function() Library.ConfigSystem.Save() end)
        end
    end))
end

function Library:MakeNotify(config)
    config = config or {}
    local title   = config.Title or "Notification"
    local desc    = config.Description or ""
    local content = config.Content or ""
    local color   = config.Color or colors.primary
    local delay   = config.Delay or 3
    if not self._gui then return end
    self._activeNotifs = self._activeNotifs or {}
    for i = #self._activeNotifs, 1, -1 do
        local old = self._activeNotifs[i]
        table.remove(self._activeNotifs, i)
        pcall(function()
            if old and old.Parent then old:Destroy() end
        end)
    end
    local notif = new("Frame", {
        Parent = self._gui,
        Size = UDim2.new(0, 0, 0, 0),
        Position = UDim2.new(1, -20, 1, -20),
        AnchorPoint = Vector2.new(1, 1),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundColor3 = colors.bg1,
        BorderSizePixel = 0,
        ZIndex = 200
    })
    table.insert(self._activeNotifs, notif)
    
    new("UIGradient", {
        Parent = notif,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.3, 0.5), 
            NumberSequenceKeypoint.new(1, 0.2)
        })
    })

    new("Frame", {
        Parent = notif,
        Size = UDim2.new(0, 3, 1, 0),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        ZIndex = 201
    })

    local textContainer = new("Frame", {
        Parent = notif,
        Size = UDim2.new(0, 0, 0, 0),
        Position = UDim2.new(0, 15, 0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1,
        ZIndex = 201
    })
    
    new("UIPadding", {
        Parent = textContainer,
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 15)
    })

    new("UIListLayout", {
        Parent = textContainer,
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4)
    })

    if title and title ~= "" then
        local tLbl = new("TextLabel", {
            Parent = textContainer,
            Text = title,
            Size = UDim2.new(0, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = color,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            LayoutOrder = 1,
            ZIndex = 201
        })
        new("UISizeConstraint", { Parent = tLbl, MaxSize = Vector2.new(240, 9999) })
    end
    
    if desc and desc ~= "" then
        local dLbl = new("TextLabel", {
            Parent = textContainer,
            Text = desc,
            Size = UDim2.new(0, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextColor3 = colors.text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            LayoutOrder = 2,
            ZIndex = 201
        })
        new("UISizeConstraint", { Parent = dLbl, MaxSize = Vector2.new(240, 9999) })
    end

    if content and content ~= "" then
        local cLbl = new("TextLabel", {
            Parent = textContainer,
            Text = content,
            Size = UDim2.new(0, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextColor3 = colors.textDim,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            LayoutOrder = 3,
            ZIndex = 201
        })
        new("UISizeConstraint", { Parent = cLbl, MaxSize = Vector2.new(240, 9999) })
    end
    task.delay(delay, function()
        pcall(function()
            if notif and notif.Parent then
                notif:Destroy()
            end
        end)
    end)
    notif.Destroying:Connect(function()
        if not self._activeNotifs then return end
        for i = #self._activeNotifs, 1, -1 do
            if self._activeNotifs[i] == notif then
                table.remove(self._activeNotifs, i)
            end
        end
    end)
end

function Library:_createConfigTab(WindowObject)
    local configTab = WindowObject:AddTab({ Name = "Config", Icon = "loop" })
    local autoSaveSection = configTab:AddSection("Auto Save")
    autoSaveSection:AddToggle({
        Title    = "Auto Save Config",
        Default  = true,
        NoSave   = true,
        Callback = function(val)
            _G.AutoSaveEnabled = val
            self:MakeNotify({
                Title       = "Auto Save",
                Description = val and "Auto Save diaktifkan" or "Auto Save dinonaktifkan",
                Delay       = 2,
            })
        end,
    })

    local mgmtSection = configTab:AddSection("Config Management")
    local function setBtnColor(frame, color)
        local btn = frame:FindFirstChildWhichIsA("TextButton")
        if btn then btn.BackgroundColor3 = color end
    end
    mgmtSection:AddButton({
        Title    = "Save Config Now",
        Callback = function()
            local ok = Library.ConfigSystem.Save()
            self:MakeNotify({
                Title       = "Config",
                Description = ok and "Config berhasil disimpan!" or "Gagal menyimpan config.",
                Color       = ok and colors.success or Color3.fromRGB(220, 50, 50),
                Delay       = 2,
            })
        end,
    })

    local resetConfirm = false
    local resetThread  = nil
    local resetBtnFrame
    resetBtnFrame = mgmtSection:AddButton({
        Title = "Reset to Default",
        Callback = function()
            if not resetConfirm then
                resetConfirm = true
                local btn = resetBtnFrame:FindFirstChildWhichIsA("TextButton")
                if btn then btn.Text = "Klik lagi untuk konfirmasi!" end
                setBtnColor(resetBtnFrame, Color3.fromRGB(255, 100, 0))
                if resetThread then task.cancel(resetThread) end
                resetThread = task.delay(3, function()
                    resetConfirm = false
                    local b = resetBtnFrame:FindFirstChildWhichIsA("TextButton")
                    if b then b.Text = "Reset to Default" end
                    setBtnColor(resetBtnFrame, colors.primary)
                end)
            else
                if resetThread then task.cancel(resetThread) end
                resetConfirm = false
                local btn = resetBtnFrame:FindFirstChildWhichIsA("TextButton")
                if btn then btn.Text = "Reset to Default" end
                setBtnColor(resetBtnFrame, colors.primary)
                Library.ConfigSystem.Reset()
                ExecuteConfigCallbacks()
                self:MakeNotify({
                    Title       = "Config",
                    Description = "Semua settingan direset ke default!",
                    Color       = Color3.fromRGB(220, 50, 50),
                    Delay       = 3,
                })
            end
        end
    })
    mgmtSection:AddParagraph({
        Title   = "⚠️ Perhatian",
        Content = "Setelah melakukan Reset to Default, beberapa settingan seperti Toggle dan nilai Input akan langsung ter-update di UI.\n\n"
               .. "Namun untuk settingan yang mempengaruhi karakter, kecepatan, atau fitur aktif lainnya — kamu perlu Rejoin / Respawn agar perubahan berlaku sepenuhnya.\n\n"
               .. "File config disimpan otomatis setiap 2 detik jika Auto Save aktif. Pastikan Auto Save ON sebelum keluar game agar settinganmu tidak hilang.",
    })
    local deleteConfirm = false
    local deleteThread  = nil
    local deleteBtnFrame
    deleteBtnFrame = mgmtSection:AddButton({
        Title = "Delete Config File",
        Callback = function()
            if not deleteConfirm then
                deleteConfirm = true
                local btn = deleteBtnFrame:FindFirstChildWhichIsA("TextButton")
                if btn then btn.Text = "Klik lagi untuk konfirmasi!" end
                setBtnColor(deleteBtnFrame, Color3.fromRGB(200, 30, 30))
                if deleteThread then task.cancel(deleteThread) end
                deleteThread = task.delay(3, function()
                    deleteConfirm = false
                    local b = deleteBtnFrame:FindFirstChildWhichIsA("TextButton")
                    if b then b.Text = "Delete Config File" end
                    setBtnColor(deleteBtnFrame, colors.primary)
                end)
            else
                if deleteThread then task.cancel(deleteThread) end
                deleteConfirm = false
                local btn = deleteBtnFrame:FindFirstChildWhichIsA("TextButton")
                if btn then btn.Text = "Delete Config File" end
                setBtnColor(deleteBtnFrame, colors.primary)
                Library.ConfigSystem.Delete()
                self:MakeNotify({
                    Title       = "Config",
                    Description = "File config telah dihapus.",
                    Color       = Color3.fromRGB(220, 50, 50),
                    Delay       = 2,
                })
            end
        end
    })
end

function Library:Window(config)
    config = config or {}
    self:CreateWindow({
        Name     = "LynxGui",
        Title    = config.Title or "LynX",
        Subtitle = config.Footer or ""
    })
    Library.ConfigSystem.Load()
    local WindowObject = {}
    WindowObject._library = self
    WindowObject._tabs    = {}
    WindowObject._tabOrder = 0
    Library._initialized = false
    Library._pendingWindowObj = WindowObject
    function WindowObject:Build()
        if not Library._initialized then
            Library:Initialize()
        end
    end
    function WindowObject:AddTab(tabConfig)
        tabConfig = tabConfig or {}
        local tabName = tabConfig.Name or "Tab"
        local tabIcon = tabConfig.Icon or ""
        local iconMap = {
            ["player"]    = "rbxassetid://12120698352",
            ["web"]       = "rbxassetid://137601480983962",
            ["bag"]       = "rbxassetid://8601111810",
            ["shop"]      = "rbxassetid://4985385964",
            ["cart"]      = "rbxassetid://128874923961846",
            ["plug"]      = "rbxassetid://137601480983962",
            ["settings"]  = "rbxassetid://70386228443175",
            ["loop"]      = "rbxassetid://122032243989747",
            ["gps"]       = "rbxassetid://78381660144034",
            ["compas"]    = "rbxassetid://125300760963399",
            ["gamepad"]   = "rbxassetid://84173963561612",
            ["boss"]      = "rbxassetid://13132186360",
            ["scroll"]    = "rbxassetid://114127804740858",
            ["menu"]      = "rbxassetid://6340513838",
            ["crosshair"] = "rbxassetid://12614416478",
            ["user"]      = "rbxassetid://108483430622128",
            ["stat"]      = "rbxassetid://12094445329",
            ["eyes"]      = "rbxassetid://14321059114",
            ["sword"]     = "rbxassetid://82472368671405",
            ["discord"]   = "rbxassetid://94434236999817",
            ["star"]      = "rbxassetid://107005941750079",
            ["skeleton"]  = "rbxassetid://17313330026",
            ["payment"]   = "rbxassetid://18747025078",
            ["scan"]      = "rbxassetid://109869955247116",
            ["alert"]     = "rbxassetid://73186275216515",
            ["question"]  = "rbxassetid://17510196486",
            ["idea"]      = "rbxassetid://16833255748",
            ["strom"]     = "rbxassetid://13321880293",
            ["water"]     = "rbxassetid://100076212630732",
            ["dcs"]       = "rbxassetid://15310731934",
            ["start"]     = "rbxassetid://108886429866687",
            ["next"]      = "rbxassetid://12662718374",
            ["rod"]       = "rbxassetid://103247953194129",
            ["fish"]      = "rbxassetid://97167558235554",
            ["send"]      = "rbxassetid://122775063389583",
            ["home"]      = "rbxassetid://86450224791749",
        }
        local iconId = ""
        if tabIcon and tabIcon ~= "" then
            iconId = iconMap[tabIcon:lower()] or ""
        end
        self._tabOrder = (self._tabOrder or 0) + 1
        local page = self._library:CreatePage(tabName, tabName, iconId, self._tabOrder)
        local TabObject = {}
        TabObject._page      = page
        TabObject._library   = self._library
        TabObject._sections  = {}
        function TabObject:AddSection(sectionTitle, isOpen, isLocked)
            sectionTitle = sectionTitle or "Section"
            local category, sectionExpand = self._library:CreateCategory(self._page, sectionTitle, isOpen, isLocked)
            local SectionObject = {}
            SectionObject._container  = category
            SectionObject._library    = self._library
            SectionObject._layoutOrder = 0
            local function registerFeature(featureName, featureFrame, featureKind)
                if not featureName or not featureFrame then return end
                local lib = self._library
                lib._searchIndex = lib._searchIndex or {}
                table.insert(lib._searchIndex, {
                    name = tostring(featureName),
                    lname = tostring(featureName):lower(),
                    frame = featureFrame,
                    pageName = tabName,
                    sectionTitle = sectionTitle,
                    kind = featureKind,
                    expand = sectionExpand,
                })
            end
            local function getNextLayoutOrder()
                SectionObject._layoutOrder = SectionObject._layoutOrder + 1
                return SectionObject._layoutOrder
            end
            function SectionObject:AddToggle(toggleConfig)
                toggleConfig = toggleConfig or {}
                local title      = toggleConfig.Title or "Toggle"
                local default    = toggleConfig.Default or false
                local callback   = toggleConfig.Callback
                local noSave     = toggleConfig.NoSave or false
                local configPath = noSave and nil or ("Toggles." .. title:gsub("%s+", "_"))
                local toggleObj = { _value = default }
                local wrappedCallback = function(val)
                    toggleObj._value = val
                    if callback then callback(val) end
                end
                local toggleResult = self._library:CreateToggle(self._container, title, configPath, wrappedCallback, noSave, default)
                local frame = toggleResult and toggleResult.frame or toggleResult
                if frame then frame.LayoutOrder = getNextLayoutOrder() end
                registerFeature(title, frame, "Toggle")
                function toggleObj:SetValue(val)
                    self._value = val
                    if toggleResult and toggleResult.set then
                        toggleResult.set(val)
                    end
                    if callback then callback(val) end
                end
                function toggleObj:GetValue()
                    return self._value
                end
                return toggleObj
            end
            function SectionObject:AddDropdown(dropdownConfig)
                dropdownConfig = dropdownConfig or {}
                local title      = dropdownConfig.Title or "Dropdown"
                local options    = dropdownConfig.Options or {}
                local default    = dropdownConfig.Default
                local callback   = dropdownConfig.Callback
                local noSave     = dropdownConfig.NoSave or false
                local isMulti    = dropdownConfig.Multi or false
                local configPath = noSave and nil or ((isMulti and "MultiDropdowns." or "Dropdowns.") .. title:gsub("%s+", "_"))
                local uniqueId   = title:gsub("%s+", "_")
                if isMulti then
                    local frame = self._library:CreateMultiDropdown(self._container, title, nil, options, configPath, callback, uniqueId)
                    if frame then frame.LayoutOrder = getNextLayoutOrder() end
                    registerFeature(title, frame, "Dropdown")

                    local dropdownObj = {
                        _options = options,
                        SetOptions = function(self, newOptions)
                            self._options = newOptions
                            local flagObj = Library.flags[uniqueId]
                            if flagObj and flagObj.Refresh then
                                flagObj:Refresh(newOptions)
                            end
                        end
                    }
                    return dropdownObj
                end
                if default and configPath then
                    local current = Library.ConfigSystem.Get(configPath, nil)
                    if current == nil then
                        Library.ConfigSystem.Set(configPath, default)
                    end
                end
                local frame = self._library:CreateDropdown(self._container, title, nil, options, configPath, callback, uniqueId, default)
                if frame then frame.LayoutOrder = getNextLayoutOrder() end
                registerFeature(title, frame, "Dropdown")
                local dropdownObj = {
                    _options = options,
                    SetOptions = function(self, newOptions)
                        self._options = newOptions
                        local flagObj = Library.flags[uniqueId]
                        if flagObj and flagObj.Refresh then
                            flagObj:Refresh(newOptions)
                        end
                    end,
                    GetOptions = function(self)
                        return self._options
                    end
                }
                return dropdownObj
            end
            function SectionObject:AddInput(inputConfig)
                inputConfig = inputConfig or {}
                local title       = inputConfig.Title or "Input"
                local default     = inputConfig.Default or ""
                local placeholder = inputConfig.Placeholder or ""
                local callback    = inputConfig.Callback
                local noSave      = inputConfig.NoSave or false
                local configPath  = noSave and nil or ("Inputs." .. title:gsub("%s+", "_"))
                
                local frame = self._library:CreateInput(self._container, title, configPath, default, callback)
                if frame then frame.LayoutOrder = getNextLayoutOrder() end
                registerFeature(title, frame, "Input")
                return {
                    SetValue = function(self, val) end
                }
            end
            
            function SectionObject:AddBind(bindConfig)
                bindConfig = bindConfig or {}
                local title       = bindConfig.Title or "Bind"
                local default     = bindConfig.Default or "None"
                local callback    = bindConfig.Callback
                local noSave      = bindConfig.NoSave or false
                local configPath  = noSave and nil or ("Binds." .. title:gsub("%s+", "_"))
                
                local frame = self._library:CreateBind(self._container, title, configPath, default, callback)
                if frame then frame.LayoutOrder = getNextLayoutOrder() end
                registerFeature(title, frame, "Bind")
                return {
                    SetValue = function(self, val) end
                }
            end
            
            function SectionObject:AddHotkey(hotkeyConfig)
                hotkeyConfig = hotkeyConfig or {}
                local title    = hotkeyConfig.Title or "Hotkey"
                local default  = hotkeyConfig.Default or ""
                local callback = hotkeyConfig.Callback
                
                local function parseKeyString(val)
                    local v = tostring(val)
                    
                    local ok, k = pcall(function() return Enum.KeyCode[v] end)
                    if ok and k then return k end
                    
                    local upperVal = string.upper(v)
                    ok, k = pcall(function() return Enum.KeyCode[upperVal] end)
                    if ok and k then return k end
                    
                    local map = {
                        ["1"] = Enum.KeyCode.One, ["2"] = Enum.KeyCode.Two, ["3"] = Enum.KeyCode.Three,
                        ["4"] = Enum.KeyCode.Four, ["5"] = Enum.KeyCode.Five, ["6"] = Enum.KeyCode.Six,
                        ["7"] = Enum.KeyCode.Seven, ["8"] = Enum.KeyCode.Eight, ["9"] = Enum.KeyCode.Nine,
                        ["0"] = Enum.KeyCode.Zero, ["-"] = Enum.KeyCode.Minus, ["="] = Enum.KeyCode.Equals,
                        ["["] = Enum.KeyCode.LeftBracket, ["]"] = Enum.KeyCode.RightBracket,
                        ["\\"] = Enum.KeyCode.BackSlash, [";"] = Enum.KeyCode.Semicolon,
                        ["'"] = Enum.KeyCode.Quote, [","] = Enum.KeyCode.Comma, ["."] = Enum.KeyCode.Period,
                        ["/"] = Enum.KeyCode.Slash, ["`"] = Enum.KeyCode.Backquote,
                        ["SPACE"] = Enum.KeyCode.Space, ["TAB"] = Enum.KeyCode.Tab,
                        ["LSHIFT"] = Enum.KeyCode.LeftShift, ["RSHIFT"] = Enum.KeyCode.RightShift,
                        ["LCTRL"] = Enum.KeyCode.LeftControl, ["RCTRL"] = Enum.KeyCode.RightControl,
                        ["LALT"] = Enum.KeyCode.LeftAlt, ["RALT"] = Enum.KeyCode.RightAlt,
                    }
                    return map[upperVal] or map[v]
                end

                return self:AddBind({
                    Title = title,
                    Default = default,
                    Callback = function(val)
                        if tostring(val) == "None" then return end
                        local k = parseKeyString(val)
                        if k then
                            local hotkeyStr = string.upper(tostring(val))
                            if hotkeyStr == "LEFTSHIFT" then hotkeyStr = "LSHIFT" end
                            if hotkeyStr == "RIGHTSHIFT" then hotkeyStr = "RSHIFT" end
                            if hotkeyStr == "LEFTCONTROL" then hotkeyStr = "LCTRL" end
                            if hotkeyStr == "RIGHTCONTROL" then hotkeyStr = "RCTRL" end
                            if hotkeyStr == "LEFTALT" then hotkeyStr = "LALT" end
                            if hotkeyStr == "RIGHTALT" then hotkeyStr = "RALT" end
                            
                            if callback then callback(k, hotkeyStr) end
                        else
                            Library:MakeNotify({
                                Title       = "Error",
                                Description = "Invalid key!",
                                Delay       = 3,
                            })
                        end
                    end
                })
            end
            
            function SectionObject:AddButton(buttonConfig)
                buttonConfig = buttonConfig or {}
                local title    = buttonConfig.Title or "Button"
                local callback = buttonConfig.Callback or function() end
                local frame = self._library:CreateButton(self._container, title, callback)
                if frame then frame.LayoutOrder = getNextLayoutOrder() end
                registerFeature(title, frame, "Button")
                return frame
            end
            function SectionObject:AddParagraph(paragraphConfig)
                paragraphConfig = paragraphConfig or {}
                local title   = formatRichText(paragraphConfig.Title or "")
                local content = formatRichText(paragraphConfig.Content or "")
                local useRich = paragraphConfig.RichText ~= false

                local PADDING_V = 20
                local GAP       = 6

                local frame = new("Frame", {
                    Parent = self._container,
                    Size = UDim2.new(1, 0, 0, PADDING_V),
                    BackgroundColor3 = colors.bg2,
                    BackgroundTransparency = 0.5,
                    ZIndex = 7,
                    LayoutOrder = getNextLayoutOrder()
                })
                new("UICorner", {Parent = frame, CornerRadius = UDim.new(0, 5)})
                new("UIStroke", {Parent = frame, Color = colors.border, Thickness = 1, Transparency = 0.65})
                new("UIPadding", {
                    Parent = frame,
                    PaddingTop    = UDim.new(0, 10),
                    PaddingBottom = UDim.new(0, 10),
                    PaddingLeft   = UDim.new(0, 12),
                    PaddingRight  = UDim.new(0, 12)
                })
                new("UIListLayout", {
                    Parent = frame,
                    Padding = UDim.new(0, GAP),
                    SortOrder = Enum.SortOrder.LayoutOrder
                })

                local titleLabel
                if title ~= "" then
                    titleLabel = new("TextLabel", {
                        Parent = frame,
                        Name = "TitleLabel",
                        LayoutOrder = 1,
                        Text = title,
                        Size = UDim2.new(1, 0, 0, 14),
                        BackgroundTransparency = 1,
                        Font = Enum.Font.GothamBold,
                        TextSize = fontSize.normal,
                        TextColor3 = colors.primary,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextYAlignment = Enum.TextYAlignment.Top,
                        TextWrapped = true,
                        RichText = useRich,
                        ZIndex = 8
                    })
                end

                local contentLabel = new("TextLabel", {
                    Parent = frame,
                    Name = "ContentLabel",
                    LayoutOrder = 2,
                    Text = content,
                    Size = UDim2.new(1, 0, 0, 12),
                    BackgroundTransparency = 1,
                    Font = Enum.Font.GothamMedium,
                    TextSize = fontSize.small,
                    TextColor3 = colors.textDim,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextYAlignment = Enum.TextYAlignment.Top,
                    TextWrapped = true,
                    RichText = useRich,
                    ZIndex = 8
                })

                local reflowPending = false
                local function reflow()
                    if reflowPending then return end
                    reflowPending = true
                    task.defer(function()
                        reflowPending = false
                        if not frame or not frame.Parent then return end
                        local total = PADDING_V
                        if titleLabel and titleLabel.Parent then
                            local h = math.max(titleLabel.TextBounds.Y, 14)
                            titleLabel.Size = UDim2.new(1, 0, 0, h)
                            total = total + h
                        end
                        if contentLabel and contentLabel.Parent then
                            local h = math.max(contentLabel.TextBounds.Y, 12)
                            contentLabel.Size = UDim2.new(1, 0, 0, h)
                            total = total + h
                        end
                        if titleLabel and titleLabel.Parent and contentLabel and contentLabel.Parent then
                            total = total + GAP
                        end
                        frame.Size = UDim2.new(1, 0, 0, total)
                    end)
                end

                if titleLabel then
                    titleLabel:GetPropertyChangedSignal("TextBounds"):Connect(reflow)
                end
                contentLabel:GetPropertyChangedSignal("TextBounds"):Connect(reflow)
                task.defer(reflow)

                return {
                    _frame        = frame,
                    _titleLabel   = titleLabel,
                    _contentLabel = contentLabel,
                    SetTitle = function(self, newTitle)
                        if self._titleLabel then
                            self._titleLabel.Text = formatRichText(newTitle or "")
                            self._titleLabel.Visible = (newTitle or "") ~= ""
                        end
                    end,
                    SetContent = function(self, newContent)
                        if self._contentLabel then
                            self._contentLabel.Text = formatRichText(newContent or "")
                        end
                    end,
                    GetTitle = function(self)
                        return self._titleLabel and self._titleLabel.Text or ""
                    end,
                    GetContent = function(self)
                        return self._contentLabel and self._contentLabel.Text or ""
                    end
                }
            end
            table.insert(self._sections, SectionObject)
            return SectionObject
        end
        if self._tabOrder == 1 then
            self._library:SetFirstPage(tabName)
        end
        table.insert(self._tabs, TabObject)
        return TabObject
    end
    return WindowObject
end

Library.FeatureHUDManager = {}
Library.FeatureHUDManager.Buttons = {}
Library.FeatureHUDManager.Rows = {}

Library.FeatureHUDManager.Gui = new("ScreenGui", {
    Name = "FeatureHUDGUI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true
})

if gethui then
    Library.FeatureHUDManager.Gui.Parent = gethui()
elseif CoreGui:FindFirstChild("RobloxGui") then
    Library.FeatureHUDManager.Gui.Parent = CoreGui
else
    Library.FeatureHUDManager.Gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

local MainContainer = new("Frame", {
    Parent = Library.FeatureHUDManager.Gui,
    Name = "MainContainer",
    BackgroundTransparency = 1,
    Position = UDim2.new(1, -15, 0, 15),
    AnchorPoint = Vector2.new(1, 0),
    Size = UDim2.new(0, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.XY
})

local PCContainer = new("Frame", {
    Parent = Library.FeatureHUDManager.Gui,
    Name = "PCContainer",
    BackgroundTransparency = 1,
    Position = UDim2.new(1, -15, 0, 15),
    AnchorPoint = Vector2.new(1, 0),
    Size = UDim2.new(0, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.XY
})

local hudScale = new("UIScale", {Parent = MainContainer})
local pcScale = new("UIScale", {Parent = PCContainer})

Library.FeatureHUDManager.baseScale = 1
local function updateHUDScale()
    if not Library.FeatureHUDManager.Gui or not Library.FeatureHUDManager.Gui.Parent then return end
    local vSize = workspace.CurrentCamera.ViewportSize
    Library.FeatureHUDManager.baseScale = math.clamp(vSize.Y / 720, 0.6, 1.8)
    hudScale.Scale = Library.FeatureHUDManager.baseScale
    pcScale.Scale = Library.FeatureHUDManager.baseScale
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateHUDScale)
updateHUDScale()

new("UIListLayout", {
    Parent = MainContainer,
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Right,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 10)
})

new("UIListLayout", {
    Parent = PCContainer,
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Right,
    VerticalAlignment = Enum.VerticalAlignment.Top,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 4)
})

if _G.FeatureHUDConn then 
    _G.FeatureHUDConn:Disconnect() 
    _G.FeatureHUDConn = nil 
end

function Library.FeatureHUDManager:GetRow()
    local rowCount = #self.Rows
    local lastRow = self.Rows[rowCount]
    if not lastRow or (#lastRow:GetChildren() - 1) >= 3 then
        lastRow = new("Frame", {
            Parent = MainContainer,
            Name = "Row" .. (rowCount + 1),
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.XY,
            LayoutOrder = rowCount + 1
        })
        new("UIListLayout", {
            Parent = lastRow,
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 10)
        })
        table.insert(self.Rows, lastRow)
    end
    return lastRow
end

function Library.FeatureHUDManager:AddButton(text, clickCallback, hotkeyString)
    if not isMobile then
        return self:AddPCIndicator(text, hotkeyString)
    end
    
    local row = self:GetRow()
    
    local container = new("Frame", {
        Parent = row,
        Name = "HUDButton_" .. text,
        Size = UDim2.new(0, 0, 0, 56),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Color3.fromRGB(20, 10, 0),
        BackgroundTransparency = 0.6,
        BorderSizePixel = 0,
        LayoutOrder = #self.Buttons
    })
    local overlay = new("Frame", {
        Parent = container,
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5
    })
    new("UICorner", {Parent = overlay, CornerRadius = UDim.new(0, 6)})
    
    new("UICorner", {Parent = container, CornerRadius = UDim.new(0, 6)})
    
    local stroke = new("UIStroke", {
        Parent = container,
        Color = Color3.fromRGB(255, 120, 0),
        Thickness = 1
    })
    
    new("UIGradient", {
        Parent = stroke,
        Rotation = 90,
        Color = ColorSequence.new{
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 0)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 80, 0)),
        }
    })
    
    new("UIGradient", {
        Parent = container,
        Rotation = 90,
        Color = ColorSequence.new{
            ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 20, 0)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 5, 0)),
        }
    })

    new("UIPadding", {
        Parent = container,
        PaddingLeft = UDim.new(0, 32),
        PaddingRight = UDim.new(0, 32)
    })
    
    local label = new("TextLabel", {
        Parent = container,
        Name = "Label",
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 20,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        RichText = true,
        Text = "<b>" .. text .. "</b>"
    })
    
    local btn = new("TextButton", {
        Parent = container,
        Name = "ClickArea",
        Size = UDim2.fromScale(1, 1),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        ZIndex = 10
    })
    
    local dragging = false
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            TweenService:Create(overlay, TweenInfo.new(0.1), {BackgroundTransparency = 0.5}):Play()
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    TweenService:Create(overlay, TweenInfo.new(0.1), {BackgroundTransparency = 1}):Play()
                end
            end)
        end
    end)
    
    if clickCallback then
        btn.MouseButton1Click:Connect(clickCallback)
    end
    
    local ref = {
        isPC = false,
        container = container,
        UpdateHotkey = function(self, newHotkey) end,
        UpdateText = function(self, newText)
            if label then label.Text = "<b>" .. tostring(newText) .. "</b>" end
        end
    }
    table.insert(self.Buttons, ref)
    return ref
end

function Library.FeatureHUDManager:AddPCIndicator(text, hotkeyString)
    local container = new("Frame", {
        Parent = PCContainer,
        Name = "PCIndicator_" .. text,
        Size = UDim2.new(0, 0, 0, 24),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = colors.bg1,
        BorderSizePixel = 0,
        LayoutOrder = #self.Buttons
    })
    
    new("UIGradient", {
        Parent = container,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.3, 0.5), 
            NumberSequenceKeypoint.new(1, 0.2)
        })
    })

    new("UIListLayout", {
        Parent = container,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder
    })

    new("Frame", {
        Parent = container,
        Size = UDim2.new(0, 40, 1, 0),
        BackgroundTransparency = 1,
        LayoutOrder = 1
    })

    local label = new("TextLabel", {
        Parent = container,
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = colors.text,
        RichText = true,
        LayoutOrder = 2
    })
    
    new("Frame", {
        Parent = container,
        Size = UDim2.new(0, 12, 1, 0),
        BackgroundTransparency = 1,
        LayoutOrder = 3
    })

    new("Frame", {
        Parent = container,
        Size = UDim2.new(0, 3, 1, 0),
        BackgroundColor3 = colors.primary,
        BorderSizePixel = 0,
        LayoutOrder = 4
    })

    local ref = {
        isPC = true,
        container = container,
        text = text,
        label = label,
        hotkey = hotkeyString or "None"
    }
    
    function ref:UpdateHotkey(newHotkey)
        local hexColor = string.format("%02X%02X%02X", 
            math.floor(colors.primary.R*255), 
            math.floor(colors.primary.G*255), 
            math.floor(colors.primary.B*255))
        
        self.hotkey = (newHotkey and tostring(newHotkey) ~= "") and tostring(newHotkey) or "None"
        self.label.Text = string.format("<font color='#%s'>[%s]</font>  %s", hexColor, self.hotkey, self.text)
    end
    
    function ref:UpdateText(newText)
        self.text = tostring(newText)
        self:UpdateHotkey(self.hotkey)
    end
    
    ref:UpdateHotkey(hotkeyString)

    table.insert(self.Buttons, ref)
    return ref
end

function Library.FeatureHUDManager:RemoveButton(ref)
    if not ref then return end
    
    local container = type(ref) == "table" and ref.container or ref

    for i, b in ipairs(self.Buttons) do
        local bContainer = type(b) == "table" and b.container or b
        if bContainer == container or b == ref then
            table.remove(self.Buttons, i)
            break
        end
    end
    
    if container and container.Parent then
        container:Destroy()
    end
    
    if not isMobile then return end
    
    local tempBtns = {}
    for _, b in ipairs(self.Buttons) do
        local bContainer = type(b) == "table" and b.container or b
        if bContainer then
            local isAlive = false
            pcall(function()
                if bContainer.Parent ~= nil then
                    isAlive = true
                end
            end)
            if isAlive then
                table.insert(tempBtns, b)
            end
        end
    end
    
    self.Buttons = {}
    for _, r in ipairs(self.Rows) do
        pcall(function() r:Destroy() end)
    end
    self.Rows = {}
    
    for _, b in ipairs(tempBtns) do
        local bContainer = type(b) == "table" and b.container or b
        local r = self:GetRow()
        local s, _ = pcall(function()
            bContainer.Parent = r
        end)
        if s then
            table.insert(self.Buttons, b)
        end
    end
end

return Library
