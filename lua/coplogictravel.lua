local key = ModPath .. '	' .. RequiredScript
if _G[key] then return else _G[key] = true end

local itr_original_coplogictravel_getexactmovepos = CopLogicTravel._get_exact_move_pos
function CopLogicTravel._get_exact_move_pos(data, nav_index)
	local my_data = data.internal_data
	local coarse_path = my_data.coarse_path
	local nr = #coarse_path

	if nr > 2 and nav_index == 2 and my_data.itr_direct_to_pos then
		if my_data.moving_to_cover then
			managers.navigation:release_cover(my_data.moving_to_cover[1])
			my_data.moving_to_cover = nil
		end

		local nav_segs = {}
		for i = 1, nr do
			nav_segs[i] = coarse_path[i][1]
		end
		my_data.itr_nav_segs = nav_segs

		my_data.coarse_path = {
			coarse_path[1],
			coarse_path[nr]
		}

		return my_data.itr_direct_to_pos
	end

	if nav_index < nr then
		if data.is_converted or data.team and data.team.id == 'criminal1' then
			if my_data.moving_to_cover then
				managers.navigation:release_cover(my_data.moving_to_cover[1])
				my_data.moving_to_cover = nil
			end
			return coarse_path[nav_index][2]

		elseif data.objective and data.objective.type == 'phalanx' then
			return coarse_path[nav_index][2]
		end
	end

	return itr_original_coplogictravel_getexactmovepos(data, nav_index)
end

local itr_original_coplogictravel_getallowedtravelnavsegs = CopLogicTravel._get_allowed_travel_nav_segs
function CopLogicTravel._get_allowed_travel_nav_segs(data, my_data, to_pos)
	local itr_nav_segs = my_data.itr_nav_segs
	if itr_nav_segs then
		my_data.itr_nav_segs = nil
		return itr_nav_segs
	end

	return itr_original_coplogictravel_getallowedtravelnavsegs(data, my_data, to_pos)
end

local itr_original_coplogictravel_begincoarsepathing = CopLogicTravel._begin_coarse_pathing
function CopLogicTravel._begin_coarse_pathing(data, my_data)
	local obj = data.objective
	if obj and obj.pos and obj.nav_seg and managers.navigation:get_nav_seg_from_pos(obj.pos) ~= obj.nav_seg then
		obj.pos = nil
	end

	itr_original_coplogictravel_begincoarsepathing(data, my_data)
end
