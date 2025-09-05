-- Auto Fishing dengan Rayfield UI
-- Pastikan Rayfield bisa di-load (eksploit mendukung game:HttpGet)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- Load Rayfield
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Network references
local netRoot = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net")
local RF_Charge = netRoot:WaitForChild("RF/ChargeFishingRod")
local RF_Start  = netRoot:WaitForChild("RF/RequestFishingMinigameStarted")
local RE_Complete = netRoot:WaitForChild("RE/FishingCompleted")
local FishingController = require(ReplicatedStorage.Controllers.FishingController)
local HttpService = game:GetService("HttpService")

-- Config (default values)
local RADIUS = 5                      -- tetap bisa diubah di kode kalau mau
local CHARGE_TO_RELEASE_DELAY = 1.1    -- fixed sesuai request
local RELEASE_TO_FIRST_CATCH_DELAY = 1.5 -- fixed sesuai request
local CATCH_COUNT = 3
local CATCH_DELAY = 0.7
local LOOP_DELAY = 1
-- (MAX_CYCLES & cycle tracking dihapus sesuai permintaan)

-- State
local running = false
-- cycle counter dihapus
local autoStart = false -- toggle Auto Fish
local currentStage = "Idle"
local animEnabled = false
local animThread
local savedPositions = {} -- [name] = CFrame
local posDropdown = nil
local selectedPos = nil
local lastPosInput = ""
local SAVE_FILE = "fishing_saved_positions.json"
local fileLoaded = false

-- Safe exploit file API references
local exploitWriteFile = (getfenv and rawget(getfenv(), "writefile")) or nil
local exploitReadFile  = (getfenv and rawget(getfenv(), "readfile")) or nil
local exploitIsFile    = (getfenv and rawget(getfenv(), "isfile")) or nil

-- Serialize CFrame to array
local function cframeToArray(cf)
    return {cf:GetComponents()}
end

local function arrayToCFrame(t)
    if type(t) == "table" and #t == 12 then
        return CFrame.new(unpack(t))
    end
    return nil
end

local function saveToDisk()
    if typeof(exploitWriteFile) ~= "function" then return end
    local payload = {}
    for name, cf in pairs(savedPositions) do
        payload[name] = cframeToArray(cf)
    end
    local ok, data = pcall(function()
        return HttpService:JSONEncode(payload)
    end)
    if ok then
        pcall(function() exploitWriteFile(SAVE_FILE, data) end)
    end
end

local function loadFromDisk()
    if typeof(exploitIsFile) ~= "function" or typeof(exploitReadFile) ~= "function" then return end
    local exists = false
    pcall(function()
        exists = exploitIsFile(SAVE_FILE)
    end)
    if not exists then return end
    local ok, content = pcall(function() return exploitReadFile(SAVE_FILE) end)
    if not ok or not content or content == "" then return end
    local ok2, decoded = pcall(function() return HttpService:JSONDecode(content) end)
    if not ok2 or type(decoded) ~= "table" then return end
    for name, arr in pairs(decoded) do
        local cf = arrayToCFrame(arr)
        if cf then
            savedPositions[name] = cf
        end
    end
    fileLoaded = true
end
local noAnimToggle
local animToggle

-- Helpers
local function notify(msg)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {Title = "Fishing", Text = msg, Duration = 2})
    end)
    print("[Fishing] " .. msg)
end

local function getRoot()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

local function randomOffset(radius)
    local angle = math.random() * math.pi * 2
    local r = math.random() * radius
    return math.cos(angle) * r, math.sin(angle) * r
end

-- Core loop
local function loop()
    getRoot()
    while running do
        -- Charge
        currentStage = "Charge"
        RF_Charge:InvokeServer(tick())
        task.wait(CHARGE_TO_RELEASE_DELAY)
        -- Release
        local dx, dz = randomOffset(RADIUS)
        currentStage = "Release"
        RF_Start:InvokeServer(dx, dz)
        if RELEASE_TO_FIRST_CATCH_DELAY > 0 then
            task.wait(RELEASE_TO_FIRST_CATCH_DELAY)
        end
        -- Catch
        for i = 1, CATCH_COUNT do
            if not running then break end
            currentStage = "Catch"
            RE_Complete:FireServer()
            if i < CATCH_COUNT then
                task.wait(CATCH_DELAY)
            end
        end
        if LOOP_DELAY > 0 then task.wait(LOOP_DELAY) end
    end
    currentStage = running and currentStage or "Idle"
end

local function start()
    if running then return end
    running = true
    currentStage = "Starting"
    notify("Start")
    task.spawn(loop)
end

local function stop(reset)
    if not running and not reset then return end
    running = false
    notify("Stop" .. (reset and " & reset" or ""))
    currentStage = "Idle"
    -- tidak ada reset counter lagi
end

-- UI
local Window = Rayfield:CreateWindow({
    Name = "Auto Fishing No Animasi",
    LoadingTitle = "Auto Fishing Loader",
    LoadingSubtitle = "Rayfield UI",
    ConfigurationSaving = { Enabled = false },
    DisableRayfieldPrompts = true,
    KeySystem = false
})

local MainTab = Window:CreateTab("Main", 4483362458)
local FishingSection = MainTab:CreateSection("Fishing")



