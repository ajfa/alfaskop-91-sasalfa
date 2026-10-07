-- press keys one by one after SAS2.1 is up; log who writes the DU cursor ($E9) with the return addresses on the stack
local m = manager.machine
local du = m.devices[":ducpu"]
local dmem = du.spaces["program"]
local function key(n)
	local port = m.ioport.ports[":du_kbd:P1" .. (n // 16)]
	for _, f in pairs(port.fields) do
		if f.mask == (1 << (n % 16)) then return f end
	end
end
local keys = {}
for k in (os.getenv("KEYS") or "23 91 39 17 98"):gmatch("%d+") do keys[#keys + 1] = tonumber(k) end
local out = io.open("keytrace.txt", "w")
local cur, n = nil, 0
TW = dmem:install_write_tap(0xe9, 0xea, "cur", function(o, d)
	if not cur or n > 6 then return end
	n = n + 1
	local s = du.state["S"].value
	local st = {}
	for i = 1, 12 do st[#st + 1] = string.format("%02X", dmem:read_u8(s + i)) end
	out:write(string.format("key %d: %02X=%02X pc=%04X s=%04X [%s]\n", cur, o, d, du.state["PC"].value, s, table.concat(st, " ")))
	out:flush()
end)
local start = tonumber(os.getenv("KSTART") or "110")
local i, at, down = 0, start, nil
K = emu.add_machine_frame_notifier(function()
	local t = m.time:as_double()
	if t < at then return end
	if down then down:clear_value(); down = nil; at = t + 1.5; return end
	i = i + 1
	if i > #keys then at = 1e9; cur = nil; out:write("done\n"); out:flush(); return end
	cur, n = keys[i], 0
	down = key(keys[i]); down:set_value(1)
	at = t + 0.15
end)
