# Changelog

## [1.3.0](https://github.com/hat0uma/csvview.nvim/compare/v1.2.0...v1.3.0) (2025-07-23)


### Features

* Add support for multi-line fields ([#55](https://github.com/hat0uma/csvview.nvim/issues/55)) ([54425e4](https://github.com/hat0uma/csvview.nvim/commit/54425e47c3bc19e43ef71b7ed3e6b589306b8d48))
* **parser:** Add automatic delimiter and header detection ([#62](https://github.com/hat0uma/csvview.nvim/issues/62)) ([bfd95ed](https://github.com/hat0uma/csvview.nvim/commit/bfd95ed77f8f96d07197aeebdb9df058615d994e))


### Bug Fixes

* **config:** Respect user delimiter.ft configuration completely ([#64](https://github.com/hat0uma/csvview.nvim/issues/64)) ([1057e6c](https://github.com/hat0uma/csvview.nvim/commit/1057e6cb883881577f99c6fa3429620fc459ab5c))
* **jump:** Just field: handle case when first col is empty ([#57](https://github.com/hat0uma/csvview.nvim/issues/57)) ([6998bd0](https://github.com/hat0uma/csvview.nvim/commit/6998bd0e821ad1fb2dd199dff6a5cc1bbf71d11f))
* **view:** disable line wrap to prevent cursor jumping in CSV fields ([#66](https://github.com/hat0uma/csvview.nvim/issues/66)) ([22c9450](https://github.com/hat0uma/csvview.nvim/commit/22c9450d19749aa80cc42f0c968cb9dd57726ece))
* **view:** Improve rendering performance ([#44](https://github.com/hat0uma/csvview.nvim/issues/44)) ([9cc5dcb](https://github.com/hat0uma/csvview.nvim/commit/9cc5dcb060c96517d8c34b74e5b81d58529b3ea2))


### Performance Improvements

* **metrics:** Implement row metrics with FFI for improved memory efficiency ([#59](https://github.com/hat0uma/csvview.nvim/issues/59)) ([507f90b](https://github.com/hat0uma/csvview.nvim/commit/507f90b8806ff18940c2d1115fd930cfb9950d93))

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
