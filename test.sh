#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
hw-odin test "$ROOT/text_input" -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true
hw-odin test "$ROOT/datepicker" -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true
