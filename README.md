# kickstart.nvim

## Large files and minified JSON

Opening a `.json` file automatically pretty-prints it with jq when one of its first 20 lines
is at least 2,000 bytes long. This runs before filetype detection, so smaller files get normal
JSON highlighting after expansion. The buffer is marked modified; **`:w` saves the new layout**,
and `u` restores the original layout. Opening a file never writes it to disk.

Snacks uses lightweight `bigfile` mode above 1.5 MiB on disk, or an average line length above
1,000 bytes. This applies to other ordinary files too. It keeps basic syntax highlighting and
disables Tree-sitter, LSP attachment, completion, automatic formatting, indent guides, Git hunk
actions, and the Tree-sitter context window. A large JSON file stays in this mode after expansion.
These protections also survive session restoration. Big-file windows disable soft wrapping so an
unformatted, very long line does not make scrolling expensive.

The formatter requires jq 1.7 or newer and verifies that only whitespace **outside strings**
changed. Duplicate keys, numeric normalization, or changed string escapes cause it to keep the
original. Malformed JSON and failed/timed-out commands also leave the buffer unchanged.
`.jsonl`, `.jsonc`, and `.ipynb` are excluded. Comments inside `.json` are rejected by jq.

Automatic formatting stops at 50 MiB and allows jq up to three seconds. To adjust these limits,
edit the early `require('custom.json_reformat').setup()` call in `init.lua`, for example:

```lua
require('custom.json_reformat').setup {
  min_line_length = 2000,
  sample_lines = 20,
  max_bytes = 50 * 1024 * 1024,
  timeout_ms = 3000,
}
```

For files too large to edit comfortably, `jless file.json` is an optional external viewer;
it is not installed by this configuration. `jq -c .` compacts JSON but does not restore original
bytes, duplicate keys, or previous numeric/string representations.

Regression checks:

```sh
NVIM_LOG_FILE=/tmp/nvim-json-test.log nvim --clean --headless -n -i NONE -l tests/json_reformat.lua
NVIM_LOG_FILE=/tmp/nvim-bigfiles-test.log nvim --headless -n -i NONE -c 'luafile tests/bigfiles.lua'
```

## Jupyter notebooks

Open an existing or new `.ipynb` file normally. Jupytext displays it as Markdown with fenced
code cells and writes notebook JSON when you save. Molten executes the cells, and Quarto/Otter
provide cell selection and language support. Nothing executes just from opening a notebook.

| Shortcut | Action |
| --- | --- |
| `Space j i` | Choose and start a kernel |
| `Space j I` | Import the notebook's saved outputs after starting a kernel |
| `Space j c` | Run the code cell under the cursor |
| `Space j a` / `Space j A` | Run through the current cell / all cells |
| `Space j e` | Run a motion; in visual mode, run the selection |
| `Space j r` | Rerun the current Molten cell |
| `Space j o` / `Space j h` | Enter / hide the output window |
| `Space j w` | Save the notebook and export executed outputs |
| `Space j x` / `Space j q` | Interrupt / stop the buffer's kernel |

