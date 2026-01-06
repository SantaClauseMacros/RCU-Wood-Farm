#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off
SetWorkingDir A_ScriptDir
CoordMode "Mouse", "Client"
CoordMode "Pixel", "Client"
SetMouseDelay 10

; ===============================
; AUTO UPDATER
; Repo: SantaClauseMacros/RCU-Wood-Farm
; ===============================

localVersionFile := A_ScriptDir "\version.txt"
remoteVersionURL := "https://raw.githubusercontent.com/SantaClauseMacros/RCU-Wood-Farm/main/version.txt"
zipURL := "https://github.com/SantaClauseMacros/RCU-Wood-Farm/archive/refs/heads/main.zip"

tempDir := A_Temp "\RCU_WoodFarm_Update"
zipFile := tempDir "\update.zip"
extractDir := tempDir "\extract"

DirCreate(tempDir)

; Read local version
localVersion := FileExist(localVersionFile)
    ? Trim(FileRead(localVersionFile))
    : "0.0.0"

; Download remote version with error handling
try {
    Download(remoteVersionURL, tempDir "\version.txt")
    remoteVersion := Trim(FileRead(tempDir "\version.txt"))
} catch as err {
    MsgBox("Failed to check for updates: " err.Message "`n`nURL: " remoteVersionURL, "Update Error")
    return
}

; Validate version format
if (remoteVersion = "" || StrLen(remoteVersion) > 20) {
    MsgBox("Invalid version format received: " remoteVersion, "Update Error")
    return
}

if (remoteVersion != localVersion)
{
    MsgBox("Updating RCU Wood Farm to v" remoteVersion, "Update")

    ; Download repo ZIP
    try {
        Download(zipURL, zipFile)
    } catch as err {
        MsgBox("Failed to download update: " err.Message, "Update Error")
        return
    }

    ; Verify ZIP was downloaded
    if !FileExist(zipFile) {
        MsgBox("ZIP file not found after download", "Update Error")
        return
    }

    ; Ensure extract directory exists and is empty
    if DirExist(extractDir)
        DirDelete(extractDir, true)
    DirCreate(extractDir)

    ; Extract using PowerShell (more reliable than COM for some systems)
    psCmd := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& {Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory(''' . zipFile . ''', ''' . extractDir . ''')}"'
    
    try {
        RunWait(psCmd, , "Hide")
    } catch as err {
        MsgBox("PowerShell extraction failed: " err.Message, "Update Error")
        return
    }

    ; Wait a moment for file system to catch up
    Sleep(1000)

    ; Find the actual extracted folder
    repoRoot := ""
    Loop Files, extractDir "\*", "D"
    {
        repoRoot := A_LoopFileFullPath
        break
    }

    ; Verify extraction succeeded
    if (repoRoot = "" || !DirExist(repoRoot)) {
        MsgBox("Extraction failed. Contents of extract dir:`n" (DirExist(extractDir) ? "Folder exists but empty" : "Folder doesn't exist"), "Update Error")
        return
    }

    ; Copy files (skip Settings)
    Loop Files, repoRoot "\*", "FD"
    {
        if (A_LoopFileName = "Settings")
            continue

        src := A_LoopFileFullPath
        dest := A_ScriptDir "\" A_LoopFileName

        try {
            if InStr(A_LoopFileAttrib, "D")
                DirCopy(src, dest, true)
            else
                FileCopy(src, dest, true)
        } catch as err {
            MsgBox("Failed to copy " A_LoopFileName ": " err.Message, "Update Error")
        }
    }

    ; Update local version file
    FileDelete(localVersionFile)
    FileCopy(tempDir "\version.txt", localVersionFile, true)

    ; Cleanup
    DirDelete(tempDir, true)

    MsgBox("Update complete! Restarting script...", "Update Success")

    ; Restart script
    Run('"' A_AhkPath '" "' A_ScriptFullPath '"')
    ExitApp
}

; ===============================
; END AUTO UPDATER
; ===============================

FarmingActive := false
CurrentWood := ""
TimeLeft := 0
QueueList := []
QueueIndex := 1
MainTimer := ""
InitializationComplete := false
RobloxHandle := ""

Stats := {
    Sessions: 0,
    TotalTime: 0,
    WoodCounts: Map()
}

WoodTypes := [
    "🌳 Wood",
    "🌵 Cactus Wood",
    "✨ Magic Wood",
]

