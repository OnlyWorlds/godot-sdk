class_name OWElementCore
extends RefCounted
## The data under every model: the Dictionary an element file parsed to, and the typed views the generated
## properties read and write through.
##
## The dictionary is the truth. Key order stays as received, keys the schema does not name ([code]created_at[/code],
## [code]change_seq[/code], [code]x_*[/code]) stay, and [code]null[/code] versus [code]""[/code] stays, so an element
## written back carries everything it was read with. Godot reads every JSON number as a float; the views turn an
## integer field back into an [int], and [OWJson] writes an integral float as an integer (folder spec section 5).

var _data: Dictionary
var _type: StringName = &""
## True once a typed property was set (or [method mark_edited] was called): the file is then written in the spec's
## section 5 form instead of the bytes it was read from.
var edited := false
## Where the element was read from, inside its world ("elements/character/ana--0000ab01.json"); "" for a new one.
var source_path := ""
## The file's bytes as read: what an unedited element is written back as.
var source_bytes: PackedByteArray

func _init(data: Dictionary = {}) -> void:
	_data = data

## The element type's slug ([code]"character"[/code]); each model returns its own.
func get_type() -> StringName:
	return _type

## The data itself, live: a change made here is a change to the element. Call [method mark_edited] after one.
func to_dict() -> Dictionary:
	return _data

## Say the element changed through [method to_dict], so it is written in the spec's form, not as read.
func mark_edited() -> void:
	edited = true

## A key's raw value, or [param default] when it is absent.
func get_value(key: String, default: Variant = null) -> Variant:
	return _data.get(key, default)

## Set any key, a schema field or an extension ([code]x_*[/code]); it is appended when new.
func set_value(key: String, value: Variant) -> void:
	_data[key] = value
	edited = true

# -- views, used by the generated properties ------------------------------------------------------------------------

func _str(key: String) -> String:
	var v = _data.get(key)
	return v if v is String else ""           # absent, null and "" are one unset string (spec section 5)

func _set_str(key: String, v: String) -> void:
	_data[key] = v
	edited = true

func _int(key: String) -> Variant:            # an int, or null for unset
	var v = _data.get(key)
	if v is float:
		return int(v)                         # JSON numbers arrive as float
	if v is int:
		return v
	return null

func _set_int(key: String, v: Variant) -> void:
	if v != null and not (v is int):
		push_error("OnlyWorlds: %s takes an int or null, not %s" % [key, type_string(typeof(v))])
		return
	_data[key] = v
	edited = true

func _bool(key: String) -> bool:
	return _data.get(key) == true

func _set_bool(key: String, v: bool) -> void:
	_data[key] = v
	edited = true

func _id(key: String) -> String:
	var v = _data.get(key)
	return v if v is String else ""

func _set_id(key: String, v: String) -> void:
	_data[key] = v if v != "" else null       # a single link: an id, or null for unset
	edited = true

func _ids(key: String) -> PackedStringArray:
	var v = _data.get(key)
	var out := PackedStringArray()
	if v is Array:
		for x in v:
			if x is String:
				out.append(x)
	return out                                # absent and [] are one empty list

func _set_ids(key: String, v: PackedStringArray) -> void:
	_data[key] = Array(v)
	edited = true

func _list(key: String) -> Array:
	var v = _data.get(key)
	return v if v is Array else []

func _set_list(key: String, v: Array) -> void:
	_data[key] = v
	edited = true
