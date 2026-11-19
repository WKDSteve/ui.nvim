-- TESTS/sheets/fixtures/git_repo.lua -- a throwaway git repository for the statusline git sheets
-- (statusline-git-branch.sheet.lua, statusline-idle-git-log.sheet.lua). Not a sheet; a step runs it with `dofile`
-- (the child's cwd is the project root). The git calls made here live below TESTS/, so `testing perf` counts them
-- as the sheet's preparation, not as starts of the plugin.
--
-- Sets `_G.repo` (`dir`, `git(args)`, `commit(subject)`, `branch(name)`) on a fresh directory with `git init`
-- and nothing committed yet: a sheet commits what it needs. Identity and default branch are passed per call, so
-- neither the user's global git config nor a CI runner's matters.

-- luacheck: globals vim

local dir = vim.fs.normalize(vim.fn.tempname())
vim.fn.mkdir(dir, "p")

local function git(args)
  local argv = {
    "git",
    "-C",
    dir,
    "-c",
    "user.name=Sheet",
    "-c",
    "user.email=sheet@example.test",
    "-c",
    "init.defaultBranch=main",
    "-c",
    "commit.gpgsign=false",
    "-c",
    "core.autocrlf=false",
  }
  vim.list_extend(argv, args)
  local res = vim.system(argv, { text = true }):wait(10000)
  if res.code ~= 0 then
    error(("git %s failed: %s"):format(table.concat(args, " "), res.stderr or ""), 0)
  end
  return res.stdout
end

local n = 0

_G.repo = {
  dir = dir,
  git = git,
  --- One more commit touching `file.txt`, with `subject` as its message.
  commit = function(subject)
    n = n + 1
    vim.fn.writefile({ "line " .. n }, dir .. "/file.txt")
    git({ "add", "file.txt" })
    git({ "commit", "-q", "-m", subject })
  end,
  --- A new local branch at HEAD, the current branch stays.
  branch = function(name)
    git({ "branch", name })
  end,
}

git({ "init", "-q" })
