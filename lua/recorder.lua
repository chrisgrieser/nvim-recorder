local fn = vim.fn
local v = vim.v
local getMacro = vim.fn.getreg
local setMacro = vim.fn.setreg
local keymap = vim.keymap.set

---@return boolean
local function isRecording() return fn.reg_recording() ~= "" end
local function isPlaying() return fn.reg_executing() ~= "" end

---runs `:normal` natively with bang
---@param cmdStr any
function normal(cmdStr) vim.cmd.normal { cmdStr, bang = true } end

local macroRegs, slotIndex, logLevel
local toggleKey, breakPointKey, dapSharedKeymaps
local M = {}

local breakCounter = 0 -- resets break counter on plugin reload

--------------------------------------------------------------------------------
-- COMMANDS

-- start/stop recording macro into the current slot
local function toggleRecording()
	local reg = macroRegs[slotIndex]

	-- start recording
	if not isRecording() then
		breakCounter = 0 -- reset break points
		normal("q" .. reg)
		vim.notify("Recording to [" .. reg .. "]…", logLevel)
		return
	end

	-- stop recording
	local prevRec = getMacro(macroRegs[slotIndex])
	normal("q")

	-- NOTE the macro key records itself, so it has to be removed from the
	-- register. As this function has to know the variable length of the
	-- LHS key that triggered it, it has to be passed in via .setup()-function
	local decodedToggleKey = fn.keytrans(toggleKey)
	local recording = getMacro(reg):sub(1, -1 * (#decodedToggleKey + 1))
	setMacro(reg, recording)

	local justRecorded = fn.keytrans(getMacro(reg))
	if justRecorded == "" then
		setMacro(reg, prevRec)
		vim.notify("Recording aborted.\n(Previous recording is kept.)", logLevel)
	else
		vim.notify("Recorded [" .. reg .. "]:\n" .. justRecorded, logLevel)
	end
end

---play the macro recorded in current slot
local function playRecording()
	-- WARN undocumented and prone to change https://github.com/mfussenegger/nvim-dap/discussions/810#discussioncomment-4623606
	if dapSharedKeymaps then
		-- nested to avoid requiring dap for lazyloaders
		local dapBreakpointsExist = next(require("dap.breakpoints").get()) ~= nil
		if dapBreakpointsExist then
			require("dap").continue()
			return
		end
	end
	local reg = macroRegs[slotIndex]
	if isRecording() then
		vim.notify(
			"Playing the macro while it is recording would cause recursion problems. Aborting recording.",
			vim.log.levels.ERROR
		)
		normal("q") -- end recording
		setMacro(reg, "") -- empties macro since the recursion has been recorded there
		return
	end

	local macro = getMacro(reg)
	local hasBreakPoints = macro:find(vim.pesc(breakPointKey))
	local countGiven = v.count ~= 0

	-- empty slot
	if macro == "" then
		vim.notify("Macro Slot [" .. reg .. "] is empty.", logLevel)
		return

	-- with breakpoints
	elseif hasBreakPoints and not countGiven then
		breakCounter = breakCounter + 1
		local macroParts = vim.split(macro, breakPointKey, {})
		local partialMacro = macroParts[breakCounter]

		-- play the partial macro
		setMacro(reg, partialMacro)
		normal("@" .. reg)
		setMacro(reg, macro) -- restore original macro for all other purposes like prewing slots

		if breakCounter ~= #macroParts then
			vim.notify("Reached Breakpoint #" .. tostring(breakCounter), logLevel)
		else
			vim.notify("Reached end of macro", logLevel)
			breakCounter = 0
		end

	-- normal macro
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
	vim.notify(msg, logLevel)
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
		vim.notify("Edited Macro [" .. reg .. "]:\n" .. editedMacro, logLevel)
	end)
end

local function yankMacro()
	breakCounter = 0
	local reg = macroRegs[slotIndex]
	local macroContent = fn.keytrans(getMacro(reg))
	if macroContent == "" then
		vim.notify("Nothing to copy, macro slot [" .. reg .. "] is still empty.", logLevel)
		return
	end
	-- remove breakpoints when yanking the macro
	macroContent = macroContent:gsub(vim.pesc(breakPointKey), "")

	local clipboardOpt = vim.opt.clipboard:get()
	local useSystemClipb = #clipboardOpt > 0 and clipboardOpt[1]:find("unnamed")
	local copyToReg = useSystemClipb and "+" or '"'

	fn.setreg(copyToReg, macroContent)
	vim.notify("Copied Macro [" .. reg .. "]:\n" .. macroContent, logLevel)
end

local function addBreakPoint()
	if isRecording() then
		-- INFO nothing happens, but the key is still recorded in the macro
		vim.notify("Macro breakpoint added.", logLevel)
	elseif not isPlaying() and not dapSharedKeymaps then
		vim.notify("Cannot insert breakpoint outside of a recording.", vim.log.levels.WARN)
	elseif not isPlaying() and dapSharedKeymaps then
		-- only test for dap here to not interfere with user lazyloading
		if require("dap") then require("dap").toggle_breakpoint() end
	end
end

--------------------------------------------------------------------------------
-- CONFIG

---@class configObj
---@field slots table<string> named register slots
---@field clear boolean whether to clear slots/registers on setup
---@field timeout number Default timeout for notification
---@field mapping maps individual mappings
---@field logLevel integer log level (vim.log.levels)
---@field dapSharedKeymaps boolean (experimental) partially share keymaps with dap

---@class maps
---@field startStopRecording string
---@field playMacro string
---@field editMacro string
---@field yankMacro string
---@field switchSlot string
---@field addBreakPoint string

---Setup Macro Plugin
---@param config configObj
function M.setup(config)
	slotIndex = 1 -- initial starting slot
	macroRegs = config.slots or { "a", "b" }
	logLevel = config.logLevel or vim.log.levels.INFO

	-- validation of slots
	for _, reg in pairs(macroRegs) do
		if not (reg:find("^%l$")) then
			vim.notify(
				"'" .. reg .. "' is an invalid slot. Choose only named registers (a-z).",
				vim.log.levels.ERROR
			)
			return
		end
	end

	-- set keymaps
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

	-- clearing
	if config.clear then
		for _, reg in pairs(macroRegs) do
			setMacro(reg, "")
		end
	end
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
