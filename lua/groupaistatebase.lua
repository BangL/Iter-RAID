local key = ModPath .. '	' .. RequiredScript
if _G[key] then return else _G[key] = true end

-- the game's version crashes when a neighbour segment is not loaded (anymore)
function GroupAIStateBase:on_nav_seg_neighbour_state(start_seg_id, end_seg_id, state)
	local all_nav_segs = managers.navigation._nav_segments

	for area_id, area in pairs(self._area_data) do
		if area.nav_segs[start_seg_id] then
			for other_area_id, other_area in pairs(area.neighbours) do
				other_area.neighbours[area_id] = nil
			end

			area.neighbours = {}

			for seg_id in pairs(area.nav_segs) do
				local nav_seg = all_nav_segs[seg_id]
				if nav_seg and not nav_seg.disabled then
					for other_nav_seg_id in pairs(nav_seg.neighbours) do
						local other_nav_seg = all_nav_segs[other_nav_seg_id]
						if other_nav_seg and not other_nav_seg.disabled then
							for other_area_id, other_area in pairs(self._area_data) do
								if other_area_id ~= area_id and other_area.nav_segs[other_nav_seg_id] then
									area.neighbours[other_area_id] = other_area

									if other_nav_seg.neighbours[seg_id] then
										other_area.neighbours[area_id] = area
									end
								end
							end
						end
					end
				end
			end
		end
	end

	managers.navigation:itr_make_neighbours_list(start_seg_id)
	managers.navigation:itr_make_neighbours_list(end_seg_id)
end
