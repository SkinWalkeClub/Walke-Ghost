local M = {}
M._VERSION = "1.0.0"
M._AUTHOR = "Weegee_MLG / Skin Walke Team"

local rawget, rawset, setmt, getmt = rawget, rawset, setmetatable, getmetatable
local sformat, srep = string.format, string.rep
local ins, cat = table.insert, table.concat
local clock = (os and os.clock) or function() return 0 end

local WATCH = {
	getgenv = "env", getrenv = "env", getsenv = "env", getfenv = "env", setfenv = "env",
	getreg = "env", getgc = "env", getinstances = "env", getnilinstances = "env",
	hookfunction = "hook", hookmetamethod = "hook", replaceclosure = "hook",
	hookmetatable = "hook", newcclosure = "hook",
	writefile = "file", appendfile = "file", readfile = "file", makefolder = "file",
	delfile = "file", delfolder = "file", loadfile = "file", dofile = "file", listfiles = "file",
	request = "net", http_request = "net", HttpGet = "net", HttpGetAsync = "net",
	HttpPost = "net", HttpPostAsync = "net",
	setclipboard = "clip", toclipboard = "clip", write_clipboard = "clip",
	loadstring = "load", load = "load",
	getconnections = "signal", firesignal = "signal", getcallbacks = "signal",
	getrawmetatable = "meta", setrawmetatable = "meta", setreadonly = "meta", getnamecallmethod = "meta",
	queue_on_teleport = "persist", queueonteleport = "persist",
	identifyexecutor = "info", getexecutorname = "info", gethwid = "info",
	messagebox = "ui", setfpscap = "misc", saveinstance = "file",
}

local function shorten(v)
	local t = type(v)
	if t == "string" then
		if #v > 80 then return sformat("%q", v:sub(1, 77) .. "...") end
		return sformat("%q", v)
	elseif t == "table" then
		return "{table}"
	elseif t == "function" then
		return "function"
	elseif t == "userdata" or t == "cdata" then
		local ok, s = pcall(tostring, v)
		return ok and s or t
	else
		return tostring(v)
	end
end

local function argstr(n, ...)
	local p = {}
	for i = 1, n do p[i] = shorten((select(i, ...))) end
	return cat(p, ", ")
end

local function newLog()
	return { entries = {}, hits = {}, reads = {}, flags = {} }
end

local function record(log, cat_, name, kind, detail, isCall)
	log.entries[#log.entries + 1] = {
		t = clock(), name = name, cat = cat_, kind = kind, detail = detail or "",
	}
	if isCall then
		log.hits[name] = (log.hits[name] or 0) + 1
		log.hits[cat_] = (log.hits[cat_] or 0) + 1
	else
		log.reads[name] = (log.reads[name] or 0) + 1
	end
end

local NET_FLAG = { "discord", "webhook", "pastebin", "hastebin", "api.telegram", "requestbin", "ngrok", "trello" }

