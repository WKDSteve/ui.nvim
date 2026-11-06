---@module 'ui.statusline.modules.learn_plan_viewer_badge'
--- The progress of `:LearnPlanViewer` from the nvim config, e.g. "Woche 3/12 · 5 Checks".
---
--- Renders empty when the viewer was not loaded in this session, and empty again until a week was
--- opened: the config's own `status()` returns "" for that and caches the count of ticked boxes, so
--- this is a thin read rather than a reimplementation.

---@return string
return function()
  -- `package.loaded`, not `require`: this runs on every statusline redraw, and a `require` would pull
  -- the viewer into a session that never asked for it.
  local statusline = package.loaded["bindings.usrcmds.learn_plan_viewer.statusline"]
  if type(statusline) ~= "table" then
    return ""
  end
  return statusline.status() or ""
end
