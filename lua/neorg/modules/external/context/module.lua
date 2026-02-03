local neorg = require("neorg.core")
local ts_utils

if not vim.treesitter.get_node then
  ts_utils = require("nvim-treesitter.ts_utils")
end

local winnr = nil
local bufnr = nil
local ns = vim.api.nvim_create_namespace("neorg-contexts")

vim.cmd([[highlight default link NeorgContext Visual]])

local module = neorg.modules.create("external.context")

module.setup = function()
  return {
    success = true,
    requires = {
      "core.neorgcmd",
      "core.concealer",
    },
  }
end

module.private = {
  enabled = true,

  toggle = function()
    if module.private.enabled == true then
      module.private.enabled = false
    else
      module.private.enabled = true
    end
  end,

  enable = function()
    module.private.enabled = true
  end,

  disable = function()
    module.private.enabled = false
  end,

  get_contexts = function()
    local highlight_table = {
      ["heading1"] = "@neorg.headings.1.title",
      ["heading2"] = "@neorg.headings.2.title",
      ["heading3"] = "@neorg.headings.3.title",
      ["heading4"] = "@neorg.headings.4.title",
      ["heading5"] = "@neorg.headings.5.title",
      ["heading6"] = "@neorg.headings.6.title",
    }

    local node

    -- TODO: remove after 0.10 release
    if not vim.treesitter.get_node then
      node = ts_utils.get_node_at_cursor(0, true)
    else
      node = vim.treesitter.get_node()
    end

    local heading_nodes = {}

    local function is_valid(potential_node)
      local topline = vim.fn.line("w0")
      local row = potential_node:start()
      return row <= (topline + #heading_nodes)
    end

    local function validate_heading_nodes()
      local valid_heading_nodes = heading_nodes
      for i = #heading_nodes, 1, -1 do
        if not is_valid(valid_heading_nodes[i]) then
          table.remove(valid_heading_nodes, i)
        end
      end
      return valid_heading_nodes
    end

    while node do
      if node:type():find("heading") and is_valid(node) then
        table.insert(heading_nodes, node)
      end
      if node:parent() then
        node = node:parent()
      else
        break
      end
    end

    heading_nodes = validate_heading_nodes()

    local function get_title(heading_node)
      local title_node = heading_node:field("title")[1]
      if not title_node then
        return nil
      end
      local text = vim.treesitter.get_node_text
          and vim.treesitter.get_node_text(title_node, 0, {})
        or vim.treesitter.get_node_text(title_node, 0)
      return vim.split(text, "\n")[1]
    end

    local segments = {}
    local highlights = {}

    for i = #heading_nodes, 1, -1 do
      local heading_node = heading_nodes[i]
      local title = get_title(heading_node)
      if title and title ~= "" then
        table.insert(segments, title)
        table.insert(highlights, highlight_table[heading_node:type()])
      end
    end

    if #segments == 0 then
      return {}, {}
    end

    local line = ""
    local spans = {}
    local col = 0

    for i, segment in ipairs(segments) do
      if i > 1 then
        line = line .. " > "
        col = col + 3
      end
      local start_col = col
      line = line .. segment
      col = col + #segment
      if highlights[i] then
        table.insert(spans, {
          hl = highlights[i],
          start_col = start_col,
          end_col = col,
        })
      end
    end

    return { line }, spans
  end,

  set_buf = function()
    local lines, spans = module.private.get_contexts()
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
      bufnr = vim.api.nvim_create_buf(false, true)
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    for _, span in ipairs(spans) do
      vim.api.nvim_buf_add_highlight(bufnr, ns, span.hl, 0, span.start_col, span.end_col)
    end
  end,

  open_win = function()
    module.private.set_buf()
    local col = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff
    local lines = module.private.get_contexts()

    if #lines == 0 then
      if winnr and vim.api.nvim_win_is_valid(winnr) then
        vim.api.nvim_win_close(winnr, true)
        winnr = nil
      end
      return
    end

    if not winnr or not vim.api.nvim_win_is_valid(winnr) then
      winnr = vim.api.nvim_open_win(bufnr, false, {
        relative = "win",
        width = vim.api.nvim_win_get_width(0) - col,
        height = #lines,
        row = 0,
        col = col,
        focusable = false,
        style = "minimal",
        noautocmd = true,
      })
    else
      vim.api.nvim_win_set_config(winnr, {
        win = vim.api.nvim_get_current_win(),
        relative = "win",
        width = vim.api.nvim_win_get_width(0) - col,
        height = #lines,
        row = 0,
        col = col,
      })
    end

    -- TODO: use this after next neovim release
    -- vim.api.nvim_set_option_value("winhl","NormalFloat:NeorgContext",{win=winnr})
    vim.api.nvim_win_set_option(winnr, "winhl", "NormalFloat:NeorgContext")
  end,

  update_window = function()
    if not module.private.enabled then
      if winnr and vim.api.nvim_win_is_valid(winnr) then
        vim.api.nvim_win_close(winnr, true)
        winnr = nil
      end
      return
    end

    if vim.bo.filetype ~= "norg" then
      if winnr and vim.api.nvim_win_is_valid(winnr) then
        vim.api.nvim_win_close(winnr, true)
        winnr = nil
      end
      return
    end

    if string.find(vim.api.nvim_buf_get_name(0), "neorg://") then
      if winnr and vim.api.nvim_win_is_valid(winnr) then
        vim.api.nvim_win_close(winnr, true)
        winnr = nil
      end
      return
    end

    module.private.open_win()
  end,
}

module.config.public = {}
module.public = {}

module.load = function()
  module.required["core.neorgcmd"].add_commands_from_table({
    context = {
      min_args = 1,
      max_args = 1,
      subcommands = {
        toggle = { args = 0, name = "context.toggle" },
        enable = { args = 0, name = "context.enable" },
        disable = { args = 0, name = "context.disable" },
      },
    },
  })

  local context_augroup = vim.api.nvim_create_augroup("neorg-contexts", {})

  vim.api.nvim_create_autocmd({ "WinScrolled", "BufEnter", "WinEnter", "CursorMoved" }, {
    callback = function()
      module.private.update_window()
    end,
    group = context_augroup,
  })
end

module.on_event = function(event)
  if vim.tbl_contains({ "core.keybinds", "core.neorgcmd" }, event.split_type[1]) then
    if event.split_type[2] == "context.toggle" then
      module.private.toggle()
    elseif event.split_type[2] == "context.enable" then
      module.private.enable()
    elseif event.split_type[2] == "context.disable" then
      module.private.disable()
    end
  end
end

module.events.subscribed = {
  ["core.neorgcmd"] = {
    ["context.toggle"] = true,
    ["context.enable"] = true,
    ["context.disable"] = true,
  },
}

return module