local function gatherText(n, ...)
	local buf = {}
	for i = 1, n do
		local a = select(i, ...)
		local t = type(a)
		if t == "string" then
			buf[#buf + 1] = a
		elseif t == "table" then
			for k, v in pairs(a) do
				if type(k) == "string" then buf[#buf + 1] = k end
				if type(v) == "string" then buf[#buf + 1] = v end
			end
		end
	end
	return cat(buf, " "):lower()
end

local function flagIfSuspicious(log, name, cat_, n, ...)
	local low = gatherText(n, ...)
	if cat_ == "net" then
		local matched
		for _, k in ipairs(NET_FLAG) do
			if low:find(k, 1, true) then matched = k break end
		end
		if matched then
			log.flags[#log.flags + 1] = sformat("network call to %q via %s", matched, name)
		else
			log.flags[#log.flags + 1] = sformat("sends data to the internet via %s", name)
		end
	end
	if cat_ == "file" and (name == "writefile" or name == "appendfile") then
		log.flags[#log.flags + 1] = sformat("writes to a file via %s", name)
	end
	if cat_ == "persist" then
		log.flags[#log.flags + 1] = sformat("queues code to survive teleport via %s", name)
	end
	if name == "getgenv" or name == "getrenv" or name == "getreg" then
		log.flags[#log.flags + 1] = sformat("reaches for the global environment via %s", name)
	end
end

local function wrapValue(name, cat_, val, log, policy)
	if type(val) ~= "function" then
		return val
	end
	return function(...)
		local n = select("#", ...)
		local detail = name .. "(" .. argstr(n, ...) .. ")"
		local mode = policy[name] or policy[cat_] or policy["*"] or "allow"
		record(log, cat_, name, mode, detail, true)
		flagIfSuspicious(log, name, cat_, n, ...)
		if mode == "block" then
			return nil
		end
		return val(...)
	end
end

function M.new(opts)
	opts = opts or {}
	local base = opts.base or (getgenv and getgenv()) or _G
	local policy = opts.policy or {}
	local log = newLog()

	local store = {}
	local cache = {}
	local env

	local function envGet(k)
		if rawget(store, k) ~= nil then return store[k] end
		return base[k]
	end
	local function envSet(k, v)
		rawset(store, k, v)
		record(log, "access", k, "write", "set " .. tostring(k) .. " = " .. shorten(v))
	end

	local safe = {}
	safe.rawget = function(t, k)
		if t == env or t == store then return envGet(k) end
		return rawget(t, k)
	end
	safe.rawset = function(t, k, v)
		if t == env or t == store then envSet(k, v) return t end
		return rawset(t, k, v)
	end
	safe.rawequal = function(a, b) return rawequal(a, b) end
	safe.getfenv = function(lvl)
		if lvl == nil or lvl == 0 or lvl == 1 then return env end
		local ok, e = pcall(getfenv, lvl)
		if ok and (e == base or e == _G) then return env end
		return ok and e or env
	end
	safe.setfenv = function(fn, e) return fn end
	safe.getrawmetatable = function(t)
		if t == env then return nil end
		if getrawmetatable then return getrawmetatable(t) end
		return getmt(t)
	end

	env = setmt({}, {
		__index = function(_, k)
			if k == "_G" or k == "_ENV" then return env end
			if k == "getgenv" or k == "getrenv" or k == "getsenv" then
				record(log, WATCH[k] or "env", k, policy[k] or policy["env"] or policy["*"] or "allow", k .. "()", true)
				flagIfSuspicious(log, k, "env", 0)
				return function() return env end
			end
			local s = safe[k]
			if s ~= nil then return s end
			local c = cache[k]
			if c ~= nil then return c end
			if rawget(store, k) ~= nil then return store[k] end
			local real = base[k]
			local w = WATCH[k]
			if w then
				local wrapped = wrapValue(k, w, real, log, policy)
				cache[k] = wrapped
				record(log, "access", k, "read", "read " .. k)
				return wrapped
			end
			return real
		end,
		__newindex = function(_, k, v)
			envSet(k, v)
		end,
		__metatable = false,
	})

	local api = {}
	api.env = env
	api.log = log
	api.store = store

	function api.run(src, chunkname, ...)
		if type(src) == "function" then
			local fn = src
			if setfenv then pcall(setfenv, fn, env) end
			return pcall(fn, ...)
		end
		local loader = (opts.loadstring) or loadstring or load
		if not loader then return false, "no loadstring available" end
		local fn, err = loader(src, chunkname or "=walkeghost")
		if not fn then return false, err end
		if setfenv then
			pcall(setfenv, fn, env)
		else
			local ok, e = pcall(function()
				local f2 = load(src, chunkname or "=walkeghost", "t", env)
				if f2 then fn = f2 end
			end)
			if not ok then return false, e end
		end
		return pcall(fn, ...)
	end

	function api.report()
		local out = {}
		out[#out + 1] = "== Walke Ghost =="
		local total = #log.entries
		out[#out + 1] = sformat("watched actions: %d", total)
		out[#out + 1] = ""

		local order = {}
		for _, e in ipairs(log.entries) do
			if e.cat ~= "access" then
				local key = e.name
				if not order[key] then
					order[key] = { cat = e.cat, kind = e.kind, count = 0, sample = e.detail }
					order[#order + 1] = key
				end
				order[key].count = order[key].count + 1
			end
		end

		if #order == 0 then
			out[#out + 1] = "no sensitive functions were used."
		else
			out[#out + 1] = "sensitive functions used:"
			for _, key in ipairs(order) do
				local e = order[key]
				out[#out + 1] = sformat("  [%s] %s x%d  %s", e.kind, key, e.count, e.sample)
			end
		end

		if #log.flags > 0 then
			out[#out + 1] = ""
			out[#out + 1] = "warnings:"
			local seen = {}
			for _, f in ipairs(log.flags) do
				if not seen[f] then
					seen[f] = true
					out[#out + 1] = "  ! " .. f
				end
			end
		end
		return cat(out, "\n"), log
	end

	return api
end

function M.scan(src, opts)
	opts = opts or {}
	local pol = opts.policy or { ["*"] = "block" }
	local g = M.new({ base = opts.base, policy = pol, loadstring = opts.loadstring })
	local ok, err = g.run(src, opts.chunkname)
	local text, log = g.report()
	return {
		ok = ok,
		err = (not ok) and err or nil,
		flags = log.flags,
		report = text,
		log = log,
	}
end

function M.watch(src, opts)
	opts = opts or {}
	local pol = opts.policy or { ["*"] = "allow" }
	local g = M.new({ base = opts.base, policy = pol, loadstring = opts.loadstring })
	local ok, err = g.run(src, opts.chunkname)
	local text, log = g.report()
	return { ok = ok, err = (not ok) and err or nil, report = text, log = log }, g
end

return M
