# Notification Material Visibility Synchronization

2026-11-13. The supplied 4.4-second device recording shows the notification
list moving out and back into view. Some card backgrounds and content fade
at different times. The recording alone cannot identify every native cause.

The replacement was a sibling of the native material, copying its alpha only
during layout. Native alpha/hidden changes between layouts could leave it stale,
and the stored hidden state only tracked reveals. The new binding forwards
MTMaterialView alpha and hidden requests to its managed replacement in the same
UIKit call. Unmanaged materials pass through. Our own suppression is distinguished
from native hidden requests; detach restores the latest native hidden state.
Empty notification bounds temporarily suspend the replacement without discarding
that state. No timer, frame polling, geometry or slider change is introduced.

UIKit validation uses the production binding with a material view double. It
exercises alpha and hide/reveal changes without layout, empty-bounds suspension,
restore/detach, and compares in-flight opacity with a normal UIKit reference
view. This does not execute iOS 16 SpringBoard's private material implementation.
The package is a targeted candidate; reproducing the original swipe on the
user's device remains the acceptance check.
