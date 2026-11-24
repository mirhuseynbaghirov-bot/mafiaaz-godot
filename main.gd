extends Node3D

const URL := "https://pgmjtimnnmcttdvfqcnw.supabase.co"
const KEY := "sb_publishable_o_Xk7py1CvvLlU3imqwiOA_ke2Rr-HU"
const SAVE := "user://session.cfg"
const GOLD := Color(0.79, 0.64, 0.35)
const TXT := Color(0.93, 0.9, 0.84)

var token := ""
var refresh_token := ""
var me := {"id": "", "name": ""}
var room := {}
var screens := {}
var f := {}
var current := ""
var root: Control
var bg: ColorRect
var world: Node3D
var cam: Camera3D
var seats: Array = []
var orbit := 0.0
var poll_t := 0.0
var polling := false


func _ready() -> void:
	build_world()
	build_ui()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE) == OK:
		refresh_token = str(cfg.get_value("s", "rt", ""))
		if await do_refresh():
			enter_home()
			return
	show_screen("auth")


func _process(delta: float) -> void:
	orbit += delta * 0.2
	cam.position = Vector3(cos(orbit) * 9.0, 6.5, sin(orbit) * 9.0)
	cam.look_at(Vector3(0, 1, 0))
	if current == "lobby":
		poll_t += delta
		if poll_t > 2.0:
			poll_t = 0.0
			poll()


# ---------------------------------------------------------------- API

func api(method: int, path: String, body = null, use_token := true, retry := true) -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	var h := PackedStringArray(["apikey: " + KEY, "Content-Type: application/json"])
	if use_token and token != "":
		h.append("Authorization: Bearer " + token)
	var payload := "" if body == null else JSON.stringify(body)
	if req.request(URL + path, h, method, payload) != OK:
		req.queue_free()
		return {"code": 0, "data": null}
	var res = await req.request_completed
	req.queue_free()
	var code: int = res[1]
	var txt: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var data = null
	if txt != "":
		data = JSON.parse_string(txt)
	if code == 401 and use_token and retry and refresh_token != "":
		if await do_refresh():
			return await api(method, path, body, use_token, false)
	return {"code": code, "data": data}


func rpc(fn: String, body: Dictionary) -> Dictionary:
	return await api(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + fn, body)


func norm(d):
	if typeof(d) == TYPE_STRING:
		d = JSON.parse_string(d)
	if typeof(d) == TYPE_ARRAY:
		return d[0] if not d.is_empty() else null
	return d


func err_text(r: Dictionary) -> String:
	if typeof(r.data) == TYPE_DICTIONARY:
		for k in ["msg", "error_description", "message", "error"]:
			if r.data.has(k):
				return str(r.data[k])
	return "Xəta (" + str(r.code) + "). İnternet bağlantısını yoxlayın."


func do_refresh() -> bool:
	if refresh_token == "":
		return false
	var r = await api(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token", {"refresh_token": refresh_token}, false)
	return apply_session(r)


func apply_session(r: Dictionary) -> bool:
	if r.code != 200 or typeof(r.data) != TYPE_DICTIONARY or not r.data.has("access_token"):
		return false
	token = str(r.data["access_token"])
	refresh_token = str(r.data.get("refresh_token", refresh_token))
	var u: Dictionary = r.data.get("user", {})
	var md: Dictionary = u.get("user_metadata", {})
	var nm := str(md.get("username", ""))
	if nm == "":
		nm = str(u.get("email", "Oyunçu"))
	me = {"id": str(u.get("id", "")), "name": nm}
	var cfg := ConfigFile.new()
	cfg.set_value("s", "rt", refresh_token)
	cfg.save(SAVE)
	return true


# ---------------------------------------------------------------- UI helpers

func label(parent: Node, text: String, size := 0, color := TXT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 120)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func edit(parent: Node, ph: String, secret := false) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = ph
	e.secret = secret
	e.custom_minimum_size = Vector2(0, 110)
	parent.add_child(e)
	return e


func make_center(name: String) -> VBoxContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(c)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(900, 0)
	v.add_theme_constant_override("separation", 24)
	c.add_child(v)
	screens[name] = c
	return v


func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var th := Theme.new()
	th.default_font_size = 40
	root.theme = th
	layer.add_child(root)
	bg = ColorRect.new()
	bg.color = Color(0.043, 0.043, 0.051)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var a := make_center("auth")
	label(a, "MAFIAAZ", 80, GOLD)
	f["em"] = edit(a, "E-poçt")
	f["pw"] = edit(a, "Şifrə", true)
	f["un"] = edit(a, "İstifadəçi adı (yalnız qeydiyyatda)")
	button(a, "Daxil ol", login)
	button(a, "Qeydiyyat", signup)
	f["am"] = label(a, "", 32, Color(0.88, 0.54, 0.54))

	var h := make_center("home")
	label(h, "MAFIAAZ", 80, GOLD)
	f["hi"] = label(h, "", 44, GOLD)
	f["rname"] = edit(h, "Otaq adı")
	f["rname"].text = "GECƏ ŞƏHƏRİ"
	button(h, "Otaq yarat", create_room)
	f["jc"] = edit(h, "Otaq kodu")
	button(h, "Qoşul", join_room)
	button(h, "Çıx", logout)
	f["hm"] = label(h, "", 32, Color(0.88, 0.54, 0.54))

	var lob := Control.new()
	lob.set_anchors_preset(Control.PRESET_FULL_RECT)
	lob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lob)
	screens["lobby"] = lob
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 30)
	lob.add_child(top)
	f["lname"] = label(top, "", 48)
	f["lcode"] = label(top, "", 80, GOLD)
	f["lcount"] = label(top, "", 40)
	var bot := VBoxContainer.new()
	bot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 30)
	bot.add_theme_constant_override("separation", 16)
	lob.add_child(bot)
	f["lmsg"] = label(bot, "", 32)
	f["bbot"] = button(bot, "+ Bot əlavə et", add_bot)
	button(bot, "Otaqdan çıx", leave)


