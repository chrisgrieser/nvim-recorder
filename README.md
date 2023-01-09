# nvim-recorder

Enhance the usage of macros in Neovim.

<!--toc:start-->
- [Features](#features)
- [Setup](#setup)
	- [Installation](#installation)
	- [Configuration](#configuration)
- [Usage](#usage)
	- [Basics](#basics)
	- [Macro Breakpoints](#macro-breakpoints)
- [Status Line Components](#status-line-components)
- [Limitations](#limitations)
- [About me](#about-me)
<!--toc:end-->

## Features
- Simplifies recording macros, especially for one-off macros. No need to remember the register where a macro has been saved to.
- Add [breakpoints to your macros](#macro-breakpoints) for easier debugging of macros. Breakpoints can also be set after the recording, and are ignored when triggering a macro with a count.
- Status line components. Particularly useful if you use `cmdheight=0`.
- Some quality-of-life features like notifications with macro content, the ability to cancel a recording, or a command to edit macros.
- Uses up-to-date nvim features like `vim.ui.input` or `vim.notify`. This means you can get confirmation notices with plugins like [nvim-notify](https://github.com/rcarriga/nvim-notify).
- Written 100% in lua. Lightweight wrapper (~250 LoC) around the built-in macro-feature.

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
	config = function() require("recorder").setup() end,
},
```

Calling `setup()` is __required__.

### Configuration

```lua
-- default values
require("recorder").setup {
	-- Named registers where macros are saved. 
	-- First register is the default register/macro-slot used after startup. 
	-- Be aware that vim saves macros in registers, so using a register inside a 
	-- macro will cause trouble.
	slots = {"a", "b"},

	-- Default Mappings
	mapping = {
		startStopRecording = "q",
		playMacro = "Q",
		editMacro = "cq",
		switchSlot = "<C-q>",
		addBreakPoint = "#",
	}

	-- clear all macros on startup
	clear = false,

	-- log level used for any notification. Mostly relevant for nvim-notify. (Note that by default, nvim-notify only shows levels 2 and higher.)
	logLevel = vim.log.levels.INFO,

	-- (experimental) if true, nvim-recorder and dap will use shared keymaps:
	-- 1) `addBreakPoint` will map to `dap.toggle_breakpoint()` outside
	-- a recording. During a recording, it will add a macro breakpoint instead.
	-- 2) `playMacro` will map to `dap.continue()` if there is at least one
	-- dap-breakpoint. If there is no dap breakpoint, will play the current
	-- macro-slot instead
	dapSharedKeymaps = false,
}
```

## Usage

### Basics
- `startStopRecording`: starts recording. Saves automatically to the current macro slot, so you do not need to specify a register. Press again to end the recording.
- `switchSlot`: cycles through the registers you specified in the configuration, and also show a notice with that macro's content.
- `editMacro`: lets you modify the macro recorded in the active slot.
- `playMacro`: plays the macro in the current slot, no need to specify a register.

### Macro Breakpoints
*nvim-recorder* allows you to set breakpoints in your macros which can be helpful for debugging macros. Breakpoints are automatically ignored when you trigger a macro with a count.

__Setting Breakpoints__  
1. *During a recording* press the `addBreakPoint` key (default: `#`) in normal mode. 
2. *After a recording* use `editMacro` and add (or remove) the `#` manually.

__Playing Macros with Breakpoints__  
Using the `playMacro` key, the macro automatically stops at the next breakpoint. The next time you press `playMacro`, the next segment of the macro is played. 

Starting a new recording, editing a macro, or switching macro slot all reset the sequence, meaning that `playMacro` starts from the beginning again.

> __Note__  
> You can also do other things in between playing segments of the macro, like moving a few characters to the left or right. That way you can also use breakpoints to manually correct things.

__Ignoring Breakpoints__  
When you play the macro with a *count* (for example `50Q`), breakpoints are automatically ignored. *Tip*: add a count of 1 (`1Q`) to play a macro once and ignore any breakpoints.


## Status Line Components

```lua
-- indicates whether you are currently recording. Useful if you are using `cmdheight=0`, where recording-status is not visible.
require("recorder").recordingStatus()

-- displays non-empty macro-slots (registers) and indicates the selected ones. Only displayed when *not* recording. Slots with breakpoints get an extra `#`.
-- Recommendation: use with the config `clear = true`
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
```

## Limitations
The plugin does not support recursive macros ( = macros played during macros). 

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
