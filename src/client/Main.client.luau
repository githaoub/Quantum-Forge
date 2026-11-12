--!strict
-- Client entry point.
--
-- Boot order matters here too: the state store has to be listening before any
-- controller subscribes, and the canvas has to exist before anything is parented
-- into it. After that, everything is independent — each controller owns its own
-- subtree and its own subscriptions, which is why a tab switch cannot leak.
--
-- Two clocks exist in this file and they are not interchangeable:
--   * StateStore.onSync fires at the server's 10Hz cadence, on new data.
--   * RenderStepped fires at the player's framerate, for smoothing and input.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ForgeConfig = require(Shared:WaitForChild("ForgeConfig"))
local Types = require(Shared:WaitForChild("Types"))
local NumberUtil = require(Shared:WaitForChild("NumberUtil"))

local Theme = require(script.Parent.Theme)
local Layout = require(script.Parent.Layout)
local UiKit = require(script.Parent.UiKit)
local StateStore = require(script.Parent.StateStore)
local Vfx = require(script.Parent.Vfx)
local SpriteFx = require(script.Parent.SpriteFx)
local Sfx = require(script.Parent.Sfx)
local Music = require(script.Parent.Music)
local Notifications = require(script.Parent.Notifications)
local Modals = require(script.Parent.Modals)
local FeedbackView = require(script.Parent.FeedbackView)
local HudController = require(script.Parent.HudController)
local ForgeView = require(script.Parent.ForgeView)
local DroneView = require(script.Parent.DroneView)
local Sections = require(script.Parent.Sections)
local InventoryModal = require(script.Parent.InventoryModal)
local CodexView = require(script.Parent.CodexView)
local LeaderboardView = require(script.Parent.LeaderboardView)
local TradeView = require(script.Parent.TradeView)
local HandbookView = require(script.Parent.HandbookView)
local CratesView = require(script.Parent.CratesView)
local CrateReveal = require(script.Parent.CrateReveal)
local DailyView = require(script.Parent.DailyView)
local OrbitalLobby = require(script.Parent.OrbitalLobby)
local TutorialController = require(script.Parent.TutorialController)

-- ---------------------------------------------------------------------------
-- Reflow
-- ---------------------------------------------------------------------------

-- A window resize — including the grow Studio's play window does a second after
-- boot — re-primes `Layout` and moves the roots. Nothing is rebuilt: every list,
-- scroll and card below the roots is elastic in X, so a resize is a handful of
-- property writes, not a second boot.
--
-- The very first measurement fires from inside `UiKit.screen`, before a single
-- panel exists, which is what the `built` guard is for.
local built = false

local function reflow(width: number)
	Layout.init(width)
	if not built then
		return
	end
	HudController.layout()
	Sections.layout()
	ForgeView.layout()
	CratesView.layout()
end


-- ---------------------------------------------------------------------------
-- Server event handlers
-- ---------------------------------------------------------------------------

