# nvim-recorder

Enhance the usage of macros in Neovim.

<!--toc:start-->
- [Features](#features)
- [Setup](#setup)
	- [Installation](#installation)
	- [Configuration](#configuration)
	- [Status Line Components](#status-line-components)
- [Usage](#usage)
	- [Basics](#basics)
	- [Macro Breakpoints](#macro-breakpoints)
- [About me](#about-me)
<!--toc:end-->

## Features
- __Simplified controls__: One key to start and stop recording, a second key for playing the macro. Instead of `qa … q @a @@`, you just do `q … q Q Q`.[^1]
- __Macro Breakpoints__ for easier debugging of macros. Breakpoints can also be set after the recording and are automatically ignored when triggering a macro with a count.
- __Status line components__: Particularly useful if you use `cmdheight=0` where the recording status is not visible.
- __Macro-to-Mapping__: Copy a macro in decoded form for mappings to your default register.
- __Various quality-of-life features__ like notifications with macro content, the ability to cancel a recording, or a command to edit macros.
- Uses up-to-date nvim features like `vim.ui.input` or `vim.notify`. This means you can get confirmation notices with plugins like [nvim-notify](https://github.com/rcarriga/nvim-notify).
- Written 100% in lua. Lightweight (~250 LoC).

## Setup

### Installation

```lua
-- packer
use {
	"chrisgrieser/nvim-recorder",
	config = function() require("recorder").setup() end,
}

-- lazy.nvim
{
	"chrisgrieser/nvim-recorder",
	opts = {},
},
```

Calling `setup()` (or lazy's `opts`) is __required__.

### Configuration

```lua
-- default values
require("recorder").setup {
	-- Named registers where macros are saved. The first register is the default
	-- register/macro-slot used after startup. 
	slots = {"a", "b"},

	-- default keymaps, see README for description what the commands do
	mapping = {
		startStopRecording = "q",
		playMacro = "Q",
		switchSlot = "<C-q>",
		editMacro = "cq",
		yankMacro = "yq", -- also decodes it for turning macros to mappings
		addBreakPoint = "##", -- ⚠️ this should be a string you don't use in insert mode during a macro
	},

	-- clears all macros-slots on startup
	clear = false,

	-- log level used for any notification, mostly relevant for nvim-notify
	-- (note that by default, nvim-notify does not show the levels trace and debug.)
	logLevel = vim.log.levels.INFO,

	-- experimental, see README
	dapSharedKeymaps = false,
}
```

If you want to handle multiple macros or use `cmdheight=0`, it is recommended to also set up the status line components.

### Status Line Components

```lua
-- indicates whether you are currently recording. Useful if you are using 
-- `cmdheight=0`, where recording-status is not visible.
require("recorder").recordingStatus()

-- displays non-empty macro-slots (registers) and indicates the selected ones. 
-- Only displayed when *not* recording. Slots with breakpoints get an extra `#`.
-- 💡 use with the config `clear = true` to see recordings you made this session.
require("recorder").displaySlots()
```

Example for adding the status line components to [lualine](https://github.com/nvim-lualine/lualine.nvim):

```lua
lualine_y = {
	{ require("recorder").displaySlots },
},
lualine_z = {
	{ require("recorder").recordingStatus },
},
-- 💡 put the components in different status line segments so they have 
-- a different color, making the recording status more distinguishable
```

## Usage

### Basics
- `startStopRecording`: Starts recording to the current macro slot (so you do not need to specify a register). Press again to end the recording.
- `playMacro`: Plays the macro in the current slot (without the need to specify a register).
- `switchSlot`: Cycles through the registers you specified in the configuration. Also show a notification with the slot and its content. (The currently selected slot can be seen in the [status line component](#status-line-components). )
- `editMacro`: Lets you modify the macro recorded in the active slot. (Be aware that these are the keystrokes in "encoded" form.)
- `yankMacro`: Copies the current macro in decoded form that can be used to create a mapping from it. Breakpoints are removed from the macro

> 💡 For recursive macros (playing a macro inside a macro), you can still use the default command `@a`.

### Macro Breakpoints
*nvim-recorder* allows you to set breakpoints in your macros which can be helpful for debugging macros. Breakpoints are automatically ignored when you trigger the macro with a count.

__Setting Breakpoints__  
1. *During a recording,* press the `addBreakPoint` key (default: `##`) in normal mode. 
2. *After a recording,* use `editMacro` and add or remove the `##` manually. 

__Playing Macros with Breakpoints__  
- Using the `playMacro` key, the macro automatically stops at the next breakpoint. The next time you press `playMacro`, the next segment of the macro is played. 
- Starting a new recording, editing a macro, yanking a macro, or switching macro slot all reset the sequence, meaning that `playMacro` starts from the beginning again.

> 💡 You can do other things in between playing segments of the macro, like moving a few characters to the left or right. That way you can also use breakpoints to manually correct irregularities.

__Ignoring Breakpoints__  
When you play the macro with a *count* (for example `50Q`), breakpoints are automatically ignored. 

> 💡 Add a count of 1 (`1Q`) to play a macro once and still ignore breakpoints.

__Shared Keybindings with nvim-dap__  
If you are using [nvim-dap](https://github.com/mfussenegger/nvim-dap), you can use `dapSharedKeymaps = true` to set up the following shared keybindings:
1. `addBreakPoint` maps to `dap.toggle_breakpoint()` outside
a recording. During a recording, it adds a macro breakpoint instead.
2. `playMacro` maps to `dap.continue()` if there is at least one
dap-breakpoint. If there is no dap-breakpoint, plays the current
macro-slot instead.

Note that this feature is experimental, since the [respective API from nvim-dap is non-public and can be changed without deprecation notice](https://github.com/mfussenegger/nvim-dap/discussions/810#discussioncomment-4623606).


<!-- vale Google.FirstPerson = NO -->
## About me
In my day job, I am a sociologist studying the social mechanisms underlying the digital economy. For my PhD project, I investigate the governance of the app economy and how software ecosystems manage the tension between innovation and compatibility. If you are interested in this subject, feel free to get in touch.

__Profiles__
- [Discord](https://discordapp.com/users/462774483044794368/)
- [Academic Website](https://chris-grieser.de/)
- [GitHub](https://github.com/chrisgrieser/)
- [Twitter](https://twitter.com/pseudo_meta)
- [ResearchGate](https://www.researchgate.net/profile/Christopher-Grieser)
- [LinkedIn](https://www.linkedin.com/in/christopher-grieser-ba693b17a/)

[^1]: As opposed to vim, Neovim already allows you to use `Q` to [play the last recorded macro](https://neovim.io/doc/user/repeat.html#Q). Considering this, the simplified controls really only save you one keystroke for one-off macros. However, as opposed to Neovim's built-in controls, you can still keep using `Q` for playing the not-most-recently recorded macro.
