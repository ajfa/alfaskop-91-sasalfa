-- after SAS2.1 is up: press every key (alone, with Shift, with Alt) and log the key message D4GSAS gets at $0260-$0264
local m = manager.machine
local dmem = m.devices[":ducpu"].spaces["program"]
local function key(n)
	local port = m.ioport.ports[":du_kbd:P1" .. (n // 16)]
	if not port then return nil end
	for _, f in pairs(port.fields) do
		if f.mask == (1 << (n % 16)) then return f, f.name end
	end
end
local mods = {}
for k in (os.getenv("MODS") or "0 32 108"):gmatch("%d+") do mods[#mods + 1] = tonumber(k) end
local skip = { [32] = true, [108] = true }
local tests = {}
for _, mod in ipairs(mods) do
	for k = 0, 127 do
		if not skip[k] and key(k) then tests[#tests + 1] = { mod, k } end
	end
end
local out = io.open("keycodes.txt", "w")
local cur, msg = nil, {}
TW = dmem:install_write_tap(0x0260, 0x0264, "msg", function(o, d)
	if cur then msg[#msg + 1] = string.format("%X=%02X", o & 0xf, d) end
end)
local start = tonumber(os.getenv("KSTART") or "110")
local i, phase, at, held = 0, "press", start, {}
K = emu.add_machine_frame_notifier(function()
	local t = m.time:as_double()
	if t < at then return end
	if phase == "press" then
		i = i + 1
		if i > #tests then out:write("done\n"); out:flush(); at = 1e9; return end
		local mod, k = tests[i][1], tests[i][2]
		cur, msg, held = tests[i], {}, {}
		if mod ~= 0 then local f = key(mod); f:set_value(1); held[#held + 1] = f end
		local f = key(k); f:set_value(1); held[#held + 1] = f
		phase, at = "release", t + 0.12
	elseif phase == "release" then
		for j = #held, 1, -1 do held[j]:clear_value() end
		phase, at = "log", t + 0.4
	else
		local _, name = key(cur[2])
		out:write(string.format("mod %3d key %3d %-18s %s\n", cur[1], cur[2], name or "?", table.concat(msg, " ")))
		out:flush()
		cur = nil
		-- some keys (Clear, Transmit) need time to settle
		phase, at = "press", t + 0.2
	end
end)
