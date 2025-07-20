# csvview.nvim

A comfortable CSV/TSV editing plugin for Neovim.

<div align="center">
  <video controls src="https://github.com/user-attachments/assets/f529b978-9ae4-4413-b73a-f0fa431c900d"></video>
</div>

## ✨ Features

- **Tabular Display**: Displays CSV/TSV files in a virtual text table.
- **Dynamic Updates**: Automatically refreshes the table as you edit.
- **Asynchronous Parsing**: Smoothly handles large CSV files without blocking.
- **Text Objects & Motions**: Conveniently select fields or move across fields/rows.
- **Comment Ignoring**: Skips specified comment lines from the table display.
- **Sticky Header**: Keeps the header row visible while scrolling.
- **Flexible Settings**: Customizable delimiter and comment prefix.
- **Two Display Modes**:
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

<details>
<summary><strong>Delimiter Configuration & Auto-Detection</strong></summary>

csvview.nvim provides flexible delimiter handling with intelligent auto-detection capabilities.

#### Auto-Detection (Recommended)

The plugin automatically detects the most appropriate delimiter by analyzing your file content:

```lua
-- Default configuration with auto-detection
{
  parser = {
    delimiter = {
      ft = {
        csv = ",",        -- Always use comma for .csv files
        tsv = "\t",       -- Always use tab for .tsv files
      },
      fallbacks = {       -- Try these delimiters in order for other files
        ",",              -- Comma (most common)
        "\t",             -- Tab
        ";",              -- Semicolon
        "|",              -- Pipe
        ":",              -- Colon
        " ",              -- Space
      },
    },
  },
}
```

**How auto-detection works:**

1. If the file type matches `ft` rules (e.g., `.csv` → comma), use that delimiter
2. Otherwise, test each delimiter in `fallbacks` order
3. Score each delimiter based on field consistency across lines
4. Select the delimiter with the highest score

#### Manual Delimiter Configuration

**Fixed delimiter for all files:**

```lua
{
  parser = {
    delimiter = ",",  -- Always use comma
  },
}
```

**Dynamic delimiter with function:**

```lua
{
  parser = {
    delimiter = function(bufnr)
      local filename = vim.api.nvim_buf_get_name(bufnr)
      if filename:match("%.tsv$") then
        return "\t"
      end
      return ","
    end,
  },
}
```

> [!NOTE]
> Multi-character delimiters are supported (e.g., `||`, `::`, `<>`), but regular expression patterns are not supported (e.g., `\s+`).

#### Command-line Delimiter Options

```vim
" For unknown file formats, let auto-detection work
:CsvViewEnable

" Specific delimiters
:CsvViewEnable delimiter=,
:CsvViewEnable delimiter=\t

" Special characters (use escape sequences)
:CsvViewEnable delimiter=\   " Space
:CsvViewEnable delimiter=\t  " Tab
```

</details>

<details>
<summary><strong>Display Configuration</strong></summary>

#### Display Modes

**Highlight Mode (Default)**

Highlights delimiter characters in place:

```lua
{
  view = {
    display_mode = "highlight",
  },
}
```

**Border Mode**

Replaces delimiters with vertical borders (`│`):

```lua
{
  view = {
    display_mode = "border",
  },
}
```

**Toggle display modes:**

```vim
:CsvViewEnable display_mode=highlight
:CsvViewEnable display_mode=border
```

#### Column Layout

```lua
{
  view = {
    min_column_width = 5,  -- Minimum width for each column
    spacing = 2,           -- Space between columns
  },
}
```

</details>

<details>
<summary><strong>Sticky Header & Header Auto-Detection</strong></summary>

Keep header rows visible while scrolling through large CSV files.

#### Header Auto-Detection (Recommended)

The plugin automatically detects header rows by analyzing file content:

