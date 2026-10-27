local key = ModPath .. '	' .. RequiredScript
if _G[key] then return else _G[key] = true end

local mvec3_cpy = mvector3.copy
local mvec3_dis = mvector3.distance
local mvec3_lerp = mvector3.lerp
local mvec3_set = mvector3.set
local mvec3_set_z = mvector3.set_z
local mvec3_z = mvector3.z

local itr_original_copactionwalk_init = CopActionWalk._init
function CopActionWalk:_init()
	local result = itr_original_copactionwalk_init(self)

	if result and self._sync then
		self:itr_prepare_for_upcoming_navlink()
	end

	return result
end

function CopActionWalk:itr_check_navlink_delay(t)
	local navlink = self._next_is_nav_link.c_class
	if alive(navlink) then
		local delay_t = self._next_is_nav_link.c_class:delay_time()
		if not delay_t or t >= delay_t then
			return true
		end
	else
		return true
	end
end

function CopActionWalk:itr_set_navlink_delay(t)
	local delay = self._next_is_nav_link.element._values.itr_interval
	if delay and delay > 0 then
		local navlink = self._next_is_nav_link.c_class
		if alive(navlink) then
			navlink:set_delay_time(t + delay)
			return true
		end
	end
end

local itr_original_copactionwalk_playnavlinkanim = CopActionWalk._play_nav_link_anim
function CopActionWalk:_play_nav_link_anim(t)
	if not self._sync then
		return itr_original_copactionwalk_playnavlinkanim(self, t)
	end

	if self:itr_check_navlink_delay(t) then
		self:itr_set_navlink_delay(t)
		self:itr_clear_navlink_reservation(self._next_is_nav_link.element)
		self.itr_wait_for_navlink_availability_t = nil
		itr_original_copactionwalk_playnavlinkanim(self, t)
	end
end

function CopActionWalk:itr_get_alternate_navlink(current_navlink_element)
	local navlink_values = current_navlink_element._values
	local from_seg_id = navlink_values.itr_from_navseg
	local to_seg_id = navlink_values.itr_to_navseg
	local access_pos = self._common_data.ext_brain._SO_access
	local near_pos = self._common_data.pos
	local alt_navlink_c_class, alt_navlink_element = managers.navigation:itr_find_best_navlink(from_seg_id, to_seg_id, access_pos, near_pos, current_navlink_element)
	if alt_navlink_element and alt_navlink_element ~= current_navlink_element then
		return alt_navlink_c_class, alt_navlink_element
	end
end

function CopActionWalk:itr_reserve_navlink(navlink_element)
	if navlink_element._values.itr_interval == 0 then
		return true
	end

	local wait_since_t = self.itr_wait_for_navlink_availability_t
	if not wait_since_t then
		wait_since_t = self._last_upd_t
		self.itr_wait_for_navlink_availability_t = wait_since_t
	end

	local user = navlink_element.itr_reserved_by_unit
	if not alive(user) or user:id() == -1 then
		local oldest_t = navlink_element.itr_navlink_queue_previous_oldest_t
		if not oldest_t or wait_since_t <= oldest_t then
			navlink_element.itr_reserved_by_unit = self._unit
			return true
		end
	elseif user:key() == self._unit:key() then
		return true
	end

	return false
end

