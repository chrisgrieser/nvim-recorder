local M = {}

local fn = vim.fn
local v = vim.v
local opt = vim.opt
local keymap = vim.keymap.set

-- internal vars
local config, macroRegs, slotIndex, defaultLogLevel, breakCounter, firstRun

-- Use this function to normalize keycodes (which can have multiple
-- representations, e.g. <C-f> or <C-F>).
---@param mapping string
local normalizeKeycodes = function(mapping)
	return fn.keytrans(vim.api.nvim_replace_termcodes(mapping, true, true, true))
end

local getMacro = function(reg)
	-- Some keys (e.g. <C-F>) have different representations when they are recorded
	-- versus when they are a result of vim.api.nvim_replace_termcodes (for example).
	-- This ensures that whenever we are manually doing something with register contents,
	-- they are always consistent.
	return vim.api.nvim_replace_termcodes(fn.keytrans(vim.fn.getreg(reg)), true, true, true)
end
local setMacro = function(reg, recording) vim.fn.setreg(reg, vim.api.nvim_replace_termcodes(recording, true, true, true), "c") end

-- vars which can be set by the user
local toggleKey, breakPointKey, dapSharedKeymaps, lessNotifications, useNerdfontIcons
local perf = {}

--------------------------------------------------------------------------------

---@param msg string
---@param level? 0|1|2|3|4 vim.log.levels
---@param importance "essential"|"nonessential"
---@param extraOpts? table
local function notify(msg, importance, level, extraOpts)
	if importance == "nonessential" and lessNotifications then return end
	if not level then level = defaultLogLevel end
	local opts = vim.tbl_deep_extend("force", { title = "nvim-recorder" }, extraOpts or {})
	vim.notify(msg, level, opts)
end

---@return boolean
local function isRecording() return fn.reg_recording() ~= "" end

---@return boolean
local function isPlaying() return fn.reg_executing() ~= "" end

---runs `:normal` natively with bang
---@param cmdStr string
local function normal(cmdStr) vim.cmd.normal { cmdStr, bang = true } end

--------------------------------------------------------------------------------
-- COMMANDS

-- start/stop recording macro into the current slot
local function toggleRecording()
	if config.dynamicSlots == "rotate" and not firstRun and not isRecording() then
		slotIndex = slotIndex + 1
		if slotIndex > #macroRegs then slotIndex = 1 end
	end
	if firstRun then firstRun = false end
	local reg = macroRegs[slotIndex]

	-- start recording
	if not isRecording() then
		breakCounter = 0 -- reset break points
		normal("q" .. reg)
		notify("Recording to [" .. reg .. "]…", "essential")
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
		if config.dynamicSlots == "rotate" then slotIndex = slotIndex - 1 end
		setMacro(reg, prevRec)
		notify("Recording aborted.\n(Previous recording is kept.)", "essential")
	elseif not lessNotifications then
		notify("Recorded [" .. reg .. "]:\n" .. justRecorded, "nonessential")
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
		notify(
			"Playing the macro while it is recording would cause recursion problems. Aborting.\n" ..
			"(You can still use recursive macros by using `@" .. reg .. "`)",
			"essential",
			vim.log.levels.ERROR
		)
		normal("q") -- end recording
		setMacro(reg, "") -- empties macro since the recursion has been recorded there
		return
	end

	-- Guard Clause 3: Slot is empty
	if macro == "" then
		notify("Macro Slot [" .. reg .. "] is empty.", "essential", vim.log.levels.WARN)
		return
	end

	-- EXECUTE MACRO
	local countGiven = v.count ~= 0
	local hasBreakPoints = fn.keytrans(macro):find(vim.pesc(breakPointKey))
	local usePerfOptimizations = v.count1 >= perf.countThreshold

	-- macro (w/ breakpoints)
	if hasBreakPoints and not countGiven then
		breakCounter = breakCounter + 1

		local macroParts = {}
		for _, macroPart in ipairs(vim.split(fn.keytrans(macro), vim.pesc(breakPointKey), {})) do
			table.insert(macroParts, vim.api.nvim_replace_termcodes(macroPart, true, true, true))
		end

		local partialMacro = macroParts[breakCounter]

		setMacro(reg, partialMacro)
		normal("@" .. reg)
		setMacro(reg, macro) -- restore original macro for all other purposes like prewing slots

		if breakCounter ~= #macroParts then
			notify("Reached Breakpoint #" .. tostring(breakCounter), "essential")
		else
			notify("Reached end of macro", "essential")
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
		notify(msg, "nonessential", nil, { animate = false }) -- no animation as macro will be blocking

		local original = {}
		if perf.lazyredraw then
			original.lazyredraw = opt.lazyredraw:get() ---@diagnostic disable-line: undefined-field
			opt.lazyredraw = true
		end
		if perf.noSystemclipboard then
			original.clipboard = opt.clipboard:get() ---@diagnostic disable-line: undefined-field
			opt.clipboard = ""
		end
		original.eventignore = opt.eventignore:get()
		opt.eventignore = perf.autocmdEventsIgnore

		-- if notification is shown, defer to ensure it is displayed
		local count = v.count1 -- counts needs to be saved due to scoping by defer_fn
		vim.defer_fn(function()
			normal(count .. "@" .. reg)

			if perf.lazyredraw then vim.opt.lazyredraw = original.lazyredraw end
			if perf.noSystemclipboard then opt.clipboard = original.clipboard end
			opt.eventignore = original.eventignore
		end, 500)

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
	notify(msg, "nonessential")
end

