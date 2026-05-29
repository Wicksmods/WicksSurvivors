-- Wick's Survivors
-- Options.lua: options panel (auto-open/close, sound, splash)

local ADDON, ns = ...
local WS = WicksSurvivors
local C  = WS.C

WS.Options = {}
local Options = WS.Options

local FRIZQT = "Fonts\\FRIZQT__.TTF"
local CINZEL = "Interface\\AddOns\\WicksSurvivors\\Fonts\\Cinzel.ttf"

local PANEL_W, PANEL_H = 300, 360

-- ── helpers ───────────────────────────────────────────────────────────────────

local function MakeText(parent, size, col, justify)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local ok = pcall(f.SetFont, f, CINZEL, size, "")
    if not ok then f:SetFont(FRIZQT, size, "") end
    if col     then f:SetTextColor(col.r, col.g, col.b, col.a or 1) end
    if justify then f:SetJustifyH(justify) end
    return f
end

local function MakeBodyText(parent, size, col, justify)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f:SetFont(FRIZQT, size or 12, "")
    if col     then f:SetTextColor(col.r, col.g, col.b, col.a or 1) end
    if justify then f:SetJustifyH(justify) end
    return f
end

-- ── build ─────────────────────────────────────────────────────────────────────

local optFrame
local toggleRefs = {}   -- { dbKey, checkTex, labelFs }

local function SetCheck(dbKey, on)
    WS.db[dbKey] = on
    local ref = toggleRefs[dbKey]
    if ref then
        if on then
            ref.check:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, 1)
            ref.inner:SetColorTexture(C.fel.r * 0.3, C.fel.g * 0.3, C.fel.b * 0.3, 1)
        else
            ref.check:SetColorTexture(C.purple.r, C.purple.g, C.purple.b, 1)
            ref.inner:SetColorTexture(C.void.r, C.void.g, C.void.b, 1)
        end
    end
    -- propagate live effects
    if dbKey == "optSound" and WS.Splash then
        WS.Splash.SetSound(on)
    end
end

local function BuildToggleRow(parent, yOff, dbKey, label, desc)
    local rowH = desc and 44 or 30

    local row = CreateFrame("Button", nil, parent)
    row:SetSize(PANEL_W - 40, rowH)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOff)

    -- checkbox box: 16×16
    local boxFrame = CreateFrame("Frame", nil, row)
    boxFrame:SetSize(16, 16)
    boxFrame:SetPoint("LEFT", row, "LEFT", 0, 0)

    local border = boxFrame:CreateTexture(nil, "BORDER")
    border:SetColorTexture(C.purple.r, C.purple.g, C.purple.b, 1)
    border:SetAllPoints(boxFrame)

    local inner = boxFrame:CreateTexture(nil, "ARTWORK")
    inner:SetColorTexture(C.void.r, C.void.g, C.void.b, 1)
    inner:SetPoint("TOPLEFT",     boxFrame, "TOPLEFT",      1, -1)
    inner:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -1,  1)

    local check = boxFrame:CreateTexture(nil, "OVERLAY")
    check:SetColorTexture(C.purple.r, C.purple.g, C.purple.b, 1)
    check:SetPoint("TOPLEFT",     boxFrame, "TOPLEFT",      3, -3)
    check:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -3,  3)

    local labelFs = MakeBodyText(row, 12, C.text, "LEFT")
    labelFs:SetPoint("LEFT", boxFrame, "RIGHT", 8, desc and 6 or 0)
    labelFs:SetText(label)

    if desc then
        local descFs = MakeBodyText(row, 10, {r=0.55, g=0.52, b=0.45}, "LEFT")
        descFs:SetPoint("TOPLEFT", boxFrame, "BOTTOMLEFT", 0, -2)
        descFs:SetWidth(PANEL_W - 80)
        descFs:SetText(desc)
    end

    toggleRefs[dbKey] = { check = check, inner = inner }

    row:SetScript("OnClick", function()
        SetCheck(dbKey, not WS.db[dbKey])
    end)
    row:SetScript("OnEnter", function()
        labelFs:SetTextColor(C.fel.r, C.fel.g, C.fel.b, 1)
    end)
    row:SetScript("OnLeave", function()
        labelFs:SetTextColor(C.text.r, C.text.g, C.text.b, 1)
    end)

    return row, rowH
end

