package datepicker

Date :: struct {
	year, month, day: int,
}

Cell :: struct {
	date:     Date,
	in_month: bool,
}

GRID_CELLS :: 42

is_leap_year :: proc(year: int) -> bool {
	return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

days_in_month :: proc(year, month: int) -> int {
	assert(month >= 1 && month <= 12)
	days := [12]int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
	return month == 2 && is_leap_year(year) ? 29 : days[month - 1]
}

valid :: proc(date: Date) -> bool {
	return date.year >= 1 && date.month >= 1 && date.month <= 12 && date.day >= 1 && date.day <= days_in_month(date.year, date.month)
}

// Zero is Sunday.
weekday :: proc(date: Date) -> int {
	assert(valid(date))
	offsets := [12]int{0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}
	year := date.month < 3 ? date.year - 1 : date.year
	return (year + year / 4 - year / 100 + year / 400 + offsets[date.month - 1] + date.day) % 7
}

shift_month :: proc(year, month, delta: int) -> (int, int) {
	index := year * 12 + (month - 1) + delta
	return index / 12, index % 12 + 1
}

// Six weeks beginning on `first_weekday` (zero is Sunday) so the grid height never changes.
month_grid :: proc(year, month: int, first_weekday := 1) -> [GRID_CELLS]Cell {
	assert(first_weekday >= 0 && first_weekday < 7)
	lead := (weekday({year, month, 1}) - first_weekday + 7) % 7
	previous_year, previous_month := shift_month(year, month, -1)
	next_year, next_month := shift_month(year, month, 1)
	previous_days := days_in_month(previous_year, previous_month)
	days := days_in_month(year, month)
	grid: [GRID_CELLS]Cell
	for &cell, index in grid {
		day := index - lead + 1
		switch {
		case day < 1: cell = {{previous_year, previous_month, previous_days + day}, false}
		case day > days: cell = {{next_year, next_month, day - days}, false}
		case: cell = {{year, month, day}, true}
		}
	}
	return grid
}
