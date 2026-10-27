local key = ModPath .. '	' .. RequiredScript
if _G[key] then return else _G[key] = true end

local mvec3_add = mvector3.add
local mvec3_ang = mvector3.angle
local mvec3_dis = mvector3.distance
local mvec3_dis_sq = mvector3.distance_sq
local mvec3_div = mvector3.divide
local mvec3_lerp = mvector3.lerp
local mvec3_set = mvector3.set
local mvec3_sub = mvector3.subtract
local mvec3_x = mvector3.x
local mvec3_y = mvector3.y
local mvec3_z = mvector3.z
local math_abs = math.abs
local math_floor = math.floor
local math_max = math.max
local table_insert = table.insert
local table_remove = table.remove

local tmp_vec1 = Vector3()

-- not available in every engine build
local function itr_is_nav_segment_blocked(quad_field, seg_id, access_pos)
	local fn = quad_field.is_nav_segment_blocked
	return fn and access_pos and fn(quad_field, seg_id, access_pos) or false
end

local _navlink_elements = {}
local _navlink_planned_use = {}

function NavigationManager:itr_make_neighbours_list(navseg_id)
	local navseg = self._nav_segments and self._nav_segments[navseg_id]
	if not navseg then
		return
	end

	local list = {}
	for neighbour_seg_id in pairs(navseg.neighbours) do
		local neighbour_seg = self._nav_segments[neighbour_seg_id]
		if neighbour_seg and not neighbour_seg.disabled then
			table.insert(list, neighbour_seg_id)
		end
	end
	navseg.itr_enabled_neighbours_i = list
end

local itr_original_navigationmanager_registeranimnavlink = NavigationManager.register_anim_nav_link
function NavigationManager:register_anim_nav_link(element)
	local values = element._values
	if not values.itr_from_navseg then
		values.itr_interval = math.max(element:_get_default_value_if_nil('interval') or 0, 0)
	end

	itr_original_navigationmanager_registeranimnavlink(self, element)

	local nav_link = element:nav_link()
	if nav_link then
		values.itr_from_navseg = nav_link:start_nav_segment()
		values.itr_to_navseg = nav_link:end_nav_segment()
		_navlink_elements[nav_link:key()] = element
	end
end

local itr_original_navigationmanager_unregisteranimnavlink = NavigationManager.unregister_anim_nav_link
function NavigationManager:unregister_anim_nav_link(element)
	local nav_link = element:nav_link()
	if nav_link then
		nav_link:set_delay_time(604800)
		itr_original_navigationmanager_unregisteranimnavlink(self, element)
	end
end

-- the game's version crashes on missing nav segments or neighbours, here they are skipped
local itr_original_navigationmanager_clbknavfield = NavigationManager.clbk_navfield
function NavigationManager:clbk_navfield(event_name, args, args2, args3)
	local groupai = managers.groupai:state()
	local nav_segments = self._nav_segments

	if event_name == 'add_nav_seg_neighbours' then
		for nav_seg_id, add_neighbours in pairs(args) do
			local nav_seg = nav_segments[nav_seg_id]
			local disabled_neighbours = nav_seg and nav_seg.disabled_neighbours
			if disabled_neighbours then
				for _, other_nav_seg_id in ipairs(add_neighbours) do
					local disabled_doors = disabled_neighbours[other_nav_seg_id]
					if disabled_doors then
						local enabled_doors = nav_seg.neighbours[other_nav_seg_id] or {}
						nav_seg.neighbours[other_nav_seg_id] = enabled_doors
						local i_door = 1
						while i_door <= #disabled_doors do
							local door = disabled_doors[i_door]
							if door.x then
								table_insert(enabled_doors, door)
								table_remove(disabled_doors, i_door)
							else
								i_door = i_door + 1
							end
						end
						if not next(disabled_doors) then
							disabled_neighbours[other_nav_seg_id] = nil
						end
					end
				end
				if not next(disabled_neighbours) then
					nav_seg.disabled_neighbours = nil
				end
			end
		end

		for nav_seg_id in pairs(args) do
			if nav_segments[nav_seg_id] then
				groupai:on_nav_seg_neighbours_state(nav_seg_id, args, true)
			end
		end

	elseif event_name == 'remove_nav_seg_neighbours' then
		for nav_seg_id, rem_neighbours in pairs(args) do
			local nav_seg = nav_segments[nav_seg_id]
			if nav_seg then
				for _, other_nav_seg_id in ipairs(rem_neighbours) do
					local doors = nav_seg.neighbours[other_nav_seg_id]
					if doors then
						nav_seg.disabled_neighbours = nav_seg.disabled_neighbours or {}
						local disabled_doors = nav_seg.disabled_neighbours[other_nav_seg_id] or {}
						nav_seg.disabled_neighbours[other_nav_seg_id] = disabled_doors
						local i_door = 1
						while i_door <= #doors do
							if doors[i_door].x then
								table_insert(disabled_doors, table_remove(doors, i_door))
							else
								i_door = i_door + 1
							end
						end
						if not next(disabled_doors) then
							nav_seg.disabled_neighbours[other_nav_seg_id] = nil
						end
						if not next(doors) then
							nav_seg.neighbours[other_nav_seg_id] = nil
						end
					end
				end
				if nav_seg.disabled_neighbours and not next(nav_seg.disabled_neighbours) then
					nav_seg.disabled_neighbours = nil
				end
			end
		end

		for nav_seg_id in pairs(args) do
			if nav_segments[nav_seg_id] then
				groupai:on_nav_seg_neighbours_state(nav_seg_id, args, false)
			end
		end

	elseif event_name == 'obstruct_nav_link' or event_name == 'unobstruct_nav_link' then
		local nav_seg_from = nav_segments[args]
		local nav_seg_to_id = args2
		local nav_link_id = args3
		local obstruct = event_name == 'obstruct_nav_link'
		local from_list = nav_seg_from and (obstruct and nav_seg_from.neighbours or nav_seg_from.disabled_neighbours)
		local doors = from_list and from_list[nav_seg_to_id]
		if doors then
			for i_door, door in pairs(doors) do
				if not door.x and alive(door) and door:script_data().element:id() == nav_link_id then
					local to_name = obstruct and 'disabled_neighbours' or 'neighbours'
					nav_seg_from[to_name] = nav_seg_from[to_name] or {}
					local is_first_door = not nav_seg_from[to_name][nav_seg_to_id]
					nav_seg_from[to_name][nav_seg_to_id] = nav_seg_from[to_name][nav_seg_to_id] or {}
					table_insert(nav_seg_from[to_name][nav_seg_to_id], table_remove(doors, i_door))

					if not next(doors) then
						from_list[nav_seg_to_id] = nil
						if not obstruct and not next(from_list) then
							nav_seg_from.disabled_neighbours = nil
						end
						if obstruct then
							groupai:on_nav_seg_neighbour_state(args, nav_seg_to_id, false)
						end
					end
					if obstruct then
						groupai:on_nav_link_unregistered(nav_link_id)
					elseif is_first_door then
						groupai:on_nav_seg_neighbour_state(args, nav_seg_to_id, true)
					end
					break
				end
			end
		end

	else
		return itr_original_navigationmanager_clbknavfield(self, event_name, args, args2, args3)
	end

	if event_name == 'add_nav_seg_neighbours' or event_name == 'remove_nav_seg_neighbours' then
		for nav_seg_id, neighbours in pairs(args) do
			self:itr_make_neighbours_list(nav_seg_id)
			for _, other_nav_seg_id in ipairs(neighbours) do
				self:itr_make_neighbours_list(other_nav_seg_id)
			end
		end
	end