local function onFeedEvent(event: Types.FeedEvent)
	if event.kind == "offline" then
		Modals.offline(event.seconds or 0, event.amount or 0)
		Vfx.flash(Theme.Color.starMatter, 0.22)
		return
	elseif event.kind == "starter" then
		-- The one un-skippable card in the game. It opens after the first payload
		-- lands so the boost it describes is already the boost the income formula
		-- is using, and the HUD chip underneath it agrees.
		Modals.starter(math.max(60, math.floor(event.seconds or Config.StarterBoostSeconds)))
		return
	elseif event.kind == "daily" then
		-- The daily track pays more than Aether now: scrap, Star-Matter, Cores.
		-- The card already showed the whole week, so the toast is the receipt
		-- only, and the payout itself is repainted by the next sync.
		Notifications.push(event.text or "Daily collected", "currency")
		Sfx.coin()
		return
	elseif event.kind == "crit" then
		-- The local prediction already floated a normal number; this adds the
		-- crit flourish on top of it, anchored on the anvil.
		Vfx.flash(Theme.Color.starMatter, 0.14)
		Sfx.crit()
		local anchor = ForgeView.strikeAnchor()
		if anchor then
			Vfx.float(anchor, string.format("CRIT  +%s", NumberUtil.abbreviate(event.amount or 0)), {
				color = Theme.Color.starMatter,
				size = Theme.Text.Hero,
				crit = true,
				drift = 96,
			})
			-- Flipbook if the sheets are uploaded, procedural sparks otherwise.
			-- Never both: the sheet already contains the burst, and stacking them
			-- doubles brightness on the frame that is already the busiest.
			--
			-- The ring is not optional. A crit used to be a flash, a float and a
			-- spark spray, which at speed reads as "a slightly bigger hit"; the
			-- gold shockwave ring is the shape the player learns to look for.
			if not SpriteFx.play(anchor, "impact", Theme.Color.starMatter, { size = 420 }) then
				Vfx.strikeBurst(anchor, Theme.Color.gold, 2.3, true)
			end
			-- The crit lands on the anvil face, not on the button plate: the plate is
			-- full-width and any positional animation on it leaves the card.
			ForgeView.punch(2.2)
		end
		return

	elseif event.kind == "forged" then
		-- Forging is the biggest beat in the loop: the blade itself has to change,
		-- not just a toast. `celebrate` owns the viewport for ~2.6s and owns the
		-- variant wash, so this handler only names the result and scores it.
		if event.text then
			Notifications.push(event.text, "currency")
		end
		-- A ten-pull names the best copy and says how many it came with. Nine
		-- silent copies in the vault with one toast is confusing; `x10` on the
		-- toast and on the reveal chip is the receipt.
		local batch = math.max(1, math.floor(event.batch or 1))
		if batch > 1 then
			Notifications.push(string.format("x%d copies forged", batch), "info")
		end
		local variant = if event.variant then ForgeConfig.variant(event.variant) else ForgeConfig.Variants.standard
		local rank = 1
		for index, id in ForgeConfig.VariantOrder do
			if id == variant.id then
				rank = index
				break
			end
		end
		ForgeView.celebrate(event.blade, event.variant, batch)
		-- The ceremony holds its answer until the last click, so the result
		-- fanfare has to wait too. Playing it here would resolve the do-re-mi
		-- ladder while the crate is still shaking.
		if not CrateReveal.isOpen() then
			Sfx.result(rank)
		end
		return

	elseif event.kind == "vent" then
		Notifications.push(event.text or "Heat vented", "good")
		return
	elseif event.kind == "ascend" then
		Notifications.push(event.text or "Ascended", "good")
		Vfx.flash(Theme.Color.quantum, 0.5)
		-- The ascent is the biggest reset in the game and the confirmation event
		-- is the only place that knows it landed. `Sfx.ascend` is the longest
		-- stinger in the kit, so it plays here and nowhere else.
		Sfx.ascend()
		return
	elseif event.kind == "purchase" then
		-- Drones and tech nodes are the only senders, and both voice the press
		-- themselves. A sound here would land 60ms after that one and read as a
		-- stutter, so this branch is text only.
		Notifications.push(event.text or "Purchased", "info")
		return
	elseif event.kind == "tradeInvite" then
		-- A request is not a session. The popup is the whole consent gate; the
		-- server opens the desk only after ACCEPT comes back.
		local from = tonumber(event.id) or 0
		Modals.tradeRequest(
			tostring(event.name or "A FORGER"),
			math.max(5, tonumber(event.seconds) or 20),
			function()
				StateStore.send("tradeRespond", { from = from, accept = true })
			end,
			function()
				StateStore.send("tradeRespond", { from = from, accept = false })
			end
		)
		return
	elseif event.kind == "tradeStarted" then
		TradeView.open()
		return
	elseif event.kind == "trade" then
		-- Commit already happened server-side. The panel polls and lands on its
		-- idle page on its own; this line is the receipt.
		Notifications.push(event.text or "Trade complete", "currency")
		Sfx.coin()
		return
	end

	if event.text then
		Notifications.push(event.text, "info")
	end
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

