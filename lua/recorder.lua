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

local macroRegs, slot, toggleKey, logLevel
local M = {}
--------------------------------------------------------------------------------
-- COMMANDS

-- start/stop recording macro into the current slot
local function toggleRecording()
	local reg = macroRegs[slot]
	if isRecording() then
		local prevRec = getMacro(macroRegs[slot])
		normal("q")

		-- NOTE the macro key records itself, so it has to be removed from the
		-- register. As this function has to know the variable length of the
		-- LHS key that triggered it, it has to be passed in via .setup()-function
		setMacro(reg, getMacro(reg):sub(1, -1 * (#toggleKey + 1)))

		local justRecorded = getMacro(reg)
		if justRecorded == "" then
			setMacro(reg, prevRec)
			vim.notify("Recording aborted. (Previous recording is kept.)", logLevel)
		else
			vim.notify("Recorded [" .. reg .. "]:\n" .. justRecorded, logLevel)
		end
	else
		normal("q" .. reg)
		vim.notify("Recording to [" .. reg .. "]…", logLevel)
	end
end

---play the macro recorded in current slot
local function playRecording()
	local reg = macroRegs[slot]
	if getMacro(reg) == "" then
		vim.notify("Macro Slot [" .. reg .. "] is empty.", logLevel)
		return
	end
	normal(v.count1 .. "@" .. reg)
end

---changes the active slot
local function switchMacroSlot()
	slot = slot + 1
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

---Setup Macro Plugin
---@param config configObj
function M.setup(config)
	slot = 1 -- initial starting slot
	macroRegs = config.slots or { "a", "b" }
	logLevel = config.logLevel or vim.log.levels.INFO

	-- validation of slots
	for _, reg in pairs(macroRegs) do
		if not (reg:find("^%l$")) then
			echoerr("'" .. reg .. "' is an invalid slot. Choose only named registers (a-z).")
			return
		end
	end

	-- set keymaps
	toggleKey = config.mapping.startStopRecording or "q"
	local playKey = config.mapping.playMacro or "Q"
	local editKey = config.mapping.editMacro or "cq"
	local switchKey = config.mapping.switchSlot or "<C-q>"
	keymap("n", toggleKey, toggleRecording, { desc = "Start/stop recording to current macro slot." })
	keymap("n", playKey, playRecording, { desc = "Play the current macro slot." })
	keymap("n", editKey, editMacro, { desc = "Edit the macro in the current slot." })
	keymap("n", switchKey, switchMacroSlot, { desc = "Edit the macro in the current slot." })

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
	return "  REC [" .. macroRegs[slot] .. "]"
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
			table.insert(out, "[" .. reg .. "]")
		elseif not empty and active then
			table.insert(out, "[ ]")
		elseif empty and not active then
			table.insert(out, reg)
		end
	end
	local output = table.concat(out)
	if output ~= "" then output = " " .. output end
	return output
end

--------------------------------------------------------------------------------

return M