end

local itr_original_navigationmanager_setnavsegmentstate = NavigationManager.set_nav_segment_state
function NavigationManager:set_nav_segment_state(id, ...)
	itr_original_navigationmanager_setnavsegmentstate(self, id, ...)

	-- nav links make neighbourhood asymmetric, so all lists pointing to this segment are refreshed
	local unique_id = tostring(id)
	for navseg_id, navseg in pairs(self._nav_segments) do
		if navseg_id == unique_id or navseg.neighbours[unique_id] then
			self:itr_make_neighbours_list(navseg_id)
		end
	end
end

function NavigationManager:itr_get_all_doors_of_segment(segment_id)
	local room_mask = {}
	if self._nav_segments[segment_id] and next(self._nav_segments[segment_id].vis_groups) then
		for _, i_vis_group in ipairs(self._nav_segments[segment_id].vis_groups) do
			local vis_group_rooms = self._visibility_groups[i_vis_group].rooms
			for i_room, _ in pairs(vis_group_rooms) do
				room_mask[i_room] = true
			end
		end
	end

	local all_seg_doors = {}
	local room_neighbours = {}
	for door_id, door in pairs(self._room_doors) do
		local door_rooms = door.rooms
		local r1 = door_rooms[1]
		local r2 = door_rooms[2]
		local rm1 = room_mask[r1]
		local rm2 = room_mask[r2]
		if rm1 or rm2 then
			all_seg_doors[door_id] = door
		end
		if not rm1 then
			room_neighbours[r1] = true
		elseif not rm2 then
			room_neighbours[r2] = true
		end
	end
	return all_seg_doors, room_neighbours
end

function NavigationManager:itr_get_room_to_doors(segment_id, all_seg_doors)
	local result = {}
	for door_id, door in pairs(all_seg_doors) do
		for _, room_id in ipairs(door.rooms) do
			local room = self._rooms[room_id]
			local vis_group = room and room.vis_group and self._visibility_groups[room.vis_group]
			if vis_group and segment_id == vis_group.seg then
				local ri = result[room_id]
				if not ri then
					ri = {}
					result[room_id] = ri
				end
				table_insert(ri, door_id)
			end
		end
	end
	return result
end

function NavigationManager:itr_is_contiguous(level, door_flood_levels, room_to_doors)
	local all_doors = self._room_doors
	local level_doors = {}
	local room_pool = {}
	for door_id, door_level in pairs(door_flood_levels) do
		if door_level == level then
			level_doors[door_id] = true
			for _, room_id in ipairs(all_doors[door_id].rooms) do
				if room_to_doors[room_id] then
					room_pool[room_id] = true
				end
			end
		end
	end

	local start = next(room_pool)
	if not start then
		return false
	end
	local to_process = {[start] = true}
	local stop
	repeat
		stop = true
		local old_to_process = to_process
		to_process = {}
		for base_room_id, _ in pairs(old_to_process) do
			room_pool[base_room_id] = nil
			for _, door_id in pairs(room_to_doors[base_room_id]) do
				for _, room_id in ipairs(all_doors[door_id].rooms) do
					if room_pool[room_id] then
						to_process[room_id] = true
						stop = false
					end
				end
				level_doors[door_id] = nil
			end
		end
	until stop

	return not next(level_doors)
end

