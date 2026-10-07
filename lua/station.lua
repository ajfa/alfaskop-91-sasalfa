-- put the DU at station $STATION before the TCC starts talking to it, then run $NEXT
local m = manager.machine
local f = m.ioport.ports[":CONFIG"].fields["Display unit station"]
f.user_value = tonumber(os.getenv("STATION") or "2") * 4
print("DU station set to " .. (f.user_value // 4))
if os.getenv("NEXT") then dofile(os.getenv("NEXT")) end
