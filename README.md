# nvim-recorder

Improving the macro experience in neovim.

<!--toc:start-->
- [Features](#features)
- [Installation and Configuration](#installation-and-configuration)
- [Usage](#usage)
- [About me](#about-me)
<!--toc:end-->

## Features
- Simplifies recording macros for one-off macros.
- Instead of having to remember in which register you saved a macro in, you cycle between macro slots. (I'd guess that 90% of vim users never use more than two macros at the same time anyway…)
- Some quality-of-life features like notifications, the ability to cancel a recording, or a command to edit macros.
- Functions for status line plugins. Particularly useful if you use `cmdheight=0`.
- Uses up-to-date nvim features like `vim.ui.input` or `vim.notify`. This means you can get nicer input fields via plugins like [dressing.nvim](https://github.com/stevearc/dressing.nvim), and nicer confirmation notices with plugins like [nvim-notify](https://github.com/rcarriga/nvim-notify).
- Written 100% in lua. Lightweight (< 150 lines) wrapper around the built-in macro-feature.

## Installation and Configuration

```lua
-- packer
use "chrisgrieser/nvim-recorder"
```

```lua
-- setup somewhere in your nvim config
local recorder = require("recorder")

-- setup is required. `recorder.setup()` is enough if you are fine with the defaults.
recorder.setup {
	-- Named registers where macros are saved. 
	-- First register is the default register/macro-slot used after startup. 
	-- Default: {"a", "b"}
	slots = {"a", "b"}, 
	-- key to start/end recording. Default: "q"
	toggleKey = "q",
}
-- these keymaps are *not* set by default, you need to set them yourself like this.
vim.keymap.set("n", "Q", recorder.playRecording)
vim.keymap.set("n", "<C-Q>", recorder.switchMacroSlot)
vim.keymap.set("n", "cq", recorder.editMacro)
```

```lua
-- For status line plugins

-- indicates whether you are currently recording. Useful if you are using `cmdheight=0`, where recording-status is not visible.
require("recorder").recordingStatus()

-- displays the currently selected macro-slot (register)
require("recorder").displayActiveSlot()
```

## Usage
- Use the `toggleKey` to start recording. Saves automatically to the current macro slot, so you do not need to specify a register.
- Press the `toggleKey` again to end the recording. When you press it directly after the beginning of the recording (i.e., an empty macro), the keypress is considered a cancellation and the register/macro-slot is not overridden with an empty macro. 
- `.switchMacroSlot()` cycles through the registers you specified in the configuration, and also show a notice with that macro's content.
- `.editMacro()` and `.playRecording()` to pretty much what they say.

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