function CopActionWalk:itr_switch_to_sibling_navlink(old_navlink_element)
	local t = self._last_upd_t
	if not self._simplified_path then
		-- qued
	elseif self.itr_reroute_t and t - self.itr_reroute_t < 0.5 then
		-- qued
	elseif old_navlink_element.itr_navlink_queue_length and old_navlink_element.itr_navlink_queue_length > 0 then
		self.itr_reroute_t = t
		local alt_navlink_c_class, alt_navlink_element = self:itr_get_alternate_navlink(old_navlink_element)
		if alt_navlink_element and not alt_navlink_element.itr_reserved_by_unit then
			local new_navpoint = {
				element = alt_navlink_element,
				c_class = alt_navlink_c_class
			}
			local invalid_after_navlink = mvec3_dis(old_navlink_element._values.search_position, alt_navlink_element._values.search_position) > 400
			if self._next_is_nav_link then
				self._next_is_nav_link = nil
				self._end_of_curved_path = nil
				if invalid_after_navlink then
					self._simplified_path = {
						self._simplified_path[1],
						mvec3_cpy(alt_navlink_element._values.position),
						new_navpoint,
						mvec3_cpy(alt_navlink_element._values.search_position)
					}
				else
					self._simplified_path[2] = new_navpoint
					table.insert(self._simplified_path, 2, mvec3_cpy(alt_navlink_element._values.position))
				end
			else
				if invalid_after_navlink then
					self._end_of_curved_path = nil
					self._simplified_path = {
						self._simplified_path[1],
						self._simplified_path[2],
						new_navpoint,
						mvec3_cpy(alt_navlink_element._values.search_position)
					}
				else
					self._simplified_path[3] = new_navpoint
				end
			end
			alt_navlink_element.itr_reserved_by_unit = self._unit
			self.itr_wait_for_navlink = nil

			return true
		end
	end

	return false
end

function CopActionWalk:itr_clear_navlink_reservation(navlink_element)
	local user = navlink_element.itr_reserved_by_unit
	if user and user:key() == self._unit:key() then
		navlink_element.itr_reserved_by_unit = nil
		if not navlink_element.itr_navlink_queue_frame_t or navlink_element.itr_navlink_queue_frame_t < self._last_upd_t then
			navlink_element.itr_navlink_queue_frame_t = nil
			navlink_element.itr_navlink_queue_oldest_t = nil
			navlink_element.itr_navlink_queue_previous_oldest_t = nil
			navlink_element.itr_navlink_queue_length_in_progress = nil
			navlink_element.itr_navlink_queue_length = nil
		end
	end
end

function CopActionWalk:itr_get_wait_pos(navseg_id, near_pos)
	local cover = managers.navigation:find_cover_in_nav_seg_3({[navseg_id] = true}, 400, near_pos)
	local wait_pos = cover and cover[1] or CopLogicTravel._get_pos_on_wall(near_pos, 400)
	return wait_pos
end

function CopActionWalk:itr_update_navlink_queue_data(navlink_element)
	local frame_t = navlink_element.itr_navlink_queue_frame_t or 0
	local t = self._last_upd_t
	if t > frame_t then
		navlink_element.itr_navlink_queue_length = navlink_element.itr_navlink_queue_length_in_progress
		navlink_element.itr_navlink_queue_length_in_progress = 1
		navlink_element.itr_navlink_queue_frame_t = t
		navlink_element.itr_navlink_queue_previous_oldest_t = navlink_element.itr_navlink_queue_oldest_t
		navlink_element.itr_navlink_queue_oldest_t = t
	else
		navlink_element.itr_navlink_queue_length_in_progress = navlink_element.itr_navlink_queue_length_in_progress + 1
	end

	if self.itr_wait_for_navlink_availability_t < navlink_element.itr_navlink_queue_oldest_t then
		navlink_element.itr_navlink_queue_oldest_t = self.itr_wait_for_navlink_availability_t
	end
end

function CopActionWalk:itr_prepare_for_upcoming_navlink()
	if self.itr_wait_for_navlink then
		return
	end

	local index = self._next_is_nav_link and 2 or 3
	local upcoming_navlink = self._simplified_path[index]
	if type(upcoming_navlink) ~= 'table' then
		return
	end

	local navlink_element = upcoming_navlink.element
	if self:itr_reserve_navlink(navlink_element) then
		self.itr_wait_for_navlink = nil
	elseif self:itr_switch_to_sibling_navlink(navlink_element) then
		self.itr_wait_for_navlink = nil
	else
		self.itr_wait_for_navlink = upcoming_navlink
		if index == 2 then
			self:_set_updator('itr_update_wait_for_navlink_availability')
		else
			local wait_pos = self:itr_get_wait_pos(navlink_element._values.itr_from_navseg, navlink_element._values.position)
			if wait_pos then
				self._common_data.ext_brain:add_pos_rsrv('stand', {
					radius = 30,
					position = mvec3_cpy(wait_pos)
				})
				table.insert(self._simplified_path, index, wait_pos)
			end
		end
	end