function NavigationManager:itr_flood(from_doors, room_to_doors)
	local door_flood_levels = {}
	local to_process = {}
	local level = 1
	for _, door_id in pairs(from_doors) do
		if type(door_id) == 'number' then
			door_flood_levels[door_id] = level
			to_process[door_id] = true
		end
	end

	local all_doors = self._room_doors
	local door_level_counts = {}
	door_level_counts[1] = #from_doors
	local stop
	repeat
		stop = true
		level = level + 1
		local old_to_process = to_process
		to_process = {}
		for base_door_id in pairs(old_to_process) do
			for _, room_id in ipairs(all_doors[base_door_id].rooms) do
				local next_doors = room_to_doors[room_id]
				if next_doors then
					for _, door_id in ipairs(next_doors) do
						if not door_flood_levels[door_id] and not to_process[door_id] then
							to_process[door_id] = true
							door_flood_levels[door_id] = level
							local cnt = door_level_counts[level]
							door_level_counts[level] = cnt and cnt + 1 or 1
							stop = false
						end
					end
				end
			end
		end
	until stop

	local room_flood_levels = {}
	for door_id, level in pairs(door_flood_levels) do
		for _, room_id in ipairs(all_doors[door_id].rooms) do
			if room_to_doors[room_id] then -- to filter rooms of this segment
				local room_level = room_flood_levels[room_id]
				room_flood_levels[room_id] = room_level and math.min(room_level, level) or level
			end
		end
	end

	return room_flood_levels, door_flood_levels, door_level_counts
end

function NavigationManager:itr_find_choke_point(room_flood_levels, room_level_counts, room_to_doors, door_flood_levels, important_rooms)
	local lower_levels_contiguity = true
	local level_max = #room_level_counts
	local threshold = math_max(4, level_max / 2)
	for level, count in pairs(room_level_counts) do
		if level > threshold or level == level_max then
			break
		end
		if lower_levels_contiguity then
			lower_levels_contiguity = self:itr_is_contiguous(level, door_flood_levels, room_to_doors)
		end
		if count == 1 then -- choke point exists
			for room_id, room_level in pairs(room_flood_levels) do
				if room_level == level and important_rooms[room_id] then
					return self._rooms[room_id].center, lower_levels_contiguity
				end
			end
			break
		end			
	end
end

local tmp_vec = Vector3()
local function itr_add_door_pos_to(sum_pos, all_doors, i_door)
	if type(i_door) == 'number' then
		local door = all_doors[i_door]
		mvec3_lerp(tmp_vec, door.pos, door.pos1, 0.5)
		mvec3_add(sum_pos, tmp_vec)
	elseif alive(i_door) then
		local start_pos = _navlink_elements[i_door:key()]:value('position')
		mvec3_add(sum_pos, start_pos)
	end
end

local function itr_get_rooms_having_access_to_next_level(all_doors, room_to_doors, room_flood_levels, room_neighbours)
	local result = {}
	for room_id, room_level in pairs(room_flood_levels) do
		for _, door_id in ipairs(room_to_doors[room_id]) do
			local rooms = all_doors[door_id].rooms
			local other_room_id = rooms[1] == room_id and rooms[2] or rooms[1]
			local other_room_level = room_flood_levels[other_room_id]
			-- next level OR other navseg
			if other_room_level and other_room_level > room_level or not other_room_level and room_level ~= 1 and room_neighbours[other_room_id] then
				result[room_id] = room_level
				break
			end
		end
	end
	return result
end

function NavigationManager:itr_find_proxies(segment_id)
	local choke_points, choke_point_proxies = {}, {}
	local in_proxies = {}
	local out_proxies = {}
	local all_doors = self._room_doors
	local all_nav_segments = self._nav_segments
	local segment = all_nav_segments[segment_id]
	local all_seg_doors, room_neighbours = self:itr_get_all_doors_of_segment(segment_id)
	local room_to_doors = self:itr_get_room_to_doors(segment_id, all_seg_doors)

	for neighbour_seg_id, door_list in pairs(segment.neighbours) do
		local best_level
		local min_count = 1000
		local level1_contiguous
		local room_flood_levels, door_flood_levels, door_level_counts = self:itr_flood(door_list, room_to_doors)

		local important_rooms = itr_get_rooms_having_access_to_next_level(all_doors, room_to_doors, room_flood_levels, room_neighbours)
		local important_doors = {}
		local room_level_counts = {}
		for room_id, level in pairs(important_rooms) do
			room_level_counts[level] = room_level_counts[level] and room_level_counts[level] + 1 or 1
			if level == 1 then
				for _, door_id in ipairs(room_to_doors[room_id]) do
					if door_flood_levels[door_id] == 1 then
						table_insert(important_doors, door_id)
					end
				end
			end
		end

		for level, count in pairs(door_level_counts) do
			if not self:itr_is_contiguous(level, door_flood_levels, room_to_doors) then
				break
			end
			if count <= min_count then
				best_level = level
				min_count = count
			end
			if level == 1 then
				level1_contiguous = true
			elseif level > 4 then
				break
			end
		end

		if best_level and table.size(all_seg_doors) > 20 then
			local cnt = 0
			local pos = Vector3(0, 0, 0)
			for door_id, level in pairs(door_flood_levels) do
				if level == best_level then
					itr_add_door_pos_to(pos, all_doors, door_id)
					cnt = cnt + 1
				end
			end
			if cnt > 0 and cnt < 5 then
				mvec3_div(pos, cnt)
				out_proxies[neighbour_seg_id] = pos
			end
		end

		local neighbour_in_proxies = all_nav_segments[neighbour_seg_id].in_proxies
		local already_done = neighbour_in_proxies and neighbour_in_proxies[segment_id]
		if already_done ~= nil then
			in_proxies[neighbour_seg_id] = already_done
		elseif level1_contiguous then
			local cnt = 0
			local frontier_center = Vector3(0, 0, 0)
			for _, door_id in ipairs(important_doors) do
				itr_add_door_pos_to(frontier_center, all_doors, door_id)
				cnt = cnt + 1
			end
			if cnt > 2 then
				mvec3_div(frontier_center, cnt)
				local metawidth = 0
				for _, door_id in ipairs(important_doors) do
					local dis
					if type(door_id) == 'number' then
						local door = all_doors[door_id]
						mvec3_lerp(tmp_vec, door.pos, door.pos1, 0.5)
						dis = mvec3_dis_sq(frontier_center, tmp_vec)
					elseif alive(door_id) then
						dis = mvec3_dis_sq(frontier_center, _navlink_elements[door_id:key()]:value('position'))
					end
					if dis and dis > metawidth then
						metawidth = dis
					end
				end
				in_proxies[neighbour_seg_id] = metawidth < (150 * 150) and frontier_center or nil
			end
		end

		if #door_list > 1 then
			local choke_point_pos, lower_levels_contiguity = self:itr_find_choke_point(room_flood_levels, room_level_counts, room_to_doors, door_flood_levels, important_rooms)
			if choke_point_pos then
				choke_points[neighbour_seg_id] = choke_point_pos

				if lower_levels_contiguity then
					-- pick the closest important door
					local best_pos = Vector3()
					local min_dis = 1000000000
					for _, door_id in ipairs(important_doors) do
						local door = all_doors[door_id]
						if mvec3_dis_sq(door.pos, door.pos1) > 2500 then
							mvec3_lerp(tmp_vec, door.pos, door.pos1, 0.5)
							local dis = mvec3_dis_sq(tmp_vec, choke_point_pos)
							if dis < min_dis then
								min_dis = dis
								mvec3_set(best_pos, tmp_vec)
							end
						else
							for _, pos in ipairs({door.pos, door.pos1}) do
								local dis = mvec3_dis_sq(pos, choke_point_pos)
								if dis < min_dis then
									min_dis = dis
									mvec3_set(best_pos, pos)
								end
							end
						end
					end
					choke_point_proxies[neighbour_seg_id] = best_pos
				end
			end
		end
	end

	return choke_points, choke_point_proxies, in_proxies, out_proxies
