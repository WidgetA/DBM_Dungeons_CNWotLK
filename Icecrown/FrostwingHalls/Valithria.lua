local mod	= DBM:NewMod("Valithria", "DBM-Raids-WoTLK", 2)
local L		= mod:GetLocalizedStrings()

mod.statTypes = "normal,normal25,heroic,heroic25"

mod:SetRevision("20241103133102")
mod:SetCreatureID(36789)
mod:SetEncounterID(not mod:IsPostCata() and 854 or 1098)
mod:SetModelID(30318)
mod:SetUsedIcons(8)
mod:SetZone(631)
mod.onlyHighest = true--Instructs DBM health tracking to literally only store highest value seen during fight, even if it drops below that
mod:RegisterCombat("combat")

mod:RegisterEventsInCombat(
	"SPELL_CAST_START 70754",
	"SPELL_CAST_SUCCESS 71179 70588",
	"SPELL_AURA_APPLIED 70633 70751 69325 70873 71941",
	"SPELL_AURA_APPLIED_DOSE 70751 70873 71941",
	"SPELL_AURA_REMOVED 70633 69325 70873 71941",
	"SPELL_DAMAGE 71086",
	"SPELL_MISSED 71086",
	"CHAT_MSG_MONSTER_YELL",
	"UNIT_SPELLCAST_START boss1"
)

--Known Issue. Weak aura key can't identify portal open from portal close timer. Both send same key. keep this in mind
local warnCorrosion			= mod:NewStackAnnounce(70751, 2, nil, false)
local warnGutSpray			= mod:NewTargetAnnounce(70633, 3, nil, "Tank|Healer")
local warnManaVoid			= mod:NewSpellAnnounce(71179, 2, nil, "ManaUser")
local warnSupression		= mod:NewTargetAnnounce(70588, 3)
local warnPortalSoon		= mod:NewSoonAnnounce(72483, 2)
local warnPortal			= mod:NewSpellAnnounce(72483, 3)
local warnPortalOpen		= mod:NewAnnounce("WarnPortalOpen", 4, 72483, nil, nil, nil, 72483)

local specWarnGutSpray		= mod:NewSpecialWarningDefensive(70633, nil, nil, nil, 1, 2)
local specWarnLayWaste		= mod:NewSpecialWarningSpell(69325, nil, nil, nil, 2, 2)
local specWarnGTFO			= mod:NewSpecialWarningGTFO(71179, nil, nil, nil, 1, 8)

local timerLayWaste			= mod:NewBuffActiveTimer(12, 69325, nil, nil, nil, 2)
local timerNextPortal		= mod:NewCDTimer(46.5, 72483, nil, nil, nil, 5, nil, DBM_COMMON_L.HEALER_ICON)
local timerPortalsOpen		= mod:NewTimer(15, "TimerPortalsOpen", 72483, nil, nil, 6, DBM_COMMON_L.HEALER_ICON, nil, nil, nil, nil, nil, nil, 72483)
local timerPortalsClose		= mod:NewTimer(10, "TimerPortalsClose", 72483, nil, nil, 6, DBM_COMMON_L.HEALER_ICON, nil, nil, nil, nil, nil, nil, 72483)
local timerHealerBuff		= mod:NewBuffFadesTimer(40, 70873, nil, nil, nil, 5, nil, DBM_COMMON_L.HEALER_ICON)
local timerGutSpray			= mod:NewTargetTimer(12, 70633, nil, "Tank|Healer", nil, 5)
local timerCorrosion		= mod:NewTargetTimer(6, 70751, nil, false, nil, 3)
local timerBlazingSkeleton	= mod:NewTimer(50, "TimerBlazingSkeleton", 17204, nil, nil, 1, DBM_COMMON_L.DAMAGE_ICON, nil, nil, nil, nil, nil, nil, 17204, nil, L.BlazingSkeleton)
local timerAbom				= mod:NewTimer(50, "TimerAbom", 43392, nil, nil, 1, DBM_COMMON_L.TANK_ICON..DBM_COMMON_L.DAMAGE_ICON, nil, nil, nil, nil, nil, nil, 43392, nil, L.GluttonousAbomination)

local berserkTimer			= mod:NewBerserkTimer(420)

mod:AddSetIconOption("SetIconOnBlazingSkeleton", nil, true, 5, {8}, nil, 17204)

mod.vb.BlazingSkeletonTimer = 60
mod.vb.AbomSpawn = 0
mod.vb.AbomTimer = 60

local function StartBlazingSkeletonTimer(self)
	timerBlazingSkeleton:Start(self.vb.BlazingSkeletonTimer)
	self:Schedule(self.vb.BlazingSkeletonTimer, StartBlazingSkeletonTimer, self)
	if self.vb.BlazingSkeletonTimer >= 10 then--Keep it from dropping below 5
		self.vb.BlazingSkeletonTimer = self.vb.BlazingSkeletonTimer - 5
	end
end

