package text_input

import "core:fmt"
import "core:strings"

Field_ID :: distinct u64
NO_FIELD :: Field_ID(0)

Selection_Granularity :: enum {
	Character,
	Word,
	All,
}

State :: struct {
	active_field: Field_ID,
	caret_byte_offset: int,
	selection_anchor_byte: int,
	marked_start_byte: int,
	marked_text: string,
	has_marked_text: bool,
	drag_field: Field_ID,
	drag_granularity: Selection_Granularity,
	drag_origin_start: int,
	drag_origin_end: int,
	drag_active: bool,
	scroll_x: f64,
}

Focus_Snapshot :: struct {
	field: Field_ID,
	caret_byte_offset: int,
	selection_anchor_byte: int,
	scroll_x: f64,
}

UTF16_Range :: struct {
	location: int,
	length: int,
	valid: bool,
}

destroy :: proc(state: ^State) {
	if state == nil {return}
	delete(state.marked_text)
	state^ = {}
}

replace_owned :: proc(target: ^string, value: string) {
	next := strings.clone(value)
	delete(target^)
	target^ = next
}

previous_character_offset :: proc(text: string, offset: int) -> int {
	if offset <= 0 {return 0}
	index := min(offset, len(text))-1
	for index > 0 && (text[index]&0xc0) == 0x80 {index -= 1}
	return index
}

next_character_offset :: proc(text: string, offset: int) -> int {
	if offset >= len(text) {return len(text)}
	index := max(0, offset)+1
	for index < len(text) && (text[index]&0xc0) == 0x80 {index += 1}
	return index
}

clamp_byte_offset :: proc(text: string, offset: int) -> int {
	index := min(max(offset, 0), len(text))
	for index > 0 && index < len(text) && (text[index]&0xc0) == 0x80 {
		index -= 1
	}
	return index
}

selection_bounds :: proc(state: ^State, text: string) -> (start, end: int) {
	if state == nil {return}
	anchor := clamp_byte_offset(text, state.selection_anchor_byte)
	active := clamp_byte_offset(text, state.caret_byte_offset)
	return min(anchor, active), max(anchor, active)
}

has_selection :: proc(state: ^State, text: string) -> bool {
	start, end := selection_bounds(state, text)
	return start != end
}

collapse_selection :: proc(state: ^State, text: string, offset: int) {
	if state == nil {return}
	next := clamp_byte_offset(text, offset)
	state.caret_byte_offset = next
	state.selection_anchor_byte = next
}

set_selection :: proc(state: ^State, text: string, anchor, active: int) {
	if state == nil {return}
	state.selection_anchor_byte = clamp_byte_offset(text, anchor)
	state.caret_byte_offset = clamp_byte_offset(text, active)
}

focus :: proc(state: ^State, field: Field_ID, text: string) -> bool {
	if state == nil || field == NO_FIELD {return false}
	changed := state.active_field != field
	state.active_field = field
	state.drag_active = false
	if changed {
		collapse_selection(state, text, len(text))
		state.scroll_x = 0
		clear_marked_text(state)
	}
	return changed
}

blur :: proc(state: ^State, target: ^string = nil) -> bool {
	if state == nil || state.active_field == NO_FIELD {return false}
	if target != nil {remove_marked_text(state, target)} else {clear_marked_text(state)}
	state.active_field = NO_FIELD
	state.drag_active = false
	state.selection_anchor_byte = state.caret_byte_offset
	state.scroll_x = 0
	return true
}

snapshot_focus :: proc(state: ^State) -> Focus_Snapshot {
	if state == nil {return {}}
	return {
		field = state.active_field,
		caret_byte_offset = state.caret_byte_offset,
		selection_anchor_byte = state.selection_anchor_byte,
		scroll_x = state.scroll_x,
	}
}

restore_focus :: proc(state: ^State, snapshot: Focus_Snapshot, text: string) {
	if state == nil {return}
	clear_marked_text(state)
	state.active_field = snapshot.field
	state.drag_active = false
	set_selection(
		state,
		text,
		snapshot.selection_anchor_byte,
		snapshot.caret_byte_offset,
	)
	state.scroll_x = max(0, snapshot.scroll_x)
}

remove_selection :: proc(state: ^State, target: ^string) -> bool {
	if state == nil || target == nil {return false}
	start, end := selection_bounds(state, target^)
	if start == end {return false}
	updated := fmt.tprintf("%s%s", target^[:start], target^[end:])
	replace_owned(target, updated)
	collapse_selection(state, target^, start)
	return true
}