end

function NavigationManager:itr_prepare_streamline_data(world_segments)
	for segment_id, segment in pairs(world_segments) do
		segment.choke_points, segment.choke_point_proxies, segment.in_proxies, segment.out_proxies = self:itr_find_proxies(segment_id)
	end

	for segment_id, segment in pairs(world_segments) do
		for neighbour_seg_id in pairs(segment.neighbours) do
			local choke_point_proxy = segment.choke_point_proxies[neighbour_seg_id]
			if choke_point_proxy then
				local neighbour_choke_point_proxies = self._nav_segments[neighbour_seg_id].choke_point_proxies
				if not neighbour_choke_point_proxies[segment_id] then
					neighbour_choke_point_proxies[segment_id] = choke_point_proxy
				end
			end
		end
	end
end

-- rooms (quads), room doors and visibility groups are only sent to the engine,
-- they are rebuilt in their old format while the streamline data of a world is prepared
local function itr_to_world_pos(pos, translation, yaw)
	local result = Vector3(mvec3_x(pos), mvec3_y(pos), mvec3_z(pos))
	if yaw and yaw ~= 0 then
		result = result:rotate_with(Rotation(yaw, 0, 0))
	end
	if translation then
		mvec3_add(result, translation)
	end
	return result
end

function NavigationManager:itr_load_room_data(load_data, world_id, translation, yaw)
	local grid_size = self._grid_size
	local rooms = {}
	local room_doors = {}
	local visibility_groups = {}

	local vg_to_seg = {}
	local world_segments = {}
	for _, nav_seg in pairs(load_data.segments) do
		local unique_id = self:get_segment_unique_id(world_id, nav_seg.id)
		local segment = self._nav_segments[unique_id]
		if segment then
			segment.itr_vis_groups = nav_seg.vis_groups or {}
			segment.vis_groups = segment.itr_vis_groups
			world_segments[unique_id] = segment
			for _, i_vis_group in ipairs(segment.vis_groups) do
				vg_to_seg[i_vis_group] = unique_id
			end
		end
	end

	local room_vis_groups = {}
	for i_vis_group, vis_group in ipairs(load_data.visibility_groups or {}) do
		local vg_rooms = {}
		for _, i_room in ipairs(vis_group.quads) do
			vg_rooms[i_room] = true
			room_vis_groups[i_room] = i_vis_group
		end
		visibility_groups[i_vis_group] = {
			rooms = vg_rooms,
			seg = vg_to_seg[i_vis_group]
		}
	end

	for i_room = 1, #(load_data.quad_borders_x_pos or {}) do
		local x_pos = load_data.quad_borders_x_pos[i_room] * grid_size
		local x_neg = load_data.quad_borders_x_neg[i_room] * grid_size
		local y_pos = load_data.quad_borders_y_pos[i_room] * grid_size
		local y_neg = load_data.quad_borders_y_neg[i_room] * grid_size
		local z = (load_data.quad_heights_xp_yp[i_room] + load_data.quad_heights_xn_yn[i_room]) / 2
		rooms[i_room] = {
			center = itr_to_world_pos(Vector3((x_pos + x_neg) / 2, (y_pos + y_neg) / 2, z), translation, yaw),
			vis_group = room_vis_groups[i_room]
		}
	end

	local function get_nav_seg_from_i_room(i_room)
		local vis_group = visibility_groups[room_vis_groups[i_room]]
		return vis_group and vis_group.seg
	end

	local neighbours = {}
	for i_door = 1, #(load_data.door_low_quads or {}) do
		local pos = load_data.door_low_pos[i_door]
		local pos1 = load_data.door_high_pos[i_door]
		local door = {
			pos = itr_to_world_pos(Vector3(pos.x * grid_size, pos.y * grid_size, pos.z), translation, yaw),
			pos1 = itr_to_world_pos(Vector3(pos1.x * grid_size, pos1.y * grid_size, pos1.z), translation, yaw),
			rooms = {
				load_data.door_low_quads[i_door],
				load_data.door_high_quads[i_door]
			}
		}
		room_doors[i_door] = door

		local seg1 = get_nav_seg_from_i_room(door.rooms[1])
		local seg2 = get_nav_seg_from_i_room(door.rooms[2])
		if seg1 and seg2 and seg1 ~= seg2 then
			for _, segs in ipairs({ { seg1, seg2 }, { seg2, seg1 } }) do
				local seg_neighbours = neighbours[segs[1]] or {}
				neighbours[segs[1]] = seg_neighbours
				seg_neighbours[segs[2]] = seg_neighbours[segs[2]] or {}
				table_insert(seg_neighbours[segs[2]], i_door)
			end
		end
	end

	self._rooms = rooms
	self._room_doors = room_doors
	self._visibility_groups = visibility_groups

	-- door ids are used as neighbours meanwhile
	local old_neighbours = {}
	for unique_id, segment in pairs(world_segments) do
		old_neighbours[unique_id] = segment.neighbours
		segment.neighbours = neighbours[unique_id] or {}
	end
	return world_segments, old_neighbours