func show_screen(n: String) -> void:
	current = n
	for k in screens:
		screens[k].visible = (k == n)
	bg.visible = n != "lobby"
	world.visible = n == "lobby"
	poll_t = 0.0


# ---------------------------------------------------------------- Auth / rooms

func login() -> void:
	f["am"].text = "..."
	var r = await api(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=password", {"email": f["em"].text.strip_edges(), "password": f["pw"].text}, false)
	if apply_session(r):
		enter_home()
	else:
		f["am"].text = err_text(r)


func signup() -> void:
	var u: String = f["un"].text.strip_edges()
	if u.length() < 3:
		f["am"].text = "İstifadəçi adı ən azı 3 simvol olmalıdır."
		return
	var r = await api(HTTPClient.METHOD_POST, "/auth/v1/signup", {"email": f["em"].text.strip_edges(), "password": f["pw"].text, "data": {"username": u}}, false)
	if apply_session(r):
		enter_home()
	elif r.code == 200:
		f["am"].text = "Qeydiyyat tamam. E-poçtu təsdiqləyib daxil olun."
	else:
		f["am"].text = err_text(r)


func logout() -> void:
	token = ""
	refresh_token = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	show_screen("auth")


func enter_home() -> void:
	f["hi"].text = me["name"]
	f["hm"].text = ""
	show_screen("home")


func create_room() -> void:
	f["hm"].text = ""
	var r = await rpc("create_room", {"p_room_name": f["rname"].text.strip_edges(), "p_max_players": 8, "p_language": "az"})
	var d = norm(r.data)
	if r.code >= 300 or typeof(d) != TYPE_DICTIONARY or not d.has("room_code"):
		f["hm"].text = err_text(r)
		return
	await enter_room(str(d["room_code"]))


func join_room() -> void:
	f["hm"].text = ""
	var code: String = f["jc"].text.strip_edges().to_upper()
	if code == "":
		f["hm"].text = "Kodu yazın."
		return
	var pw = await rpc("room_requires_password", {"p_room_code": code})
	if typeof(pw.data) == TYPE_BOOL and pw.data:
		f["hm"].text = "Parollu otaqlar hələlik dəstəklənmir."
		return
	var r = await rpc("join_room", {"p_room_code": code})
	var d = norm(r.data)
	var failed: bool = r.code >= 300 or (typeof(d) == TYPE_DICTIONARY and d.get("success", true) == false)
	if failed:
		var m := ""
		if typeof(d) == TYPE_DICTIONARY:
			m = str(d.get("message", ""))
		f["hm"].text = m if m != "" else err_text(r)
		return
	await enter_room(code)


func enter_room(code: String) -> void:
	var r = await api(HTTPClient.METHOD_GET, "/rest/v1/rooms?select=id,room_code,room_name,host_id,max_players,status&room_code=eq." + code.uri_encode())
	if r.code != 200 or typeof(r.data) != TYPE_ARRAY or r.data.is_empty():
		f["hm"].text = "Otaq tapılmadı."
		return
	room = r.data[0]
	f["lname"].text = str(room["room_name"])
	f["lcode"].text = str(room["room_code"])
	f["lmsg"].text = ""
	build_seats(int(room.get("max_players", 8)))
	show_screen("lobby")
	await poll()


func seatnum(p: Dictionary) -> int:
	var s = p.get("seat_number")
	return int(s) if s != null else 99


func poll() -> void:
	if polling or room.is_empty():
		return
	polling = true
	var id := str(room["id"])
	var rr = await api(HTTPClient.METHOD_GET, "/rest/v1/rooms?select=status,host_id,max_players&id=eq." + id)
	var q = await api(HTTPClient.METHOD_GET, "/rest/v1/room_players?select=user_id,seat_number,is_alive,username&room_id=eq." + id)
	if q.code != 200:
		q = await api(HTTPClient.METHOD_GET, "/rest/v1/room_players?select=user_id,seat_number,is_alive&room_id=eq." + id)
	var b = await api(HTTPClient.METHOD_GET, "/rest/v1/room_bots?select=id,bot_name,seat_number,is_alive&room_id=eq." + id)
	polling = false
	if room.is_empty():
		return
	if rr.code == 200 and typeof(rr.data) == TYPE_ARRAY and not rr.data.is_empty():
		room.merge(rr.data[0], true)
	var list: Array = []
	if q.code == 200 and typeof(q.data) == TYPE_ARRAY:
		for p in q.data:
			var nm := ""
			if p.get("username") != null:
				nm = str(p["username"])
			if nm == "" and str(p["user_id"]) == me["id"]:
				nm = me["name"]
			if nm == "":
				nm = "Oyunçu"
			list.append({"seat": seatnum(p), "alive": p.get("is_alive", true) != false, "name": nm})
	if b.code == 200 and typeof(b.data) == TYPE_ARRAY:
		for p in b.data:
			list.append({"seat": seatnum(p), "alive": p.get("is_alive", true) != false, "name": str(p["bot_name"])})
	list.sort_custom(func(x, y): return x["seat"] < y["seat"])
	set_seats(list)
	f["lcount"].text = str(list.size()) + "/" + str(room.get("max_players", 8))
	var host := str(room.get("host_id", "")) == me["id"]
	var waiting := str(room.get("status", "")) == "waiting"
	f["bbot"].visible = host and waiting
	if not waiting:
		f["lmsg"].text = "Oyun başlayıb. Oyun ekranı növbəti yeniləmədə əlavə olunacaq."
	elif host:
		f["lmsg"].text = "Oyunçuları gözləyin."
	else:
		f["lmsg"].text = "Host oyunu başladacaq."


func add_bot() -> void:
	if room.is_empty():
		return
	var r = await rpc("add_room_bot", {"p_room_id": room["id"]})
	var d = norm(r.data)
	if r.code >= 300 or (typeof(d) == TYPE_DICTIONARY and d.get("success", true) == false):
		f["lmsg"].text = err_text(r)
	else:
		poll()


func leave() -> void:
	if room.is_empty():
		show_screen("home")
		return
	var id := str(room["id"])
	room = {}
	show_screen("home")
	await api(HTTPClient.METHOD_DELETE, "/rest/v1/room_players?room_id=eq." + id + "&user_id=eq." + str(me["id"]))


# ---------------------------------------------------------------- 3D

func mesh(parent: Node3D, m: Mesh, c: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.roughness = 0.8
	mi.material_override = mt
	mi.position = pos
	parent.add_child(mi)
	return mi


func cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	return m


func build_world() -> void:
	world = Node3D.new()
	add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.045, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.68)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.85, 0.6)
	world.add_child(sun)
	mesh(world, cyl(14, 14, 0.1), Color(0.1, 0.09, 0.08), Vector3(0, -0.05, 0))
	mesh(world, cyl(2.2, 2.2, 0.18), Color(0.29, 0.18, 0.1), Vector3(0, 1.0, 0))
	mesh(world, cyl(0.35, 0.5, 1.0), Color(0.16, 0.1, 0.05), Vector3(0, 0.5, 0))
	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = 60
	add_child(cam)
	cam.position = Vector3(0, 6.5, 9)
	cam.look_at(Vector3(0, 1, 0))