Use whole-cell execution when saving notebook outputs. Plain `:w` saves your source and retains
outputs for unchanged cells; `Space j w` also exports the current Molten results. The output
shortcuts require exactly one kernel attached to the notebook. Molten matches outputs by cell
code, so execute all duplicate code cells before exporting results. See its
[output matching rules](https://github.com/benlubas/molten-nvim/blob/v1.9.2/docs/Advanced-Functionality.md#cell-matching).

Neovim's Python host lives in `~/.local/share/nvim/python`, independently of project environments.
To recreate it on another machine:

```sh
uv venv ~/.local/share/nvim/python
uv pip install --python ~/.local/share/nvim/python/bin/python pynvim jupyter-client jupytext nbformat ipykernel
```

Install the plugins with `:Lazy install`, then run `:UpdateRemotePlugins` and restart Neovim.
For a project's packages, register its Python environment as a kernel and select that kernel:

```sh
uv pip install --python .venv/bin/python ipykernel
.venv/bin/python -m ipykernel install --user --name my-project --display-name 'Python (my-project)'
```

The basic `python3` kernel is available for a smoke test. Plots use the existing image.nvim/Kitty
setup; plot libraries belong in the selected kernel's environment. `:checkhealth molten jupytext`
checks dependencies. Git hunk actions and automatic formatting are disabled for converted notebook
buffers. Notebook writes finish synchronously before outputs are exported.

The integration check opens a temporary notebook, imports an output, edits and executes a cell,
saves its result and metadata, reopens the file, and creates a new notebook:

```sh
NVIM_LOG_FILE=/tmp/nvim-notebooks.log nvim --headless -n -i NONE -c 'luafile tests/notebooks.lua'
```

## Reflowing prose

Use `:Reflow` to wrap prose in the current Rust, Markdown, or Python buffer to 98 columns.
Pass a different width with `:Reflow 88`. Select complete paragraphs or comment/docstring blocks
and run `:'<,'>Reflow 88` to limit the operation. A single `u` undoes the command.
Press **Space, Shift+R** to reflow at 98 columns: the whole buffer in normal mode or the
selection in visual mode.

Reflow handles standalone comments, triple-quoted Python docstrings (including Google-style
fields and NumPy-style descriptions), and Markdown paragraphs, lists, and blockquotes.
It preserves Markdown tables, fenced code, indented code, doctest examples, and explicit hard
line breaks. Links, inline code, and `$...$` math stay intact, even when a unit exceeds the
requested width. Code, ordinary string values, and trailing inline comments are left alone.
Docstrings keep their existing opening-quote placement, including when a summary needs wrapping.

Use `<!-- reflow: off -->` / `<!-- reflow: on -->` in Markdown, or the same directives in
Python/Rust line comments, to preserve a region. `fmt: off/on` and Markdown's
`prettier-ignore` directives are also recognized. Ambiguous syntax and paragraph edits that
would introduce Markdown blocks are left unchanged. See [reflow edge cases](doc/reflow.md)
for the handling rules, deliberate limits, and regression checks.

The command uses the configured Tree-sitter parsers and Neovim's native paragraph formatter.
It runs only on request, separately from Conform's code formatting on save. Missing parsers
or Python/Rust syntax errors stop the operation before any edits are applied.

## Introduction

A starting point for Neovim that is:

* Small
* Single-file
* Completely Documented

**NOT** a Neovim distribution, but instead a starting point for your configuration.

## Installation

### Install Neovim

Kickstart.nvim targets *only* the latest
['stable'](https://github.com/neovim/neovim/releases/tag/stable) and latest
['nightly'](https://github.com/neovim/neovim/releases/tag/nightly) of Neovim.
If you are experiencing issues, please make sure you have the latest versions.

### Install External Dependencies

External Requirements:
- Basic utils: `git`, `make`, `unzip`, C Compiler (`gcc`)
- [ripgrep](https://github.com/BurntSushi/ripgrep#installation),
  [fd-find](https://github.com/sharkdp/fd#installation)
- Clipboard tool (xclip/xsel/win32yank or other depending on the platform)
- A [Nerd Font](https://www.nerdfonts.com/): optional, provides various icons
  - if you have it set `vim.g.have_nerd_font` in `init.lua` to true
- Emoji fonts (Ubuntu only, and only if you want emoji!) `sudo apt install fonts-noto-color-emoji`
- Language Setup:
  - If you want to write Typescript, you need `npm`
  - If you want to write Golang, you will need `go`
  - etc.

> [!NOTE]
> See [Install Recipes](#Install-Recipes) for additional Windows and Linux specific notes
> and quick install snippets

### Install Kickstart

> [!NOTE]
> [Backup](#FAQ) your previous configuration (if any exists)

Neovim's configurations are located under the following paths, depending on your OS:

| OS | PATH |
| :- | :--- |
| Linux, MacOS | `$XDG_CONFIG_HOME/nvim`, `~/.config/nvim` |
| Windows (cmd)| `%localappdata%\nvim\` |
| Windows (powershell)| `$env:LOCALAPPDATA\nvim\` |

#### Recommended Step

[Fork](https://docs.github.com/en/get-started/quickstart/fork-a-repo) this repo
so that you have your own copy that you can modify, then install by cloning the
fork to your machine using one of the commands below, depending on your OS.

> [!NOTE]
> Your fork's URL will be something like this:
> `https://github.com/<your_github_username>/kickstart.nvim.git`

You likely want to remove `lazy-lock.json` from your fork's `.gitignore` file
too - it's ignored in the kickstart repo to make maintenance easier, but it's
[recommended to track it in version control](https://lazy.folke.io/usage/lockfile).

#### Clone kickstart.nvim

> [!NOTE]
> If following the recommended step above (i.e., forking the repo), replace
> `nvim-lua` with `<your_github_username>` in the commands below

<details><summary> Linux and Mac </summary>

```sh
git clone https://github.com/nvim-lua/kickstart.nvim.git "${XDG_CONFIG_HOME:-$HOME/.config}"/nvim
```

</details>

<details><summary> Windows </summary>

If you're using `cmd.exe`:

```
git clone https://github.com/nvim-lua/kickstart.nvim.git "%localappdata%\nvim"
```

If you're using `powershell.exe`

```
git clone https://github.com/nvim-lua/kickstart.nvim.git "${env:LOCALAPPDATA}\nvim"
```

</details>

### Post Installation

Start Neovim

```sh
nvim
```

That's it! Lazy will install all the plugins you have. Use `:Lazy` to view
the current plugin status. Hit `q` to close the window.

#### Read The Friendly Documentation

Read through the `init.lua` file in your configuration folder for more
information about extending and exploring Neovim. That also includes
examples of adding popularly requested plugins.

> [!NOTE]
> For more information about a particular plugin check its repository's documentation.


### Getting Started

[The Only Video You Need to Get Started with Neovim](https://youtu.be/m8C0Cq9Uv9o)

### FAQ

* What should I do if I already have a pre-existing Neovim configuration?
  * You should back it up and then delete all associated files.
  * This includes your existing init.lua and the Neovim files in `~/.local`
    which can be deleted with `rm -rf ~/.local/share/nvim/`
* Can I keep my existing configuration in parallel to kickstart?
  * Yes! You can use [NVIM_APPNAME](https://neovim.io/doc/user/starting.html#%24NVIM_APPNAME)`=nvim-NAME`
    to maintain multiple configurations. For example, you can install the kickstart
    configuration in `~/.config/nvim-kickstart` and create an alias:
    ```
    alias nvim-kickstart='NVIM_APPNAME="nvim-kickstart" nvim'
    ```
    When you run Neovim using `nvim-kickstart` alias it will use the alternative
    config directory and the matching local directory
    `~/.local/share/nvim-kickstart`. You can apply this approach to any Neovim
    distribution that you would like to try out.
* What if I want to "uninstall" this configuration:
  * See [lazy.nvim uninstall](https://lazy.folke.io/usage#-uninstalling) information
* Why is the kickstart `init.lua` a single file? Wouldn't it make sense to split it into multiple files?
  * The main purpose of kickstart is to serve as a teaching tool and a reference
    configuration that someone can easily use to `git clone` as a basis for their own.
    As you progress in learning Neovim and Lua, you might consider splitting `init.lua`
    into smaller parts. A fork of kickstart that does this while maintaining the
    same functionality is available here:
    * [kickstart-modular.nvim](https://github.com/dam9000/kickstart-modular.nvim)
  * Discussions on this topic can be found here:
    * [Restructure the configuration](https://github.com/nvim-lua/kickstart.nvim/issues/218)
    * [Reorganize init.lua into a multi-file setup](https://github.com/nvim-lua/kickstart.nvim/pull/473)

### Install Recipes

Below you can find OS specific install instructions for Neovim and dependencies.

After installing all the dependencies continue with the [Install Kickstart](#Install-Kickstart) step.

#### Windows Installation

<details><summary>Windows with Microsoft C++ Build Tools and CMake</summary>
Installation may require installing build tools and updating the run command for `telescope-fzf-native`

See `telescope-fzf-native` documentation for [more details](https://github.com/nvim-telescope/telescope-fzf-native.nvim#installation)

This requires:

- Install CMake and the Microsoft C++ Build Tools on Windows

```lua
{'nvim-telescope/telescope-fzf-native.nvim', build = 'cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release && cmake --install build --prefix build' }
```
</details>
<details><summary>Windows with gcc/make using chocolatey</summary>
Alternatively, one can install gcc and make which don't require changing the config,
the easiest way is to use choco:

1. install [chocolatey](https://chocolatey.org/install)
either follow the instructions on the page or use winget,
run in cmd as **admin**:
```
winget install --accept-source-agreements chocolatey.chocolatey
```

2. install all requirements using choco, exit the previous cmd and
open a new one so that choco path is set, and run in cmd as **admin**:
```
choco install -y neovim git ripgrep wget fd unzip gzip mingw make
```
</details>
<details><summary>WSL (Windows Subsystem for Linux)</summary>

```
wsl --install
wsl
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt install make gcc ripgrep unzip git xclip neovim
```
</details>

#### Linux Install
<details><summary>Ubuntu Install Steps</summary>

```
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt install make gcc ripgrep unzip git xclip neovim
```
</details>
<details><summary>Debian Install Steps</summary>

```
sudo apt update
sudo apt install make gcc ripgrep unzip git xclip curl

# Now we install nvim
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
sudo rm -rf /opt/nvim-linux-x86_64
sudo mkdir -p /opt/nvim-linux-x86_64
sudo chmod a+rX /opt/nvim-linux-x86_64
sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz

# make it available in /usr/local/bin, distro installs to /usr/bin
sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/
```
</details>
<details><summary>Fedora Install Steps</summary>

```
sudo dnf install -y gcc make git ripgrep fd-find unzip neovim
```
</details>

<details><summary>Arch Install Steps</summary>

```
sudo pacman -S --noconfirm --needed gcc make git ripgrep fd unzip neovim
```
</details>