end

function NavigationManager:itr_unload_room_data(world_segments, old_neighbours)
	for unique_id, segment in pairs(world_segments) do
		segment.neighbours = old_neighbours[unique_id] or {}
		segment.vis_groups = nil
		segment.itr_vis_groups = nil
	end

	self._rooms = nil
	self._room_doors = nil
	self._visibility_groups = nil
end

-- the engine gives door positions instead of door ids, they are matched by their (rounded) center
local ITR_DOOR_BUCKET = 25
local function itr_door_bucket(v)
	return math_floor(v / ITR_DOOR_BUCKET)
end

local function itr_index_doors(room_doors)
	local doors_by_bucket = {}
	for _, door in pairs(room_doors) do
		local center = Vector3()
		mvec3_lerp(center, door.pos, door.pos1, 0.5)
		local bx, by = itr_door_bucket(mvec3_x(center)), itr_door_bucket(mvec3_y(center))
		local key = bx .. ' ' .. by
		doors_by_bucket[key] = doors_by_bucket[key] or {}
		table_insert(doors_by_bucket[key], { center, door.pos, door.pos1 })
	end
	return doors_by_bucket
end

local function itr_find_door_data(doors_by_bucket, door)
	local bx, by = itr_door_bucket(mvec3_x(door)), itr_door_bucket(mvec3_y(door))
	local best_data
	local best_dis = 15 * 15
	for x = bx - 1, bx + 1 do
		for y = by - 1, by + 1 do
			for _, data in ipairs(doors_by_bucket[x .. ' ' .. y] or {}) do
				if math_abs(mvec3_z(data[1]) - mvec3_z(door)) < 1 then
					local dis = mvec3_dis_sq(data[1], door)
					if dis < best_dis then
						best_dis = dis
						best_data = data
					end
				end
			end
		end
	end
	return best_data
end

function NavigationManager:itr_match_door_data(world_id)
	local doors_by_bucket = self.itr_world_doors and self.itr_world_doors[world_id]
	if not doors_by_bucket then
		return
	end
	self.itr_world_doors[world_id] = nil

	self.itr_room_doors = self.itr_room_doors or {}
	local nr, nr_found = 0, 0
	for _, segment in pairs(self._nav_segments) do
		if segment.world_id == world_id then
			for _, door_list in pairs(segment.neighbours) do
				for _, door in ipairs(door_list) do
					if door.x then
						local data = itr_find_door_data(doors_by_bucket, door)
						self.itr_room_doors[door] = data or { door }
						nr = nr + 1
						nr_found = data and nr_found + 1 or nr_found
					end
				end
			end
		end
	end

	log(('[Iter] streamline data of world %s ready, %i/%i doors identified'):format(tostring(world_id), nr_found, nr))
end

function NavigationManager:itr_prepare_world(load_data, world_id, translation, yaw)
	if not load_data or not load_data.segments or not load_data.quad_borders_x_pos then
		return
	end

	local world_segments, old_neighbours = self:itr_load_room_data(load_data, world_id, translation, yaw)
	self:itr_prepare_streamline_data(world_segments)
	self.itr_world_doors = self.itr_world_doors or {}
	self.itr_world_doors[world_id] = itr_index_doors(self._room_doors)
	self:itr_unload_room_data(world_segments, old_neighbours)
end

function NavigationManager:itr_make_all_neighbours_lists()
	for navseg_id in pairs(self._nav_segments) do
		self:itr_make_neighbours_list(navseg_id)
	end
end

local itr_original_navigationmanager_resolvesegmentneighbours = NavigationManager._resolve_segment_neighbours
function NavigationManager:_resolve_segment_neighbours(world_id, ...)
	itr_original_navigationmanager_resolvesegmentneighbours(self, world_id, ...)

	self:itr_match_door_data(world_id)
	self:itr_make_all_neighbours_lists()
end

local itr_original_navigationmanager_unloadworlddata = NavigationManager.unload_world_data
function NavigationManager:unload_world_data(world_id)
	local removed = {}
	for seg_id, segment in pairs(self._nav_segments) do
		if segment.world_id == world_id then
			removed[seg_id] = true
			for _, doors in pairs(segment.neighbours) do
				for _, door in ipairs(doors) do
					if self.itr_room_doors then
						self.itr_room_doors[door] = nil
					end
				end
			end
		end
	end
	self.itr_coarse_cache = {}

	itr_original_navigationmanager_unloadworlddata(self, world_id)

	-- the game leaves disabled neighbours pointing to the unloaded segments
	for _, segment in pairs(self._nav_segments) do
		local disabled_neighbours = segment.disabled_neighbours
		if disabled_neighbours then
			for seg_id in pairs(removed) do
				disabled_neighbours[seg_id] = nil
			end
			if not next(disabled_neighbours) then
				segment.disabled_neighbours = nil
			end
		end
	end

	self:itr_make_all_neighbours_lists()
end

