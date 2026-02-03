local neorg = require("neorg.core")

local winnr = nil
local bufnr = nil
local ns = vim.api.nvim_create_namespace("neorg-breadcrumbs")

vim.cmd([[highlight default link NeorgContext Visual]])

local module = neorg.modules.create("external.breadcrumbs")

module.setup = function()
  return {
    success = true,
    requires = {
      "core.concealer",
    },
  }
end

module.private = {
  get_contexts = function()
    local highlight_table = {
      ["heading1"] = "@neorg.headings.1.title",
      ["heading2"] = "@neorg.headings.2.title",
      ["heading3"] = "@neorg.headings.3.title",
      ["heading4"] = "@neorg.headings.4.title",
      ["heading5"] = "@neorg.headings.5.title",
      ["heading6"] = "@neorg.headings.6.title",
    }

    local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed
    local topline = vim.fn.line("w0") - 1                    -- 0-indexed

    local ok, parser = pcall(vim.treesitter.get_parser, 0, "norg")
    if not ok or not parser then
      return {}, {}
    end

    local trees = parser:trees()
    if not trees or #trees == 0 then
      return {}, {}
    end

    local root = trees[1]:root()
    local heading_nodes = {}

    local function collect_headings(node)
      for child in node:iter_children() do
        local child_type = child:type()
        local start_row = child:start()
        local end_row = child:end_()
        if start_row <= cursor_row and end_row >= cursor_row then
          if highlight_table[child_type] then
            table.insert(heading_nodes, child)
          end
          collect_headings(child)
        end
      end
    end
    collect_headings(root)

    -- Keep only headings scrolled above the viewport
    local filtered = {}
    for _, heading_node in ipairs(heading_nodes) do
      if heading_node:start() < topline then
        table.insert(filtered, heading_node)
      end
    end
    heading_nodes = filtered

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

    for i = 1, #heading_nodes do
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
        line = line .. " ❯ "
        col = col + 5
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

module.load = function()
  local context_augroup = vim.api.nvim_create_augroup("neorg-breadcrumbs", {})

  vim.api.nvim_create_autocmd({ "WinScrolled", "BufEnter", "WinEnter", "CursorMoved" }, {
    callback = function()
      module.private.update_window()
    end,
    group = context_augroup,
  })
end

return module
