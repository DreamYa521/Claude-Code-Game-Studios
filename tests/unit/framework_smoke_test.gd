# Example unit test — verifies the test framework is functional
# Remove or replace when real system tests are written
# Story: data-definitions-001 — Enums & Constants
extends GdUnitTestSuite


func test_framework_smoke_assertion_passes() -> void:
	# Arrange — nothing needed, pure smoke check
	# Act — nothing to act on
	# Assert — if this runs at all, the framework is correctly installed
	assert_bool(true).is_true()
