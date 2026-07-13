local BASE        = "https://raw.githubusercontent.com/MudillaScripts/aw_cs2v6_femboytap/main/"
local GUILIB_URL  = BASE .. "femboytap_guilib.lua"
local CHANGER_URL = BASE .. "femboytap_changer.lua"

local ffi = rawget(_G, "ffi")

local function r_ptr(a) return tonumber(ffi.cast("uint64_t*", a)[0]) end
local function valid(p) return p ~= nil and p > 0x10000 and p < 0x7FFFFFFFFFFF end

-- client.dll
local SIG = {
    vm        = "E8 ?? ?? ?? ?? 48 8B CB E8 ?? ?? ?? ?? 84 C0 74 11 F3 0F 10 45 B0",            -- viewmodel offset apply
    ev_mgr    = "48 8D 47 40 48 C1 E2 04 48 03 D0 74 0D 48 8B 0D",                               -- g_pGameEventManager xref
    ev_getint = "48 89 5C 24 08 48 89 6C 24 10 48 89 74 24 18 57 48 83 EC 30 48 8B 01 41 8B F0", -- CGameEvent::GetInt
}

local function fetch(url, cacheFile)
    local src
    local bust = url .. "?nocache=" .. tostring({}):gsub("%W", "")
    pcall(function() src = http.Get(bust) end)
    if type(src) ~= "string" or #src <= 500 then pcall(function() src = http.Get(url) end) end
    if type(src) == "string" and #src > 500 then
        pcall(function()
            local f = file.Open(cacheFile, "w")
            if f then f:Write(src); f:Close() end
        end)
        return src, "server"
    end
    pcall(function()
        local f = file.Open(cacheFile, "r")
        if f then src = f:Read(); f:Close() end
    end)
    if type(src) == "string" and #src > 500 then return src, "cache" end
    return nil
end

local function load(url, cacheFile, name)
    local src, where = fetch(url, cacheFile)
    if not src then print("[femboytap] FATAL: cannot load " .. name) return nil end
    -- If this is the GUI library, modify the source to change theme colors and title
    if name == "guilib" then
        -- Change background to dark Dracula-like
        src = src:gsub("bg%s*=%s*{[%d+,]+}", "bg        = {40,42,54,255}")
        src = src:gsub("bg2%s*=%s*{[%d+,]+}", "bg2       = {30,30,40,255}")
        -- Change accent purple to light green
        src = src:gsub("accent%s*=%s*{%d+,%d+,%d+}", "accent    = {80,250,120}")
        -- Change accent_bg purple to dark green
        src = src:gsub("accent_bg%s*=%s*{[%d+,]+}", "accent_bg = {40,80,60,255}")
        -- Change widget (button background) to light green
        src = src:gsub("widget%s*=%s*{[%d+,]+}", "widget    = {80,250,120,255}")
        -- Change widgethi (button highlight) to lighter green
        src = src:gsub("widgethi%s*=%s*{[%d+,]+}", "widgethi  = {100,255,150,255}")
        -- Change section background
        src = src:gsub("section%s*=%s*{[%d+,]+}", "section   = {50,55,65,255}")
        -- Change border
        src = src:gsub("border%s*=%s*{[%d+,]+}", "border    = {60,70,80,255}")
        -- Change divider
        src = src:gsub("divider%s*=%s*{[%d+,]+}", "divider   = {50,60,70,255}")
        -- Change text colors to lighter shades
        src = src:gsub("text%s*=%s*{[%d+,]+}", "text      = {200,255,200,255}")
        src = src:gsub("textdim%s*=%s*{[%d+,]+}", "textdim   = {120,180,120,255}")
        src = src:gsub("texthi%s*=%s*{[%d+,]+}", "texthi    = {220,255,220,255}")
        -- Change notification colors
        src = src:gsub("notif_info%s*=%s*{%d+,%d+,%d+}", "notif_info    = {80,250,120}")
        src = src:gsub("notif_success%s*=%s*{%d+,%d+,%d+}", "notif_success = {80,250,120}")
        src = src:gsub("notif_error%s*=%s*{%d+,%d+,%d+}", "notif_error   = {250,120,120}")
        -- Change hitlog colors
        src = src:gsub("_hitlog%.colors%.miss%s*=%s*{%d+,%d+,%d+}", "_hitlog.colors.miss = {250,120,120}")
        src = src:gsub("_hitlog%.colors%.hit%s*=%s*{%d+,%d+,%d+}", "_hitlog.colors.hit = {80,250,120}")
        src = src:gsub("_hitlog%.colors%.hurt%s*=%s*{%d+,%d+,%d+}", "_hitlog.colors.hurt = {250,200,100}")
        src = src:gsub("_hitlog%.colors%.kill%s*=%s*{%d+,%d+,%d+}", "_hitlog.colors.kill = {80,250,120}")
        -- Change title
        src = src:gsub('title%s*=%s*"FEMBOYTAP"', 'title     = "LUNARHUB"')
    end
    local chunk, err = loadstring(src, "=" .. cacheFile)
    if not chunk then print("[femboytap] " .. name .. " compile error: " .. tostring(err)) return nil end
    local ok, mod = pcall(chunk)
    if not ok then print("[femboytap] " .. name .. " run error: " .. tostring(mod)) return nil end
    print("[femboytap] " .. name .. " loaded from " .. tostring(where))
    return mod
