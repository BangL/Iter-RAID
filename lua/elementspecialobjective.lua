local key = ModPath .. '	' .. RequiredScript
if _G[key] then return else _G[key] = true end

-- the delay of nav links is handled by the queue of CopActionWalk
function ElementSpecialObjective:nav_link_delay()
	return 0
end
