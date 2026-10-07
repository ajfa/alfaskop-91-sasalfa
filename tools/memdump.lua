-- from $AT seconds on, write the DU's RAM (0000-EFFF) to du.bin every 2 seconds; the rest is I/O whose reads
-- have side effects (the ACIA and TCC data registers give their byte away), so it is left out
local m = manager.machine
local dmem = m.devices[":ducpu"].spaces["program"]
local at = tonumber(os.getenv("AT") or "115")
D = emu.add_machine_frame_notifier(function()
	if m.time:as_double() < at then return end
	at = at + 2
	local t = {}
	for a = 0, 0xefff do t[#t + 1] = string.char(dmem:read_u8(a)) end
	local f = io.open("du.bin", "wb")
	f:write(table.concat(t)); f:close()
end)
