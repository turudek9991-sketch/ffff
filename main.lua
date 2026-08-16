-- v2.4.13-boulder-burst
-- Single-session guard:
-- This script creates several long-lived Roblox connections. Running the same
-- script repeatedly without disconnecting the old session accumulates those
-- connections and eventually hits the executor's connection limit.
local __DHubEnv = (type(getgenv)=="function" and getgenv()) or _G
if __DHubEnv.__DHubMineMountainActive then
	return
end
__DHubEnv.__DHubMineMountainActive=true

-- [0.5] PREMIUM LICENSE / KEY STATE
-- Key is supplied by the loader through getgenv().key (or _G.key).
-- Firebase stores each key directly under /LivePets/<KEY>.
local PremiumLicense = {
	Key = "",
	IsPremium = false,
	Checked = false,
	Error = nil,
}

-- D-HUB: MINE A MOUNTAIN — v2.4.14 (Boulder Fast Dig control + clean Premium UI)
-- ============================================================
-- [1] SERVICES
local S = {
	Players           = game:GetService("Players"),
	CoreGui           = game:GetService("CoreGui"),
	RunService        = game:GetService("RunService"),
	Workspace         = game:GetService("Workspace"),
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
	UserInputService  = game:GetService("UserInputService"),
	TweenService      = game:GetService("TweenService"),
	HttpService       = game:GetService("HttpService"),
	TeleportService   = game:GetService("TeleportService"),
	GuiService        = game:GetService("GuiService"),
	VirtualUser       = game:GetService("VirtualUser"),
	Lighting          = game:GetService("Lighting"),
}
local LocalPlayer = S.Players.LocalPlayer
local Mouse       = LocalPlayer:GetMouse()

-- [2] CONFIG LOAD
local CONFIG_PATH = "D-HUB/MineAMountain.json"
pcall(function() if isfolder and not isfolder("D-HUB") then makefolder("D-HUB") end end)
local LoadedCfg   = {}
pcall(function()
	local content = readfile(CONFIG_PATH)
	if type(content) == "string" and content ~= "" then
		LoadedCfg = S.HttpService:JSONDecode(content)
	end
end)
if type(LoadedCfg) ~= "table" then LoadedCfg = {} end

-- [3] AFK
local afkConns   = {}
local afkRunning = true
do
	local function silenceIdle()
		local ok, list = pcall(function() return getconnections(LocalPlayer.Idled) end)
		if not ok or type(list) ~= "table" then return end
		for _, c in ipairs(list) do pcall(function() c:Disable() end) end
	end
	local function nudge()
		pcall(function()
			S.VirtualUser:CaptureController()
			S.VirtualUser:ClickButton2(Vector3.new())
		end)
	end
	silenceIdle()
	afkConns[#afkConns+1] = LocalPlayer.Idled:Connect(nudge)
	task.spawn(function()
		while afkRunning do
			task.wait(60)
			if not afkRunning or not LocalPlayer.Parent then break end
			silenceIdle(); nudge()
		end
	end)
end

-- [4] GUI ROOT
local function resolveGuiRoot()
	local ok, h = pcall(function() return gethui() end)
	if ok and typeof(h) == "Instance" then return h end
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pg then return pg end
	return LocalPlayer:WaitForChild("PlayerGui", 10) or S.CoreGui
end
local GuiRoot = resolveGuiRoot()
for _, container in ipairs({GuiRoot, S.CoreGui}) do
	for _, name in ipairs({"UniverseESPGui","UniverseCrystalEsp","DScriptsPF"}) do
		pcall(function()
			local e = container:FindFirstChild(name)
			if e then e:Destroy() end
		end)
	end
end

-- [5] REMOTE DISCOVERY
local _remoteFolder
local function getRemoteFolder()
	if _remoteFolder and _remoteFolder.Parent then return _remoteFolder end
	_remoteFolder = S.ReplicatedStorage:FindFirstChild("Remotes")
		or S.ReplicatedStorage:WaitForChild("Remotes", 10)
	return _remoteFolder
end
local function findRemote(name)
	local folder = getRemoteFolder()
	if not folder then return nil end
	return folder:FindFirstChild(name) or folder:WaitForChild(name, 5)
end
local RMT = {}
RMT.SellRequest    = findRemote("SellRequest")
RMT.GoHome         = findRemote("GoHome")
RMT.HoldComplete   = findRemote("CrystalHoldComplete")
RMT.ToggleFavorite = findRemote("ToggleFavorite")
RMT.ReviveBase     = findRemote("ReviveBase")
RMT.ReviveShow     = findRemote("ReviveShow")
RMT.BombActivate   = findRemote("BombActivate")
RMT.BombOpen       = findRemote("BombOpen")
RMT.BombBuyRequest = findRemote("BombBuyRequest")
RMT.Notify         = findRemote("Notify")
RMT.DigRequest     = findRemote("DigRequest")
RMT.ShopBuy        = findRemote("ShopBuy")
RMT.ShopEquip      = findRemote("ShopEquip")
RMT.UpgradeBuy     = findRemote("UpgradeBuy")
RMT.UpgradePrices  = findRemote("UpgradePrices")
RMT.RadarBuy       = findRemote("RadarBuy")
RMT.RadarBuyRequest = findRemote("RadarBuyRequest")
RMT.RadarShopQuery  = findRemote("RadarShopQuery")

-- [6] DATA TABLES
local BOMB_MATERIALS = {
	[Enum.Material.Pavement]   = {bombId="ClassicBomb",  tier=1, matName="Gunpowder Stone"},
	[Enum.Material.Salt]       = {bombId="WindBomb",     tier=2, matName="Skyglass"},
	[Enum.Material.Ice]        = {bombId="IceBomb",      tier=3, matName="Cryostone"},
	[Enum.Material.LeafyGrass] = {bombId="FireBomb",     tier=4, matName="Cinderforge Plate"},
	[Enum.Material.Asphalt]    = {bombId="ThunderBomb",  tier=5, matName="Stormsteel"},
	[Enum.Material.Concrete]   = {bombId="PoisonBomb",   tier=6, matName="Venomite"},
	[Enum.Material.Cobblestone]= {bombId="TimeBomb",     tier=7, matName="Chronoshard"},
	[Enum.Material.Brick]      = {bombId="AgonyBomb",    tier=8, matName="Dreadstone"},
}
local BOMB_TIER = {
	ClassicBomb=1, WindBomb=2, IceBomb=3, FireBomb=4,
	ThunderBomb=5, PoisonBomb=6, TimeBomb=7, AgonyBomb=8, NukeBomb=9,
}
local BOMB_CONFIG = {
	ClassicBomb  = {displayName="Classic Bomb",  fuse=2.5, cashPrice=50000},
	WindBomb     = {displayName="Wind Bomb",     fuse=2.5, cashPrice=400000},
	IceBomb      = {displayName="Ice Bomb",      fuse=2.5, cashPrice=2000000},
	FireBomb     = {displayName="Fire Bomb",     fuse=2.5, cashPrice=5000000},
	ThunderBomb  = {displayName="Thunder Bomb",  fuse=2.5, cashPrice=15000000},
	PoisonBomb   = {displayName="Poison Bomb",   fuse=2.5, cashPrice=40000000},
	TimeBomb     = {displayName="Time Bomb",     fuse=4.0, cashPrice=175000000},
	AgonyBomb    = {displayName="Agony Bomb",    fuse=3.6, cashPrice=600000000},
}
local PICKAXE_SHOP = {
	{id="RustyScrapper",   displayName="Rusty Scrapper",    cashPrice=0},
	{id="WeatheredWood",   displayName="Weathered Wood",    cashPrice=50},
	{id="ChippedStone",    displayName="Chipped Stone",     cashPrice=200},
	{id="HardenedIron",    displayName="Hardened Iron",     cashPrice=600},
	{id="CopperPick",      displayName="Copper Pick",       cashPrice=1500},
	{id="ReinforcedSteel", displayName="Reinforced Steel",  cashPrice=4000},
	{id="TitaniumSpike",   displayName="Titanium Spike",    cashPrice=10000},
	{id="FrostbitePick",   displayName="Frostbite Pick",    cashPrice=25000},
	{id="EmeraldCarver",   displayName="Emerald Carver",    cashPrice=60000},
	{id="VolcanoBasalt",   displayName="Volcano Basalt",    cashPrice=15000},
	{id="ObsidianEdge",    displayName="Obsidian Edge",     cashPrice=400000},
	{id="TempestPick",     displayName="Tempest Pick",      cashPrice=1000000},
	{id="CelestialApex",   displayName="Celestial Apex",    cashPrice=2500000},
	{id="AstralRend",      displayName="Astral Rend",       cashPrice=6000000},
	{id="EclipseFang",     displayName="Eclipse Fang",      cashPrice=15000000},
	{id="NebularThrone",   displayName="Nebular Throne",    cashPrice=35000000},
	{id="Voidreign",       displayName="Voidreign",         cashPrice=80000000},
	{id="Singularity",     displayName="Singularity",       cashPrice=180000000},
	{id="TheTerminus",     displayName="The Terminus",      cashPrice=400000000},
}
local RADAR_SHOP = {
	{id="CrystalRadar",     displayName="Crystal Radar",     cashPrice=0},
	{id="CaveRadar",        displayName="Cave Radar",        cashPrice=0},
	{id="LavaRadar",        displayName="Lava Radar",        cashPrice=0},
	{id="AetherstoneRadar", displayName="Aetherstone Radar", cashPrice=0},
	{id="BombveinsRadar",   displayName="Bombveins Radar",   cashPrice=0},
	{id="BoulderRadar",     displayName="Boulder Radar",     cashPrice=0},
}
do
	local mod=game:GetService("ReplicatedStorage"):FindFirstChild("ShopCatalog",true)
	if mod and mod:IsA("ModuleScript") then
		local ok,data=pcall(require,mod)
		if ok and type(data)=="table" and type(data.Pickaxes)=="table" then
			table.clear(PICKAXE_SHOP)
			for _,entry in pairs(data.Pickaxes) do
				if type(entry)=="table" and type(entry.id)=="string" then
					PICKAXE_SHOP[#PICKAXE_SHOP+1]={id=entry.id,displayName=entry.toolName or entry.name or entry.id,cashPrice=tonumber(entry.price) or 0}
				end
			end
		end
	end
end
do
	local mod=game:GetService("ReplicatedStorage"):FindFirstChild("RadarShopConfig",true)
	if mod and mod:IsA("ModuleScript") then
		local ok,data=pcall(require,mod)
		local radars=ok and type(data)=="table" and data.RADARS or nil
		if type(radars)=="table" then
			table.clear(RADAR_SHOP)
			for id,entry in pairs(radars) do
				if type(entry)=="table" then
					RADAR_SHOP[#RADAR_SHOP+1]={id=tostring(id),displayName=entry.displayName or entry.name or tostring(id),cashPrice=tonumber(entry.cashPrice) or 0,rarity=entry.rarity}
				end
			end
			table.sort(RADAR_SHOP,function(a,b) return a.id<b.id end)
		end
	end
end
local BOMB_SHOP_ORDER = {"ClassicBomb","WindBomb","IceBomb","FireBomb","ThunderBomb","PoisonBomb","TimeBomb","AgonyBomb"}
local RARITY_LIST = {"Default","Common","Uncommon","Rare","Epic","Legendary","Mythic","Empyrean","Pulsar","Quasar"}
local function isBombMaterial(mat) return BOMB_MATERIALS[mat] ~= nil end
local function sampleTerrainMaterial(position)
	local VOXEL = 4; local half = Vector3.new(VOXEL*0.5, VOXEL*0.5, VOXEL*0.5)
	local region = Region3.new(position - half, position + half)
	local ok, mats = pcall(workspace.Terrain.ReadVoxels, workspace.Terrain, region, VOXEL)
	if not ok or not mats then return nil end
	local sz = mats.Size
	if sz.X >= 1 and sz.Y >= 1 and sz.Z >= 1 then
		local m = mats[1][1][1]; if m ~= Enum.Material.Air then return m end
	end
	return nil
end

-- [7] CFG CONSTANTS
local CFG = {
	ESP = {
		font   = Enum.Font.GothamMedium,
		sweep  = 0.5,
		budget = 0.005,
		offset = Vector3.new(0, 3, 0),
		width  = 250,
		height = 66,
		text   = 16,
		ttl    = 5,
	},
	PLAYER = {offset=Vector3.new(0,-8,0), width=220, height=44, text=15},
	PACE   = {boost=35, normal=16, stats=0.25, distance=0.05},
	TP = {
		offset = Vector3.new(0, 4.5, 0),
		hold   = 0.35,
		clear  = {
			Vector3.new(0,0,0), Vector3.new(0,3,0), Vector3.new(0,7,0),
			Vector3.new(5,3,0), Vector3.new(-5,3,0), Vector3.new(0,3,5),
			Vector3.new(0,3,-5), Vector3.new(0,12,0), Vector3.new(9,6,0),
			Vector3.new(-9,6,0), Vector3.new(0,6,9), Vector3.new(0,6,-9),
			Vector3.new(0,20,0),
		},
	},
	PICK = {
		aimRange=5000, aimDot=0.995, range=13, cooldown=0.04,
		restore=0.2, burst=8, retry=0.15, forget=5, pad=4,
		instantRadius=60, instantTick=0.25,
	},
	COLORS = {
		money=Color3.fromRGB(60,255,90), default=Color3.fromRGB(0,225,255),
		extra=Color3.fromRGB(255,255,255), player=Color3.fromRGB(255,40,140),
		stroke=Color3.fromRGB(0,0,0), hexDistance="00E5FF", hexLuck="FFC400",
		vein=Color3.fromRGB(255,170,0),
	},
	TIER_NAMES   = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Empyrean","Pulsar","Quasar"},
	LUCK         = {rarity={1,1.6,2.6,4.2,7,12}, base=0.00045, exponent=0.5, cap=500, bomb=3, blood=4},
	MUTATION_LUCK = {
		Verdant=15, Voltaic=20, Gilded=18, Onyx=28, Terminus=40,
		Frost=1.4, Fire=1.4, Thunder=1.5, Starfall=1.3,
		Aurora=2.2, Radioactive=2, Poison=1.5, Wet=1,
	},
	WATCHED_ATTRIBUTES = {
		"Value","Collected","WeightKg","Tier","TierName","CrystalName","Mutation","ExtraMutations",
	},
	SUFFIXES          = {"","k","M","B","T","Qa"},
	PARSE_MULTIPLIERS = {k=1e3, m=1e6, b=1e9, t=1e12, qa=1e15},
	CONTAINER_NAMES   = {"DroppedCrystals","Crystals"},
}

-- [8] ESP HOLDER
local EspHolder    = Instance.new("Folder")
EspHolder.Name     = "UniverseCrystalEsp"
EspHolder.Parent   = GuiRoot

-- [9] TOGGLES + CACHE + STATE
local saveConfig
local Toggles = {
	CrystalEsp       = LoadedCfg.CrystalEsp == true,
	PlayerEsp        = LoadedCfg.PlayerEsp == true,
	BoulderEsp       = LoadedCfg.BoulderEsp == true,
	VeinEsp          = LoadedCfg.VeinEsp == true,
	PrismariteEsp    = LoadedCfg.PrismariteEsp == true,
	AimTeleport      = LoadedCfg.AimTeleport == true,
	AutoPickup       = LoadedCfg.AutoPickup == true,
	InstantPrompt    = LoadedCfg.InstantPrompt == true,
	AutoRunePickup   = LoadedCfg.AutoRunePickup == true,
	AutoFavoriteItem = LoadedCfg.AutoFavoriteItem == true,
	AutoDig          = LoadedCfg.AutoDig == true,
	AutoFarmMoney    = LoadedCfg.AutoFarmMoney == true,
	AutoFarmBoulders = LoadedCfg.AutoFarmBoulders == true,
	AutoFarmPrismarite = LoadedCfg.AutoFarmPrismarite == true,
	PremiumAutoPickup = LoadedCfg.PremiumAutoPickup == true,
	MoneyAutoSell    = LoadedCfg.MoneyAutoSell == true,
	AutoWeightUpgrade= LoadedCfg.AutoWeightUpgrade == true,
	AutoAirUpgrade   = LoadedCfg.AutoAirUpgrade == true,
	AutoBuyPick      = LoadedCfg.AutoBuyPick == true,
	AutoBomb         = LoadedCfg.AutoBomb == true,
	AutoBuyBombs     = LoadedCfg.AutoBuyBombs == true,
	AutoBuyRadar     = LoadedCfg.AutoBuyRadar == true,
	SpeedBoost       = LoadedCfg.SpeedBoost == true,
	Noclip           = LoadedCfg.Noclip == true,
	InfJump          = LoadedCfg.InfJump == true,
	Fly              = LoadedCfg.Fly == true,
	AutoRevive       = LoadedCfg.autoRevive == true,
	FpsBoost         = LoadedCfg.fpsBoost == true,
	UltraFps         = LoadedCfg.ultraFps == true or LoadedCfg.fpsBoost == true,
	AutoHop          = LoadedCfg.autoHop == true,
}
local ToggleSetFn = {}
local Cache = {
	registry={}, candidates={}, dirty={}, espCache={},
	playerCache={}, containerConns={}, claimed={}, instantPatched={},
	promptRestores={}, pendingActions={}, pickupFound={}, pickupSeen={},
	boulderFarmFilter={}, veinCache={},
}
local DHubState = {
	DHubState.registryCount = 0,
	DHubState.espCount = 0,
	DHubState.aimTeleport = nil,
	DHubState.valueFilter = minValue > 0,
	DHubState.autoHopMinutes = LoadedCfg.autoHopMinutes or 30,
	DHubState.boulderFastDig = LoadedCfg.boulderFastDig == true,
	DHubState.boulderDigSpeed = math.clamp(tonumber(LoadedCfg.boulderDigSpeed) or 200,100,500),
	DHubState.premiumMinLuck = tonumber(LoadedCfg.premiumMinLuck) or 0,
	DHubState.premiumFarmMethod = (LoadedCfg.premiumFarmMethod == "Random Server") and "Random Server" or "Current Server",
	DHubState.selectedRadarToBuy = LoadedCfg.selectedRadarToBuy or "",
	DHubState.autoBuyRadarActive = Toggles.AutoBuyRadar,
}


local espActive           = Toggles.CrystalEsp
local playerEspActive     = Toggles.PlayerEsp
local veinEspActive       = Toggles.VeinEsp
local prismariteEspActive = Toggles.PrismariteEsp
local aimTpEnabled        = Toggles.AimTeleport

local speedActive         = Toggles.SpeedBoost
local autoPickupActive    = Toggles.AutoPickup
local instantPromptActive = Toggles.InstantPrompt
local autoReviveActive    = Toggles.AutoRevive
local autoFarmPrismariteActive = Toggles.AutoFarmPrismarite
Toggles.FpsBoost = Toggles.FpsBoost or Toggles.UltraFps
local fpsBoostActive      = Toggles.FpsBoost
local autoHopActive       = Toggles.AutoHop
local autoBombActive      = Toggles.AutoBomb
local minValue            = LoadedCfg.minValue or 0
local boulderMinLuck      = tonumber(LoadedCfg.boulderMinLuck) or 0



local espScale            = (LoadedCfg.espScale or 70) / 100
local playerScale         = (LoadedCfg.playerScale or 60) / 100
local boulderScale        = (LoadedCfg.boulderScale or 60) / 100
-- Boulder Dig Speed: OFF keeps the current/default V9 burst timing exactly.
-- When Fast Dig is enabled, the slider acts as a speed multiplier in percent.




local selectedPickaxeToBuy = LoadedCfg.selectedPickaxeToBuy or ""
local selectedBombToBuy = {}
do
	local raw = LoadedCfg.selectedBombToBuy
	if type(raw) == "table" then
		for _, id in ipairs(raw) do
			if type(id) == "string" and BOMB_CONFIG[id] then selectedBombToBuy[id] = true end
		end
	elseif type(raw) == "string" and raw ~= "" and BOMB_CONFIG[raw] then
		selectedBombToBuy[raw] = true
	end
end

local autoBuyBombsActive   = Toggles.AutoBuyBombs


local crystalFilter = {}
do
	local raw = LoadedCfg.crystalFilter
	if type(raw) == "table" then for _, v in ipairs(raw) do if type(v)=="string" then crystalFilter[v]=true end end end
end
local rarityPickupFilter = {}
do
	local raw = LoadedCfg.rarityPickupFilter
	if type(raw) == "table" then
		for _, v in ipairs(raw) do
			if type(v)=="string" and v~="Default" and v~="" then rarityPickupFilter[v]=true end
		end
	end
end
local crystalEspFilter = {}
do
	local raw = LoadedCfg.crystalEspFilter
	if type(raw) == "table" then for _, v in ipairs(raw) do if type(v)=="string" then crystalEspFilter[v]=true end end end
end
local boulderEspFilter = {}
do
	local raw = LoadedCfg.boulderEspFilter
	if type(raw) == "table" then for _, v in ipairs(raw) do if type(v)=="string" then boulderEspFilter[v]=true end end end
end
local veinEspFilter = {}
do
	local raw = LoadedCfg.veinEspFilter
	if type(raw) == "table" then for _, v in ipairs(raw) do if type(v)=="string" then veinEspFilter[v]=true end end end
end
local farmCrystalFilter = {}
do
	local raw = LoadedCfg.farmCrystalFilter
	if type(raw) == "table" then for _, v in ipairs(raw) do if type(v)=="string" then farmCrystalFilter[v]=true end end end
end
local farmRarityFilter = {}
do
	local raw = LoadedCfg.farmRarityFilter
	if type(raw) == "table" then
		for _, v in ipairs(raw) do
			if type(v)=="string" and v~="Default" and v~="" then farmRarityFilter[v]=true end
		end
	end
end
local premiumRarityFilter = {}
do
	local raw = LoadedCfg.premiumRarityFilter
	if type(raw) == "table" then
		for _, v in ipairs(raw) do
			if type(v)=="string" and v~="Default" and v~="" then premiumRarityFilter[v]=true end
		end
	end
end
if type(LoadedCfg.boulderFarmFilter)=="table" then
	for _,v in ipairs(LoadedCfg.boulderFarmFilter) do
		if type(v)=="string" then Cache.boulderFarmFilter[v]=true end
	end
end

local Runtime = {
	PrismariteFarmActive = false,
	speedHooked = nil,
	speedConn = nil,
	rootPart = nil,
	tpState = nil,
	lastReport = 0,
	sweepAccumulator = math.huge,
	statsDirty = true,
	statsAccumulator = 0,
	distanceAccumulator = math.huge,
	lastPickup = 0,
	lastBagWarn = 0,
	instantAccumulator = math.huge,
	autoHopStartClock = 0,
	autoHopConn = nil,
	savedParticleState = {},
	savedCastShadow = {},
	savedPostFx = {},
	savedLightState = {},
	fpsBoostDescConn = nil,
	ultraDescConn = nil,
	fpsPassId = 0,
	ultraPassId = 0,	savedWaterWaveSpeed = nil,
	ultraPlayerAccumulator = 0, ultraBackpackAccumulator = 0,
	StatsLabel=nil, BackpackLabel=nil, sellClock=0, lastGlobalAutoSell=0, configSaveClock=0, aimParams=nil, aimFDown=false,
	savedWaterReflectance = nil,
	BoulderVeinBlocked = false,
	BoulderVeinSerial = 0,
	_pickupStepRunning = false,
	prismariteCache = {},
	favoriteSentAt = setmetatable({}, {__mode="k"}),
	farmMethod = (LoadedCfg.farmMethod == "Random Server") and "Random Server" or "Current Server",
	farmReturnJobId = nil,
	autoDigAccumulator = 0,
	autoDigLastFire = 0,
	AutoDigButton = nil, AutoDigSet = nil,
	FarmMethodButton = nil, FarmMethodGet = nil, FarmMethodSet = nil,
}

-- Boulder/Vein coordination: a bomb-required notification blocks the current Boulder.
-- Auto Bomb clears this flag only after the vein is verified gone.
local function isBombRequirementNotification(text)
	if type(text) ~= "string" then return false end
	local lower=text:lower()
	for _,name in ipairs({"Agony Bomb","Time Bomb","Poison Bomb","Thunder Bomb","Fire Bomb","Ice Bomb","Wind Bomb","Classic Bomb"}) do
		if lower:find(name:lower(),1,true) then return true end
	end
	return false
end
if RMT.Notify and RMT.Notify:IsA("RemoteEvent") then
	RMT.Notify.OnClientEvent:Connect(function(_,text)
		if isBombRequirementNotification(text) then
			Runtime.BoulderVeinBlocked=true
			Runtime.BoulderVeinSerial=(Runtime.BoulderVeinSerial or 0)+1
		end
	end)
end

-- [10] NOTIFY
local function Notify(text, duration)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification",{
			Title="D-Hub", Text=tostring(text), Duration=duration or 3
		})
	end)
end

-- [11] UTILITIES
local function reportError(context, err)
	local now = os.clock()
	if now - Runtime.lastReport < 5 then return end
	Runtime.lastReport = now
	warn(string.format("[MaM] %s: %s", context, tostring(err)))
end
local function formatShort(n, prefix)
	n = tonumber(n) or 0; prefix = prefix or ""
	local sign = n<0 and "-" or ""; n=math.abs(n)
	if n<1000 then return string.format("%s%s%d",sign,prefix,math.floor(n+0.5)) end
	local index=0
	while n>=1000 and index<#CFG.SUFFIXES-1 do n=n/1000; index=index+1 end
	return string.format("%s%s%.2f%s",sign,prefix,n,CFG.SUFFIXES[index+1])
end
local function formatWeight(kg)
	kg=tonumber(kg) or 0
	if kg>=1000 then return formatShort(kg).."kg" end
	return string.format("%.1fkg",kg)
end
local function formatDistance(studs)
	studs=tonumber(studs) or 0
	if studs>=1000 then return string.format("%.1fkm",studs/1000) end
	return string.format("%dm",math.floor(studs+0.5))
end
local function formatLuck(score)
	local pct=(tonumber(score) or 0)*100
	if pct<=0 then return "+0%" end
	if pct<1  then return string.format("+%.2f%%",pct) end
	if pct<10 then return string.format("+%.1f%%",pct) end
	return string.format("+%.0f%%",pct)
end
local function parseValue(text)
	if type(text)~="string" then return nil end
	local cleaned=text:lower():gsub("[%s,%$_]","")
	if cleaned=="" then return 0 end
	local number,suffix=cleaned:match("^(%d*%.?%d+)(%a*)$")
	if not number then return nil end
	local base=tonumber(number); if not base then return nil end
	if suffix=="" then return base end
	local mult=CFG.PARSE_MULTIPLIERS[suffix]; if not mult then return nil end
	return base*mult
end
local function fireRemote(remote,...)
	if not remote then return false end
	local args=table.pack(...)
	return pcall(function() remote:FireServer(table.unpack(args,1,args.n)) end)
