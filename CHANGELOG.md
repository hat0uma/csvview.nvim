# Changelog

## 1.0.0 (2025-02-17)


### ⚠ BREAKING CHANGES

* change command line options to key=value format

### Features

* Add `CsvViewToggle` command ([003ba89](https://github.com/hat0uma/csvview.nvim/commit/003ba892b2cbafb8aa479e9f14a5a9af2f539662))
* add `get_cursor` function to retrieve cursor information ([e46d72e](https://github.com/hat0uma/csvview.nvim/commit/e46d72e1953bc25afe5eb698f792c9da5e22e28d))
* add buffer update test cases ([b239c70](https://github.com/hat0uma/csvview.nvim/commit/b239c707937b115aace6038ff3a128d2dcd842ff))
* add customizable delimiter for CSV/TSV files ([2741dfd](https://github.com/hat0uma/csvview.nvim/commit/2741dfdd21b184bbd632f1a78cb2fb487237410a))
* add delimiter option to CsvView commands ([3fa3684](https://github.com/hat0uma/csvview.nvim/commit/3fa36845b8555c4d1032878dfd73b3340cf51eeb))
* add motion and textobject modules for csvview ([b101e18](https://github.com/hat0uma/csvview.nvim/commit/b101e18a92ecb3132acc8462b3f14725468bd78d))
* add row and column validation methods ([e8ebd73](https://github.com/hat0uma/csvview.nvim/commit/e8ebd73711e3ab1b98430948af2ccc4a990b6c09))
* add support for comment lines in CSV view ([9e1dcff](https://github.com/hat0uma/csvview.nvim/commit/9e1dcff494e91c5fad930bf76a0064a404cbb1f4))
* add support for custom delimiters in parser ([a3fde6e](https://github.com/hat0uma/csvview.nvim/commit/a3fde6e7cc9af6aa88b9bc07852eaa2fae57f493))
* Add support for customizable configuration options. ([58a02c1](https://github.com/hat0uma/csvview.nvim/commit/58a02c17ac97fa81aff5a7ccc0b586e3b3f8162b))
* add test fixtures for CsvView ([57e37dc](https://github.com/hat0uma/csvview.nvim/commit/57e37dc2fdb7fc67a6b781c4907846e962e487b2))
* add tests for `csvview.util` module ([6e9482f](https://github.com/hat0uma/csvview.nvim/commit/6e9482f01b2b35b36fb8a8635c2a779d7e6d5ac5))
* Add TODO section to README([#17](https://github.com/hat0uma/csvview.nvim/issues/17)) ([3c29a47](https://github.com/hat0uma/csvview.nvim/commit/3c29a4703e783370b7657cd0d943e301de8653ad))
* change command line options to key=value format ([d6ca48d](https://github.com/hat0uma/csvview.nvim/commit/d6ca48d8b3c2bdf784ad8d88bfbe1556c8437f10))
* **ci:** add style and linting to CI workflow ([36c3e26](https://github.com/hat0uma/csvview.nvim/commit/36c3e26ff10b58cd89bb4aa9e8ffb4a7c96cdaca))
* **csvview:** add event hooks for attach/detach ([092fada](https://github.com/hat0uma/csvview.nvim/commit/092fada3e43b61fe7573bf439e1bc92f1e304f2b))
* **csvview:** add keymaps and actions support ([85e137a](https://github.com/hat0uma/csvview.nvim/commit/85e137aac985234935d842977ab8d33385afe539))
* **metrics:** optimize calculation for larger buffer ([fdd1187](https://github.com/hat0uma/csvview.nvim/commit/fdd118711cbea339b9b117540e20f0aa2a8d1566))
* **parser:** Add support for parsing quoted fields. ([950a3fe](https://github.com/hat0uma/csvview.nvim/commit/950a3fefcd118328f3e3752390e1302276d1b9da))
* Support bufnr=0 for csvview API ([#26](https://github.com/hat0uma/csvview.nvim/issues/26)) ([afc4863](https://github.com/hat0uma/csvview.nvim/commit/afc4863c6d81ae6a839aab9c552c80dc39845098))
* update README with example commands for CSV view ([e729d2b](https://github.com/hat0uma/csvview.nvim/commit/e729d2b6633eb77e4d6b838ea9ee284a4022f5b4))
* **view:** Added a `display_mode = "border"` option for table-like display ([572c5cf](https://github.com/hat0uma/csvview.nvim/commit/572c5cf80de7533a1a548e203d9d923ecc9af346))


### Bug Fixes

* **#23:** improve buffer detach handling ([#24](https://github.com/hat0uma/csvview.nvim/issues/24)) ([9f9aa7e](https://github.com/hat0uma/csvview.nvim/commit/9f9aa7e7a9f977de9cf056b2d1878edd5474be7e))
* **ci:** auto-fix style only on push to main ([da6d9f1](https://github.com/hat0uma/csvview.nvim/commit/da6d9f159165154070ea7d6229e9855b6aa0c747))
* correct class references and comments ([0c225f6](https://github.com/hat0uma/csvview.nvim/commit/0c225f60052fac45db54f6776fbb8ff1bdee7fa7))
* correct command example in README for toggling CSV view ([dc1f458](https://github.com/hat0uma/csvview.nvim/commit/dc1f4584a34cfabe484b27557aee8c6a29214ff4))
* correct command syntax in README.md ([f68cb79](https://github.com/hat0uma/csvview.nvim/commit/f68cb7950c811f2b2b6b19818812f3b4c5624f03))
* Correct display issues when adding or removing lines ([eab34fa](https://github.com/hat0uma/csvview.nvim/commit/eab34fad5a5b27488b41296cdf5d320fca228f23))
* correct row placeholder insertion logic ([2855886](https://github.com/hat0uma/csvview.nvim/commit/2855886ab610fa177eb0bb0a8408a2056cd6a335))
* Fix duplicate BufReadPost event. ([5dacda7](https://github.com/hat0uma/csvview.nvim/commit/5dacda7c738ed22a0c40b3bb0a93582d6e1f21ca))
* **motion:** field jump behavior ([b36f251](https://github.com/hat0uma/csvview.nvim/commit/b36f251c09631117243778b5d1cc5815ab575da2))
* **parser:** Add message for long parsing. ([7c4734c](https://github.com/hat0uma/csvview.nvim/commit/7c4734c51fc1d1c53bf0bc8dfe52b46074b041c0))
* **parser:** Fix parsing the same line twice when async parsing ([33d1c44](https://github.com/hat0uma/csvview.nvim/commit/33d1c44ae997416f2d52ce057806134a02d34e45))
* resolve `nvim_buf_attach` detachment issue ([9c4bfb7](https://github.com/hat0uma/csvview.nvim/commit/9c4bfb791b2c9c5582d729d7613dd8a9444cc5f5))
* update end_col function to handle window changes ([6ef2094](https://github.com/hat0uma/csvview.nvim/commit/6ef20944bc428e78ab434fecf3357c149053d912))
* **view:** redraw when updated. ([6d6b203](https://github.com/hat0uma/csvview.nvim/commit/6d6b2033a99b81681919fab2a1c2fc8ec265f659))


### Performance Improvements

* Improve performance when parsing large buffer. ([d71af4d](https://github.com/hat0uma/csvview.nvim/commit/d71af4dc20c7f4d91ac3c9c82404046c2abeb306))
* improve row handling efficiency ([accda47](https://github.com/hat0uma/csvview.nvim/commit/accda47a7109a75ac2b46f8760a0615b3ee84733))
