package text_input

import "core:strings"
import "core:testing"

@(test)
utf8_and_utf16_offsets_follow_character_boundaries_test :: proc(t: ^testing.T) {
	text := "A😀B"
	testing.expect_value(t, next_character_offset(text, 1), len("A😀"))
	testing.expect_value(t, previous_character_offset(text, len("A😀")), 1)
	testing.expect_value(t, clamp_byte_offset(text, 2), 1)
	testing.expect_value(t, utf16_index_for_byte_offset(text, len(text)), 4)
	testing.expect_value(t, byte_offset_for_utf16_index(text, 3), len("A😀"))
}

@(test)
selection_replacement_and_deletion_use_owned_application_string_test :: proc(
	t: ^testing.T,
) {
	state: State
	defer destroy(&state)
	value := strings.clone("A😀BC")
	defer delete(value)
	_ = focus(&state, 1, value)
	set_selection(&state, value, 1, len("A😀B"))
	testing.expect(t, replace_selection(&state, &value, "x"))
	testing.expect_value(t, value, "AxC")
	testing.expect_value(t, state.caret_byte_offset, 2)
	set_selection(&state, value, 1, 2)
	testing.expect(t, delete_backward(&state, &value))
	testing.expect_value(t, value, "AC")
}

@(test)
word_bounds_and_movement_support_utf8_words_test :: proc(t: ^testing.T) {
	text := "one,  café_two! end"
	start, end := word_bounds(text, strings.index(text, "fé"))
	testing.expect_value(t, text[start:end], "café_two")
	testing.expect_value(t, next_word_offset(text, 0), len("one"))
	testing.expect_value(
		t,
		previous_word_offset(text, len(text)),
		len("one,  café_two! "),
	)
}

@(test)
movement_extends_and_collapses_selection_test :: proc(t: ^testing.T) {
	state: State
	defer destroy(&state)
	text := "ab\ncafé"
	_ = focus(&state, 1, text)
	collapse_selection(&state, text, 1)
	move_right(&state, text, true)
	testing.expect_value(t, state.selection_anchor_byte, 1)
	testing.expect_value(t, state.caret_byte_offset, 2)
	move_left(&state, text, false)
	testing.expect_value(t, state.caret_byte_offset, 1)
	move_vertical(&state, text, 1, true)
	testing.expect_value(t, state.selection_anchor_byte, 1)
	testing.expect_value(t, state.caret_byte_offset, len("ab\nc"))
}

@(test)
pointer_click_counts_select_character_word_and_all_test :: proc(t: ^testing.T) {
	state: State
	defer destroy(&state)
	text := "one two"
	begin_pointer_selection(&state, 7, text, 1, 1)
	testing.expect_value(t, state.caret_byte_offset, 1)
	begin_pointer_selection(&state, 7, text, 5, 2)
	start, end := selection_bounds(&state, text)
	testing.expect_value(t, text[start:end], "two")
	begin_pointer_selection(&state, 7, text, 3, 3)
	start, end = selection_bounds(&state, text)
	testing.expect_value(t, start, 0)
	testing.expect_value(t, end, len(text))
	testing.expect(t, !state.drag_active)
}

@(test)
marked_text_reports_appkit_utf16_ranges_test :: proc(t: ^testing.T) {
	state: State
	defer destroy(&state)
	value := strings.clone("AB")
	defer delete(value)
	_ = focus(&state, 3, value)
	collapse_selection(&state, value, 1)
	testing.expect(t, set_marked_text(&state, &value, "😀", 0, 2))
	testing.expect_value(t, value, "A😀B")
	marked := marked_utf16_range(&state, value)
	testing.expect(t, marked.valid)
	testing.expect_value(t, marked.location, 1)
	testing.expect_value(t, marked.length, 2)
	unmark_text(&state)
	testing.expect(t, !state.has_marked_text)
}

@(test)
focus_snapshot_and_horizontal_scroll_are_component_state_test :: proc(
	t: ^testing.T,
) {
	state: State
	defer destroy(&state)
	_ = focus(&state, 4, "abcdef")
	set_selection(&state, "abcdef", 2, 4)
	testing.expect_value(t, update_horizontal_scroll(&state, 90, 60), 30.0)
	snapshot := snapshot_focus(&state)
	_ = focus(&state, 5, "other")
	restore_focus(&state, snapshot, "abcdef")
	testing.expect_value(t, state.active_field, Field_ID(4))
	testing.expect_value(t, state.selection_anchor_byte, 2)
	testing.expect_value(t, state.caret_byte_offset, 4)
	testing.expect_value(t, state.scroll_x, 30.0)
}
