# Feature Guide

A guide to features and configuration options.

## Table of Contents

- [Display Configuration](#display-configuration)
- [Delimiter Configuration & Auto-Detection](#delimiter-configuration--auto-detection)
- [Header Configuration & Sticky Headers](#header-configuration--sticky-headers)
- [Navigation & Text Objects](#navigation--text-objects)
- [Quote Character Configuration](#quote-character-configuration)
- [Multi-line Field Configuration](#multi-line-field-configuration)
- [Comment Line Handling](#comment-line-handling)
- [Buffer Statistics](#buffer-statistics)
- [API Reference](#api-reference)

## Display Configuration

### Display Modes

csvview.nvim supports two display modes for better visualization of your CSV data.

#### Highlight Mode (Default)

Highlights delimiter characters in place, maintaining the original file structure:

```lua
{
  view = {
    display_mode = "highlight",
  },
}
```

#### Border Mode

Replaces delimiters with vertical borders (`│`) for a cleaner table appearance:

```lua
{
  view = {
    display_mode = "border",
  },
}
```

### Toggle Display Modes

Switch between display modes on the fly:

```vim
:CsvViewEnable display_mode=highlight
:CsvViewEnable display_mode=border
```

### Column Layout Configuration

Customize the appearance of your table columns:

```lua
{
  view = {
    min_column_width = 5,  -- Minimum width for each column
    spacing = 2,           -- Space between columns
  },
}
```

## Delimiter Configuration & Auto-Detection

csvview.nvim provides intelligent delimiter detection and flexible configuration options.

### Auto-Detection (Recommended)

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

#### How Auto-Detection Works

1. If the file type matches `ft` rules (e.g., `.csv` → comma), use that delimiter
2. Otherwise, test each delimiter in `fallbacks` order
3. Score each delimiter based on field consistency across lines
4. Select the delimiter with the highest score

### Manual Delimiter Configuration

#### Fixed Delimiter for All Files

```lua
{
  parser = {
    delimiter = ",",  -- Always use comma
  },
}
```

#### Dynamic Delimiter with Function

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

### Command-line Delimiter Options

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

**Note**: Multi-character delimiters are supported (e.g., `||`, `::`, `<>`), but regular expression patterns are not supported (e.g., `\s+`).

## Header Configuration & Sticky Headers

Keep header rows visible while scrolling through large CSV files with intelligent header detection.

### Header Auto-Detection (Recommended)

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

#### How Header Auto-Detection Works

1. Find the first non-comment line as header candidate
2. Analyze each column independently using two heuristics:
   - **Type Mismatch**: If the first row contains text while data rows are numeric, it's likely a header
   - **Length Deviation**: If the first row's text length differs significantly from data rows, it's likely a header
3. Combine evidence from all columns to make the final decision

### Manual Header Configuration

#### Fixed Header Line

```lua
{
  view = {
    header_lnum = 1,  -- Use line 1 as header
    -- header_lnum = 3,  -- Use line 3 as header
  },
}
```

#### Disable Header

```lua
{
  view = {
    header_lnum = false,  -- No header line
  },
}
```

### Command-line Header Options

```vim
:CsvViewEnable header_lnum=auto  " Auto-detect header (default)
:CsvViewEnable header_lnum=1     " First line as header
:CsvViewEnable header_lnum=none  " No header line
```

### Customize Separator

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

## Navigation & Text Objects

### Excel-like Navigation

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

### Text Objects for Field Selection

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

#### Usage Examples

- `vif` - Select current field content
- `vaf` - Select current field including delimiter
- `dif` - Delete field content
- `caf` - Change entire field

### Custom Navigation

```lua
-- Jump to specific field position
require("csvview.jump").field(0, {
  pos = { 2, 3 },      -- Row 2, Column 3
  mode = "absolute",
  anchor = "start",    -- Place cursor at field start
})
```

## Quote Character Configuration

Handle quoted fields that contain delimiters or special characters.

### Basic Quote Configuration

```lua
{
  parser = {
    quote_char = '"',   -- Standard double quotes (default)
    -- quote_char = "'", -- Single quotes
  },
}
```

### How Quoted Fields Work

When a field is enclosed in quote characters, the delimiter inside is ignored:

```csv
name,description,value
John,"Smith, Jr.",100
Jane,"O'Connor ""Jane""",200
```

In this example:

- `"Smith, Jr."` contains a comma but is treated as one field
- `"O'Connor ""Jane"""` contains escaped quotes within the field

### Command-line Usage

```vim
" Use double quotes (default)
:CsvViewEnable quote_char="

" Use single quotes
:CsvViewEnable quote_char='

" Disable quote handling (not recommended)
:CsvViewEnable quote_char=
```

## Multi-line Field Configuration

Handle CSV fields that span multiple lines when properly quoted.

### Basic Configuration

```lua
{
  parser = {
    max_lookahead = 50,  -- Maximum lines to search for closing quotes
  },
}
```

### How Multi-line Fields Work

When a field starts with a quote character but doesn't end on the same line, the parser will search ahead for the closing quote:

```csv
id,description,notes
1,"This field contains
multiple lines of text
with embedded newlines",Short note
2,"Another multi-line field
that spans several lines",Another note
```

### Performance Tuning

Adjust `max_lookahead` based on your data:

- Increase for files with long multi-line fields (e.g., `max_lookahead = 200`)
- Decrease for simple CSV files to improve performance (e.g., `max_lookahead = 10`)

## Comment Line Handling

Skip comment lines from the table display to focus on data rows.

### Basic Comment Configuration

```lua
{
  parser = {
    comments = { "#", "//", "--" },  -- Lines starting with these are ignored
  },
}
```

### Comment Examples

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

### Fixed Header Comment Lines

For files with a fixed number of metadata lines at the top, use `comment_lines`:

```lua
{
  parser = {
    comment_lines = 2,  -- First 2 lines are always treated as comments
  },
}
```

This is useful for files like:

```csv
Generated: 2024-01-15
Source: database_export
name,age,city
John,25,NYC
Jane,30,LA
```

The first 2 lines will be treated as comments regardless of their content.

### Command-line Usage

```vim
" Enable hash comments
:CsvViewEnable comment=#

" Enable C++ style comments
:CsvViewEnable comment=//

" Enable SQL style comments
:CsvViewEnable comment=--

" Treat first N lines as comments
:CsvViewEnable comment_lines=2

" Multiple comment types (requires Lua configuration)
```

## Buffer Statistics

Display detailed information about the current CSV buffer using the `:CsvViewInfo` command.

### Basic Usage

```vim
" Show buffer statistics
:CsvViewInfo

" Show with debug information
:CsvViewInfo!
```

### Closing the Info Window

Press `q` or `<Esc>` to close the info window.

## API Reference

### Core Functions

```lua
local csvview = require('csvview')

-- Buffer management
csvview.enable(bufnr?, opts?)    -- Enable for specific buffer
csvview.disable(bufnr?)          -- Disable for specific buffer
csvview.toggle(bufnr?, opts?)    -- Toggle with options
csvview.is_enabled(bufnr?)       -- Check status

-- Buffer information
csvview.info(bufnr?, show_debug?) -- Show buffer statistics
```

### Jump API

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

### Text Object API

```lua
local textobj = require("csvview.textobject")

-- Select current field
textobj.field(bufnr, {
  include_delimiter = false,    -- Include surrounding delimiter
})
```

### Utility Functions

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