func build_seats(n: int) -> void:
	for s in seats:
		s["node"].queue_free()
	seats.clear()
	for i in n:
		var ang := TAU * i / n
		var g := Node3D.new()
		g.position = Vector3(cos(ang) * 3.3, 0, sin(ang) * 3.3)
		world.add_child(g)
		var bm := BoxMesh.new()
		bm.size = Vector3(0.8, 0.9, 0.8)
		mesh(g, bm, Color(0.17, 0.11, 0.06), Vector3(0, 0.45, 0))
		var fig := Node3D.new()
		g.add_child(fig)
		var col := Color.from_hsv(float(i) / n, 0.35, 0.6)
		var cm := CapsuleMesh.new()
		cm.radius = 0.3
		cm.height = 1.0
		var body := mesh(fig, cm, col, Vector3(0, 1.3, 0))
		var sm := SphereMesh.new()
		sm.radius = 0.24
		sm.height = 0.48
		mesh(fig, sm, Color(0.85, 0.7, 0.56), Vector3(0, 2.0, 0))
		var lbl := Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.pixel_size = 0.006
		lbl.font_size = 64
		lbl.outline_size = 12
		lbl.position = Vector3(0, 2.7, 0)
		fig.add_child(lbl)
		fig.visible = false
		seats.append({"node": g, "fig": fig, "body": body, "lbl": lbl, "col": col})


func set_seats(list: Array) -> void:
	for i in seats.size():
		var s = seats[i]
		if i >= list.size():
			s["fig"].visible = false
			continue
		var p = list[i]
		var alive: bool = p["alive"]
		s["fig"].visible = true
		s["fig"].rotation_degrees.z = 0.0 if alive else 85.0
		s["fig"].position.y = 0.0 if alive else 0.5
		s["body"].material_override.albedo_color = s["col"] if alive else Color(0.33, 0.33, 0.33)
		s["lbl"].text = ("" if alive else "† ") + str(p["name"])
