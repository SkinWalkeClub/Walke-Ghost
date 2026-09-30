<p align="center">
  <img src="https://media.discordapp.net/attachments/1554722448589594754/1554730183251075182/content.png?backend=b2&ex=6abdf2d1&is=6abca151&hm=fe81aad7d5e2cd528e6b4d568ad482f3bc0c5ac0d8cf6d763b0fd7ff92c236bf&=&format=webp&quality=lossless&width=640&height=640" width="600" alt="Walke Serializer">
</p>

# Walke Ghost

A sandbox for running scripts you do not trust.

You paste a "free aimbot" or some random script from a Discord server and hit execute. If that script quietly steals your data or drops a backdoor, you never find out until it is too late. Walke Ghost runs the script inside a fake isolated environment first. The script thinks it has full access but it cannot actually touch anything real, and Ghost writes down every dangerous thing it tried to do. You read the report, and then you decide if it is safe to run for real.

Think of it as opening a suspicious file inside a virtual machine instead of on your main PC.

## What it actually does

- **Isolation of writes.** When the script sets a global or changes `getgenv()`, that change is trapped inside the sandbox. Your real environment and your other scripts stay untouched. Even `_G`, `getrenv()`, `rawset`, and `getfenv` are redirected so the script cannot reach around the sandbox to write to the real globals.
- **Monitoring.** Every time the script calls something sensitive (writing a file, sending a web request, hooking a function, reaching for the global environment) Ghost logs it with the arguments it used.
- **Control.** You choose a policy. `allow` runs the call and logs it. `log` is the same as allow. `block` stops the call from ever reaching the real function and just records the attempt.
- **Red flags and notices, kept apart.** Ghost splits what it sees into two lists. A red flag is something that is usually bad, like sending data to a Discord webhook or hooking a function. A notice is something common and often harmless on its own, like writing a file or reading the global environment. This way the report does not cry wolf.

## Two isolation modes

**Read-through (default).** Unknown globals fall through to the real environment, so the script can see `game`, `workspace`, `task`, and the executor functions. This is what you want when you actually want the script to run and be watched, because a script that cannot see anything cannot do anything worth watching. Writes are still trapped, and sensitive calls are still logged and controllable.

**Sealed (`sealed = true`).** The script only gets a whitelist of safe standard functions (`print`, `math`, `string`, `table`, `task`, and so on) plus the sensitive functions Ghost watches. Custom globals from the real environment are hidden. Use this when you want the tightest box and you do not care whether the script runs correctly, only what it tries to do. You can hand it specific globals with `expose`.

```lua
Ghost.scan(src, { sealed = true })
Ghost.scan(src, { sealed = true, expose = { MyGlobal = true } })
```

Heads up: `game`, `workspace`, and similar are not on the whitelist, so a script that touches them will error early under sealed mode unless you expose them. That is the point of sealed mode, but if you want the script to actually reach its network or file calls so you can see them, either expose what it needs (`expose = { game = true }`) or use read-through mode.

Being honest about the limit: read-through mode inherits whatever is in the real environment by design. If you need a genuinely closed box, use `sealed`. If you need the script to behave normally so you can watch it, use read-through and rely on the write-trapping and the call log, not on hiding the world from it.

## What it does NOT do

- **A red flag is a signal, not proof.** "sends data to discord" means the script called a network function with a Discord URL in the arguments. That is worth stopping. But a notice like "uses a network function" only means the API was used, not that anything was actually stolen. Read the report, do not just trust a green light.
- **It does not stop an infinite loop or a crash.** It stops writes, web calls, and hooks when you block them. It does not police CPU. For maximum safety on something totally unknown, use `scan`, which blocks everything by default.

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

For a fake aimbot that grabs your UserId, saves it, sends it to a Discord webhook, and silences `print`, the report looks like this:

```
== Walke Ghost ==
environment: read-through
watched actions: 6

sensitive functions used:
  [block] writefile x1  writefile("aimbot_cache.txt", "12345")
  [block] request x1  request({table})
  [block] hookfunction x1  hookfunction(function, function)

red flags:
  ! sends data to "discord" via request
  ! replaces or hooks a function via hookfunction. check what it is hooking

notices:
  - writes to the filesystem via writefile
```

The report states the environment mode on the second line, so if you save a scan result and read it later you know whether it was run read-through or sealed. It caught the Discord webhook even though the URL was hidden inside a table argument. That is the whole point.

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
Ghost.scan(src, opts)   -- blocks everything, returns { ok, err, flags, notices, report, log }
Ghost.watch(src, opts)  -- allows everything, returns (result, ghost)
Ghost.new(opts)         -- build a sandbox yourself, returns a ghost object
```

A ghost object has:

```lua
ghost.run(src, chunkname, ...)  -- run source (string) or a function inside the sandbox
ghost.report()                  -- returns (reportText, log)
ghost.env                       -- the sandbox environment table
ghost.store                     -- everything the script wrote, kept here instead of the real globals
ghost.log                       -- { entries, hits, reads, flags, notices }
```

`opts` fields: `base` (the real environment to read through, defaults to `getgenv()` or `_G`), `policy`, `sealed`, `expose`, `loadstring` (override the loader), `chunkname`.

## Notes on how it loads code

- Ghost prefers the modern `load(src, name, "t", env)` form, which applies the sandbox environment directly. If that is not available it falls back to `loadstring` plus `setfenv`. If neither can apply the environment it returns a clear error instead of running the code unsandboxed. It never runs your untrusted code outside the sandbox as a "fallback".
- Passing a **function value** to `run` needs `setfenv`, because you cannot rebind an already-created function's environment without it. Real executors have `setfenv`, so this works there. If you are on a runtime without it, pass the code as a string instead and Ghost will load it into the sandbox properly.
- Inside the sandbox, `setfenv` and `getfenv` are handled so a script cannot use them to escape. `getfenv` gives back the sandbox environment, and `setfenv` cannot rebind anything to the real globals.

## Notes on detection

- The red-flag scanner looks at string arguments and one level inside table arguments. A URL passed directly or inside a request table is caught. A URL buried several tables deep is still logged as a network call, but the specific site might land in notices instead of red flags.
- Known-bad hosts checked by name include Discord, Pastebin, Hastebin, Telegram, ngrok, and a few others. You can add more by editing the `NET_FLAG` list in the file.

## License

MIT. Weegee_MLG / The Skin Walke Team.