for woodType in WoodTypes {
    cleanType := RegExReplace(woodType, "^[^\s]+ ", "")
    Stats.WoodCounts[cleanType] := 0
}

MainGui := ""
WoodTypeDD := ""
DurationEdit := ""
QueueList_LV := ""
StatusLabel := ""
TimeLabel := ""
ProgressBar := ""
SaveNameEdit := ""
LoadPresetDD := ""

SettingsFolder := A_ScriptDir "\Settings"
StatsFile := SettingsFolder "\stats.ini"

if !DirExist(SettingsFolder)
    DirCreate(SettingsFolder)

CreateGUI()
LoadStats()
RefreshPresetList()
InitializeRoblox()

CreateGUI() {
    global
    
    MainGui := Gui("+Resize", "Wood Farming Manager")
    MainGui.OnEvent("Close", (*) => OnExit())
    MainGui.BackColor := "White"
    
    TitleText := MainGui.Add("Text", "x20 y15 w460 h30 Center", "Wood Farming Manager")
    TitleText.SetFont("s16 Bold", "Segoe UI")
    
    MainGui.Add("GroupBox", "x20 y50 w200 h120", "Add to Queue")
    
    MainGui.Add("Text", "x30 y75", "Wood Type:")
    WoodTypeDD := MainGui.Add("DropDownList", "x30 y95 w170", WoodTypes)
    WoodTypeDD.Choose(1)
    
    MainGui.Add("Text", "x30 y125", "Duration (minutes):")
    DurationEdit := MainGui.Add("Edit", "x130 y122 w40 Number", "5")
    
    AddBtn := MainGui.Add("Button", "x30 y145 w80 h25", "Add")
    AddBtn.OnEvent("Click", AddToQueue)
    
    ClearBtn := MainGui.Add("Button", "x120 y145 w80 h25", "Clear All")
    ClearBtn.OnEvent("Click", ClearQueue)
    
    MainGui.Add("GroupBox", "x240 y50 w240 h120", "Queue")
    QueueList_LV := MainGui.Add("ListView", "x250 y75 w220 h85 -Multi ReadOnly", ["Wood Type", "Duration"])
    QueueList_LV.ModifyCol(1, 130)
    QueueList_LV.ModifyCol(2, 70)
    
    MainGui.Add("GroupBox", "x20 y180 w460 h120", "Controls")
    
    StartBtn := MainGui.Add("Button", "x30 y205 w80 h25", "Start")
    StartBtn.OnEvent("Click", StartFarming)
    
    StopBtn := MainGui.Add("Button", "x120 y205 w80 h25", "Pause")
    StopBtn.OnEvent("Click", StopFarming)
    
    StatsBtn := MainGui.Add("Button", "x210 y205 w80 h25", "Statistics")
    StatsBtn.OnEvent("Click", ShowStats)
    
    MainGui.Add("Text", "x30 y250", "Save As:")
    SaveNameEdit := MainGui.Add("Edit", "x85 y247 w100", "")
    
    SaveBtn := MainGui.Add("Button", "x190 y245 w80 h25", "Save Queue")
    SaveBtn.OnEvent("Click", SaveQueue)
    
    MainGui.Add("Text", "x280 y250", "Load:")
    LoadPresetDD := MainGui.Add("DropDownList", "x320 y247 w100", [""])
    
    LoadBtn := MainGui.Add("Button", "x425 y245 w45 h25", "Load")
    LoadBtn.OnEvent("Click", LoadQueue)
    
    MainGui.Add("GroupBox", "x20 y310 w460 h80", "Status")
    
    StatusLabel := MainGui.Add("Text", "x30 y335 w440 h20", "Ready")
    StatusLabel.SetFont("s10", "Segoe UI")
    
    TimeLabel := MainGui.Add("Text", "x30 y355 w200 h20", "Time: 0:00")
    TimeLabel.SetFont("s10 Bold", "Segoe UI")
    
    ProgressBar := MainGui.Add("Progress", "x250 y355 w220 h20", 0)
    
    MainGui.Add("Text", "x20 y400 w460 h20 Center", "Hotkeys: F1=Start  F2=Pause  F3=Exit  F5=Reload")
    MainGui.SetFont("s8", "Segoe UI")
    
    MainGui.Show("w500 h430")
}