--23, 60, 55, 55, 55, 50, 45, 40, 35, etc (at least on normal, on heroic it might be only 2 55s, need more testing)
local function StartAbomTimer(self)
	self.vb.AbomSpawn = self.vb.AbomSpawn + 1
	if self.vb.AbomSpawn == 1 then
		timerAbom:Start(self.vb.AbomTimer)--Timer is 60 seconds after first early abom, it's set to 60 on combat start.
		self:Schedule(self.vb.AbomTimer, StartAbomTimer, self)
		self.vb.AbomTimer = self.vb.AbomTimer - 5--Right after first abom timer starts, change it from 60 to 55.
	elseif self.vb.AbomSpawn == 2 or self.vb.AbomSpawn == 3 then
		timerAbom:Start(self.vb.AbomTimer)--Start first and second 55 second timer
		self:Schedule(self.vb.AbomTimer, StartAbomTimer, self)
	elseif self.vb.AbomSpawn >= 4 then--after 4th abom, the timer starts subtracting again.
		timerAbom:Start(self.vb.AbomTimer)--Start third 55 second timer before subtracking from it again.
		self:Schedule(self.vb.AbomTimer, StartAbomTimer, self)
		if self.vb.AbomTimer >= 10 then--Keep it from dropping below 5
			self.vb.AbomTimer = self.vb.AbomTimer - 5--Rest of timers after 3rd 55 second timer will be 5 less than previous until they come every 5 seconds.
		end
	end
end

local function Portals(self)
	warnPortal:Show()
	warnPortalOpen:Cancel()
	timerPortalsOpen:Cancel()
	warnPortalSoon:Cancel()
	warnPortalOpen:Schedule(15)
	timerPortalsOpen:Start()
	timerPortalsClose:Schedule(15)
	warnPortalSoon:Schedule(41)
	timerNextPortal:Start()
	self:Unschedule(Portals)
	self:Schedule(46.5, Portals, self)--This will never be perfect, since it's never same. 45-48sec variations
end

function mod:OnCombatStart(delay)
	if self:IsDifficulty("heroic10", "heroic25") then
		berserkTimer:Start(-delay)
	end
	timerNextPortal:Start()
	warnPortalSoon:Schedule(41)
	self:Schedule(46.5, Portals, self)--This will never be perfect, since it's never same. 45-48sec variations
	self.vb.BlazingSkeletonTimer = 60
	self.vb.AbomTimer = 60
	self.vb.AbomSpawn = 0
	self:Schedule(50-delay, StartBlazingSkeletonTimer, self)
	self:Schedule(23-delay, StartAbomTimer, self)--First abom is 23-25 seconds after combat start, cause of variation, it may cause slightly off timer rest of fight
	timerBlazingSkeleton:Start(-delay)
	timerAbom:Start(23-delay)
end

function mod:SPELL_CAST_START(args)
	if args.spellId == 70754 then--Fireball (its the first spell Blazing SKeleton's cast upon spawning)
		if self.Options.SetIconOnBlazingSkeleton then
			self:ScanForMobs(args.sourceGUID, 2, 8, 1, nil, 12, "SetIconOnBlazingSkeleton")
		end
	end
end

function mod:SPELL_CAST_SUCCESS(args)
	if args.spellId == 71179 then--Mana Void
		warnManaVoid:Show()
	elseif args.spellId == 70588 and self:AntiSpam(5, 1) then--Supression
		warnSupression:Show(args.destName)
	end
end

function mod:SPELL_AURA_APPLIED(args)
	if args.spellId == 70633 and args:IsDestTypePlayer() then--Gut Spray
		timerGutSpray:Start(args.destName)
		warnGutSpray:CombinedShow(0.3, args.destName)
		if self:IsTank() then
			specWarnGutSpray:Show()
			specWarnGutSpray:Play("defensive")
		end
	elseif args.spellId == 70751 and args:IsDestTypePlayer() then--Corrosion
		warnCorrosion:Show(args.destName, args.amount or 1)
		timerCorrosion:Start(args.destName)
	elseif args.spellId == 69325 then--Lay Waste
		specWarnLayWaste:Show()
		specWarnLayWaste:Play("aesoon")
		timerLayWaste:Start()
	elseif args:IsSpellID(70873, 71941) and args:IsPlayer() then	--Emerald Vigor/Twisted Nightmares (portal healers)
		timerHealerBuff:Stop()
		timerHealerBuff:Start()
	end
end
mod.SPELL_AURA_APPLIED_DOSE = mod.SPELL_AURA_APPLIED

function mod:SPELL_AURA_REMOVED(args)
	if args.spellId == 70633 then--Gut Spray
		timerGutSpray:Cancel(args.destName)
	elseif args.spellId == 69325 then--Lay Waste
		timerLayWaste:Cancel()
	elseif args:IsSpellID(70873, 71941) and args:IsPlayer() then	--Emerald Vigor/Twisted Nightmares (portal healers)
		timerHealerBuff:Stop()
	end
end

function mod:SPELL_DAMAGE(_, _, _, _, destGUID, _, _, _, spellId, spellName)
	if spellId == 71086 and destGUID == UnitGUID("player") and self:AntiSpam(2, 2) then		-- Mana Void
		specWarnGTFO:Show(spellName)
		specWarnGTFO:Play("watchfeet")
	end
end
mod.SPELL_MISSED = mod.SPELL_DAMAGE

function mod:UNIT_SPELLCAST_START(uId, _, spellId)
	if spellId == 71189 then
		DBM:EndCombat(self)
	end
end

function mod:CHAT_MSG_MONSTER_YELL(msg)
	if (msg == L.YellPortals or msg:find(L.YellPortals)) and self:LatencyCheck() then
		self:SendSync("NightmarePortal")
	end
end

function mod:OnSync(msg, arg)
	if msg == "NightmarePortal" and self:IsInCombat() then
		self:Unschedule(Portals)
		Portals(self)
	end
end
