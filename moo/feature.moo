@@ @mcp any any any
":@mcp(STR request_json) => NONE";
"Dispatch one feature request under the attached programmer's authority.";
if (player != this.mcp_programmer || caller != player || caller_perms() != player || !player.programmer)
  return notify(player, "MOO-MCP " + generate_json(["ok" -> false, "error" -> ["code" -> "E_PERM", "message" -> "Permission denied."]]));
endif
id = "";
try
  if (length(argstr) > 8192)
    raise(E_INVARG, "Request exceeds 8192 characters.");
  endif
  request = parse_json(argstr);
  if (typeof(request) != MAP || !maphaskey(request, "id") || typeof(request["id"]) != STR || length(request["id"]) > 80)
    raise(E_INVARG, "Expected a request map with a string id.");
  endif
  id = request["id"];
  {operation, params} = {request["op"], request["params"]};
  if (typeof(operation) != STR || typeof(params) != MAP)
    raise(E_INVARG, "Expected a string operation and a parameter map.");
  endif
  result = this:dispatch(operation, params);
  response = generate_json(["id" -> id, "ok" -> true, "result" -> result], "common-subset", true);
  if (length(response) > 262144)
    raise(E_QUOTA, "Response exceeds 262144 characters; use a narrower query.");
  endif
except e (ANY)
  response = generate_json(["id" -> id, "ok" -> false, "error" -> ["code" -> toliteral(e[1]), "message" -> e[2]]], "common-subset", true);
endtry
notify(player, "MOO-MCP " + response);

@@ dispatch this none this
":dispatch(STR operation, MAP params) => ANY";
if (caller != this || caller_perms() != this.mcp_programmer || player != this.mcp_programmer)
  raise(E_PERM);
