local key = ModPath .. '	' .. RequiredScript
if _G[key] then return else _G[key] = true end

local _search_path_queued

function CopBrain:search_for_coarse_path(search_id, to_seg, verify_clbk, access_neg)
	local to_pos
	local objective = self._logic_data.objective
	if objective then
		to_pos = objective.pos
		if not to_pos and alive(objective.follow_unit) then
			to_pos = objective.follow_unit:movement():nav_tracker():field_position()
		end
	end

	local params = {
		from_tracker = self._unit:movement():nav_tracker(),
		to_seg = to_seg,
		access = {'walk'},
		id = search_id,
		results_clbk = callback(self, self, 'clbk_coarse_pathing_results', search_id),
		verify_clbk = verify_clbk,
		access_pos = self._logic_data.char_tweak.access,
		access_neg = access_neg,
		to_pos = to_pos
	}
	self._logic_data.active_searches[search_id] = 2

	_search_path_queued = true

	managers.navigation:search_coarse(params)

	if _search_path_queued then
		local cs = managers.navigation._coarse_searches
		local last_search = cs[#cs]
		if last_search and last_search.id == search_id then
			last_search.from_pos = self._logic_data.m_pos
		end
	end

	return true
end

local itr_original_copbrain_clbkcoarsepathingresults = CopBrain.clbk_coarse_pathing_results
function CopBrain:clbk_coarse_pathing_results(search_id, path)
	_search_path_queued = false

	if path then
		local data = self._logic_data
		local my_data = data.internal_data
		local objective = data.objective

		path.coarse_dis = nil

		if path.has_navlinks then
			path.has_navlinks = nil
			my_data.itr_direct_to_pos = nil

		elseif objective and objective.pos and managers.groupai:state():whisper_mode() then
			my_data.itr_direct_to_pos = objective.pos
		end

		if not my_data.itr_direct_to_pos then
			path[1][2] = data.m_pos

			if objective and objective.follow_unit then
				path[#path][2] = objective.follow_unit:position()
			end

			path = managers.navigation:itr_streamline(path, self._SO_access)
		end
	end

	itr_original_copbrain_clbkcoarsepathingresults(self, search_id, path)
end
