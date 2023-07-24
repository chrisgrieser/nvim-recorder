local fn = vim.fn
local v = vim.v
local opt = vim.opt
local getMacro = vim.fn.getreg
local setMacro = vim.fn.setreg
local keymap = vim.keymap.set
local level = vim.log.levels

---@return boolean
local function isRecording() return fn.reg_recording() ~= "" end
local function isPlaying() return fn.reg_executing() ~= "" end

---runs `:normal` natively with bang
---@param cmdStr any
local function normal(cmdStr) vim.cmd.normal { cmdStr, bang = true } end

local macroRegs, slotIndex, logLevel, lessNotifications
local toggleKey, breakPointKey, dapSharedKeymaps
local perf = {}
local M = {}

local breakCounter = 0 -- resets break counter on plugin reload

-- post vim.notify with configured log level.
-- Posts no notifications if lessNotifications is true
local function nonEssentialNotify(msg)
	if lessNotifications then return end
	vim.notify(msg, logLevel)
end

--------------------------------------------------------------------------------
-- COMMANDS

-- start/stop recording macro into the current slot
local function toggleRecording()
	local reg = macroRegs[slotIndex]

	-- start recording
	if not isRecording() then
		breakCounter = 0 -- reset break points
		normal("q" .. reg)
		nonEssentialNotify("Recording to [" .. reg .. "]…")
		return
	end

	-- stop recording
	local prevRec = getMacro(macroRegs[slotIndex])
	normal("q")

	-- NOTE the macro key records itself, so it has to be removed from the
	-- register. As this function has to know the variable length of the
	-- LHS key that triggered it, it has to be passed in via .setup()-function
	local decodedToggleKey = vim.api.nvim_replace_termcodes(toggleKey, true, true, true)
	local recording = getMacro(reg):sub(1, -1 * (#decodedToggleKey + 1))
	setMacro(reg, recording)

	local justRecorded = fn.keytrans(getMacro(reg))
	if justRecorded == "" then
		setMacro(reg, prevRec)
		vim.notify("Recording aborted.\n(Previous recording is kept.)", level.INFO)
	elseif not lessNotifications then
		nonEssentialNotify("Recorded [" .. reg .. "]:\n" .. justRecorded)
	end
end

---play the macro recorded in current slot
local function playRecording()
	local reg = macroRegs[slotIndex]
	local macro = getMacro(reg)
	local countGiven = v.count ~= 0

	-- Guard Clause 1: Toggle Breakpoint instead of Macro
	-- WARN undocumented and prone to change https://github.com/mfussenegger/nvim-dap/discussions/810#discussioncomment-4623606
	if dapSharedKeymaps then
		-- nested to avoid requiring `dap` for lazyloading
		local dapBreakpointsExist = next(require("dap.breakpoints").get()) ~= nil
		if dapBreakpointsExist then
			require("dap").continue()
			return
		end
	end

	-- Guard Clause 2: Recursively play macro
	if isRecording() then
		-- stylua: ignore
		vim.notify(
			"Playing the macro while it is recording would cause recursion problems." ..
			"Aborting. (You can still use recursive macros by using `@" .. reg .. "`)",
			level.ERROR
		)
		normal("q") -- end recording
		setMacro(reg, "") -- empties macro since the recursion has been recorded there
		return
	end

	-- Guard Clause 3: Slot is empty
	if macro == "" then
		vim.notify("Macro Slot [" .. reg .. "] is empty.", level.WARN)
		return
	end

	local hasBreakPoints = macro:find(vim.pesc(breakPointKey))
	local useLazyRedraw = v.count >= perf.countThreshold
		and perf.lazyredraw
		and not (opt.lazyredraw:get() == true)
	local noSystemClipboard = v.count >= perf.countThreshold
		and perf.noSystemclipboard
		and (opt.clipboard:get() ~= "")

	-- Execute Macro (with breakpoints)
	if hasBreakPoints and not countGiven then
		breakCounter = breakCounter + 1
		local macroParts = vim.split(macro, breakPointKey, {})
		local partialMacro = macroParts[breakCounter]

		setMacro(reg, partialMacro)
		normal("@" .. reg)
		setMacro(reg, macro) -- restore original macro for all other purposes like prewing slots

		if breakCounter ~= #macroParts then
			vim.notify("Reached Breakpoint #" .. tostring(breakCounter), level.INFO)
		else
			vim.notify("Reached end of macro", level.INFO)
			breakCounter = 0
		end

	-- Execute Macro (without breakpoints, but with performance optimization)
	else
		if useLazyRedraw then opt.lazyredraw = true end
		local prevClipboardOpt
		if noSystemClipboard then
			opt.clipboard = ""
			prevClipboardOpt = opt.clipboard:get()
		end
		local prevAutocmdIgnore = opt.eventignore:get()
		opt.eventignore = perf.autocmdEventsIgnore

		normal(v.count1 .. "@" .. reg)

		if useLazyRedraw then opt.lazyredraw = false end
		if noSystemClipboard then opt.clipboard = prevClipboardOpt end
		opt.eventignore = prevAutocmdIgnore
	end
end

---changes the active slot
local function switchMacroSlot()
	slotIndex = slotIndex + 1
	breakCounter = 0 -- reset breakpoint counter

	if slotIndex > #macroRegs then slotIndex = 1 end
	local reg = macroRegs[slotIndex]
	local currentMacro = fn.keytrans(getMacro(reg))
	local msg = " Now using macro slot [" .. reg .. "]"
	if currentMacro ~= "" then
		msg = msg .. ".\n" .. currentMacro
	else
		msg = msg .. "\n(empty)"
	end
	nonEssentialNotify(msg)
end

---edit the current slot
local function editMacro()
	breakCounter = 0 -- reset breakpoint counter
	local reg = macroRegs[slotIndex]
	local macroContent = getMacro(reg)
	local inputConfig = {
		prompt = "Edit Macro [" .. reg .. "]:",
		default = macroContent,
	}
	vim.ui.input(inputConfig, function(editedMacro)
		if not editedMacro then return end -- cancellation
		setMacro(reg, editedMacro)
		nonEssentialNotify("Edited Macro [" .. reg .. "]:\n" .. editedMacro)
	end)
end

local function yankMacro()
	breakCounter = 0
	local reg = macroRegs[slotIndex]
	local macroContent = fn.keytrans(getMacro(reg))
	if macroContent == "" then
		vim.notify("Nothing to copy, macro slot [" .. reg .. "] is still empty.", level.WARN)
		return
	end
	-- remove breakpoints when yanking the macro
	macroContent = macroContent:gsub(vim.pesc(breakPointKey), "")

	local clipboardOpt = opt.clipboard:get()
	local useSystemClipb = #clipboardOpt > 0 and clipboardOpt[1]:find("unnamed")
	local copyToReg = useSystemClipb and "+" or '"'

	fn.setreg(copyToReg, macroContent)
	nonEssentialNotify("Copied Macro [" .. reg .. "]:\n" .. macroContent)
end

local function addBreakPoint()
	if isRecording() then
		-- INFO nothing happens, but the key is still recorded in the macro
		vim.notify("Macro breakpoint added.", level.INFO)
	elseif not isPlaying() and not dapSharedKeymaps then
		vim.notify("Cannot insert breakpoint outside of a recording.", level.WARN)
	elseif not isPlaying() and dapSharedKeymaps then
		-- only test for dap here to not interfere with user lazyloading
		if require("dap") then require("dap").toggle_breakpoint() end
	end
end

--------------------------------------------------------------------------------
-- CONFIG

---@class configObj
---@field slots string[] named register slots
---@field clear boolean whether to clear slots/registers on setup
---@field timeout number Default timeout for notification
---@field mapping maps individual mappings
---@field logLevel integer log level (vim.log.levels)
---@field lessNotifications boolean plugin is less verbose, shows only essential or critical notifications
---@field performanceOpts perfOpts various performance options
---@field dapSharedKeymaps boolean (experimental) partially share keymaps with dap

---@class perfOpts
---@field countThreshold number if count used is higher than threshold, the following performance optimizations are applied
---@field lazyredraw boolean :h lazyredraw
---@field noSystemClipboard boolean no `*` or `+` in clipboard https://vi.stackexchange.com/a/31888
---@field autocmdEventsIgnore string[] list of autocmd events to ignore

---@class maps
---@field startStopRecording string
---@field playMacro string
---@field editMacro string
---@field yankMacro string
---@field switchSlot string
---@field addBreakPoint string

---Setup Macro Plugin
---@param config configObj
-- selene: allow(high_cyclomatic_complexity)
function M.setup(config)
	config = config or {}
	slotIndex = 1 -- initial starting slot

	-- General settings
	logLevel = config.logLevel or level.INFO
	lessNotifications = config.lessNotifications or false

	-- performance opts
	local defaultPerfOpts = {
		countThreshold = 100,
		lazyredraw = true,
		noSystemClipboard = true,
		autocmdEventsIgnore = {
			"TextChangedI",
			"TextChanged",
			"InsertLeave",
			"InsertEnter",
			"InsertCharPre",
		},
	}
	if not config.performanceOpts then config.performanceOpts = defaultPerfOpts end
	perf.countThreshold = config.performanceOpts.countThreshold or defaultPerfOpts.countThreshold
	perf.lazyredraw = config.performanceOpts.lazyredraw or defaultPerfOpts.lazyredraw
	perf.noSystemClipboard = config.performanceOpts.noSystemClipboard
		or defaultPerfOpts.noSystemClipboard
	perf.autocmdEventsIgnore = config.performanceOpts.autocmdEventsIgnore
		or defaultPerfOpts.autocmdEventsIgnore

	-- macro slots (+ validate them)
	macroRegs = config.slots or { "a", "b" }
	for _, reg in pairs(macroRegs) do
		if not (reg:find("^%l$")) then
			vim.notify(
				"'" .. reg .. "' is an invalid slot. Choose only named registers (a-z).",
				level.ERROR
			)
			return
		end
	end

	-- clearing
	if config.clear then
		for _, reg in pairs(macroRegs) do
			setMacro(reg, "")
		end
	end

	-- keymaps
	local defaultKeymaps = {
		startStopRecording = "q",
		playMacro = "Q",
		switchSlot = "<C-q>",
		editMacro = "cq",
		yankMacro = "yq",
		addBreakPoint = "##",
	}
	if not config.mapping then config.mapping = defaultKeymaps end
	toggleKey = config.mapping.startStopRecording or defaultKeymaps.startStopRecording
	local playKey = config.mapping.playMacro or defaultKeymaps.playMacro
	local switchKey = config.mapping.switchSlot or defaultKeymaps.switchSlot
	local editKey = config.mapping.editMacro or defaultKeymaps.editMacro
	local yankKey = config.mapping.yankMacro or defaultKeymaps.yankMacro
	breakPointKey = config.mapping.addBreakPoint or defaultKeymaps.addBreakPoint

	keymap("n", toggleKey, toggleRecording, { desc = " Start/Stop Recording" })
	keymap("n", switchKey, switchMacroSlot, { desc = " Switch Macro Slot" })
	keymap("n", editKey, editMacro, { desc = " Edit Macro" })
	keymap("n", yankKey, yankMacro, { desc = " Yank Macro" })

	-- (experimental) if true, nvim-recorder and dap will use shared keymaps:
	-- 1) `addBreakPoint` will map to `dap.toggle_breakpoint()` outside
	-- a recording. During a recording, it will add a macro breakpoint instead.
	-- 2) `playMacro` will map to `dap.continue()` if there is at least one
	-- dap-breakpoint. If there is no dap breakpoint, will play the current
	-- macro-slot instead
	dapSharedKeymaps = config.dapSharedKeymaps or false
	local desc1 = dapSharedKeymaps and "/ Breakpoint" or " Insert Macro Breakpoint."
	keymap("n", breakPointKey, addBreakPoint, { desc = desc1 })
	local desc2 = dapSharedKeymaps and "/ Continue/Play" or " Play Macro"
	keymap("n", playKey, playRecording, { desc = desc2 })
end

--------------------------------------------------------------------------------
-- STATUS LINE COMPONENTS

---returns recording status for status line plugins (e.g., used with cmdheight=0)
---@return string
function M.recordingStatus()
	if not isRecording() then return "" end
	return "  Recording… [" .. macroRegs[slotIndex] .. "]"
end

---returns non-empty for status line plugins.
---@return string
function M.displaySlots()
	if isRecording() then return "" end
	local out = {}

	for _, reg in pairs(macroRegs) do
		local empty = getMacro(reg) == ""
		local active = macroRegs[slotIndex] == reg
		local hasBreakPoints = getMacro(reg):find(vim.pesc(breakPointKey))
		local bpIcon = hasBreakPoints and "!" or ""

		if empty and active then
			table.insert(out, "[ ]")
		elseif not empty and active then
			table.insert(out, "[" .. reg .. bpIcon .. "]")
		elseif not empty and not active then
			table.insert(out, reg .. bpIcon)
		end
	end

	local output = table.concat(out)
	if output == "[ ]" then return "" end
	return " " .. output
end

--------------------------------------------------------------------------------

return M
