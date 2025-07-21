# csvview.nvim

A comfortable CSV/TSV editing plugin for Neovim.

<div align="center">
  <video controls src="https://github.com/user-attachments/assets/f529b978-9ae4-4413-b73a-f0fa431c900d"></video>
</div>

## ✨ Features

- Tabular display using virtual text
- Dynamic updates using asynchronous parsing
- Comment Line Handling
- Sticky Headers
- Auto-Detection of Delimiters and Headers
- Text Objects & Motions
- Two Display Modes:
  - `highlight`: Highlights delimiters.
  - `border`: Uses a vertical border (`│`) as delimiters.

<table>
  <tr>
    <th>display_mode = "highlight"</th>
    <th>display_mode = "border"</th>
  </tr>
    <td>
      <img src="https://github.com/user-attachments/assets/cb26e430-c3cb-407f-bb80-42c11ba7fa19" />
    </td>
    <td>
      <img src="https://github.com/user-attachments/assets/17e5fc01-9a58-4801-b2a6-3d23ca48e26f" />
    </td>
  </tr>
</table>

## ⚡ Requirements

Neovim v0.10 or newer is required.

## 📦 Installation

Install the plugin using your favorite package manager.

### lazy.nvim

```lua
{
  "hat0uma/csvview.nvim",
  ---@module "csvview"
  ---@type CsvView.Options
  opts = {
    parser = { comments = { "#", "//" } },
    keymaps = {
      -- Text objects for selecting fields
      textobject_field_inner = { "if", mode = { "o", "x" } },
      textobject_field_outer = { "af", mode = { "o", "x" } },
      -- Excel-like navigation:
      -- Use <Tab> and <S-Tab> to move horizontally between fields.
      -- Use <Enter> and <S-Enter> to move vertically between rows and place the cursor at the end of the field.
      -- Note: In terminals, you may need to enable CSI-u mode to use <S-Tab> and <S-Enter>.
      jump_next_field_end = { "<Tab>", mode = { "n", "v" } },
      jump_prev_field_end = { "<S-Tab>", mode = { "n", "v" } },
      jump_next_row = { "<Enter>", mode = { "n", "v" } },
      jump_prev_row = { "<S-Enter>", mode = { "n", "v" } },
    },
  },
  cmd = { "CsvViewEnable", "CsvViewDisable", "CsvViewToggle" },
}
```

### vim-plug

```vim
Plug 'hat0uma/csvview.nvim'
lua require('csvview').setup()
```

## 🛠️  Configuration

`csvview.nvim` are highly customizable, Please refer to the following default settings.

<details>

<summary>Default Settings</summary>

```lua
{
  parser = {
    --- The number of lines that the asynchronous parser processes per cycle.
    --- This setting is used to prevent monopolization of the main thread when displaying large files.
    --- If the UI freezes, try reducing this value.
    --- @type integer
    async_chunksize = 50,

    --- Specifies the delimiter character to separate columns.
    --- This can be configured in one of three ways:
    ---
    --- 1. As a single string for a fixed delimiter.
    ---    e.g., delimiter = ","
    ---
    --- 2. As a function that dynamically returns the delimiter.
    ---    e.g., delimiter = function(bufnr) return "\t" end
    ---
    --- 3. As a table for advanced configuration:
    ---    - `ft`: Maps filetypes to specific delimiters. This has the highest priority.
    ---    - `fallbacks`: An ordered list of delimiters to try for automatic detection
    ---      when no `ft` rule matches. The plugin will test them in sequence and use
    ---      the first one that highest scores based on the number of fields in each line.
    ---
    --- Note: Only fixed-length strings are supported as delimiters.
    --- Regular expressions (e.g., `\s+`) are not currently supported.
    --- @type CsvView.Options.Parser.Delimiter
    delimiter = {
      ft = {
        csv = ",",
        tsv = "\t",
      },
      fallbacks = {
        ",",
        "\t",
        ";",
        "|",
        ":",
        " ",
      },
    },

    --- The quote character
    --- If a field is enclosed in this character, it is treated as a single field and the delimiter in it will be ignored.
    --- e.g:
    ---  quote_char= "'"
    --- You can also specify it on the command line.
    --- e.g:
    --- :CsvViewEnable quote_char='
    --- @type string
    quote_char = '"',

    --- The comment prefix characters
    --- If the line starts with one of these characters, it is treated as a comment.
    --- Comment lines are not displayed in tabular format.
    --- You can also specify it on the command line.
    --- e.g:
    --- :CsvViewEnable comment=#
    --- @type string[]
    comments = {
      -- "#",
      -- "--",
      -- "//",
    },

    --- Maximum lookahead for multi-line fields
    --- This limits how many lines ahead the parser will look when trying to find 
    --- the closing quote of a multi-line field. Setting this too high may cause
    --- performance issues when editing files with unmatched quotes.
    --- @type integer
    max_lookahead = 50,
  },
  view = {
    --- minimum width of a column
    --- @type integer
    min_column_width = 5,

    --- spacing between columns
    --- @type integer
    spacing = 2,

    --- The display method of the delimiter
    --- "highlight" highlights the delimiter
    --- "border" displays the delimiter with `│`
    --- You can also specify it on the command line.
    --- e.g:
    --- :CsvViewEnable display_mode=border
    ---@type CsvView.Options.View.DisplayMode
    display_mode = "highlight",

    --- The line number of the header row
    --- Controls which line should be treated as the header for the CSV table.
    --- This affects both visual styling and the sticky header feature.
    ---
    --- Values:
    --- - `true`: Automatically detect the header line (default)
    --- - `integer`: Specific line number to use as header (1-based)
    --- - `false`: No header line, treat all lines as data rows
    ---
    --- When a header is defined, it will be:
    --- - Highlighted with the CsvViewHeaderLine highlight group
    --- - Used for the sticky header feature if enabled
    --- - Excluded from normal data processing in some contexts
    ---
    --- See also: `view.sticky_header`
    --- @type integer|false|true
    header_lnum = true,

    --- The sticky header feature settings
    --- If `view.header_lnum` is set, the header line is displayed at the top of the window.
    sticky_header = {
      --- Whether to enable the sticky header feature
      --- @type boolean
      enabled = true,

      --- The separator character for the sticky header window
      --- set `false` to disable the separator
      --- @type string|false
      separator = "─",
    },
  },

  --- Keymaps for csvview.
  --- These mappings are only active when csvview is enabled.
  --- You can assign key mappings to each action defined in `opts.actions`.
  --- For example:
  --- ```lua
  --- keymaps = {
  ---   -- Text objects for selecting fields
  ---   textobject_field_inner = { "if", mode = { "o", "x" } },
  ---   textobject_field_outer = { "af", mode = { "o", "x" } },
  ---
  ---   -- Excel-like navigation:
  ---   -- Use <Tab> and <S-Tab> to move horizontally between fields.
  ---   -- Use <Enter> and <S-Enter> to move vertically between rows.
  ---   -- Note: In terminals, you may need to enable CSI-u mode to use <S-Tab> and <S-Enter>.
  ---   jump_next_field_end = { "<Tab>", mode = { "n", "v" } },
  ---   jump_prev_field_end = { "<S-Tab>", mode = { "n", "v" } },
  ---   jump_next_row = { "<Enter>", mode = { "n", "v" } },
  ---   jump_prev_row = { "<S-Enter>", mode = { "n", "v" } },
  ---
  ---   -- Custom key mapping example:
  ---   { "<leader>h", function() print("hello") end, mode = "n" },
  --- }
  --- ```
  --- @type CsvView.Options.Keymaps
  keymaps = {},

  --- Actions for keymaps.
  ---@type CsvView.Options.Actions
  actions = {
    -- See lua/csvview/config.lua
  },
}
```