```lua
-- Default configuration with auto-detection
{
  view = {
    header_lnum = true,  -- Auto-detect header (default)
    sticky_header = {
      enabled = true,
      separator = "─",  -- Separator line character
    },
  },
}
```

**How header auto-detection works:**

1. Find the first non-comment line as header candidate
2. Analyze each column independently using two heuristics:
   - **Type Mismatch**: If the first row contains text while data rows are numeric, it's likely a header
   - **Length Deviation**: If the first row's text length differs significantly from data rows, it's likely a header
3. Combine evidence from all columns to make the final decision

#### Manual Header Configuration

**Fixed header line:**

```lua
{
  view = {
    header_lnum = 1,  -- Use line 1 as header
    -- header_lnum = 3,  -- Use line 3 as header
  },
}
```

**Disable header:**

```lua
{
  view = {
    header_lnum = false,  -- No header line
  },
}
```

#### Command-line usage

```vim
:CsvViewEnable header_lnum=auto  " Auto-detect header (default)
:CsvViewEnable header_lnum=1     " First line as header
:CsvViewEnable header_lnum=none  " No header line
```

#### Customize Separator

```lua
{
  view = {
    sticky_header = {
      separator = "═",     -- Double line
      -- separator = false, -- No separator
    },
  },
}
```

</details>

<details>
<summary><strong>Navigation & Text Objects</strong></summary>

#### Excel-like Navigation

Navigate between fields and rows with familiar keyboard shortcuts:

```lua
{
  keymaps = {
    -- Horizontal navigation
    jump_next_field_end = { "<Tab>", mode = { "n", "v" } },
    jump_prev_field_end = { "<S-Tab>", mode = { "n", "v" } },
    
    -- Vertical navigation  
    jump_next_row = { "<Enter>", mode = { "n", "v" } },
    jump_prev_row = { "<S-Enter>", mode = { "n", "v" } },
  },
}
```

#### Text Objects for Field Selection

```lua
{
  keymaps = {
    -- Select field content (inner)
    textobject_field_inner = { "if", mode = { "o", "x" } },
    
    -- Select field including delimiter (outer)  
    textobject_field_outer = { "af", mode = { "o", "x" } },
  },
}
```

**Usage examples:**

- `vif` - Select current field content
- `vaf` - Select current field including delimiter
- `dif` - Delete field content
- `caf` - Change entire field

#### Custom Navigation

```lua
-- Jump to specific field position
require("csvview.jump").field(0, {
  pos = { 2, 3 },      -- Row 2, Column 3
  mode = "absolute",
  anchor = "start",    -- Place cursor at field start
})
```

</details>

<details>
<summary><strong>Quote Character Configuration</strong></summary>

Handle quoted fields that contain delimiters or special characters.

#### Basic Quote Configuration

```lua
{
  parser = {
    quote_char = '"',   -- Standard double quotes (default)
    -- quote_char = "'", -- Single quotes
  },
}
```

#### How Quoted Fields Work

When a field is enclosed in quote characters, the delimiter inside is ignored:

```csv
name,description,value
John,"Smith, Jr.",100
Jane,"O'Connor ""Jane""",200
```

In this example:

- `"Smith, Jr."` contains a comma but is treated as one field
- `"O'Connor ""Jane"""` contains escaped quotes within the field

#### Command-line Usage

```vim
" Use double quotes (default)
:CsvViewEnable quote_char="

" Use single quotes
:CsvViewEnable quote_char='

" Disable quote handling (not recommended)
:CsvViewEnable quote_char=
```

#### Multi-line Field Support

Quoted fields can span multiple lines:

```csv
id,description
1,"This is a long
description that spans
multiple lines"
2,"Another field"
```

Configure the parser for multi-line fields:

```lua
{
  parser = {
    max_lookahead = 50,  -- Maximum lines to search for closing quotes
  },
}
```

</details>

<details>
<summary><strong>Multi-line Field Configuration</strong></summary>

Handle CSV fields that span multiple lines when properly quoted.

