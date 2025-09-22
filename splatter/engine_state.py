# Engine State Management
# This module contains global state variables for tracking the external C++ engine
#
# State Categories:
# - Process State (engine.py): Raw subprocess lifecycle, direct communication
# - Sync Bridge State (engine_state.py): High-level connection status, sync metadata, operation queues

# Track the expected engine state for each group (what the engine thinks attributes should be)
# Key: group name (str), Value: dict of {attr_name: value}
# Only includes groups that have been processed by align_to_axes
_engine_expected_state = {}