UpdateCurrentStatus(message) {
    global StatusLabel
    if (StatusLabel != "")
        StatusLabel.Text := message
}

ShowStatus(message, duration := 2000) {
    global StatusLabel
    if (StatusLabel != "") {
        StatusLabel.Text := message
        SetTimer(() => StatusLabel.Text := "Ready", -duration)
    }
}

InitializeRoblox() {
    global
    UpdateCurrentStatus("Initializing Roblox window...")
    try {
        WinActivate "ahk_exe RobloxPlayerBeta.exe"
        RobloxHandle := WinGetID("ahk_exe RobloxPlayerBeta.exe")
        WinRestore RobloxHandle
        WinMove 150, 150, 800, 600, RobloxHandle
        WinActivate "ahk_exe RobloxPlayerBeta.exe"
        UpdateCurrentStatus("Roblox window initialized successfully")
        return true
    } catch {
        UpdateCurrentStatus("Failed to initialize Roblox window")
        ShowStatus("Failed to initialize Roblox window", 3000)
        RobloxHandle := ""
        return false
    }
}

RobloxClick(x, y) {
    global RobloxHandle
    if (RobloxHandle == "") {
        if (!InitializeRoblox())
            return false
    }
    
    try {
        WinActivate "ahk_id " . RobloxHandle
        
        SendEvent "{Click " x " " y "}"
        return true
    } catch {
        try {
            WinActivate "ahk_id " . RobloxHandle
            SendEvent "{Click " x " " y "}"
            return true
        } catch {
            return false
        }
    }
}

RobloxSendText(text) {
    global RobloxHandle
    if (RobloxHandle == "") {
        if (!InitializeRoblox())
            return false
    }
    
    try {
        WinActivate "ahk_id " . RobloxHandle
        SendEvent text
        return true
    } catch {
        return false
    }
}

RobloxSendKey(key, holdMs := 0) {
    global RobloxHandle
    if (RobloxHandle = "") {
        if (!InitializeRoblox())
            return false
    }
    try {
        WinActivate "ahk_id " . RobloxHandle
        Sleep 50

        if (holdMs = 0) {
            SendEvent(key)
        } else {
            SendEvent("{" . key . " down}")
            Sleep holdMs
            SendEvent("{" . key . " up}")
        }
        return true
    } catch {
        try {
            ControlSend(key, , "ahk_id " . RobloxHandle)
            return true
        } catch {
            return false
        }
    }
}

AddToQueue(*) {
    global
    woodType := WoodTypeDD.Text
    duration := DurationEdit.Text
    
    if (woodType == "" || duration == "" || duration == 0) {
        MsgBox("Please select wood type and duration!", "Error")
        return
    }
    
    cleanWood := RegExReplace(woodType, "^[^\s]+ ", "")
    QueueList.Push({Wood: woodType, CleanWood: cleanWood, Duration: Integer(duration)})
    
    UpdateQueueDisplay()
    DurationEdit.Text := "5"
}

UpdateQueueDisplay() {
    global
    QueueList_LV.Delete()
    
    for index, item in QueueList {
        status := ""
        if (FarmingActive) {
            if (index < QueueIndex)
                status := "✓ "
            else if (index == QueueIndex)
                status := "► "
        }
        
        QueueList_LV.Add("", status . item.CleanWood, item.Duration . "m")
    }
}

ClearQueue(*) {
    global
    if (QueueList.Length == 0)
        return
        
    result := MsgBox("Clear entire queue?", "Confirm", "YesNo")
    if (result == "Yes") {
        QueueList := []
        QueueIndex := 1
        UpdateQueueDisplay()
        
        if (FarmingActive)
            StopFarming()
    }
}

StartFarming(*) {
    global
    if (QueueList.Length == 0) {
        MsgBox("Queue is empty! Add items first.", "Error")
        return
    }
    
    if (FarmingActive) {
        MsgBox("Already farming!", "Info")
        return
    }
    
    if (!InitializationComplete) {
        StatusLabel.Text := "Initializing farming setup..."
        PerformInitialization()
        InitializationComplete := true
    }
    
    FarmingActive := true
    QueueIndex := 1
    Stats.Sessions++
    
    StatusLabel.Text := "Starting farming session..."
    ProcessNextItem()
}

PerformInitialization() {
    RobloxSendKey("{1}")
}

