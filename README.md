# csvview.nvim

`csvview.nvim` is a lightweight CSV file viewer plugin for Neovim.
With this plugin, you can easily view and edit CSV files within Neovim.

![csvview](https://github.com/hat0uma/csvview.nvim/assets/55551571/27130f41-98f5-445d-a9eb-643b31e0b96b)

## Features

- Displays the CSV file in a tabular format using virtual text.
- Dynamically updates the CSV view as you edit, ensuring a seamless editing experience.
- Asynchronous parsing enables comfortable handling of large CSV files.

**Note:** The plugin is currently a work in progress (WIP) and only implements basic functionality.

## Requirements

Neovim Nightly

## Installation

Install the plugin using your favorite package manager.

### vim-plug

```vim
Plug 'hat0uma/csvview.nvim'
lua require('csvview').setup()
```

### lazy.nvim

```lua
{
  'hat0uma/csvview.nvim',
  config = function()
    require('csvview').setup()
  end
}
```

## Configuration

`csvview.nvim` works with default settings, but you can customize options as follows:

```lua
require('csvview').setup({
  -- Add your configuration here
})
```

The configuration options are as follows:

```lua
{
  parser = {
    --- The number of lines that the asynchronous parser processes per cycle.
    --- This setting is used to prevent monopolization of the main thread when displaying large files.
    --- If the UI freezes, try reducing this value.
    async_chunksize = 50,
  },
  view = {
    --- minimum width of a column
    min_column_width = 5,
    --- spacing between columns
    spacing = 2,
  },
}
```

## Usage

After opening a CSV file, use the following commands to interact with the plugin:

### Commands

- `:CsvViewEnable`: Enable CSV view.
- `:CsvViewDisable`: Disable CSV view.

## Highlights

| Group                | Default            | Description         |
| -------------------- | ------------------ | ------------------- |
| **CsvViewDelimiter** | link to `Comment`  | used for `,`        |

## License

This plugin is released under the MIT License