end

local itr_original_copactionwalk_advancesimplifiedpath = CopActionWalk._advance_simplified_path
function CopActionWalk:_advance_simplified_path()
	if self._sync then
		self:itr_prepare_for_upcoming_navlink()
	end

	itr_original_copactionwalk_advancesimplifiedpath(self)

	if self._sync and self.itr_wait_for_navlink and self._next_is_nav_link == self.itr_wait_for_navlink then
		self:_set_updator('itr_update_wait_for_navlink_availability')
		self.itr_wait_for_navlink_availability_t = self._last_upd_t
	end
end

function CopActionWalk:itr_update_wait_for_navlink_availability(t)
	local navlink_element = self._next_is_nav_link.element
	if self:itr_reserve_navlink(navlink_element) then
		-- qued
	elseif self:itr_switch_to_sibling_navlink(navlink_element) then
		-- qued
	else
		self._last_upd_t = t
		self:itr_update_navlink_queue_data(navlink_element)
		if self._ext_anim.move then
			self:_stop_walk()
		end
		return
	end

	self:_set_updator(self._start_run and '_upd_start_anim_first_frame' or nil)
	self._common_data.ext_brain:rem_pos_rsrv('stand')
	self.itr_wait_for_navlink = nil
	self:update(t)
end

local itr_original_CopActionWalk_onexit = CopActionWalk.on_exit
function CopActionWalk:on_exit()
	if self._sync and self._next_is_nav_link then
		self:itr_clear_navlink_reservation(self._next_is_nav_link.element)
	end
	return itr_original_CopActionWalk_onexit(self)
end

local tmp_vec1 = Vector3()
local tmp_vec2 = Vector3()

local _chk_shortcut_pos_to_pos_params = CopActionWalk._chk_shortcut_pos_to_pos_params
local _obstacle_mask

function CopActionWalk._chk_shortcut_pos_to_pos(from, to, trace)
	local params = _chk_shortcut_pos_to_pos_params
	params.pos_from = from
	params.pos_to = to
	params.trace = trace

	_obstacle_mask = _obstacle_mask or managers.slot:get_mask('AI_graph_obstacle_check') + managers.slot:get_mask('vehicles')

	local res = managers.navigation:raycast(params)
	if res then
		local from_z = mvec3_z(from)
		local to_z = mvec3_z(to)
		local min_z, max_z
		if from_z < to_z then
			min_z, max_z = from_z, to_z
		else
			min_z, max_z = to_z, from_z
		end

		if max_z - min_z < 40 then
			local raised_from = tmp_vec1
			mvec3_set(raised_from, from)
			mvec3_set_z(raised_from, from_z + 65)

			local raised_to = tmp_vec2
			mvec3_set(raised_to, to)
			mvec3_set_z(raised_to, to_z + 65)

			local res2 = World:raycast('ray', raised_from, raised_to, 'sphere_cast_radius', 40, 'slot_mask', _obstacle_mask, 'ray_type', 'walk', 'report')
			if not res2 then
				local middle_up = tmp_vec1
				mvec3_lerp(middle_up, from, to, 0.5)
				mvec3_set_z(middle_up, max_z)

				local middle_down = tmp_vec2
				mvec3_set(middle_down, middle_up)
				mvec3_set_z(middle_down, min_z - 100)

				local res3 = World:raycast('ray', middle_up, middle_down, 'slot_mask', _obstacle_mask, 'ray_type', 'walk')
				if res3 and res3.distance < 40 then
					return res2, trace and {to}
				end
			end
		end
	end

	return res, params.trace
end
