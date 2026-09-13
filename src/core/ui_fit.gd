extends Node
## Warns when a visible text box is showing less than it contains.
##
## Registered as the `UiFit` autoload, and does nothing at all outside a debug
## build. Three separate menus have shipped with their last row clipped off the
## bottom of the panel -- the learn prompt, the pause menu, the debug menu --
## and in every case the symptom was invisible in code, invisible to every
## assertion, and obvious the moment somebody looked at a screenshot.
##
## So this looks, every frame, at every RichTextLabel that is actually on
## screen, and says so when the text is taller than the box holding it. It
## needs no cooperation from the menus, which is the whole point: the rule that
## kept being broken was one written in a document, and the fix for that is not
## a better document.

## Scanning every frame is wasteful and pointless -- a clipped panel stays
## clipped. Once every this many frames is plenty to catch it on the first
## screen it appears on.
const SCAN_INTERVAL := 20

## Sub-pixel rounding makes exact comparisons noisy; only report real clipping.
const SLACK := 1.0

## Node paths already reported, so one bad panel does not print every scan.
var _seen := {}
var _frames := 0


func _ready() -> void:
	if not OS.is_debug_build():
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	_frames += 1
	if _frames % SCAN_INTERVAL != 0:
		return
	var scene := get_tree().current_scene
	if scene != null:
		_scan(scene)


func _scan(node: Node) -> void:
	if node is RichTextLabel:
		_check(node)
	for child in node.get_children():
		_scan(child)


func _check(label: RichTextLabel) -> void:
	# A scrolling box is allowed to hold more than it shows; that is what
	# scrolling is for. Everything in this project switches it off.
	if label.scroll_active or not label.is_visible_in_tree() or label.text.is_empty():
		return
	var overflow := label.get_content_height() - label.size.y
	if overflow <= SLACK:
		return

	var path := str(label.get_path())
	if _seen.has(path):
		return
	_seen[path] = true
	push_warning(
		"UiFit: %s is showing %.0fpx less than it contains (box %.0f, text %.0f). "
		% [path, overflow, label.size.y, label.get_content_height()]
		+ "Something is clipped off the bottom -- widen the panel or cut a row.")