end

local M = load(GUILIB_URL, ".\\femboytap_lua\\femboytap_guilib.lua", "guilib")
if type(M) ~= "table" then return end

local C = load(CHANGER_URL, ".\\femboytap_lua\\femboytap_changer.lua", "changer")
if type(C) ~= "table" then return end

local floor = math.floor

local VM = {}
local EV = { installed = false }
local HS = {}

local weaponLb, skinLb, skinWd
local sWear, sSeed, cbAuto
local modelLb, modelWd, modelPaths
local cbVm, vmX, vmY, vmZ
local hsOn, hsCmb, hsCmbWd, hsVol
local ksOn, ksCmb, ksCmbWd, ksVol
local SND_NAMES, SND_PATHS

local lastModelSel = -1
local curPaints    = { 0 }
local lastSel      = -1
local lastSig      = nil
local lastAutoDef  = nil
local lastAuto     = false

local function item()     return C.items[weaponLb:Get()] end
local function paint()    return curPaints[skinLb:Get()] or 0 end
local function settings() return sWear:Get(), floor(sSeed:Get() + 0.5) end

local function applySelected()
    local it = item(); if not it then return end
    local w, s = settings()
    C.apply(it, paint(), w, s)
end

local function sig()
    local it = item(); if not it then return "none" end
    local w, s = settings()
    return it.def.."|"..paint().."|"..floor(w * 100000).."|"..s
end

local function autoFollow()
    if not cbAuto:Get() then lastAutoDef = nil; return end
    local def = C.activeDef(); if not def then return end
    if not C.defToItem[def] and C.isKnife(def) and C.knifeDef() then def = C.knifeDef() end
    if def == lastAutoDef then return end
    local idx = C.defToItem[def]; if not idx then return end
    lastAutoDef = def
    weaponLb:Set(idx)
end

local function autoApply()
    local s = sig()
    if s == lastSig then return end
    lastSig = s
    applySelected()
end

local function syncSkins()
    local sel = weaponLb:Get()
    if sel == lastSel then return end
    lastSel = sel
    local it = C.items[sel]; if not it then return end
    local names, paints = C.skinList(it.def)
    curPaints     = paints
    skinWd.items  = names
    skinWd.value  = 1
    skinWd.scroll = 0
    local c = C.getCfg(it.def)
    if c then
        sWear:Set(c.wear); sSeed:Set(c.seed)
        for i = 2, #paints do
            if paints[i] == c.paint then skinWd.value = i; break end
        end
    end
    lastSig = sig()
end

local function persistOpts()
    local v = cbAuto:Get()
    if v ~= lastAuto then lastAuto = v; C.setOpt("autoFollow", v) end
end

local function syncModel()
    if not modelLb then return end
    local sel = modelLb:Get()
    if sel == lastModelSel then return end
    lastModelSel = sel
    C.setLocalModel(modelPaths and modelPaths[sel] or nil)
end