</details>

## 🎯 Getting Started

#### Basic Commands

| Command                    | Description                                      |
|----------------------------|--------------------------------------------------|
| `:CsvViewEnable [options]` | Enable CSV view with the specified options      |
| `:CsvViewDisable`          | Disable CSV view                                 |
| `:CsvViewToggle [options]` | Toggle CSV view with the specified options      |

#### Quick Start

```vim
" Enable CSV view with automatic delimiter detection
:CsvViewToggle

" Enable with specific settings
:CsvViewToggle delimiter=, display_mode=border header_lnum=1
```

## 📋 Feature Guide

- [Display Configuration](GUIDE.md#display-configuration)
- [Delimiter Configuration & Auto-Detection](GUIDE.md#delimiter-configuration--auto-detection)
- [Header Configuration & Sticky Headers](GUIDE.md#header-configuration--sticky-headers)
- [Navigation & Text Objects](GUIDE.md#navigation--text-objects)
- [Quote Character Configuration](GUIDE.md#quote-character-configuration)
- [Multi-line Field Configuration](GUIDE.md#multi-line-field-configuration)
- [Comment Line Handling](GUIDE.md#comment-line-handling)
- [API Reference](GUIDE.md#api-reference)

## 🌈 Highlights

The plugin uses the following highlight groups for customizing colors and appearance:

| Group                            | Default                    | Purpose                          |
|----------------------------------|----------------------------|----------------------------------|
| `CsvViewDelimiter`               | links to `Comment`         | Delimiter highlighting           |
| `CsvViewComment`                 | links to `Comment`         | Comment line highlighting        |
| `CsvViewStickyHeaderSeparator`   | links to `CsvViewDelimiter`| Sticky header separator          |
| `CsvViewHeaderLine`              | -                          | Header line highlighting         |
| `CsvViewCol0` to `CsvViewCol8`   | links to `csvCol0`-`csvCol8`| Column-based highlighting       |

## 🎭 Events

This plugin provides custom events that you can hook into for advanced integrations and automation.

### Available Events

| Event            | When Triggered                              | Data              |
|------------------|---------------------------------------------|-------------------|
| `CsvViewAttach`  | CSV view enabled and metrics calculated     | `bufnr` (number)  |
| `CsvViewDetach`  | CSV view disabled                           | `bufnr` (number)  |

<details>
<summary>Example Usage</summary>

```lua
-- Simple event logging
local group = vim.api.nvim_create_augroup("CsvViewEvents", {})

vim.api.nvim_create_autocmd("User", {
  pattern = "CsvViewAttach",
  group = group,
  callback = function(args)
    local bufnr = tonumber(args.data)
    print("CSV view enabled for buffer", bufnr)
  end,
})

vim.api.nvim_create_autocmd("User", {
  pattern = "CsvViewDetach", 
  group = group,
  callback = function(args)
    local bufnr = tonumber(args.data)
    print("CSV view disabled for buffer", bufnr)
  end,
})
```

</details>

## 📝 TODO

- [x] Customizable delimiter character.
- [x] Ignore comment lines.
- [x] Motions and text objects.
- [ ] Enhanced editing features (e.g., sorting, filtering).
- [ ] Row, column, and cell change events for integration with other plugins.

### Not planned

- Pre- and post-processing of files, such as reading/writing Excel files.
- Displaying tables embedded in Markdown as formatted tables.

## 🤝 Contributing

Contributions are welcome! Please open an issue or submit a pull request on GitHub.

## 📄 License

Distributed under the MIT License.

## 👏 Acknowledgements

- [nvim-treesitter-context](https://github.com/nvim-treesitter/nvim-treesitter-context) for inspiration of the sticky-header feature.
