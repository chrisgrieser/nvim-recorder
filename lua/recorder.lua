local M = {}

local fn = vim.fn
local v = vim.v
local opt = vim.opt
local getMacro = vim.fn.getreg
local setMacro = vim.fn.setreg
local keymap = vim.keymap.set
local level = vim.log.levels

-- internal vars
local macroRegs, slotIndex, logLevel, breakCounter

-- vars which can be set by the user
local toggleKey, breakPointKey, dapSharedKeymaps, lessNotifications, useNerdfontIcons
local perf = {}

--------------------------------------------------------------------------------

-- post vim.notify with configured log level.
-- Posts no notifications if lessNotifications is true
local function nonEssentialNotify(msg)
	if lessNotifications then return end
	vim.notify(msg, logLevel)
end

---@return boolean
local function isRecording() return fn.reg_recording() ~= "" end
local function isPlaying() return fn.reg_executing() ~= "" end

---runs `:normal` natively with bang
---@param cmdStr any
local function normal(cmdStr) vim.cmd.normal { cmdStr, bang = true } end

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

	-- EXECUTE MACRO
	local countGiven = v.count ~= 0
	local hasBreakPoints = macro:find(vim.pesc(breakPointKey))
	local usePerfOptimizations = v.count >= perf.countThreshold

	-- macro (w/ breakpoints)
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

	-- macro (w/ perf optimizations)
	elseif usePerfOptimizations then
		-- message to avoid confusion by the user due to performance optimizations
		local msg = "Running macro with performance optimizations…"
		if perf.lazyredraw then
			msg = msg
				.. "\nnvim might appear to freeze due to lazy redrawing. \nThis is to be expected and not a bug."
		end
		nonEssentialNotify(msg)

		local original = {}
		if perf.lazyredraw then
			---@diagnostic disable-next-line: param-type-mismatch neodev buggy here?
			original.lazyredraw = opt.lazyredraw:get()
			opt.lazyredraw = true
		end
		if perf.noSystemclipboard then
			original.clipboard = opt.clipboard:get()
			opt.clipboard = ""
		end
		original.eventignore = opt.eventignore:get()
		opt.eventignore = perf.autocmdEventsIgnore

		-- if notification is shown, defer to ensure it is displayed
		-- (e.g., nvim-notify animations delay the display a bit)
		local delay = lessNotifications and 0 or 1500
		local count = v.count1 -- counts needs to be saved due to scoping by defer_fn
		vim.defer_fn(function()
			normal(count .. "@" .. reg)

			---@diagnostic disable-next-line: assign-type-mismatch neodev buggy here?
			if perf.lazyredraw then vim.opt.lazyredraw = original.lazyredraw end
			if perf.noSystemclipboard then opt.clipboard = original.clipboard end
			opt.eventignore = original.eventignore
		end, delay)

	-- macro (regular)
	else
		normal(v.count1 .. "@" .. reg)
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
---@field useNerdfontIcons boolean currently only relevant for status bar components

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

---@param userConfig configObj
function M.setup(userConfig)
	-- initialize values on plugin load
	slotIndex = 1
	breakCounter = 0

	local defaultConfig = {
		slots = { "a", "b" },
		mapping = {
			startStopRecording = "q",
			playMacro = "Q",
			switchSlot = "<C-q>",
			editMacro = "cq",
			yankMacro = "yq",
			addBreakPoint = "##",
		},
		dapSharedKeymaps = false,
		clear = false,
		logLevel = vim.log.levels.INFO,
		lessNotifications = false,
		useNerdfontIcons = true,
		performanceOpts = {
			countThreshold = 100,
			lazyredraw = true,
			noSystemClipboard = true,
			-- stylua: ignore
			autocmdEventsIgnore = { "TextChangedI", "TextChanged", "InsertLeave", "InsertEnter", "InsertCharPre" },
		},
	}
	local config = vim.tbl_deep_extend("keep", userConfig, defaultConfig)

	-- validate macro slots
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

	-- clear macro slots
	if config.clear then
		for _, reg in pairs(macroRegs) do
			setMacro(reg, "")
		end
	end

	-- setup keymaps
	toggleKey = config.mapping.startStopRecording
	breakPointKey = config.mapping.addBreakPoint
	local icon = config.useNerdfontIcons and " " or ""
	local dapSharedIcon = config.useNerdfontIcons and " /  " or ""

	keymap("n", toggleKey, toggleRecording, { desc = icon .. "Start/Stop Recording" })
	keymap("n", config.mapping.switchSlot, switchMacroSlot, { desc = icon .. "Switch Macro Slot" })
	keymap("n", config.mapping.editMacro, editMacro, { desc = icon .. "Edit Macro" })
	keymap("n", config.mapping.yankMacro, yankMacro, { desc = icon .. "Yank Macro" })

	-- (experimental) if true, nvim-recorder and dap will use shared keymaps:
	-- 1) `addBreakPoint` will map to `dap.toggle_breakpoint()` outside
	-- a recording. During a recording, it will add a macro breakpoint instead.
	-- 2) `playMacro` will map to `dap.continue()` if there is at least one
	-- dap-breakpoint. If there is no dap breakpoint, will play the current
	-- macro-slot instead
	dapSharedKeymaps = config.dapSharedKeymaps or false
	local desc1 = dapSharedKeymaps and dapSharedIcon .. "Breakpoint"
		or icon .. "Insert Macro Breakpoint."
	keymap("n", breakPointKey, addBreakPoint, { desc = desc1 })
	local desc2 = dapSharedKeymaps and dapSharedIcon .. "Continue/Play" or icon .. "Play Macro"
	keymap("n", config.mapping.playMacro, playRecording, { desc = desc2 })
end

--------------------------------------------------------------------------------
-- STATUS LINE COMPONENTS

---returns recording status for status line plugins (e.g., used with cmdheight=0)
---@return string
function M.recordingStatus()
	if not isRecording() then return "" end
	local icon = useNerdfontIcons and "  " or ""
	return icon .. "Recording… [" .. macroRegs[slotIndex] .. "]"
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
	local icon = useNerdfontIcons and "󰃽 " or "RECs "
	return icon .. output
end

--------------------------------------------------------------------------------

return M
