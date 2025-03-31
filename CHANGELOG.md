# Changelog

## [1.2.0](https://github.com/hat0uma/csvview.nvim/compare/v1.1.0...v1.2.0) (2025-03-31)


### Features

* **view:** add custom highlight groups ([#42](https://github.com/hat0uma/csvview.nvim/issues/42)) ([5ee3a76](https://github.com/hat0uma/csvview.nvim/commit/5ee3a76c9e7e06545378077223d3ef0871259d0a))
* **view:** Support sticky header ([#39](https://github.com/hat0uma/csvview.nvim/issues/39)) ([7dcb6aa](https://github.com/hat0uma/csvview.nvim/commit/7dcb6aa2965a1d5555d4940ed0c9c2f0e173ecdb))


### Bug Fixes

* add bufnr to `CsvViewAttach`,`CsvViewDetach` ([9bd000f](https://github.com/hat0uma/csvview.nvim/commit/9bd000f338bf020ed4791c95af023c1e14029236))

## [1.1.0](https://github.com/hat0uma/csvview.nvim/compare/v1.0.0...v1.1.0) (2025-03-17)


### Features

* add `display_mode` option to `CsvViewEnable` and `CsvViewToggle` command ([67b6347](https://github.com/hat0uma/csvview.nvim/commit/67b6347090dfc58583c3dd774535a1960ccc19a9))
* **jump:** support repeating for jump motions ([#28](https://github.com/hat0uma/csvview.nvim/issues/28)) ([58ffaea](https://github.com/hat0uma/csvview.nvim/commit/58ffaeab44760dffcbb6d5fde014dbf915209765))
* support fixed-length multi-character delimiters ([#37](https://github.com/hat0uma/csvview.nvim/issues/37)) ([8a07c17](https://github.com/hat0uma/csvview.nvim/commit/8a07c174cef860871eff535569f81bd8a33be53a))


### Bug Fixes

* **#33:** Temporarily disable tabular view during buffer preview with `inccommand=nosplit` ([#34](https://github.com/hat0uma/csvview.nvim/issues/34)) ([ed446a5](https://github.com/hat0uma/csvview.nvim/commit/ed446a55b4ff9297d9b94a955db3a2eca6cdb2b2))
* Resolve Discrepancy Between Neovim's Built-in CSV Highlighting and csvview ([#38](https://github.com/hat0uma/csvview.nvim/issues/38)) ([9e4617b](https://github.com/hat0uma/csvview.nvim/commit/9e4617b2cb8256e8d0e20c7cf87a2c9e48e2addb))