noAnimToggle = MainTab:CreateToggle({
    Name = "Auto Fish No Animasi",
    CurrentValue = false,
    Flag = "AutoStartToggle",
    Callback = function(val)
        autoStart = val
        if val then
            -- Matikan mode animasi jika aktif
            if animEnabled then
                animEnabled = false
                if animThread then task.cancel(animThread); animThread = nil end
                if animToggle then pcall(function() animToggle:Set(false) end) end
            end
            if not running then start() end
        else
            if running then stop(false) end
        end
    end
})

local StatusLabel = MainTab:CreateLabel("Status: idle")
-- (Pengaturan manual dihapus; semua nilai fixed sesuai permintaan)

animToggle = MainTab:CreateToggle({
    Name = "Auto Fish Animasi",
    CurrentValue = false,
    Flag = "AutoFishAnimToggle",
    Callback = function(val)
        animEnabled = val
        if animEnabled then
            if animThread then task.cancel(animThread) end
            -- Pastikan mode no animasi dimatikan
            if running then
                if noAnimToggle then pcall(function() noAnimToggle:Set(false) end) end
                stop(false)
            end
            animThread = task.spawn(function()
                while animEnabled do
                    -- lempar kail (charge)
                    currentStage = "Anim-Charge"
                    pcall(function()
                        local mousePos = UserInputService:GetMouseLocation()
                        FishingController:RequestChargeFishingRod(mousePos, 1)
                    end)

                    -- spam klik minigame
                    currentStage = "Anim-Minigame"
                    while animEnabled and FishingController:GetCurrentGUID() do
                        pcall(function()
                            FishingController:RequestFishingMinigameClick()
                        end)
                        task.wait(0.1)
                    end

                    -- jeda sebelum ulang
                    currentStage = "Anim-Delay"
                    task.wait(1.5)
                end
                currentStage = "Idle"
            end)
        else
            if animThread then
                task.cancel(animThread)
                animThread = nil
                currentStage = "Idle"
            end
        end
    end
})

local PosSection = MainTab:CreateSection("Posisi")



-- Helper untuk update dropdown
local function updateDropdown()
    if not posDropdown then return end
    local options = {}
    for name,_ in pairs(savedPositions) do table.insert(options, name) end
    table.sort(options)
    -- Coba method refresh (jika Rayfield mendukung)
    local ok = pcall(function()
        if posDropdown.Refresh then
            posDropdown:Refresh(options)
        elseif posDropdown.Update then
            posDropdown:Update(options)
        end
    end)
    -- Set current selection jika masih ada
    if selectedPos and savedPositions[selectedPos] then
        pcall(function()
            if posDropdown.Set then
                posDropdown:Set(selectedPos)
            elseif posDropdown.SetOption then
                posDropdown:SetOption(selectedPos)
            end
        end)
    end
    if not ok then
        -- fallback: buat label info jumlah
        -- (Tidak bisa dinamically rebuild tanpa duplikasi, jadi abaikan jika gagal)
    end
end

local nameInput = MainTab:CreateInput({
    Name = "Nama Posisi",
    PlaceholderText = "cth: Spot1",
    RemoveTextAfterFocusLost = false,
    Callback = function(txt)
        lastPosInput = txt or ""
    end
})

MainTab:CreateButton({
    Name = "Simpan Posisi", Callback = function()
        local root = getRoot()
        local name = lastPosInput
        if name == nil or name == "" then
            name = "Pos-" .. tostring(#savedPositions + 1)
        end
        savedPositions[name] = root.CFrame
        selectedPos = name
        notify("Tersimpan: " .. name)
        updateDropdown()
    saveToDisk()
    end
})

posDropdown = MainTab:CreateDropdown({
    Name = "Pilih Posisi",
    Options = {},
    CurrentOption = {},
    Flag = "SavedPosDropdown",
    Callback = function(opt)
        if type(opt) == "table" then
            selectedPos = opt[1]
        else
            selectedPos = opt
        end
        -- Validasi agar tidak hilang jika option belum ada (misal race condition refresh)
        if selectedPos and not savedPositions[selectedPos] then
            -- cari case-insensitive
            for k,_ in pairs(savedPositions) do
                if k:lower() == tostring(selectedPos):lower() then
                    selectedPos = k
                    break
                end
            end
        end
    end
})

MainTab:CreateButton({
    Name = "Teleport", Callback = function()
    local name = selectedPos
    if type(name) == "table" then name = name[1] end
    if not name or not savedPositions[name] then
            notify("Pilih posisi dulu / belum ada.")
            return
        end
        local root = getRoot()
    root.CFrame = savedPositions[name]
    notify("Teleport ke " .. name)
    end
})

MainTab:CreateButton({
    Name = "Hapus Posisi", Callback = function()
        if not selectedPos or not savedPositions[selectedPos] then
            notify("Tidak ada posisi dipilih.")
            return
        end
        savedPositions[selectedPos] = nil
        notify("Hapus: " .. selectedPos)
        selectedPos = nil
        updateDropdown()
        saveToDisk()
    end
})

-- Load any saved positions from disk (after UI elements declared so dropdown exists)
task.defer(function()
    loadFromDisk()
    updateDropdown()
    if fileLoaded then
        notify("Posisi tersimpan dimuat.")
    end
end)

-- Live status updater
spawn(function()
    while true do
        if running then
            StatusLabel:Set("Status: " .. currentStage)
        else
            StatusLabel:Set("Status: idle")
        end
        task.wait(0.25)
    end
end)




notify("Rayfield UI siap.")
