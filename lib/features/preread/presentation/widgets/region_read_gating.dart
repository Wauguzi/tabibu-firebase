/// Client kill switch for the region read. Default off; the defaults file
/// owns the value.
const regionReadEnabledKey = 'region_read_enabled';

/// The ask action shows for the pathologist on an accepted case when the
/// switch is on. The workspace screen supplies all three (role via
/// `RoleHelper`); a missing action hides the pill.
bool showRegionAsk({
  required bool isPathologist,
  required bool accepted,
  required bool enabled,
}) => isPathologist && accepted && enabled;