local function boot()
	local bootClock = os.clock()

	-- UI first, networking last. Nothing above `StateStore.init()` below may
	-- touch a remote: the screen has to paint even if the server is still
	-- loading its services, and a WaitForChild on an unbuilt folder used to cost
	-- the player several seconds of empty viewport before the first frame.
	--
	-- The screen measures itself and hands back the design width it picked; the
	-- layout has to be primed with that number before a single panel is built,
	-- because every panel reads `Layout` rather than the canvas.
	local gui, canvas, uiScale, designWidth = UiKit.screen("QuantumForge", Layout.MIN_WIDTH, reflow)
	Layout.init(designWidth)

	Vfx.init(canvas, uiScale)
	-- Same canvas, one ZIndex below: the flipbook is the effect, `Vfx` is the
	-- numbers and screen shake that must stay legible on top of it.
	SpriteFx.init(canvas, uiScale)
	Notifications.init(canvas)
	Modals.init(canvas)

	ForgeView.init(canvas, Layout.CONTENT_X, Layout.CONTENT_Y, Layout.CONTENT_W, Layout.CONTENT_H)
	CratesView.init(canvas, Layout.CONTENT_X, Layout.CONTENT_Y, Layout.CONTENT_W, Layout.CONTENT_H)
	-- The nav owns the section panels; the two full-bleed cards are passed in so
	-- the host can hide them without reaching into another module's state.
	Sections.init(canvas, ForgeView.card(), { crates = CratesView.card() })
	-- After the rail exists, because the rate readout lives at its foot.
	HudController.init(canvas, Sections.railFoot())
	-- The vault is a canvas-level overlay, so it is built after the panels and
	-- before anything can open it. Built lazily on first open would cost a frame
	-- of empty screen at the worst moment.
	InventoryModal.init(canvas)
	CodexView.init(canvas)
	LeaderboardView.init(canvas)
	TradeView.init(canvas)
	HandbookView.init(canvas)
	DailyView.init(canvas)
	OrbitalLobby.init()
	Music.init()

	-- Boots hidden and reveals itself on the first payload: at this point the
	-- profile has not arrived, so whether this player has already finished
	-- onboarding is still unknown. The controller reads `tutorialCompleted` from
	-- that first payload and shows the welcome card once.
	TutorialController.init(canvas, uiScale)
	FeedbackView.init(canvas)

	-- The utility bank lives in the top bar now: seven labelled keys and two
	-- verbs on one row. `Main` still owns every overlay module, so the wiring
	-- stays here rather than inside the chrome.
	HudController.vaultHandler = function()
		InventoryModal.open()
	end

	HudController.codexHandler = function()
		CodexView.open()
	end

	HudController.boardsHandler = function()
		LeaderboardView.open()
	end

	HudController.tradeHandler = function()
		TradeView.open()
	end

	HudController.feedbackHandler = function()
		FeedbackView.open()
	end

	HudController.settingsHandler = function()
		Sections.openSettings()
	end

	HudController.dailyHandler = function()
		DailyView.open()
	end

	-- The rail-foot NEXT line is a key, not a caption. It opens the section it
	-- names; the daily is an overlay, so it takes the same path as the DAILY key.
	HudController.nextGoalHandler = function(key: string)
		if key == "daily" then
			DailyView.open()
		elseif key == "crate" then
			Sections.select("crates")
		elseif key == "drone" then
			Sections.select("fleet")
		elseif key == "tech" then
			Sections.select("tech")
		end
	end


	-- Picking a pool on the roll page moves the anvil with it. Both surfaces price
	-- the same crate, and a player who picked Void here should not find the forge
	-- card still selling Standard.
	CratesView.onSelect = function(id: string)
		ForgeView.setCrate(id)
	end

	InventoryModal.tradeHandler = function()
		TradeView.open()
	end

	HudController.guideHandler = function()
		HandbookView.open()
	end

	-- Ascension is destructive: confirm before firing.
	HudController.ascendHandler = function()
		local state = StateStore.current
		if state == nil then
			return
		end
		if state.sm < Config.AscendThreshold then
			Notifications.push("Not enough Star-Matter to ascend", "warn")
			return
		end

		local cores = math.floor((state.sm / Config.AscendThreshold) ^ Config.AscendExponent)
		Modals.confirm(
			"ASCEND?",
			string.format(
				"You will gain %s Quantum Cores and lose all Star-Matter, Aether, drones and forged blades.\n\nTech tree nodes are permanent.",
				NumberUtil.abbreviate(cores)
			),
			"ASCEND",
			Theme.Color.quantum,
			function()
				StateStore.send("ascend")
			end
		)
	end

	local unsubscribeFeed = StateStore.onEvent(onFeedEvent)

	-- Preferences are applied on the first payload only. Applying them on every
	-- sync would fight the local mute key: the tap mutes immediately, but the
	-- next 10Hz packet still carries the old server value until the action is
	-- processed, so the sound would flicker back on for a frame or two.
	local settingsApplied = false
	local unsubscribeSettings = StateStore.onSync(function(payload: Types.SyncPayload)
		if settingsApplied then
			return
		end
		settingsApplied = true
		Sfx.setVolume(payload.settings.sfxVolume)
		Music.setVolume(payload.settings.musicVolume)
		Vfx.setEnabled(payload.settings.vfx)
		Vfx.setShakeEnabled(payload.settings.shake)
	end)

	-- The roll page prices its keys and its pity footer from the payload, so it
	-- follows the sync even while it is on screen. It ignores the packet mid-roll:
	-- the crate owns the clock then, and the note under the keys is the page's.
	local unsubscribeCrates = StateStore.onSync(function(payload: Types.SyncPayload)
		CratesView.render(payload)
	end)

	-- Spacebar is the same input as the anvil. Keyboard players should not have
	-- to move the mouse to the button for every strike. Gated on the forge being
	-- the visible section: a hidden card that still answers Space would spend
	-- heat and play sounds from a screen the player cannot see.
	local inputConnection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space and Sections.activeTab() == "forge" then
			ForgeView.strike()
		end
	end)

	local badgeAccumulator = 0

	local renderConnection = RunService.RenderStepped:Connect(function(dt)
		HudController.step(dt)
		ForgeView.step(dt)

		badgeAccumulator += dt
		if badgeAccumulator >= 0.5 then
			badgeAccumulator = 0
			Sections.refreshTabBadges()
		end
	end)

	-- Last step on purpose: from here the HUD is live and the store simply starts
	-- reporting. If the remotes are not replicated yet this returns immediately
	-- and connects on a background thread once they are.
	built = true
	StateStore.init()

	-- A destroyed ScreenGui means the player left or the UI was torn down; drop
	-- everything so Play Again starts clean.
	gui.Destroying:Once(function()
		built = false
		renderConnection:Disconnect()
		inputConnection:Disconnect()
		unsubscribeFeed()
		unsubscribeSettings()
		unsubscribeCrates()
		HudController.destroy()
		ForgeView.destroy()
		SpriteFx.destroy()
		Sections.destroy()
		InventoryModal.destroy()
		CodexView.destroy()
		LeaderboardView.destroy()
		TradeView.destroy()
		HandbookView.destroy()
		OrbitalLobby.destroy()
		TutorialController.destroy()
	end)

	if Config.Debug then
		print(string.format(
			"[QuantumForge] ui built in %.0fms (content %dx%d, linked=%s)",
			(os.clock() - bootClock) * 1000,
			Layout.CONTENT_W,
			Layout.CONTENT_H,
			tostring(StateStore.linked)
		))
	end

	if RunService:IsStudio() then
		-- Dev seam. Studio's `VirtualInputManager` needs the RobloxScript
		-- capability, so automated verification cannot click a button. A
		-- BindableFunction runs its callback in *this* script's VM, which means
		-- an inspector can drive the same entry points the buttons call without
		-- faking input. Studio only, and it dies with the GUI.
		local dev = Instance.new("BindableFunction")
		dev.Name = "QF_Dev"
		dev.OnInvoke = function(command: string, argument: any): any
			if command == "openVault" then
				InventoryModal.open()
				return true
			elseif command == "closeVault" then
				InventoryModal.close()
				return true
			elseif command == "roll" then
				ForgeView.roll()
				return true
			elseif command == "strike" then
				-- Same entry point the strike key and the stage both call, so a
				-- heat run can be driven without pointer synthesis.
				ForgeView.strike()
				return true
			elseif command == "stats" then
				local state = StateStore.current
				if state == nil then
					return nil
				end
				return {
					heat = state.heat,
					yield = state.clickYield,
					sm = state.sm,
					bandMult = state.bandMult,
					inSweetSpot = state.inSweetSpot,
					overdrive = state.overdriveRemaining,
					boost = state.boostRemaining,
					paidBoost = state.paidBoostRemaining,
					ownedPasses = state.ownedPasses,
					forgeCosts = state.forgeCosts,
					settings = state.settings,
				}
			elseif command == "vent" then
				StateStore.send("vent")
				return true
			elseif command == "forgeState" then
				local state = StateStore.current
				return {
					rolling = ForgeView.isRolling(),
					unlocked = ForgeView.isUnlocked(),
					note = ForgeView.rollNote(),
					sm = if state then state.sm else -1,
					forgeCost = if state then state.forgeCost else -1,
					heat = if state then state.heat else -1,
				}
			elseif command == "forgeOrbit" then
				local orbit = ForgeView.orbitHandle()
				if orbit == nil then
					return nil
				end
				orbit.cameraYaw += if type(argument) == "number" then argument else 0.35
				return { yaw = orbit.cameraYaw, pitch = orbit.cameraPitch }
			elseif command == "vaultOrbit" then
				local orbit = InventoryModal.orbitHandle()
				if orbit == nil then
					return nil
				end
				orbit.cameraYaw += if type(argument) == "number" then argument else 0.35
				return { yaw = orbit.cameraYaw, pitch = orbit.cameraPitch }
			elseif command == "vaultOpen" then
				return InventoryModal.isOpen()
			elseif command == "detailFirst" then
				InventoryModal.openFirstDetail()
				return true
			elseif command == "selectDupes" then
				InventoryModal.selectDupes()
				return true
			elseif command == "meltMode" and type(argument) == "boolean" then
				InventoryModal.setMeltMode(argument)
				return InventoryModal.isMeltMode()
			elseif command == "batchState" then
				return InventoryModal.batchState()
			elseif command == "meltSelected" then
				return InventoryModal.meltSelected()
			elseif command == "commitMelt" then
				local picks = InventoryModal.selectionSummary()
				InventoryModal.commitMelt(picks)
				return #picks
			elseif command == "selection" then
				local picks, worth = InventoryModal.selectionSummary()
				return { uids = picks, worth = worth }
			elseif command == "settings" then
				Sections.openSettings()
				return true
			elseif command == "tradeInvitePreview" then
				-- Studio seam: the invite card needs a second player to fire for
				-- real, so this paints one with a stand-in name. The buttons send
				-- the real verb; there is simply no invite to answer here.
				Modals.tradeRequest(
					if type(argument) == "string" then argument else "KILLYWILLY",
					20,
					function() end,
					function() end
				)
				return true
			elseif command == "skipGuide" then
				TutorialController.skip()
				return true
			elseif command == "detailAt" then
				return InventoryModal.openDetailAt(argument)
			elseif command == "toggleAt" then
				return InventoryModal.toggleAt(argument)
			elseif command == "meltDetail" then
				return InventoryModal.meltDetail()
			elseif command == "rerollDetail" then
				return InventoryModal.rerollDetail()
			elseif command == "commitReroll" then
				-- Reroll the copy on the turntable, skipping the confirm dialog.
				-- The dialog itself cannot be pressed from here: the build has no
				-- way to synthesise a pointer event, which is why the melt seam
				-- commits directly too.
				InventoryModal.commitDetailReroll(nil)
				return true
			elseif command == "commitDetail" then
				local target = InventoryModal.detailMeltTarget()
				if target == nil then
					return false
				end
				InventoryModal.commitDetailMelt(target)
				return true
			elseif command == "favoriteAt" then
				return InventoryModal.favoriteAt(argument)
			elseif command == "vaultFilter" and type(argument) == "string" then
				InventoryModal.setFilter(argument)
				return true
			elseif command == "vaultSort" and type(argument) == "string" then
				InventoryModal.setSort(argument)
				return true
			elseif command == "vaultState" then
				local state = StateStore.current
				local favorites = {}
				local favoriteCount = 0
				if state then
					for uid, flag in state.favorites or {} do
						if flag then
							favorites[uid] = true
							favoriteCount += 1
						end
					end
				end
				return {
					filter = InventoryModal.currentFilter(),
					sort = InventoryModal.currentSort(),
					inspected = InventoryModal.inspectedKey(),
					favorites = favoriteCount,
					invCount = state and state.invCount or 0,
					invMax = state and state.invMax or 0,
					rolls = state and state.forgeRolls or 0,
				}
			elseif command == "openCodex" then
				CodexView.open()
				return true
			elseif command == "closeCodex" then
				CodexView.close()
				return true
			elseif command == "codexOpen" then
				return CodexView.isOpen()
			elseif command == "codexTab" and type(argument) == "string" then
				return CodexView.setTab(argument)
			elseif command == "openBoards" then
				LeaderboardView.open()
				return true
			elseif command == "closeBoards" then
				LeaderboardView.close()
				return true
			elseif command == "boardsOpen" then
				return LeaderboardView.isOpen()
			elseif command == "boardsTab" and type(argument) == "string" then
				return LeaderboardView.setBoard(argument)
			elseif command == "boardsPreview" then
				return LeaderboardView.isPreview()
			elseif command == "openTrade" then
				TradeView.open()
				return true
			elseif command == "closeTrade" then
				TradeView.close()
				return true
			elseif command == "tradeOpen" then
				return TradeView.isOpen()
			elseif command == "tradePreview" then
				return TradeView.preview()
			elseif command == "openHandbook" then
				HandbookView.open()
				return true
			elseif command == "closeHandbook" then
				HandbookView.close()
				return true
			elseif command == "handbookOpen" then
				return HandbookView.isOpen()
			elseif command == "handbookPage" and type(argument) == "string" then
				return HandbookView.setPage(argument)
			elseif command == "handbookId" then
				return HandbookView.page()
			elseif command == "tradeState" then
				return StateStore.request("trade")
			elseif command == "codexState" then
				local keys = 0
				for _ in StateStore.codex do
					keys += 1
				end
				return { keys = keys, version = StateStore.codexVersion }
			elseif command == "openCrates" then
				Sections.select("crates")
				return true
			elseif command == "closeCrates" then
				Sections.select("forge")
				return true
			elseif command == "cratesOpen" then
				return Sections.activeTab() == "crates"
			elseif command == "crateSelect" and type(argument) == "string" then
				return CratesView.select(argument)
			elseif command == "crateRoll" then
				-- Rolls on the page itself, exactly what the key does. The page owns
				-- the drop, the rattle and the reveal; there is no hand-off to the
				-- anvil any more.
				Sections.select("crates")
				return CratesView.roll(if type(argument) == "number" then argument else 1)
			elseif command == "cratePreview" and type(argument) == "string" then
				-- Visual QA for the top-rarity reveal without a 0.35% roll.
				Sections.select("crates")
				return CratesView.preview(argument, "prismatic")
			elseif command == "crateReveal" and type(argument) == "string" then
				-- Same copy, through the canvas overlay the player sees.
				Sections.select("crates")
				return CratesView.revealPreview(argument, "prismatic")
			elseif command == "crateStage" then
				-- The ceremony itself, with N crates and no charge. Walks the drop,
				-- the click ladder and the reveal exactly as a real pull does.
				Sections.select("crates")
				return CratesView.stagePreview(if type(argument) == "number" then argument else 1)
			elseif command == "crateDismiss" then
				Sections.select("crates")
				CratesView.dismiss()
				return true
			elseif command == "openDaily" then
				DailyView.open()
				return true
			elseif command == "closeDaily" then
				DailyView.close()
				return true
			elseif command == "dailyOpen" then
				return DailyView.isOpen()
			elseif command == "starterPreview" then
				Modals.starter(Config.StarterBoostSeconds)
				return true
			elseif command == "wired" then
				-- The overlay keys are wired by `Main`, not by the module that
				-- draws them. This is the only way to prove from outside that a
				-- handler actually landed on the module the UI holds.
				return {
					codex = HudController.codexHandler ~= nil,
					boards = HudController.boardsHandler ~= nil,
					feedback = HudController.feedbackHandler ~= nil,
					guide = HudController.guideHandler ~= nil,
					trade = HudController.tradeHandler ~= nil,
					vault = HudController.vaultHandler ~= nil,
					settings = HudController.settingsHandler ~= nil,
					daily = HudController.dailyHandler ~= nil,
					crates = Sections.activeTab() ~= nil,
					crateSel = ForgeView.crateId(),
				}
			elseif command == "state" then
				local state = StateStore.current
				if state == nil then
					return nil
				end
				return {
					sm = state.sm,
					forgeCost = state.forgeCost,
					rolls = state.forgeRolls,
					invCount = state.invCount,
					invMax = state.invMax,
					scrap = state.scrap,
					pity = state.forgePity,
					locked = state.locked,
					equipped = state.equipped,
					equippedUid = state.equippedUid,
				}
			elseif command == "fleetTier" and type(argument) == "string" then
				return DroneView.select(argument)
			elseif command == "sideTab" and type(argument) == "string" then
				-- The four right-panel tabs are buttons, and this build cannot
				-- synthesise a pointer press. Routing through the same
				-- `Sections.select` the tab handler calls is the only way to
				-- photograph FLEET, RUNES and TECH on a given profile.
				Sections.select(argument)
				return Sections.activeTab()
			elseif command == "fleetState" then
				local state = StateStore.current
				local fleet = {}
				if state then
					for _, entry in state.fleet do
						fleet[entry.id] = {
							owned = entry.owned,
							cost = entry.cost,
							bulk = entry.bulk,
							unlocked = entry.unlocked,
							unlockAt = entry.unlockAt,
						}
					end
				end
				return {
					selected = DroneView.selected(),
					drones = state and state.drones or 0,
					aether = state and state.as or 0,
					fleet = fleet,
				}
			elseif command == "setting" and type(argument) == "table" then
				StateStore.send("setting", { key = argument.key, value = argument.value })
				return true
			end
			return false
		end
		dev.Parent = gui
	end
end

boot()
