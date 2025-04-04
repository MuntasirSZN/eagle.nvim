local config = require('eagle.config')
local util = require('eagle.util')
local mouse_handler = require('eagle.mouse_handler')
local keyboard_handler = require('eagle.keyboard_handler')

local M = {}

function M.setup(opts)
  -- a bool variable to detect if the mouse is moving, binded with the <MouseMove> event
  local isMouseMoving = false

  -- a bool variable to make sure process_mouse_pos() is only called once, when the mouse goes idle
  local lock_processing = false

  -- Call the config setup functon to initialize the options
  config.setup(opts)

  if config.options.logging then
    print("eagle.nvim is running")
  end

  -- handle unreasonable values
  if config.options.render_delay < 0 then
    config.options.render_delay = 500
  end

  if config.options.detect_idle_timer < 0 then
    config.options.detect_idle_timer = 50
  end

  if config.options.max_width_factor < 1.1 or config.options.max_width_factor > 5.0 then
    config.options.max_width_factor = 2
  end

  if config.options.max_height_factor < 2.5 or config.options.max_height_factor > 5.0 then
    config.options.max_height_factor = 2.5
  end

  if config.options.mouse_mode then
    local append_keymap = require("eagle.keymap")

    append_keymap("n", "<MouseMove>", function(preceding)
      preceding()

      vim.schedule(function()
        mouse_handler.manage_windows()
        isMouseMoving = true
      end)
    end, { silent = true, expr = true })

    -- in the future, I may need to bind this to CmdlineEnter and/or CmdWinEnter, instead of setting a keymap
    append_keymap({ "n", "v" }, ":", function(preceding)
      preceding()

      if util.eagle_win
          and vim.api.nvim_win_is_valid(util.eagle_win)
          and vim.api.nvim_get_current_win() == util.eagle_win and config.options.close_on_cmd
          and vim.api.nvim_win_get_config(util.eagle_win).focusable then
        vim.api.nvim_win_close(util.eagle_win, false)
        mouse_handler.win_lock = 0
      end
    end, { silent = true })

    -- detect changes in Neovim modes (close the eagle window when leaving normal mode)
    vim.api.nvim_create_autocmd("ModeChanged", {
      callback = function()
        -- when entering normal mode, dont call process_mouse_pos(),
        -- because we should let the user move the mouse again to "unlock" the plugin.
        -- If we do otherwise, then when the user is focusing on typing something, the eagle window will keep popping up
        -- whenever he enters normal mode (assuming the mouse is on code with diagnostics and/or lsp info).
        if vim.fn.mode() ~= "n" then
          mouse_handler.process_mouse_pos()
        end
      end
    })

    -- start the timer that enables mouse control
    -- runs periodically every <config.options.detect_idle_timer> ms
    vim.uv.new_timer():start(0, config.options.detect_idle_timer, vim.schedule_wrap(function()
      -- check if the view is scrolled, when the mouse is idle and the eagle window is not focused
      if not isMouseMoving and vim.api.nvim_get_current_win() ~= util.eagle_win then
        mouse_handler.handle_scroll()
      end

      if isMouseMoving then
        isMouseMoving = false
        lock_processing = false
      else
        if not lock_processing then
          mouse_handler.process_mouse_pos()
          lock_processing = true
        end
      end
    end))
  end

  if config.options.keyboard_mode then
    -- Expose the function so it can be called from a keybinding
    vim.api.nvim_create_user_command('EagleWin', keyboard_handler.render_keyboard_mode, {})
  end

  vim.api.nvim_create_autocmd("CursorMoved", {
    callback = function()
      if util.eagle_win and vim.api.nvim_win_is_valid(util.eagle_win) and vim.api.nvim_get_current_win() ~= util.eagle_win then
        vim.api.nvim_win_close(util.eagle_win, false)
        mouse_handler.win_lock = 0
      end
    end
  })

  -- when the diagnostics of the file change, sort them
  vim.api.nvim_create_autocmd("DiagnosticChanged", { callback = util.sort_buf_diagnostics })
end

-- Toggle headers visibility and close any open eagle window
function M.toggle_headers()
  -- Toggle the show_headers option
  config.options.show_headers = not config.options.show_headers

  -- If eagle window is open and valid, close it
  if util.eagle_win and vim.api.nvim_win_is_valid(util.eagle_win) then
    vim.api.nvim_win_close(util.eagle_win, false)
    -- Reset the win_lock for mouse handler
    mouse_handler.win_lock = 0
  end

  -- Return the new state for convenience
  return config.options.show_headers
end

-- Add a command for easy access
vim.api.nvim_create_user_command('EagleWinToggleHeaders', function()
  local state = M.toggle_headers()
  if config.options.logging then
    vim.notify("Eagle headers " .. (state and "enabled" or "disabled"))
  end
end, {})

return M