StopFarming(*) {
    global
    FarmingActive := false
    InitializationComplete := false
    if (MainTimer != "") {
        SetTimer(MainTimer, 0)
        MainTimer := ""
    }
    
    StatusLabel.Text := "Paused"
    TimeLabel.Text := "Time: Paused"
    ProgressBar.Value := 0
    UpdateQueueDisplay()
    SaveStats()
}

ProcessNextItem() {
    global
    if (!FarmingActive || QueueIndex > QueueList.Length) {
        FarmingActive := false
        StatusLabel.Text := "Queue completed!"
        TimeLabel.Text := "Time: Complete"
        ProgressBar.Value := 100
        
        sessionTime := 0
        for item in QueueList {
            sessionTime += item.Duration * 60
            Stats.WoodCounts[item.CleanWood]++
        }
        Stats.TotalTime += sessionTime
        
        UpdateQueueDisplay()
        SaveStats()
        
        return
    }
    
    CurrentItem := QueueList[QueueIndex]
    CurrentWood := CurrentItem.Wood
    TimeLeft := CurrentItem.Duration * 60
    
    StatusLabel.Text := "Farming: " . CurrentItem.CleanWood . " (" . QueueIndex . "/" . QueueList.Length . ")"
    UpdateQueueDisplay()
    
    MainTimer := () => UpdateTimer()
    SetTimer(MainTimer, 1000)
    
    StartWoodFarming(CurrentItem.CleanWood)
}

StartWoodFarming(woodType) {
    
    switch woodType {
        case "Wood":
            TeleportToSpawnWorld()
        case "Cactus Wood":
            TeleportToDesertWorld()
        case "Magic Wood":
            TeleportToMagicWorld()
        default:
    }
}

WaitForTreeToBreak() {
    global
    Sleep(250)
    colorFound := false
    timeout := 0
    
    while (!colorFound && timeout < 100) {
        if (!FarmingActive)
            return
        
        if (PixelSearch(&foundX, &foundY, 320, 518, 320, 518, 0x2FB7FC)) {
            colorFound := true
        } else {
            Sleep(100)
            timeout++
        }
    }
    
    if (colorFound) {
        while (PixelSearch(&foundX, &foundY, 320, 518, 320, 518, 0x2FB7FC)) {
            if (!FarmingActive)
                return
            Sleep(100)
        }
        
        Sleep 250
        LookForGoldenTrees()
    }
}

WaitForClickButton() {
    Sleep 250
    imagePath := A_ScriptDir "\images\Click Button.png"
    Loop {
        if ImageSearch(&x, &y, 0, 0, A_ScreenWidth, A_ScreenHeight, "*50 " imagePath) {
            return
        }
    }
}

WaitForTeleportIcon() {
    Sleep 250
    imagePath := A_ScriptDir "\images\Teleport Icon.png"
    Loop {
        if ImageSearch(&x, &y, 0, 0, A_ScreenWidth, A_ScreenHeight, "*50 " imagePath) {
            return
        }
    }
}

LookForGoldenTrees() {
    targetColor := 0xFFDB3B
    colorVariation := 35
    
    searchBoxes := [
        {x1: 346, y1: 265, x2: 374, y2: 343},
        {x1: 413, y1: 272, x2: 448, y2: 336},
        {x1: 340, y1: 251, x2: 439, y2: 282}
    ]

    for index, box in searchBoxes {
        if PixelSearch(&foundX, &foundY, box.x1, box.y1, box.x2, box.y2, targetColor, colorVariation) {
           RobloxClick(foundX, foundY)
           WaitForTreeToBreak()
            return true
        }
    }
    
    return false
}

SpawnWorldCameraSetup() {
    Loop 20 {
    RobloxSendKey "{WheelUp}"
    }
    Loop 15 {
    RobloxSendKey "{WheelDown}"
    }
}

TeleportToSpawnWorld() {
    global
    RobloxClick(705, 325)
    Sleep 100
    RobloxClick(492, 283)
    WaitForClickButton()
    Sleep 100
    SpawnWorldCameraSetup()
    FarmWoodTrees()
}