replace_selection :: proc(state: ^State, target: ^string, value: string) -> bool {
	if state == nil || target == nil {return false}
	start, end := selection_bounds(state, target^)
	updated := fmt.tprintf("%s%s%s", target^[:start], value, target^[end:])
	replace_owned(target, updated)
	collapse_selection(state, target^, start+len(value))
	return start != end || len(value) > 0
}

insert_text :: proc(state: ^State, target: ^string, value: string) -> bool {
	return replace_selection(state, target, value)
}

delete_backward :: proc(state: ^State, target: ^string) -> bool {
	if state == nil || target == nil {return false}
	if remove_selection(state, target) {return true}
	caret := clamp_byte_offset(target^, state.caret_byte_offset)
	start := previous_character_offset(target^, caret)
	if start == caret {return false}
	updated := fmt.tprintf("%s%s", target^[:start], target^[caret:])
	replace_owned(target, updated)
	collapse_selection(state, target^, start)
	return true
}

delete_forward :: proc(state: ^State, target: ^string) -> bool {
	if state == nil || target == nil {return false}
	if remove_selection(state, target) {return true}
	caret := clamp_byte_offset(target^, state.caret_byte_offset)
	end := next_character_offset(target^, caret)
	if end == caret {return false}
	updated := fmt.tprintf("%s%s", target^[:caret], target^[end:])
	replace_owned(target, updated)
	collapse_selection(state, target^, caret)
	return true
}

Character_Class :: enum {
	Word,
	Whitespace,
	Punctuation,
}

character_class :: proc(text: string, offset: int) -> Character_Class {
	if offset < 0 || offset >= len(text) {return .Whitespace}
	value := text[offset]
	if value >= 0x80 ||
	   value >= 'a' && value <= 'z' ||
	   value >= 'A' && value <= 'Z' ||
	   value >= '0' && value <= '9' ||
	   value == '_' {
		return .Word
	}
	if value == ' ' || value == '\t' || value == '\n' ||
	   value == '\r' || value == '\v' || value == '\f' {
		return .Whitespace
	}
	return .Punctuation
}

word_bounds :: proc(text: string, offset: int) -> (start, end: int) {
	if len(text) == 0 {return 0, 0}
	index := clamp_byte_offset(text, offset)
	if index == len(text) {index = previous_character_offset(text, index)}
	class := character_class(text, index)
	start = index
	for start > 0 {
		previous := previous_character_offset(text, start)
		if character_class(text, previous) != class {break}
		start = previous
	}
	end = next_character_offset(text, index)
	for end < len(text) {
		if character_class(text, end) != class {break}
		end = next_character_offset(text, end)
	}
	return
}

previous_word_offset :: proc(text: string, offset: int) -> int {
	index := clamp_byte_offset(text, offset)
	if index > 0 {
		previous := previous_character_offset(text, index)
		if character_class(text, previous) != .Word {
			for index > 0 {
				previous = previous_character_offset(text, index)
				if character_class(text, previous) == .Word {break}
				index = previous
			}
			return index
		}
	}
	for index > 0 {
		previous := previous_character_offset(text, index)
		if character_class(text, previous) != .Word {break}
		index = previous
	}
	return index
}

next_word_offset :: proc(text: string, offset: int) -> int {
	index := clamp_byte_offset(text, offset)
	if index < len(text) && character_class(text, index) == .Word {
		for index < len(text) && character_class(text, index) == .Word {
			index = next_character_offset(text, index)
		}
		return index
	}
	for index < len(text) && character_class(text, index) != .Word {
		index = next_character_offset(text, index)
	}
	for index < len(text) && character_class(text, index) == .Word {
		index = next_character_offset(text, index)
	}
	return index
}

delete_word_backward :: proc(state: ^State, target: ^string) -> bool {
	if state == nil || target == nil {return false}
	if remove_selection(state, target) {return true}
	caret := clamp_byte_offset(target^, state.caret_byte_offset)
	start := previous_word_offset(target^, caret)
	if start == caret {return false}
	updated := fmt.tprintf("%s%s", target^[:start], target^[caret:])
	replace_owned(target, updated)
	collapse_selection(state, target^, start)
	return true
}

line_start_for_offset :: proc(text: string, offset: int) -> int {
	index := clamp_byte_offset(text, offset)
	for index > 0 && text[index-1] != '\n' {index -= 1}
	return index
}

line_end_for_offset :: proc(text: string, offset: int) -> int {
	index := clamp_byte_offset(text, offset)
	for index < len(text) && text[index] != '\n' {index += 1}
	return index
}

character_column_for_offset :: proc(text: string, line_start, offset: int) -> int {
	column := 0
	index := clamp_byte_offset(text, line_start)
	end := max(index, clamp_byte_offset(text, offset))
	for index < end {
		index = next_character_offset(text, index)
		column += 1
	}
	return column
}

