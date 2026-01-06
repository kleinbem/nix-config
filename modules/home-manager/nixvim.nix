{ inputs, ... }:

{
  imports = [
    inputs.nixvim.homeModules.nixvim
  ];

  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    # Colorscheme
    colorschemes.tokyonight = {
      enable = true;
      settings.style = "night";
    };

    # Basic Settings
    opts = {
      number = true;
      relativenumber = true;
      shiftwidth = 2;
      tabstop = 2;
      expandtab = true;
      smartindent = true;
      wrap = false;
      undofile = true;
      signcolumn = "yes";
      updatetime = 300;
    };

    # Plugins
    plugins = {
      lualine.enable = true;
      bufferline.enable = true;
      web-devicons.enable = true;

      # File Tree
      neo-tree = {
        enable = true;
        settings = {
          close_if_last_window = true;
        };
      };

      # Fuzzy Finder
      telescope = {
        enable = true;
        keymaps = {
          "<leader>ff" = "find_files";
          "<leader>fg" = "live_grep";
          "<leader>fb" = "buffers";
        };
      };

      # Syntax Highlighting
      treesitter = {
        enable = true;
        settings.indent.enable = true;
        settings.highlight.enable = true;
      };

      # Git Integration
      gitsigns.enable = true;

      # LSP
      lsp = {
        enable = true;
        servers = {
          nil_ls.enable = true; # Nix LSP
          bashls.enable = true;
        };
      };

      # Autocomplete
      cmp = {
        enable = true;
        autoEnableSources = true;
        settings.sources = [
          { name = "nvim_lsp"; }
          { name = "path"; }
          { name = "buffer"; }
        ];
        settings.mapping = {
          "<CR>" = "cmp.mapping.confirm({ select = true })";
          "<Tab>" = "cmp.mapping.select_next_item()";
        };
      };
    };

    extraConfigLua = ''
      vim.g.mapleader = " "
    '';
  };
}