FarmWoodTrees() {
    global
    while (FarmingActive && TimeLeft > 0) {
        trees := [ 
        {x: 626, y: 156},
        {x: 771, y: 175},
        {x: 186, y: 161},
        {x: 162, y: 57},
        {x: 613, y: 256},
        {x: 124, y: 167},
        {x: 251, y: 174},
        {x: 121, y: 100},
        {x: 6, y: 103},
        {x: 748, y: 160}
    ]   
        
        for index, tree in trees {
            if (!FarmingActive)
                return
                
            RobloxClick(tree.x, tree.y)
            WaitForTreeToBreak()
            
            if (index = 8) {
                Send("{WheelUp}")
            }
        }

        if (TimeLeft <= 0)
            return
            
        TeleportToSpawnWorld()
    }
}

DesertWorldCameraSetup() {
    Loop 20 {
    RobloxSendKey "{WheelUp}"
    }
    Loop 15 {
    RobloxSendKey "{WheelDown}"
    }
}

TeleportToDesertWorld() {
    global
    RobloxClick(705, 325)
    Sleep 100
    RobloxClick(400, 300)
    Sleep 100
    RobloxSendKey "{WheelDown}"
    Sleep 100
    RobloxClick(492, 348)
    WaitForClickButton()
    Sleep 100
    DesertWorldCameraSetup()
    FarmCactusTrees()
}

    FarmCactusTrees() {
    global
    while (FarmingActive && TimeLeft > 0) {
        trees := [ 
        {x: 502, y: 272},
        {x: 184, y: 135},
        {x: 481, y: 299},
        {x: 634, y: 331},
        {x: 525, y: 129}
    ]   
        
        for index, tree in trees {
            if (!FarmingActive)
                return
                
            RobloxClick(tree.x, tree.y)
            WaitForTreeToBreak()
            
            if (index = 4) {
                Loop 4 {
                RobloxSendKey "{WheelUp}"
                }
            }
        }
        
        if (TimeLeft <= 0)
            return
            
        Sleep 7000
        
        if (TimeLeft <= 0)
            return
            
        TeleportToDesertWorld()
    }
}

TeleportToMagicWorld() {
    global
    RobloxClick(705, 325)
    Sleep(100)
    Loop 4 {
    RobloxSendKey "{WheelDown}"
    }
    RobloxClick(492, 350)
    WaitForClickButton()
    Sleep 100
    Loop 4 {
    RobloxSendKey "{WheelDown}"
    }
    Sleep 500
    FarmWoodTrees()
}

FarmMagicTrees() {
    global
    while (FarmingActive && TimeLeft > 0) {
        trees := [ 
        {x: 626, y: 156},
        {x: 771, y: 175},
        {x: 186, y: 161},
        {x: 162, y: 57},
        {x: 613, y: 256},
        {x: 124, y: 167},
        {x: 251, y: 174},
        {x: 121, y: 100},
        {x: 6, y: 103},
        {x: 748, y: 160}
    ]   
        
        for index, tree in trees {
            if (!FarmingActive)
                return
                
            RobloxClick(tree.x, tree.y)
            WaitForTreeToBreak()
            
            if (index = 8) {
                Send("{WheelUp}")
            }
        }

        if (TimeLeft <= 0)
            return
            
        TeleportToSpawnWorld()
    }
}

UpdateTimer() {
    global
    if (!FarmingActive) {
        if (MainTimer != "") {
            SetTimer(MainTimer, 0)
            MainTimer := ""
        }
        return
    }
    
    if (TimeLeft <= 0) {
        QueueIndex++
        if (MainTimer != "") {
            SetTimer(MainTimer, 0)
            MainTimer := ""
        }
        ProcessNextItem()
        return
    }
    
    TimeLeft--
    minutes := TimeLeft // 60
    seconds := Mod(TimeLeft, 60)
    TimeLabel.Text := "Time: " . minutes . ":" . Format("{:02d}", seconds)
    
    if (QueueIndex <= QueueList.Length) {
        totalTime := QueueList[QueueIndex].Duration * 60
        progress := ((totalTime - TimeLeft) / totalTime) * 100
        ProgressBar.Value := progress
    }
}

