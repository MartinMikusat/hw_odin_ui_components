package calendar

import "core:testing"

@(test)
month_lengths_and_weekdays_follow_the_gregorian_calendar_test :: proc(t: ^testing.T) {
	testing.expect_value(t, days_in_month(2024, 2), 29)
	testing.expect_value(t, days_in_month(1900, 2), 28)
	testing.expect_value(t, days_in_month(2000, 2), 29)
	testing.expect(t, !valid({2026, 2, 29}))
	testing.expect_value(t, weekday({2026, 10, 8}), 4) // Thursday.
	testing.expect_value(t, weekday({2000, 1, 1}), 6) // Saturday.
}

@(test)
month_grid_pads_with_adjacent_months_test :: proc(t: ^testing.T) {
	grid := month_grid(2026, 10) // 1 October 2026 is a Thursday.
	testing.expect_value(t, grid[0].date, Date{2026, 9, 28})
	testing.expect(t, !grid[0].in_month)
	testing.expect_value(t, grid[3].date, Date{2026, 10, 1})
	testing.expect(t, grid[3].in_month)
	testing.expect_value(t, grid[GRID_CELLS - 1].date, Date{2026, 11, 8})
	sunday_first := month_grid(2026, 10, 0)
	testing.expect_value(t, sunday_first[4].date, Date{2026, 10, 1})
}

@(test)
shift_month_crosses_year_boundaries_test :: proc(t: ^testing.T) {
	year, month := shift_month(2026, 1, -1)
	testing.expect_value(t, year, 2025)
	testing.expect_value(t, month, 12)
	year, month = shift_month(2026, 12, 1)
	testing.expect_value(t, year, 2027)
	testing.expect_value(t, month, 1)
}