#### Basic Configuration

```lua
{
  parser = {
    max_lookahead = 50,  -- Maximum lines to search for closing quotes
  },
}
```

#### How Multi-line Fields Work

When a field starts with a quote character but doesn't end on the same line, the parser will search ahead for the closing quote:

```csv
id,description,notes
1,"This field contains
multiple lines of text
with embedded newlines",Short note
2,"Another multi-line field
that spans several lines",Another note
```

**Adjust `max_lookahead` based on your data:**

- Increase for files with long multi-line fields (e.g., `max_lookahead = 200`)
- Decrease for simple CSV files to improve performance (e.g., `max_lookahead = 10`)

</details>

<details>
<summary><strong>Comment Line Handling</strong></summary>

Skip comment lines from the table display to focus on data rows.

#### Basic Comment Configuration

```lua
{
  parser = {
    comments = { "#", "//", "--" },  -- Lines starting with these are ignored
  },
}
```

#### Comment Examples

```csv
# This is a comment line
// Another comment style
-- SQL-style comment
name,age,city
John,25,NYC
# Comments can appear anywhere
Jane,30,LA
```

Only the data rows (`name,age,city`, `John,25,NYC`, `Jane,30,LA`) will be displayed in the table format.

#### Command-line Usage

```vim
" Enable hash comments
:CsvViewEnable comment=#

" Enable C++ style comments  
:CsvViewEnable comment=//

" Enable SQL style comments
:CsvViewEnable comment=--

" Multiple comment types (requires Lua configuration)
```

#### Advanced Comment Configuration

```lua
{
  parser = {
    comments = {
      "#",        -- Shell/Python style
      "//",       -- C++ style  
      "--",       -- SQL style
      ";;",       -- Custom comment prefix
    },
  },
}
```

#### Use Cases

- **Data files with metadata**: Skip header comments explaining the data format
- **Generated CSV files**: Ignore generator information or timestamps  
- **Configuration files**: Skip documentation lines in CSV-like config files
- **Log analysis**: Focus on data rows while ignoring log headers

</details>

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

### Basic Event Usage

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

### Lua API Reference

<details>
<summary><strong>Core Functions</strong></summary>

```lua
local csvview = require('csvview')

-- Buffer management
csvview.enable(bufnr?, opts?)    -- Enable for specific buffer
csvview.disable(bufnr?)          -- Disable for specific buffer
csvview.toggle(bufnr?, opts?)    -- Toggle with options
csvview.is_enabled(bufnr?)       -- Check status
```

</details>

<details>
<summary><strong>Jump API</strong></summary>

```lua
local jump = require("csvview.jump")

-- Precise field navigation
jump.field(bufnr, {
  pos = { row, col },           -- Target position (1-based)
  mode = "absolute",            -- "absolute" or "relative" 
  anchor = "start",             -- "start" or "end"
  col_wrap = true,              -- Wrap at row boundaries
})

-- Convenience functions
jump.next_field_start(bufnr?)   -- Like 'w' motion
jump.prev_field_start(bufnr?)   -- Like 'b' motion  
jump.next_field_end(bufnr?)     -- Like 'e' motion
jump.prev_field_end(bufnr?)     -- Like 'ge' motion
```

</details>

<details>
<summary><strong>Text Object API</strong></summary>

```lua
local textobj = require("csvview.textobject")

-- Select current field
textobj.field(bufnr, {
  include_delimiter = false,    -- Include surrounding delimiter
})
```

</details>

<details>
<summary><strong>Utility Functions</strong></summary>

```lua
local util = require("csvview.util")

-- Get detailed cursor information
local info = util.get_cursor(bufnr)
-- Returns:
-- {
--   kind = "field" | "comment" | "empty_line",
--   pos = { row, col },        -- 1-based CSV coordinates
--   anchor = "start" | "end" | "inside" | "delimiter",
--   text = "field content"
-- }
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