local itr_original_navigationmanager_loadnavdata = NavigationManager._load_nav_data
function NavigationManager:_load_nav_data(data, world_id, ...)
	itr_original_navigationmanager_loadnavdata(self, data, world_id, ...)

	self.itr_coarse_cache = {}

	-- only the host plans paths
	if Network:is_server() then
		self:itr_prepare_world(data, world_id, ...)
	end

	-- worlds without streamline data
	for _, segment in pairs(self._nav_segments) do
		if segment.world_id == world_id and not segment.choke_points then
			segment.choke_points, segment.choke_point_proxies, segment.in_proxies, segment.out_proxies = {}, {}, {}, {}
		end
	end
end

local function itr_log_navlink_usage(navlink, t)
	local key = navlink:key()
	local navlink_usage = _navlink_planned_use[key]
	if not navlink_usage then
		navlink_usage = {}
		_navlink_planned_use[key] = navlink_usage
	end
	local last_entry = navlink_usage[#navlink_usage]
	if not last_entry or t > last_entry then -- 1 coarse path per frame, no need to stack multiple attempts from the same NPC
		table_insert(navlink_usage, t)
	end
end

local function itr_get_navlink_usage(navlink, t)
	local result = 0
	local n_key = navlink:key()
	local navlink_usage = _navlink_planned_use[n_key]
	if not navlink_usage then
		return 0
	end

	local nu = navlink_usage[1]
	local threshold = t - _navlink_elements[n_key]._values.itr_interval
	while nu and nu < threshold do
		table_remove(navlink_usage, 1)
		nu = navlink_usage[1]
	end
	return #navlink_usage
end

function NavigationManager:itr_get_closest_door_to_pos(all_doors, door_list, pos_from, pos_to, access_pos, navlink_accounting)
	local best_pos, best_pos_with_delay, t, min_congestion_risk
	local best_dis = 1000000000
	local is_direct, through_navlink, through_navlink_with_delay

	for i = #door_list, 1, -1 do
		local i_door = door_list[i]
		if i_door.x then
			for _, door_pos in ipairs(self.itr_room_doors[i_door] or { i_door }) do
				local nav_tracker = self._quad_field:create_nav_tracker(door_pos, true)
				local obstructed = nav_tracker:obstructed()
				self._quad_field:destroy_nav_tracker(nav_tracker)
				if not obstructed then
					local dis = (pos_from and mvec3_dis(pos_from, door_pos) or 0) + mvec3_dis(door_pos, pos_to)
					if dis <= best_dis then
						best_pos = door_pos
						best_dis = dis
						is_direct = true
					end
					break
				end
			end

		elseif is_direct then
			-- qued

		elseif i_door and alive(i_door) and not i_door:is_obstructed() and (not access_pos or i_door:check_access(access_pos, 0)) then
			local element = _navlink_elements[i_door:key()]
			local start_pos = element:value('position')
			local end_pos = element:nav_link_end_pos()
			local dis = (pos_from and mvec3_dis(pos_from, start_pos) or 0) + mvec3_dis(start_pos, end_pos) + mvec3_dis(end_pos, pos_to)
			local nav_link_delay = element._values.itr_interval
			local congestion_risk = 0
			if nav_link_delay > 0 then
				t = t or TimerManager:game():time()
				local user = element.itr_reserved_by_unit
				congestion_risk = math_max(0, i_door:delay_time() - t)
					+ (
						(alive(user) and user:id() ~= -1 and 0 or 1)
						+ (element.itr_navlink_queue_length or 0)
						+ itr_get_navlink_usage(i_door, t)
					) * nav_link_delay
			end
			if congestion_risk == 0 then
				if dis * 1.4 < best_dis then
					is_direct = false
					best_pos = end_pos
					best_dis = dis * 1.4
					through_navlink = i_door
				end
			elseif not min_congestion_risk or congestion_risk < min_congestion_risk then
				min_congestion_risk = congestion_risk
				best_pos_with_delay = end_pos
				through_navlink_with_delay = i_door
			end
		end
	end

	if is_direct then
		through_navlink = nil
	else
		through_navlink = through_navlink or through_navlink_with_delay
		if through_navlink and navlink_accounting then
			itr_log_navlink_usage(through_navlink, t or TimerManager:game():time())
		end
	end

	return best_pos or best_pos_with_delay, through_navlink
end

function NavigationManager:itr_get_door_between(segment1_id, segment2_id, near_pos)
	local door_list = self._nav_segments[segment1_id].neighbours[segment2_id]
	if door_list then
		return self:itr_get_closest_door_to_pos(self._room_doors, door_list, nil, near_pos, nil, true)
	end
end

function NavigationManager:itr_find_best_navlink(segment1_id, segment2_id, access_pos, near_pos, current_navlink_element)
	local door_list = self._nav_segments[segment1_id].neighbours[segment2_id]
	if not door_list then
		return
	end

	local best_dis = 100000000000000
	local best_time_to_wait = 100000000000
	local best_navlink, best_navlink_element
	for i = #door_list, 1, -1 do
		local navlink = door_list[i]
		if not navlink.x and alive(navlink) and not navlink:is_obstructed() and navlink:check_access(access_pos, 0) then
			local navlink_element = _navlink_elements[navlink:key()]

			local interval = navlink_element._values.itr_interval
			local extra_time_to_go = math_max(0, 1.5 - interval)
			local navpos = navlink_element:value('position')

			local queue_length = navlink_element.itr_navlink_queue_length or 0
			if navlink_element == current_navlink_element then
				queue_length = queue_length - 1
			end

			local time_to_wait = queue_length * (interval + extra_time_to_go)

			if near_pos then
				local my_time_to_go = mvec3_dis(near_pos, navpos) / (self.itr_navlink_coef * 0.7)
				time_to_wait = time_to_wait - extra_time_to_go + math_max(0, my_time_to_go - interval)
			end

			local user = navlink_element.itr_reserved_by_unit
			if alive(user) and user:id() ~= -1 then
				time_to_wait = time_to_wait + interval + math_max(0, mvec3_dis(user:position(), navpos) / self.itr_navlink_coef - interval)
			end

			if time_to_wait < best_time_to_wait then
				best_time_to_wait = time_to_wait
				best_dis = dis
				best_navlink = navlink
				best_navlink_element = navlink_element
			end
		end
	end

	return best_navlink, best_navlink_element
end

local axis = Vector3()
local function itr_get_door_in_alignment(all_doors, door_list, from, to)
	if not from or not to then
		return
	end
	local best_pos, best_angle
	mvec3_set(axis, to)
	mvec3_sub(axis, from)
	for i = #door_list, 1, -1 do
		local i_door = door_list[i]
		if i_door.x then
			local door_pos = i_door
			mvec3_set(tmp_vec1, door_pos)
			mvec3_sub(tmp_vec1, from)
			local angle = mvec3_ang(axis, tmp_vec1)
			if not best_angle or angle < best_angle then
				best_angle = angle
				best_pos = door_pos
			end
		end
	end
	return best_pos
end

function NavigationManager:itr_get_coarse_pos_between(segment1_id, segment2_id, near_pos, access_pos)
	local doors = self._nav_segments[segment1_id].neighbours[segment2_id]
	if not doors then
		return false
	end

	local segment1 = self._nav_segments[segment1_id]
	local best_pos = segment1.choke_point_proxies[segment2_id]
	if best_pos then
		return best_pos
	end

	best_pos = segment1.out_proxies[segment2_id]
	if best_pos then
		return best_pos
	end

	best_pos = segment1.in_proxies[segment2_id]
	if best_pos then
		return best_pos
	end

	return self:itr_get_closest_door_to_pos(self._room_doors, doors, nil, near_pos, access_pos, false)
end

function NavigationManager:itr_streamline(path, access_pos)
	local all_segs = self._nav_segments
	local all_doors = self._room_doors
	local path_nr = #path
	local step1 = path[1]
	local step2

	if not step1[2] then
		step1[2] = all_segs[step1[1]].pos
	end

	for i = 2, path_nr do
		step2 = path[i]

		local segment1 = all_segs[step1[1]]
		local segment2_id = step2[1]
		local door_list = segment1.neighbours[segment2_id]
		if door_list then
			local navlink
			local segment2 = all_segs[segment2_id]
			local step3 = path[i + 1]
			local segment3 = step3 and all_segs[step3[1]]

			local best_pos = segment1.choke_point_proxies[step2[1]]

			if not best_pos then
				local out_proxy = step3 and (segment3.choke_points[step2[1]] or segment2.out_proxies[step3[1]])
				local in_proxy = segment2.in_proxies[step1[1]] or step3 and all_segs[step3[1]].pos
				best_pos = itr_get_door_in_alignment(all_doors, door_list, step1[2], out_proxy or in_proxy)
			end

			if not best_pos then
				local proxy = step3 and segment2.in_proxies[step3[1]] or path[path_nr][2]
				best_pos, navlink = self:itr_get_closest_door_to_pos(all_doors, door_list, step1[2], proxy, access_pos, true)
				if not best_pos then
					return false
				end
			end

			step2[2] = best_pos
			step2[3] = navlink
		end

		step1 = step2
	end

	path[1][2] = nil
	if path_nr > 1 and path[path_nr - 1][1] ~= path[path_nr][1] then
		path[path_nr + 1] = { path[path_nr][1] }
		path[path_nr][1] = path[path_nr - 1][1]
	end
	return path
end

function NavigationManager:itr_get_accessibility(door_list, access_pos, access_neg)
	local min_congestion_risk, t
	for i = #door_list, 1, -1 do
		local i_door = door_list[i]
		if i_door.x then
			return 0
		elseif i_door and alive(i_door) and not i_door:is_obstructed() and i_door:check_access(access_pos, access_neg or 0) then
			t = t or TimerManager:game():time()
			local element = _navlink_elements[i_door:key()]
			local nav_link_delay = element._values.itr_interval
			if nav_link_delay > 0 then
				local user = element.itr_reserved_by_unit
				local congestion_risk = math_max(0, i_door:delay_time() - t)
					+ (
						(alive(user) and user:id() ~= -1 and 0 or 1)
						+ (element.itr_navlink_queue_length or 0)
						+ itr_get_navlink_usage(i_door, t)
					) * nav_link_delay
				if congestion_risk == 0 then
					return 0.1
				elseif not min_congestion_risk or congestion_risk < min_congestion_risk then
					min_congestion_risk = congestion_risk
				end
			end
		end
	end
	return min_congestion_risk or 0.01
end

local function path_copy(path)
	local result = {}
	for i = 1, #path do
		local step_src = path[i]
		local step_dst = {
			step_src[1],
			step_src[2]
		}
		table_insert(result, step_dst)
	end
	return result
end

local function get_coarse_dis(p1, p2, ps)
	local dis = mvec3_dis(p1, p2)
	if ps then
		local ps_z = mvec3_z(ps)
		dis = dis + (math_abs(mvec3_z(p1) - ps_z) + math_abs(mvec3_z(p2) - ps_z)) * 2
	end
	return dis
end

NavigationManager.itr_navlink_coef = 350
NavigationManager.itr_coarse_cache_lifetime = 2
NavigationManager.itr_coarse_fail_retry_t = 3
NavigationManager.itr_coarse_cache = {}

function NavigationManager:_execute_coarce_search(search_data)
	local t = TimerManager:game():time()
	local access_pos = search_data.access_pos
	local next_seg_id = search_data.start_i_seg
	local end_i_seg = search_data.end_i_seg
	local verify_clbk = search_data.verify_clbk

	local bypass_congestion = search_data.bypass_congestion
	if not bypass_congestion then
		if type(search_data.id) ~= 'string' then
			bypass_congestion = true
		else
			local fc = search_data.id:sub(1, 1)
			bypass_congestion = not (fc == 'T' or fc == 'C')
		end
	end

	local path_key = tostring(access_pos) .. ';' .. next_seg_id .. ';' .. end_i_seg
	if verify_clbk then
		path_key = path_key .. 'vc'
	end

	local cached_result = not bypass_congestion and self.itr_coarse_cache[path_key]
	if not cached_result then
		-- qued
	elseif type(cached_result) == 'number' then
		local fail_t = cached_result
		if t - fail_t < self.itr_coarse_fail_retry_t then
			return false
		end
	else
		if t - cached_result.t < self.itr_coarse_cache_lifetime then
			local result = path_copy(cached_result)
			result[#result][2] = search_data.to_pos
			return search_data.results_callback and result or self:itr_streamline(result, access_pos)
		end
	end

	if itr_is_nav_segment_blocked(self._quad_field, end_i_seg, access_pos) then
		self.itr_coarse_cache[path_key] = t
		return false
	end

	local all_nav_segments = self._nav_segments
	local access_neg = search_data.access_neg
	local navlink_coef = self.itr_navlink_coef

	local potential_paths = {}
	local seg_to_search = {}
	local discovered_seg = {
		[next_seg_id] = {
			path = tostring(next_seg_id),
			delay = 0,
			steps_nr = 0,
			coarse_dis = 0,
			pos = search_data.from_pos or all_nav_segments[next_seg_id].pos
		}
	}

	local candidate
	repeat
		local navseg = all_nav_segments[next_seg_id]
		local neighbours = navseg.neighbours
		if neighbours then
			local consider_neighbours = true
			local from = discovered_seg[next_seg_id]
			local door_list = neighbours[end_i_seg]
			if door_list then
				local access_cost = bypass_congestion and 0 or self:itr_get_accessibility(door_list, access_pos, access_neg)
				if access_cost then
					local through_pos = self:itr_get_coarse_pos_between(next_seg_id, end_i_seg, from.pos, access_pos)
					consider_neighbours = access_cost > 0 or not through_pos
					if through_pos then
						local tmp = table.map_copy(from)
						tmp.delay = tmp.delay + access_cost
						tmp.coarse_dis = tmp.coarse_dis + get_coarse_dis(tmp.pos, through_pos, navseg.pos) + mvec3_dis(through_pos, search_data.to_pos or all_nav_segments[end_i_seg].pos)
						table_insert(potential_paths, tmp)

						if not candidate or tmp.coarse_dis < candidate.coarse_dis then
							if tmp.delay < 0.2 then
								candidate = tmp
							end
						end
					end
				end
			end

			if consider_neighbours then
				local enabled_neighbours = navseg.itr_enabled_neighbours_i
				for i = #enabled_neighbours, 1, -1 do
					local neighbour_seg_id = enabled_neighbours[i]
					if verify_clbk and not verify_clbk(neighbour_seg_id) then
						-- qued
					elseif itr_is_nav_segment_blocked(self._quad_field, neighbour_seg_id, access_pos) then
						-- qued
					else
						local door_list = neighbours[neighbour_seg_id]
						local access_cost = bypass_congestion and 0 or self:itr_get_accessibility(door_list, access_pos, access_neg)
						if access_cost then
							local through_pos = self:itr_get_coarse_pos_between(next_seg_id, neighbour_seg_id, from.pos, access_pos)
							if through_pos then
								local delay = from.delay + access_cost
								local coarse_dis = from.coarse_dis + get_coarse_dis(from.pos, through_pos, navseg.pos)
								local discovered = discovered_seg[neighbour_seg_id]
								if not discovered then
									if not candidate or coarse_dis + delay * navlink_coef < candidate.coarse_dis + candidate.delay * navlink_coef then
										table_insert(seg_to_search, neighbour_seg_id)
										discovered = {
											path = from.path .. ';' .. neighbour_seg_id,
											delay = delay,
											steps_nr = from.steps_nr + 1,
											coarse_dis = coarse_dis,
											pos = through_pos
										}
										discovered_seg[neighbour_seg_id] = discovered
									end
								else
									if coarse_dis + delay * navlink_coef < discovered.coarse_dis + discovered.delay * navlink_coef then
										table_insert(seg_to_search, neighbour_seg_id)
										discovered.path = from.path .. ';' .. neighbour_seg_id
										discovered.delay = delay
										discovered.steps_nr = from.steps_nr + 1
										discovered.coarse_dis = coarse_dis
										discovered.pos = through_pos
									end
								end
							end
						end
					end
				end
			end
		end

		next_seg_id = table_remove(seg_to_search, 1)
	until not next_seg_id

	local best_score = 100000000
	local best_path
	for _, ppath in ipairs(potential_paths) do
		local score = ppath.coarse_dis + ppath.delay * navlink_coef
		if score < best_score then
			best_score = score
			best_path = ppath
		end
	end

	if not best_path then
		self.itr_coarse_cache[path_key] = t
		return false
	end

	local i = 1
	local result = {}
	for idseg in string.gmatch(best_path.path, '[^;]+') do
		result[i] = { idseg }
		i = i + 1
	end
	result[i] = {
		end_i_seg,
		search_data.to_pos
	}
	result.has_navlinks = best_path.delay > 0
	result.coarse_dis = best_path.coarse_dis

	if best_path.delay == 0 then
		local cache_result = path_copy(result)
		cache_result.t = t
		self.itr_coarse_cache[path_key] = cache_result
	end

	return search_data.results_callback and result or self:itr_streamline(result, access_pos)
end