SaveQueue(*) {
    global
    if (QueueList.Length == 0) {
        MsgBox("Queue is empty! Nothing to save.", "Info")
        return
    }
    
    saveName := Trim(SaveNameEdit.Text)
    if (saveName == "") {
        MsgBox("Please enter a name for the queue preset!", "Error")
        return
    }
    
    saveName := RegExReplace(saveName, '[\\/:*?"<>|]', "_")
    
    presetFile := SettingsFolder "\" saveName ".ini"
    
    try {
        if FileExist(presetFile)
            FileDelete(presetFile)
        
        for index, item in QueueList {
            IniWrite(item.Wood, presetFile, "Queue", "Wood" . index)
            IniWrite(item.CleanWood, presetFile, "Queue", "CleanWood" . index)
            IniWrite(item.Duration, presetFile, "Queue", "Duration" . index)
        }
        
        IniWrite(QueueList.Length, presetFile, "Queue", "Count")
        
        MsgBox("Queue saved successfully as: " . saveName . "`n" . QueueList.Length . " items saved.", "Queue Saved")
        
        SaveNameEdit.Text := ""
        RefreshPresetList()
        
    } catch as e {
        MsgBox("Error saving queue: " . e.Message, "Save Error")
    }
}

LoadQueue(*) {
    global
    if (FarmingActive) {
        MsgBox("Cannot load queue while farming is active!", "Error")
        return
    }
    
    presetName := LoadPresetDD.Text
    if (presetName == "" || presetName == "Select preset...") {
        MsgBox("Please select a preset to load!", "Error")
        return
    }
    
    presetFile := SettingsFolder "\" presetName ".ini"
    
    if !FileExist(presetFile) {
        MsgBox("Preset file not found!", "Error")
        RefreshPresetList()
        return
    }
    
    try {
        QueueList := []
        
        count := IniRead(presetFile, "Queue", "Count", 0)
        
        if (count > 0) {
            Loop count {
                wood := IniRead(presetFile, "Queue", "Wood" . A_Index, "")
                cleanWood := IniRead(presetFile, "Queue", "CleanWood" . A_Index, "")
                duration := IniRead(presetFile, "Queue", "Duration" . A_Index, 0)
                
                if (wood != "" && duration > 0) {
                    QueueList.Push({Wood: wood, CleanWood: cleanWood, Duration: Integer(duration)})
                }
            }
        }
        
        UpdateQueueDisplay()
        MsgBox("Queue loaded successfully!`n" . QueueList.Length . " items loaded from: " . presetName, "Queue Loaded")
        
    } catch as e {
        MsgBox("Error loading queue: " . e.Message, "Load Error")
    }
}

RefreshPresetList() {
    global LoadPresetDD
    
    presets := ["Select preset..."]
    
    Loop Files, SettingsFolder "\*.ini" {
        if (A_LoopFileName != "stats.ini") {
            presetName := StrReplace(A_LoopFileName, ".ini", "")
            presets.Push(presetName)
        }
    }
    
    LoadPresetDD.Delete()
    LoadPresetDD.Add(presets)
    LoadPresetDD.Choose(1)
}

ShowStats(*) {
    global
    statsText := "Sessions: " . Stats.Sessions . "`n"
    statsText .= "Total Time: " . FormatDuration(Stats.TotalTime) . "`n`n"
    statsText .= "Wood Collection:`n"
    
    for woodType, count in Stats.WoodCounts {
        if (count > 0)
            statsText .= woodType . ": " . count . "`n"
    }
    
    MsgBox(statsText, "Statistics")
}

FormatDuration(seconds) {
    hours := seconds // 3600
    minutes := (seconds - hours * 3600) // 60
    if (hours > 0)
        return hours . "h " . minutes . "m"
    else
        return minutes . "m"
}

SaveStats() {
    global
    try {
        IniWrite(Stats.Sessions, StatsFile, "Stats", "Sessions")
        IniWrite(Stats.TotalTime, StatsFile, "Stats", "TotalTime")
        
        for woodType, count in Stats.WoodCounts {
            IniWrite(count, StatsFile, "WoodCounts", woodType)
        }
        
    } catch {
    }
}

LoadStats() {
    global
    try {
        if FileExist(StatsFile) {
            Stats.Sessions := IniRead(StatsFile, "Stats", "Sessions", 0)
            Stats.TotalTime := IniRead(StatsFile, "Stats", "TotalTime", 0)
            
            for woodType in Stats.WoodCounts {
                count := IniRead(StatsFile, "WoodCounts", woodType, 0)
                Stats.WoodCounts[woodType] := Integer(count)
            }
        }
    } catch {
    }
}

F1::StartFarming()
F2::StopFarming()
F3::OnExit()
F5::Reload()

OnExit(*) {
    global
    try {
        SaveStats()
        if (MainTimer != "")
            SetTimer(MainTimer, 0)
    } catch {
    }
    ExitApp()
}