end
local function schedule(delay, fn)
	Cache.pendingActions[#Cache.pendingActions+1]={at=os.clock()+delay, fn=fn}
end

-- [12] CHARACTER
local function bindCharacter(character)
	if not character then Runtime.rootPart=nil; return end
	Runtime.rootPart=character:FindFirstChild("HumanoidRootPart")
end
bindCharacter(LocalPlayer.Character)
local characterConn=LocalPlayer.CharacterAdded:Connect(function(character)
	Runtime.rootPart=nil; Runtime.tpState=nil
	if Runtime.favoriteWatchCharacter then Runtime.favoriteWatchCharacter(character) end
	local waiter
	waiter=character.ChildAdded:Connect(function(child)
		if child.Name=="HumanoidRootPart" then
			Runtime.rootPart=child; waiter:Disconnect()
		end
	end)
	bindCharacter(character)
	if Runtime.rootPart then waiter:Disconnect() end
end)
local function getRoot()
	if Runtime.rootPart and Runtime.rootPart.Parent then return Runtime.rootPart end
	bindCharacter(LocalPlayer.Character)
	return Runtime.rootPart
end

-- [13] ATTRIBUTE HELPERS
local function getAttr(inst,name)
	local ok,value=pcall(inst.GetAttribute,inst,name)
	return ok and value or nil
end
local function crystalValue(inst)  return tonumber(getAttr(inst,"Value")) or 0 end
local function crystalWeight(inst) return tonumber(getAttr(inst,"WeightKg")) or 0 end
local function crystalTier(inst)   return tonumber(getAttr(inst,"Tier")) or 0 end
local function crystalRarity(inst)
	local name=getAttr(inst,"TierName")
	if type(name)=="string" and name~="" then return name end
	return CFG.TIER_NAMES[crystalTier(inst)] or "Unknown"
end
local function crystalName(inst)
	local name=getAttr(inst,"CrystalName")
	if type(name)=="string" and name~="" then return name end
	return inst.Name
end
local function crystalColor(inst)
	local r=tonumber(getAttr(inst,"TierColorR"))
	local g=tonumber(getAttr(inst,"TierColorG"))
	local b=tonumber(getAttr(inst,"TierColorB"))
	if r and g and b then return Color3.fromRGB(r,g,b) end
	return CFG.COLORS.default
end
local function mutationLuck(name)
	if type(name)~="string" or name=="" then return 1 end
	return CFG.MUTATION_LUCK[name] or 1
end
local function combinedLuckMult(inst)
	local mutation=getAttr(inst,"Mutation")
	local roll=tonumber(getAttr(inst,"MutationLuckRoll"))
	local mult=(roll and roll>0) and roll or mutationLuck(mutation)
	local extra=getAttr(inst,"ExtraMutations")
	if type(extra)=="string" and extra~="" then
		for n in string.gmatch(extra,"[^,]+") do
			if n~="" then mult=mult*mutationLuck(n) end
		end
	end
	if getAttr(inst,"IsBloodCrystal")==true then mult=mult*CFG.LUCK.blood end
	if getAttr(inst,"AdminMutation")=="Radioactive" and mutation~="Radioactive" then
		local has=type(extra)=="string" and extra:find("Radioactive",1,true)~=nil
		if not has then mult=mult*mutationLuck("Radioactive") end
	end
	return mult
end
local function computeLuck(inst)
	local tier=crystalTier(inst); if tier<=0 then return 0 end
	local weight=math.max(0,crystalWeight(inst))
	local base=(CFG.LUCK.rarity[tier] or CFG.LUCK.rarity[1])
		*math.min(weight,CFG.LUCK.cap)^CFG.LUCK.exponent*CFG.LUCK.base
	if getAttr(inst,"BombCrystal")==true then base=base*CFG.LUCK.bomb end
	return base*combinedLuckMult(inst)
end
local function luckLabel(inst)
	local hover=inst:FindFirstChild("CrystalHover"); if not hover then return nil end
	local label=hover:FindFirstChild("LuckBoost")
	if not label or not label:IsA("TextLabel") then return nil end
	return label
end
local function luckLabelText(inst)
	local label=luckLabel(inst); return label and label.Text or nil
end
local function crystalLuck(inst)
	local text=luckLabelText(inst)
	if type(text)=="string" then
		local pct=tonumber(text:match("([%d%.]+)%s*%%"))
		if pct and pct>0 then return pct/100 end
	end
	return computeLuck(inst)
end

-- ============================================================
-- ============================================================
-- STANDALONE AUTO FAVORITE ITEM
-- Uses the exact inventory path/remote captured from manual Favorite.
-- Does not depend on any farming, pickup, rune, rarity, or value logic.
-- ============================================================
Runtime.favoriteMinLuck = tonumber(LoadedCfg.favoriteMinLuck)
if Runtime.favoriteMinLuck == nil or Runtime.favoriteMinLuck < 0 then Runtime.favoriteMinLuck = 10 end
Runtime.favoriteMinLuck = math.clamp(Runtime.favoriteMinLuck,0,100000)
Runtime.favoritePending = Runtime.favoritePending or setmetatable({}, {__mode="k"})

Runtime.autoFavoriteInventoryStep = function()
	if Toggles.AutoFavoriteItem ~= true then return end
	local threshold = tonumber(Runtime.favoriteMinLuck)
	if threshold == nil or threshold < 0 then threshold = 10 end
	local player = LocalPlayer
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return end
	local remotes = S.ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("ToggleFavorite")
	if not event or not event:IsA("RemoteEvent") then return end

	local function readLuck(tool)
		if not tool or not tool:IsA("Tool") then return nil end
		local handle = tool:FindFirstChild("Handle")
		local billboard = handle and handle:FindFirstChild("CrystalToolBillboard")
		local label = billboard and billboard:FindFirstChild("LuckBoost")
		-- The game UI stores the crystal Luck here: Backpack/Tool/Handle/
		-- CrystalToolBillboard/LuckBoost. Do not fall back to unrelated labels.
		if not label or not label:IsA("TextLabel") then return nil end
		local text=label.Text
		if type(text)~="string" then return nil end
		local n=tonumber(text:match("^[Ll]uck:%s*%+?%s*([%d]+[%.]?[%d]*)%s*%%$"))
		if n==nil then n=tonumber(text:match("([%d]+[%.]?[%d]*)%s*%%")) end
		return n
	end

	local function tryFavorite(tool,target)
		if not tool or not tool:IsA("Tool") then return end
		local handle=tool:FindFirstChild("Handle")
		local billboard=handle and handle:FindFirstChild("CrystalToolBillboard")
		local luckLabel=billboard and billboard:FindFirstChild("LuckBoost")
		if not billboard or not luckLabel or not luckLabel:IsA("TextLabel") then return end
		if tool:GetAttribute("Favorited")==true or tool:GetAttribute("Favorite")==true then return end
		local luck=readLuck(tool)
		if luck==nil or luck < threshold then return end
		local serverTool=target or backpack:FindFirstChild(tool.Name)
		if not serverTool then return end
		local pendingAt=Runtime.favoritePending[serverTool]
		if pendingAt and (os.clock()-pendingAt)<2 then return end
		Runtime.favoritePending[serverTool]=os.clock()
		local ok=pcall(function() event:FireServer(serverTool,true) end)
		if not ok then Runtime.favoritePending[serverTool]=nil end
	end

	for _,tool in ipairs(backpack:GetChildren()) do
		if tool:IsA("Tool") then tryFavorite(tool,backpack:FindFirstChild(tool.Name)) end
	end
	local character=player.Character
	if character then
		for _,tool in ipairs(character:GetChildren()) do
			if tool:IsA("Tool") then tryFavorite(tool,tool) end
		end
	end
end

Runtime.unfavoriteAllCrystalItems = function()
	local player=LocalPlayer
	local remotes=S.ReplicatedStorage:FindFirstChild("Remotes")
	local event=remotes and remotes:FindFirstChild("ToggleFavorite")
	if not event or not event:IsA("RemoteEvent") then return end
	local function process(container)
		if not container then return end
		for _,tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") then
				local handle=tool:FindFirstChild("Handle")
				local billboard=handle and handle:FindFirstChild("CrystalToolBillboard")
				if billboard and (tool:GetAttribute("Favorited")==true or tool:GetAttribute("Favorite")==true) then
					pcall(function() event:FireServer(tool,false) end)
				end
				Runtime.favoritePending[tool]=nil
			end
		end
	end
	process(player:FindFirstChildOfClass("Backpack")); process(player.Character)
end

Runtime.setFavoriteMinLuck = function(text)
	-- IMPORTANT: string.gsub returns (string, count). Never pass it
	-- directly into tonumber or the count is treated as the numeric base.
	local cleaned=tostring(text or ""):gsub("%%", "")
	cleaned=cleaned:match("^%s*(.-)%s*$") or cleaned
	local n=tonumber(cleaned)
	if n==nil then return end
	n=math.clamp(n,0,100000)
	Runtime.favoriteMinLuck=n
	LoadedCfg.favoriteMinLuck=n
	-- Save immediately so changing the textbox is persisted before any
	-- later heartbeat/config save can occur.
	local saved=saveConfig()
	if not saved then
		warn("[D-HUB] Failed to save favoriteMinLuck config")
	end
	if Toggles.AutoFavoriteItem==true then Runtime.autoFavoriteInventoryStep() end
end

Runtime.toggleFavoriteItem = function()
	Toggles.AutoFavoriteItem=not Toggles.AutoFavoriteItem
	if ToggleSetFn.AutoFavoriteItem then ToggleSetFn.AutoFavoriteItem(Toggles.AutoFavoriteItem) end
	pcall(saveConfig)
	if Toggles.AutoFavoriteItem==true then Runtime.autoFavoriteInventoryStep() end
end

Runtime.favoriteWatchBackpack = function(backpack)
	if not backpack then return end
	if Runtime.favoriteBackpackConn then pcall(function() Runtime.favoriteBackpackConn:Disconnect() end) end
	Runtime.favoriteBackpackConn=backpack.ChildAdded:Connect(function(child)
		if not Toggles.AutoFavoriteItem or not child:IsA("Tool") then return end
		task.delay(0.35,function()
			if child.Parent==backpack and Toggles.AutoFavoriteItem then Runtime.autoFavoriteInventoryStep() end
		end)
	end)
end

Runtime.favoriteWatchCharacter = function(character)
	if not character then return end
	if Runtime.favoriteCharacterConn then pcall(function() Runtime.favoriteCharacterConn:Disconnect() end) end
	Runtime.favoriteCharacterConn=character.ChildAdded:Connect(function(child)
		if not Toggles.AutoFavoriteItem or not child:IsA("Tool") then return end
		task.delay(0.35,Runtime.autoFavoriteInventoryStep)
	end)
end

task.spawn(function()
	local backpack=LocalPlayer:FindFirstChildOfClass("Backpack") or LocalPlayer:WaitForChild("Backpack",10)
	Runtime.favoriteWatchBackpack(backpack)
	Runtime.favoriteWatchCharacter(LocalPlayer.Character)
end)

local function meetsFilter(inst, value)
	if DHubState.valueFilter and (value or crystalValue(inst)) < minValue then return false end
	if next(crystalFilter)~=nil then
		local cname=crystalName(inst)
		if not crystalFilter[cname] then return false end
	end
	return true
end
-- New filter logic applied for Money Farm
local function meetsFarmFilter(inst, value)
	if DHubState.valueFilter and (value or crystalValue(inst)) < minValue then return false end
	if next(farmCrystalFilter)~=nil then
		local cname=crystalName(inst)
		if not farmCrystalFilter[cname] then return false end
	end
	if next(farmRarityFilter)~=nil then
		local rarity=crystalRarity(inst)
		if not farmRarityFilter[rarity] then return false end
	end
	return true
end
-- Unified rarity/luck pickup rule. An empty rarity filter means ALL rarities.
-- A positive luck threshold means luck >= the configured percentage.
local function meetsPickupFilter(inst, value)
	if not inst then return false end
	value = value or crystalValue(inst)
	if next(rarityPickupFilter)~=nil and not rarityPickupFilter[crystalRarity(inst)] then return false end
	if boulderMinLuck>0 then
		local luckPct=(tonumber(crystalLuck(inst)) or 0)*100
		if luckPct+1e-6<boulderMinLuck then return false end
	end
	return true
end

-- [14] BACKPACK
local function ownsGamepass(name)
	local folder=LocalPlayer:FindFirstChild("GamepassesOwned"); if not folder then return false end
	local flag=folder:FindFirstChild(name)
	return flag~=nil and flag:IsA("BoolValue") and flag.Value==true
end
local function realStat(name)
	local data=LocalPlayer:FindFirstChild("PlayerData")
	local stats=data and data:FindFirstChild("RealStats")
	local entry=stats and stats:FindFirstChild(name)
	return entry and tonumber(entry.Value) or nil
end
local function hasActiveRune(keyword)
	local data=LocalPlayer:FindFirstChild("PlayerData")
	local plot=data and data:FindFirstChild("PlotData")
	local runes=plot and plot:FindFirstChild("Runes")
	if not runes then return false end
	for _,child in ipairs(runes:GetChildren()) do
		local runeName=child:GetAttribute("RuneName")
		if type(runeName)=="string" and runeName:find(keyword,1,true) then
			if (tonumber(child:GetAttribute("Remaining")) or 0)>0 then return true end
		end
	end
	return false
end
local function backpackCapacity()
	if LocalPlayer:GetAttribute("InfBackpack")==true then return math.huge end
	local base=realStat("CarryWeight") or 10
	if ownsGamepass("CarryKgPlus4") then base=base*4 end
	local total=base+(realStat("CarryWeightBonus") or 0)
	if hasActiveRune("Weight") then return total*2 end
	return total
end
local function backpackWeight()
	local total=0
	local function scan(c)
		if not c then return end
		for _,child in ipairs(c:GetChildren()) do
			if child:IsA("Tool") and getAttr(child,"Tier")~=nil then
				local kg=tonumber(getAttr(child,"WeightKg"))
				if kg then total=total+kg end
			end
		end
	end
	scan(LocalPlayer:FindFirstChildOfClass("Backpack"))
	scan(LocalPlayer.Character)
	return total
end
local function backpackFree()
	local cap=backpackCapacity()
	if cap==math.huge then return math.huge end
	return cap-backpackWeight()
end

-- [15] BOMB INVENTORY
local function getBombCount(bombId)
	local data=LocalPlayer:FindFirstChild("PlayerData")
	local inv=data and data:FindFirstChild("Inventory")
	local bombs=inv and inv:FindFirstChild("Bombs")
	if not bombs then return 0 end
	local entry=bombs:FindFirstChild(bombId)
	if entry then
		local n=tonumber(entry.Value); if n then return n end
		if entry:IsA("IntValue") or entry:IsA("NumberValue") then return tonumber(entry.Value) or 0 end
	end
	return 0
end

-- [16] CRYSTAL DETECTION
local function looksLikeCrystal(inst)
	if not inst:IsA("BasePart") then return false end
	return inst.Name:find("Crystal",1,true)~=nil
end
local crystalFlags=setmetatable({},{__mode="k"})
local function isCrystal(inst)
	local cached=crystalFlags[inst]; if cached~=nil then return cached end
	local result=false
	if inst:IsA("BasePart") and getAttr(inst,"Value")~=nil then
		result=getAttr(inst,"CrystalName")~=nil or inst.Name:find("Crystal",1,true)~=nil
	end
	crystalFlags[inst]=result
	return result
end

-- [17] CONTAINERS
local containerList={}
local containerClock=0
local function rebuildContainers()
	table.clear(containerList); local seen={}
	local function push(c)
		if not c or seen[c] then return end
		seen[c]=true; containerList[#containerList+1]=c
	end
	push(S.Workspace)
	for _,name in ipairs(CFG.CONTAINER_NAMES) do push(S.Workspace:FindFirstChild(name)) end
	local things=S.Workspace:FindFirstChild("Things")
	if things then for _,name in ipairs(CFG.CONTAINER_NAMES) do push(things:FindFirstChild(name)) end end
end
local function eachContainer(fn)
	local now=os.clock()
	local stale=#containerList==0 or now-containerClock>=1
	if not stale then
		for _,c in ipairs(containerList) do
			if not c.Parent and c~=S.Workspace then stale=true; break end
		end
	end
	if stale then containerClock=now; rebuildContainers() end
	for _,c in ipairs(containerList) do fn(c) end
end

-- [18] ESP HELPERS + CRYSTAL TRACKING
local function newLabel(name,parent,order,total,color,rich,maxText)
	local label=Instance.new("TextLabel")
	label.Name=name; label.BackgroundTransparency=1; label.BorderSizePixel=0
	label.Size=UDim2.new(1,0,1/total,0); label.Position=UDim2.new(0,0,order/total,0)
	label.Font=CFG.ESP.font; label.TextScaled=true; label.TextTransparency=0
	label.TextStrokeTransparency=0; label.TextStrokeColor3=CFG.COLORS.stroke
	label.TextColor3=color; label.RichText=rich==true; label.Text=""; label.Parent=parent
	local constraint=Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize=maxText; constraint.Parent=label
	return label, constraint
end
local function crystalGuiSize()  return UDim2.fromOffset(CFG.ESP.width*espScale, CFG.ESP.height*espScale) end
local function crystalTextSize() return math.max(6,math.floor(CFG.ESP.text*espScale+0.5)) end
local function playerGuiSize()   return UDim2.fromOffset(CFG.PLAYER.width*playerScale, CFG.PLAYER.height*playerScale) end
local function playerTextSize()  return math.max(6,math.floor(CFG.PLAYER.text*playerScale+0.5)) end
local function createEntry(inst)
	local bb=Instance.new("BillboardGui")
	bb.Name="UniverseEsp"; bb.Adornee=inst; bb.AlwaysOnTop=true
	bb.ResetOnSpawn=false; bb.LightInfluence=0
	bb.Size=crystalGuiSize(); bb.StudsOffsetWorldSpace=CFG.ESP.offset
	bb.MaxDistance=math.huge; bb.Parent=EspHolder
	local ts=crystalTextSize()
	local rarity,rc=newLabel("Rarity",bb,0,3,CFG.COLORS.default,false,ts)
	local info,ic  =newLabel("Info",  bb,1,3,CFG.COLORS.money,  false,ts)
	local extra,ec =newLabel("Extra", bb,2,3,CFG.COLORS.extra,  true, ts)
	return {gui=bb,rarity=rarity,info=info,extra=extra,constraints={rc,ic,ec},signature=false,luckText="+0%",distanceText=false}
end
local function destroyEntry(inst,entry)
	entry=entry or Cache.espCache[inst]; if not entry then return end
	if entry.gui then entry.gui:Destroy() end
	Cache.espCache[inst]=nil; DHubState.espCount=DHubState.espCount-1; Runtime.statsDirty=true
end
local function applyEspScale()
	local size=crystalGuiSize(); local ts=crystalTextSize()
	for _,e in pairs(Cache.espCache) do
		if e.gui then e.gui.Size=size end
		for _,c in ipairs(e.constraints) do c.MaxTextSize=ts end
	end
end
local function applyPlayerScale()
	local size=playerGuiSize(); local ts=playerTextSize()
	for _,e in pairs(Cache.playerCache) do
		if e.gui then e.gui.Size=size end
		for _,c in ipairs(e.constraints) do c.MaxTextSize=ts end
	end
end
local function applyExtra(entry,distanceText)
	entry.distanceText=distanceText
	entry.extra.Text=string.format(
		'<font color="#%s">%s</font>  \u{2022}  <font color="#%s">%s</font>',
		CFG.COLORS.hexDistance,distanceText,CFG.COLORS.hexLuck,entry.luckText)
end
local function buildTitle(inst)
	local rarity=crystalRarity(inst); local name=crystalName(inst)
	local mutation=getAttr(inst,"Mutation")
	if type(mutation)=="string" and mutation~="" then
		return string.format("[%s] %s (%s)",rarity,name,mutation)
	end
	return string.format("[%s] %s",rarity,name)
end
local function applyDetails(inst,entry,origin)
	local luckOk,luck=pcall(crystalLuck,inst)
	entry.luckText=formatLuck(luckOk and luck or 0)
	entry.rarity.Text=buildTitle(inst); entry.rarity.TextColor3=crystalColor(inst)
	entry.info.Text=string.format("%s  \u{2022}  %s",
		formatShort(crystalValue(inst),"$"),formatWeight(crystalWeight(inst)))
	applyExtra(entry,origin and formatDistance((inst.Position-origin).Magnitude) or "--")
end
local function crystalSignature(inst)
	return table.concat({
		tostring(getAttr(inst,"Tier")),tostring(getAttr(inst,"TierName")),
		tostring(getAttr(inst,"CrystalName")),tostring(getAttr(inst,"Value")),
		tostring(getAttr(inst,"WeightKg")),tostring(getAttr(inst,"Mutation")),
		tostring(getAttr(inst,"ExtraMutations")),tostring(luckLabelText(inst)),
	},"|")
end
local function inventoryCrystalKey(tool)
	if not tool or not tool:IsA("Tool") then return nil end
	local handle=tool:FindFirstChild("Handle")
	local billboard=handle and handle:FindFirstChild("CrystalToolBillboard")
	local luckLabel=billboard and billboard:FindFirstChild("LuckBoost")
	local isCrystalTool=(getAttr(tool,"Tier")~=nil or getAttr(tool,"CrystalName")~=nil or (luckLabel and luckLabel:IsA("TextLabel")))
	if not isCrystalTool then return nil end
	local luckText=luckLabel and luckLabel:IsA("TextLabel") and luckLabel.Text or ""
	return table.concat({
		tostring(getAttr(tool,"Tier")),tostring(getAttr(tool,"TierName")),
		tostring(getAttr(tool,"CrystalName") or tool.Name),tostring(getAttr(tool,"Value")),
		tostring(getAttr(tool,"WeightKg")),tostring(getAttr(tool,"Mutation")),
		tostring(getAttr(tool,"ExtraMutations")),tostring(luckText),
	},"|")
end
local function inventoryCrystalLuckPercent(tool)
	local handle=tool and tool:FindFirstChild("Handle")
	local billboard=handle and handle:FindFirstChild("CrystalToolBillboard")
	local label=billboard and billboard:FindFirstChild("LuckBoost")
	if label and label:IsA("TextLabel") then
		local pct=tonumber(tostring(label.Text):match("([%d%.]+)%s*%%"))
		if pct then return pct end
	end
	return (tonumber(crystalLuck(tool)) or 0)*100
end
local function inventoryCrystalAllowed(tool)
	if not tool or not tool:IsA("Tool") then return false end
	local rarity=crystalRarity(tool)
	if next(rarityPickupFilter)~=nil and not rarityPickupFilter[rarity] then return false end
	if boulderMinLuck>0 and inventoryCrystalLuckPercent(tool)+1e-6<boulderMinLuck then return false end
	return inventoryCrystalKey(tool)~=nil
end
local function inventoryCrystalSnapshot()
	local counts={}
	local function scan(container)
		if not container then return end
		for _,child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") then
				local key=inventoryCrystalKey(child)
				if key then counts[key]=(counts[key] or 0)+1 end
			end
		end
	end
	scan(LocalPlayer:FindFirstChildOfClass("Backpack")); scan(LocalPlayer.Character)
	return counts
end
local function inventoryHasNewEligibleCrystal(before)
	before=before or {}
	local current={}
	local function scan(container)
		if not container then return end
		for _,child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and inventoryCrystalAllowed(child) then
				local key=inventoryCrystalKey(child)
				if key then current[key]=(current[key] or 0)+1 end
			end
		end
	end
	scan(LocalPlayer:FindFirstChildOfClass("Backpack")); scan(LocalPlayer.Character)
	for key,count in pairs(current) do
		if count>(before[key] or 0) then return true end
	end
	return false
end
local function markDirty(inst) Cache.dirty[inst]=true end
-- Local-only crystal visibility optimization.
-- Low-value crystals are hidden on this client while FPS Boost is active.
local crystalHideState=setmetatable({}, {__mode="k"})
local function crystalHidePart(inst, hidden)
	if not inst or not inst:IsA("BasePart") then return end
	local state=crystalHideState[inst]
	if hidden then
		if not state then
			state={base=inst.LocalTransparencyModifier, descendants={}}
			crystalHideState[inst]=state
			pcall(function() inst.LocalTransparencyModifier=1 end)
			-- Descendants are traversed only once when the crystal becomes hidden.
			-- The old code repeated GetDescendants() every sync, which caused
			-- unnecessary CPU spikes when many crystals were present.
			for _,obj in ipairs(inst:GetDescendants()) do
				if obj:IsA("BasePart") then
					state.descendants[obj]=obj.LocalTransparencyModifier
					pcall(function() obj.LocalTransparencyModifier=1 end)
				elseif obj:IsA("BillboardGui") or obj:IsA("SurfaceGui") then
					state.descendants[obj]=obj.Enabled
					pcall(function() obj.Enabled=false end)
				end
			end
		else
			-- Already hidden: do not traverse the whole model again.
			pcall(function() inst.LocalTransparencyModifier=1 end)
		end
	elseif state then
		pcall(function() inst.LocalTransparencyModifier=state.base or 0 end)
		for obj,oldValue in pairs(state.descendants) do
			if obj and obj.Parent then
				if obj:IsA("BasePart") then
					pcall(function() obj.LocalTransparencyModifier=oldValue or 0 end)
				elseif obj:IsA("BillboardGui") or obj:IsA("SurfaceGui") then
					pcall(function() obj.Enabled=oldValue end)
				end
			end
		end
		crystalHideState[inst]=nil
	end
end
local function shouldHideCrystal(inst)
	if not fpsBoostActive or not DHubState.valueFilter then return false end
	return crystalValue(inst) < minValue
end
local function refreshCrystalVisibility(inst)
	if inst then
		crystalHidePart(inst, shouldHideCrystal(inst))
		return
	end
	for crystal in pairs(Cache.registry) do
		crystalHidePart(crystal, shouldHideCrystal(crystal))
	end
end
local function untrackCrystal(inst)
	local conns=Cache.registry[inst]; if not conns then return end
	crystalHidePart(inst, false)
	for _,c in ipairs(conns) do c:Disconnect() end
	Cache.registry[inst]=nil; DHubState.registryCount=DHubState.registryCount-1
	Cache.dirty[inst]=nil; Cache.candidates[inst]=nil; Runtime.statsDirty=true
	destroyEntry(inst)
end
local function trackCrystal(inst)
	if Cache.registry[inst] then return end
	local conns={}; Cache.registry[inst]=conns; DHubState.registryCount=DHubState.registryCount+1; Runtime.statsDirty=true
	local ok=pcall(function()
		conns[#conns+1]=inst.Destroying:Connect(function() untrackCrystal(inst) end)
		conns[#conns+1]=inst.AncestryChanged:Connect(function()
			if not inst:IsDescendantOf(S.Workspace) then untrackCrystal(inst) end
		end)
		for _,name in ipairs(CFG.WATCHED_ATTRIBUTES) do
			conns[#conns+1]=inst:GetAttributeChangedSignal(name):Connect(function() markDirty(inst) end)
		end
		local label=luckLabel(inst)
		if label then
			conns[#conns+1]=label:GetPropertyChangedSignal("Text"):Connect(function() markDirty(inst) end)
		end
	end)
	if not ok then untrackCrystal(inst); return end
	markDirty(inst)
end
local function syncCrystal(inst)
	Cache.dirty[inst]=nil
	if not Cache.registry[inst] then return end
	if not inst.Parent then untrackCrystal(inst); return end
	-- Hide low-value dropped crystals only while FPS Boost is active.
	-- The object is never destroyed, so farming/pickup logic remains intact.
	crystalHidePart(inst, shouldHideCrystal(inst))
	local entry=Cache.espCache[inst]
	local hidden=not espActive or getAttr(inst,"Collected")==true
	if not hidden then
		if next(crystalEspFilter)~=nil then
			local cname=crystalName(inst)
			if not crystalEspFilter[cname] then hidden=true end
		end
		if not hidden and not meetsFilter(inst) then hidden=true end
	end
	if hidden then if entry then destroyEntry(inst,entry) end; return end
	if not entry then
		local built,result=pcall(createEntry,inst)
		if not built then reportError("billboard",result); return end
		entry=result; Cache.espCache[inst]=entry; DHubState.espCount=DHubState.espCount+1; Runtime.statsDirty=true
	end
	local sig=crystalSignature(inst)
	if sig==entry.signature then return end
	local root=getRoot()
	local ok,err=pcall(applyDetails,inst,entry,root and root.Position or nil)
	if ok then entry.signature=sig else reportError("details",err) end
end
local sweepSeen={}
local function sweep()
	local seen=sweepSeen; table.clear(seen)
	eachContainer(function(c)
		for _,child in ipairs(c:GetChildren()) do
			if not seen[child] and isCrystal(child) then
				seen[child]=true
				if not Cache.registry[child] then trackCrystal(child) end
			end
		end
	end)
	local stale
	for inst in pairs(Cache.registry) do
		if not seen[inst] then stale=stale or {}; stale[#stale+1]=inst end
	end
	if stale then for _,inst in ipairs(stale) do untrackCrystal(inst) end end
end
local lastDistanceOrigin
local function updateDistances()
	local root=getRoot(); if not root then return end
	local origin=root.Position
	if lastDistanceOrigin and (origin-lastDistanceOrigin).Magnitude<1 then return end
	lastDistanceOrigin=origin
	for inst,entry in pairs(Cache.espCache) do
		if inst.Parent then
			local text=formatDistance((inst.Position-origin).Magnitude)
			if text~=entry.distanceText then applyExtra(entry,text) end
		end
	end
end
local function clearEsp()
	for inst,entry in pairs(Cache.espCache) do destroyEntry(inst,entry) end
	Cache.espCache={}; DHubState.espCount=0; Runtime.statsDirty=true
end
local function clearRegistry()
	local all; for inst in pairs(Cache.registry) do all=all or {}; all[#all+1]=inst end
	if all then for _,inst in ipairs(all) do untrackCrystal(inst) end end
	clearEsp(); Cache.registry={}; Cache.candidates={}; Cache.dirty={}; DHubState.registryCount=0; Runtime.statsDirty=true
end
local function requestRefresh()
	for inst in pairs(Cache.registry) do Cache.dirty[inst]=true end
	Runtime.sweepAccumulator=math.huge
end
local function onContainerChild(child)
	if looksLikeCrystal(child) then Cache.candidates[child]=os.clock()+CFG.ESP.ttl end
end
local function watchContainers()
	for c,conn in pairs(Cache.containerConns) do
		if not c:IsDescendantOf(game) then conn:Disconnect(); Cache.containerConns[c]=nil end
	end
	eachContainer(function(c)
		if Cache.containerConns[c] then return end
		Cache.containerConns[c]=c.ChildAdded:Connect(onContainerChild)
	end)
end
local function unwatchContainers()
	for c,conn in pairs(Cache.containerConns) do conn:Disconnect(); Cache.containerConns[c]=nil end
end
local function updateTracking()
	if espActive then Runtime.sweepAccumulator=math.huge; watchContainers(); requestRefresh()
	else unwatchContainers(); clearRegistry() end
end
local function getTrackedCrystalNames()
	local names={}; local seen={}
	local function addName(name)
		if type(name)~="string" then return end
		name=name:gsub("^%s+",""):gsub("%s+$","")
		if name=="" or seen[name] then return end
		seen[name]=true; names[#names+1]=name
	end
	local function addInst(inst)
		if not inst then return end
		local attr=getAttr(inst,"CrystalName")
		if type(attr)=="string" and attr~="" then
			addName(attr)
		elseif inst.Name and inst.Name:find("Crystal",1,true) then
			-- Only use names from explicit crystal data folders for directory
			-- discovery; do not treat arbitrary Workspace objects as a directory.
			addName(inst.Name:gsub("%s*Crystal$",""))
		end
	end

	-- Prefer the game's replicated/static data when it exists.
	local rs=S.ReplicatedStorage
	local directoryNames={"Crystals","CrystalTools","CrystalDirectory","CrystalData","CrystalTypes"}
	for _,folderName in ipairs(directoryNames) do
		local folder=rs:FindFirstChild(folderName,true)
		if folder then
			for _,child in ipairs(folder:GetChildren()) do
				local attr=getAttr(child,"CrystalName")
				if type(attr)=="string" and attr~="" then addName(attr)
				elseif child:IsA("Folder") or child:IsA("Model") or child:IsA("Configuration") then
					addName(child.Name)
				elseif child.Name and child.Name~="" then
					addName(child.Name)
				end
			end
		end
	end
	for _,inst in ipairs(rs:GetDescendants()) do
		local attr=getAttr(inst,"CrystalName")
		if type(attr)=="string" and attr~="" then addName(attr) end
	end

	-- Live-world fallback/merge so newly introduced crystal types also appear.
	for inst in pairs(Cache.registry) do
		if inst and inst.Parent and isCrystal(inst) then addName(crystalName(inst)) end
	end
	eachContainer(function(c)
		for _,inst in ipairs(c:GetDescendants()) do
			if isCrystal(inst) then addName(crystalName(inst)) end
		end
	end)
	table.sort(names,function(a,b) return string.lower(a)<string.lower(b) end)
	return names
end

local function getTrackedRuneNames()
	-- The game's authoritative rune directory is:
	-- ReplicatedStorage > Assets > RuneTools
	-- Do NOT build this list from DroppedRunes/Workspace because that only
	-- contains runes that are currently spawned in the world.
	local names = {}
	local seen = {}

	local function addName(name)
		if type(name) ~= "string" then return end
		name = name:gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" or seen[name] then return end
		seen[name] = true
		names[#names + 1] = name
	end

	local assets = S.ReplicatedStorage:FindFirstChild("Assets")
	local runeTools = assets and assets:FindFirstChild("RuneTools")
	if runeTools then
		for _, rune in ipairs(runeTools:GetChildren()) do
			addName(rune.Name)
		end
	end

	-- Fallback only if the directory is temporarily unavailable.
	if #names == 0 then
		local rs = S.ReplicatedStorage
		for _, inst in ipairs(rs:GetDescendants()) do
			local id = getAttr(inst, "RuneId") or getAttr(inst, "RuneName")
			if type(id) == "string" and id ~= "" then
				addName(id)
			end
		end
	end

	table.sort(names, function(a, b)
		return string.lower(a) < string.lower(b)
	end)
	return names
end

-- [19] PLAYER ESP
local function destroyPlayerEntry(player)
	local entry=Cache.playerCache[player]; if not entry then return end
	if entry.gui then entry.gui:Destroy() end
	Cache.playerCache[player]=nil
end
local function createPlayerEntry(player)
	local bb=Instance.new("BillboardGui")
	bb.Name="UniversePlayerEsp"; bb.AlwaysOnTop=true; bb.ResetOnSpawn=false
	bb.LightInfluence=0; bb.Size=playerGuiSize()
	bb.StudsOffsetWorldSpace=CFG.PLAYER.offset; bb.MaxDistance=math.huge; bb.Parent=EspHolder
	local ts=playerTextSize()
	local nameLabel,nc=newLabel("Name",    bb,0,2,CFG.COLORS.player,false,ts)
	local distLabel,dc=newLabel("Distance",bb,1,2,CFG.COLORS.extra, false,ts)
	nameLabel.Text=player.DisplayName
	return {gui=bb,name=nameLabel,distance=distLabel,constraints={nc,dc},nameText=player.DisplayName,distanceText=false}
end
local function clearPlayerEsp()
	for player in pairs(Cache.playerCache) do destroyPlayerEntry(player) end
	Cache.playerCache={}
end
local function updatePlayerEsp()
	if not playerEspActive then return end
	local root=getRoot(); local origin=root and root.Position or nil
	for _,player in ipairs(S.Players:GetPlayers()) do
		if player~=LocalPlayer then
			local char=player.Character
			local target=char and char:FindFirstChild("HumanoidRootPart")
			if target then
				local entry=Cache.playerCache[player]
				if not entry then
					local built,result=pcall(createPlayerEntry,player)
					if built then entry=result; Cache.playerCache[player]=entry else reportError("player",result) end
				end
				if entry then
					if entry.gui.Adornee~=target then entry.gui.Adornee=target end
					if entry.nameText~=player.DisplayName then
						entry.nameText=player.DisplayName; entry.name.Text=player.DisplayName
					end
					local text=origin and formatDistance((target.Position-origin).Magnitude) or "--"
					if text~=entry.distanceText then entry.distanceText=text; entry.distance.Text=text end
				end
			else
				destroyPlayerEntry(player)
			end
		end
	end
	local gone
	for player in pairs(Cache.playerCache) do
		if player==LocalPlayer or not player.Parent then gone=gone or {}; gone[#gone+1]=player end
	end
	if gone then for _,p in ipairs(gone) do destroyPlayerEntry(p) end end
end

-- [19.5] VEIN ESP MODULE — Optimized Terrain Scanner
local VeinsModule = {}
local veinConn
do
	local function install()
		local VEIN_MATS = {
			[Enum.Material.Pavement]    = {name="Gunpowder Stone", bomb="Classic Bomb",   color=Color3.fromRGB(150,150,150)},
			[Enum.Material.Salt]        = {name="Skyglass",         bomb="Wind Bomb",      color=Color3.fromRGB(200,220,255)},
			[Enum.Material.Ice]         = {name="Cryostone",        bomb="Ice Bomb",       color=Color3.fromRGB(100,200,255)},
			[Enum.Material.LeafyGrass]  = {name="Cinderforge Plate",bomb="Fire Bomb",      color=Color3.fromRGB(255,100,50)},
			[Enum.Material.Asphalt]     = {name="Stormsteel",       bomb="Thunder Bomb",   color=Color3.fromRGB(255,255,0)},
			[Enum.Material.Concrete]    = {name="Venomite",         bomb="Poison Bomb",    color=Color3.fromRGB(150,255,100)},
			[Enum.Material.Cobblestone] = {name="Chronoshard",      bomb="Time Bomb",      color=Color3.fromRGB(200,150,255)},
			[Enum.Material.Brick]       = {name="Dreadstone",       bomb="Agony Bomb",     color=Color3.fromRGB(255,50,50)},
		}

				local ALL_VEIN_NAMES = {}
		do
			local seen = {}
			for _,info in pairs(VEIN_MATS) do
				if not seen[info.name] then
					seen[info.name] = true
					ALL_VEIN_NAMES[#ALL_VEIN_NAMES+1] = info.name
				end
			end
			table.sort(ALL_VEIN_NAMES)
		end

		-- IMPORTANT:
		-- The old scanner read a 400x400x400 stud cube every 2 seconds.
		-- At Terrain resolution 4 that is roughly 100^3 = 1,000,000 voxels.
		-- The new scanner uses a smaller horizontal/vertical window and a
		-- spatial hash, then limits the number of rendered ESP cards.
		local SCAN_RADIUS_XZ = 90
		local SCAN_RADIUS_Y  = 56
		local CLUSTER_SIZE   = 16
		local VEIN_STEP      = 3.5
		local VEIN_TTL       = 7.0
		local MAX_CARDS      = 40
		local OCCUPANCY_MIN  = 0.35
		local VEIN_OFFSET    = Vector3.new(0, 5, 0)

		local veinClusters = {}
		local veinClock = VEIN_STEP
		local enabled = false
		local scanRunning = false

		local function textSize()
			return math.max(6, math.floor(CFG.ESP.text * espScale + 0.5))
		end

		local function createCard(anchorPart, info)
			local bb = Instance.new("BillboardGui")
			bb.Name = "UniverseVeinEsp"
			bb.Adornee = anchorPart
			bb.AlwaysOnTop = true
			bb.ResetOnSpawn = false
			bb.LightInfluence = 0
			bb.MaxDistance = 1000
			bb.Size = UDim2.fromOffset(220 * espScale, 44 * espScale)
			bb.StudsOffsetWorldSpace = VEIN_OFFSET
			bb.Parent = EspHolder

			local sz = textSize()
			local nameLabel,nc = newLabel("Name",bb,0,2,info.color,false,sz)
			nameLabel.Text = "[VEIN] " .. info.name
			local distLabel,dc = newLabel("Dist",bb,1,2,CFG.COLORS.extra,false,sz)
			distLabel.Text = info.bomb

			return {gui=bb,nameLabel=nameLabel,distLabel=distLabel,constraints={nc,dc}}
		end

		local function scaleCard(entry)
			if not entry or not entry.gui then return end
			entry.gui.Size = UDim2.fromOffset(220 * espScale, 44 * espScale)
			local sz = textSize()
			for _,c in ipairs(entry.constraints) do c.MaxTextSize = sz end
		end

		local function makeAnchor(position)
			local part = Instance.new("Part")
			part.Name = "UniverseVeinAnchor"
			part.Size = Vector3.new(0.5,0.5,0.5)
			part.CFrame = CFrame.new(position)
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
			part.Transparency = 1
			part.Parent = EspHolder
			return part
		end

		local function destroyCard(cluster)
			if cluster.card then
				if cluster.card.gui then cluster.card.gui:Destroy() end
				cluster.card = nil
			end
			if cluster.anchor then
				cluster.anchor:Destroy()
				cluster.anchor = nil
			end
		end

		local function clearAll()
			for _,cluster in pairs(veinClusters) do destroyCard(cluster) end
			table.clear(veinClusters)
		end

		local function passesFilter(info)
			if not next(veinEspFilter) then return true end
			return veinEspFilter[info.name] == true
		end

		local function cellCoord(v)
			return math.floor(v / CLUSTER_SIZE)
		end

		local function clusterKey(mat,x,y,z)
			return tostring(mat) .. ":" .. x .. ":" .. y .. ":" .. z
		end


		local function scanTerrain()
			if scanRunning then return end
			scanRunning = true
			local root = getRoot()
			if not root then scanRunning = false; return end
			if not root then return end
			local origin = root.Position

			local minPos = origin - Vector3.new(SCAN_RADIUS_XZ,SCAN_RADIUS_Y,SCAN_RADIUS_XZ)
			local maxPos = origin + Vector3.new(SCAN_RADIUS_XZ,SCAN_RADIUS_Y,SCAN_RADIUS_XZ)
			local ok,region = pcall(function()
				return Region3.new(minPos,maxPos):ExpandToGrid(4)
			end)
			if not ok or not region then scanRunning = false; return end

			local readOk,mats,occs = pcall(function()
				return S.Workspace.Terrain:ReadVoxels(region,4)
			end)
			if not readOk or not mats or not occs then scanRunning = false; return end

			local sz = mats.Size
			local regionMin = region.CFrame.Position - region.Size * 0.5
			local now = os.clock()
			local seen = {}

			-- O(1)-ish clustering: the old code compared every found voxel
			-- against every existing cluster. This version uses a grid key.
			for x=1,sz.X do
				for y=1,sz.Y do
					for z=1,sz.Z do
						local occ = occs[x][y][z]
						if occ and occ >= OCCUPANCY_MIN then
							local mat = mats[x][y][z]
							local info = VEIN_MATS[mat]
							if info and passesFilter(info) then
								local pos = regionMin + Vector3.new((x-0.5)*4,(y-0.5)*4,(z-0.5)*4)
								local cx,cy,cz = cellCoord(pos.X),cellCoord(pos.Y),cellCoord(pos.Z)
								local id = clusterKey(mat,cx,cy,cz)
								local cluster = seen[id]
								if not cluster then
									cluster = veinClusters[id]
									if not cluster then
										cluster = {material=mat,position=pos,lastSeen=now,card=nil,anchor=nil,count=0}
										veinClusters[id] = cluster
									else
										cluster.position = cluster.position:Lerp(pos,1/math.max(1,cluster.count+1))
									end
								end
								cluster.count = cluster.count + 1
								cluster.lastSeen = now
								seen[id] = cluster
							end
						end
					end
				end
			end

			-- Remove old clusters without touching live GUI objects every scan.
			for id,cluster in pairs(veinClusters) do
				if not seen[id] and now-cluster.lastSeen > VEIN_TTL then
					destroyCard(cluster)
					veinClusters[id] = nil
				end
			end

			-- Build a small candidate list and render only the nearest cards.
			local candidates = {}
			for id,cluster in pairs(veinClusters) do
				if seen[id] then
					local info = VEIN_MATS[cluster.material]
					if info and passesFilter(info) then
						candidates[#candidates+1] = {id=id,cluster=cluster,dist=(cluster.position-origin).Magnitude}
					end
				end
			end
			table.sort(candidates,function(a,b) return a.dist < b.dist end)

			local keep = {}
			for i=1,math.min(MAX_CARDS,#candidates) do
				local item = candidates[i]
				keep[item.id] = true
				local cluster = item.cluster
				local info = VEIN_MATS[cluster.material]
				if not cluster.anchor then cluster.anchor = makeAnchor(cluster.position) end
				cluster.anchor.CFrame = CFrame.new(cluster.position)
				if not cluster.card then cluster.card = createCard(cluster.anchor,info) end
				scaleCard(cluster.card)
				local distText = string.format("Bomb: %s  •  %dm",info.bomb,math.floor(item.dist))
				if cluster.card.distLabel.Text ~= distText then cluster.card.distLabel.Text = distText end
			end

			-- Anything outside the display budget keeps its data cache but has
			-- no BillboardGui/Part, which is the key GPU/UI optimization.
			for id,cluster in pairs(veinClusters) do
				if not keep[id] then destroyCard(cluster) end
			end
			scanRunning = false
		end

		function VeinsModule.setVeinEsp(value)
			enabled = value == true
			if not enabled then clearAll() end
		end

		function VeinsModule.getTrackedVeinNames()
			return ALL_VEIN_NAMES
		end

		function VeinsModule.applyScale()
			for _,cluster in pairs(veinClusters) do
				if cluster.card then scaleCard(cluster.card) end
			end
		end

		-- Driven by the single global scheduler. Keeping ESP scanners off their
		-- own Heartbeat connection prevents connection accumulation on reruns.
		function VeinsModule.tick(dt)
			if not enabled then return end
			veinClock = veinClock + dt
			local veinInterval = fpsBoostActive and math.max(VEIN_STEP,5.0) or VEIN_STEP
			if veinClock >= veinInterval then
				veinClock = 0
				task.spawn(function()
					pcall(scanTerrain)
				end)
			end
		end
	end
	install()
end

-- [19.6] PRISMARITE ESP MODULE — Terrain WoodPlanks Scanner
-- Standalone from Vein ESP. Prismarite is represented by Terrain Material WoodPlanks.
local PrismariteModule = {}
do
	local enabled = false
	local scannerEnabled = false
	local clock = 1.5
	local STEP = 1.5
	-- Keep Prismarite scans small. A 600x240x600 stud ReadVoxels region
	-- creates ~1.35M voxels per pass and causes large frame stalls.
	local SCAN_RADIUS_XZ = 96
	local SCAN_RADIUS_Y = 64
	local FARM_SCAN_RADIUS_XZ = 96
	local FARM_SCAN_RADIUS_Y = 96
	local FARM_SCAN_INTERVAL = 0.60
	local CLUSTER_SIZE = 16
	local OCCUPANCY_MIN = 0.35
	local TTL = 7.0
	local MAX_CARDS = 120
	local OFFSET = Vector3.new(0,5,0)
	local clusters = {}
	local scanning = false
	local scanSerial = 0

	local INFO = {
		name = "Prismarite",
		color = Color3.fromRGB(255,120,255),
	}

	local function textSize()
		return math.max(6, math.floor(CFG.ESP.text * espScale + 0.5))
	end

	local function makeAnchor(position)
		local part = Instance.new("Part")
		part.Name = "UniversePrismariteAnchor"
		part.Size = Vector3.new(0.5,0.5,0.5)
		part.CFrame = CFrame.new(position)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Transparency = 1
		part.Parent = EspHolder
		return part
	end

	local function createCard(anchorPart)
		local bb = Instance.new("BillboardGui")
		bb.Name = "UniversePrismariteEsp"
		bb.Adornee = anchorPart
		bb.AlwaysOnTop = true
		bb.ResetOnSpawn = false
		bb.LightInfluence = 0
		bb.MaxDistance = SCAN_RADIUS_XZ + 24
		bb.Size = UDim2.fromOffset(220 * espScale, 44 * espScale)
		bb.StudsOffsetWorldSpace = OFFSET
		bb.Parent = EspHolder

		local sz = textSize()
		local nameLabel,nc = newLabel("Name",bb,0,2,INFO.color,false,sz)
		nameLabel.Text = "[PRISMARITE] Prismarite"
		local distLabel,dc = newLabel("Dist",bb,1,2,CFG.COLORS.extra,false,sz)

		return {gui=bb,nameLabel=nameLabel,distLabel=distLabel,constraints={nc,dc}}
	end

	local function destroyCard(cluster)
		if cluster.card then
			if cluster.card.gui then cluster.card.gui:Destroy() end
			cluster.card = nil
		end
		if cluster.anchor then
			cluster.anchor:Destroy()
			cluster.anchor = nil
		end
	end

	local function clear()
		for id,cluster in pairs(clusters) do
			destroyCard(cluster)
			clusters[id] = nil
		end
	end

	local function cellCoord(v)
		return math.floor(v / CLUSTER_SIZE)
	end

	local function cellKey(x,y,z)
		return tostring(x)..":"..tostring(y)..":"..tostring(z)
	end

	local function applyScaleCard(entry)
		if not entry or not entry.gui then return end
		entry.gui.Size = UDim2.fromOffset(220 * espScale,44 * espScale)
		local sz = textSize()
		for _,c in ipairs(entry.constraints) do c.MaxTextSize = sz end
	end

	local function scan()
		if scanning then return end
		scanning = true

		local root = getRoot()
		if not root then scanning=false; return end

		local origin = root.Position
		-- Farm scans a tighter hidden bubble while moving. At 350 studs/s and
		-- 0.45s cadence, an 80-stud radius almost exactly overlaps the flight
		-- path, while keeping each ReadVoxels pass to about 38k voxels.
		local radiusXZ = Runtime.PrismariteFarmActive==true and FARM_SCAN_RADIUS_XZ or SCAN_RADIUS_XZ
		local radiusY = Runtime.PrismariteFarmActive==true and FARM_SCAN_RADIUS_Y or SCAN_RADIUS_Y
		local minPos = origin - Vector3.new(radiusXZ,radiusY,radiusXZ)
		local maxPos = origin + Vector3.new(radiusXZ,radiusY,radiusXZ)
		local ok,region = pcall(function()
			return Region3.new(minPos,maxPos):ExpandToGrid(4)
		end)
		if not ok or not region then scanning=false; return end

		local readOk,mats,occs = pcall(function()
			return S.Workspace.Terrain:ReadVoxels(region,4)
		end)
		if not readOk or not mats or not occs then scanning=false; return end

		local size = mats.Size
		local regionMin = region.CFrame.Position - region.Size * 0.5
		local now = os.clock()
		local seen = {}

		for x=1,size.X do
			for y=1,size.Y do
				for z=1,size.Z do
					local occ = occs[x][y][z]
					if occ and occ >= OCCUPANCY_MIN and mats[x][y][z] == Enum.Material.WoodPlanks then
						local pos = regionMin + Vector3.new((x-0.5)*4,(y-0.5)*4,(z-0.5)*4)
						local cx,cy,cz = cellCoord(pos.X),cellCoord(pos.Y),cellCoord(pos.Z)
						local id = cellKey(cx,cy,cz)
						local cluster = clusters[id]
						if not cluster then
							cluster = {position=pos,lastSeen=now,count=0,card=nil,anchor=nil}
							clusters[id] = cluster
						end

						-- Rebuild this cluster from the CURRENT terrain scan.
						if not seen[id] then
							cluster.position = pos
							cluster.count = 0
						end
						cluster.position = cluster.position:Lerp(pos,1/math.max(1,cluster.count+1))
						cluster.count = cluster.count + 1
						cluster.lastSeen = now
						seen[id] = true
					end
				end
			end
		end

		for id,cluster in pairs(clusters) do
			if not seen[id] then
				local p=cluster.position
				local insideScan = p and p.X >= minPos.X-8 and p.X <= maxPos.X+8
					and p.Y >= minPos.Y-8 and p.Y <= maxPos.Y+8
					and p.Z >= minPos.Z-8 and p.Z <= maxPos.Z+8

				if Runtime.PrismariteFarmActive==true and insideScan then
					-- Fresh farm scan says this old voxel cluster is gone.
					destroyCard(cluster)
					clusters[id] = nil
				elseif now-cluster.lastSeen > TTL then
					destroyCard(cluster)
					clusters[id] = nil
				end
			end
		end

		-- Scanner-only mode is intentionally invisible: keep the cache but do not
		-- create hundreds of Parts/BillboardGuis while Premium Farm is running.
		if enabled then
			local candidates={}
			for id,cluster in pairs(clusters) do
				if seen[id] then
					candidates[#candidates+1] = {id=id,cluster=cluster,dist=(cluster.position-origin).Magnitude}
				end
			end
			table.sort(candidates,function(a,b) return a.dist < b.dist end)

			local keep={}
			for i=1,math.min(MAX_CARDS,#candidates) do
				local item=candidates[i]
				keep[item.id]=true
				local cluster=item.cluster
				if not cluster.anchor then cluster.anchor=makeAnchor(cluster.position) end
				cluster.anchor.CFrame=CFrame.new(cluster.position)
				if not cluster.card then cluster.card=createCard(cluster.anchor) end
				applyScaleCard(cluster.card)
				cluster.card.distLabel.Text=string.format("D-Hub On Top  •  %dm",math.floor(item.dist))
			end

			for id,cluster in pairs(clusters) do
				if not keep[id] then destroyCard(cluster) end
			end
		else
			for _,cluster in pairs(clusters) do
				destroyCard(cluster)
			end
		end

		scanSerial = scanSerial + 1
		scanning=false
	end

	function PrismariteModule.getScanSerial()
		return scanSerial
	end

	function PrismariteModule.setActive(value)
		enabled = value == true
		if enabled then
			scannerEnabled = true
		else
			-- Do not kill the hidden scanner while Premium Farm is active.
			if Runtime.PrismariteFarmActive ~= true then
				scannerEnabled = false
				clear()
			end
		end
		clock = STEP
	end

	function PrismariteModule.setScannerActive(value)
		scannerEnabled = value == true
		if scannerEnabled then clock = FARM_SCAN_INTERVAL end
		if not scannerEnabled and not enabled then
			clear()
		end
		clock = 0
	end

	function PrismariteModule.isActive()
		return enabled == true
	end

	function PrismariteModule.isScannerActive()
		return scannerEnabled == true
	end

	function PrismariteModule.applyScale()
		for _,cluster in pairs(clusters) do
			if cluster.card then applyScaleCard(cluster.card) end
		end
	end

	-- Read-only target API for Premium Prismarite Farm.
	function PrismariteModule.getTargets(origin)
		local list={}
		local now=os.clock()
		local pos=origin or Vector3.zero
		for id,cluster in pairs(clusters) do
			if cluster.position and cluster.count and cluster.count>0 and now-cluster.lastSeen<=TTL then
				local dist=(cluster.position-pos).Magnitude
				if dist<=SCAN_RADIUS_XZ+30 then
					list[#list+1]={id=id,position=cluster.position,count=cluster.count,distance=dist,lastSeen=cluster.lastSeen}
				end
			end
		end
		table.sort(list,function(a,b) return a.distance<b.distance end)
		return list
	end

	function PrismariteModule.getAllTargets()
		local list={}
		local now=os.clock()
		for id,cluster in pairs(clusters) do
			if cluster.position and cluster.count and cluster.count>0 and now-cluster.lastSeen<=TTL then
				list[#list+1]={id=id,position=cluster.position,count=cluster.count,distance=0,lastSeen=cluster.lastSeen}
			end
		end
		table.sort(list,function(a,b) return a.lastSeen>b.lastSeen end)
		return list
	end

	function PrismariteModule.getAreaTargets(center,radius,maxAge)
		local list={}
		local now=os.clock()
		if typeof(center)~="Vector3" then return list end
		radius=tonumber(radius) or 56
		maxAge=tonumber(maxAge) or 1.1
		for id,cluster in pairs(clusters) do
			if cluster.position and cluster.count and cluster.count>0 and now-cluster.lastSeen<=maxAge then
				local distance=(cluster.position-center).Magnitude
				if distance<=radius then
					list[#list+1]={id=id,position=cluster.position,count=cluster.count,distance=distance,lastSeen=cluster.lastSeen}
				end
			end
		end
		table.sort(list,function(a,b)
			if a.distance==b.distance then return a.count>b.count end
			return a.distance<b.distance
		end)
		return list
	end

	function PrismariteModule.getNearest(origin,excludeId)
		local list=PrismariteModule.getTargets(origin)
		for _,entry in ipairs(list) do if entry.id~=excludeId then return entry end end
		return nil
	end

	function PrismariteModule.getStats(origin)
		local list=PrismariteModule.getTargets(origin)
		local nearest=list[1]
		return #list,nearest and nearest.distance or nil
	end

	PrismariteModule.clear=clear

	PrismariteModule.tick=function(dt)
		if not scannerEnabled then return end
		clock=clock+dt
		local interval
		if Runtime.PrismariteFarmActive==true then
			interval=FARM_SCAN_INTERVAL
		else
			interval=fpsBoostActive and math.max(STEP,2.5) or STEP
		end
		if clock>=interval then
			clock=0
			task.spawn(function() pcall(scan) end)
		end
	end

end
-- [20] TELEPORT
local streamMark=0; local streamSpot
local function requestStream(position)
	if typeof(position)~="Vector3" then return end
	local now=os.clock()
	if streamSpot and now-streamMark<0.3 and (streamSpot-position).Magnitude<32 then return end
	streamMark=now; streamSpot=position
	task.spawn(function() pcall(function() LocalPlayer:RequestStreamAroundAsync(position,1) end) end)
end
local function applyPivot(cframe)
	local char=LocalPlayer.Character; if not char then return false end
	requestStream(cframe.Position)
	local root=getRoot(); if not root then return false end
	local moved=pcall(function() char:PivotTo(cframe) end)
	if not moved then moved=pcall(function() root.CFrame=cframe end) end
	if not moved then return false end
	pcall(function()
		root.AssemblyLinearVelocity=Vector3.zero
		root.AssemblyAngularVelocity=Vector3.zero
	end)
	return true
end
local function findClearGoal(position,ignore)
	local params=OverlapParams.new()
	params.FilterType=Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances=ignore; params.MaxParts=1
	for _,offset in ipairs(CFG.TP.clear) do
		local candidate=position+offset
		local ok,hits=pcall(function() return S.Workspace:GetPartBoundsInRadius(candidate,2.5,params) end)
		if ok and #hits==0 then return candidate end
	end
	return position+CFG.TP.clear[#CFG.TP.clear]
end
local function finishTeleport()
	if not Runtime.tpState then return end
	local root=getRoot()
	if root then pcall(function()
		root.AssemblyLinearVelocity=Vector3.zero
		root.AssemblyAngularVelocity=Vector3.zero
	end) end
	local char=LocalPlayer.Character
	local h=char and char:FindFirstChildOfClass("Humanoid")
	if h then pcall(function()
		h.PlatformStand=false
		h:SetStateEnabled(Enum.HumanoidStateType.Freefall,true)
		h:SetStateEnabled(Enum.HumanoidStateType.FallingDown,true)
		h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,true)
		h:ChangeState(Enum.HumanoidStateType.GettingUp)
	end) end
	Runtime.tpState=nil
end
local function teleportTo(target)
	local position
	if typeof(target)=="Vector3" then position=target
	elseif typeof(target)=="Instance" and target.Parent then position=target.Position end
	if not position then return false end
	local char=LocalPlayer.Character; if not char then return false end
	local root=getRoot(); if not root then return false end
	finishTeleport()
	local h=char:FindFirstChildOfClass("Humanoid")
	if h then pcall(function()
		if h.SeatPart or h.Sit then h.Sit=false end
		h:SetStateEnabled(Enum.HumanoidStateType.FallingDown,false)
		h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,false)
	end) end
	local ignore={char}
	if typeof(target)=="Instance" then ignore[#ignore+1]=target end
	local goalFrame=CFrame.new(findClearGoal(position+CFG.TP.offset,ignore))
	if not applyPivot(goalFrame) then return false end
	Runtime.tpState={goal=goalFrame,holdUntil=os.clock()+CFG.TP.hold}
	return true
end

-- [21] PICKUP MECHANICS
local promptCache=setmetatable({},{__mode="k"})
local function crystalPrompt(inst)
	local cached=promptCache[inst]
	if cached and cached.Parent then return cached end
	local ok,prompt=pcall(inst.FindFirstChildOfClass,inst,"ProximityPrompt")
	if not (ok and prompt) then
		ok,prompt=pcall(inst.FindFirstChildWhichIsA,inst,"ProximityPrompt",true)
	end
	if ok and prompt then promptCache[inst]=prompt; return prompt end
	promptCache[inst]=nil; return nil
end
local function surfaceDistance(part,origin)
	local ok,distance=pcall(function()
		local point=part.CFrame:PointToObjectSpace(origin)
		local half=part.Size*0.5
		local clamped=Vector3.new(
			math.clamp(point.X,-half.X,half.X),
			math.clamp(point.Y,-half.Y,half.Y),
			math.clamp(point.Z,-half.Z,half.Z))
		return (point-clamped).Magnitude
	end)
	if ok and distance then return distance end
	return (part.Position-origin).Magnitude
end
local function firePrompt(prompt)
	if not Cache.promptRestores[prompt] then
		Cache.promptRestores[prompt]={
			hold=prompt.HoldDuration,sight=prompt.RequiresLineOfSight,
			enabled=prompt.Enabled,range=prompt.MaxActivationDistance,
		}
	end
	pcall(function()
		prompt.HoldDuration=0; prompt.RequiresLineOfSight=false
		prompt.Enabled=true; prompt.MaxActivationDistance=1000
	end)
	local fired=false
	if typeof(fireproximityprompt)=="function" then
		fired=pcall(fireproximityprompt,prompt,1)
		if not fired then fired=pcall(fireproximityprompt,prompt) end
	end
	if not fired then
		fired=pcall(function() prompt:InputHoldBegin(); prompt:InputHoldEnd() end)
	end
	schedule(CFG.PICK.restore,function()
		local saved=Cache.promptRestores[prompt]; if not saved then return end
		Cache.promptRestores[prompt]=nil
		if prompt.Parent then
			prompt.HoldDuration=saved.hold; prompt.RequiresLineOfSight=saved.sight
			prompt.Enabled=saved.enabled; prompt.MaxActivationDistance=saved.range
		end
	end)
	return fired
end
local pickupParams=OverlapParams.new()
pickupParams.FilterType=Enum.RaycastFilterType.Exclude
pcall(function() pickupParams.MaxParts=300; pickupParams.RespectCanCollide=false end)
local function pickupCandidates(free,origin,rangeOverride)
	local found=Cache.pickupFound; local seen=Cache.pickupSeen
	local scanRange=tonumber(rangeOverride) or CFG.PICK.range
	table.clear(found); table.clear(seen)
	local now=os.clock()
	local function consider(child)
		if not child or seen[child] then return end; seen[child]=true
		if not child.Parent or not isCrystal(child) or getAttr(child,"Collected")==true then return end
		local claim=Cache.claimed[child]
		if claim and now-claim<CFG.PICK.retry then return end
		local value=crystalValue(child)
		if not meetsPickupFilter(child,value) then return end
		local weight=crystalWeight(child)
		if weight>free then return end
		local dist=surfaceDistance(child,origin)
		if dist>scanRange then return end
		found[#found+1]={inst=child,prompt=crystalPrompt(child),value=value,weight=weight,distance=dist,tier=crystalTier(child)}
	end
	pickupParams.FilterDescendantsInstances={LocalPlayer.Character or LocalPlayer}
	local ok,hits=pcall(function() return S.Workspace:GetPartBoundsInRadius(origin,scanRange+CFG.PICK.pad,pickupParams) end)
	if ok and hits then for _,p in ipairs(hits) do consider(p) end end
	eachContainer(function(c)
		for _,child in ipairs(c:GetChildren()) do
			if child:IsA("BasePart") then consider(child)
			elseif child:IsA("Model") then for _,inner in ipairs(child:GetChildren()) do consider(inner) end end
		end
	end)
	for inst in pairs(Cache.registry) do consider(inst) end
	local useRarityPriority=(next(rarityPickupFilter)~=nil and next(rarityPickupFilter,next(rarityPickupFilter))~=nil)
	table.sort(found,function(a,b)
		if useRarityPriority and a.tier~=b.tier then return a.tier>b.tier end
		if a.value==b.value then return a.distance<b.distance end
		return a.value>b.value
	end)
	return found
end
local function grabCrystal(inst,prompt,forcePickup)
	local sent=false
	local hp=tonumber(getAttr(inst,"MinedHP"))
	if RMT.HoldComplete and (forcePickup or not hp or hp<=0) then
		sent=pcall(function() RMT.HoldComplete:FireServer(inst) end)
		if typeof(getnilinstances)=="function" then
			local ok,nilList=pcall(getnilinstances)
			if ok and nilList then
				for _,obj in ipairs(nilList) do
					if obj.Name==inst.Name and typeof(obj)=="Instance" then
						pcall(function() RMT.HoldComplete:FireServer(obj) end); break
					end
				end
			end
		end
	end
	-- Trigger extra client logic per request
	local pickupJuice = findRemote("CrystalPickupJuice")
	if pickupJuice and (forcePickup or not hp or hp<=0) then
		pcall(function() pickupJuice:FireServer(inst, true) end)
	end
	if not prompt then prompt=crystalPrompt(inst) end
	if prompt and prompt.Parent and firePrompt(prompt) then sent=true end
	if not sent and typeof(fireclickdetector)=="function" then
		local ok,det=pcall(inst.FindFirstChildWhichIsA,inst,"ClickDetector",true)
		if ok and det then sent=pcall(fireclickdetector,det,0) end
	end
	return sent
end
local function instantPromptPatch(prompt)
	if Cache.instantPatched[prompt] or Cache.promptRestores[prompt] then return end
	Cache.instantPatched[prompt]={hold=prompt.HoldDuration,sight=prompt.RequiresLineOfSight,enabled=prompt.Enabled}
	pcall(function() prompt.HoldDuration=0; prompt.RequiresLineOfSight=false; prompt.Enabled=true end)
end
local function restoreInstantPrompts()
	for prompt,saved in pairs(Cache.instantPatched) do
		if prompt.Parent then
			pcall(function()
				prompt.HoldDuration=saved.hold; prompt.RequiresLineOfSight=saved.sight; prompt.Enabled=saved.enabled
			end)
		end
	end
	table.clear(Cache.instantPatched)
end
local function nearbyCrystalParts(origin,radius)
	pickupParams.FilterDescendantsInstances={LocalPlayer.Character or LocalPlayer}
	local ok,hits=pcall(function() return S.Workspace:GetPartBoundsInRadius(origin,radius,pickupParams) end)
	return (ok and hits) and hits or nil
end
local function refreshInstantPrompts()
	local root=getRoot(); if not root then return end
	local stale
	for prompt in pairs(Cache.instantPatched) do
		if not prompt.Parent then stale=stale or {}; stale[#stale+1]=prompt end
	end
	if stale then for _,p in ipairs(stale) do Cache.instantPatched[p]=nil end end
	local hits=nearbyCrystalParts(root.Position,CFG.PICK.instantRadius)
	if not hits then return end
	local seen={}
	for _,part in ipairs(hits) do
		local prompt=part:FindFirstChildWhichIsA("ProximityPrompt",true)
		if prompt and not seen[prompt] then seen[prompt]=true; instantPromptPatch(prompt) end
		local model=part:FindFirstAncestorOfClass("Model")
		if model then
			prompt=model:FindFirstChildWhichIsA("ProximityPrompt",true)
			if prompt and not seen[prompt] then seen[prompt]=true; instantPromptPatch(prompt) end
		end
	end
end

local function setInstantPrompt(value)
	instantPromptActive=value; Runtime.instantAccumulator=math.huge
	if not value then restoreInstantPrompts() end
end
local function instantGrab()
	if not instantPromptActive then return end
	local root=getRoot(); if not root then return end
	local hits=nearbyCrystalParts(root.Position,CFG.PICK.range+CFG.PICK.pad)
	if not hits then return end
	local best,bestPrompt,bestDistance
	for _,part in ipairs(hits) do
		if part.Parent and isCrystal(part) and getAttr(part,"Collected")~=true and meetsPickupFilter(part,crystalValue(part)) then
			local dist=surfaceDistance(part,root.Position)
			if dist<=CFG.PICK.range and (not best or dist<bestDistance) then
				best=part; bestPrompt=crystalPrompt(part); bestDistance=dist
			end
		end
	end
	if not best then return end
	if bestPrompt then instantPromptPatch(bestPrompt) end
	if grabCrystal(best,bestPrompt) then Cache.claimed[best]=os.clock() end
end
local function pickupStep()
	if Runtime._pickupStepRunning then return end
	Runtime._pickupStepRunning=true
	local now=os.clock()
	if now-Runtime.lastPickup<CFG.PICK.cooldown then Runtime._pickupStepRunning=false; return end
	local root=getRoot(); if not root then Runtime._pickupStepRunning=false; return end
	local free=backpackFree()
	if free<=0 then
		if now-Runtime.lastBagWarn>=8 then Runtime.lastBagWarn=now; Notify("Backpack full",2) end
		Runtime._pickupStepRunning=false; return
	end
	for inst,stamp in pairs(Cache.claimed) do
		if now-stamp>=CFG.PICK.forget or not inst.Parent then Cache.claimed[inst]=nil end
	end
	local cands=pickupCandidates(free,root.Position)
	if #cands==0 then requestStream(root.Position); Runtime._pickupStepRunning=false; return end
	local budget=free; local grabs=0
	for _,entry in ipairs(cands) do
		if grabs>=CFG.PICK.burst then break end
		if entry.weight<=budget then
			Cache.claimed[entry.inst]=now
			if grabCrystal(entry.inst,entry.prompt) then budget=budget-entry.weight; grabs=grabs+1 end
		end
	end
	if grabs>0 then Runtime.lastPickup=now end
	Runtime._pickupStepRunning=false
end

-- [22] SPEED
local function enforceSpeed(humanoid)
	if not humanoid or humanoid.WalkSpeed==CFG.PACE.boost then return end
	pcall(function() humanoid.WalkSpeed=CFG.PACE.boost end)
end
local function watchSpeed(humanoid)
	if Runtime.speedHooked==humanoid then return end
	if Runtime.speedConn then Runtime.speedConn:Disconnect(); Runtime.speedConn=nil end
	Runtime.speedHooked=humanoid; if not humanoid then return end
	local ok,conn=pcall(function()
		return humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if speedActive then enforceSpeed(humanoid) end
		end)
	end)
	if ok then Runtime.speedConn=conn end
end
local function setSpeedBoost(value)
	speedActive=value
	local char=LocalPlayer.Character
	local h=char and char:FindFirstChildOfClass("Humanoid")
	if value then watchSpeed(h); enforceSpeed(h); return end
	watchSpeed(nil)
	if h then pcall(function() h.WalkSpeed=CFG.PACE.normal end) end
end

-- [23] FPS BOOST (ULTRA / ALL-IN-ONE — UI SAFE)
-- One toggle only. Aggressive visual optimization without touching game UI.
-- IMPORTANT: Do not lower Roblox rendering quality globally and do not modify
-- GuiObjects/LayerCollectors/SurfaceGui/BillboardGui outside the crystal-hide system.
local function applyFpsBoost(enabled)
	fpsBoostActive=enabled
	Toggles.FpsBoost=enabled
	Toggles.UltraFps=enabled -- compatibility only
	local Lighting=S.Lighting
	local POST_TYPES={BloomEffect=true,BlurEffect=true,ColorCorrectionEffect=true,DepthOfFieldEffect=true,SunRaysEffect=true}
	local KILL_TYPES={ParticleEmitter=true,Trail=true,Beam=true,Smoke=true,Fire=true,Sparkles=true}

	if enabled then
		Runtime.fpsPassId=Runtime.fpsPassId+1
		local passId=Runtime.fpsPassId

		-- Save only global visual settings that we actually change.
		Runtime.savedLightState.GlobalShadows=Lighting.GlobalShadows
		Runtime.savedLightState.FogEnd=Lighting.FogEnd
		Runtime.savedWaterWaveSpeed=workspace.Terrain.WaterWaveSpeed
		Runtime.savedWaterReflectance=workspace.Terrain.WaterReflectance

		pcall(function() Lighting.GlobalShadows=false end)
		pcall(function() Lighting.FogEnd=100000 end)

		-- Do NOT force QualityLevel=Level01 here.
		-- That setting is global and can alter the game's own presentation/UI.
		-- We get the FPS gain from disabling expensive visual effects instead.

		table.clear(Runtime.savedParticleState)
		table.clear(Runtime.savedPostFx)
		table.clear(Runtime.savedCastShadow)

		-- Only process visual effect instances. We deliberately do NOT iterate
		-- BaseParts and do not touch anything under PlayerGui/CoreGui.
		local ok,objects=pcall(function() return workspace:GetDescendants() end)
		if ok and type(objects)=="table" then
			task.spawn(function()
				local processed=0
				for _,obj in ipairs(objects) do
					if Runtime.fpsPassId~=passId or not fpsBoostActive then return end
					local cls=obj.ClassName
					if KILL_TYPES[cls] then
						Runtime.savedParticleState[obj]=obj.Enabled
						if obj.Enabled then pcall(function() obj.Enabled=false end) end
					elseif POST_TYPES[cls] then
						Runtime.savedPostFx[obj]=obj.Enabled
						if obj.Enabled then pcall(function() obj.Enabled=false end) end
					end
					processed=processed+1
					if processed%300==0 then task.wait() end
				end
			end)
		end

		-- Lighting post-processing is kept separate and chunked.
		local okLight,lightObjects=pcall(function() return Lighting:GetDescendants() end)
		if okLight and type(lightObjects)=="table" then
			task.spawn(function()
				for i,obj in ipairs(lightObjects) do
					if Runtime.fpsPassId~=passId or not fpsBoostActive then return end
					if POST_TYPES[obj.ClassName] then
						Runtime.savedPostFx[obj]=obj.Enabled
						pcall(function() obj.Enabled=false end)
					end
					if i%50==0 then task.wait() end
				end
			end)
		end

		pcall(function() workspace.Terrain.Decoration=false end)
		pcall(function() workspace.Terrain.WaterWaveSize=0 end)
		pcall(function() workspace.Terrain.WaterWaveSpeed=0 end)
		pcall(function() workspace.Terrain.WaterReflectance=0 end)

		-- New visual effects are handled, but GUI objects are never modified.
		if not Runtime.fpsBoostDescConn then
			Runtime.fpsBoostDescConn=workspace.DescendantAdded:Connect(function(obj)
				if not fpsBoostActive then return end
				local cls=obj.ClassName
				if KILL_TYPES[cls] then
					Runtime.savedParticleState[obj]=obj.Enabled
					pcall(function() obj.Enabled=false end)
				elseif POST_TYPES[cls] then
					Runtime.savedPostFx[obj]=obj.Enabled
					pcall(function() obj.Enabled=false end)
				end
			end)
		end

		-- Keep the low-value crystal optimization, but it is the ONLY place
		-- where the script intentionally hides BillboardGui/SurfaceGui children.
		pcall(refreshCrystalVisibility)
		Notify("FPS Boost ON - Ultra / UI Safe",2)
	else
		Runtime.fpsPassId=Runtime.fpsPassId+1

		if Runtime.savedLightState.GlobalShadows~=nil then
			pcall(function() Lighting.GlobalShadows=Runtime.savedLightState.GlobalShadows end)
		end
		if Runtime.savedLightState.FogEnd~=nil then
			pcall(function() Lighting.FogEnd=Runtime.savedLightState.FogEnd end)
		end

		for obj,wasEnabled in pairs(Runtime.savedParticleState) do
			if obj and obj.Parent then pcall(function() obj.Enabled=wasEnabled end) end
		end
		for obj,wasEnabled in pairs(Runtime.savedPostFx) do
			if obj and obj.Parent then pcall(function() obj.Enabled=wasEnabled end) end
		end

		-- Kept only for compatibility with older saved state. This version does
		-- not modify CastShadow, so normally this table stays empty.
		for obj,oldShadow in pairs(Runtime.savedCastShadow) do
			if obj and obj.Parent then pcall(function() obj.CastShadow=oldShadow end) end
		end

		table.clear(Runtime.savedParticleState)
		table.clear(Runtime.savedPostFx)
		table.clear(Runtime.savedCastShadow)
		pcall(function() workspace.Terrain.Decoration=true end)
		if Runtime.savedWaterWaveSpeed~=nil then pcall(function() workspace.Terrain.WaterWaveSpeed=Runtime.savedWaterWaveSpeed end) end
		if Runtime.savedWaterReflectance~=nil then pcall(function() workspace.Terrain.WaterReflectance=Runtime.savedWaterReflectance end) end
		if Runtime.fpsBoostDescConn then Runtime.fpsBoostDescConn:Disconnect(); Runtime.fpsBoostDescConn=nil end
		fpsBoostActive=false
		pcall(refreshCrystalVisibility)
		Notify("FPS Boost OFF",2)
	end
end

-- [24] AUTO REVIVE
if RMT.ReviveShow then
	RMT.ReviveShow.OnClientEvent:Connect(function()
		if not autoReviveActive then return end
		task.wait(0.4)
		pcall(function() RMT.ReviveBase:FireServer() end)
	end)
end

-- [25] AUTO HOP
local function startAutoHop()
	if Runtime.autoHopConn then Runtime.autoHopConn:Disconnect(); Runtime.autoHopConn=nil end
	if not autoHopActive then return end
	Runtime.autoHopStartClock=os.clock()
	local targetSec=DHubState.autoHopMinutes*60
	Runtime.autoHopConn=S.RunService.Heartbeat:Connect(function()
		if not autoHopActive then Runtime.autoHopConn:Disconnect(); Runtime.autoHopConn=nil; return end
		if os.clock()-Runtime.autoHopStartClock>=targetSec then
			Runtime.autoHopConn:Disconnect(); Runtime.autoHopConn=nil
			Notify(string.format("Auto-hop: %d min reached",DHubState.autoHopMinutes),3)
			task.wait(1)
			if Net and Net.hop then Net.hop() end
		end
	end)
end
local function setAutoHop(enabled)
	autoHopActive=enabled
	if enabled then startAutoHop()
	else if Runtime.autoHopConn then Runtime.autoHopConn:Disconnect(); Runtime.autoHopConn=nil end end
	if saveConfig then pcall(saveConfig) end
end

-- [26] MOUNTAIN MODULE
local Mountain={}
local mountainConn
do
	local function install()
		local BOULDER_INFO={
			Mossite   ={rarity="Common",    pickaxe="Titanium Spike", crystals="8-11",  runes="Luck / Haste",        color=Color3.fromRGB(150,220,120)},
			Voltite   ={rarity="Uncommon",  pickaxe="Celestial Apex", crystals="10-14", runes="Storm / Weight",        color=Color3.fromRGB(110,190,240)},
			Gildrite  ={rarity="Rare",      pickaxe="Eclipse Fang",   crystals="11-15", runes="Fortune / Detonation",  color=Color3.fromRGB(255,200,60)},
			Rimeveil  ={rarity="Epic",      pickaxe="Voidreign",      crystals="13-18", runes="Preservation / Warmth", color=Color3.fromRGB(170,100,255)},
			Nocturnite={rarity="Legendary", pickaxe="The Terminus",   crystals="16-22", runes="Excavator / Colossus",  color=Color3.fromRGB(255,80,180)},
		}
		local BOULDER_OFFSET=Vector3.new(0,7,0)
		local BOULDER_WIDTH=300; local BOULDER_HEIGHT=78
		local BOULDER_STEP=0.8; local BOULDER_MAX_DISTANCE=350; local GRAB_RANGE=20
		local GRAB_STEP=0.15; local GRAB_LIMIT=4; local GRAB_RETRY=0.2
		local boulderEsp=false; local autoGrab=false
		local boulderCache={}; local grabbed={}
		local boulderClock=0; local grabClock=0
		local scanParams=OverlapParams.new()
		scanParams.FilterType=Enum.RaycastFilterType.Exclude
		local function textSize() return math.max(6,math.floor(CFG.ESP.text*boulderScale+0.5)) end
		local function anchorPart(inst)
			if inst:IsA("BasePart") then return inst end
			if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart") end
			return nil
		end
		local function createCard(anchor,offset,colors,width,height)
			local bb=Instance.new("BillboardGui")
			bb.Name="UniverseMountainEsp"; bb.Adornee=anchor; bb.AlwaysOnTop=true
			bb.ResetOnSpawn=false; bb.LightInfluence=0
			bb.Size=UDim2.fromOffset(width*boulderScale,height*boulderScale)
			bb.StudsOffsetWorldSpace=offset; bb.MaxDistance=math.huge; bb.Parent=EspHolder
			local total=#colors; local sz=textSize(); local labels={}; local constraints={}
			for i,color in ipairs(colors) do
				local label,constraint=newLabel("Line"..i,bb,i-1,total,color,false,sz)
				labels[i]=label; constraints[i]=constraint
			end
			return {gui=bb,labels=labels,constraints=constraints,width=width,height=height,text={}}
		end
		local function scaleCard(entry)
			entry.gui.Size=UDim2.fromOffset(entry.width*boulderScale,entry.height*boulderScale)
			local sz=textSize(); for _,c in ipairs(entry.constraints) do c.MaxTextSize=sz end
		end
		local function setLine(entry,index,text)
			if entry.text[index]==text then return end
			entry.text[index]=text; entry.labels[index].Text=text
		end
		local function dropCard(cache,key)
			local e=cache[key]; if not e then return end
			if e.gui then e.gui:Destroy() end; cache[key]=nil
		end
		local function clearCache(cache) for key in pairs(cache) do dropCard(cache,key) end end
		local function boulderKind(inst)
			for kind in pairs(BOULDER_INFO) do if inst.Name:find(kind,1,true) then return kind end end
			return nil
		end
		local function boulderRoots()
			local roots={}
			local deco=S.Workspace:FindFirstChild("MountainDecorations")
			local fold=deco and deco:FindFirstChild("Boulders"); if fold then roots[#roots+1]=fold end
			local test=S.Workspace:FindFirstChild("BoulderTest"); if test then roots[#roots+1]=test end
			return roots
		end
		local function eachBoulder(fn)
			for _,container in ipairs(boulderRoots()) do
				for _,child in ipairs(container:GetChildren()) do
					local kind=boulderKind(child); if kind then fn(child,kind) end
				end
			end
		end
		local function isRune(inst)
			if getAttr(inst,"RuneId")~=nil then return true end
			if getAttr(inst,"IsRune")==true then return true end
			if getAttr(inst,"RuneName")~=nil then return true end
			return inst.Name:find(" Rune",1,true)~=nil
		end
		local function runeTitle(inst)
			local id=getAttr(inst,"RuneId") or getAttr(inst,"RuneName")
			if type(id)=="string" and id~="" then
				if id:find("Rune",1,true) then return id end
				return id.." Rune"
			end
			return inst.Name
		end
		local function eachRune(origin,radius,fn)
			local seen={}
			local function offer(owner,part)
				if not owner or seen[owner] then return end
				local anchor=part or anchorPart(owner)
				if not anchor or not anchor.Parent then return end
				if (anchor.Position-origin).Magnitude>radius then return end
				seen[owner]=true; fn(owner,anchor)
			end
			local function scanFolder(c)
				if not c then return end
				for _,child in ipairs(c:GetChildren()) do
					if isRune(child) then offer(child,anchorPart(child)) end
				end
			end
			scanFolder(S.Workspace:FindFirstChild("DroppedRunes"))
			local char=LocalPlayer.Character
			scanParams.FilterDescendantsInstances=char and {char} or {}
			local ok,parts=pcall(function() return S.Workspace:GetPartBoundsInRadius(origin,radius,scanParams) end)
			if not ok or not parts then return end
			for _,part in ipairs(parts) do
				if isRune(part) then offer(part,part)
				else
					local parent=part.Parent
					if parent and parent~=S.Workspace and isRune(parent) then
						offer(parent,anchorPart(parent) or part)
					end
				end
			end
		end
		local function syncBoulders()
			local root=getRoot(); local origin=root and root.Position or nil; local seen={}
			eachBoulder(function(model,kind)
				local anchor=anchorPart(model); if not anchor then return end
			local distance=origin and (anchor.Position-origin).Magnitude or 0
			if origin and distance>BOULDER_MAX_DISTANCE then dropCard(boulderCache,model); return end
				seen[model]=true
				if next(boulderEspFilter)~=nil and not boulderEspFilter[kind] then
					local entry=boulderCache[model]
					if entry then dropCard(boulderCache,model) end
					return
				end
				local info=BOULDER_INFO[kind]
				local entry=boulderCache[model]
				if entry and not entry.gui.Parent then dropCard(boulderCache,model); entry=nil end
				if not entry then
					entry=createCard(anchor,BOULDER_OFFSET,{info.color,CFG.COLORS.extra,CFG.COLORS.money},BOULDER_WIDTH,BOULDER_HEIGHT)
					boulderCache[model]=entry
				end
				if entry.gui.Adornee~=anchor then entry.gui.Adornee=anchor end
				scaleCard(entry)
				setLine(entry,1,string.format("[%s] %s",info.rarity,kind))
				setLine(entry,2,string.format("%s  \u{2022}  %s crystals",info.pickaxe,info.crystals))
				local dist=origin and formatDistance((anchor.Position-origin).Magnitude) or "--"
				setLine(entry,3,string.format("%s  \u{2022}  %s",info.runes,dist))
			end)
			local stale
			for model in pairs(boulderCache) do
				if not seen[model] then stale=stale or {}; stale[#stale+1]=model end
			end
			if stale then for _,m in ipairs(stale) do dropCard(boulderCache,m) end end
		end
		local function runeMatchesFilter(owner)
			-- V2.4: Auto Pickup Rune is intentionally unfiltered.
			return true
		end
		local function grabRunes(radius)
			local root=getRoot(); if not root then return 0 end
			local now=os.clock(); local fired=0
			for prompt,stamp in pairs(grabbed) do
				if now-stamp>5 or not prompt.Parent then grabbed[prompt]=nil end
			end
			eachRune(root.Position,radius or GRAB_RANGE,function(owner,part)
				if fired>=GRAB_LIMIT then return end
				if not runeMatchesFilter(owner) then return end
				local prompt=owner:FindFirstChildOfClass("ProximityPrompt") or crystalPrompt(owner)
				if not prompt and part~=owner then prompt=crystalPrompt(part) end
				if not prompt or not prompt.Parent then return end
				local last=grabbed[prompt]
				if last and now-last<GRAB_RETRY then return end
				grabbed[prompt]=now
				if firePrompt(prompt) then fired=fired+1; Notify(string.format("Rune: %s",runeTitle(owner)),2) end
			end)
			return fired
		end
		function Mountain.applyScale()
			for _,entry in pairs(boulderCache) do scaleCard(entry) end
		end
		function Mountain.boulderList()
			local list={}
			for _,kind in ipairs({"Mossite","Voltite","Gildrite","Rimeveil","Nocturnite"}) do
				local info=BOULDER_INFO[kind]
				list[#list+1]=string.format("%s  \u{2022}  %s",kind,info.pickaxe)
			end
			return list
		end
		function Mountain.setBoulderEsp(value)
			boulderEsp=value
			if value then boulderClock=math.huge else clearCache(boulderCache) end
		end
		function Mountain.setAutoGrab(value)
			autoGrab=value
			if not value then table.clear(grabbed) end
		end
		function Mountain.grabRange() return GRAB_RANGE end
		function Mountain.grabNear(radius)
			local ok,fired=pcall(grabRunes,radius)
			if not ok then reportError("runeGrab",fired); return 0 end
			return fired or 0
		end
		function Mountain.runesNear(radius)
			local root=getRoot(); if not root then return 0 end
			local count=0
			eachRune(root.Position,radius or GRAB_RANGE,function() count=count+1 end)
			return count
		end
		function Mountain.shutdown()
			boulderEsp=false; autoGrab=false
			clearCache(boulderCache); table.clear(grabbed)
		end
		function Mountain.tick(deltaTime)
			if boulderEsp then
				boulderClock=boulderClock+deltaTime
				if boulderClock>=BOULDER_STEP then
					boulderClock=0
					local ok,err=pcall(syncBoulders); if not ok then reportError("boulder",err) end
				end
			end
			if autoGrab then
				grabClock=grabClock+deltaTime
				if grabClock>=GRAB_STEP then
					grabClock=0
					local ok,err=pcall(grabRunes); if not ok then reportError("runeGrab",err) end
				end
			end
		end
	end
	install()
end

-- [27] MOVE MODULE
local Move={}
do
	local function install()
		local FLY_KEYS={
			{key=Enum.KeyCode.W,           axis="look",  sign= 1},
			{key=Enum.KeyCode.S,           axis="look",  sign=-1},
			{key=Enum.KeyCode.D,           axis="right", sign= 1},
			{key=Enum.KeyCode.A,           axis="right", sign=-1},
			{key=Enum.KeyCode.Space,       axis="up",    sign= 1},
			{key=Enum.KeyCode.LeftControl, axis="up",    sign=-1},
		}
		local flyActive=false; local noclipActive=false; local jumpActive=false
		local flySpeed=100
		local velocity,gyro
		local flyConn,noclipConn,jumpConn
		local collisions={}
		local function humanoidOf()
			local char=LocalPlayer.Character
			return char and char:FindFirstChildOfClass("Humanoid")
		end
		local function dropMovers()
			if velocity then pcall(function() velocity:Destroy() end); velocity=nil end
			if gyro     then pcall(function() gyro:Destroy()     end); gyro=nil     end
		end
		local function attach(root)
			dropMovers()
			local ok=pcall(function()
				local body=Instance.new("BodyVelocity")
				body.Name="UniverseFlyVelocity"; body.MaxForce=Vector3.new(9e9,9e9,9e9)
				body.P=9e4; body.Velocity=Vector3.zero; body.Parent=root; velocity=body
				local spin=Instance.new("BodyGyro")
				spin.Name="UniverseFlyGyro"; spin.MaxTorque=Vector3.new(9e9,9e9,9e9)
				spin.P=9e4; spin.D=500; spin.CFrame=root.CFrame; spin.Parent=root; gyro=spin
			end)
			if not ok then dropMovers() end; return ok
		end
		local function flyStep()
			if Runtime.tpState then return end
			local root=getRoot(); if not root then return end
			if not velocity or velocity.Parent~=root then if not attach(root) then return end end
			local camera=S.Workspace.CurrentCamera; if not camera then return end
			local h=humanoidOf()
			if h and not h.PlatformStand then h.PlatformStand=true end
			local frame=camera.CFrame; local direction=Vector3.zero
			if not S.UserInputService:GetFocusedTextBox() then
				for _,entry in ipairs(FLY_KEYS) do
					if S.UserInputService:IsKeyDown(entry.key) then
						if     entry.axis=="look"  then direction=direction+frame.LookVector*entry.sign
						elseif entry.axis=="right" then direction=direction+frame.RightVector*entry.sign
						else                            direction=direction+Vector3.yAxis*entry.sign end
					end
				end
			end
			if direction.Magnitude>0.1 then velocity.Velocity=direction.Unit*flySpeed
			else                            velocity.Velocity=Vector3.zero end
			local flat=Vector3.new(frame.LookVector.X,0,frame.LookVector.Z)
			if flat.Magnitude>0.05 then gyro.CFrame=CFrame.new(root.Position,root.Position+flat) end
		end
		local function noclipStep()
			local char=LocalPlayer.Character; if not char then return end
			for _,part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide then
					if collisions[part]==nil then collisions[part]=true end
					part.CanCollide=false
				end
			end
		end
		function Move.setFly(value)
			flyActive=value
			if value then
				local root=getRoot(); if root then attach(root) end
				if not flyConn then
					flyConn=S.RunService.Heartbeat:Connect(function()
						if not flyActive then return end
						local ok,err=pcall(flyStep); if not ok then reportError("fly",err) end
					end)
				end; return
			end
			if flyConn then flyConn:Disconnect(); flyConn=nil end
			dropMovers()
			local h=humanoidOf()
			if h then pcall(function() h.PlatformStand=false; h:ChangeState(Enum.HumanoidStateType.GettingUp) end) end
		end
		function Move.setFlySpeed(value) flySpeed=math.clamp(value,10,500) end
		function Move.setNoclip(value)
			noclipActive=value
			if value then
				if not noclipConn then
					noclipConn=S.RunService.Heartbeat:Connect(function()
						if not noclipActive then return end
						local ok,err=pcall(noclipStep); if not ok then reportError("noclip",err) end
					end)
				end; return
			end
			if noclipConn then noclipConn:Disconnect(); noclipConn=nil end
			for part,state in pairs(collisions) do
				if part.Parent then pcall(function() part.CanCollide=state end) end
			end; table.clear(collisions)
		end
		function Move.setInfJump(value)
			jumpActive=value
			if value then
				if not jumpConn then
					jumpConn=S.UserInputService.JumpRequest:Connect(function()
						if not jumpActive then return end
						local h=humanoidOf()
						if h then pcall(function() h:ChangeState(Enum.HumanoidStateType.Jumping) end) end
					end)
				end; return
			end
			if jumpConn then jumpConn:Disconnect(); jumpConn=nil end
		end
		function Move.shutdown()
			Move.setFly(false); Move.setNoclip(false); Move.setInfJump(false)
			if Move.glideStop then Move.glideStop() end
		end
	end
	install()
end

-- [28] MOVE GLIDE
do
	local function install()
		local GLIDE_SPEED=350; local AIM_RATE=9; local SNAP_GAP=0.35
		local RESPONSE=200; local STREAM_GAP=0.5
		local HOLD_FORCE=1e7; local HOLD_TORQUE=1e7
		local attachment,mover,aligner
		local cursor,facing,goalFrame,aimSpot
		local streamClock=0; local glideConn; local running=false
		local function humanoidOf()
			local char=LocalPlayer.Character
			return char and char:FindFirstChildOfClass("Humanoid")
		end
		local function detach()
			if mover     then pcall(function() mover:Destroy()      end); mover=nil      end
			if aligner   then pcall(function() aligner:Destroy()    end); aligner=nil    end
			if attachment then pcall(function() attachment:Destroy() end); attachment=nil end
		end
		local function attach(root)
			detach()
			local ok=pcall(function()
				local point=Instance.new("Attachment"); point.Name="UniverseGlidePoint"; point.Parent=root
				local position=Instance.new("AlignPosition"); position.Name="UniverseGlidePosition"
				position.Mode=Enum.PositionAlignmentMode.OneAttachment; position.Attachment0=point
				position.RigidityEnabled=false; position.ApplyAtCenterOfMass=true
				position.ReactionForceEnabled=false; position.MaxForce=HOLD_FORCE
				position.MaxVelocity=math.huge; position.Responsiveness=RESPONSE
				position.Position=root.Position; position.Parent=root
				local orientation=Instance.new("AlignOrientation"); orientation.Name="UniverseGlideOrientation"
				orientation.Mode=Enum.OrientationAlignmentMode.OneAttachment; orientation.Attachment0=point
				orientation.RigidityEnabled=false; orientation.ReactionTorqueEnabled=false
				orientation.MaxTorque=HOLD_TORQUE; orientation.MaxAngularVelocity=math.huge
				orientation.Responsiveness=RESPONSE; orientation.CFrame=root.CFrame.Rotation
				orientation.Parent=root
				attachment=point; mover=position; aligner=orientation
			end)
			if not ok then detach() end; return ok
		end
		local function step(deltaTime)
			if not goalFrame then return end
			local root=getRoot(); if not root then return end
			if not mover or mover.Parent~=root or not aligner or aligner.Parent~=root then
				if not attach(root) then return end
				cursor=root.Position; facing=root.CFrame.Rotation
			end
			local h=humanoidOf()
			if h and not h.PlatformStand then pcall(function() h.PlatformStand=true end) end
			cursor=cursor or root.Position; facing=facing or root.CFrame.Rotation
			local delta=goalFrame.Position-cursor; local span=GLIDE_SPEED*deltaTime
			if delta.Magnitude<=math.max(span,SNAP_GAP) then cursor=goalFrame.Position
			else cursor=cursor+delta.Unit*span end
			streamClock=streamClock+deltaTime
			if streamClock>=STREAM_GAP then streamClock=0; requestStream(goalFrame.Position) end
			local look=goalFrame.Rotation
			if aimSpot then
				local gap=aimSpot-cursor
				if gap.Magnitude>0.1 then look=CFrame.lookAt(cursor,aimSpot).Rotation end
			end
			facing=facing:Lerp(look,1-math.exp(-AIM_RATE*deltaTime))
			mover.Position=cursor; aligner.CFrame=facing
		end
		function Move.glide(goal,aim)
			if typeof(goal)~="CFrame" then return false end
			goalFrame=goal; aimSpot=typeof(aim)=="Vector3" and aim or nil
			if not running then
				running=true
				local root=getRoot()
				if root then cursor=root.Position; facing=root.CFrame.Rotation; attach(root) end
			end
			if not glideConn then
				glideConn=S.RunService.Heartbeat:Connect(function(dt)
					if not running then return end
					local ok,err=pcall(step,dt); if not ok then reportError("glide",err) end
				end)
			end
			return true
		end
		function Move.glideStop()
			running=false; goalFrame=nil; aimSpot=nil; cursor=nil; facing=nil; streamClock=0
			if glideConn then glideConn:Disconnect(); glideConn=nil end
			detach()
			local root=getRoot()
			if root then pcall(function()
				root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero
			end) end
			local h=humanoidOf()
			if h then pcall(function() h.PlatformStand=false; h:ChangeState(Enum.HumanoidStateType.GettingUp) end) end
		end
	end
	install()
end

-- [29] NET MODULE
local Net={}
local netConns={}
do
	local function install()
		local PLACE=game.PlaceId; local PAGES=1; local POOL_TARGET=20
		local RETRY_STEP=1.5; local RETRY_LIMIT=10; local BACK_DELAY=3
		local REFILL_MARK=8; local WARM_STEP=30
		local visited={}; local pool={}; local hopping=false; local reviving=false
		local lastCode=0; local alive=true
		local function note(text) pcall(function() Notify("Hop  "..text,4) end) end
		local function grab(link)
			local sender=(syn and syn.request) or (http and http.request) or http_request or request
			if type(sender)=="function" then
				local ok,response=pcall(function() return sender({Url=link,Method="GET"}) end)
				if ok and type(response)=="table" then
					local code=tonumber(response.StatusCode) or 0
					if code>=200 and code<300 and type(response.Body)=="string" then return response.Body,code end
					return nil,code
				end
			end
			local ok,body=pcall(function() return game:HttpGet(link) end)
			if ok and type(body)=="string" then return body,200 end
			return nil,0
		end
		local function fetch(cursor)
			local link=string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&excludeFullGames=true&limit=100",PLACE)
			if type(cursor)=="string" and cursor~="" then link=link.."&cursor="..cursor end
			local body,code=grab(link)
			if type(body)~="string" then lastCode=code or 0; return nil,nil end
			local parsed,data=pcall(function() return S.HttpService:JSONDecode(body) end)
			if not parsed or type(data)~="table" then lastCode=-1; return nil,nil end
			return data.data,data.nextPageCursor
		end
		local function refill()
			table.clear(pool)
			local cursor
			for _=1,PAGES do
				local entries,nextCursor=fetch(cursor)
				if type(entries)=="table" then
					for _,entry in ipairs(entries) do
						local id=type(entry)=="table" and entry.id or nil
						if type(id)=="string" and id~=game.JobId and not visited[id] then
							local playing=tonumber(entry.playing) or 0
							local room=tonumber(entry.maxPlayers) or 0
							if room==0 or playing<room then pool[#pool+1]=id end
						end
					end
				end
				cursor=nextCursor
				if type(cursor)~="string" or cursor=="" or #pool>=POOL_TARGET then break end
			end
			for i=#pool,2,-1 do
				local swap=math.random(1,i); pool[i],pool[swap]=pool[swap],pool[i]
			end
			return #pool
		end
		function Net.rejoin()
			if reviving then return end; reviving=true
			local jobId=game.JobId
			task.spawn(function()
				for _=1,RETRY_LIMIT do
					local sent=pcall(function() S.TeleportService:TeleportToPlaceInstance(PLACE,jobId,LocalPlayer) end)
					if not sent then pcall(function() S.TeleportService:Teleport(PLACE,LocalPlayer) end) end
					task.wait(RETRY_STEP)
				end; reviving=false
			end)
		end
		function Net.hop()
			if hopping then return false end
			hopping=true; visited[game.JobId]=true
			task.spawn(function()
				for round=1,RETRY_LIMIT do
					if #pool==0 and refill()==0 then table.clear(visited); visited[game.JobId]=true; refill() end
					local choice=table.remove(pool)
					if choice then
						visited[choice]=true
						note(string.format("try %d  %s",round,string.sub(choice,1,8)))
						local sent,err=pcall(function() S.TeleportService:TeleportToPlaceInstance(PLACE,choice,LocalPlayer) end)
						if not sent then note("blocked  "..tostring(err)) end
						if #pool<=REFILL_MARK then task.spawn(refill) end
					else
						note(string.format("no servers  http %d",lastCode))
					end
					task.wait(RETRY_STEP)
				end; hopping=false
			end); return true
		end
		function Net.forget() table.clear(visited); table.clear(pool); visited[game.JobId]=true end
		function Net.busy()  return hopping end
		function Net.ready() return #pool   end
		function Net.stop()  alive=false     end
		task.spawn(function()
			while alive do
				if #pool<POOL_TARGET and not hopping then refill() end
				task.wait(WARM_STEP)
			end
		end)
		netConns[#netConns+1]=S.TeleportService.TeleportInitFailed:Connect(function() hopping=false end)
		netConns[#netConns+1]=S.GuiService.ErrorMessageChanged:Connect(function()
			local ok,message=pcall(function() return S.GuiService:GetErrorMessage() end)
			if ok and type(message)=="string" and message~="" then task.delay(BACK_DELAY,Net.rejoin) end
		end)
		local prompts=S.CoreGui:FindFirstChild("RobloxPromptGui")
		local overlay=prompts and prompts:FindFirstChild("promptOverlay")
		if overlay then
			netConns[#netConns+1]=overlay.ChildAdded:Connect(function(child)
				if child.Name:find("ErrorPrompt") then task.delay(BACK_DELAY,Net.rejoin) end
			end)
		end
	end
	install()
end

-- [30] SHARED TOOLS
local Tools={}
do
	local _digRemote
	local PICK_NAMES={
		["Rusty Scrapper"]=true,["Weathered Wood"]=true,["Chipped Stone"]=true,
		["Hardened Iron"]=true,["Copper Pick"]=true,["Reinforced Steel"]=true,
		["Titanium Spike"]=true,["Frostbite Pick"]=true,["Emerald Carver"]=true,
		["Volcano Basalt"]=true,["Obsidian Edge"]=true,["Tempest Pick"]=true,
		["Celestial Apex"]=true,["Astral Rend"]=true,["Eclipse Fang"]=true,
		["Nebular Throne"]=true,Voidreign=true,Singularity=true,
		["The Terminus"]=true,["Admin Pickaxe"]=true,["Shark Pickaxe"]=true,["Diamond Pickaxe"]=true,
	}
	local COOLDOWN_KEYS={"SwingCooldown","DigCooldown","Cooldown","SwingSpeed","DigSpeed"}
	local SWING_GAP=0.04; local SWING_FLOOR=0.02
	function Tools.digEvent()
		if _digRemote and _digRemote.Parent then return _digRemote end
		_digRemote=RMT.DigRequest or findRemote("DigRequest")
		return _digRemote
	end
	function Tools.isPickaxe(tool)
		if not tool or not tool:IsA("Tool") then return false end
		if getAttr(tool,"IsPickaxe")==true then return true end
		if PICK_NAMES[tool.Name] then return true end
		return getAttr(tool,"DigPower")~=nil and getAttr(tool,"Tier")==nil
	end
	function Tools.pickScore(tool)
		if not Tools.isPickaxe(tool) then return 0 end
		local score=1; local power=tonumber(getAttr(tool,"DigPower"))
		if power then score=score+power end; return score
	end
	function Tools.equipPick()
		local char=LocalPlayer.Character
		local h=char and char:FindFirstChildOfClass("Humanoid")
		if not char or not h then return nil end
		local held=char:FindFirstChildOfClass("Tool")
		local choice; local best=0
		local function consider(tool)
			local score=Tools.pickScore(tool); if score>best then best=score; choice=tool end
		end
		consider(held)
		local bp=LocalPlayer:FindFirstChildOfClass("Backpack")
		if bp then for _,tool in ipairs(bp:GetChildren()) do consider(tool) end end
		if not choice then return nil end
		if choice==held then return held end
		pcall(function() h:EquipTool(choice) end)
		local now=char:FindFirstChildOfClass("Tool")
		return (now and Tools.isPickaxe(now)) and now or nil
	end
	function Tools.swingGap(tool)
		if tool then
			for _,key in ipairs(COOLDOWN_KEYS) do
				local value=tonumber(getAttr(tool,key))
				if value and value>0 then return math.max(value,SWING_FLOOR) end
			end
		end
		return SWING_GAP
	end
end

-- [31] FARM MODULE (BOULDER FARM) - SAFE TOP-DOWN TERRAIN FARM
local Farm={}
local farmConn
do
	local function install()
		local FARM_KINDS={"Mossite","Voltite","Gildrite","Rimeveil","Rimveil","Nocturnite"}
		local SCAN_SPOTS={
			CFrame.new(-12.7105675,459.090942,818.847412,0.993408799,-0.00500036497,-0.11451605,0.000644713698,0.999275982,-0.0380407833,0.114623353,0.0377162211,0.992692769),
			CFrame.new(13.0506754,318.450409,-488.078888,-0.99998939,0.000884758658,-0.00452193478,-0.000498382491,0.954864502,0.297041386,0.00458064489,0.297040492,-0.954853892),
			CFrame.new(74.3923645,610.789368,210.838226,-0.94896102,-0.27110818,0.161162555,2.26557495e-06,0.51098305,0.859590769,-0.315393418,0.815718472,-0.484902382),
		}

		-- Safe mode: never use noclip while Boulder Farm is active.
		local SCAN_HOLD=1.4
		local TOP_CLEARANCE=6
		-- Rimveil / Voltite can be embedded below the terrain surface.
		-- These two kinds use a special top-of-terrain position only; all other
		-- Boulder kinds keep the normal Money-Farm-style top-down positioning.
		local BURIED_BOULDER_LIFT=3
		local BURIED_BOULDER_HIT_LIFT=1.15
		local BURIED_DIG_REACH=18
		local BURIED_DIG_SINK=2
		local BURIED_DIG_BURST=2
		local SURFACE_REFRESH=0.18
		-- Boulder hit tuning: use a small burst so a valid swing is less likely
		-- to be lost when the character/aim is settling. Keep the burst modest
		-- instead of spamming the remote every frame.
		local SWING_BURST=4
		local FAST_DIG_MULTIPLIER=0.30
		local HARD_BOULDER_HP=500
		local HARD_DIG_MULTIPLIER=0.24
		local EQUIP_STEP=1
		local LOST_GRACE=2.5
		local DRY_ROUNDS=5
		local DRY_TIME=1.25
		local RUNE_SWEEP=90
		local LOOT_WATCHDOG=60
		local LOOT_SCAN_RANGE=70
		local LOOT_QUIET_TIME=1.50
		local RESET_WAIT=2
		local SIGHT_STEPS=8

		local active=false; local targets={}; local phase="idle"
		local target,anchor=nil,nil
		local blockedTargets=setmetatable({}, {__mode="k"})
		local lastVeinSerial=0
		local heldPick=nil
		local areaLootSnapshot={}
		local areaLootActive=false
		local areaLootStartedAt=0
		local swingClock,equipClock=0,0
		local waitUntil=0
		local lootSnapshot={}
		local lootDropSeen=false
		local lootStartedAt=0
		local lootQuietSince=0
		local lootFocus=nil
		local scanned=false; local scanIndex=0
		local lastSpot=nil; local pendingFinish=false
		local hpMark=nil; local dryRounds=0; local dryClock=0
		local lostClock=0; local surfaceClock=0
		local cameraZoomSaved=false
		local cameraMinZoomSaved=nil
		local cameraMaxZoomSaved=nil

		local function setBoulderHitZoom(enabled)
			local player=LocalPlayer
			if not player then return end
			if enabled then
				if not cameraZoomSaved then
					cameraMinZoomSaved=player.CameraMinZoomDistance
					cameraMaxZoomSaved=player.CameraMaxZoomDistance
					cameraZoomSaved=true
				end
				-- Force the camera to its closest legal zoom while the Boulder is hit.
				-- This reduces terrain occlusion without changing the farm's target/aim logic.
				pcall(function()
					player.CameraMinZoomDistance=0.5
					player.CameraMaxZoomDistance=0.5
				end)
			else
				if not cameraZoomSaved then return end
				pcall(function()
					player.CameraMinZoomDistance=cameraMinZoomSaved
					player.CameraMaxZoomDistance=cameraMaxZoomSaved
				end)
				cameraZoomSaved=false
				cameraMinZoomSaved=nil
				cameraMaxZoomSaved=nil
			end
		end

		local terrainSurface=nil; local statusText="Idle"
		local farmNoclipBefore=false

		local rayParams=RaycastParams.new()
		rayParams.FilterType=Enum.RaycastFilterType.Exclude
		rayParams.IgnoreWater=true
		rayParams.RespectCanCollide=false

		local terrainParams=RaycastParams.new()
		terrainParams.FilterType=Enum.RaycastFilterType.Include
		terrainParams.FilterDescendantsInstances={S.Workspace.Terrain}
		terrainParams.IgnoreWater=true

		local buriedDigParams=RaycastParams.new()
		buriedDigParams.FilterType=Enum.RaycastFilterType.Include
		buriedDigParams.IgnoreWater=true

		local function zoneBase()
			local v=S.Workspace:GetAttribute("MountainBaseY")
			return typeof(v)=="number" and v or 0
		end
		local function zonePeak()
			local v=S.Workspace:GetAttribute("MountainPeakY")
			return typeof(v)=="number" and v or zoneBase()+900
		end
		local function mountainCenter()
			local x=S.Workspace:GetAttribute("MountainCenterX")
			local z=S.Workspace:GetAttribute("MountainCenterZ")
			if typeof(x)=="number" and typeof(z)=="number" then return x,z end
			return nil,nil
		end
		local function terrainSurfaceAt(x,z)
			local cx,cz=mountainCenter()
			if cx and cz then
				local radius=S.Workspace:GetAttribute("MountainRadius")
				if typeof(radius)=="number" and radius>10 then
					if (Vector2.new(x,z)-Vector2.new(cx,cz)).Magnitude>radius+16 then return nil end
				end
			end
			local base=zoneBase()
			local top=zonePeak()+100
			local hit=S.Workspace:Raycast(Vector3.new(x,top,z),Vector3.new(0,-(top-base+150),0),terrainParams)
			if hit and hit.Position.Y>base+1 then return hit.Position end
			return nil
		end

		local function junkName(instance)
			local name=string.lower(instance.Name)
			for _,word in ipairs({"vfx","effect","fx","debris","particle","shard","chunk","dust","smoke"}) do
				if string.find(name,word,1,true) then return true end
			end
			return false
		end
		local function usablePart(item)
			return item and item:IsA("BasePart") and item.Anchored and not item.Massless and item.Transparency<0.9 and not junkName(item)
		end
		local function partList(model)
			if model:IsA("BasePart") then return {model} end
			local list={}
			for _,item in ipairs(model:GetDescendants()) do
				if usablePart(item) then list[#list+1]=item end
			end
			return list
		end
		local function anchorOf(model)
			if model:IsA("BasePart") then return model end
			local list=partList(model)
			if list[1] then return list[1] end
			local ok,part=pcall(model.FindFirstChildWhichIsA,model,"BasePart",true)
			return ok and part or nil
		end
		local function boulderHealth(model)
			return tonumber(getAttr(model,"Health") or getAttr(model,"Hp") or getAttr(model,"CurrentHealth"))
		end
		local function boulderKind(inst)
			for _,kind in ipairs(FARM_KINDS) do
				if inst.Name:find(kind,1,true) then return kind end
			end
			return nil
		end
		local function isBuriedBoulderKind(model)
			local kind=boulderKind(model)
			return kind=="Rimeveil" or kind=="Rimveil" or kind=="Voltite"
		end
		local function boulderTopY(model,part)
			if model:IsA("BasePart") then return model.Position.Y+model.Size.Y*0.5 end
			local ok,boxSize,boxCFrame=pcall(function()
				local cf,size=model:GetBoundingBox(); return size,cf
			end)
			if ok and boxSize and boxCFrame then return boxCFrame.Position.Y+boxSize.Y*0.5 end
			if part and part.Parent then return part.Position.Y+part.Size.Y*0.5 end
			return nil
		end
		local function visibleAnchor(model)
			local root=getRoot(); local origin=root and root.Position
			local best,fallback,bestDist,fallDist=nil,nil,nil,nil
			for _,part in ipairs(partList(model)) do
				if part.Parent then
					local d=origin and (part.Position-origin).Magnitude or 0
					if not fallback or d<fallDist then fallback=part; fallDist=d end
					if not best then best=part; bestDist=d end
				end
			end
			return best or fallback
		end
		local function boulderRoots()
			local roots={}
			local deco=S.Workspace:FindFirstChild("MountainDecorations")
			local fold=deco and deco:FindFirstChild("Boulders")
			if fold then roots[#roots+1]=fold end
			local test=S.Workspace:FindFirstChild("BoulderTest")
			if test then roots[#roots+1]=test end
			return roots
		end
		local function pickTarget()
			local root=getRoot(); if not root then return nil,nil end
			local best,bestAnchor,bestScore=nil,nil,nil
			for _,container in ipairs(boulderRoots()) do
				for _,child in ipairs(container:GetChildren()) do
					local kind=boulderKind(child)
					if kind and targets[kind] and not blockedTargets[child] then
						local part=anchorOf(child)
						if part then
							local dist=(part.Position-root.Position).Magnitude
							local hp=boulderHealth(child) or 0
							local score=hp*2+dist
							if not best or score<bestScore then best,bestAnchor,bestScore=child,part,score end
						end
					end
				end
			end
			return best,bestAnchor
		end

		-- Only ignore the player's own character when checking the vertical path.
		local function pathToBoulder(origin,part,model)
			if not part or not part.Parent then return true end
			local delta=part.Position-origin
			if delta.Magnitude<1 then return true end
			rayParams.FilterDescendantsInstances={LocalPlayer.Character}
			local hit=S.Workspace:Raycast(origin,delta.Unit*(delta.Magnitude+2),rayParams)
			if not hit then return true end
			return hit.Instance==part or (model and hit.Instance:IsDescendantOf(model))
		end

		local function refreshBuriedDigFilter()
			local list={S.Workspace.Terrain}
			local deco=S.Workspace:FindFirstChild("MountainDecorations")
			local boulders=deco and deco:FindFirstChild("Boulders")
			if boulders then list[#list+1]=boulders end
			local test=S.Workspace:FindFirstChild("BoulderTest")
			if test then list[#list+1]=test end
			buriedDigParams.FilterDescendantsInstances=list
		end

		local function buriedAimPoint(origin,spot,reach)
			refreshBuriedDigFilter()
			local goals={spot,spot-Vector3.new(0,BURIED_DIG_SINK,0),origin-Vector3.new(0,reach,0)}
			for _,goal in ipairs(goals) do
				local delta=goal-origin
				local distance=delta.Magnitude
				if distance>0.05 then
					local span=math.min(distance+4,reach)
					local hit=S.Workspace:Raycast(origin,delta.Unit*span,buriedDigParams)
					if hit then return hit.Position end
				end
			end
			local delta=spot-origin
			if delta.Magnitude<=reach then return spot end
			return origin+delta.Unit*reach
		end

		local function digBuriedTerrain(root,surface)
			if not surface or not root or not heldPick then return false end
			local event=Tools.digEvent()
			if not event then return false end
			local aim=buriedAimPoint(root.Position,surface,BURIED_DIG_REACH) or surface
			local name=heldPick.Name
			return pcall(function()
				for step=0,BURIED_DIG_BURST-1 do
					event:FireServer(name,aim-Vector3.new(0,step*BURIED_DIG_SINK,0))
				end
			end)
		end

		local function buriedTerrainStillBlocks(root,part)
			if not root or not part or not part.Parent then return false end
			local delta=part.Position-root.Position
			if delta.Magnitude<1 then return false end
			rayParams.FilterDescendantsInstances={LocalPlayer.Character}
			local hit=S.Workspace:Raycast(root.Position,delta.Unit*(delta.Magnitude+2),rayParams)
			return hit and hit.Instance==S.Workspace.Terrain or false
		end

		local function topDownGoal(model,part)
			if not part or not part.Parent then return nil,nil end

			local center=part.Position
			local topY=boulderTopY(model,part)
			if not model:IsA("BasePart") then
				local ok,boxCFrame=pcall(function()
					local cf=model:GetBoundingBox()
					return cf
				end)
				if ok and boxCFrame then
					center=boxCFrame.Position
				end
			end

			if not topY then
				topY=center.Y+(part.Size.Y*0.5)
			end

			local surface=terrainSurfaceAt(center.X,center.Z)

			-- SPECIAL CASE:
			-- Rimveil / Rimeveil and Voltite can be embedded inside Terrain.
			-- They use the Money-Farm-style terrain excavation fallback before
			-- the normal Boulder hit is attempted.
			if isBuriedBoulderKind(model) and surface then
				local surfaceY=surface.Y
				local posY=math.max(surfaceY+BURIED_BOULDER_LIFT,topY+BURIED_BOULDER_LIFT)
				local pos=Vector3.new(center.X,posY,center.Z)
				local aim=Vector3.new(center.X,topY,center.Z)
				return CFrame.new(pos,aim),surface
			end

			local pos=Vector3.new(center.X,topY+TOP_CLEARANCE,center.Z)
			local aim=Vector3.new(center.X,topY,center.Z)
			return CFrame.new(pos,aim),surface
		end

		local function swingPoint(point)
			local event=Tools.digEvent(); if not event or not heldPick or typeof(point)~="Vector3" then return false end
			local name=heldPick.Name
			return pcall(function()
				for _=1,SWING_BURST do event:FireServer(name,point) end
			end)
		end
		local function boulderHitPoint(part)
			if not part or not part:IsA("BasePart") then return part and part.Position or nil end
			local root=getRoot()
			if not root then return part.Position end

			-- Do not aim at the BasePart center. For thick/large Boulders the
			-- center can be outside the tool's valid dig reach even though the
			-- visible surface is directly in front of the player. Manual clicks
			-- naturally hit that surface, so use the closest point on the part's
			-- bounding box to the character as the farm's Dig point.
			local localRoot=part.CFrame:PointToObjectSpace(root.Position)
			local half=part.Size*0.5
			local localPoint=Vector3.new(
				math.clamp(localRoot.X,-half.X,half.X),
				math.clamp(localRoot.Y,-half.Y,half.Y),
				math.clamp(localRoot.Z,-half.Z,half.Z)
			)
			return part.CFrame:PointToWorldSpace(localPoint)
		end

		local function swingDown(part,model)
			local event=Tools.digEvent(); if not event or not heldPick or not part then return false end
			if not part.Parent or not part:IsDescendantOf(S.Workspace) then return false end
			if model and (not model.Parent or not model:IsDescendantOf(S.Workspace)) then return false end

			-- Hit the visible/nearest surface instead of the part center. This
			-- fixes the case where Auto Farm is active but manual clicking works
			-- on the exact same Boulder: the old center point could be too deep
			-- for the server's Dig reach check.
			local name=heldPick.Name
			local point=boulderHitPoint(part) or part.Position
			return pcall(function()
				for _=1,SWING_BURST do
					event:FireServer(name,point)
				end
			end)
		end

		local function beginLoot(finish)
			setBoulderHitZoom(false)
			pendingFinish=finish==true
			lootSnapshot=inventoryCrystalSnapshot()
			lootDropSeen=false
			lootStartedAt=os.clock()
			lootQuietSince=0
			lootFocus=nil
			phase="loot"
			statusText="Waiting for Boulder loot"
		end
		local function stopFarm()
			setBoulderHitZoom(false)
			active=false; phase="idle"; target=nil; anchor=nil; heldPick=nil
			waitUntil=0; lastSpot=nil; pendingFinish=false; lootDropSeen=false; lootStartedAt=0; lootQuietSince=0; lootFocus=nil; table.clear(lootSnapshot)
			scanned=false; scanIndex=0; hpMark=nil; dryRounds=0; dryClock=0; lostClock=0; surfaceClock=0; terrainSurface=nil
			table.clear(blockedTargets); lastVeinSerial=Runtime.BoulderVeinSerial or 0
			swingClock=0; equipClock=0
			Move.glideStop()
			-- Restore the user's previous noclip preference only after the farm stops.
			Move.setNoclip(farmNoclipBefore and true or false)
			Mountain.setAutoGrab(Toggles.AutoRunePickup)
			statusText="Idle"
		end

		local function restart()
			task.spawn(function()
				pcall(function() LocalPlayer:Kick("Universe: restarting") end)
				for _=1,20 do
					task.wait(1.5)
					local sent=pcall(function() S.TeleportService:Teleport(game.PlaceId,LocalPlayer) end)
					if not sent then pcall(function() S.TeleportService:TeleportToPlaceInstance(game.PlaceId,game.JobId,LocalPlayer) end) end
				end
			end)
		end

		local function step(deltaTime)
			local root=getRoot(); if not root then statusText="Waiting for character"; return end
			local now=os.clock()

			if phase=="scan" then
				if not scanned then
					if scanIndex==0 then scanIndex=1; waitUntil=now+SCAN_HOLD end
					if scanIndex<=#SCAN_SPOTS then
						Move.glide(SCAN_SPOTS[scanIndex])
						statusText=string.format("Scanning %d/%d",scanIndex,#SCAN_SPOTS)
						if now>=waitUntil then scanIndex=scanIndex+1; waitUntil=now+SCAN_HOLD end
						return
					end
					scanned=true
				end
				local model,part=pickTarget()
				if not model then beginLoot(true); statusText="Final rune sweep"; return end
				target=model; anchor=part or visibleAnchor(model)
				hpMark=boulderHealth(model); dryRounds=0; dryClock=0; lostClock=0; surfaceClock=0; terrainSurface=nil
				phase="mine"; statusText="Approaching boulder"; return
			end

			if phase=="mine" then
				-- A bomb-required vein can interrupt Boulder digging.
				-- Auto Bomb ON: hold this exact Boulder until the vein is verified gone.
				-- Auto Bomb OFF: blacklist only this Boulder and immediately seek another.
				if Runtime.BoulderVeinSerial ~= lastVeinSerial then
					lastVeinSerial=Runtime.BoulderVeinSerial or lastVeinSerial
					if target then
						if Toggles.AutoBomb then
							Move.glideStop()
							statusText="Vein detected — waiting for Auto Bomb"
							return
						else
							blockedTargets[target]=true
							target=nil; anchor=nil; phase="scan"; scanned=false; scanIndex=0
							Runtime.BoulderVeinBlocked=false
							statusText="Vein detected — switching Boulder"
							return
						end
					end
				end
				if Runtime.BoulderVeinBlocked then
					if Toggles.AutoBomb then
						statusText="Waiting for vein to clear"
						return
					else
						if target then blockedTargets[target]=true end
						target=nil; anchor=nil; phase="scan"; scanned=false; scanIndex=0
						Runtime.BoulderVeinBlocked=false
						statusText="Vein blocked — switching Boulder"
						return
					end
				end
				if not target or not target.Parent or not target:IsDescendantOf(S.Workspace) then
					lastSpot=root.CFrame; beginLoot(false); return
				end
				local kind=boulderKind(target) or "Boulder"
				local hp=boulderHealth(target)
				if hp and hp<=0 then lastSpot=root.CFrame; beginLoot(false); return end
				if not anchor or not anchor.Parent or not anchor:IsDescendantOf(target) then anchor=visibleAnchor(target) end
				if not anchor then
					lostClock=lostClock+deltaTime
					if lostClock>=LOST_GRACE then lastSpot=root.CFrame; beginLoot(false); return end
					statusText="Finding boulder part"; return
				end
				lostClock=0

				-- MONEY FARM STYLE:
				-- normal Boulders: go directly above the Boulder, keep the character
				-- locked there, face downward, and hit the Boulder itself.
				-- Rimveil/Voltite: topDownGoal places the character on the terrain
				-- surface above the buried Boulder, then the same downward dig logic
				-- is used until that Boulder is actually broken.
				local goal,surface=topDownGoal(target,anchor)
				if goal then
					terrainSurface=surface
					if isBuriedBoulderKind(target) then
						-- While terrain still blocks the Boulder, stay above the
						-- excavation point. Once the Boulder is exposed, lower the
						-- character close to its top so the pickaxe can actually reach it.
						local blocked=buriedTerrainStillBlocks(root,anchor)
						if blocked then
							Move.glide(goal,surface or anchor.Position)
						else
							local topY=boulderTopY(target,anchor) or anchor.Position.Y
							local center=anchor.Position
							local ok,boxCFrame=pcall(function()
								local cf=target:GetBoundingBox()
								return cf
							end)
							if ok and boxCFrame then center=boxCFrame.Position end
							local hitPos=Vector3.new(center.X,topY+BURIED_BOULDER_HIT_LIFT,center.Z)
							local hitAim=Vector3.new(center.X,topY,center.Z)
							Move.glide(CFrame.new(hitPos,hitAim),hitAim)
						end
					else
						Move.glide(goal,anchor.Position)
					end
				end

				if heldPick==nil or heldPick.Parent~=LocalPlayer.Character then
					equipClock=0; heldPick=Tools.equipPick()
				else
					equipClock=equipClock+deltaTime
					if equipClock>=EQUIP_STEP then equipClock=0; heldPick=Tools.equipPick() or heldPick end
				end
				if not heldPick then setBoulderHitZoom(false); statusText="No pickaxe"; return end
				setBoulderHitZoom(true)

				swingClock=swingClock+deltaTime
				local baseGap=math.max(0.03,Tools.swingGap(heldPick))
				local hardBoulder=(hp and hp>=HARD_BOULDER_HP) or false
				local defaultMultiplier=(hardBoulder and HARD_DIG_MULTIPLIER or FAST_DIG_MULTIPLIER)
				-- Fast Dig is opt-in. With it OFF, this remains the exact V9 timing.
				local speedMultiplier=DHubState.boulderFastDig and math.max(1,DHubState.boulderDigSpeed/100) or 1
				local gap=baseGap*defaultMultiplier/speedMultiplier
				gap=math.max(0.025,gap)
				if swingClock>=gap then
					swingClock=swingClock-gap
					local terrainBlocks=isBuriedBoulderKind(target) and terrainSurface and buriedTerrainStillBlocks(root,anchor) or false
					if terrainBlocks then
						digBuriedTerrain(root,terrainSurface)
						statusText=string.format("Excavating terrain for %s",kind)
					else
						swingDown(anchor,target)
						statusText=string.format("Mining %s",kind)
					end
				end

				if hp then
					if hpMark==nil or hp<hpMark-0.001 then
						hpMark=hp; dryRounds=0; dryClock=0
					else
						dryClock=dryClock+deltaTime
						dryRounds=dryRounds+1
						if dryClock>=DRY_TIME or dryRounds>=DRY_ROUNDS then
							dryClock=0; dryRounds=0
							-- Re-read the closest/visible part after a dry window so a
							-- multi-part Boulder cannot stay locked to a stale anchor.
							anchor=visibleAnchor(target) or anchor
							statusText="Reacquiring boulder"
						end
					end
				end
				return
			end

			if phase=="loot" then
				local lootOrigin=lastSpot and lastSpot.Position or root.Position

				-- Stay anchored to the Boulder break spot while loot is still resolving.
				-- We deliberately do NOT advance to another Boulder just because one
				-- crystal has already reached the backpack. More eligible drops can
				-- spawn/break a little later, especially with very high Luck.
				if lootFocus and lootFocus.Parent and getAttr(lootFocus,"Collected")~=true then
					Move.glide(CFrame.new(lootFocus.Position+Vector3.new(0,5,0),lootFocus.Position),lootFocus.Position)
				elseif lastSpot then
					Move.glide(lastSpot)
				end

				if Toggles.AutoRunePickup then Mountain.grabNear(RUNE_SWEEP) end

				local inventoryConfirmed=inventoryHasNewEligibleCrystal(lootSnapshot)
				local candidates={}
				if Toggles.AutoPickup then
					pickupStep()
					local free=backpackFree()
					local scanFree=(free>0 and free or math.huge)
					candidates=pickupCandidates(scanFree,lootOrigin,LOOT_SCAN_RANGE)
					if #candidates>0 then
						lootDropSeen=true
						lootQuietSince=0
						lootFocus=candidates[1].inst
					end
				end

				if inventoryConfirmed then
					-- IMPORTANT: inventory confirmation is no longer enough to leave.
					-- First prove that there are NO remaining crystals matching the
					-- user's configured rarity/Luck filter around this Boulder.
					if #candidates>0 then
						statusText=string.format("Crystal confirmed • %d eligible loot remain",#candidates)
						return
					end

					if lootQuietSince==0 then lootQuietSince=now end
					if now-lootQuietSince<LOOT_QUIET_TIME then
						statusText="Loot sweep • waiting for late crystal drops"
						return
					end

					statusText="Loot clear • Next Boulder"
					if pendingFinish then
						phase="reset"; waitUntil=now+RESET_WAIT; statusText="Loot confirmed • area clear"
					else
						target=nil; anchor=nil; phase="scan"; scanned=false; scanIndex=0; lootFocus=nil; statusText="Loot confirmed • Next boulder"
					end
					return
				end

				if not Toggles.AutoPickup then
					if pendingFinish then phase="reset"; waitUntil=now+RESET_WAIT else target=nil; anchor=nil; phase="scan"; scanned=false; scanIndex=0 end
					return
				end

				if #candidates>0 then
					statusText="Waiting/collecting eligible Boulder crystal"
					return
				end

				-- No candidate is visible yet. Keep watching instead of immediately
				-- selecting another Boulder; high-Luck drops can take time to appear.
				if lootQuietSince==0 then lootQuietSince=now end
				statusText="Waiting for Boulder crystal drop"

				if now-lootStartedAt>=LOOT_WATCHDOG then
					if pendingFinish then
						phase="reset"; waitUntil=now+RESET_WAIT; statusText="Loot watchdog reached"
					else
						target=nil; anchor=nil; phase="scan"; scanned=false; scanIndex=0; lootFocus=nil; statusText="Loot watchdog reached • Next boulder"
					end
				end
				return
			end

			if phase=="reset" then
				if now<waitUntil then return end
				-- All selected boulders are exhausted. V2.4 adds a server method
				-- without changing the Boulder scan/mine/loot state machine.
				target=nil; anchor=nil; pendingFinish=false
				Notify("Empty Boulder\n"..tostring(Runtime.farmMethod),4)
				statusText="Server: "..tostring(Runtime.farmMethod)
				if Runtime.farmMethod=="Current Server" then
					-- Use the same reset/restart sequence as the older stable Boulder
					-- implementation. The important part is that Current Server does
					-- NOT call Net.rejoinJob() / TeleportToPlaceInstance() directly.
					-- Kick first, then use the existing restart routine used by the
					-- original script to let the client return to the same private-server
					-- context when the executor/Roblox client reconnects.
					restart()
				else
					if Net and Net.hop then Net.hop() end
				end
				waitUntil=now+18
				phase="reset"
			end
		end

		function Farm.stop() stopFarm() end
		function Farm.setTargets(value)
			table.clear(targets)
			if type(value)=="table" then
				for key,flag in pairs(value) do
					if type(key)=="string" and flag==true then targets[key]=true
					elseif type(flag)=="string" then targets[flag]=true end
				end
			elseif type(value)=="string" then targets[value]=true end
		end
		function Farm.setActive(value)
			if not value then stopFarm(); return end
			if not next(targets) then
				Notify("Pick at least one boulder",2)
				Toggles.AutoFarmBoulders=false
				if ToggleSetFn.AutoFarmBoulders then ToggleSetFn.AutoFarmBoulders(false) end
				return
			end
			-- Boulder Farm always uses noclip while active so large rocks cannot trap the character.
			Runtime.farmReturnJobId=game.JobId
			farmNoclipBefore=Toggles.Noclip==true
			Move.setNoclip(true)
			active=true; phase="scan"; waitUntil=0; target=nil; anchor=nil; lastSpot=nil
			swingClock=0; equipClock=0; hpMark=nil; dryRounds=0; dryClock=0
			lostClock=0; surfaceClock=0; terrainSurface=nil; scanned=false; scanIndex=0
			heldPick=nil; pendingFinish=false; statusText="Starting"
			Move.setFly(false); Mountain.setAutoGrab(Toggles.AutoRunePickup)
		end

		local FarmStatusLabel; local labelClock=0
		farmConn=S.RunService.Heartbeat:Connect(function(deltaTime)
			if active then
				local ok,err=pcall(step,deltaTime)
				if not ok then reportError("boulderFarm",err) end
			end
			labelClock=labelClock+deltaTime
			if labelClock>=0.25 then
				labelClock=0
				if FarmStatusLabel then FarmStatusLabel.Text=statusText end
			end
		end)
		Farm._getStatusLabel=function(lbl) FarmStatusLabel=lbl end
	end
	install()
end

-- [31.5] PREMIUM PRISMARITE FARM
-- Prismarite farm uses the PrismariteModule cache, but owns its own hidden
-- scanner. Visual Prismarite ESP is optional and is never required for farming.
local PremiumPrismarite={}
local premiumPrismariteConn
do
    local function install()
        local SEARCH_SPOTS={
            CFrame.new(-12.7105675,459.090942,818.847412,0.993408799,-0.00500036497,-0.11451605,0.000644713698,0.999275982,-0.0380407833,0.114623353,0.0377162211,0.992692769),
            CFrame.new(13.0506754,318.450409,-488.078888,-0.99998939,0.000884758658,-0.00452193478,-0.000498382491,0.954864502,0.297041386,0.00458064489,0.297040492,-0.954853892),
            CFrame.new(74.3923645,610.789368,210.838226,-0.94896102,-0.27110818,0.161162555,2.26557495e-06,0.51098305,0.859590769,-0.315393418,0.815718472,-0.484902382),
        }

        -- Keep the proven old farm timings/flight pattern.
        local SEARCH_HOLD=1.4
        local DIG_LIFT=6
        local DIG_MULT=0.42
        local PREMIUM_DIG_REACH=18
        local AREA_RADIUS=72
        local SEARCH_CYCLE_LIMIT=3
        local CLEAR_CONFIRM=2
        local SERVER_WAIT=18
        local LOOT_WATCHDOG=20

        local active=false
        local phase="idle"
        local statusText="Idle"
        local searchIndex=1
        local searchUntil=0
        local searchRounds=0
        local target=nil
        local areaCenter=nil
        local digClock=0
        local pickupClock=0
        local clearScanSerial=0
        local clearConfirm=0
        local lootActive=false
        local lootStartedAt=0
        local lootSnapshot={}
        local resetClock=0
        local heldPick=nil

        local function premiumCrystalAllowed(inst)
            if not inst or not inst.Parent or not isCrystal(inst) then return false end
            if getAttr(inst,"Collected")==true then return false end
            local hasRarity=false
            for rarity in pairs(premiumRarityFilter) do
                if rarity~="Default" and rarity~="" then
                    hasRarity=true
                    break
                end
            end
            if hasRarity and not premiumRarityFilter[crystalRarity(inst)] then return false end
            if DHubState.premiumMinLuck>0 then
                local luckPct=(tonumber(crystalLuck(inst)) or 0)*100
                if luckPct+1e-6<DHubState.premiumMinLuck then return false end
            end
            return true
        end

        local function pickupAtArea(origin)
            if not Toggles.PremiumAutoPickup then return 0,false end
            local now=os.clock()
            if now-pickupClock<0.10 then return 0,false end
            pickupClock=now

            local free=backpackFree()
            if free<=0 then
                statusText="Prismarite: Backpack full"
                return 0,true
            end

            local candidates={}
            local seen={}
            local function consider(inst)
                if not inst or seen[inst] or not inst.Parent then return end
                seen[inst]=true
                if not premiumCrystalAllowed(inst) then return end
                local distance=surfaceDistance(inst,origin)
                if distance>CFG.PICK.range then return end
                local weight=crystalWeight(inst)
                if weight>free then return end
                candidates[#candidates+1]={
                    inst=inst,
                    prompt=crystalPrompt(inst),
                    weight=weight,
                    value=crystalValue(inst),
                    distance=distance
                }
            end

            local hits=nearbyCrystalParts(origin,CFG.PICK.range+CFG.PICK.pad)
            if hits then
                for _,part in ipairs(hits) do consider(part) end
            end

            eachContainer(function(container)
                for _,child in ipairs(container:GetChildren()) do
                    if child:IsA("BasePart") then
                        consider(child)
                    elseif child:IsA("Model") then
                        for _,inner in ipairs(child:GetChildren()) do
                            if inner:IsA("BasePart") then consider(inner) end
                        end
                    end
                end
            end)

            for inst in pairs(Cache.registry) do consider(inst) end

            table.sort(candidates,function(a,b)
                if a.value==b.value then return a.distance<b.distance end
                return a.value>b.value
            end)

            local budget=free
            local grabbed=0
            for _,entry in ipairs(candidates) do
                if entry.weight<=budget then
                    if entry.prompt then instantPromptPatch(entry.prompt) end
                    if grabCrystal(entry.inst,entry.prompt,true) then
                        Cache.claimed[entry.inst]=now
                        budget=budget-entry.weight
                        grabbed=grabbed+1
                    end
                end
                if grabbed>=8 then break end
            end
            return grabbed,#candidates>0
        end

        -- Keep the old working Dig burst: one swing triggers four nearby voxel
        -- aims, which is much more reliable for a Prismarite cluster.
        local function digAt(pos)
            local event=Tools.digEvent()
            if not event or not heldPick or typeof(pos)~="Vector3" then return false end

            local root=getRoot()
            local aim=pos
            if root then
                local delta=pos-root.Position
                if delta.Magnitude>PREMIUM_DIG_REACH then
                    aim=root.Position+delta.Unit*PREMIUM_DIG_REACH
                end
            end

            local name=heldPick.Name
            return pcall(function()
                for i=0,3 do
                    event:FireServer(name,aim-Vector3.new(0,i*0.7,0))
                end
            end)
        end

        -- Farm target selection is deliberately independent from the visual ESP.
        local function nearestTarget(rootPosition)
            local list=PrismariteModule.getAllTargets()
            local best,bestDistance
            for _,entry in ipairs(list) do
                local distance=(entry.position-rootPosition).Magnitude
                if not bestDistance or distance<bestDistance then
                    best=entry
                    bestDistance=distance
                end
            end
            if best then best.distance=bestDistance end
            return best
        end

        local function targetInArea(rootPosition)
            if not areaCenter then return nil end
            local list=PrismariteModule.getAllTargets()
            local best,bestDistance
            for _,entry in ipairs(list) do
                local fromArea=(entry.position-areaCenter).Magnitude
                local fromPlayer=(entry.position-rootPosition).Magnitude
                if fromArea<=AREA_RADIUS and fromPlayer<=math.max(AREA_RADIUS,PREMIUM_DIG_REACH+20) then
                    if not bestDistance or fromArea<bestDistance then
                        best=entry
                        bestDistance=fromArea
                    end
                end
            end
            if best then best.distance=(best.position-rootPosition).Magnitude end
            return best
        end

        local function stopFarm()
            active=false
            autoFarmPrismariteActive=false
            Runtime.PrismariteFarmActive=false
            phase="idle"
            statusText="Idle"
            searchIndex=1
            searchUntil=0
            searchRounds=0
            target=nil
            areaCenter=nil
            digClock=0
            pickupClock=0
            clearScanSerial=0
            clearConfirm=0
            lootActive=false
            lootStartedAt=0
            table.clear(lootSnapshot)
            resetClock=0
            heldPick=nil

            Move.glideStop()
            if not Toggles.PrismariteEsp then
                PrismariteModule.setScannerActive(false)
            end
            Move.setFly(Toggles.Fly)
            Move.setNoclip(Toggles.Noclip)
        end

        local function restartCurrentServer()
            task.spawn(function()
                pcall(function()
                    LocalPlayer:Kick("D-HUB Premium Prismarite: restarting")
                end)
                for _=1,20 do
                    task.wait(1.5)
                    local sent=pcall(function()
                        S.TeleportService:Teleport(game.PlaceId,LocalPlayer)
                    end)
                    if not sent then
                        pcall(function()
                            S.TeleportService:TeleportToPlaceInstance(game.PlaceId,game.JobId,LocalPlayer)
                        end)
                    end
                end
            end)
        end

        local function serverReset()
            Notify("No Prismarite left\n"..premiumFarmMethod,4)
            statusText="Server: "..premiumFarmMethod
            if DHubState.premiumFarmMethod=="Current Server" then
                restartCurrentServer()
            elseif Net and Net.hop then
                Net.hop()
            end
            resetClock=os.clock()+SERVER_WAIT
            phase="reset"
        end

        local function step(dt)
            local root=getRoot()
            if not root then
                statusText="Waiting for character"
                return
            end

            local now=os.clock()

            if phase=="search" then
                local found=nearestTarget(root.Position)
                if found then
                    target=found
                    areaCenter=found.position
                    digClock=0
                    clearConfirm=0
                    clearScanSerial=PrismariteModule.getScanSerial()
                    lootActive=false
                    lootStartedAt=0
                    table.clear(lootSnapshot)
                    phase="mine"
                    statusText="Prismarite target acquired"
                    -- Do NOT call glideStop here. The next heartbeat immediately
                    -- retargets the same Glide controller to the Prismarite.
                    return
                end

                Move.setNoclip(true)
                local destination=SEARCH_SPOTS[searchIndex]
                if destination then
                    Move.glide(destination)
                end
                statusText=string.format(
                    "Flying + scanning Prismarite %d/%d",
                    searchIndex,#SEARCH_SPOTS
                )

                if searchUntil==0 then
                    searchUntil=now+SEARCH_HOLD
                end
                if now>=searchUntil then
                    searchIndex=searchIndex+1
                    searchUntil=now+SEARCH_HOLD
                    if searchIndex>#SEARCH_SPOTS then
                        searchIndex=1
                        searchRounds=searchRounds+1
                        if searchRounds>=SEARCH_CYCLE_LIMIT then
                            phase="server"
                            return
                        end
                    end
                end
                return
            end

            if phase=="mine" then
                Move.setNoclip(true)

                local current=targetInArea(root.Position)
                if current then
                    target=current
                    areaCenter=areaCenter:Lerp(current.position,0.20)

                    Move.glide(
                        CFrame.new(
                            current.position+Vector3.new(0,DIG_LIFT,0),
                            current.position
                        ),
                        current.position
                    )

                    if heldPick==nil or heldPick.Parent~=LocalPlayer.Character then
                        heldPick=Tools.equipPick()
                    end
                    if not heldPick then
                        statusText="No pickaxe"
                        return
                    end

                    digClock=digClock+dt
                    local gap=math.max(0.025,Tools.swingGap(heldPick)*DIG_MULT)
                    if digClock>=gap then
                        digClock=digClock-gap
                        digAt(current.position)
                    end

                    statusText=string.format(
                        "Mining Prismarite • %d voxels",
                        current.count or 0
                    )
                    return
                end

                -- A cluster disappeared from the current scan. Do not loot on
                -- the first empty result; require fresh scanner passes.
                Move.glide(
                    CFrame.new(areaCenter+Vector3.new(0,DIG_LIFT,0),areaCenter),
                    areaCenter
                )

                local serial=PrismariteModule.getScanSerial()
                if serial>clearScanSerial then
                    clearScanSerial=serial
                    clearConfirm=clearConfirm+1
                end

                if clearConfirm<CLEAR_CONFIRM then
                    statusText="Confirming Prismarite clear"
                    return
                end

                -- Only after the Prismarite cluster has actually disappeared
                -- from fresh scans do we start looting its drops.
                if Toggles.PremiumAutoPickup then
                    if not lootActive then
                        lootSnapshot=inventoryCrystalSnapshot()
                        lootActive=true
                        lootStartedAt=now
                    end

                    local grabbed,hasCandidates=pickupAtArea(areaCenter)
                    local confirmed=inventoryHasNewEligibleCrystal(lootSnapshot)

                    if grabbed>0 or hasCandidates then
                        statusText=string.format("Prismarite • Pickup %d",grabbed)
                        return
                    end

                    if not confirmed and now-lootStartedAt<LOOT_WATCHDOG then
                        statusText="Waiting for Prismarite drop"
                        return
                    end
                end

                target=nil
                areaCenter=nil
                clearConfirm=0
                clearScanSerial=PrismariteModule.getScanSerial()
                lootActive=false
                lootStartedAt=0
                table.clear(lootSnapshot)
                searchIndex=1
                searchUntil=0
                searchRounds=0
                phase="search"
                statusText="Prismarite cleared • finding next"
                return
            end

            if phase=="server" then
                if now<resetClock then return end
                serverReset()
                return
            end

            if phase=="reset" then
                if now<resetClock then return end
                phase="search"
                searchIndex=1
                searchUntil=0
                searchRounds=0
                target=nil
                areaCenter=nil
                clearConfirm=0
                clearScanSerial=PrismariteModule.getScanSerial()
                lootActive=false
                lootStartedAt=0
                table.clear(lootSnapshot)
                return
            end
        end

        function PremiumPrismarite.stop()
            stopFarm()
        end

        function PremiumPrismarite.setActive(value)
            if not value then
                stopFarm()
                return
            end

            active=true
            autoFarmPrismariteActive=true
            Toggles.AutoFarmPrismarite=true
            Runtime.PrismariteFarmActive=true
            phase="search"
            statusText="Starting Prismarite farm"

            searchIndex=1
            searchUntil=0
            searchRounds=0
            target=nil
            areaCenter=nil
            digClock=0
            pickupClock=0
            clearConfirm=0
            clearScanSerial=PrismariteModule.getScanSerial()
            lootActive=false
            lootStartedAt=0
            table.clear(lootSnapshot)
            resetClock=0
            heldPick=nil

            Move.setNoclip(true)
            -- Hidden scanner is always enabled for Farm; visual ESP remains
            -- completely independent.
            PrismariteModule.setScannerActive(true)
        end

        PremiumPrismarite._getStatusLabel=function(lbl)
            task.spawn(function()
                while lbl and lbl.Parent do
                    lbl.Text=active and statusText or "Idle"
                    task.wait(0.25)
                end
            end)
        end

        premiumPrismariteConn=S.RunService.Heartbeat:Connect(function(dt)
            if active then
                local ok,err=pcall(step,dt)
                if not ok then reportError("premiumPrismarite",err) end
            end
        end)
    end
    install()
end

-- [32] MONEY FARM
local Money={}
local moneyConn
do
	local function install()
		local SCAN_SPOTS={
			CFrame.new(-12.7105675,459.090942,818.847412,0.993408799,-0.00500036497,-0.11451605,0.000644713698,0.999275982,-0.0380407833,0.114623353,0.0377162211,0.992692769),
			CFrame.new(13.0506754,318.450409,-488.078888,-0.99998939,0.000884758658,-0.00452193478,-0.000498382491,0.954864502,0.297041386,0.00458064489,0.297040492,-0.954853892),
			CFrame.new(74.3923645,610.789368,210.838226,-0.94896102,-0.27110818,0.161162555,2.26557495e-06,0.51098305,0.859590769,-0.315393418,0.815718472,-0.484902382),
		}
		local SCAN_HOLD=1.4; local PEAK_GAP=10; local PEAK_STEP=48; local PEAK_RINGS=12
		local COLUMN_STEP=8; local RING_MAX=6; local RAY_TOP=120; local RAY_DROP=60
		local ZONE_PAD=12; local SURFACE_GAP=0.15; local COLUMN_DRY=40
		local DIG_BURST=7; local DIG_SINK=1.2; local DIG_LIFT=6; local DIG_REACH=12
		local DIG_REFRESH=5; local COLLECT_RANGE=32000; local COLLECT_LIFT=5
		local COLLECT_GAP=0.12; local GRAB_GAP=0.05; local EQUIP_STEP=1
		local SELL_MARK=0.5; local SELL_WAIT=7
		local OFFSETS={Vector2.new(0,0)}
		local PEAK_OFFSETS={Vector2.new(0,0)}
		for ring=1,RING_MAX do
			local slices=ring*6
			for slice=0,slices-1 do
				local angle=slice/slices*math.pi*2; local reach=ring*COLUMN_STEP
				OFFSETS[#OFFSETS+1]=Vector2.new(math.cos(angle)*reach,math.sin(angle)*reach)
			end
		end
		for ring=1,PEAK_RINGS do
			local slices=ring*3
			for slice=0,slices-1 do
				local angle=slice/slices*math.pi*2; local reach=ring*PEAK_STEP
				PEAK_OFFSETS[#PEAK_OFFSETS+1]=Vector2.new(math.cos(angle)*reach,math.sin(angle)*reach)
			end
		end
		local surfaceParams=RaycastParams.new()
		surfaceParams.FilterType=Enum.RaycastFilterType.Include
		surfaceParams.FilterDescendantsInstances={S.Workspace.Terrain}
		surfaceParams.IgnoreWater=true
		local digParams=RaycastParams.new()
		digParams.FilterType=Enum.RaycastFilterType.Include
		digParams.IgnoreWater=true
		local digClock=0
		local function digFilter(now)
			if digClock>0 and now-digClock<DIG_REFRESH then return end
			digClock=now
			local list={S.Workspace.Terrain}
			local deco=S.Workspace:FindFirstChild("MountainDecorations")
			local boulders=deco and deco:FindFirstChild("Boulders")
			if boulders then list[#list+1]=boulders end
			local test=S.Workspace:FindFirstChild("BoulderTest"); if test then list[#list+1]=test end
			digParams.FilterDescendantsInstances=list
		end
		local function pickReach(tool)
			local override=tool and tonumber(getAttr(tool,"OverrideMaxReach"))
			return (override or DIG_REACH)+3
		end
		local function aimPoint(origin,spot,reach,now)
			digFilter(now)
			local goals={spot,spot-Vector3.new(0,2,0),origin-Vector3.new(0,reach,0)}
			for _,goal in ipairs(goals) do
				local delta=goal-origin; local distance=delta.Magnitude
				if distance>0.05 then
					local span=math.min(distance+4,reach)
					local hit=S.Workspace:Raycast(origin,delta.Unit*span,digParams)
					if hit then return hit.Position end
				end
			end
			local delta=spot-origin
			if delta.Magnitude<=reach then return spot end
			return origin+delta.Unit*reach
		end
		local active=false; local autoSell=false; local heldPick
		local loot,lootClock,grabClock=nil,0,0
		local lootScanClock=0
		local lootHp,lootMax
		local digTarget,columnY
		local columnDry,columnSwings=0,0
		local surfaceClock,peakClock=0,0
		local scanIndex,scanUntil=0,0; local loaded=false
		local swingClock,equipClock=0,0
		local sellSpot,sellUntil=nil,0; local lootBlocked=false
		local statusText="Idle"
		local function zoneBase()
			local base=S.Workspace:GetAttribute("MountainBaseY")
			return typeof(base)=="number" and base or 0
		end
		local function zonePeak()
			local peak=S.Workspace:GetAttribute("MountainPeakY")
			return typeof(peak)=="number" and peak or zoneBase()+900
		end
		local function mountainSpot()
			local cx=S.Workspace:GetAttribute("MountainCenterX")
			local cz=S.Workspace:GetAttribute("MountainCenterZ")
			if typeof(cx)=="number" and typeof(cz)=="number" then
				local base=S.Workspace:GetAttribute("MountainBaseY")
				local peak=S.Workspace:GetAttribute("MountainPeakY")
				local height=700
				if typeof(base)=="number" and typeof(peak)=="number" then height=base+(peak-base)*0.55 end
				return Vector3.new(cx,height,cz)
			end
			local things=S.Workspace:FindFirstChild("Things")
			local zones=things and things:FindFirstChild("MountainZones")
			if zones then
				for _,child in ipairs(zones:GetChildren()) do
					if child:IsA("BasePart") and child.Name=="MountainZone" then return child.Position end
				end
			end
			return nil
		end
		local function mountainSpan()
			local r=S.Workspace:GetAttribute("MountainRadius")
			if typeof(r)=="number" and r>20 then return r end; return 150
		end
		local function zoneCenter()
			local spot=mountainSpot(); if spot then return Vector2.new(spot.X,spot.Z) end; return nil
		end
		local function insideZone(x,z)
			local center=zoneCenter(); if not center then return false end
			return (Vector2.new(x,z)-center).Magnitude<=mountainSpan()+ZONE_PAD
		end
		local function surfaceAt(x,z)
			if not insideZone(x,z) then return nil end
			local base=zoneBase(); local top=zonePeak()+RAY_TOP
			local hit=S.Workspace:Raycast(Vector3.new(x,top,z),Vector3.new(0,-(top-base+RAY_DROP),0),surfaceParams)
			if not hit or hit.Position.Y<=base+1 then return nil end
			return hit.Position
		end
		local function farmOrigin(root)
			if insideZone(root.Position.X,root.Position.Z) then return root.Position end
			return mountainSpot() or root.Position
		end
		local function highestColumn(origin,offsets)
			local best
			for _,offset in ipairs(offsets) do
				local spot=surfaceAt(origin.X+offset.X,origin.Z+offset.Y)
				if spot and (not best or spot.Y>best.Y) then best=spot end
			end
			return best
		end
		local function findDigTarget(origin,now)
			local center=mountainSpot()
			if center and now-peakClock>=PEAK_GAP then
				peakClock=now; local high=highestColumn(center,PEAK_OFFSETS); if high then return high end
			end
			local spot=highestColumn(origin,OFFSETS); if spot then return spot end
			if center then peakClock=now; return highestColumn(center,PEAK_OFFSETS) end
			return nil
		end
		local function swing(spot)
			local event=Tools.digEvent(); if not event or not heldPick then return false end
			local name=heldPick.Name; local root=getRoot(); local aim=spot
			if root then aim=aimPoint(root.Position,spot,pickReach(heldPick),os.clock()) or spot end
			return pcall(function()
				for step=0,DIG_BURST-1 do event:FireServer(name,aim-Vector3.new(0,step*DIG_SINK,0)) end
			end)
		end
		local function bagRatio()
			local cap=backpackCapacity(); if cap==math.huge or cap<=0 then return 0 end
			return backpackWeight()/cap
		end

		-- ============================================================
		-- CRYSTAL SCANNER
		-- ============================================================
		-- This scanner is intentionally reused by Money Farm and the
		-- "Refresh Crystal" UI. It scans the game's crystal containers
		-- plus the live registry, without doing Workspace:GetDescendants()
		-- every frame.
		local function scanCrystalEntries()
			local byName={}
			local function consider(inst)
				if not inst or not inst.Parent or not isCrystal(inst) then return end
				if getAttr(inst,"Collected")==true then return end
				local value=crystalValue(inst)
				if value < minValue then return end
				local name=crystalName(inst)
				if type(name)~="string" or name=="" then return end
				local rarity=crystalRarity(inst)
				local current=byName[name]
				if not current or value>current.value then
					byName[name]={name=name,rarity=rarity,value=value}
				end
			end
			eachContainer(function(c)
				for _,child in ipairs(c:GetChildren()) do
					if child:IsA("BasePart") then
						consider(child)
					elseif child:IsA("Model") then
						for _,inner in ipairs(child:GetChildren()) do
							if inner:IsA("BasePart") then consider(inner) end
						end
					end
				end
			end)
			for inst in pairs(Cache.registry) do consider(inst) end
			local list={}
			for _,entry in pairs(byName) do list[#list+1]=entry end
			table.sort(list,function(a,b)
				if a.value==b.value then return string.lower(a.name)<string.lower(b.name) end
				return a.value>b.value
			end)
			return list
		end

		local function findLoot(free,origin)
			local best,bestValue,bestDistance; local blocked=false; local seen={}
			local function consider(inst)
				if not inst or seen[inst] then return end; seen[inst]=true
				if not inst.Parent or not isCrystal(inst) or getAttr(inst,"Collected")==true then return end
				local value=crystalValue(inst)
				if not meetsFarmFilter(inst,value) then return end
				local distance=(inst.Position-origin).Magnitude; if distance>COLLECT_RANGE then return end
				local weight=crystalWeight(inst)
				if weight>free then blocked=true; return end
				local better=not best or value>bestValue
				if not better and value==bestValue and distance<bestDistance then better=true end
				if better then best=inst; bestValue=value; bestDistance=distance end
			end
			eachContainer(function(c)
				for _, child in ipairs(c:GetChildren()) do
					if child:IsA("BasePart") then consider(child)
					elseif child:IsA("Model") then
						for _, inner in ipairs(child:GetChildren()) do if inner:IsA("BasePart") then consider(inner) end end
					end
				end
			end)
			for inst in pairs(Cache.registry) do consider(inst) end
			return best,blocked
		end

		function Money.scanEligibleCrystals()
			return scanCrystalEntries()
		end

		local function stopMoney()
			active=false; digTarget=nil; columnY=nil; loaded=false
			Move.glideStop(); scanIndex=0; loot=nil; lootHp=nil; lootMax=nil; lootScanClock=0
			lootBlocked=false; sellSpot=nil; sellUntil=0; heldPick=nil; statusText="Idle"
			Move.setFly(Toggles.Fly); Move.setNoclip(Toggles.Noclip)
			Mountain.setAutoGrab(Toggles.AutoRunePickup)
		end
		local function step(deltaTime)
			local root=getRoot(); if not root then statusText="Waiting for character"; return end
			local now=os.clock()
			if not loaded then
				if scanIndex==0 then scanIndex=1; scanUntil=now+SCAN_HOLD end
				if scanIndex<=#SCAN_SPOTS then
					Move.glide(SCAN_SPOTS[scanIndex])
					statusText=string.format("Loading terrain %d/%d",scanIndex,#SCAN_SPOTS)
					if now>=scanUntil then scanIndex=scanIndex+1; scanUntil=now+SCAN_HOLD end; return
				end
				loaded=true; peakClock=0
			end
			if sellUntil>0 then
				if now<sellUntil then statusText="Selling"; return end
				sellUntil=0
				if sellSpot then applyPivot(sellSpot); sellSpot=nil end
				digTarget=nil; columnY=nil; surfaceClock=0
			end
			-- Removed general auto-sell from here, moved to global scheduler. 
			-- However, keeping the emergency fail-safe if loot blocked by full bag.
			if autoSell and lootBlocked and backpackFree()<=0 then
				sellSpot=root.CFrame
				if doSell() then lootBlocked=false; sellUntil=now+SELL_WAIT; statusText="Selling"; return end
			end

			-- Continuously rescan for eligible crystals while the terrain column
			-- is being dug. We do NOT scan every frame: this interval is frequent
			-- enough to catch newly spawned high-value crystals without turning
			-- the farm into a Workspace scanning loop.
			local free=backpackFree()
			if not loot and now-lootScanClock>=0.18 then
				lootScanClock=now
				local candidate,blocked=findLoot(free,root.Position)
				lootBlocked=blocked
				if candidate then
					loot=candidate
					local hp=tonumber(getAttr(loot,"MinedHP")); lootHp=hp; lootMax=hp
					Move.glideStop()
					statusText="High-value crystal found"
				end
			end
			swingClock=swingClock+deltaTime
			if loot then
				-- MONEY FARM PICKUP MODE:
				-- Never mine/break the selected crystal. Use the exact same
				-- pickup helper used by Boulder loot, regardless of rarity.
				if not loot.Parent or getAttr(loot,"Collected")==true then
					loot=nil; lootHp=nil; lootMax=nil
				else
					local spot=loot.Position
					Move.glide(CFrame.new(spot+Vector3.new(0,COLLECT_LIFT,0),spot),spot)
					requestStream(spot)
					if now-grabClock>=GRAB_GAP then
						grabClock=now
						local prompt=crystalPrompt(loot)
						if prompt then instantPromptPatch(prompt) end
						if grabCrystal(loot,prompt,true) then
							Cache.claimed[loot]=now
						end
					end
					statusText="Collecting crystal"
				end
				return
			end

			-- No eligible crystal is currently targeted. Preserve the original
			-- Money Farm digging fallback exactly as before.
			if heldPick==nil or heldPick.Parent~=LocalPlayer.Character then
				equipClock=0; heldPick=Tools.equipPick()
			else
				equipClock=equipClock+deltaTime
				if equipClock>=EQUIP_STEP then equipClock=0; heldPick=Tools.equipPick() or heldPick end
			end
			if not heldPick then statusText="No pickaxe"; return end
			local swingNeed=math.max(0.02,Tools.swingGap(heldPick)*0.4)
			local canSwing=swingClock>=swingNeed
			local origin=farmOrigin(root)
			if digTarget and now-surfaceClock>=SURFACE_GAP then
				surfaceClock=now
				local spot=surfaceAt(digTarget.X,digTarget.Z)
				if not spot then digTarget=nil; columnY=nil; columnDry=0; columnSwings=0
				else
					if not columnY or spot.Y<columnY-0.05 then columnDry=0 else columnDry=columnDry+columnSwings end
					columnSwings=0; columnY=spot.Y; digTarget=spot
					if columnDry>=COLUMN_DRY then digTarget=nil; columnY=nil; columnDry=0 end
				end
			end
			if not digTarget then
				local spot=findDigTarget(origin,now) or surfaceAt(origin.X,origin.Z)
				if not spot then
					requestStream(origin)
					if canSwing then swingClock=swingClock-swingNeed; swing(root.Position-Vector3.new(0,DIG_REACH*0.5,0)) end
					statusText="Loading terrain"; return
				end
				digTarget=spot; columnY=spot.Y; columnDry=0; columnSwings=0; surfaceClock=now
			end
			Move.glide(CFrame.new(digTarget+Vector3.new(0,DIG_LIFT,0),digTarget),digTarget)
			if canSwing then swingClock=swingClock-swingNeed; columnSwings=columnSwings+1; swing(digTarget) end
			statusText=string.format("Mining surface at %dm",math.floor(digTarget.Y))
		end
		function Money.stop() stopMoney() end
		function Money.setActive(value)
			if not value then stopMoney(); return end
			active=true; digTarget=nil; columnY=nil; columnDry=0; columnSwings=0
			surfaceClock=0; peakClock=0; scanIndex=0; scanUntil=0; loaded=true
			loot=nil; lootClock=0; lootScanClock=0; lootHp=nil; lootMax=nil; lootBlocked=false
			swingClock=0; equipClock=0; sellSpot=nil; sellUntil=0; heldPick=nil; statusText="Starting"
			Move.setFly(false); Move.setNoclip(true); Mountain.setAutoGrab(true)
		end
		function Money.setAutoSell(v) autoSell=v end
		local MoneyStatusLabel; local labelClock=0
		moneyConn=S.RunService.Heartbeat:Connect(function(deltaTime)
			if active then
				local ok,err=pcall(step,deltaTime)
				if not ok then reportError("moneyFarm",err) end
			end
			labelClock=labelClock+deltaTime
			if labelClock>=0.25 then
				labelClock=0
				if MoneyStatusLabel then MoneyStatusLabel.Text=statusText end
			end
		end)
		Money._getStatusLabel=function(lbl) MoneyStatusLabel=lbl end
	end
	install()
end

-- [33] AUTO BOMB MODULE
local AutoBomb = {}
local autoBombConn
do
	local function install()
		local CONFIG = {
			STEP = 0.12,
			ACTIVATE_COOLDOWN = 0.85,
			FUSE_BUFFER = 0.65,
			EXPLOSION_TIMEOUT = 6.0,
			MAX_RETRY = 2,
			RETRY_DELAY = 0.45,
			EQUIP_TIMEOUT = 1.50,
			POST_EXPLOSION_PICK_DELAY = 0.18,
			NO_BOMB_TELEPORT_COOLDOWN = 1.5,
			TELEPORT_SURFACE_HEIGHT = 5,
			NOTIFICATION_TARGET_RADIUS = 10,
			TARGET_SAMPLE_STEP = 2,
			TARGET_SAMPLE_DEPTH = 10,
			TOOL_ACTIVATE_DELAY = 0.10,
			REMOTE_RETRY_DELAY = 0.20,
		}
		local STATE = {
			IDLE="IDLE", WAITING_NOTIFICATION="WAITING_NOTIFICATION", READY="READY",
			EQUIPPING="EQUIPPING", ACTIVATING="ACTIVATING",
			WAITING_EXPLOSION="WAITING_EXPLOSION", VERIFYING="VERIFYING",
			SUCCESS="SUCCESS", RETRY="RETRY", FAILED="FAILED",
		}
		local state = STATE.IDLE
		local statusText = "Idle"
		local bombStatusLabel
		local currentBomb, currentMaterial, currentPosition
		local equippedBombTool
		local attempt, retryAt = 0, 0
		local lastActivation, activationAt, expectedExplosionAt = 0, 0
		local accumulator, labelClock = 0, 0
		local requiredBombTier, requiredBombId
		local notificationClock = 0
		local lastNotificationText = ""
		local lastNoBombTeleport = 0
		local activationConfirmed = false
		local function safeNotify(text, duration) pcall(function() Notify(text, duration or 2) end) end
		local function setState(newState, text)
			state = newState
			statusText = text or newState
		end
		local function resetAttempt(keepRequirement)
			currentBomb = nil; currentMaterial = nil; currentPosition = nil; equippedBombTool = nil
			attempt = 0; retryAt = 0; activationAt = 0; expectedExplosionAt = 0; activationConfirmed = false
			if not keepRequirement then requiredBombTier = nil; requiredBombId = nil end
		end
		local function bombToolMatches(tool, bombId)
			if not tool or not tool:IsA("Tool") or not bombId then return false end
			local id = getAttr(tool,"BombId") or getAttr(tool,"ItemId") or getAttr(tool,"Id")
			if tostring(id) == bombId then return true end
			if tool.Name == bombId then return true end
			local display = BOMB_CONFIG[bombId] and BOMB_CONFIG[bombId].displayName
			if display and (tool.Name == display or tool.Name:gsub(" ",""):lower() == bombId:gsub(" ",""):lower()) then return true end
			local lower = tool.Name:lower():gsub("[%s_%-]","")
			local wanted = bombId:lower():gsub("[%s_%-]","")
			return lower:find("bomb",1,true) ~= nil and lower:find(wanted,1,true) ~= nil
		end
		local function findBombTool(bombId)
			local char = LocalPlayer.Character
			if char then
				local held = char:FindFirstChildOfClass("Tool")
				if bombToolMatches(held,bombId) then return held end
			end
			local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
			if bp then
				for _,tool in ipairs(bp:GetChildren()) do if bombToolMatches(tool,bombId) then return tool end end
			end
			return nil
		end
		local function equipBombTool(bombId)
			local char = LocalPlayer.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if not char or not hum then return nil end
			local tool = findBombTool(bombId)
			if not tool then return nil end
			if tool.Parent ~= char then pcall(function() hum:EquipTool(tool) end) end
			local deadline = os.clock() + CONFIG.EQUIP_TIMEOUT
			while os.clock() < deadline do
				local held = char:FindFirstChildOfClass("Tool")
				if held and bombToolMatches(held,bombId) then return held end
				task.wait()
			end
			return nil
		end
		local function equipPickaxeAfterBomb()
			task.wait(CONFIG.POST_EXPLOSION_PICK_DELAY)
			local ok, tool = pcall(function() return Tools.equipPick() end)
			return ok and tool or nil
		end
		local function getBestBombForRequirement(requiredTier)
			requiredTier = tonumber(requiredTier) or 1
			local bestId, bestTier, bestCount = nil, math.huge, 0
			for bombId in pairs(BOMB_CONFIG) do
				local tier = BOMB_TIER[bombId] or 0
				local count = getBombCount(bombId)
				if tier >= requiredTier and count > 0 and tier < bestTier then
					bestId, bestTier, bestCount = bombId, tier, count
				end
			end
			return bestId,bestTier,bestCount
		end
		local function parseBombRequirement(text)
			if type(text) ~= "string" then return nil,nil end
			local lower = text:lower()
			local names = {
				{ "Agony Bomb", "AgonyBomb", 8 }, { "Time Bomb", "TimeBomb", 7 },
				{ "Poison Bomb", "PoisonBomb", 6 }, { "Thunder Bomb", "ThunderBomb", 5 },
				{ "Fire Bomb", "FireBomb", 4 }, { "Ice Bomb", "IceBomb", 3 },
				{ "Wind Bomb", "WindBomb", 2 }, { "Classic Bomb", "ClassicBomb", 1 },
			}
			for _,entry in ipairs(names) do if lower:find(entry[1]:lower(),1,true) then return entry[2],entry[3] end end
			return nil,nil
		end
		local function teleportToFreshSurface()
			local now=os.clock()
			if now-lastNoBombTeleport < CONFIG.NO_BOMB_TELEPORT_COOLDOWN then return false end
			local root=getRoot()
			if not root then return false end
			local cx=S.Workspace:GetAttribute("MountainCenterX")
			local cz=S.Workspace:GetAttribute("MountainCenterZ")
			local base=S.Workspace:GetAttribute("MountainBaseY")
			local peak=S.Workspace:GetAttribute("MountainPeakY")
			local radius=S.Workspace:GetAttribute("MountainRadius")
			if typeof(cx)~="number" or typeof(cz)~="number" then return false end
			base=typeof(base)=="number" and base or 0
			peak=typeof(peak)=="number" and peak or (base+900)
			radius=typeof(radius)=="number" and math.max(radius-10,20) or 120
			local rayParams=RaycastParams.new()
			rayParams.FilterType=Enum.RaycastFilterType.Include
			rayParams.FilterDescendantsInstances={S.Workspace.Terrain}
			rayParams.IgnoreWater=true
			for _=1,12 do
				local angle=math.random()*math.pi*2
				local r=math.sqrt(math.random())*radius
				local x=cx+math.cos(angle)*r
				local z=cz+math.sin(angle)*r
				local top=peak+80
				local hit=S.Workspace:Raycast(Vector3.new(x,top,z),Vector3.new(0,-(top-base+120),0),rayParams)
				if hit and hit.Position.Y>base+5 then
					local target=hit.Position+Vector3.new(0,CONFIG.TELEPORT_SURFACE_HEIGHT,0)
					if applyPivot(CFrame.new(target,target-Vector3.new(0,1,0))) then
						lastNoBombTeleport=now; requestStream(target); return true
					end
				end
			end
			return false
		end
		local function sampleNearbyBombTarget(rootPosition)
			if not rootPosition then return nil,nil end
			local bestMat,bestPos,bestDistance
			local offsets={
				Vector3.new(0,0,0), Vector3.new(0,-2,0), Vector3.new(0,-4,0), Vector3.new(0,-6,0),
				Vector3.new(0,-8,0), Vector3.new(0,-10,0), Vector3.new(0,-12,0), Vector3.new(0,-14,0),
				Vector3.new(0,-16,0), Vector3.new(0,-18,0), Vector3.new(2,-6,0), Vector3.new(-2,-6,0),
				Vector3.new(0,-6,2), Vector3.new(0,-6,-2), Vector3.new(2,-12,0), Vector3.new(-2,-12,0),
				Vector3.new(0,-12,2), Vector3.new(0,-12,-2),
			}
			for _,offset in ipairs(offsets) do
				local pos=rootPosition+offset
				local mat=sampleTerrainMaterial(pos)
				if mat and isBombMaterial(mat) then
					local d=offset.Magnitude
					if bestDistance==nil or d<bestDistance then bestMat,bestPos,bestDistance=mat,pos,d end
				end
			end
			return bestMat,bestPos
		end
		local function getNotificationTarget()
			local root=getRoot()
			if not root then return nil,nil end
			local mat,pos=sampleNearbyBombTarget(root.Position)
			if mat and pos then return mat,pos end
			return nil,root.Position+Vector3.new(0,-6,0)
		end
		local function activateBomb(bombId, position)
			if not bombId or not position then return false end
			if os.clock() - lastActivation < CONFIG.ACTIVATE_COOLDOWN then return false end
			if getBombCount(bombId) <= 0 then setState(STATE.FAILED,"Need "..tostring(bombId)); return false end
			setState(STATE.EQUIPPING,"Equipping "..tostring(bombId))
			local tool=equippedBombTool
			if not tool or not bombToolMatches(tool,bombId) or tool.Parent~=LocalPlayer.Character then tool=equipBombTool(bombId) end
			if not tool then statusText="Bomb tool not found"; return false end
			equippedBombTool=tool
			local toolActivated=pcall(function() tool:Activate() end)
			if not toolActivated then statusText="Bomb tool activation failed"; return false end
			task.wait(CONFIG.TOOL_ACTIVATE_DELAY)
			if not RMT.BombActivate or not RMT.BombActivate:IsA("RemoteEvent") then statusText="BombActivate remote unavailable"; return false end
			setState(STATE.ACTIVATING,"Using "..tostring(bombId))
			local sent=false
			local ok,err=pcall(function() RMT.BombActivate:FireServer(bombId,position); sent=true end)
			if not ok or not sent then reportError("autoBomb.activate",err or "BombActivate failed"); return false end
			local now=os.clock()
			lastActivation=now; activationAt=now; activationConfirmed=true
			local fuse=(BOMB_CONFIG[bombId] and BOMB_CONFIG[bombId].fuse) or 2.5
			expectedExplosionAt=now+fuse+CONFIG.FUSE_BUFFER; currentBomb=bombId
			setState(STATE.WAITING_EXPLOSION,"Waiting for "..tostring(bombId).." explosion")
			return true
		end
		local function verifyExplosion()
			if not currentPosition then return false end
			local mat=sampleTerrainMaterial(currentPosition)
			return (not mat) or (not isBombMaterial(mat))
		end
		local function failAndReturnSurface(reason)
			setState(STATE.FAILED,reason or "Bomb failed")
			safeNotify((reason or "Bomb failed").." - returning to surface",2)
			teleportToFreshSurface(); resetAttempt(false)
			state=autoBombActive and STATE.WAITING_NOTIFICATION or STATE.IDLE
			statusText=autoBombActive and "Waiting for bomb notification" or "Idle"
		end
		local function scheduleRetry(reason)
			attempt=attempt+1
			if attempt>=CONFIG.MAX_RETRY then failAndReturnSurface(reason or "Bomb failed"); return end
			retryAt=os.clock()+CONFIG.RETRY_DELAY
			setState(STATE.RETRY,string.format("Retry %d/%d",attempt,CONFIG.MAX_RETRY))
		end
		local function onNotify(kind,text)
			if not autoBombActive or type(text)~="string" then return end
			local bombId,tier=parseBombRequirement(text)
			if not bombId then return end
			if state==STATE.WAITING_EXPLOSION or state==STATE.EQUIPPING or state==STATE.ACTIVATING then return end
			if os.clock()-notificationClock<0.20 and text==lastNotificationText then return end
			notificationClock=os.clock(); lastNotificationText=text; requiredBombId=bombId; requiredBombTier=tier
			local selected,count=getBestBombForRequirement(tier)
			if not selected then failAndReturnSurface("No "..tostring(bombId).." or higher"); return end
			local mat,pos=getNotificationTarget()
			currentMaterial=mat; currentPosition=pos; currentBomb=selected; attempt=0
			statusText=string.format("Notification -> %s (%d)",selected,count or 0)
			state=STATE.READY
		end
		if RMT.Notify and RMT.Notify:IsA("RemoteEvent") then
			RMT.Notify.OnClientEvent:Connect(function(kind,text) pcall(function() onNotify(kind,text) end) end)
		end
		local function step()
			if not autoBombActive then setState(STATE.IDLE,"Idle"); return end
			local now=os.clock()
			if state==STATE.IDLE then state=STATE.WAITING_NOTIFICATION; statusText="Waiting for bomb notification"; return end
			if state==STATE.RETRY then if now<retryAt then return end; state=STATE.READY end
			if state==STATE.WAITING_NOTIFICATION then statusText="Waiting for bomb notification"; return end
			if state==STATE.READY then
				if not currentBomb or not currentPosition then state=STATE.WAITING_NOTIFICATION; return end
				if getBombCount(currentBomb)<=0 then failAndReturnSurface("Bomb empty"); return end
				state=STATE.ACTIVATING
			end
			if state==STATE.ACTIVATING then
				if not activateBomb(currentBomb,currentPosition) then
					if getBombCount(currentBomb)<=0 then failAndReturnSurface("Bomb unavailable")
					else scheduleRetry("Bomb activation failed") end
				end
				return
			end
			if state==STATE.WAITING_EXPLOSION then
				if now<expectedExplosionAt then statusText=string.format("Bomb active %.1fs",expectedExplosionAt-now); return end
				state=STATE.VERIFYING
			end
			if state==STATE.VERIFYING then
				if verifyExplosion() then
					Runtime.BoulderVeinBlocked=false
					setState(STATE.SUCCESS,"Bomb exploded - pickaxe restored")
					attempt=0
					task.spawn(function()
						equipPickaxeAfterBomb()
						currentBomb=nil; currentMaterial=nil; currentPosition=nil; requiredBombId=nil; requiredBombTier=nil
						state=autoBombActive and STATE.WAITING_NOTIFICATION or STATE.IDLE
						statusText=autoBombActive and "Bomb cleared - digging continues" or "Idle"
					end)
					return
				end
				if now-activationAt>=CONFIG.EXPLOSION_TIMEOUT then scheduleRetry("Explosion not detected"); return end
				statusText="Explosion not verified"
			end
		end
		function AutoBomb.setActive(value)
			autoBombActive=value==true; resetAttempt(false)
			if autoBombActive then state=STATE.WAITING_NOTIFICATION; statusText="Waiting for bomb notification"
			else state=STATE.IDLE; statusText="Idle" end
		end
		AutoBomb._getStatusLabel=function(label) bombStatusLabel=label end
		autoBombConn=S.RunService.Heartbeat:Connect(function(dt)
			if autoBombActive then
				accumulator=accumulator+dt
				if accumulator>=CONFIG.STEP then
					accumulator=0
					local ok,err=pcall(step)
					if not ok then reportError("autoBomb",err); scheduleRetry("Internal error") end
				end
			end
			labelClock=labelClock+dt
			if labelClock>=0.30 then
				labelClock=0
				if bombStatusLabel then bombStatusLabel.Text=statusText end
			end
		end)
	end
	install()
end

-- [34] AUTO UPGRADE
local AutoUpgrade={}
local autoUpgradeConn
do
	local function install()
		local PICKAXE_ORDER={
			"RustyScrapper","WeatheredWood","ChippedStone",
			"HardenedIron","CopperPick","ReinforcedSteel",
			"TitaniumSpike","FrostbitePick","EmeraldCarver",
			"VolcanoBasalt","ObsidianEdge","TempestPick",
			"CelestialApex","AstralRend","EclipseFang",
			"NebularThrone","Voidreign","Singularity","TheTerminus",
		}
		local autoWeight=false; local autoAir=false; local autoPick=false
		local weightTier=LoadedCfg.weightTier or 3
		local airTier=LoadedCfg.airTier or 2
		local upgradeClock=0; local UPGRADE_STEP=4
		local priceCache={}
		local autoBuyBombClock=0; local AUTO_BUY_STEP=0.50; local SHOP_BUY_DELAY=0.05
		local autoBuyRadarClock=0
		local function getCash()
			local data=LocalPlayer:FindFirstChild("PlayerData")
			local stats=data and data:FindFirstChild("RealStats")
			local cash=stats and stats:FindFirstChild("Cash")
			return cash and tonumber(cash.Value) or 0
		end
		local function getOwnedPickaxes()
			local data=LocalPlayer:FindFirstChild("PlayerData")
			local inv=data and data:FindFirstChild("Inventory")
			local picks=inv and inv:FindFirstChild("Pickaxes")
			local owned=picks and picks:FindFirstChild("Owned")
			if not owned then return {} end
			local result={}
			for _,child in ipairs(owned:GetChildren()) do result[child.Name]=true end
			return result
		end
		local function getEquippedPickaxe()
			local data=LocalPlayer:FindFirstChild("PlayerData")
			local inv=data and data:FindFirstChild("Inventory")
			local picks=inv and inv:FindFirstChild("Pickaxes")
			local equip=picks and picks:FindFirstChild("Equipped")
			return equip and equip.Value or nil
		end
		local function fetchPrices(kind)
			if not RMT.UpgradePrices then return priceCache[kind] end
			local ok,result=pcall(function() return RMT.UpgradePrices:InvokeServer(kind) end)
			if ok and type(result)=="table" then priceCache[kind]=result; return result end
			return priceCache[kind]
		end
		local function tryWeightUpgrade()
			if not RMT.UpgradeBuy then return end
			local prices=fetchPrices("Weight"); local price=prices and prices[weightTier]
			if not price then return end
			if getCash()>=price then
				pcall(function() RMT.UpgradeBuy:FireServer("Weight",weightTier) end)
				local amounts={1,5,10}
				Notify(string.format("Weight +%dkg",amounts[weightTier] or weightTier),2)
			end
		end
		local function tryAirUpgrade()
			if not RMT.UpgradeBuy then return end
			local prices=fetchPrices("Air"); local price=prices and prices[airTier]
			if not price then return end
			if getCash()>=price then
				pcall(function() RMT.UpgradeBuy:FireServer("Air",airTier) end)
				local amounts={10,50,100}
				Notify(string.format("Warmth +%d",amounts[airTier] or airTier),2)
			end
		end
		local function tryBuyBestPickaxe()
			if not RMT.ShopBuy or not RMT.ShopEquip then return end
			local owned=getOwnedPickaxes(); local equipped=getEquippedPickaxe(); local cash=getCash()
			local nextBuy
			for i=1,#PICKAXE_ORDER do
				local id=PICKAXE_ORDER[i]; local price=math.huge
				for _,entry in ipairs(PICKAXE_SHOP) do
					if entry.id==id then price=tonumber(entry.cashPrice) or math.huge; break end
				end
				if not owned[id] and cash>=price then nextBuy=id end
			end
			if nextBuy then
				pcall(function() RMT.ShopBuy:FireServer(nextBuy) end); task.wait(0.1)
				owned=getOwnedPickaxes()
			end
			local bestOwned
			for i=#PICKAXE_ORDER,1,-1 do
				local id=PICKAXE_ORDER[i]; if owned[id] then bestOwned=id; break end
			end
			if bestOwned and bestOwned~=equipped then
				pcall(function() RMT.ShopEquip:FireServer(bestOwned) end)
				Notify("Equipped: "..bestOwned,2)
			end
		end
		local function tryBuySelectedPickaxe()
			if not autoPick or selectedPickaxeToBuy=="" then return end
			if not RMT.ShopBuy then return end
			local price=0
			for _,entry in ipairs(PICKAXE_SHOP) do
				if entry.id==selectedPickaxeToBuy then price=entry.cashPrice; break end
			end
			local cash=getCash()
			if cash>=price then
				pcall(function() RMT.ShopBuy:FireServer(selectedPickaxeToBuy) end)
				Notify("Bought: "..(selectedPickaxeToBuy),2)
			end
		end
		local function tryBuySelectedBomb()
			if not autoBuyBombsActive then return end
			if type(selectedBombToBuy) ~= "table" then return end
			local bombBuyRequest=RMT.BombBuyRequest
			if not bombBuyRequest or not bombBuyRequest:IsA("RemoteFunction") then return end
			for _,bombId in ipairs(BOMB_SHOP_ORDER) do
				if selectedBombToBuy[bombId] then
					local cfg=BOMB_CONFIG[bombId]
					if cfg and getCash()>=cfg.cashPrice then
						local ok,result=pcall(function() return bombBuyRequest:InvokeServer(bombId) end)
						if ok and type(result)=="table" and result.ok==true then Notify("Bought: "..cfg.displayName,1.2) end
						task.wait(SHOP_BUY_DELAY)
					end
				end
			end
		end
		local function tryBuySelectedRadar()
			if not DHubState.autoBuyRadarActive or DHubState.selectedRadarToBuy=="" then return end
			if not RMT.RadarBuyRequest then return end
			local price=nil
			for _,entry in ipairs(RADAR_SHOP) do
				if entry.id==DHubState.selectedRadarToBuy then price=tonumber(entry.cashPrice); break end
			end
			if RMT.RadarShopQuery then pcall(function() RMT.RadarShopQuery:InvokeServer() end) end
			if price and price>0 and getCash()<price then return end
			local ok,result=pcall(function() return RMT.RadarBuyRequest:InvokeServer(DHubState.selectedRadarToBuy,1) end)
			if ok then
				local success=true
				if type(result)=="table" and result.ok~=nil then success=result.ok==true end
				if success then Notify("Bought: "..selectedRadarToBuy,2) end
			end
		end
		local function step(dt)
			upgradeClock=upgradeClock+dt
			if upgradeClock>=UPGRADE_STEP then
				upgradeClock=0
				if autoWeight then pcall(tryWeightUpgrade) end
				if autoAir    then pcall(tryAirUpgrade)    end
				if autoPick   then pcall(tryBuyBestPickaxe) end
			end
			autoBuyBombClock=autoBuyBombClock+dt
			if autoBuyBombClock>=AUTO_BUY_STEP then
				autoBuyBombClock=0
				if autoBuyBombsActive then pcall(tryBuySelectedBomb) end
				if DHubState.autoBuyRadarActive then pcall(tryBuySelectedRadar) end
			end
		end
		AutoUpgrade.setWeight     = function(v) autoWeight=v end
		AutoUpgrade.setAir        = function(v) autoAir=v    end
		AutoUpgrade.setAutoPick   = function(v) autoPick=v   end
		AutoUpgrade.setWeightTier = function(v) weightTier=math.clamp(math.floor(v),1,3) end
		AutoUpgrade.setAirTier    = function(v) airTier=math.clamp(math.floor(v),1,3)    end
		AutoUpgrade.equipBest     = tryBuyBestPickaxe
		AutoUpgrade.getWeightTier = function() return weightTier end
		AutoUpgrade.getAirTier    = function() return airTier    end
		AutoUpgrade.shutdown      = function() autoWeight=false; autoAir=false; autoPick=false end
		task.spawn(function() task.wait(2); pcall(fetchPrices,"Weight"); pcall(fetchPrices,"Air") end)
		autoUpgradeConn=S.RunService.Heartbeat:Connect(function(dt)
			if autoWeight or autoAir or autoPick or autoBuyBombsActive or DHubState.autoBuyRadarActive then
				local ok,err=pcall(step,dt)
				if not ok then reportError("autoUpgrade",err) end
			end
		end)
	end
	install()
end

-- [10.5] PREMIUM LICENSE VALIDATION

-- Keep the helpers inside the function so they use the function's local
-- registers instead of consuming more registers in this already-large chunk.
function validatePremiumKey()
	PremiumLicense.Key = ""
	PremiumLicense.IsPremium = false
	PremiumLicense.Checked = true
	PremiumLicense.Error = nil

	local env = (type(getgenv) == "function" and getgenv()) or _G
	local value = nil
	pcall(function() value = env.key end)
	if value == nil then
		pcall(function() value = _G.key end)
	end
	if value == nil then value = "" end

	PremiumLicense.Key = tostring(value)
	PremiumLicense.Key = PremiumLicense.Key:match("^%s*(.-)%s*$") or PremiumLicense.Key

	-- Empty key is a normal Free account; do not make an HTTP request.
	if PremiumLicense.Key == "" then
		return false
	end

	local encodedKey = PremiumLicense.Key
	pcall(function()
		encodedKey = S.HttpService:UrlEncode(PremiumLicense.Key)
	end)

	local url = "https://growagardenpetfinder-default-rtdb.asia-southeast1.firebasedatabase.app/LivePets/" .. encodedKey .. ".json"
	local body, code

	local sender = (syn and syn.request) or (http and http.request) or http_request or request
	if type(sender) == "function" then
		local ok, response = pcall(function()
			return sender({
				Url = url,
				Method = "GET"
			})
		end)
		if ok and type(response) == "table" then
			code = tonumber(response.StatusCode) or 0
			if code >= 200 and code < 300 and type(response.Body) == "string" then
				body = response.Body
			end
		end
	end

	if body == nil then
		local ok, responseBody = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and type(responseBody) == "string" then
			body = responseBody
			code = 200
		end
	end

	if type(body) ~= "string" then
		PremiumLicense.Error = "Firebase HTTP " .. tostring(code or 0)
		return false
	end

	local ok, data = pcall(function()
		return S.HttpService:JSONDecode(body)
	end)
	if not ok then
		PremiumLicense.Error = "Firebase JSON error"
		return false
	end

	-- Supported Firebase formats:
	-- LivePets/KEY = true
	-- LivePets/KEY = {active=true}
	-- LivePets/KEY = {valid=true}
	-- LivePets/KEY = {premium=true}
	local valid = data == true
	if type(data) == "table" then
		valid = data.active == true or data.valid == true or data.premium == true
	end

	PremiumLicense.IsPremium = valid == true
	if not PremiumLicense.IsPremium then
		PremiumLicense.Error = "Key not found or inactive"
	end

	return PremiumLicense.IsPremium
end

-- Validate before the UI is created so Premium never briefly runs while the
-- Firebase check is still pending. A network failure safely falls back to Free.
pcall(validatePremiumKey)

-- A previously saved Premium config must never activate Premium while the
-- current key is invalid/missing. Existing non-Premium logic is untouched.
if not PremiumLicense.IsPremium then
	Toggles.AutoFarmPrismarite = false
	Toggles.PremiumAutoPickup = false
	autoFarmPrismariteActive = false
	DHubState.boulderFastDig = false
end

-- [35] CONFIG SAVE
saveConfig = function()
	if isfolder and makefolder then pcall(function() if not isfolder("D-HUB") then makefolder("D-HUB") end end) end
	LoadedCfg.favoriteMinLuck = tonumber(Runtime.favoriteMinLuck) or 10
	LoadedCfg.PrismariteEsp = Toggles.PrismariteEsp == true
	LoadedCfg.AutoFarmPrismarite = Toggles.AutoFarmPrismarite == true
	local filterArr={}; for name in pairs(crystalFilter) do filterArr[#filterArr+1]=name end
	local rarityPickArr={}; for name in pairs(rarityPickupFilter) do rarityPickArr[#rarityPickArr+1]=name end
	local crystalEspArr={}; for name in pairs(crystalEspFilter) do crystalEspArr[#crystalEspArr+1]=name end
	local boulderEspArr={}; for name in pairs(boulderEspFilter) do boulderEspArr[#boulderEspArr+1]=name end
	local veinEspArr={}; for name in pairs(veinEspFilter) do veinEspArr[#veinEspArr+1]=name end
	local farmCrystalArr={}; for name in pairs(farmCrystalFilter) do farmCrystalArr[#farmCrystalArr+1]=name end
	local farmRarityArr={}; for name in pairs(farmRarityFilter) do farmRarityArr[#farmRarityArr+1]=name end
	local config={
		CrystalEsp       = Toggles.CrystalEsp,
		PlayerEsp        = Toggles.PlayerEsp,
		BoulderEsp       = Toggles.BoulderEsp,
		VeinEsp          = Toggles.VeinEsp,
		PrismariteEsp    = Toggles.PrismariteEsp,
		AimTeleport      = Toggles.AimTeleport,
		AutoPickup       = Toggles.AutoPickup,
		InstantPrompt    = Toggles.InstantPrompt,
		AutoRunePickup   = Toggles.AutoRunePickup,
		AutoFavoriteItem = Toggles.AutoFavoriteItem,
		AutoDig          = Toggles.AutoDig,
		AutoFarmMoney    = Toggles.AutoFarmMoney,
		AutoFarmBoulders = Toggles.AutoFarmBoulders,
		AutoFarmPrismarite = Toggles.AutoFarmPrismarite,
		PremiumAutoPickup = Toggles.PremiumAutoPickup,
		MoneyAutoSell    = Toggles.MoneyAutoSell,
		AutoWeightUpgrade= Toggles.AutoWeightUpgrade,
		AutoAirUpgrade   = Toggles.AutoAirUpgrade,
		AutoBuyPick      = Toggles.AutoBuyPick,
		AutoBomb         = Toggles.AutoBomb,
		AutoBuyBombs     = Toggles.AutoBuyBombs,
		AutoBuyRadar     = Toggles.AutoBuyRadar,
		SpeedBoost       = Toggles.SpeedBoost,
		Noclip           = Toggles.Noclip,
		InfJump          = Toggles.InfJump,
		Fly              = Toggles.Fly,
		minValue         = minValue,
		boulderMinLuck   = boulderMinLuck,
		favoriteMinLuck  = math.max(0,tonumber(Runtime.favoriteMinLuck) or 10),
		farmMethod       = Runtime.farmMethod,
		DHubState.premiumFarmMethod = DHubState.premiumFarmMethod,
		DHubState.premiumMinLuck   = DHubState.premiumMinLuck,
		espScale         = math.floor(espScale*100),
		playerScale      = math.floor(playerScale*100),
		boulderScale     = math.floor(boulderScale*100),
		DHubState.boulderFastDig   = DHubState.boulderFastDig == true,
		DHubState.boulderDigSpeed  = math.floor(DHubState.boulderDigSpeed),
		autoRevive       = Toggles.AutoRevive,
		fpsBoost         = Toggles.FpsBoost,
		ultraFps         = Toggles.UltraFps,
		autoHop          = Toggles.AutoHop,
		DHubState.autoHopMinutes   = DHubState.autoHopMinutes,
		weightTier       = AutoUpgrade.getWeightTier(),
		airTier          = AutoUpgrade.getAirTier(),
		crystalFilter    = filterArr,
		rarityPickupFilter = rarityPickArr,
		crystalEspFilter = crystalEspArr,
		boulderEspFilter = boulderEspArr,
		veinEspFilter    = veinEspArr,
		farmCrystalFilter = farmCrystalArr,
		farmRarityFilter = farmRarityArr,
		premiumRarityFilter = (function() local t={}; for name in pairs(premiumRarityFilter) do t[#t+1]=name end; return t end)(),
		boulderFarmFilter = (function() local t={}; for name in pairs(Cache.boulderFarmFilter) do t[#t+1]=name end; return t end)(),
		selectedPickaxeToBuy = selectedPickaxeToBuy,
		selectedBombToBuy    = (function() local t={}; for _,id in ipairs(BOMB_SHOP_ORDER) do if selectedBombToBuy[id] then t[#t+1]=id end end; return t end)(),
		DHubState.selectedRadarToBuy   = DHubState.selectedRadarToBuy,
	}
	local ok=pcall(function()
		writefile(CONFIG_PATH,S.HttpService:JSONEncode(config))
	end)
	return ok
end

-- [36] HEARTBEAT CONNECTIONS & GLOBAL AUTO SELL
local function updateBackpackLabel()
	if not Runtime.BackpackLabel then return end
	local cap=backpackCapacity(); local used=backpackWeight()
	if cap==math.huge then Runtime.BackpackLabel.Text=string.format("%.1f / ∞ KG",used); return end
	Runtime.BackpackLabel.Text=string.format("%.1f / %.1f KG",used,cap)
end

local function doSell()
	local now=os.clock()
	if now-Runtime.sellClock<1.5 then return false end
	Runtime.sellClock=now; fireRemote(RMT.GoHome,"sell")
	schedule(0.6,function() fireRemote(RMT.SellRequest,"all") end)
	return true
end

Runtime.autoDigStep = function()
	if not Toggles.AutoDig then return end
	local event=Tools.digEvent(); if not event then return end
	local tool=Tools.equipPick(); if not tool then return end
	local hit=Mouse.Hit
	if not hit then return end
	local point=hit.Position
	pcall(function() event:FireServer(tool.Name,point) end)
end

Runtime.favoriteAccumulator=0
Runtime.favoriteConn=S.RunService.Heartbeat:Connect(function(dt)
	Runtime.favoriteAccumulator=Runtime.favoriteAccumulator+dt
	if Runtime.favoriteAccumulator>=2.0 then
		Runtime.favoriteAccumulator=0
		if Toggles.AutoFavoriteItem == true then pcall(Runtime.autoFavoriteInventoryStep) end
	end
	if Toggles.AutoDig then
		Runtime.autoDigAccumulator=Runtime.autoDigAccumulator+dt
		if Runtime.autoDigAccumulator>=0.03 then
			Runtime.autoDigAccumulator=0
			pcall(Runtime.autoDigStep)
		end
	end
end)

Runtime.crystalEspTick=function(deltaTime)
	if Runtime.statsDirty and Runtime.StatsLabel then
		Runtime.statsDirty=false
		Runtime.StatsLabel.Text=string.format("Tracking: %d  |  Shown: %d",DHubState.registryCount,DHubState.espCount)
	end
	if not espActive then return end
	local now=os.clock()
	for inst,expiry in pairs(Cache.candidates) do
		if not inst.Parent then Cache.candidates[inst]=nil
		elseif isCrystal(inst) then Cache.candidates[inst]=nil; trackCrystal(inst)
		elseif now>expiry then Cache.candidates[inst]=nil end
	end
	local deadline=now+(fpsBoostActive and math.min(CFG.ESP.budget,0.0015) or CFG.ESP.budget)
	if next(Cache.dirty)~=nil then
		for inst in pairs(Cache.dirty) do
			local ok,err=pcall(syncCrystal,inst)
			if not ok then Cache.dirty[inst]=nil; reportError("sync",err) end
			if os.clock()>deadline then break end
		end
	end
	Runtime.sweepAccumulator=Runtime.sweepAccumulator+deltaTime
	if Runtime.sweepAccumulator>=(fpsBoostActive and math.max(CFG.ESP.sweep,2.5) or CFG.ESP.sweep) then
		Runtime.sweepAccumulator=0
		local ok,err=pcall(function() watchContainers(); sweep() end)
		if not ok then reportError("sweep",err) end
	end
	Runtime.distanceAccumulator=Runtime.distanceAccumulator+deltaTime
	if Runtime.distanceAccumulator>=(fpsBoostActive and math.max(CFG.PACE.distance,0.25) or CFG.PACE.distance) then
		Runtime.distanceAccumulator=0
		local ok,err=pcall(updateDistances); if not ok then reportError("distance",err) end
	end
end

-- Register-limit fix:
-- Keep the global scheduler connection in Runtime instead of allocating
-- another top-level local register. The previous `local schedulerConn`
-- crossed the executor/Luau local-register limit in this large script.
Runtime.schedulerConn=S.RunService.Heartbeat:Connect(function(deltaTime)
	-- Global Auto Sell Logic (Works all the time, completely independent of Money Farm)
	if Toggles.MoneyAutoSell then
		local bagRatio = 0
		local cap = backpackCapacity()
		if cap ~= math.huge and cap > 0 then bagRatio = backpackWeight() / cap end
		if bagRatio >= 0.5 then
			if os.clock() - Runtime.lastGlobalAutoSell > 10 then -- 10s cooldown fail-safe to prevent spam
				Runtime.lastGlobalAutoSell = os.clock()
				if doSell() then Notify("Auto Selling...", 2) end
			end
		end
	end

	if Runtime.tpState then
		local ok,err=pcall(function()
			if not applyPivot(Runtime.tpState.goal) then finishTeleport(); return end
			if os.clock()>=Runtime.tpState.holdUntil then finishTeleport() end
		end)
		if not ok then finishTeleport(); reportError("teleport",err) end
	end

	-- Aim Teleport uses the existing scheduler instead of creating a dedicated
	-- UserInputService.InputBegan connection. It fires once per F key press.
	local fDown=false
	if aimTpEnabled and not S.UserInputService:GetFocusedTextBox() then
		fDown=S.UserInputService:IsKeyDown(Enum.KeyCode.F)
		if fDown and not Runtime.aimFDown and DHubState.aimTeleport then
			local ok,err=pcall(DHubState.aimTeleport)
			if not ok then reportError("DHubState.aimTeleport",err) end
		end
	end
	Runtime.aimFDown=fDown

	-- All ESP scanners share this one existing Heartbeat. No separate
	-- espConn/veinConn/Prismarite/mountain Heartbeat connections are created.
	if Runtime.crystalEspTick then
		local ok,err=pcall(Runtime.crystalEspTick,deltaTime)
		if not ok then reportError("esp",err) end
	end
	if VeinsModule.tick then
		local ok,err=pcall(VeinsModule.tick,deltaTime)
		if not ok then reportError("veinEsp",err) end
	end
	if PrismariteModule.tick then
		local ok,err=pcall(PrismariteModule.tick,deltaTime)
		if not ok then reportError("prismariteEsp",err) end
	end
	if Mountain.tick then
		local ok,err=pcall(Mountain.tick,deltaTime)
		if not ok then reportError("boulderEsp",err) end
	end

	-- Instant Pickup is global and independent of Money/Boulder Farm.
	if instantPromptActive then
		Runtime.instantAccumulator=Runtime.instantAccumulator+deltaTime
		if Runtime.instantAccumulator>=CFG.PICK.instantTick then
			Runtime.instantAccumulator=0
			local ok,err=pcall(refreshInstantPrompts); if not ok then reportError("instant",err) end
		end
	end
	if speedActive then
		local body=LocalPlayer.Character
		local mover=body and body:FindFirstChildOfClass("Humanoid")
		if mover then watchSpeed(mover); enforceSpeed(mover) end
	end
	if playerEspActive then
		Runtime.ultraPlayerAccumulator=Runtime.ultraPlayerAccumulator+deltaTime
		local playerInterval=fpsBoostActive and 0.15 or 0.05
		if Runtime.ultraPlayerAccumulator>=playerInterval then
			Runtime.ultraPlayerAccumulator=0
			local ok,err=pcall(updatePlayerEsp); if not ok then reportError("playerEsp",err) end
		end
	end
	Runtime.statsAccumulator=Runtime.statsAccumulator+deltaTime
	if fpsBoostActive then
		Runtime.ultraBackpackAccumulator=Runtime.ultraBackpackAccumulator+deltaTime
		if Runtime.ultraBackpackAccumulator>=0.75 then
			Runtime.ultraBackpackAccumulator=0
			local ok,err=pcall(updateBackpackLabel); if not ok then reportError("backpack",err) end
		end
	else
		Runtime.ultraBackpackAccumulator=0
		if Runtime.statsAccumulator>=CFG.PACE.stats then
			Runtime.statsAccumulator=0
			local ok,err=pcall(updateBackpackLabel); if not ok then reportError("backpack",err) end
		end
	end
	-- Config persistence is intentionally handled by this existing global
	-- scheduler. Do NOT create a separate Heartbeat connection for config saves;
	-- repeated script execution would otherwise accumulate ConfigSaveConn
	-- connections until the executor's connection limit is reached.
	Runtime.configSaveClock=Runtime.configSaveClock+deltaTime
	if Runtime.configSaveClock>=30 then
		Runtime.configSaveClock=0
		pcall(saveConfig)
	end

	if #Cache.pendingActions==0 then return end
	local now=os.clock()
	for index=#Cache.pendingActions,1,-1 do
		local job=Cache.pendingActions[index]
		if now>=job.at then
			table.remove(Cache.pendingActions,index)
			local ok,err=pcall(job.fn); if not ok then reportError("action",err) end
		end
	end
end)

-- [37] SORT / TELEPORT ACTIONS
Runtime.aimParams=RaycastParams.new()
Runtime.aimParams.FilterType=Enum.RaycastFilterType.Exclude
Runtime.aimParams.IgnoreWater=true
function sortedByScore(scoreFn)
	local scored={}; local seen={}
	local function consider(inst)
		if seen[inst] or not inst.Parent then return end
		if getAttr(inst,"Collected")==true then return end
		seen[inst]=true
		local ok,score=pcall(scoreFn,inst)
		scored[#scored+1]={inst=inst,score=ok and score or 0}
	end
	for inst in pairs(Cache.registry) do consider(inst) end
	eachContainer(function(c) for _,child in ipairs(c:GetChildren()) do if isCrystal(child) then consider(child) end end end)
	table.sort(scored,function(a,b) return a.score>b.score end)
	return scored
end
function getAimedCrystal()
	local unitRay=Mouse.UnitRay; local origin=unitRay.Origin; local direction=unitRay.Direction.Unit
	local char=LocalPlayer.Character
	Runtime.aimParams.FilterDescendantsInstances=char and {char} or {}
	local hit=S.Workspace:Raycast(origin,direction*CFG.PICK.aimRange,Runtime.aimParams)
	if hit and hit.Instance and (Cache.registry[hit.Instance] or isCrystal(hit.Instance)) then return hit.Instance end
	local best,bestDot; local seen={}
	local function consider(inst)
		if seen[inst] or not inst.Parent then return end; seen[inst]=true
		local offset=(inst.Position+CFG.ESP.offset)-origin; local mag=offset.Magnitude
		if mag>0 then
			local dot=direction:Dot(offset/mag)
			if not bestDot or dot>bestDot then bestDot=dot; best=inst end
		end
	end
	for inst in pairs(Cache.espCache) do consider(inst) end
	eachContainer(function(c) for _,child in ipairs(c:GetChildren()) do if isCrystal(child) then consider(child) end end end)
	if best and bestDot and bestDot>=CFG.PICK.aimDot then return best end
	return nil
end
DHubState.aimTeleport=function()
	if not espActive then Notify("Enable Crystal ESP first",3); return end
	local inst=getAimedCrystal()
	if not inst then Notify("No crystal aimed",2); return end
	if teleportTo(inst) then Notify(string.format("TP -> %s",crystalName(inst)),2)
	else Notify("Teleport failed",2) end
end
-- Register-limit fix:
-- tpToRank was the next top-level local after schedulerConn and could push
-- this large script over the executor's 200 local-register limit.
-- Store the same function on Runtime instead; behavior is unchanged.
Runtime.tpToRank=function(scoreFn,rank,formatter)
	local entry=sortedByScore(scoreFn)[rank]
	if not entry or entry.score<=0 then Notify(string.format("No crystal #%d",rank),3); return end
	if teleportTo(entry.inst) then
		Notify(string.format("TP #%d %s (%s)",rank,crystalName(entry.inst),formatter(entry.inst,entry.score)),3)
	else Notify("Teleport failed",3) end
end

function UIH_Corner(UI,p,r) local c=Instance.new("UICorner",p); c.CornerRadius=UDim.new(0,r or 6) end

function UIH_Stroke(UI,p,col,th) local s=Instance.new("UIStroke",p); s.Color=col or UI.C.BORDER; s.Thickness=th or 1; return s end

function UIH_MakeDraggable(UI,frame,handle)
		local drag,ds,sp
		handle.InputBegan:Connect(function(inp)
			if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
				drag=true; ds=inp.Position; sp=frame.Position
				inp.Changed:Connect(function() if inp.UserInputState==Enum.UserInputState.End then drag=false end end)
			end
		end)
		S.UserInputService.InputChanged:Connect(function(inp)
			if drag and (inp.UserInputType==Enum.UserInputType.MouseMovement or inp.UserInputType==Enum.UserInputType.Touch) then
				local d=inp.Position-ds
				frame.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)
			end
		end)
	end

function UIH_BuatPage(UI,name)
		local Page=Instance.new("ScrollingFrame",UI.ContentArea)
		Page.Name=name; Page.Size=UDim2.new(1,0,1,0); Page.BackgroundTransparency=1
		Page.BorderSizePixel=0; Page.ScrollBarThickness=4; Page.ScrollBarImageColor3=UI.C.DIVIDER; Page.Visible=false
		local Layout=Instance.new("UIListLayout",Page)
		Layout.Padding=UDim.new(0,8); Layout.SortOrder=Enum.SortOrder.LayoutOrder
		local Pad=Instance.new("UIPadding",Page)
		Pad.PaddingTop=UDim.new(0,15); Pad.PaddingBottom=UDim.new(0,15)
		Pad.PaddingLeft=UDim.new(0,15); Pad.PaddingRight=UDim.new(0,15)
		Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			Page.CanvasSize=UDim2.new(0,0,0,Layout.AbsoluteContentSize.Y+30)
		end)
		UI.Pages[name]=Page; return Page
	end

function UIH_SwitchTab(UI,targetName)
		for name,page in pairs(UI.Pages) do page.Visible=(name==targetName) end
		for name,btnData in pairs(UI.NavButtons) do
			local isActive=(name==targetName)
			S.TweenService:Create(btnData.Indicator,TweenInfo.new(0.2),{BackgroundTransparency=isActive and 0 or 1}):Play()
			S.TweenService:Create(btnData.Label,TweenInfo.new(0.2),{TextColor3=isActive and UI.C.TEXT_1 or UI.C.TEXT_2}):Play()
			S.TweenService:Create(btnData.Btn,TweenInfo.new(0.2),{BackgroundColor3=isActive and UI.C.ELEVATED or UI.C.SURFACE}):Play()
		end
	end

function UIH_BuatNavButton(UI,name)
		local Btn=Instance.new("TextButton",UI.TabContainer)
		Btn.Size=UDim2.new(1,-16,0,36); Btn.BackgroundColor3=UI.C.SURFACE
		Btn.BorderSizePixel=0; Btn.Text=""; Btn.AutoButtonColor=false; UIH_Corner(UI,Btn,6)
		local Indicator=Instance.new("Frame",Btn)
		Indicator.Size=UDim2.new(0,3,0,18); Indicator.Position=UDim2.new(0,0,0.5,-9)
		Indicator.BackgroundColor3=UI.C.ACCENT; Indicator.BorderSizePixel=0; Indicator.BackgroundTransparency=1; UIH_Corner(UI,Indicator,2)
		local Label=Instance.new("TextLabel",Btn)
		Label.Size=UDim2.new(1,-16,1,0); Label.Position=UDim2.new(0,12,0,0)
		Label.BackgroundTransparency=1; Label.Text=name; Label.TextColor3=UI.C.TEXT_2
		Label.Font=Enum.Font.GothamMedium; Label.TextSize=12; Label.TextXAlignment=Enum.TextXAlignment.Left
		Btn.MouseButton1Click:Connect(function() UIH_SwitchTab(UI,name) end)
		UI.NavButtons[name]={Btn=Btn,Indicator=Indicator,Label=Label}
	end

function UIH_BuatSection(UI,parent,text)
		local Lbl=Instance.new("TextLabel",parent)
		Lbl.Size=UDim2.new(1,0,0,20); Lbl.BackgroundTransparency=1
		Lbl.Font=Enum.Font.GothamBold; Lbl.TextColor3=UI.C.TEXT_2
		Lbl.Text=text:upper(); Lbl.TextSize=11; Lbl.TextXAlignment=Enum.TextXAlignment.Left
	end

function UIH_BuatLabel(UI,parent,defaultText)
		local Row=Instance.new("Frame",parent)
		Row.Size=UDim2.new(1,0,0,30); Row.BackgroundColor3=UI.C.SURFACE; UIH_Corner(UI,Row,6)
		local LabelTxt=Instance.new("TextLabel",Row)
		LabelTxt.Size=UDim2.new(1,-20,1,0); LabelTxt.Position=UDim2.new(0,14,0,0)
		LabelTxt.BackgroundTransparency=1; LabelTxt.Text=defaultText
		LabelTxt.TextColor3=UI.C.TEXT_1; LabelTxt.Font=Enum.Font.GothamMedium
		LabelTxt.TextSize=12; LabelTxt.TextXAlignment=Enum.TextXAlignment.Left
		return LabelTxt
	end

function UIH_BuatToggle(UI,parent,label,sublabel,defaultState,accentColor)
	local Row=Instance.new("Frame",parent)
	Row.Size=UDim2.new(1,0,0,42); Row.BackgroundColor3=UI.C.SURFACE; UIH_Corner(UI,Row,6)
	local RowStroke=UIH_Stroke(UI,Row,UI.C.BORDER)
	local LeftAccent=Instance.new("Frame",Row)
	LeftAccent.Size=UDim2.new(0,2,0,18); LeftAccent.Position=UDim2.new(0,0,0.5,-9)
	LeftAccent.BackgroundColor3=UI.C.BORDER; UIH_Corner(UI,LeftAccent,1)
	local LabelTxt=Instance.new("TextLabel",Row)
	LabelTxt.Size=UDim2.new(1,-70,1,0); LabelTxt.Position=UDim2.new(0,14,0,0)
	LabelTxt.BackgroundTransparency=1; LabelTxt.Text=label
	LabelTxt.TextColor3=UI.C.TEXT_2; LabelTxt.Font=Enum.Font.GothamMedium; LabelTxt.TextSize=12; LabelTxt.TextXAlignment=Enum.TextXAlignment.Left
	local Pill=Instance.new("Frame",Row)
	Pill.Size=UDim2.new(0,38,0,20); Pill.Position=UDim2.new(1,-50,0.5,-10); Pill.BackgroundColor3=UI.C.DIVIDER; UIH_Corner(UI,Pill,10)
	local PillDot=Instance.new("Frame",Pill)
	PillDot.Size=UDim2.new(0,14,0,14); PillDot.Position=UDim2.new(0,3,0.5,-7); PillDot.BackgroundColor3=UI.C.TEXT_3; UIH_Corner(UI,PillDot,7)
	local Btn=Instance.new("TextButton",Row)
	Btn.Size=UDim2.new(1,0,1,0); Btn.BackgroundTransparency=1; Btn.Text=""
	local accent=accentColor or UI.C.ACCENT
	local accentD=accentColor and accentColor:lerp(Color3.new(0,0,0),0.25) or UI.C.ACCENT_D
	local function SetInstant(on)
		Row.BackgroundColor3=on and UI.C.ELEVATED or UI.C.SURFACE
		RowStroke.Color=on and accentD or UI.C.BORDER
		LabelTxt.TextColor3=on and UI.C.TEXT_1 or UI.C.TEXT_2
		LeftAccent.BackgroundColor3=on and accent or UI.C.BORDER
		Pill.BackgroundColor3=on and accentD or UI.C.DIVIDER
		PillDot.Position=on and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,3,0.5,-7)
		PillDot.BackgroundColor3=on and accent or UI.C.TEXT_3
	end
	local function SetTween(on)
		S.TweenService:Create(Row,TweenInfo.new(0.2),{BackgroundColor3=on and UI.C.ELEVATED or UI.C.SURFACE}):Play()
		RowStroke.Color=on and accentD or UI.C.BORDER
		LabelTxt.TextColor3=on and UI.C.TEXT_1 or UI.C.TEXT_2
		LeftAccent.BackgroundColor3=on and accent or UI.C.BORDER
		S.TweenService:Create(Pill,TweenInfo.new(0.2),{BackgroundColor3=on and accentD or UI.C.DIVIDER}):Play()
		S.TweenService:Create(PillDot,TweenInfo.new(0.2),{
			Position=on and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,3,0.5,-7),
			BackgroundColor3=on and accent or UI.C.TEXT_3,
		}):Play()
	end
	SetInstant(defaultState==true)
	return Btn,SetTween
end

function UIH_BuatButton(UI,parent,label,sublabel,bgColor)
	local Row=Instance.new("TextButton",parent)
	Row.Size=UDim2.new(1,0,0,36); Row.BackgroundColor3=bgColor or UI.C.SURFACE
	Row.Text=""; Row.AutoButtonColor=false; UIH_Corner(UI,Row,6); UIH_Stroke(UI,Row,UI.C.BORDER)
	local LeftAccent=Instance.new("Frame",Row)
	LeftAccent.Size=UDim2.new(0,2,0,18); LeftAccent.Position=UDim2.new(0,0,0.5,-9)
	LeftAccent.BackgroundColor3=UI.C.BORDER; UIH_Corner(UI,LeftAccent,1)
	local LabelTxt=Instance.new("TextLabel",Row)
	LabelTxt.Size=UDim2.new(1,-20,1,0); LabelTxt.Position=UDim2.new(0,14,0,0)
	LabelTxt.BackgroundTransparency=1; LabelTxt.Text=label
	LabelTxt.TextColor3=UI.C.TEXT_1; LabelTxt.Font=Enum.Font.GothamMedium; LabelTxt.TextSize=12; LabelTxt.TextXAlignment=Enum.TextXAlignment.Left
	return Row
end

function UIH_BuatSlider(UI,parent,label,min,max,default,callback)
		local Row=Instance.new("Frame",parent)
		Row.Size=UDim2.new(1,0,0,50); Row.BackgroundColor3=UI.C.SURFACE; UIH_Corner(UI,Row,6); UIH_Stroke(UI,Row,UI.C.BORDER)
		local LabelTxt=Instance.new("TextLabel",Row)
		LabelTxt.Size=UDim2.new(0.7,0,0,20); LabelTxt.Position=UDim2.new(0,14,0,5)
		LabelTxt.BackgroundTransparency=1; LabelTxt.Text=label..": "..tostring(default)
		LabelTxt.TextColor3=UI.C.TEXT_1; LabelTxt.Font=Enum.Font.GothamMedium; LabelTxt.TextSize=11; LabelTxt.TextXAlignment=Enum.TextXAlignment.Left
		local Track=Instance.new("Frame",Row)
		Track.Size=UDim2.new(1,-28,0,4); Track.Position=UDim2.new(0,14,1,-12); Track.BackgroundColor3=UI.C.DIVIDER; UIH_Corner(UI,Track,2)
		local Progress=Instance.new("Frame",Track); Progress.Size=UDim2.new(0,0,1,0); Progress.BackgroundColor3=UI.C.ACCENT; UIH_Corner(UI,Progress,2)
		local Thumb=Instance.new("Frame",Track)
		Thumb.Size=UDim2.new(0,12,0,12); Thumb.Position=UDim2.new(0,-6,0.5,-6); Thumb.BackgroundColor3=UI.C.TEXT_1; UIH_Corner(UI,Thumb,6)
		local Dragger=Instance.new("TextButton",Track)
		Dragger.Size=UDim2.new(1,0,3,0); Dragger.Position=UDim2.new(0,0,-1,0); Dragger.BackgroundTransparency=1; Dragger.Text=""
		local function UpdateSlider(value)
			local pct=math.clamp((value-min)/(max-min),0,1)
			Progress.Size=UDim2.new(pct,0,1,0); Thumb.Position=UDim2.new(pct,-6,0.5,-6)
			LabelTxt.Text=label..": "..string.format("%d",value); callback(math.floor(value))
		end
		UpdateSlider(default)
		local dragging=false
		Dragger.InputBegan:Connect(function(i)
			if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true end
		end)
		Dragger.InputEnded:Connect(function(i)
			if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
		end)
		S.UserInputService.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
				local relX=i.Position.X-Track.AbsolutePosition.X
				local pct=math.clamp(relX/Track.AbsoluteSize.X,0,1)
				UpdateSlider(min+(max-min)*pct)
			end
		end)
		return Row
	end

function UIH_BuatInput(UI,parent,label,placeholder,default,callback)
		local Row=Instance.new("Frame",parent)
		Row.Size=UDim2.new(1,0,0,42); Row.BackgroundColor3=UI.C.SURFACE; UIH_Corner(UI,Row,6); UIH_Stroke(UI,Row,UI.C.BORDER)
		local LabelTxt=Instance.new("TextLabel",Row)
		LabelTxt.Size=UDim2.new(0.5,-20,1,0); LabelTxt.Position=UDim2.new(0,14,0,0)
		LabelTxt.BackgroundTransparency=1; LabelTxt.Text=label
		LabelTxt.TextColor3=UI.C.TEXT_1; LabelTxt.Font=Enum.Font.GothamMedium; LabelTxt.TextSize=12; LabelTxt.TextXAlignment=Enum.TextXAlignment.Left
		local InputBox=Instance.new("TextBox",Row)
		InputBox.Size=UDim2.new(0.4,0,0,24); InputBox.Position=UDim2.new(0.6,-14,0.5,-12)
		InputBox.BackgroundColor3=UI.C.ELEVATED; UIH_Corner(UI,InputBox,4); UIH_Stroke(UI,InputBox,UI.C.DIVIDER)
		InputBox.Text=default or ""; InputBox.PlaceholderText=placeholder or ""
		InputBox.TextColor3=UI.C.TEXT_1; InputBox.Font=Enum.Font.Gotham; InputBox.TextSize=11
		InputBox.FocusLost:Connect(function() callback(InputBox.Text) end)
		return Row
	end

function UIH_BuatDropdown(UI,parent, label, options, isMulti, defaultSelected, callback)
		local selected = isMulti and {} or ""
		if isMulti and type(defaultSelected)=="table" then
			for _,v in ipairs(defaultSelected) do
				if type(v)=="string" and v~="Default" and v~="" then selected[v]=true end
			end
		elseif not isMulti and type(defaultSelected)=="string" then
			selected=(defaultSelected=="Default") and "" or defaultSelected
		end
		local function displayText()
			if isMulti then
				local keys={}; for k in pairs(selected) do keys[#keys+1]=k end
				if #keys==0 then return "[Default]" end
				table.sort(keys)
				if #keys==1 then return keys[1] end
				return keys[1].." +"..tostring(#keys-1)
			else
				return selected=="" and "[Default]" or selected
			end
		end
		local Row=Instance.new("Frame",parent)
		Row.Size=UDim2.new(1,0,0,42); Row.BackgroundColor3=UI.C.SURFACE; UIH_Corner(UI,Row,6); UIH_Stroke(UI,Row,UI.C.BORDER)
		local LabelTxt=Instance.new("TextLabel",Row)
		LabelTxt.Size=UDim2.new(0.42,0,1,0); LabelTxt.Position=UDim2.new(0,14,0,0)
		LabelTxt.BackgroundTransparency=1; LabelTxt.Text=label
		LabelTxt.TextColor3=UI.C.TEXT_2; LabelTxt.Font=Enum.Font.GothamMedium; LabelTxt.TextSize=11; LabelTxt.TextXAlignment=Enum.TextXAlignment.Left
		local DropBtn=Instance.new("TextButton",Row)
		DropBtn.Size=UDim2.new(0.55,0,0,28); DropBtn.Position=UDim2.new(0.44,0,0.5,-14)
		DropBtn.BackgroundColor3=UI.C.ELEVATED; UIH_Corner(UI,DropBtn,4); UIH_Stroke(UI,DropBtn,UI.C.DIVIDER)
		DropBtn.Text=displayText(); DropBtn.TextColor3=UI.C.TEXT_1
		DropBtn.Font=Enum.Font.GothamMedium; DropBtn.TextSize=11
		DropBtn.AutoButtonColor=false
		local Panel=Instance.new("Frame",UI.MainSG)
		Panel.Size=UDim2.new(0,220,0,math.min(#options*28+8,180))
		Panel.BackgroundColor3=UI.C.ELEVATED; UIH_Corner(UI,Panel,6); UIH_Stroke(UI,Panel,UI.C.BORDER)
		Panel.Visible=false; Panel.ZIndex=20
		local PanelScroll=Instance.new("ScrollingFrame",Panel)
		PanelScroll.Size=UDim2.new(1,-4,1,-4); PanelScroll.Position=UDim2.new(0,2,0,2)
		PanelScroll.BackgroundTransparency=1; PanelScroll.BorderSizePixel=0
		PanelScroll.ScrollBarThickness=3; PanelScroll.ZIndex=20
		local PanelLayout=Instance.new("UIListLayout",PanelScroll)
		PanelLayout.Padding=UDim.new(0,2); PanelLayout.SortOrder=Enum.SortOrder.LayoutOrder
		PanelLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			PanelScroll.CanvasSize=UDim2.new(0,0,0,PanelLayout.AbsoluteContentSize.Y+6)
		end)
		local function rebuildOptions(optList)
			for _,ch in ipairs(PanelScroll:GetChildren()) do
				if ch:IsA("TextButton") then ch:Destroy() end
			end
			local clearBtn=Instance.new("TextButton",PanelScroll)
			clearBtn.Size=UDim2.new(1,0,0,26); clearBtn.BackgroundTransparency=1
			clearBtn.Text="[Default]"; clearBtn.TextColor3=UI.C.TEXT_3
			clearBtn.Font=Enum.Font.GothamMedium; clearBtn.TextSize=11; clearBtn.ZIndex=21
			clearBtn.MouseButton1Click:Connect(function()
				if isMulti then table.clear(selected) else selected="" end
				DropBtn.Text=displayText()
				Panel.Visible=false; UI.activeDropdown=nil
				callback(isMulti and {} or "")
			end)
			for _,opt in ipairs(optList) do
				local isOn=isMulti and selected[opt]==true or selected==opt
				local OBtn=Instance.new("TextButton",PanelScroll)
				OBtn.Size=UDim2.new(1,0,0,26); OBtn.BackgroundColor3=isOn and UI.C.ACCENT_D or UI.C.ELEVATED
				OBtn.BorderSizePixel=0; UIH_Corner(UI,OBtn,4)
				OBtn.Text=opt; OBtn.TextColor3=isOn and UI.C.TEXT_1 or UI.C.TEXT_2
				OBtn.Font=Enum.Font.GothamMedium; OBtn.TextSize=11; OBtn.ZIndex=21
				OBtn.MouseButton1Click:Connect(function()
					if isMulti then
						if opt=="Default" then
							table.clear(selected)
						else
							if selected[opt] then selected[opt]=nil else selected[opt]=true end
						end
						selected.Default=nil
						for _,child in ipairs(PanelScroll:GetChildren()) do
							if child:IsA("TextButton") and child~=clearBtn then
								local on=selected[child.Text]==true
								child.BackgroundColor3=on and UI.C.ACCENT_D or UI.C.ELEVATED
								child.TextColor3=on and UI.C.TEXT_1 or UI.C.TEXT_2
							end
						end
					else
						selected=(opt=="Default") and "" or opt
						Panel.Visible=false; UI.activeDropdown=nil
					end
					DropBtn.Text=displayText()
					local result
					if isMulti then
						result={}; for k in pairs(selected) do if k~="Default" then result[#result+1]=k end end
					else result=selected end
					callback(result)
				end)
			end
		end
		rebuildOptions(options)
		DropBtn.MouseButton1Click:Connect(function()
			if Panel.Visible then
				Panel.Visible=false; UI.activeDropdown=nil; return
			end
			if UI.activeDropdown and UI.activeDropdown~=Panel then UI.activeDropdown.Visible=false end
			local absPos=DropBtn.AbsolutePosition
			local absSize=DropBtn.AbsoluteSize
			Panel.Position=UDim2.fromOffset(absPos.X,absPos.Y+absSize.Y+4)
			Panel.Visible=true; UI.activeDropdown=Panel
		end)
		local function GetSelected() return isMulti and selected or selected end
		local function SetOptions(newOpts)
			rebuildOptions(newOpts)
			Panel.Size=UDim2.new(0,220,0,math.min(#newOpts*28+8+28,180))
		end
		local function SetSelected(val)
			if isMulti and type(val)=="table" then
				table.clear(selected)
				for _,v in ipairs(val) do selected[v]=true end
			elseif not isMulti and type(val)=="string" then
				selected=val
			end
			DropBtn.Text=displayText()
		end
		return Row, GetSelected, SetOptions, SetSelected
	end

function UIH_BuatStepSelect(UI,parent, label, default, callback)
		local Row=Instance.new("Frame",parent)
		Row.Size=UDim2.new(1,0,0,42); Row.BackgroundColor3=UI.C.SURFACE; UIH_Corner(UI,Row,6); UIH_Stroke(UI,Row,UI.C.BORDER)
		local LabelTxt=Instance.new("TextLabel",Row)
		LabelTxt.Size=UDim2.new(0.55,0,1,0); LabelTxt.Position=UDim2.new(0,14,0,0)
		LabelTxt.BackgroundTransparency=1; LabelTxt.Text=label
		LabelTxt.TextColor3=UI.C.TEXT_2; LabelTxt.Font=Enum.Font.GothamMedium; LabelTxt.TextSize=12; LabelTxt.TextXAlignment=Enum.TextXAlignment.Left
		local BtnHolder=Instance.new("Frame",Row)
		BtnHolder.Size=UDim2.new(0,96,0,28); BtnHolder.Position=UDim2.new(1,-110,0.5,-14)
		BtnHolder.BackgroundTransparency=1
		local BHL=Instance.new("UIListLayout",BtnHolder)
		BHL.FillDirection=Enum.FillDirection.Horizontal; BHL.Padding=UDim.new(0,4)
		local current=default or 1
		local btns={}
		local function refreshBtns()
			for i,btn in ipairs(btns) do
				btn.BackgroundColor3=i==current and UI.C.ACCENT or UI.C.ELEVATED
				btn.TextColor3=i==current and UI.C.TEXT_1 or UI.C.TEXT_2
			end
		end
		for i=1,3 do
			local B=Instance.new("TextButton",BtnHolder)
			B.Size=UDim2.new(0,28,1,0); B.BackgroundColor3=i==current and UI.C.ACCENT or UI.C.ELEVATED
			UIH_Corner(UI,B,4); B.Text=tostring(i); B.TextColor3=i==current and UI.C.TEXT_1 or UI.C.TEXT_2
			B.Font=Enum.Font.GothamBold; B.TextSize=12; B.AutoButtonColor=false
			B.MouseButton1Click:Connect(function()
				current=i; refreshBtns(); callback(i)
			end)
			btns[i]=B
		end
		return Row
	end

function UIH_BuatShopDropdown(UI,parent, label, items, defaultId, callback)
		local options={}
		local idByDisplay={}
		for _,item in ipairs(items) do
			local display=item.displayName.."  ["..formatShort(item.cashPrice,"$").."]"
			options[#options+1]=display
			idByDisplay[display]=item.id
		end
		local selectedDisplay=""
		local displayById={}
		for _,item in ipairs(items) do
			displayById[item.id]=item.displayName.."  ["..formatShort(item.cashPrice,"$").."]"
		end
		if defaultId and defaultId~="" and displayById[defaultId] then
			selectedDisplay=displayById[defaultId]
		end
		local row, getter, setOptions, setter = UIH_BuatDropdown(UI,parent, label, options, false, selectedDisplay, function(val)
			local id=idByDisplay[val] or ""
			callback(id)
		end)
		if selectedDisplay~="" then setter(selectedDisplay) end
		return row
	end

-- Premium-only visual lock. This is intentionally local to Premium UI so
-- existing Farming/ESP/Shop/Teleport/Misc controls keep their old behavior.
local function UIH_LockPremiumRow(UI, row, label)
	if PremiumLicense.IsPremium then return end
	if not row or not row:IsA("GuiObject") then return end
	local blocker = Instance.new("TextButton")
	blocker.Name = "PremiumLockedOverlay"
	blocker.Size = UDim2.new(1,0,1,0)
	blocker.Position = UDim2.new(0,0,0,0)
	blocker.BackgroundTransparency = 1
	blocker.BorderSizePixel = 0
	blocker.Text = "LOCKED"
	blocker.TextColor3 = UI.C.TEXT_3
	blocker.Font = Enum.Font.GothamBold
	blocker.TextSize = 10
	blocker.TextXAlignment = Enum.TextXAlignment.Right
	blocker.TextYAlignment = Enum.TextYAlignment.Center
	blocker.AutoButtonColor = false
	blocker.ZIndex = 100
	blocker.Parent = row
	blocker.MouseButton1Click:Connect(function()
		Notify("Premium key required", 2)
	end)
end

UIHelpers={
	Corner=UIH_Corner,
	Stroke=UIH_Stroke,
	MakeDraggable=UIH_MakeDraggable,
	BuatPage=UIH_BuatPage,
	SwitchTab=UIH_SwitchTab,
	BuatNavButton=UIH_BuatNavButton,
	BuatSection=UIH_BuatSection,
	BuatLabel=UIH_BuatLabel,
	BuatToggle=UIH_BuatToggle,
	BuatButton=UIH_BuatButton,
	BuatSlider=UIH_BuatSlider,
	BuatInput=UIH_BuatInput,
	BuatDropdown=UIH_BuatDropdown,
	BuatStepSelect=UIH_BuatStepSelect,
	BuatShopDropdown=UIH_BuatShopDropdown,
}


function InitializeUI()
	local C={
		BASE    =Color3.fromRGB(13,  8,  32),
		SURFACE =Color3.fromRGB(22, 14,  46),
		ELEVATED=Color3.fromRGB(33, 22,  66),
		BORDER  =Color3.fromRGB(74, 45, 128),
		DIVIDER =Color3.fromRGB(30, 18,  58),
		TEXT_1  =Color3.fromRGB(237,232,255),
		TEXT_2  =Color3.fromRGB(184,159,232),
		TEXT_3  =Color3.fromRGB(112, 85,168),
		ACCENT  =Color3.fromRGB(139, 93,209),
		ACCENT_D=Color3.fromRGB(106, 58,170),
		DANGER  =Color3.fromRGB(196, 94,138),
		SHOP    =Color3.fromRGB(60,180,120),
		BOMB    =Color3.fromRGB(220,120, 40),
	}
	local MainSG=Instance.new("ScreenGui",GuiRoot)
	MainSG.Name="DScriptsPF"; MainSG.ResetOnSpawn=false
	local UI={C=C,MainSG=MainSG}
	local H=UIHelpers
	local Root=Instance.new("Frame",MainSG)
	Root.Size=UDim2.new(0,520,0,400); Root.Position=UDim2.new(0.5,-260,0.5,-200); Root.BackgroundTransparency=1
	local MinimizedIcon=Instance.new("ImageButton",Root)
	MinimizedIcon.Size=UDim2.new(1,0,1,0); MinimizedIcon.BackgroundTransparency=1
	MinimizedIcon.Image="rbxassetid://122511465288707"; MinimizedIcon.Visible=false
	MinimizedIcon.AutoButtonColor=false; H.Corner(UI,MinimizedIcon,8); H.MakeDraggable(UI,Root,MinimizedIcon)
	local Win=Instance.new("Frame",Root)
	Win.Size=UDim2.new(1,0,1,0); Win.BackgroundColor3=C.BASE; Win.ClipsDescendants=true; H.Corner(UI,Win,8); H.Stroke(UI,Win,C.BORDER,1)
	local Header=Instance.new("Frame",Win)
	Header.Size=UDim2.new(1,0,0,45); Header.BackgroundColor3=C.SURFACE; H.Corner(UI,Header,8)
	local HFix=Instance.new("Frame",Header)
	HFix.Size=UDim2.new(1,0,0,8); HFix.Position=UDim2.new(0,0,1,-8); HFix.BackgroundColor3=C.SURFACE; HFix.BorderSizePixel=0
	local AccentLine=Instance.new("Frame",Header)
	AccentLine.Size=UDim2.new(0,40,0,3); AccentLine.Position=UDim2.new(0,16,0,0)
	AccentLine.BackgroundColor3=C.ACCENT; AccentLine.BorderSizePixel=0; H.Corner(UI,AccentLine,2)
	local HeaderIcon=Instance.new("ImageLabel",Header)
	HeaderIcon.Size=UDim2.new(0,30,0,30); HeaderIcon.Position=UDim2.new(0,8,0.5,-15)
	HeaderIcon.BackgroundTransparency=1; HeaderIcon.Image="rbxassetid://122511465288707"
	H.Corner(UI,HeaderIcon,8)
	local TitleLbl=Instance.new("TextLabel",Header)
	TitleLbl.Size=UDim2.new(1,-132,1,0); TitleLbl.Position=UDim2.new(0,46,0,0)
	TitleLbl.BackgroundTransparency=1; TitleLbl.RichText=true
	TitleLbl.Text="D-HUB: <font color='#EB3C3C'>MINE A MOUNTAIN</font> <font color='#888'>v2.4</font>"
	TitleLbl.TextColor3=C.TEXT_1; TitleLbl.Font=Enum.Font.GothamBold; TitleLbl.TextSize=14; TitleLbl.TextXAlignment=Enum.TextXAlignment.Left
	H.MakeDraggable(UI,Root,Header)
	local originalSize=Root.Size; local minimizedSize=UDim2.new(0,52,0,52)
	local MinBtn=Instance.new("TextButton",Header)
	MinBtn.Size=UDim2.new(0,24,0,24); MinBtn.Position=UDim2.new(1,-34,0.5,-12)
	MinBtn.BackgroundColor3=C.SURFACE; MinBtn.BorderSizePixel=0; MinBtn.Text="—"
	MinBtn.TextColor3=C.TEXT_2; MinBtn.Font=Enum.Font.GothamBold; MinBtn.TextSize=14
	MinBtn.AutoButtonColor=false; H.Corner(UI,MinBtn,4)
	MinBtn.MouseButton1Click:Connect(function()
		Win.Visible=false; MinimizedIcon.Visible=true
		S.TweenService:Create(Root,TweenInfo.new(0.2),{Size=minimizedSize}):Play()
	end)
	MinimizedIcon.MouseButton1Click:Connect(function()
		Win.Visible=true; MinimizedIcon.Visible=false
		S.TweenService:Create(Root,TweenInfo.new(0.2),{Size=originalSize}):Play()
	end)
	local Body=Instance.new("Frame",Win)
	Body.Size=UDim2.new(1,0,1,-45); Body.Position=UDim2.new(0,0,0,45); Body.BackgroundTransparency=1
	local Sidebar=Instance.new("Frame",Body)
	Sidebar.Size=UDim2.new(0,140,1,0); Sidebar.BackgroundColor3=C.SURFACE; Sidebar.BorderSizePixel=0
	local SidebarStroke=Instance.new("Frame",Sidebar)
	SidebarStroke.Size=UDim2.new(0,1,1,0); SidebarStroke.Position=UDim2.new(1,0,0,0)
	SidebarStroke.BackgroundColor3=C.DIVIDER; SidebarStroke.BorderSizePixel=0
	local TabContainer=Instance.new("ScrollingFrame",Sidebar)
	TabContainer.Size=UDim2.new(1,0,1,-65); TabContainer.BackgroundTransparency=1
	TabContainer.BorderSizePixel=0; TabContainer.ScrollBarThickness=2
	local TabLayout=Instance.new("UIListLayout",TabContainer)
	TabLayout.Padding=UDim.new(0,5); TabLayout.HorizontalAlignment=Enum.HorizontalAlignment.Center
	Instance.new("UIPadding",TabContainer).PaddingTop=UDim.new(0,10)
	TabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		TabContainer.CanvasSize=UDim2.new(0,0,0,TabLayout.AbsoluteContentSize.Y+20)
	end)
	local ProfileContainer=Instance.new("Frame",Sidebar)
	ProfileContainer.Size=UDim2.new(1,0,0,65); ProfileContainer.Position=UDim2.new(0,0,1,-65)
	ProfileContainer.BackgroundColor3=C.BASE; ProfileContainer.BorderSizePixel=0
	local AvatarImg=Instance.new("ImageLabel",ProfileContainer)
	AvatarImg.Size=UDim2.new(0,36,0,36); AvatarImg.Position=UDim2.new(0,12,0.5,-18)
	AvatarImg.BackgroundColor3=C.SURFACE; AvatarImg.BorderSizePixel=0; H.Corner(UI,AvatarImg,18)
	task.spawn(function()
		pcall(function()
			AvatarImg.Image=S.Players:GetUserThumbnailAsync(LocalPlayer.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size420x420)
		end)
	end)
	local NameLbl=Instance.new("TextLabel",ProfileContainer)
	NameLbl.Size=UDim2.new(1,-60,0,16); NameLbl.Position=UDim2.new(0,56,0.5,-16)
	NameLbl.BackgroundTransparency=1; NameLbl.Text=LocalPlayer.DisplayName
	NameLbl.TextColor3=C.TEXT_1; NameLbl.Font=Enum.Font.GothamBold; NameLbl.TextSize=11; NameLbl.TextXAlignment=Enum.TextXAlignment.Left
	local PremiumLbl=Instance.new("TextLabel",ProfileContainer)
	PremiumLbl.Size=UDim2.new(1,-60,0,14); PremiumLbl.Position=UDim2.new(0,56,0.5,2)
	PremiumLbl.BackgroundTransparency=1; PremiumLbl.Text=PremiumLicense.IsPremium and "Premium" or "Free"
	PremiumLbl.TextColor3=C.ACCENT; PremiumLbl.Font=Enum.Font.GothamMedium; PremiumLbl.TextSize=10; PremiumLbl.TextXAlignment=Enum.TextXAlignment.Left
	local ContentArea=Instance.new("Frame",Body)
	ContentArea.Size=UDim2.new(1,-155,1,0); ContentArea.Position=UDim2.new(0,155,0,0); ContentArea.BackgroundTransparency=1
	local Pages,NavButtons={},{}
	UI.ContentArea=ContentArea; UI.TabContainer=TabContainer
	UI.Pages=Pages; UI.NavButtons=NavButtons
	UI.BuatPage=H.BuatPage; UI.BuatNavButton=H.BuatNavButton
	UI.BuatSection=H.BuatSection; UI.BuatLabel=H.BuatLabel
	UI.BuatToggle=H.BuatToggle; UI.BuatButton=H.BuatButton
	UI.BuatSlider=H.BuatSlider; UI.BuatInput=H.BuatInput
	UI.BuatDropdown=H.BuatDropdown; UI.BuatStepSelect=H.BuatStepSelect
	UI.BuatShopDropdown=H.BuatShopDropdown
	UI.activeDropdown=nil
	S.UserInputService.InputBegan:Connect(function(input)
		if not UI.activeDropdown or not UI.activeDropdown.Visible then return end
		if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
		local p=input.Position
		local pos=UI.activeDropdown.AbsolutePosition; local size=UI.activeDropdown.AbsoluteSize
		if p.X>=pos.X and p.X<=pos.X+size.X and p.Y>=pos.Y and p.Y<=pos.Y+size.Y then return end
		UI.activeDropdown.Visible=false; UI.activeDropdown=nil
	end)

	-- ============================================================
	-- TABS
	-- ============================================================
local PageNames={"Farming","Premium","Shop","ESP","Teleport","Misc"}
	for _,name in ipairs(PageNames) do H.BuatNavButton(UI,name); H.BuatPage(UI,name) end

	BuildTabsUI(UI)

	-- Initialization
	H.SwitchTab(UI,"Farming")
	Win.Visible=true
end


function BuildFarmingTab(UI,P_FAR)
	UI.BuatSection(UI,P_FAR,"Farm Money")
	UI.BuatInput(UI,P_FAR,"Minimum Crystal Value","Example: 1M / 1B / 1T",formatShort(minValue,"$"),function(text)
		local v=parseValue(text)
		minValue=math.max(0,tonumber(v) or 0)
		DHubState.valueFilter=minValue>0
		pcall(refreshCrystalVisibility)
		requestRefresh()
		saveConfig()
	end)

	-- Money Farm crystal directory:
	-- only crystals currently detected at/above the minimum are listed,
	-- sorted from highest value to lowest value.
	local farmCrystalDisplayToName={}
	local farmCrystalRow,farmCrystalGetter,farmCrystalSetOptions,farmCrystalSetSelected =
		UI.BuatDropdown(UI,P_FAR,"Crystal To Farm",{},true,{},function(selectedDisplays)
			table.clear(farmCrystalFilter)
			for _,display in ipairs(selectedDisplays) do
				local rawName=farmCrystalDisplayToName[display] or display
				if rawName and rawName~="" then farmCrystalFilter[rawName]=true end
			end
			saveConfig()
		end)

	local function refreshMoneyCrystalDropdown()
		local ok,entries=pcall(Money.scanEligibleCrystals)
		if not ok or type(entries)~="table" then
			farmCrystalSetOptions({})
			return
		end
		local options={}
		farmCrystalDisplayToName={}
		local displayByName={}
		for _,entry in ipairs(entries) do
			local display=string.format("%s  •  %s  •  %s",
				entry.name,entry.rarity,formatShort(entry.value,"$"))
			options[#options+1]=display
			farmCrystalDisplayToName[display]=entry.name
			displayByName[entry.name]=display
		end
		farmCrystalSetOptions(options)
		local selectedDisplays={}
		for name in pairs(farmCrystalFilter) do
			if displayByName[name] then selectedDisplays[#selectedDisplays+1]=displayByName[name] end
		end
		farmCrystalSetSelected(selectedDisplays)
	end

	local crystalRefreshBtn=UI.BuatButton(UI,P_FAR,"Refresh Crystal","Scan eligible crystals >= minimum value")
	crystalRefreshBtn.MouseButton1Click:Connect(function()
		refreshMoneyCrystalDropdown()
		Notify("Crystal list refreshed",2)
	end)

	local farmRarityRow = UI.BuatDropdown(UI,
		P_FAR,"Rarity To Farm",RARITY_LIST,true,
		(function() local t={}; for k in pairs(farmRarityFilter) do t[#t+1]=k end; return t end)(),
		function(selected)
			table.clear(farmRarityFilter)
			for _,v in ipairs(selected) do farmRarityFilter[v]=true end
			saveConfig()
		end
	)

	local M_FarmBtn,M_SetFarm=UI.BuatToggle(UI,
		P_FAR,"Auto Farm Crystal",
		"Continuously scans for eligible crystals, then digs them",
		Toggles.AutoFarmMoney
	)
	M_FarmBtn.MouseButton1Click:Connect(function()
		local v=not Toggles.AutoFarmMoney
		Toggles.AutoFarmMoney=v
		M_SetFarm(v)
		if v then refreshMoneyCrystalDropdown() end
		Money.setActive(v)
		saveConfig()
	end)

	local M_SellBtn,M_SetSell=UI.BuatToggle(UI,
		P_FAR,"Auto Sell At 50%",
		"Sell automatically when backpack reaches 50%",
		Toggles.MoneyAutoSell
	)
	M_SellBtn.MouseButton1Click:Connect(function()
		local v=not Toggles.MoneyAutoSell
		Toggles.MoneyAutoSell=v
		M_SetSell(v)
		saveConfig()
	end)

	local MoneyStatusLbl=UI.BuatLabel(UI,P_FAR,"Idle")
	Money._getStatusLabel(MoneyStatusLbl)
	refreshMoneyCrystalDropdown()

	UI.BuatSection(UI,P_FAR,"Boulder Farm")
	local boulderFarmOptions={"Mossite","Voltite","Gildrite","Rimeveil","Nocturnite"}
	local boulderFarmRow=UI.BuatDropdown(UI,
		P_FAR,"Boulder To Farm",boulderFarmOptions,true,
		(function() local t={}; for k in pairs(Cache.boulderFarmFilter) do t[#t+1]=k end; return t end)(),
		function(selected)
			table.clear(Cache.boulderFarmFilter)
			for _,v in ipairs(selected) do Cache.boulderFarmFilter[v]=true end
			Farm.setTargets(Cache.boulderFarmFilter)
			saveConfig()
		end
	)

	local BF_Btn,BF_Set=UI.BuatToggle(UI,
		P_FAR,"Auto Farm Boulder",
		"Mine selected Boulders and manage their 3s post-break loot",
		Toggles.AutoFarmBoulders
	)
	BF_Btn.MouseButton1Click:Connect(function()
		local v=not Toggles.AutoFarmBoulders
		Toggles.AutoFarmBoulders=v
		BF_Set(v)
		Farm.setTargets(Cache.boulderFarmFilter)
		Farm.setActive(v)
		saveConfig()
	end)

	local pickRarityRow = UI.BuatDropdown(UI,
		P_FAR,"Rarity To Pickup",RARITY_LIST,true,
		(function() local t={}; for k in pairs(rarityPickupFilter) do t[#t+1]=k end; return t end)(),
		function(selected)
			table.clear(rarityPickupFilter)
			for _,v in ipairs(selected) do rarityPickupFilter[v]=true end
			saveConfig()
		end
	)

	UI.BuatInput(UI,
		P_FAR,"Min Luck To Pickup","Example: 10%",string.format("%g%%",boulderMinLuck),
		function(text)
			local cleaned=tostring(text or ""):gsub("%%", "")
			cleaned=cleaned:match("^%s*(.-)%s*$") or cleaned
			local n=tonumber(cleaned) or 0
			boulderMinLuck=math.clamp(n,0,100000)
			saveConfig()
		end
	)

	local F_PickBtn,F_SetPick=UI.BuatToggle(UI,
		P_FAR,"Auto Pickup Crystal",
		"Only picks Boulder drops during the 3s loot window",
		Toggles.AutoPickup
	)
	F_PickBtn.MouseButton1Click:Connect(function()
		autoPickupActive=not autoPickupActive
		Toggles.AutoPickup=autoPickupActive
		F_SetPick(autoPickupActive)
		saveConfig()
	end)

	local F_RuneBtn,F_SetRune=UI.BuatToggle(UI,
		P_FAR,"Auto Pickup Rune",
		"Pick all Boulder-drop runes",
		Toggles.AutoRunePickup
	)
	F_RuneBtn.MouseButton1Click:Connect(function()
		local v=not Toggles.AutoRunePickup
		Toggles.AutoRunePickup=v
		F_SetRune(v)
		Mountain.setAutoGrab(v)
		saveConfig()
	end)

	Runtime.FarmMethodButton,Runtime.FarmMethodGet,Runtime.FarmMethodSet = UI.BuatDropdown(UI,
		P_FAR,"Farm Method",{"Current Server","Random Server"},false,Runtime.farmMethod,
		function(selected)
			if selected=="Random Server" then Runtime.farmMethod="Random Server" else Runtime.farmMethod="Current Server" end
			saveConfig()
		end
	)

	local F_InstBtn,F_SetInst=UI.BuatToggle(UI,
		P_FAR,"Instant Pickup",
		"Make pickup prompts instant",
		Toggles.InstantPrompt
	)
	F_InstBtn.MouseButton1Click:Connect(function()
		instantPromptActive=not instantPromptActive
		Toggles.InstantPrompt=instantPromptActive
		F_SetInst(instantPromptActive)
		setInstantPrompt(instantPromptActive)
		saveConfig()
	end)

	Runtime.AutoDigButton,Runtime.AutoDigSet = UI.BuatToggle(UI,
		P_FAR,"Auto Dig","Dig rapidly at aim point",Toggles.AutoDig
	)
	Runtime.AutoDigButton.MouseButton1Click:Connect(function()
		Toggles.AutoDig=not Toggles.AutoDig
		Runtime.AutoDigSet(Toggles.AutoDig)
		if not Toggles.AutoDig then Runtime.autoDigAccumulator=0 end
		saveConfig()
	end)

	Runtime.BackpackLabel=UI.BuatLabel(UI,P_FAR,"0 / 0 KG")
	UI.BuatSection(UI,P_FAR,"Bombs")
	local AB_Btn2,AB_Set2=UI.BuatToggle(UI,P_FAR,"Auto Use Bombs","Use bombs automatically",Toggles.AutoBomb,UI.C.BOMB)
	AB_Btn2.MouseButton1Click:Connect(function()
		local v=not Toggles.AutoBomb; Toggles.AutoBomb=v; AB_Set2(v); autoBombActive=v; AutoBomb.setActive(v); saveConfig()
	end)
	local BombStatusLbl2=UI.BuatLabel(UI,P_FAR,"Idle")
	AutoBomb._getStatusLabel(BombStatusLbl2)
	UI.BuatSection(UI,P_FAR,"Upgrade Dynamic Crystal List")
	local allRefreshBtn=UI.BuatButton(UI,P_FAR,"Refresh Loot Lists","Refresh Money targets + Boulder loot directories")
	allRefreshBtn.MouseButton1Click:Connect(function()
		refreshMoneyCrystalDropdown()
		local names=getTrackedCrystalNames()
		Notify(string.format("Crystal list refreshed: %d",#names),2)
	end)

	end

function BuildPremiumTab(UI,P_PRE)
	UI.BuatSection(UI,P_PRE,"Premium Prismarite Farm")

	local PP_RarityRow = UI.BuatDropdown(UI,
		P_PRE,"Rarity To Pickup",RARITY_LIST,true,
		(function() local t={}; for k in pairs(premiumRarityFilter) do t[#t+1]=k end; return t end)(),
		function(selected)
			table.clear(premiumRarityFilter)
			for _,v in ipairs(selected) do premiumRarityFilter[v]=true end
			saveConfig()
		end
	)
	UIH_LockPremiumRow(UI,PP_RarityRow,"Rarity To Pickup")

	local PP_LuckRow = UI.BuatInput(UI,
		P_PRE,"Min Luck To Pickup","Example: 10%",string.format("%g%%",DHubState.premiumMinLuck),
		function(value)
			local cleaned=tostring(value or ""):gsub("%%","")
			cleaned=cleaned:match("^%s*(.-)%s*$") or cleaned
			DHubState.premiumMinLuck=math.clamp(tonumber(cleaned) or 0,0,100000)
			saveConfig()
		end
	)
	UIH_LockPremiumRow(UI,PP_LuckRow,"Min Luck To Pickup")

	local PP_MethodRow = UI.BuatDropdown(UI,
		P_PRE,"Select Method",{"Current Server","Random Server"},false,DHubState.premiumFarmMethod,
		function(selected)
			DHubState.premiumFarmMethod=(selected=="Random Server") and "Random Server" or "Current Server"
			saveConfig()
		end
	)
	UIH_LockPremiumRow(UI,PP_MethodRow,"Select Method")

	local PP_PickBtn,PP_SetPick=UI.BuatToggle(UI,
		P_PRE,"Auto Pickup Crystal",
		"Pick crystals inside the active Prismarite area using the selected filter",
		Toggles.PremiumAutoPickup
	)
	if not PremiumLicense.IsPremium then PP_SetPick(false) end
	PP_PickBtn.MouseButton1Click:Connect(function()
		if not PremiumLicense.IsPremium then Notify("Premium key required",2); return end
		local v=not Toggles.PremiumAutoPickup
		Toggles.PremiumAutoPickup=v
		PP_SetPick(v)
		saveConfig()
	end)
	UIH_LockPremiumRow(UI,PP_PickBtn.Parent,"Auto Pickup Crystal")

	local PP_FarmBtn,PP_SetFarm=UI.BuatToggle(UI,
		P_PRE,"Auto Farm Prismarite",
		"Scan the terrain, fly to each Prismarite area, dig it out, then continue",
		Toggles.AutoFarmPrismarite
	)
	if not PremiumLicense.IsPremium then PP_SetFarm(false) end
	PP_FarmBtn.MouseButton1Click:Connect(function()
		if not PremiumLicense.IsPremium then Notify("Premium key required",2); return end
		local v=not Toggles.AutoFarmPrismarite
		Toggles.AutoFarmPrismarite=v
		autoFarmPrismariteActive=v
		PP_SetFarm(v)
		PremiumPrismarite.setActive(v)
		Runtime.PrismariteFarmActive=v
		saveConfig()
	end)
	UIH_LockPremiumRow(UI,PP_FarmBtn.Parent,"Auto Farm Prismarite")

	UI.BuatSection(UI,P_PRE,"Boulder Dig Speed")

	local BD_FastBtn,BD_SetFast=UI.BuatToggle(UI,
		P_PRE,"Fast Dig",
		"Increase Boulder burst frequency; OFF keeps the current/default speed",
		DHubState.boulderFastDig
	)
	if not PremiumLicense.IsPremium then BD_SetFast(false) end
	BD_FastBtn.MouseButton1Click:Connect(function()
		if not PremiumLicense.IsPremium then Notify("Premium key required",2); return end
		DHubState.boulderFastDig=not DHubState.boulderFastDig
		BD_SetFast(DHubState.boulderFastDig)
		saveConfig()
	end)
	UIH_LockPremiumRow(UI,BD_FastBtn.Parent,"Fast Dig")

	local BD_SpeedRow = UI.BuatSlider(UI,P_PRE,"Dig Speed",100,500,DHubState.boulderDigSpeed,function(v)
		if not PremiumLicense.IsPremium then return end
		DHubState.boulderDigSpeed=math.clamp(tonumber(v) or 200,100,500)
		saveConfig()
	end)
	UIH_LockPremiumRow(UI,BD_SpeedRow,"Dig Speed")

	if not PremiumLicense.IsPremium then
		UI.BuatLabel(UI,P_PRE,"Premium features are locked. Set getgenv().key before loading the script.")
	end
end

function BuildESPTab(UI,P_ESP)
	UI.BuatSection(UI,P_ESP,"Player")
	local P_PBtn,P_SetP=UI.BuatToggle(UI,P_ESP,"Player ESP","Show other players through walls",Toggles.PlayerEsp)
	P_PBtn.MouseButton1Click:Connect(function()
		playerEspActive=not playerEspActive; Toggles.PlayerEsp=playerEspActive; P_SetP(playerEspActive)
		if not playerEspActive then clearPlayerEsp() end; saveConfig()
	end)
	UI.BuatSlider(UI,P_ESP,"Player Size",40,250,math.floor(playerScale*100),function(v) playerScale=v/100; applyPlayerScale(); saveConfig() end)

	UI.BuatSection(UI,P_ESP,"Veins")
	local veinEspDropRow, veinEspGetter, veinEspSetOptions = UI.BuatDropdown(UI,
		P_ESP,"Vein To ESP",VeinsModule.getTrackedVeinNames(),true,
		(function() local t={}; for k in pairs(veinEspFilter) do t[#t+1]=k end; return t end)(),
		function(selected)
			table.clear(veinEspFilter)
			for _,v in ipairs(selected) do veinEspFilter[v]=true end
			saveConfig()
		end
	)
	local V_EspBtn,V_SetEsp=UI.BuatToggle(UI,P_ESP,"Vein ESP","Show ESP on all active Veins",Toggles.VeinEsp)
	V_EspBtn.MouseButton1Click:Connect(function()
		veinEspActive=not veinEspActive; Toggles.VeinEsp=veinEspActive; V_SetEsp(veinEspActive)
		VeinsModule.setVeinEsp(veinEspActive); saveConfig()
	end)

	local PR_EspBtn,PR_SetEsp=UI.BuatToggle(UI,
		P_ESP,"Prismarite ESP","Show Terrain WoodPlanks as Prismarite",Toggles.PrismariteEsp
	)
	local PR_StatsLbl=UI.BuatLabel(UI,P_ESP,"Prismarite: 0  |  Nearest: --  |  Farm: OFF")
	Runtime.PrismariteEspSet=function(value)
		prismariteEspActive=value==true
		Toggles.PrismariteEsp=prismariteEspActive
		PR_SetEsp(prismariteEspActive)
		PrismariteModule.setActive(prismariteEspActive)
	end
	PR_EspBtn.MouseButton1Click:Connect(function()
		Runtime.PrismariteEspSet(not prismariteEspActive)
		saveConfig()
	end)
	task.spawn(function()
		while PR_StatsLbl and PR_StatsLbl.Parent do
			local root=getRoot()
			local count,nearest=PrismariteModule.getStats(root and root.Position or nil)
			local nearText=nearest and string.format("%dm",math.floor(nearest)) or "--"
			local farmText=Toggles.AutoFarmPrismarite and "ACTIVE" or "OFF"
			PR_StatsLbl.Text=string.format("Prismarite: %d  |  Nearest: %s  |  Farm: %s",count,nearText,farmText)
			task.wait(0.35)
		end
	end)

	UI.BuatSection(UI,P_ESP,"Crystals")
	local crystalEspDropRow, crystalEspGetter, crystalEspSetOptions = UI.BuatDropdown(UI,
		P_ESP,"Crystal To ESP",getTrackedCrystalNames(),true,
		(function() local t={}; for k in pairs(crystalEspFilter) do t[#t+1]=k end; return t end)(),
		function(selected)
			table.clear(crystalEspFilter)
			for _,v in ipairs(selected) do crystalEspFilter[v]=true end
			requestRefresh(); saveConfig()
		end
	)
	local C_EspBtn,C_SetEsp=UI.BuatToggle(UI,P_ESP,"Crystal ESP","Show ESP on all tracked crystals",Toggles.CrystalEsp)
	C_EspBtn.MouseButton1Click:Connect(function()
		espActive=not espActive; Toggles.CrystalEsp=espActive; C_SetEsp(espActive)
		if not espActive then clearEsp() end; updateTracking(); saveConfig()
	end)
	UI.BuatSlider(UI,P_ESP,"Crystal/Vein Size",40,250,math.floor(espScale*100),function(v) espScale=v/100; applyEspScale(); VeinsModule.applyScale(); PrismariteModule.applyScale(); saveConfig() end)
	Runtime.StatsLabel=UI.BuatLabel(UI,P_ESP,"Tracking: 0  |  Shown: 0")
	UI.BuatSection(UI,P_ESP,"Boulders")
	local boulderEspDropRow = UI.BuatDropdown(UI,
		P_ESP,"Boulder To ESP",{"Mossite","Voltite","Gildrite","Rimeveil","Nocturnite"},true,
		(function() local t={}; for k in pairs(boulderEspFilter) do t[#t+1]=k end; return t end)(),
		function(selected)
			table.clear(boulderEspFilter)
			for _,v in ipairs(selected) do boulderEspFilter[v]=true end
			saveConfig()
		end
	)

	local B_EspBtn,B_SetEsp=UI.BuatToggle(UI,P_ESP,"Boulder ESP","Show info on nearby boulders",Toggles.BoulderEsp)
	B_EspBtn.MouseButton1Click:Connect(function()
		local v=not Toggles.BoulderEsp; Toggles.BoulderEsp=v; B_SetEsp(v); Mountain.setBoulderEsp(v); saveConfig()
	end)
	UI.BuatSlider(UI,P_ESP,"Boulder Size",40,250,math.floor(boulderScale*100),function(v) boulderScale=v/100; Mountain.applyScale(); saveConfig() end)
	UI.BuatButton(UI,P_ESP,"Refresh ESP Lists","Update dropdowns from workspace").MouseButton1Click:Connect(function()
		local names=getTrackedCrystalNames()
		crystalEspSetOptions(names)
		veinEspSetOptions(VeinsModule.getTrackedVeinNames())
		Notify("ESP lists updated",2)
	end)

	end

function BuildTeleportTab(UI,P_TEL)
	UI.BuatSection(UI,P_TEL,"Teleport Crystal")
	local T_AimBtn,T_SetAim=UI.BuatToggle(UI,P_TEL,"Aim Teleport (F key)","Teleport toward aimed crystal",Toggles.AimTeleport)
	T_AimBtn.MouseButton1Click:Connect(function()
		aimTpEnabled=not aimTpEnabled; Toggles.AimTeleport=aimTpEnabled; T_SetAim(aimTpEnabled); saveConfig()
	end)
	UI.BuatSection(UI,P_TEL,"Quick Teleport")
	local function fmtValue(_,score) return formatShort(score,"$") end
	local function fmtLuck(_,score)  return formatLuck(score) end
	local function fmtWeight(inst)   return formatWeight(crystalWeight(inst)) end
	UI.BuatButton(UI,P_TEL,"Teleport High Value","TP to highest value crystal").MouseButton1Click:Connect(function()
		Runtime.tpToRank(crystalValue,1,fmtValue)
	end)
	UI.BuatButton(UI,P_TEL,"Teleport High Luck","TP to highest luck crystal").MouseButton1Click:Connect(function()
		Runtime.tpToRank(crystalLuck,1,fmtLuck)
	end)
	UI.BuatButton(UI,P_TEL,"Teleport High Weight","TP to heaviest crystal").MouseButton1Click:Connect(function()
		Runtime.tpToRank(crystalWeight,1,fmtWeight)
	end)
	UI.BuatButton(UI,P_TEL,"Teleport Home","Go to your home base").MouseButton1Click:Connect(function()
		if fireRemote(RMT.GoHome,"home") then Notify("Teleporting home",2) end
	end)

	end

function BuildMiscTab(UI,P_MIS)
	UI.BuatSection(UI,P_MIS,"Movement")
	local M_SpdBtn,M_SetSpd=UI.BuatToggle(UI,P_MIS,"Speed Boost","Walk faster",Toggles.SpeedBoost)
	M_SpdBtn.MouseButton1Click:Connect(function()
		speedActive=not speedActive; Toggles.SpeedBoost=speedActive; M_SetSpd(speedActive); setSpeedBoost(speedActive); saveConfig()
	end)
	local M_FlyBtn,M_SetFly=UI.BuatToggle(UI,P_MIS,"Fly","Fly around freely",Toggles.Fly)
	M_FlyBtn.MouseButton1Click:Connect(function()
		local v=not Toggles.Fly; Toggles.Fly=v; M_SetFly(v); Move.setFly(v); saveConfig()
	end)
	UI.BuatSlider(UI,P_MIS,"Fly Speed",10,500,100,function(v) Move.setFlySpeed(v) end)
	local M_ClipBtn,M_SetClip=UI.BuatToggle(UI,P_MIS,"Noclip","Walk through objects",Toggles.Noclip)
	M_ClipBtn.MouseButton1Click:Connect(function()
		local v=not Toggles.Noclip; Toggles.Noclip=v; M_SetClip(v); Move.setNoclip(v); saveConfig()
	end)
	local M_JmpBtn,M_SetJmp=UI.BuatToggle(UI,P_MIS,"Infinite Jump","Jump in mid-air",Toggles.InfJump)
	M_JmpBtn.MouseButton1Click:Connect(function()
		local v=not Toggles.InfJump; Toggles.InfJump=v; M_SetJmp(v); Move.setInfJump(v); saveConfig()
	end)

	UI.BuatSection(UI,P_MIS,"Utility")
	local U_RevBtn,U_SetRev=UI.BuatToggle(UI,P_MIS,"Auto Revive","Instantly revive on death",Toggles.AutoRevive)
	U_RevBtn.MouseButton1Click:Connect(function()
		local v=not Toggles.AutoRevive; Toggles.AutoRevive=v; U_SetRev(v); autoReviveActive=v; saveConfig()
	end)
	local U_FpsBtn,U_SetFps=UI.BuatToggle(UI,P_MIS,"FPS Boost","Ultra performance mode - particles, shadows, post FX and low-value crystals",Toggles.FpsBoost)
	U_FpsBtn.MouseButton1Click:Connect(function()
		local v=not Toggles.FpsBoost
		U_SetFps(v)
		applyFpsBoost(v)
		saveConfig()
	end)

	UI.BuatSection(UI,P_MIS,"Server")
	local U_HopBtn,U_SetHop=UI.BuatToggle(UI,P_MIS,"Auto Hop","Hop server every X minutes",Toggles.AutoHop)
	U_HopBtn.MouseButton1Click:Connect(function()
		local v=not Toggles.AutoHop; Toggles.AutoHop=v; U_SetHop(v); setAutoHop(v); saveConfig()
	end)
	UI.BuatSlider(UI,P_MIS,"Auto Hop Minutes",5,120,DHubState.autoHopMinutes,function(v)
		DHubState.autoHopMinutes=v; if autoHopActive then setAutoHop(true) end; saveConfig()
	end)
	UI.BuatButton(UI,P_MIS,"Hop Server","Join a different server").MouseButton1Click:Connect(function() Net.hop() end)
	UI.BuatButton(UI,P_MIS,"Rejoin Server","Rejoin current server").MouseButton1Click:Connect(function() Net.rejoin() end)

	end

function BuildTabsUI(UI)
	BuildFarmingTab(UI,UI.Pages.Farming)
	BuildPremiumTab(UI,UI.Pages.Premium)
	BuildShopTab(UI,UI.Pages.Shop)
	BuildESPTab(UI,UI.Pages.ESP)
	BuildTeleportTab(UI,UI.Pages.Teleport)
	BuildMiscTab(UI,UI.Pages.Misc)
end

InitializeUI()

-- Init Features
if Toggles.FpsBoost then applyFpsBoost(true) end
if Toggles.AutoHop then setAutoHop(true) end
if Toggles.CrystalEsp then updateTracking() end
if Toggles.VeinEsp then VeinsModule.setVeinEsp(true) end

-- Restore visual Prismarite ESP only when its own toggle is saved ON.
-- Premium Farm separately restores its hidden scanner below.
if Toggles.PrismariteEsp then
	prismariteEspActive=true
	PrismariteModule.setActive(true)
end

if Toggles.BoulderEsp then Mountain.setBoulderEsp(true) end
if Toggles.AutoFarmBoulders then Farm.setTargets(Cache.boulderFarmFilter); Farm.setActive(true) end
if PremiumLicense.IsPremium and Toggles.AutoFarmPrismarite then
	autoFarmPrismariteActive=true
	PremiumPrismarite.setActive(true)
end
if Toggles.AutoFarmMoney then Money.setActive(true) end
if Toggles.AutoBomb then AutoBomb.setActive(true) end
if Toggles.AutoRunePickup and Toggles.AutoFarmBoulders then Mountain.setAutoGrab(true) end
if instantPromptActive then setInstantPrompt(true) end
if speedActive then setSpeedBoost(true) end

-- Persist normalized Prismarite Farm/ESP state after startup.
saveConfig()
