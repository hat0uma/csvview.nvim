# csvview.nvim

A comfortable CSV/TSV editing plugin for Neovim.

![csvview](https://github.com/hat0uma/csvview.nvim/assets/55551571/27130f41-98f5-445d-a9eb-643b31e0b96b)

## ✨ Features

- **Tabular Display**: Displays CSV/TSV files in a virtual text table.
- **Dynamic Updates**: Automatically refreshes the table as you edit.
- **Asynchronous Parsing**: Smoothly handles large CSV files without blocking.
- **Text Objects & Motions**: Conveniently select fields or move across fields/rows.
- **Comment Ignoring**: Skips specified comment lines from the table display.
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

    --- The delimiter character
    --- You can specify a string, a table of delimiter characters for each file type, or a function that returns a delimiter character.
    --- e.g:
    ---  delimiter = ","
    ---  delimiter = function(bufnr) return "," end
    ---  delimiter = {
    ---    default = ",",
    ---    ft = {
    ---      tsv = "\t",
    ---    },
    ---  }
    --- @type CsvView.Options.Parser.Delimiter
    delimiter = {
      default = ",",
      ft = {
        tsv = "\t",
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
    ---@type CsvView.Options.View.DisplayMode
    display_mode = "highlight",
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
    textobject_field_inner = {
      function()
        require("csvview.textobject").field(0, { include_delimiter = false })
      end,
      desc = "[csvview] Select the current field",
      noremap = true,
      silent = true,
    },
    textobject_field_outer = {
      function()
        require("csvview.textobject").field(0, { include_delimiter = true })
      end,
      desc = "[csvview] Select the current field with delimiter",
      noremap = true,
      silent = true,
    },
    jump_next_field_start = {
      function()
        for _ = 1, vim.v.count1 do
          require("csvview.jump").next_field_start()
        end
      end,
      desc = "[csvview] Jump to the next start of the field",
      noremap = true,
      silent = true,
    },
    jump_prev_field_start = {
      function()
        for _ = 1, vim.v.count1 do
          require("csvview.jump").prev_field_start()
        end
      end,
      desc = "[csvview] Jump to the previous start of the field",
      noremap = true,
      silent = true,
    },
    jump_next_field_end = {
      function()
        for _ = 1, vim.v.count1 do
          require("csvview.jump").next_field_end()
        end
      end,
      desc = "[csvview] Jump to the next end of the field",
      noremap = true,
      silent = true,
    },
    jump_prev_field_end = {
      function()
        for _ = 1, vim.v.count1 do
          require("csvview.jump").prev_field_end()
        end
      end,
      desc = "[csvview] Jump to the previous end of the field",
      noremap = true,
      silent = true,
    },
    jump_next_row = {
      function()
        require("csvview.jump").field(0, { pos = { vim.v.count1, 0 }, anchor = "end" })
      end,
      desc = "[csvview] Jump to the next row",
      noremap = true,
      silent = true,
    },
    jump_prev_row = {
      function()
        require("csvview.jump").field(0, { pos = { -vim.v.count1, 0 }, anchor = "end" })
      end,
      desc = "[csvview] Jump to the previous row",
      noremap = true,
      silent = true,
    },
  },
}
```

</details>

## 🚀 Usage

After opening a CSV file, use the following commands to interact with the plugin:

### Commands

| Command                    | Description                                      |
|----------------------------|--------------------------------------------------|
| `:CsvViewEnable [options]` | Enable CSV view with the specified options.      |
| `:CsvViewDisable`          | Disable CSV view.                                |
| `:CsvViewToggle [options]` | Toggle CSV view with the specified options.      |

### Example

To toggle CSV view, use the following command. By default, the delimiter is `,` for CSV files and `\t` for TSV files.

```vim
:CsvViewToggle
```

To toggle CSV view with a custom field delimiter, a custom string delimiter and comment, use the following command.

```vim
:CsvViewToggle delimiter=, quote_char=' comment=# display_mode=border
```

### Lua API

Below are the core Lua functions that you can call programmatically. If you want to map these functions to key bindings, you can use the `opts.keymaps` option.

#### Basic Functions

- `require('csvview').enable()`: Enable CSV view.
- `require('csvview').disable()`: Disable CSV view.
- `require('csvview').toggle()`: Toggle CSV view.
- `require('csvview').is_enabled()`: Check if CSV view is enabled.

#### Jump Motions

You can move across CSV fields and rows with the following API.

```lua
-- Basic usage:
require("csvview.jump").field(0, {
  pos = { 1, 2 },      -- Move to row=1, column=2
  mode = "absolute",   -- "absolute": interpret `pos` as absolute coords.
                       -- "relative": interpret `pos` as offset from the current field.
  anchor = "start",    -- "start": place the cursor at field start, "end" : field end.
  col_wrap = true,     -- Wrap to the next/previous row when exceeding column bounds.
})
```

Shortcuts for common movements:

```lua
-- Jump to the start of the next field like `w` motion.
require("csvview.jump").next_field_start(bufnr?)
-- Jump to the start of the previous field like `b` motion.
require("csvview.jump").prev_field_start(bufnr?)
-- Jump to the end of the next field like `e` motion.
require("csvview.jump").next_field_end(bufnr?)
-- Jump to the end of the previous field like `ge` motion.
require("csvview.jump").prev_field_end(bufnr?)
```

#### Text Objects

For selecting a CSV field via text objects:

```lua
require("csvview.textobject").field(0, {
  include_delimiter = false -- Include the delimiter in the selection
})
```

#### Cursor Information

Retrieve detailed information about the cursor position:

  ```lua
  local info = require("csvview.util").get_cursor(bufnr)

  -- info returns:
  -- {
  --   kind   = "field" | "comment" | "empty_line",
  --   pos    = { 1, 2 },    -- 1-based [row, col] csv coordinates
  --   anchor = "start" | "end" | "inside" | "delimiter", -- The position of the cursor in the field
  --   text   = "the field content"
  -- }
  ```

## Events

This plugin provides the following events:

| Event            | Description                                                                 |
|------------------|-----------------------------------------------------------------------------|
| CsvViewAttach    | Triggered after the initial metrics calculation is completed and the CsvView is attached. |
| CsvViewDetach    | Triggered after the CsvView is detached.                                    |

### Example

You can hook into these events as follows:

```lua
local group = vim.api.nvim_create_augroup("CsvViewEvents", {})
vim.api.nvim_create_autocmd("User", {
  pattern = "CsvViewAttach",
  group = group,
  callback = function()
    print("CsvView is attached")
  end,
})
```

## 🌈 Highlights

| Group                            | Default                    | Description                      |
| -------------------------------- | -------------------------- | -------------------------------- |
| **CsvViewDelimiter**             | link to `Comment`          | used for `,`                     |
| **CsvViewComment**               | link to `Comment`          | used for comment                 |
| **CsvViewStickyHeaderSeparator** | link to `CsvViewDelimiter` | used for sticky header separator |

> [!NOTE]
> For field highlighting, this plugin utilizes the `csvCol0` ~ `csvCol8` highlight groups that are used by Neovim's built-in CSV syntax highlighting.

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