local function Build()
    if optFrame then return end

    optFrame = CreateFrame("Frame", "WicksSurvivorsOptions", UIParent)
    optFrame:SetSize(PANEL_W, PANEL_H)
    optFrame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    optFrame:SetFrameStrata("HIGH")
    optFrame:SetFrameLevel(200)
    optFrame:SetMovable(true)
    optFrame:EnableMouse(true)
    optFrame:RegisterForDrag("LeftButton")
    optFrame:SetScript("OnDragStart", optFrame.StartMoving)
    optFrame:SetScript("OnDragStop",  optFrame.StopMovingOrSizing)
    optFrame:Hide()

    WS.Skin.Panel(optFrame, PANEL_W, PANEL_H)

    -- header
    local header = CreateFrame("Frame", nil, optFrame)
    header:SetSize(PANEL_W, 42)
    header:SetPoint("TOPLEFT")
    WS.Skin.Header(header)

    local titleFs = MakeText(header, 15, C.text, "CENTER")
    titleFs:SetPoint("CENTER", header, "CENTER", -10, 0)
    titleFs:SetText("Options")

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    WS.Skin.Button(closeBtn, false, 28, 28)
    local xLabel = MakeBodyText(closeBtn, 13, C.text, "CENTER")
    xLabel:SetPoint("CENTER")
    xLabel:SetText("x")
    closeBtn:SetScript("OnEnter", function() xLabel:SetTextColor(C.red.r, C.red.g, C.red.b, 1) end)
    closeBtn:SetScript("OnLeave", function() xLabel:SetTextColor(C.text.r, C.text.g, C.text.b, 1) end)
    closeBtn:SetScript("OnClick", function() optFrame:Hide() end)

    -- section labels + rows
    local body = CreateFrame("Frame", nil, optFrame)
    body:SetSize(PANEL_W - 40, PANEL_H - 72)
    body:SetPoint("TOPLEFT",  optFrame, "TOPLEFT",  20, -52)

    local function SectionLabel(parent, yOff, text)
        local fs = MakeBodyText(parent, 10, {r=C.fel.r*0.7, g=C.fel.g*0.7, b=C.fel.b*0.7}, "LEFT")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOff)
        fs:SetText(string.upper(text))
        -- divider line
        local line = parent:CreateTexture(nil, "BACKGROUND")
        line:SetColorTexture(C.purple.r, C.purple.g, C.purple.b, 0.7)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, yOff - 14)
        line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOff - 14)
        return -16
    end

    local y = 0

    y = y + SectionLabel(body, y, "Auto-Open")
    local r1, h1 = BuildToggleRow(body, y - 4, "optAutoOpenFlight", "On Flight Start")
    y = y - 4 - h1 - 2
    local r2, h2 = BuildToggleRow(body, y, "optAutoOpenLogin", "On Log-in")
    y = y - h2 - 10

    y = y + SectionLabel(body, y, "Auto-Close")
    local r3, h3 = BuildToggleRow(body, y - 4, "optAutoCloseFlight", "On Flight End")
    y = y - 4 - h3 - 2
    local r4, h4 = BuildToggleRow(body, y, "optAutoCloseCombat", "On Enter Combat")
    y = y - h4 - 10

    y = y + SectionLabel(body, y, "Display")
    local r5, h5 = BuildToggleRow(body, y - 4, "optSplash", "Show title splash on open")
    y = y - 4 - h5 - 10

    y = y + SectionLabel(body, y, "Audio")
    local r6, h6 = BuildToggleRow(body, y - 4, "optSound", "Sound effects")
    y = y - 4 - h6

    optFrame.body = body
end

local function RefreshToggles()
    for key, ref in pairs(toggleRefs) do
        local on = WS.db[key]
        if on then
            ref.check:SetColorTexture(C.fel.r, C.fel.g, C.fel.b, 1)
            ref.inner:SetColorTexture(C.fel.r * 0.3, C.fel.g * 0.3, C.fel.b * 0.3, 1)
        else
            ref.check:SetColorTexture(C.purple.r, C.purple.g, C.purple.b, 1)
            ref.inner:SetColorTexture(C.void.r, C.void.g, C.void.b, 1)
        end
    end
end

function Options.Toggle()
    Build()
    if optFrame:IsShown() then
        optFrame:Hide()
    else
        RefreshToggles()
        optFrame:Show()
    end
end