---edit the current slot
local function editMacro()
	breakCounter = 0 -- reset breakpoint counter
	local reg = macroRegs[slotIndex]
	local macroContent = fn.keytrans(getMacro(reg))
	local inputConfig = {
		prompt = "Edit Macro [" .. reg .. "]:",
		default = macroContent,
	}
	vim.ui.input(inputConfig, function(editedMacro)
		if not editedMacro then return end -- cancellation
		setMacro(reg, editedMacro)
		notify("Edited Macro [" .. reg .. "]:\n" .. editedMacro, "nonessential")
	end)
end

---@param mode? "silent"
local function deleteAllMacros(mode)
	breakCounter = 0 -- reset breakpoint counter
	for _, reg in pairs(macroRegs) do
		setMacro(reg, "")
	end
	if mode ~= "silent" then notify("All macros deleted.", "nonessential") end
end

local function yankMacro()
	breakCounter = 0
	local reg = macroRegs[slotIndex]
	local macroContent = fn.keytrans(getMacro(reg))
	if macroContent == "" then
		notify(
			"Nothing to copy, macro slot [" .. reg .. "] is still empty.",
			"essential",
			vim.log.levels.WARN
		)
		return
	end
	-- remove breakpoints when yanking the macro
	macroContent = macroContent:gsub(vim.pesc(breakPointKey), "")

	local clipboardOpt = opt.clipboard:get() ---@diagnostic disable-line: undefined-field
	local useSystemClipb = #clipboardOpt > 0 and clipboardOpt[1]:find("unnamed")
	local copyToReg = useSystemClipb and "+" or '"'

	fn.setreg(copyToReg, macroContent)
	notify("Copied Macro [" .. reg .. "]:\n" .. macroContent, "nonessential")
end

local function addBreakPoint()
	if isRecording() then
		-- INFO nothing happens, but the key is still recorded in the macro
		notify("Macro breakpoint added.", "essential")
	elseif not isPlaying() and not dapSharedKeymaps then
		notify("Cannot insert breakpoint outside of a recording.", "essential", vim.log.levels.WARN)
	elseif not isPlaying() and dapSharedKeymaps then
		-- only test for dap here to not interfere with user lazyloading
		if require("dap") then require("dap").toggle_breakpoint() end
	end
end

--------------------------------------------------------------------------------
-- CONFIG

---@class configObj
---@field slots string[] named register slots
---@field dynamicSlots string 2 states we could choose from:
---static   -> use static slots
---rotate   -> through letters specified in slots[] if end is encountered it goes(overwrite) from start
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
---@field deleteAllMacros string
---@field switchSlot string
---@field addBreakPoint string

---@param userConfig configObj
function M.setup(userConfig)
	-- initialize values on plugin load
	slotIndex = 1
	breakCounter = 0
	firstRun = true

	local defaultConfig = {
		slots = { "a", "b" },
		dynamicSlots = "static",
		mapping = {
			startStopRecording = "q",
			playMacro = "Q",
			switchSlot = "<C-q>",
			editMacro = "cq",
			deleteAllMacros = "dq",
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
	config = vim.tbl_deep_extend("keep", userConfig, defaultConfig)

	-- settings to be used globally
	perf = config.performanceOpts
	useNerdfontIcons = config.useNerdfontIcons
	lessNotifications = config.lessNotifications
	defaultLogLevel = config.logLevel

	-- validate macro slots
	macroRegs = config.slots
	for _, reg in pairs(macroRegs) do
		if not (reg:find("^%l$")) then
			notify(
				('"%s" is an invalid slot. Choose only named registers (a-z).'):format(reg),
				"essential",
				vim.log.levels.ERROR
			)
			return
		end
	end

	-- clear macro slots
	if config.clear then deleteAllMacros("silent") end

	-- setup keymaps
	toggleKey = config.mapping.startStopRecording
	breakPointKey = normalizeKeycodes(config.mapping.addBreakPoint)
	local icon = config.useNerdfontIcons and " " or ""
	local dapSharedIcon = config.useNerdfontIcons and " /  " or ""

	keymap("n", toggleKey, toggleRecording, { desc = icon .. "Start/Stop Recording" })
	keymap("n", config.mapping.switchSlot, switchMacroSlot, { desc = icon .. "Switch Macro Slot" })
	keymap("n", config.mapping.editMacro, editMacro, { desc = icon .. "Edit Macro" })
	keymap("n", config.mapping.yankMacro, yankMacro, { desc = icon .. "Yank Macro" })
	-- stylua: ignore
	keymap("n", config.mapping.deleteAllMacros, deleteAllMacros, { desc = icon .. "Delete All Macros" })

	-- (experimental) if true, nvim-recorder and dap will use shared keymaps:
	-- 1) `addBreakPoint` will map to `dap.toggle_breakpoint()` outside
	-- a recording. During a recording, it will add a macro breakpoint instead.
	-- 2) `playMacro` will map to `dap.continue()` if there is at least one
	-- dap-breakpoint. If there is no dap breakpoint, will play the current
	-- macro-slot instead
	dapSharedKeymaps = config.dapSharedKeymaps or false
	local breakPointDesc = dapSharedKeymaps and dapSharedIcon .. "Breakpoint"
		or icon .. "Insert Macro Breakpoint."
	keymap("n", breakPointKey, addBreakPoint, { desc = breakPointDesc })
	local playDesc = dapSharedKeymaps and dapSharedIcon .. "Continue/Play" or icon .. "Play Macro"
	keymap("n", config.mapping.playMacro, playRecording, { desc = playDesc })
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
