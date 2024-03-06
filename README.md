<!-- LTeX: enabled=false -->
# nvim-recorder 📹
<!-- LTeX: enabled=true -->
<a href="https://dotfyle.com/plugins/chrisgrieser/nvim-recorder">
<img alt="badge" src="https://dotfyle.com/plugins/chrisgrieser/nvim-recorder/shield"/></a>

Enhance the usage of macros in Neovim.

<!-- toc -->

- [Features](#features)
- [Setup](#setup)
	* [Installation](#installation)
	* [Configuration](#configuration)
	* [Status Line Components](#status-line-components)
- [Basic Usage](#basic-usage)
- [Advanced Usage](#advanced-usage)
	* [Performance Optimizations](#performance-optimizations)
	* [Macro Breakpoints](#macro-breakpoints)
	* [Lazy-loading the plugin](#lazy-loading-the-plugin)
- [About me](#about-me)

<!-- tocstop -->

## Features
- __Simplified controls__: One key to start and stop recording, a second key for
  playing the macro. Instead of `qa … q @a @@`, you just do `q … q Q Q`.[^1]
- __Macro Breakpoints__ for easier debugging of macros. Breakpoints can also be
  set after the recording and are automatically ignored when triggering a macro
  with a count.
- __Status line components__: Particularly useful if you use `cmdheight=0` where
  the recording status is not visible.
- __Macro-to-Mapping__: Copy a macro, so you can save it as a mapping.
- __Various quality-of-life features__: notifications with macro content, the
  ability to cancel a recording, a command to edit macros,
- __Performance Optimizations for large macros__: When the macro is triggered
  with a high count, temporarily enable some performance improvements.
- Uses up-to-date nvim features like `vim.notify`. This means you can get
  confirmation notices with plugins like
  [nvim-notify](https://github.com/rcarriga/nvim-notify).

## Setup

### Installation

```lua
-- lazy.nvim
{
	"chrisgrieser/nvim-recorder",
	dependencies = "rcarriga/nvim-notify", -- optional
	opts = {}, -- required even with default settings, since it calls `setup()`
},

-- packer
use {
	"chrisgrieser/nvim-recorder",
	requires = "rcarriga/nvim-notify", -- optional
	config = function() require("recorder").setup() end,
}
```

Calling `setup()` (or `lazy`'s `opts`) is __required__.

### Configuration

```lua
-- default values
require("recorder").setup {
	-- Named registers where macros are saved (single lowercase letters only).
	-- The first register is the default register used as macro-slot after
	-- startup.
	slots = { "a", "b" },

	mapping = {
		startStopRecording = "q",
		playMacro = "Q",
		-- ⚠️ this should be a mapping you don't normally use in insert mode
		insertPlayMacro = "<C-q>",
		switchSlot = "<C-q>",
		editMacro = "cq",
		deleteAllMacros = "dq",
		yankMacro = "yq",
		-- ⚠️ this should be a string you don't use in insert mode during a macro
		addBreakPoint = "##",
		-- ⚠️ this should be a string you don't use in normal mode during a macro
		insertAddBreakPoint = "<C-e>",
	},

	-- Clears all macros-slots on startup.
	clear = false,

	-- Log level used for any notification, mostly relevant for nvim-notify.
	-- (Note that by default, nvim-notify does not show the levels `trace` & `debug`.)
	logLevel = vim.log.levels.INFO,

	-- If enabled, only critical notifications are sent.
	-- If you do not use a plugin like nvim-notify, set this to `true`
	-- to remove otherwise annoying messages.
	lessNotifications = false,

	-- Use nerdfont icons in the status bar components and keymap descriptions
	useNerdfontIcons = true,

	-- Performance optimzations for macros with high count. When `playMacro` is
	-- triggered with a count higher than the threshold, nvim-recorder
	-- temporarily changes changes some settings for the duration of the macro.
	performanceOpts = {
		countThreshold = 100,
		lazyredraw = true, -- enable lazyredraw (see `:h lazyredraw`)
		noSystemClipboard = true, -- remove `+`/`*` from clipboard option
		autocmdEventsIgnore = { -- temporarily ignore these autocmd events
			"TextChangedI",
			"TextChanged",
			"InsertLeave",
			"InsertEnter",
			"InsertCharPre",
		},
	},

	-- [experimental] partially share keymaps with nvim-dap.
	-- (See README for further explanations.)
	dapSharedKeymaps = false,
}
```

If you want to handle multiple macros or use `cmdheight=0`, it is recommended to
also set up the status line components:

### Status Line Components

```lua
-- Indicates whether you are currently recording. Useful if you are using
-- `cmdheight=0`, where recording-status is not visible.
require("recorder").recordingStatus()

-- Displays non-empty macro-slots (registers) and indicates the selected ones.
-- Only displayed when *not* recording. Slots with breakpoints get an extra `#`.
require("recorder").displaySlots()
```

> [!TIP]
> Use with the config `clear = true` to see recordings you made this session.

Example for adding the status line components to [lualine](https://github.com/nvim-lualine/lualine.nvim):

```lua
lualine_y = {
	{ require("recorder").displaySlots },
},
lualine_z = {
	{ require("recorder").recordingStatus },
},
```

> [!TIP]
> Put the components in different status line segments, so they have
> a different color, making the recording status more distinguishable
> from saved recordings

## Basic Usage

- `startStopRecording`: Starts recording to the current macro slot (so you do
  not need to specify a register). Press again to end the recording.
- `playMacro`: Plays the macro in the current slot (without the need to specify
  a register), continuing the current macro if at a breakpoint.
- `insertPlayMacro`: Insert-mode version of `playMacro` (useful when a breakpoint
  is hit in insert mode).
- `switchSlot`: Cycles through the registers you specified in the configuration.
  Also show a notification with the slot and its content. (The currently
  selected slot can be seen in the [status line
  component](#status-line-components).)
- `editMacro`: Edit the macro recorded in the active slot. (Be aware that these
  are the keystrokes in "encoded" form.)
- `yankMacro`: Copies the current macro in decoded form that can be used to
  create a mapping from it. Breakpoints are removed from the copied macro.
- `deleteAllMacros`: Copies the current macro in decoded form that can be used to

> [!TIP]
> For recursive macros (playing a macro inside a macro), you can still use
> the default command `@a`.

## Advanced Usage

### Performance Optimizations
Running long macros or macros with a high count, can be demanding on the system
and result in lags. For this reason, `nvim-recorder` provides some performance
optimizations that are temporarily enabled when a macro with a high count is
run.

Note that these optimizations do have some potential drawbacks.
- [`lazyredraw`](https://neovim.io/doc/user/options.html#'lazyredraw') disables
  redrawing of the screen, which makes it harder to notice edge cases not
  considered in the macro. It may also appear as if the screen is frozen for a
  while.
- Disabling the system clipboard is mostly safe, if you do not intend to copy
  content to it with the macro.
- Ignoring auto-commands is not recommended, when you rely on certain plugin
  functionality during the macro, since it can potentially disrupt those
  plugins' effect.

### Macro Breakpoints
`nvim-recorder` allows you to set breakpoints in your macros, which can be
helpful for debugging macros. Breakpoints are automatically ignored when you
trigger the macro with a count.

__Setting Breakpoints__  
1. *During a recording,* press the `addBreakPoint` key (default: `##`) in normal mode,
    and the `insertAddBreakPoint` key (default: `<C-e>`) in insert mode.
2. *After a recording,* use `editMacro` and add or remove the `##` manually.

__Playing Macros with Breakpoints__  
- Using the `playMacro`/`insertPlayMacro` key, the macro automatically stops at
  the next breakpoint. The next time you press `playMacro`/`insertPlayMacro`, the
  next segment of the macro is played.
- Starting a new recording, editing a macro, yanking a macro, or switching macro
  slot all reset the sequence, meaning that `playMacro` starts from the
  beginning again.

> [!TIP]
> You can do other things in between playing segments of the macro, like
> moving a few characters to the left or right. That way you can also use
> breakpoints to manually correct irregularities.

__Ignoring Breakpoints__  
When you play the macro with a *count* (for example `50Q`), breakpoints are
automatically ignored.

> [!TIP]
> Add a count of 1 (`1Q`) to play a macro once and still ignore breakpoints.

__Shared Keybindings with `nvim-dap`__  
If you are using [nvim-dap](https://github.com/mfussenegger/nvim-dap), you can
use `dapSharedKeymaps = true` to set up the following shared keybindings:
1. `addBreakPoint` maps to `dap.toggle_breakpoint()` outside
a recording. During a recording, it adds a macro breakpoint instead.
2. `playMacro` maps to `dap.continue()` if there is at least one
DAP-breakpoint. If there is no DAP-breakpoint, plays the current
macro-slot instead.

Note that this feature is experimental, since the [respective API from nvim-dap
is non-public and can be changed without deprecation
notice](https://github.com/mfussenegger/nvim-dap/discussions/810#discussioncomment-4623606).

### Lazy-loading the plugin
`nvim-recorder` can be lazy-loaded, but the setup is a bit more complex than
with other plugins.

`nvim-recorder` is best lazy-loaded on the mappings for `startStopRecording` and
`playMacro`. However, it is still required to set the mappings to the `setup`
call.

However, since using the status line components also results in loading the
plugin. The loading of the status line components can be delayed by setting them
in the plugin's `config`. The only drawback of this method is that no component
is shown when until you start or play a recording (which you can completely
disregard when you set `clear = true`, though).

Nonetheless, the plugin is pretty lightweight (~350 lines of code), so not
lazy-loading it should not have a big impact.

```lua
-- minimal config for lazy-loading with lazy.nvim
{
	"chrisgrieser/nvim-recorder",
	dependencies = "rcarriga/nvim-notify",
	keys = {
		-- these must match the keys in the mapping config below
		{ "q", desc = " Start Recording" },
		{ "Q", desc = " Play Recording" },
	},
	config = function()
		require("recorder").setup({
			mapping = {
				startStopRecording = "q",
				playMacro = "Q",
			},
		})

			local lualineZ = require("lualine").get_config().sections.lualine_z or {}
			local lualineY = require("lualine").get_config().sections.lualine_y or {}
			table.insert(lualineZ, { require("recorder").recordingStatus })
			table.insert(lualineY, { require("recorder").displaySlots })

			require("lualine").setup {
				tabline = {
					lualine_y = lualineY,
					lualine_z = lualineZ,
				},
			}
	end,
},
```

<!-- vale Google.FirstPerson = NO -->
## About me
In my day job, I am a sociologist studying the social mechanisms underlying the
digital economy. For my PhD project, I investigate the governance of the app
economy and how software ecosystems manage the tension between innovation and
compatibility. If you are interested in this subject, feel free to get in touch.

__Blog__  
I also occasionally blog about vim: [Nano Tips for Vim](https://nanotipsforvim.prose.sh)

__Profiles__
- [Discord](https://discordapp.com/users/462774483044794368/)
- [Academic Website](https://chris-grieser.de/)
- [GitHub](https://github.com/chrisgrieser/)
- [Twitter](https://twitter.com/pseudo_meta)
- [Mastodon](https://pkm.social/@pseudometa)
- [ResearchGate](https://www.researchgate.net/profile/Christopher-Grieser)
- [LinkedIn](https://www.linkedin.com/in/christopher-grieser-ba693b17a/)

<a href='https://ko-fi.com/Y8Y86SQ91' target='_blank'>
<img
	height='36'
	style='border:0px;height:36px;'
	src='https://cdn.ko-fi.com/cdn/kofi1.png?v=3'
	border='0'
	alt='Buy Me a Coffee at ko-fi.com'
/></a>

[^1]: As opposed to vim, Neovim already allows you to use `Q` to [play the last
	recorded macro](https://neovim.io/doc/user/repeat.html#Q). Considering this,
	the simplified controls really only save you one keystroke for one-off
	macros. However, as opposed to Neovim's built-in controls, you can still
	keep using `Q` for playing the not-most-recently recorded macro.