do
    local page, match, origRel, ok = nil, nil, nil, false

    local function r_i32(a) return ffi.cast("int32_t*",  a)[0] end
    local function w_u8 (a, v) ffi.cast("uint8_t*", a)[0] = v end
    local function w_i32(a, v) ffi.cast("int32_t*", a)[0] = v end
    local function w_f32(a, v) ffi.cast("float*",   a)[0] = v end

    local function le64(v)
        local t = {}
        for _ = 1, 8 do t[#t + 1] = v % 256; v = math.floor(v / 256) end
        return t
    end

    local function alloc_near(target, size)
        local gran = 0x10000
        local base = target - (target % gran)
        for i = 1, 0x8000 do
            local lo, hi = base - i * gran, base + i * gran
            if lo > 0x10000 then
                local p = ffi.C.VirtualAlloc(ffi.cast("void*", lo), size, 0x3000, 0x40)
                if p ~= nil then return p end
            end
            local p2 = ffi.C.VirtualAlloc(ffi.cast("void*", hi), size, 0x3000, 0x40)
            if p2 ~= nil then return p2 end
        end
        return nil
    end

    local function install()
        if type(ffi) ~= "table" then print("[femboytap] VM: no ffi"); return false end
        pcall(function() ffi.cdef [[
            void* VirtualAlloc(void*, size_t, uint32_t, uint32_t);
            int   VirtualProtect(void*, size_t, uint32_t, uint32_t*);
            void* GetCurrentProcess(void);
            int   FlushInstructionCache(void*, void*, size_t);
        ]] end)

        local a = mem.FindPattern("client.dll", SIG.vm)
        if not a or a == 0 then print("[femboytap] VM: sig not found"); return false end
        match = a
        local orig = a + 5 + r_i32(a + 1)

        local p = alloc_near(orig, 0x1000)
        if p == nil then print("[femboytap] VM: alloc failed"); return false end
        page = tonumber(ffi.cast("uintptr_t", p))
        local code = page + 16

        local b = { 0x53, 0x56, 0x48,0x83,0xEC,0x28, 0x48,0x89,0xD6, 0x48,0xB8 }
        for _, v in ipairs(le64(orig)) do b[#b + 1] = v end
        for _, v in ipairs({ 0xFF,0xD0, 0x48,0xBB }) do b[#b + 1] = v end
        for _, v in ipairs(le64(page)) do b[#b + 1] = v end
        for _, v in ipairs({
            0x8B,0x0B, 0x85,0xC9, 0x74,0x2B,
            0xF3,0x0F,0x10,0x4B,0x04, 0xF3,0x0F,0x58,0x0E, 0xF3,0x0F,0x11,0x0E,
            0xF3,0x0F,0x10,0x4B,0x08, 0xF3,0x0F,0x58,0x4E,0x04, 0xF3,0x0F,0x11,0x4E,0x04,
            0xF3,0x0F,0x10,0x4B,0x0C, 0xF3,0x0F,0x58,0x4E,0x08, 0xF3,0x0F,0x11,0x4E,0x08,
            0x48,0x83,0xC4,0x28, 0x5E, 0x5B, 0xC3,
        }) do b[#b + 1] = v end
        for i = 0, #b - 1 do w_u8(code + i, b[i + 1]) end
        w_i32(page, 0); w_f32(page + 4, 0); w_f32(page + 8, 0); w_f32(page + 12, 0)

        local rel = code - (match + 5)
        if rel < -2147483648 or rel > 2147483647 then print("[femboytap] VM: rel32 overflow"); return false end
        origRel = r_i32(match + 1)
        local old = ffi.new("uint32_t[1]")
        ffi.C.VirtualProtect(ffi.cast("void*", match), 5, 0x40, old)
        w_i32(match + 1, rel)
        ffi.C.VirtualProtect(ffi.cast("void*", match), 5, old[0], old)
        pcall(function() ffi.C.FlushInstructionCache(ffi.C.GetCurrentProcess(), ffi.cast("void*", match), 5) end)
        print("[femboytap] VM: installed")
        return true
    end

    pcall(function() ok = install() end)

    function VM.set(on, x, y, z)
        if not ok or not page then return end
        w_i32(page, on and 1 or 0)
        w_f32(page + 4, x or 0)
        w_f32(page + 8, y or 0)
        w_f32(page + 12, z or 0)
    end

    function VM.uninstall()
        if not (ok and match and origRel) then return end
        pcall(function()
            local old = ffi.new("uint32_t[1]")
            ffi.C.VirtualProtect(ffi.cast("void*", match), 5, 0x40, old)
            w_i32(match + 1, origRel)
            ffi.C.VirtualProtect(ffi.cast("void*", match), 5, old[0], old)
        end)
    end
end
pcall(function() callbacks.Register("Unload", function() pcall(VM.uninstall) end) end)

local lastVm = nil
local function syncVm()
    local on = cbVm:Get()
    local x, y, z = vmX:Get(), vmY:Get(), vmZ:Get()
    VM.set(on, x, y, z)
    local s = (on and "1" or "0") .. ":" .. x .. ":" .. y .. ":" .. z
    if s ~= lastVm then
        lastVm = s
        C.setOpt("vm_on", on)
        C.setOpt("vm_x", x); C.setOpt("vm_y", y); C.setOpt("vm_z", z)
    end
end

do
    local DLL = "client.dll"

    local I_ADD, I_REMOVE = 3, 5
    local LISTEN_FLAG = 2

    local registry = {}
    local queue    = {}
    local keep     = { names = {} }
    local getNameFn, getIntFn

    local function onFire(_self, ev)
        if ev == nil then return end
        pcall(function()
            local evn = tonumber(ffi.cast("uint64_t", ev))
            if not valid(evn) then return end
            if not getNameFn then
                getNameFn = ffi.cast("const char* (*)(void*)", r_ptr(r_ptr(evn) + 8))
            end
            local np = getNameFn(ev); if np == nil then return end
            local name = ffi.string(np)
            local subs = registry[name]; if not subs then return end
            for i = 1, #subs do
                local sub  = subs[i]
                local f    = sub.fields
                local data = { name = name }
                for j = 1, #f do data[f[j]] = getIntFn(ev, sub.fc[f[j]], -1) end
                queue[#queue + 1] = { sub.handler, data }
            end
        end)
    end

    local function inMod(base, a) return a and a >= base + 0x1000 and a < base + 0x4000000 end

    function EV.install()
        if EV.installed then return true end
        if type(ffi) ~= "table" then return false end
        local base = mem.GetModuleBase(DLL); if not base then return false end
        local mp = mem.FindPattern(DLL, SIG.ev_mgr)
        if not mp or mp == 0 then print("[femboytap] event hook: mgr sig not found"); return false end
        local mgrPtr = mp + 20 + ffi.cast("int32_t*", mp + 16)[0]
        local mgr = r_ptr(mgrPtr);          if not valid(mgr) then return false end
        local vt  = r_ptr(mgr);             if not valid(vt)  then return false end
        local addAddr = r_ptr(vt + I_ADD * 8)
        local remAddr = r_ptr(vt + I_REMOVE * 8)
        if not (inMod(base, addAddr) and inMod(base, remAddr)) then
            print("[femboytap] event hook: vtable resolve failed (bad offsets?) -- aborted"); return false
        end
        EV._mgr = ffi.cast("void*", mgr)
        EV._add = ffi.cast("char (*)(void*, void*, const char*, char)", addAddr)
        EV._rem = ffi.cast("void (*)(void*, void*)",                    remAddr)
        local gi = mem.FindPattern(DLL, SIG.ev_getint)
        if not gi or gi == 0 then print("[femboytap] event hook: getint sig not found"); return false end
        getIntFn = ffi.cast("int (*)(void*, const char*, int)", gi)

        local cb0    = ffi.cast("void* (*)(void*)", function(s) return s end)
        local cbFire = ffi.cast("void (*)(void*, void*)", onFire)
        local cbDbg  = ffi.cast("int (*)(void*)", function() return 42 end)
        local lvt = ffi.new("void*[3]")
        lvt[0] = ffi.cast("void*", cb0); lvt[1] = ffi.cast("void*", cbFire); lvt[2] = ffi.cast("void*", cbDbg)
        local obj = ffi.new("void*[1]"); obj[0] = ffi.cast("void*", lvt)
        keep.cb0, keep.cbFire, keep.cbDbg, keep.lvt, keep.obj = cb0, cbFire, cbDbg, lvt, obj
        EV._listener = ffi.cast("void*", obj)
        EV.installed = true
        for _, cs in pairs(keep.names) do pcall(function() EV._add(EV._mgr, EV._listener, cs, LISTEN_FLAG) end) end
        print("[femboytap] event hook installed")
        return true
    end

    function EV.on(name, fields, handler)
        fields = fields or {}
        if not keep.names[name] then keep.names[name] = ffi.new("char[?]", #name + 1, name) end
        local fc = {}
        for i = 1, #fields do fc[fields[i]] = ffi.new("char[?]", #fields[i] + 1, fields[i]) end
        registry[name] = registry[name] or {}
        registry[name][#registry[name] + 1] = { fields = fields, fc = fc, handler = handler }
        if EV.installed and #registry[name] == 1 then
            pcall(function() EV._add(EV._mgr, EV._listener, keep.names[name], LISTEN_FLAG) end)
        end
    end

    function EV.drain()
        local n = #queue; if n == 0 then return end
        local q = queue; queue = {}
        for i = 1, n do pcall(q[i][1], q[i][2]) end
    end

    function EV.uninstall()
        if EV.installed and EV._rem then pcall(function() EV._rem(EV._mgr, EV._listener) end) end
        EV.installed = false
    end
end
pcall(function() callbacks.Register("Unload", function() pcall(EV.uninstall) end) end)

do
    local f = ffi
    local FFF, FNF, FCL, GCD, WINEXEC
    local soundDir = ".\\csgo\\sounds"
    if type(f) == "table" then
        pcall(function() f.cdef [[ void* GetModuleHandleA(const char*); void* GetProcAddress(void*, const char*); ]] end)
        pcall(function() f.cdef [[ typedef struct { uint32_t attr; uint8_t pad[40]; char nm[260]; char alt[14]; } AWSNDFD; ]] end)
        local function P(nm, t)
            local h = f.C.GetModuleHandleA("kernel32.dll"); if h == nil then return nil end
            local p = f.C.GetProcAddress(h, nm); return (p ~= nil) and f.cast(t, p) or nil
        end
        FFF = P("FindFirstFileA",       "void*(*)(const char*, void*)")
        FNF = P("FindNextFileA",        "int(*)(void*, void*)")
        FCL = P("FindClose",            "int(*)(void*)")
        GCD = P("GetCurrentDirectoryA", "uint32_t(*)(uint32_t, char*)")
        WINEXEC = P("WinExec",          "uint32_t(*)(const char*, uint32_t)")
        pcall(function()
            if GCD then
                local eb = f.new("char[?]", 1024)
                local cwd = f.string(eb, GCD(1024, eb))
                soundDir = cwd:gsub("[\\/]bin[\\/]win64.*$", "\\csgo\\sounds")
            end
        end)
    end
    HS.openSoundDir = function()
        if WINEXEC then pcall(function() WINEXEC('explorer.exe "' .. soundDir .. '"', 5) end) end
    end

    local function scanSounds()
        local names = {}
        pcall(function()
            if not (f and FFF and FNF and FCL) then return end
            local INVALID = f.cast("void*", f.cast("intptr_t", -1))
            local fd = f.new("AWSNDFD")
            local h = FFF(soundDir .. "\\*.vsnd_c", fd)
            if h ~= INVALID then
                repeat
                    local nm = f.string(fd.nm)
                    if nm:sub(-7):lower() == ".vsnd_c" then names[#names + 1] = nm:sub(1, #nm - 7) end
                until FNF(h, fd) == 0
                FCL(h)
            end
        end)
        table.sort(names)
        local paths = {}
        for i = 1, #names do paths[i] = names[i] end
        if #names == 0 then names[1] = "[ put .vsnd_c in csgo\\sounds ]" end
        return names, paths
    end
    HS.scan = scanSounds
    SND_NAMES, SND_PATHS = scanSounds()

    local function resolve(cmb)
        return tostring(SND_PATHS[cmb:Get()] or "")
    end

    local function play(path, vol)
        if path == "" then return end
        vol = (tonumber(vol) or 100) / 100
        if vol <= 0 then return end
        pcall(function() client.SetConVar("snd_toolvolume", vol, true) end)
        pcall(function() client.Command("play sounds\\" .. path, true) end)
    end

    function HS.playHit()  play(resolve(hsCmb), hsVol:Get()) end
    function HS.playKill() play(resolve(ksCmb), ksVol:Get()) end

    local bit_ = rawget(_G, "bit")
    local DLL  = "client.dll"
    local off  = {}
    pcall(function()
        local j = http.Get("https://raw.githubusercontent.com/a2x/cs2-dumper/main/output/offsets.json")
        local function pull(name) local v = j and j:match('"' .. name .. '"%s*:%s*(%-?%d+)'); return v and tonumber(v) or nil end
        off.dwEntityList            = pull("dwEntityList")
        off.dwLocalPlayerController = pull("dwLocalPlayerController")
    end)

    local band, rshift = (bit_ or {}).band, (bit_ or {}).rshift
    local function slot(elist, idx)
        if not valid(elist) then return nil end
        local chunk = r_ptr(elist + 8 * rshift(idx, 9) + 16); if not valid(chunk) then return nil end
        local e = r_ptr(chunk + 112 * band(idx, 0x1FF))
        if valid(e) and valid(r_ptr(e)) then return e end
        return nil
    end

    local function evHurt(d)
        if (d.dmg_health or 0) <= 0 then return end
        if type(ffi) == "table" and band and off.dwLocalPlayerController and off.dwEntityList then
            local base = mem.GetModuleBase(DLL)
            if base then
                local lctrl = r_ptr(base + off.dwLocalPlayerController)
                local elist = r_ptr(base + off.dwEntityList)
                if valid(lctrl) and valid(elist) then
                    if slot(elist, (d.attacker or -1) + 1) ~= lctrl then return end
                    if d.userid == d.attacker then return end
                end
            end
        end
        if (d.health or 1) <= 0 then
            if ksOn:Get() then HS.playKill() end
        elseif hsOn:Get() then HS.playHit() end
    end

    function HS.tick()
        if EV.installed then return end
        if EV.install() then EV.on("player_hurt", { "attacker", "userid", "health", "dmg_health" }, evHurt) end
    end

    local lastHs = nil
    function HS.sync()
        local s = table.concat({ hsOn:Get() and 1 or 0, hsCmb:Get(), hsVol:Get(),
                                 ksOn:Get() and 1 or 0, ksCmb:Get(), ksVol:Get() }, ":")
        if s == lastHs then return end
        lastHs = s
        C.setOpt("hs_on2", hsOn:Get()); C.setOpt("hs_snd2", hsCmb:Get()); C.setOpt("hs_vol2", hsVol:Get())
        C.setOpt("ks_on2", ksOn:Get()); C.setOpt("ks_snd2", ksCmb:Get()); C.setOpt("ks_vol2", ksVol:Get())
    end
end

local tab = M:Tab("Skins")

tab:Row()
weaponLb = tab:Section("Weapons"):Listbox("", C.names, "fill", 1)

tab:Col()
local sSec = tab:Section("Skins")
skinLb = sSec:Listbox("", { "[ select a weapon ]" }, "fill", 1)
skinWd = sSec.ws[#sSec.ws]

tab:Col()
local setSec = tab:Section("Settings")
sWear  = setSec:Slider("Wear / Float", 0.0001, 0.0, 1.0, 0.001, "%.3f")
sSeed  = setSec:Slider("Seed", 0, 0, 1000, 1)
cbAuto = setSec:Checkbox("Auto select weapon", false)

local actSec = tab:Section("Actions")
actSec:Button("Remove",    function() C.remove(item()) end)
actSec:Button("Reset All", function() C.resetAll() end)

local cfgSec = tab:Section("Config")
cfgSec:Button("Reset config", function() C.clearConfig() end)

local vtab = M:Tab("Visuals")

local submodels = vtab:Sub("Models")
submodels:Row()
local vSec = submodels:Section("List")
local mNames
mNames, modelPaths = C.modelList()
modelLb = vSec:Listbox("", mNames, "fill", 1)
modelWd = vSec.ws[#vSec.ws]
submodels:Col()
local vSsec = submodels:Section("Settings")
vSsec:Button("Refresh models", function()
    local cur = C.getLocalModel()
    local n, p = C.refreshModels()
    modelPaths     = p
    modelWd.items  = n
    modelWd.value  = 1
    modelWd.scroll = 0
    if cur then
        for i = 2, #p do if p[i] == cur then modelWd.value = i; break end end
    end
    lastModelSel = modelWd.value
end)

local sublocal = vtab:Sub("Local")
sublocal:Row()
local localSection = sublocal:Section("Local player")
cbVm = localSection:Checkbox("Viewmodel override", false)
vmX  = localSection:Slider("Offset X", 0, -30, 30, 0.1, "%.1f")
vmY  = localSection:Slider("Offset Y", 0, -30, 30, 0.1, "%.1f")
vmZ  = localSection:Slider("Offset Z", 0, -30, 30, 0.1, "%.1f")

local stab = M:Tab("Sounds")
stab:Row()
local hsSec = stab:Section("Hit sound")
hsOn    = hsSec:Checkbox("Enabled", true)
hsCmb   = hsSec:Combo("Sound", SND_NAMES, 1)
hsCmbWd = hsSec.ws[#hsSec.ws]
hsVol   = hsSec:Slider("Volume", 100, 0, 100, 1, "%.0f")

stab:Col()
local ksSec = stab:Section("Kill sound")
ksOn    = ksSec:Checkbox("Enabled", false)
ksCmb   = ksSec:Combo("Sound", SND_NAMES, 1)
ksCmbWd = ksSec.ws[#ksSec.ws]
ksVol   = ksSec:Slider("Volume", 100, 0, 100, 1, "%.0f")

stab:Col()
local tSec = stab:Section("Preview")
tSec:Button("Play hit",  function() HS.playHit() end)
tSec:Button("Play kill", function() HS.playKill() end)
tSec:Button("Rescan", function()
    local n, p = HS.scan()
    SND_PATHS = p
    hsCmbWd.options = n; hsCmbWd.value = 1
    ksCmbWd.options = n; ksCmbWd.value = 1
end)
tSec:Button("Open folder", function() HS.openSoundDir() end)

if C.loadConfig() then lastSel = -2 end
cbAuto:Set(C.getOpt("autoFollow") and true or false)
lastAuto = cbAuto:Get()

cbVm:Set(C.getOpt("vm_on") and true or false)
vmX:Set(tonumber(C.getOpt("vm_x")) or 0)
vmY:Set(tonumber(C.getOpt("vm_y")) or 0)
vmZ:Set(tonumber(C.getOpt("vm_z")) or 0)

do
    local cur = C.getLocalModel()
    if cur and modelPaths then
        for i = 2, #modelPaths do
            if modelPaths[i] == cur then modelLb:Set(i); break end
        end
    end
    lastModelSel = modelLb:Get()
end

local function getBool(k, d)
    local v = C.getOpt(k); if v == nil then return d end
    return v and true or false
end
hsOn:Set(getBool("hs_on2", true))
ksOn:Set(getBool("ks_on2", false))
local function setCmb(cmb, k)
    local i = tonumber(C.getOpt(k))
    if i and i >= 1 and i <= #SND_NAMES then cmb:Set(i) end
end
setCmb(hsCmb, "hs_snd2")
setCmb(ksCmb, "ks_snd2")
hsVol:Set(tonumber(C.getOpt("hs_vol2")) or 100)
ksVol:Set(tonumber(C.getOpt("ks_vol2")) or 100)

M:OnFrame(function()
    pcall(autoFollow)
    pcall(syncSkins)
    pcall(autoApply)
    pcall(persistOpts)
    pcall(syncModel)
    pcall(syncVm)
    pcall(EV.drain)
    pcall(HS.tick)
    pcall(HS.sync)
end)

M:Build({ w = 720, h = 500 })