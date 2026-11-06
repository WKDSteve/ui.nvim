-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.learn_plan_viewer_badge` -- a thin read of the nvim config's
--- `bindings.usrcmds.learn_plan_viewer.statusline.status()`. The wording and the caching are tested
--- in the config; this holds the adapter contract, the same shape as `recommender_badge_spec`.

local MODULE = "bindings.usrcmds.learn_plan_viewer.statusline"
local badge = require("ui.statusline.modules.learn_plan_viewer_badge")

describe("ui.statusline.modules.learn_plan_viewer_badge", function()
  after_each(function()
    package.loaded[MODULE] = nil
  end)

  it("renders empty when the viewer was not loaded, and does not load it", function()
    package.loaded[MODULE] = nil
    assert.equals("", badge())
    assert.is_nil(package.loaded[MODULE])
  end)

  it("renders empty until a week was opened", function()
    package.loaded[MODULE] = {
      status = function()
        return ""
      end,
    }
    assert.equals("", badge())
  end)

  it("passes the viewer's own text through unchanged", function()
    package.loaded[MODULE] = {
      status = function()
        return "Woche 3/12 · 5 Checks"
      end,
    }
    assert.equals("Woche 3/12 · 5 Checks", badge())
  end)

  it("renders empty when the viewer returns nothing", function()
    package.loaded[MODULE] = {
      status = function()
        return nil
      end,
    }
    assert.equals("", badge())
  end)

  it("is in the statusline catalog", function()
    local source
    for _, entry in ipairs(require("ui.statusline.catalog")) do
      if entry.key == "learn_plan_viewer_badge" then
        source = entry.source
      end
    end
    assert.equals("ui.statusline.modules.learn_plan_viewer_badge", source)
  end)
end)