offset_for_character_column :: proc(
	text: string,
	line_start, line_end, column: int,
) -> int {
	offset := clamp_byte_offset(text, line_start)
	end := max(offset, clamp_byte_offset(text, line_end))
	for _ in 0..<max(0, column) {
		if offset >= end {break}
		offset = next_character_offset(text, offset)
	}
	return offset
}

vertical_offset :: proc(text: string, offset, direction: int) -> int {
	current_start := line_start_for_offset(text, offset)
	current_end := line_end_for_offset(text, offset)
	column := character_column_for_offset(text, current_start, offset)
	if direction < 0 {
		if current_start == 0 {return clamp_byte_offset(text, offset)}
		previous_end := current_start-1
		previous_start := line_start_for_offset(text, previous_end)
		return offset_for_character_column(
			text,
			previous_start,
			previous_end,
			column,
		)
	}
	if current_end >= len(text) {return clamp_byte_offset(text, offset)}
	next_start := current_end+1
	next_end := line_end_for_offset(text, next_start)
	return offset_for_character_column(text, next_start, next_end, column)
}

move_selection :: proc(
	state: ^State,
	text: string,
	destination: int,
	extend: bool,
) {
	if state == nil {return}
	next := clamp_byte_offset(text, destination)
	if extend {
		state.caret_byte_offset = next
	} else {
		collapse_selection(state, text, next)
	}
}

move_left :: proc(state: ^State, text: string, extend: bool) {
	start, _ := selection_bounds(state, text)
	if !extend && has_selection(state, text) {
		collapse_selection(state, text, start)
		return
	}
	move_selection(
		state,
		text,
		previous_character_offset(text, state.caret_byte_offset),
		extend,
	)
}

move_right :: proc(state: ^State, text: string, extend: bool) {
	_, end := selection_bounds(state, text)
	if !extend && has_selection(state, text) {
		collapse_selection(state, text, end)
		return
	}
	move_selection(
		state,
		text,
		next_character_offset(text, state.caret_byte_offset),
		extend,
	)
}

move_word_left :: proc(state: ^State, text: string, extend: bool) {
	start, _ := selection_bounds(state, text)
	if !extend && has_selection(state, text) {
		collapse_selection(state, text, start)
		return
	}
	move_selection(
		state,
		text,
		previous_word_offset(text, state.caret_byte_offset),
		extend,
	)
}

move_word_right :: proc(state: ^State, text: string, extend: bool) {
	_, end := selection_bounds(state, text)
	if !extend && has_selection(state, text) {
		collapse_selection(state, text, end)
		return
	}
	move_selection(
		state,
		text,
		next_word_offset(text, state.caret_byte_offset),
		extend,
	)
}

move_line_start :: proc(state: ^State, text: string, extend: bool) {
	move_selection(
		state,
		text,
		line_start_for_offset(text, state.caret_byte_offset),
		extend,
	)
}

move_line_end :: proc(state: ^State, text: string, extend: bool) {
	move_selection(
		state,
		text,
		line_end_for_offset(text, state.caret_byte_offset),
		extend,
	)
}

move_vertical :: proc(state: ^State, text: string, direction: int, extend: bool) {
	move_selection(
		state,
		text,
		vertical_offset(text, state.caret_byte_offset, direction),
		extend,
	)
}

clear_marked_text :: proc(state: ^State) {
	if state == nil {return}
	delete(state.marked_text)
	state.marked_text = ""
	state.marked_start_byte = 0
	state.has_marked_text = false
}

remove_marked_text :: proc(state: ^State, target: ^string) -> bool {
	if state == nil || target == nil || !state.has_marked_text {return false}
	start := clamp_byte_offset(target^, state.marked_start_byte)
	end := min(start+len(state.marked_text), len(target^))
	updated := fmt.tprintf("%s%s", target^[:start], target^[end:])
	replace_owned(target, updated)
	collapse_selection(state, target^, start)
	clear_marked_text(state)
	return true
}

set_marked_text :: proc(
	state: ^State,
	target: ^string,
	value: string,
	selected_utf16_location := -1,
	selected_utf16_length := 0,
) -> bool {
	if state == nil || target == nil {return false}
	_ = remove_marked_text(state, target)
	start, _ := selection_bounds(state, target^)
	state.marked_text = strings.clone(value)
	state.marked_start_byte = start
	state.has_marked_text = true
	_ = insert_text(state, target, value)
	if selected_utf16_location >= 0 {
		local_start := byte_offset_for_utf16_index(
			value,
			selected_utf16_location,
		)
		local_end := byte_offset_for_utf16_index(
			value,
			selected_utf16_location+max(0, selected_utf16_length),
		)
		set_selection(
			state,
			target^,
			start+local_start,
			start+local_end,
		)
	}
	return true
}

