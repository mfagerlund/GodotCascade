extends RefCounted

## One authoritative built-in GXML element/attribute schema shared by runtime
## validation and editor tooling. Registered native components remain extensible.

const ALIASES := {"input": "TextInput", "radio": "RadioButton"}

const ELEMENT_ATTRIBUTES := {
	"Page": [],
	"Row": [],
	"Column": [],
	"Panel": [],
	"Stack": [],
	"Grid": [],
	"Scroll": [],
	"Label": ["text"],
	"Button": ["text", "disabled", "on-pressed"],
	"Checkbox": ["text", "disabled", "checked", "bind-checked", "on-toggled"],
	"RadioButton": ["text", "disabled", "checked", "group", "bind-checked", "on-toggled"],
	"Switch": ["text", "disabled", "checked", "bind-checked", "on-toggled"],
	"Select": ["disabled", "selected", "bind-selected", "on-selection-changed"],
	"Option": ["id", "class", "text", "value", "disabled"],
	"Slider": ["disabled", "min", "max", "value", "step", "bind-value", "on-value-changed"],
	"Progress": ["min", "max", "value"],
	"TextInput": ["text", "disabled", "bind-text", "placeholder", "multiline", "read-only", "secret", "required", "pattern", "error-message", "max-length"],
	"Image": ["src"],
	"Table": [],
	"TableHeader": [],
	"TableBody": [],
	"TableRow": [],
	"TableHeaderCell": ["text"],
	"TableCell": ["text"],
	"Repeat": ["items", "key", "virtual", "item-height", "overscan"],
	"Component": ["name"],
	"Param": ["name", "type", "required", "default"],
	"Slot": ["name"],
	"Bindings": ["class", "namespace", "document", "output"],
	"Binding": ["name", "type", "get", "set"],
	"Formatter": ["name", "input", "output"],
	"Parser": ["name", "input", "output"],
	"Using": ["namespace"],
}

const COMMON_ATTRIBUTES := [
	"id", "class", "visible", "accessible-label", "accessible-description",
	"if", "tab-index", "autofocus", "focus-trap", "slot",
]
const NON_VISUAL_ELEMENTS := ["Option", "Component", "Param", "Slot", "Bindings", "Binding", "Formatter", "Parser", "Using"]
const FOCUS_TRAP_ELEMENTS := ["Page", "Row", "Column", "Panel", "Stack", "Grid", "Scroll", "Table", "TableHeader", "TableBody", "TableRow", "TableHeaderCell", "TableCell", "Repeat"]
const GENERATED_BINDING_ATTRIBUTES := ["format-text", "parse-text", "format-checked", "parse-checked", "format-value", "parse-value", "format-selected", "parse-selected", "format-disabled", "format-visible", "format-min", "format-max"]


static func canonical_element(tag_name: String) -> String:
	var normalized := tag_name.to_lower()
	if ALIASES.has(normalized):
		return ALIASES[normalized]
	for candidate in ELEMENT_ATTRIBUTES:
		if str(candidate).to_lower() == normalized:
			return candidate
	return ""


static func is_builtin(tag_name: String) -> bool:
	return not canonical_element(tag_name).is_empty()


static func is_attribute_allowed(tag_name: String, attribute_name: String) -> bool:
	var name := attribute_name.to_lower()
	if attribute_name != name:
		return false
	if name.begins_with("__"):
		return false
	var canonical := canonical_element(tag_name)
	if canonical.is_empty():
		return true
	if canonical not in NON_VISUAL_ELEMENTS and (name.begins_with("on-") or name.begins_with("bind-") or name in GENERATED_BINDING_ATTRIBUTES):
		return true
	if name in COMMON_ATTRIBUTES and canonical not in NON_VISUAL_ELEMENTS:
		return true
	return name in ELEMENT_ATTRIBUTES.get(canonical, [])


static func attributes_for(tag_name: String) -> PackedStringArray:
	var canonical := canonical_element(tag_name)
	var result := PackedStringArray() if canonical in NON_VISUAL_ELEMENTS else PackedStringArray(COMMON_ATTRIBUTES)
	for attribute_name in ELEMENT_ATTRIBUTES.get(canonical, []):
		if attribute_name not in result:
			result.append(attribute_name)
	return result


static func supports_generated_bindings(tag_name: String) -> bool:
	var canonical := canonical_element(tag_name)
	return not canonical.is_empty() and canonical not in NON_VISUAL_ELEMENTS


static func supports_focus_trap(tag_name: String) -> bool:
	return canonical_element(tag_name) in FOCUS_TRAP_ELEMENTS
