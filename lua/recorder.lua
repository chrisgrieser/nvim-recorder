require("utils")
local trace = vim.log.levels.TRACE
local warn = vim.log.levels.WARN
local fn = vim.fn
local getMacro = vim.fn.getreg
local setMacro = vim.fn.setreg
local normal = vim.cmd.normal

---@return boolean
local function isRecording()
	return fn.reg_recording() ~= ""
end

local macroRegs, slot, toggleKey
local M = {}
--------------------------------------------------------------------------------

-- start/stop recording macro into the current slot
local function toggleRecording()
	local reg = macroRegs[slot]
	if isRecording() then
		local prevRec = getMacro(macroRegs[slot])
		normal {"q", bang = true}

		-- NOTE the macro key records itself, so it has to be removed from the
		-- register. As this function has to know the variable length of the
		-- LHS key that triggered it, it has to be passed in via .setup()-function
		setMacro(reg, getMacro(reg):sub(1, -1 * (#toggleKey + 1)))

		local justRecorded = getMacro(reg)
		if justRecorded == "" then
			setMacro(reg, prevRec)
			vim.notify(" Recording aborted. (Previous recording is kept.) ", warn)
		else
			vim.notify(" Recorded [" .. reg .. "]: \n " .. justRecorded .. " ", trace)
		end
	else
		normal {"q" .. reg, bang = true}
		vim.notify(" Recording to [" .. reg .. "]… ", trace)
	end
end

---Setup Macro Plugin
---@param config table
function M.setup(config)
	-- TODO typing and validation of config
	macroRegs = config.slots or {"a", "b"}
	slot = 1

	toggleKey = config.toggleKey or "q"
	vim.keymap.set("n", toggleKey, toggleRecording, {desc = "Start/stop recording to current macro slot."})
end

---play the macro recorded in current slot
function M.playRecording()
	normal {"@" .. macroRegs[slot], bang = true}
end

--------------------------------------------------------------------------------

---changes the active slot
function M.switchMacroSlot()
	slot = slot + 1
	if slot > #macroRegs then slot = 1 end
	local currentMacro = getMacro(macroRegs[slot])
	local msg = " Now using macro slot [" .. macroRegs[slot] .. "]. "
	if currentMacro ~= "" then
		msg = msg .. "\n Currently recorded macro: \n " .. currentMacro .. " "
	end
	vim.notify(msg, trace)
end

---edit the current slot
function M.editMacro()
	local reg = macroRegs[slot]
	local macroContent = getMacro(reg)
	local inputConfig = {
		prompt = "Edit Macro [" .. reg .. "]: ",
		default = macroContent,
	}
	vim.ui.input(inputConfig, function(editedMacro)
		if not (editedMacro) then return end -- cancellation
		setMacro(reg, editedMacro)
		vim.notify(" Edited Macro [" .. reg .. "]\n " .. editedMacro, trace)
	end)
end

--------------------------------------------------------------------------------

---returns recording status for status line plugins (e.g., used with cmdheight=0)
---@return string
function M.recordingStatus()
	if not(isRecording()) then return "" end
	return "  REC [" .. macroRegs[slot] .. "]"
end

---returns active slot for status line plugins
---@return string
function M.displayActiveSlot()
	return "Macro [" .. macroRegs[slot] .. "]"
end

--------------------------------------------------------------------------------

return M