unmark_text :: proc(state: ^State) {
	clear_marked_text(state)
}

byte_offset_for_utf16_index :: proc(text: string, target_index: int) -> int {
	byte_index, utf16_index := 0, 0
	for byte_index < len(text) && utf16_index < max(0, target_index) {
		first := text[byte_index]
		byte_count, utf16_count := 1, 1
		if first&0xf8 == 0xf0 {byte_count, utf16_count = 4, 2}
		else if first&0xf0 == 0xe0 {byte_count = 3}
		else if first&0xe0 == 0xc0 {byte_count = 2}
		if utf16_index+utf16_count > target_index {break}
		byte_index += byte_count
		utf16_index += utf16_count
	}
	return min(byte_index, len(text))
}

utf16_index_for_byte_offset :: proc(text: string, target_offset: int) -> int {
	byte_index, utf16_index := 0, 0
	end := clamp_byte_offset(text, target_offset)
	for byte_index < end {
		first := text[byte_index]
		byte_count, utf16_count := 1, 1
		if first&0xf8 == 0xf0 {byte_count, utf16_count = 4, 2}
		else if first&0xf0 == 0xe0 {byte_count = 3}
		else if first&0xe0 == 0xc0 {byte_count = 2}
		byte_index += byte_count
		utf16_index += utf16_count
	}
	return utf16_index
}

selected_utf16_range :: proc(state: ^State, text: string) -> UTF16_Range {
	if state == nil || state.active_field == NO_FIELD {return {}}
	start, end := selection_bounds(state, text)
	utf16_start := utf16_index_for_byte_offset(text, start)
	utf16_end := utf16_index_for_byte_offset(text, end)
	return {
		location = utf16_start,
		length = utf16_end-utf16_start,
		valid = true,
	}
}

marked_utf16_range :: proc(state: ^State, text: string) -> UTF16_Range {
	if state == nil || !state.has_marked_text {return {}}
	start := utf16_index_for_byte_offset(text, state.marked_start_byte)
	length := utf16_index_for_byte_offset(
		state.marked_text,
		len(state.marked_text),
	)
	return {location = start, length = length, valid = true}
}

selected_text :: proc(state: ^State, text: string) -> string {
	start, end := selection_bounds(state, text)
	return text[start:end]
}

begin_pointer_selection :: proc(
	state: ^State,
	field: Field_ID,
	text: string,
	offset: int,
	click_count: uint,
) {
	if state == nil || field == NO_FIELD {return}
	_ = focus(state, field, text)
	clear_marked_text(state)
	next := clamp_byte_offset(text, offset)
	state.drag_field = field
	state.drag_active = click_count < 3
	if click_count >= 3 {
		state.drag_granularity = .All
		state.drag_origin_start = 0
		state.drag_origin_end = len(text)
		set_selection(state, text, 0, len(text))
		return
	}
	if click_count == 2 {
		start, end := word_bounds(text, next)
		state.drag_granularity = .Word
		state.drag_origin_start = start
		state.drag_origin_end = end
		set_selection(state, text, start, end)
		return
	}
	state.drag_granularity = .Character
	state.drag_origin_start = next
	state.drag_origin_end = next
	set_selection(state, text, next, next)
}

update_pointer_selection :: proc(
	state: ^State,
	field: Field_ID,
	text: string,
	offset: int,
) -> bool {
	if state == nil || !state.drag_active ||
	   state.active_field != field || state.drag_field != field {
		return false
	}
	next := clamp_byte_offset(text, offset)
	switch state.drag_granularity {
	case .Character:
		set_selection(state, text, state.drag_origin_start, next)
	case .Word:
		start, end := word_bounds(text, next)
		if next < state.drag_origin_start {
			set_selection(state, text, state.drag_origin_end, start)
		} else {
			set_selection(state, text, state.drag_origin_start, end)
		}
	case .All:
		set_selection(state, text, 0, len(text))
	}
	return true
}

end_pointer_selection :: proc(state: ^State) {
	if state == nil {return}
	state.drag_active = false
}

update_horizontal_scroll :: proc(
	state: ^State,
	caret_advance, available_width: f64,
) -> f64 {
	if state == nil {return 0}
	available := max(0, available_width)
	if caret_advance-state.scroll_x > available {
		state.scroll_x = caret_advance-available
	}
	if caret_advance-state.scroll_x < 0 {
		state.scroll_x = max(0, caret_advance)
	}
	return state.scroll_x
}
