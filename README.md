# Walke Ghost

A sandbox for running scripts you do not trust.

You paste a "free aimbot" or some random script from a Discord server and hit execute. If that script quietly steals your data or drops a backdoor, you never find out until it is too late. Walke Ghost runs the script inside a fake isolated environment first. The script thinks it has full access but it cannot actually touch anything real, and Ghost writes down every dangerous thing it tried to do. You read the report, and then you decide if it is safe to run for real.

Think of it as opening a suspicious file inside a virtual machine instead of on your main PC.

## What it actually does

- **Isolation.** The script gets its own environment. When it writes a global or changes `getgenv()`, that change stays inside the sandbox. Your real environment and your other scripts are untouched.
- **Monitoring.** Every time the script calls something sensitive (writing a file, sending a web request, hooking a function, reaching for the global environment) Ghost logs it with the arguments it used.
- **Control.** You choose a policy. `allow` runs the call and logs it. `log` is the same as allow. `block` stops the call from ever reaching the real function and just records the attempt.
- **Warnings.** Ghost knows the common red flags. A web request to a Discord webhook or Pastebin, a file write, code queued to survive a teleport. These show up in a warnings list so you do not have to read the whole log.

## What it does NOT do

Read this part so you are not surprised.

- **It is not an anti-cheat bypass and it does not make you invisible to games.** This protects YOU from a malicious script. It does nothing to hide you from a game's detection. That is a different problem and honestly nobody can promise to solve it.
- **It reads globals through to the real ones so normal code works.** `print`, `math`, `game`, `workspace` and so on all work normally. Isolation is about WRITES and about the sensitive functions, not about blinding the script to everything.
- **A determined script can still waste your time or spam.** Ghost stops it from writing, sending, and hooking when you block those. It does not stop an infinite loop. If you want a script to do literally nothing harmful, run it in `scan` mode which blocks everything by default.

## Load it

```lua
local Ghost = loadstring(game:HttpGet("https://raw.githubusercontent.com/SkinWalkeClub/Walke-Ghost/main/walkeghost.lua"))()
```

## Check a script before you trust it

`scan` blocks everything by default and gives you back a report. Nothing the script does actually happens. This is the safe way to inspect something new.

```lua
local result = Ghost.scan(sketchySource)
print(result.report)
if #result.flags > 0 then
    warn("do not run this")
end
```

For the script in `example.lua` (a fake aimbot that saves your UserId and sends it to a Discord webhook) the report looks like this:

```
== Walke Ghost ==
watched actions: 4

sensitive functions used:
  [block] writefile x1  writefile("aimbot_cache.txt", "12345")
  [block] request x1  request({table})

warnings:
  ! writes to a file via writefile
  ! network call to "discord" via request
```

Notice it caught the Discord webhook even though the URL was hidden inside a table argument. That is the whole point.

## Run a script for real but watched

If you want the script to actually work but you still want a log, use `watch`. By default it allows everything and just records it. You can tighten specific categories.

```lua
local sandbox, ghost = Ghost.watch(source, {
    policy = { net = "block", file = "log" }
})
print(sandbox.report)
```

That runs the script, lets it write files but logs them, and blocks any web request outright.

## Policy

A policy is a table. Keys can be a single function name, a whole category, or `"*"` for everything. Values are `"allow"`, `"log"`, or `"block"`.

```lua
Ghost.new({
    policy = {
        request = "block",      -- block this exact function
        file = "log",           -- log the whole file category, let it run
        ["*"] = "allow",        -- everything else runs
    }
})
```

The categories are `env`, `hook`, `file`, `net`, `clip`, `load`, `signal`, `meta`, `persist`, `info`, `ui`, `misc`.

## Full API

```lua
Ghost.scan(src, opts)   -- blocks everything, returns { ok, err, flags, report, log }
Ghost.watch(src, opts)  -- allows everything, returns (result, ghost)
Ghost.new(opts)         -- build a sandbox yourself, returns a ghost object
```

A ghost object has:

```lua
ghost.run(src, chunkname, ...)  -- run source or a function inside the sandbox, returns pcall results
ghost.report()                  -- returns (reportText, log)
ghost.env                       -- the sandbox environment table
ghost.store                     -- everything the script wrote, kept here instead of the real globals
ghost.log                       -- { entries, hits, reads, flags }
```

`opts` fields: `base` (the real environment to read through, defaults to `getgenv()` or `_G`), `policy`, `loadstring` (override the loader), `chunkname`.

## Notes

- The warning scanner looks at string arguments and one level inside table arguments. A URL passed directly or inside a request table is caught. A URL buried three tables deep is logged as a network call but the specific site name might not be flagged.
- On executors without `setfenv`, Ghost loads the chunk with a custom environment instead. Both paths give the same isolation.
- Reading a global is logged separately from calling it, so `ghost.log.reads` and `ghost.log.hits` are kept apart. The report counts calls, not reads.

## License

MIT. Weegee_MLG / The Skin Walke Team.
