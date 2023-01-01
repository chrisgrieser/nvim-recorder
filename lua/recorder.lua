local fn = vim.fn
local v = vim.v
local echoerr = vim.cmd.echoerr
local getMacro = vim.fn.getreg
local setMacro = vim.fn.setreg
local keymap = vim.keymap.set

---@return boolean
local function isRecording() return fn.reg_recording() ~= "" end

---runs :normal natively with bang
---@param cmdStr any
function normal(cmdStr) vim.cmd.normal { cmdStr, bang = true } end


local macroRegs, slot, logLevel
local toggleKey, breakPointKey
local M = {}

local breakCounter = 0 -- resets break counter on plugin reload
local logWarn = vim.log.levels.WARN
--------------------------------------------------------------------------------
-- COMMANDS

-- start/stop recording macro into the current slot
local function toggleRecording()
	local reg = macroRegs[slot]

	-- start recording
	if not isRecording() then
		breakCounter = 0 -- reset break points
		normal("q" .. reg)
		vim.notify("Recording to [" .. reg .. "]…", logLevel)
		return
	end

	-- stop recording
	local prevRec = getMacro(macroRegs[slot])
	normal("q")

	-- NOTE the macro key records itself, so it has to be removed from the
	-- register. As this function has to know the variable length of the
	-- LHS key that triggered it, it has to be passed in via .setup()-function
	local recording = getMacro(reg):sub(1, -1 * (#toggleKey + 1))
	setMacro(reg, recording)

	local justRecorded = getMacro(reg)
	if justRecorded == "" then
		setMacro(reg, prevRec)
		vim.notify("Recording aborted.\n(Previous recording is kept.)", logLevel)
	else
		vim.notify("Recorded [" .. reg .. "]:\n" .. justRecorded, logLevel)
	end
end

---play the macro recorded in current slot
local function playRecording()
	local reg = macroRegs[slot]
	local macro = getMacro(reg)

	-- empty slot
	if macro == "" then
		vim.notify("Macro Slot [" .. reg .. "] is empty.", logLevel)
		return

	-- macro has breakpoints
	elseif macro:find(vim.pesc(breakPointKey)) then
		if v.count1 > 1 then
			vim.notify("Cannot play macro ["..reg.."] with a count since it contains breakpoints.\nRemove breakpoints or play without a count.", logWarn)
			return
		end
		breakCounter = breakCounter + 1
		local macroParts = vim.split(macro, breakPointKey, {})
		local partialMacro = macroParts[breakCounter]

		-- play the partial macro
		setMacro(slot, partialMacro)
		normal("@" .. reg)
		setMacro(slot, macro) -- restore original macro for all other purposes like prewing slots

		if breakCounter == #macroParts then
			vim.notify("Reached end of macro.", logLevel)
			breakCounter = 0
		else
			vim.notify("Reached Breakpoint #"..tostring(breakCounter), logLevel)
		end

	-- play normal macro
	else
		normal(v.count1 .. "@" .. reg)
	end
end

---changes the active slot
local function switchMacroSlot()
	slot = slot + 1
	breakCounter = 0 -- reset breakpoint counter
	if slot > #macroRegs then slot = 1 end
	local currentMacro = getMacro(macroRegs[slot])
	local msg = " Now using macro slot [" .. macroRegs[slot] .. "]"
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
	local reg = macroRegs[slot]
	local macroContent = getMacro(reg)
	local inputConfig = {
		prompt = "Edit Macro [" .. reg .. "]: ",
		default = macroContent,
	}
	vim.ui.input(inputConfig, function(editedMacro)
		if not editedMacro then return end -- cancellation
		setMacro(reg, editedMacro)
		vim.notify("Edited Macro [" .. reg .. "]\n" .. editedMacro, logLevel)
	end)
end

local function addBreakPoint()
	if isRecording() then
		-- does nothing, but is recorded in the macro
		vim.notify("Macro breakpoint added.", logLevel)
	else
		vim.notify("Cannot insert breakpoint outside of a recording.", logWarn)
	end
end

--------------------------------------------------------------------------------
-- CONFIG

---@class configObj
---@field slots table<string>: named register slots
---@field clear boolean: whether to clear slots/registers on setup
---@field timeout number: Default timeout for notification
---@field mapping maps: individual mappings
---@field logLevel integer: log level (vim.log.levels)

---@class maps
---@field startStopRecording string
---@field playMacro string
---@field editMacro string
---@field switchSlot string
---@field addBreakPoint string

---Setup Macro Plugin
---@param config configObj
function M.setup(config)
	slot = 1 -- initial starting slot
	macroRegs = config.slots or { "a", "b" }
	logLevel = config.logLevel or vim.log.levels.INFO

	-- validation of slots
	for _, reg in pairs(macroRegs) do
		if not (reg:find("^%l$")) then
			vim.notify("'" .. reg .. "' is an invalid slot. Choose only named registers (a-z).", vim.log.levels.ERROR)
			return
		end
	end

	-- set keymaps
	toggleKey = config.mapping.startStopRecording or "q"
	local playKey = config.mapping.playMacro or "Q"
	local editKey = config.mapping.editMacro or "cq"
	local switchKey = config.mapping.switchSlot or "<C-q>"
	breakPointKey = config.mapping.addBreakPoint -- not setting default yet, as it's still experimental
	keymap("n", toggleKey, toggleRecording, { desc = "Start/stop recording to current macro slot." })
	keymap("n", playKey, playRecording, { desc = "Play the current macro slot." })
	keymap("n", editKey, editMacro, { desc = "Edit the macro in the current slot." })
	keymap("n", switchKey, switchMacroSlot, { desc = "Edit the macro in the current slot." })
	if breakPointKey then
		keymap("n", breakPointKey, addBreakPoint, { desc = "Insert Break point during a recording." })
	end

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
	return "  Recording… [" .. macroRegs[slot] .. "]"
end

---returns non-empty for status line plugins.
---@return string
function M.displaySlots()
	if isRecording() then return "" end
	local out = {}
	for _, reg in pairs(macroRegs) do
		local empty = getMacro(reg) == ""
		local active = macroRegs[slot] == reg
		if empty and active then
			table.insert(out, "[ ]")
		elseif not empty and active then
			table.insert(out, "[" .. reg .. "]")
		elseif not empty and not active then
			table.insert(out, reg)
		end
	end

	local output = table.concat(out)
	if output == "[ ]" then return "" end
	return " " .. output
end

--------------------------------------------------------------------------------

return M
