-- pick SAS2.1 in the facility menu, log every new DU screen to sas.txt, take a snapshot every 30 s, and with
-- TYPE set, type it from home once the emulated time passes TYPEAT
local m = manager.machine
local dmem = m.devices[":ducpu"].spaces["program"]
local out = io.open("sas.txt", "w")
local function log(s) out:write(s, "\n"); out:flush() end
local function key(n)
	local port = m.ioport.ports[":du_kbd:P1" .. (n // 16)]
	for _, f in pairs(port.fields) do
		if f.mask == (1 << (n % 16)) then return f end
	end
	error("no key " .. n)
end
local function row(addr, step)
	local l = ""
	for i = 0, 79 do
		local c = dmem:read_u8(addr + i * step) & 0x7f
		l = l .. ((c >= 0x20 and c < 0x7f) and string.char(c) or " ")
	end
	return l
end
local function screen()
	local lines = {}
	-- D4GSAS keeps its screen at $DF:$E0 with 160 bytes per row ($E1): attribute and character per cell
	local two = dmem:read_u8(0xdf) == 0x70 and dmem:read_u8(0xe0) == 0x60 and dmem:read_u8(0xe1) == 0xa0
	for r = 0, 23 do
		lines[#lines + 1] = two and row(0x7061 + r * 160, 2) or row(0x7800 + r * 80, 1)
	end
	lines[#lines + 1] = two and row(0x7fb0, 1) or row(0x7f80, 1)
	return table.concat(lines, "|")
end
local presses = {}
local function press(f, at) presses[#presses + 1] = { f, at, at + 0.15 } end
local state, t_state, last, nextcheck, type_at, typed = "wait", 0, "", 30, nil, false
T = emu.add_machine_frame_notifier(function()
	local t = m.time:as_double()
	for _, p in ipairs(presses) do
		if not p.down and t >= p[2] then p[1]:set_value(1); p.down = true end
		if p.down and not p.up and t >= p[3] then p[1]:clear_value(); p.up = true end
	end
	if type_at and t >= type_at then
		type_at = nil
		m.natkeyboard:post(os.getenv("TYPE"))
		log(string.format("== %.1f typed %s", t, os.getenv("TYPE")))
	end
	if t < nextcheck then return end
	nextcheck = t + 0.5
	local s = screen()
	if s ~= last then
		log(string.format("== %.1f screen", t))
		for l in s:gmatch("[^|]+") do if l:find("%S") then log("|" .. l:gsub("%s+$", "")) end end
		last = s
	end
	if state == "wait" and s:find("Facility", 1, true) then
		state = "down"; t_state = t; press(key(87), t + 2)
		log(string.format("== %.1f down", t))
	elseif state == "down" and t >= t_state + 5 then
		m.natkeyboard:post("\r"); state = "enter"; t_state = t; log(string.format("== %.1f enter", t))
	elseif state == "enter" and t >= t_state + 20 then
		t_state = t + 10
		m.video:snapshot()
		log(string.format("== %.1f snapshot", t))
		local text = os.getenv("TYPE")
		if text and text ~= "" and not typed and t >= tonumber(os.getenv("TYPEAT") or "0") then
			-- the DU transmits from home (or the last SOE) to the cursor; Cursor Home in SAS is key 55
			typed = true
			press(key(55), t)
			type_at = t + 1
		end
	end
end)