endif
{op, params} = args;
if (op == "hello")
  ops = {"hello", "verb-data", "verbs-json", "props-json", "show-json", "contents", "location", "cored_json", "defines_verb_json", "defines_prop_json", "search-json", "run_moo_code_search", "prop-search"};
  if (this.mcp_eval_enabled)
    ops = {@ops, "run_moo_eval"};
  endif
  return ["protocol" -> 1, "server" -> server_version(), "feature" -> tostr(this), "programmer" -> tostr(player), "operations" -> ops, "regex" -> `!!function_info("pcre_match") ! E_INVARG => false'];
elseif (op in {"defines_verb_json", "defines_prop_json", "search-json", "run_moo_code_search", "prop-search"})
  return this:search(op, params);
elseif (op == "cored_json")
  return this:corerefs(`params["arg"] ! E_RANGE => ""');
elseif (op == "run_moo_eval" && this.mcp_eval_enabled)
  {ok, value} = eval(params["code"]);
  return ["compiled" -> !!ok, "value" -> this:json_value(value)];
elseif (!(op in {"verb-data", "verbs-json", "props-json", "show-json", "contents", "location"}))
  raise(E_INVARG, "Unknown or disabled operation.");
endif
object = this:resolve_object(params["object"]);
if (op == "verb-data")
  return this:verb_data(object, params["verb"], `params["mode"] ! E_RANGE => "resolved"');
elseif (op == "verbs-json")
  result = {};
  names = verbs(object);
  for slot in [1..length(names)]
    result = {@result, this:verb_metadata(object, slot)};
  endfor
  return ["object" -> this:object_summary(object), "verbs" -> result];
elseif (op == "props-json")
  return ["object" -> this:object_summary(object), "props" -> this:property_rows(object)];
elseif (op == "show-json")
  return ["object" -> this:object_summary(object), "contents" -> this:list_contents(object), "ancestors" -> this:json_value(ancestors(object)), "props" -> this:property_rows(object, true, `params["property"] ! E_RANGE => ""')];
elseif (op == "contents")
  return ["object" -> this:object_summary(object), "contents" -> this:list_contents(object)];
else
  chain = {};
  loc = object.location;
  while (valid(loc) && !(loc in chain))
    chain = {@chain, loc};
    loc = loc.location;
  endwhile
  rows = {};
  for loc in (chain)
    rows = {@rows, this:object_summary(loc)};
  endfor
  return ["object" -> this:object_summary(object), "location" -> rows];
endif

@@ resolve_object this none this
":resolve_object(STR reference) => OBJ";
if (caller != this || caller_perms() != this.mcp_programmer || player != this.mcp_programmer)
  raise(E_PERM);
endif
{reference} = args;
if (typeof(reference) != STR || length(reference) < 2)
  raise(E_INVARG, "Expected #number or a system object reference.");
elseif (reference[1] == "$")
  object = #0.(reference[2..$]);
elseif (reference[1] == "#" && match(reference[2..$], "^[0-9]+$"))
  object = toobj(reference);
else
  raise(E_INVARG, "Expected #number or a system object reference.");
endif
if (typeof(object) != OBJ || !valid(object))
  raise(E_INVARG, "Expected a valid numbered object.");
endif
return object;

@@ object_summary this none this
":object_summary(OBJ object) => MAP";
if (caller != this || caller_perms() != this.mcp_programmer || player != this.mcp_programmer)
  raise(E_PERM);
endif
{object} = args;
return ["object" -> tostr(object), "id" -> toint(object), "name" -> object.name, "owner" -> tostr(object.owner), "parents" -> this:json_value(parents(object)), "location" -> tostr(object.location), "flags" -> ["player" -> !!is_player(object), "programmer" -> !!object.programmer, "wizard" -> !!object.wizard, "r" -> !!object.r, "w" -> !!object.w, "f" -> !!object.f]];

@@ list_contents this none this
":list_contents(OBJ object) => LIST";
if (caller != this || caller_perms() != this.mcp_programmer || player != this.mcp_programmer)
  raise(E_PERM);
endif
{object} = args;
rows = {};
for item in (object.contents)
  if (valid(item))
    rows = {@rows, this:object_summary(item)};
  endif
endfor
return rows;

@@ verb_metadata this none this
":verb_metadata(OBJ object, INT slot) => MAP";
if (caller != this || caller_perms() != this.mcp_programmer || player != this.mcp_programmer)
  raise(E_PERM);
endif
{object, slot} = args;
{owner, perms, names} = verb_info(object, slot);
return ["verb_index" -> slot, "owner" -> tostr(owner), "perms" -> perms, "names" -> explode(names, " "), "args" -> verb_args(object, slot)];

@@ verb_data this none this
":verb_data(OBJ object, STR|INT selector, STR mode) => MAP";
if (caller != this || caller_perms() != this.mcp_programmer || player != this.mcp_programmer)
  raise(E_PERM);
endif
{object, selector, mode} = args;
definer = object;
slot = selector;
resolved = 0;
if (typeof(selector) == STR)
  if (mode == "resolved")
    resolved = respond_to(object, selector);
    if (resolved == 1)
      raise(E_PERM, "Callable verb metadata is unreadable.");
    elseif (resolved)
      {definer, aliases} = resolved;
    endif
  elseif (mode != "local")
    raise(E_INVARG, "Expected local or resolved verb lookup.");
  endif
  matches = {};
  names = verbs(definer);
  for i in [1..length(names)]
    if (typeof(resolved) == LIST ? equal(names[i], aliases) && index(verb_info(definer, i)[2], "x") | selector in explode(names[i], " "))
      matches = {@matches, i};
    endif
  endfor
  if (!matches)
    raise(E_VERBNF, "Verb not found. Use a local slot for a wildcard or noncallable definition.");
  elseif (length(matches) > 1)
    raise(E_INVARG, "Ambiguous verb selector. Use a local slot.");
  endif
  slot = matches[1];
elseif (typeof(selector) != INT || selector < 1)
  raise(E_INVARG, "Expected a verb name or a positive local slot.");
endif
data = this:verb_metadata(definer, slot);
source = verb_code(definer, slot, false, true);
data["query_object"] = this:object_summary(object);
data["defined_on"] = this:object_summary(definer);
data["source"] = ["code_lines" -> source, "line_count" -> length(source)];
return data;

@@ property_rows this none this
":property_rows(OBJ object, ?BOOL values=false, ?STR property_name) => MAP";
if (caller != this || caller_perms() != this.mcp_programmer || player != this.mcp_programmer)
  raise(E_PERM);
endif
{object, ?values = false, ?property_name = ""} = args;
rows = [];
if (property_name)
  names = {property_name};
else
  names = {};
  for defining in ({object, @ancestors(object)})
    for name in (`properties(defining) ! E_PERM => {}')
      names = setadd(names, name);
    endfor
  endfor
endif
direct = `properties(object) ! E_PERM => {}';
for name in (names)
  try
    {owner, perms} = property_info(object, name);
    row = ["owner" -> tostr(owner), "permissions" -> perms, "clear" -> !!is_clear_property(object, name), "local" -> !!(name in direct)];
    if (values)
      row["value"] = this:json_value(object.(name));
    endif
    rows[name] = row;
  except (E_PERM)
    rows[name] = ["error" -> "E_PERM"];
  endtry
endfor
return rows;

@@ corerefs this none this
":corerefs(STR query) => LIST";
if (caller != this || caller_perms() != this.mcp_programmer || player != this.mcp_programmer)
  raise(E_PERM);
endif
{query} = args;
target = #-1;
if (query && query[1] == "#")
  target = this:resolve_object(query);
endif
refs = {};
for name in (properties(#0))
  value = `#0.(name) ! E_PERM => #-1';
  if (typeof(value) == OBJ && valid(value) && (valid(target) ? value == target | !query || index("$" + name, query)))
    refs = {@refs, ["reference" -> "$" + name, "object" -> tostr(value)]};
  endif
endfor
return refs;

@@ json_value this none this
":json_value(ANY value, ?INT depth=0) => ANY";
if (caller != this || caller_perms() != this.mcp_programmer || player != this.mcp_programmer)
  raise(E_PERM);
endif
{value, ?depth = 0} = args;
kind = typeof(value);
if (depth >= 20)
  return ["type" -> "truncated"];
elseif (kind == OBJ || kind == ERR)
  return toliteral(value);
elseif (kind == WAIF || kind == ANON)
  return ["type" -> kind == WAIF ? "waif" | "anonymous"];
elseif (kind == LIST)
  result = {};
  for item in (value)
    result = {@result, this:json_value(item, depth + 1)};
  endfor
  return result;
elseif (kind == MAP)
  entries = {};
  result = [];
  string_keys = true;
  for item, key in (value)
    item = this:json_value(item, depth + 1);
    if (typeof(key) == STR)
      result[key] = item;
    else
      string_keys = false;
    endif
    entries = {@entries, {this:json_value(key, depth + 1), item}};
  endfor
  return string_keys ? result | ["type" -> "map", "entries" -> entries];
endif
return value;

@@ search this none this
":search(STR operation, MAP params) => MAP";
if (caller != this || caller_perms() != this.mcp_programmer || player != this.mcp_programmer)
  raise(E_PERM);
endif
{op, params} = args;
limit = `params["limit"] ! E_RANGE => 50';
cursor = `params["cursor"] ! E_RANGE => 0';
offset = `params["offset"] ! E_RANGE => 0';
scope = `params["scope"] ! E_RANGE => ""';
recursive = `params["include_descendants"] ! E_RANGE => false';
count_only = `params["count_only"] ! E_RANGE => false';
pattern = `params["pattern"] ! E_RANGE => ""';
regex = `params["match_type"] ! E_RANGE => "simple"';
type = `params["type"] ! E_RANGE => "objects"';
if (typeof(limit) != INT || limit < 1 || limit > 200 || typeof(cursor) != INT || cursor < 0 || typeof(offset) != INT || offset < 0 || (offset && count_only) || typeof(pattern) != STR || length(pattern) > 512 || !(regex in {"simple", "regex"}))
  raise(E_INVARG, "Invalid scan arguments.");
endif
if (regex == "regex")
  if (!`function_info("pcre_match") ! E_INVARG => 0')
    raise(E_INVARG, "Regex is unavailable on this server.");
  endif
  pcre_match("", pattern);
endif
if (op != "search-json" && !pattern)
  raise(E_INVARG, "A nonempty pattern is required.");
elseif (op == "prop-search" && !scope)
  raise(E_INVARG, "Property search requires a scope.");
endif
root = scope ? this:resolve_object(scope) | #-1;
named = `params["name"] ! E_RANGE => ""';
parent_ref = `params["parent"] ! E_RANGE => ""';
location_ref = `params["location"] ! E_RANGE => ""';
ancestor = parent_ref ? this:resolve_object(parent_ref) | #-1;
place = location_ref && location_ref != "#-1" ? this:resolve_object(location_ref) | #-1;
if (!(type in {"objects", "things", "players", "players-all"}) && !(type in {"rooms", "exits"} && maphaskey(this.mcp_prototypes, type)))
  raise(E_INVARG, "Unsupported object search type.");
endif
prototype = `this.mcp_prototypes[type] ! E_RANGE => #-1';
results = {};
matches = 0;
scanned = 0;
last = scope && !recursive ? toint(root) | toint(max_object());
start = scope && !recursive ? max(cursor, toint(root)) | cursor;
stop = min(last, start + 511);
next_cursor = start;
next_offset = 0;
for number in [start..stop]
  next_cursor = number + 1;
  object = toobj(number);
  if (!valid(object) || valid(root) && object != root && !isa(object, root))
    continue;
  endif
  if (ticks_left() < 5000 || seconds_left() < 2)
    suspend(0);
  endif
  scanned = scanned + 1;
  hits = {};
  seen_hits = 0;
  skip_hits = number == cursor ? offset | 0;
  try
    if (op == "search-json")
      if ((!named || index(object.name, named)) && (!parent_ref || isa(object, ancestor)) && (!location_ref || object.location == place) && (!(type in {"players", "players-all"}) || is_player(object)) && (!valid(prototype) || isa(object, prototype)))
        hits = {this:object_summary(object)};
      endif
    elseif (op == "defines_prop_json")
      if (pattern in properties(object))
        property_info(object, pattern);
        hits = {this:object_summary(object)};
      endif
    elseif (op == "defines_verb_json")
      verb_info(object, pattern);
      hits = {this:object_summary(object)};
    elseif (op == "run_moo_code_search")
      names = verbs(object);
      for slot in [1..length(names)]
        lines = `verb_code(object, slot, false, true) ! E_PERM, E_VERBNF => {}';
        for line in [1..length(lines)]
          if (ticks_left() < 5000 || seconds_left() < 2)
            suspend(0);
          endif
          if (this:matches(lines[line], pattern, regex))
            seen_hits = seen_hits + 1;
          else
            continue;
          endif
          if (!count_only && seen_hits > skip_hits)
            hits = {@hits, ["object" -> tostr(object), "verb" -> names[slot], "verb_index" -> slot, "line" -> line, "source_line" -> lines[line], "before_line" -> `lines[line - 1] ! E_RANGE => ""', "after_line" -> `lines[line + 1] ! E_RANGE => ""']};
          endif
          if (!count_only && length(hits) + matches >= limit)
            break slot;
          endif
        endfor
      endfor
    else
      for name in (properties(object))
        try
          value = toliteral(object.(name));
          if (this:matches(value, pattern, regex))
            seen_hits = seen_hits + 1;
            if (!count_only && seen_hits > skip_hits)
              hits = {@hits, ["object" -> tostr(object), "property_name" -> name, "value" -> value[1..min(200, $)], "truncated" -> length(value) > 200]};
            endif
          endif
        except (E_PERM, E_PROPNF)
        endtry
        if (!count_only && length(hits) + matches >= limit)
          break;
        endif
      endfor
    endif
  except (E_PERM, E_VERBNF, E_INVARG)
  endtry
  matches = matches + (count_only && op in {"run_moo_code_search", "prop-search"} ? seen_hits | length(hits));
  if (!count_only)
    results = {@results, @hits};
    if (matches >= limit)
      if (op in {"run_moo_code_search", "prop-search"})
        next_cursor = number;
        next_offset = skip_hits + length(hits);
      endif
      break;
    endif
  endif
endfor
return ["results" -> results, "meta" -> ["scanned_object_count" -> scanned, "total_matches" -> matches, "next_cursor" -> next_cursor <= last ? next_cursor | -1, "next_offset" -> next_offset, "truncated" -> next_cursor <= last]];

@@ matches this none this
":matches(STR value, STR pattern, STR match_type) => BOOL";
if (caller != this || caller_perms() != this.mcp_programmer || player != this.mcp_programmer)
  raise(E_PERM);
endif
{value, pattern, kind} = args;
return kind == "regex" ? !!pcre_match(value, pattern) | !!index(value, pattern);
