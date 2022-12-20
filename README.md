# nvim-recorder

Simplifying and improving how you interact with macros in neovim.

<!--toc:start-->
- [Features](#features)
- [Installation and Configuration](#installation-and-configuration)
- [Usage](#usage)
- [Status Line Components](#status-line-components)
- [About me](#about-me)
<!--toc:end-->

## Features
- Simplifies recording macros, especially for one-off macros.
- Instead of having to remember in which register you saved a macro in, you cycle between macro slots. (I'd guess that 90% of vim users never use more than two macros at the same time anyway…)
- Some quality-of-life features like notifications with macro content, the ability to cancel a recording, or a command to edit macros.
- Status line components. Particularly useful if you use `cmdheight=0`.
- Uses up-to-date nvim features like `vim.ui.input` or `vim.notify`. This means you can get confirmation notices with plugins like [nvim-notify](https://github.com/rcarriga/nvim-notify).
- Written 100% in lua. Lightweight wrapper around the built-in macro-feature.

## Installation and Configuration

```lua
-- packer
use "chrisgrieser/nvim-recorder"
```

```lua
-- setup is required and will use the default config
require("recorder").setup()
```

```lua
-- default config
require("recorder").setup {
	-- Named registers where macros are saved. 
	-- First register is the default register/macro-slot used after startup. 
	-- Be aware that vim saves macros in registers, so using a register inside a 
	-- macro will cause trouble.
	slots = {"a", "b"},

	-- clear the macro-slots/registers on startup/running this setup function
	clear = false,

	-- log level used for any notification. Mostly relevant for nvim-notify. (Note that by default, nvim-notify only shows levels 2 and higher.)
	logLevel = vim.log.levels.INFO,

	-- Default Mappings
	mapping = {
		startStopRecording = "q",
		playMacro = "Q",
		editMacro = "cq",
		switchSlot = "<C-q>",
	}
}
```

## Usage
- Use the `toggleKey` to start recording. Saves automatically to the current macro slot, so you do not need to specify a register.
- Press the `toggleKey` again to end the recording. 
- `.switchMacroSlot()` cycles through the registers you specified in the configuration, and also show a notice with that macro's content.
- `.editMacro()` and `.playRecording()` to pretty much what they say.

## Status Line Components

```lua
-- indicates whether you are currently recording. Useful if you are using `cmdheight=0`, where recording-status is not visible.
require("recorder").recordingStatus()

-- displays non-empty macro-slots (registers) and indicates the selected ones. Only displayed when *not* recording.
-- Recommendation: use with the config `clear = true`
require("recorder").displaySlots()
```

Example for adding the status line components for [lualine](https://github.com/nvim-lualine/lualine.nvim):

```lua
lualine_y = {
	{ require("recorder").recordingStatus },
	{ require("recorder").displaySlots },
},
```

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
