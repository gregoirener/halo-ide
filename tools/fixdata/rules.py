#!/usr/bin/env python3
"""The mistakes Halo fixes: wrong API names, habits from other languages and
classic typos, per language. Writes Resources/Fixes/rules.json.

    python3 tools/fixdata/rules.py

Each rule is an ICU regular expression and a replacement template ($1…):
  auto       fix it the moment it's typed (otherwise only suggest it)
  why        the one-line explanation shown next to the suggestion
  undefined  capture group that must not be a name the file defines itself
  module     Python module the rule is about (skipped if the file redefines it)
  when       regex that must appear somewhere in the file
  unless     regex that must not appear anywhere in the file
Matches must start in code (not in a string or comment).
"""
import json, os, re

LANGS = {}

def rules(lang):
    return LANGS.setdefault(lang, {"rules": []})["rules"]

def R(lang, rid, match, to, why, auto=False, undefined=None, module=None, when=None, unless=None):
    rule = {"id": f"{lang}.{rid}", "match": match, "with": to, "why": why}
    if auto: rule["auto"] = True
    if undefined: rule["undefined"] = undefined
    if module: rule["module"] = module
    if when: rule["when"] = when
    if unless: rule["unless"] = unless
    rules(lang).append(rule)

def alt(words):
    return "|".join(sorted(set(words), key=lambda w: (-len(w), w)))

# ---------------------------------------------------------------- Python

def py_mod(module, wrong, right, why, auto=True, call=True):
    """module.<one of wrong>( → module.right("""
    look = r"(?=\s*\()" if call else r"(?![\w(])"
    R("python", f"{module}.{right}.{wrong[0]}", rf"(?<![\w.]){re.escape(module)}\.(?:{alt(wrong)}){look}",
      f"{module}.{right}", why, auto, module=module.split(".")[0])

py_mod("time", "wait delay pause sleepFor sleep_for waitFor wait_for sleeep slp sleepSeconds".split(), "sleep",
       "Python pauses with time.sleep(seconds)")
py_mod("time", "now current currentTime current_time timestamp getTime get_time time_now timeNow seconds".split(), "time",
       "time.time() gives the current time in seconds")
R("python", "os.path.fn", r"(?<![\w.])os\.(exists|isfile|isdir|join|basename|dirname|abspath|splitext|getsize|expanduser|isabs|realpath|relpath|normpath|getmtime|islink|split)(?=\s*\()",
  "os.path.$1", "That function lives in os.path", auto=True, module="os")
py_mod("os", "mkdirs mkdir_p make_dirs makeDirs mkdirp".split(), "makedirs", "os.makedirs() creates a folder and its parents")
py_mod("os", "makedir".split(), "makedirs", "os.makedirs() creates a folder (and its parents)", auto=False)
py_mod("os", "delete rm erase del_file deleteFile delete_file remove_file removeFile".split(), "remove", "os.remove(path) deletes a file")
py_mod("os", "cwd pwd get_cwd current_dir currentDir currentdir getcurrentdir".split(), "getcwd", "os.getcwd() is the current folder")
py_mod("os", "ls listDir list_dir listfiles list_files dir files".split(), "listdir", "os.listdir(path) lists a folder")
py_mod("os", "cd changedir change_dir changeDir".split(), "chdir", "os.chdir(path) changes folder")
py_mod("os", "env environment env_vars ENV environ_vars".split(), "environ", "Environment variables are os.environ", call=False)
py_mod("os", "getenviron get_env".split(), "getenv", "os.getenv(name) reads an environment variable")
R("python", "os.exit", r"(?<![\w.])os\.exit(?=\s*\()", "sys.exit", "os has no exit(); sys.exit() ends the program", module="os")
R("python", "os.sleep", r"(?<![\w.])os\.sleep(?=\s*\()", "time.sleep", "Sleeping is time.sleep(seconds)", module="os")
R("python", "os.copy", r"(?<![\w.])os\.(?:copy|copyfile|cp)(?=\s*\()", "shutil.copy", "Copying files is shutil.copy", module="os")
R("python", "os.move", r"(?<![\w.])os\.(?:move|mv)(?=\s*\()", "shutil.move", "Moving files is shutil.move (or os.rename)", module="os")
R("python", "os.cls", r"(?<![\w.])os\.system\(\s*([\"'])cls\1\s*\)", "os.system($1clear$1)", "cls is Windows; macOS clears the terminal with clear", auto=True, module="os")
py_mod("os.path", "exist isExist file_exists fileExists exits".split(), "exists", "os.path.exists(path) checks a path")
py_mod("os.path", "combine concat join_path joinPath".split(), "join", "os.path.join() builds a path")
py_mod("os.path", "size filesize file_size".split(), "getsize", "os.path.getsize(path) is a file's size")
py_mod("os.path", "ext extension get_extension".split(), "splitext", "os.path.splitext(path) splits off the extension", auto=False)
py_mod("os.path", "filename file_name name base_name".split(), "basename", "os.path.basename(path) is the file name", auto=False)
py_mod("os.path", "dir directory folder parent dir_name".split(), "dirname", "os.path.dirname(path) is the folder", auto=False)
py_mod("sys", "args arguments argc arg params".split(), "argv", "Command-line arguments are sys.argv", call=False)
py_mod("sys", "maxint".split(), "maxsize", "Python 3 renamed sys.maxint to sys.maxsize", call=False)
py_mod("sys", "sizeof getsize size size_of".split(), "getsizeof", "sys.getsizeof(obj) is an object's size")
py_mod("sys", "quit stop terminate kill end close".split(), "exit", "sys.exit() ends the program")
py_mod("json", "parse decode deserialize fromJSON from_json fromString from_string parseString parse_string toObject to_object load_string loadString readString unserialize".split(), "loads",
       "json.loads(text) turns JSON text into Python data")
py_mod("json", "stringify encode serialize toJSON to_json toString to_string dumpString dump_string write_string writeString stringfy".split(), "dumps",
       "json.dumps(data) turns Python data into JSON text")
py_mod("json", "read readFile read_file parse_file parseFile open".split(), "load", "json.load(file) reads JSON from an open file")
py_mod("json", "write writeFile write_file save saveFile save_file".split(), "dump", "json.dump(data, file) writes JSON to an open file")
py_mod("random", "int integer randomInt random_int randInteger rand_int randi randomInteger random_integer number randomNumber random_number".split(), "randint",
       "random.randint(a, b) picks a whole number from a to b")
py_mod("random", "rand float rnd randFloat random_float randomFloat double decimal".split(), "random", "random.random() is a float from 0 to 1")
py_mod("random", "choose pick select element random_choice randomChoice oneOf one_of pickOne pick_one item randomElement random_element".split(), "choice",
       "random.choice(seq) picks one item")
py_mod("random", "range".split(), "randrange", "random.randrange(start, stop) picks from a range")
py_mod("random", "between randBetween rand_between float_between".split(), "uniform", "random.uniform(a, b) is a float between a and b", auto=False)
py_mod("random", "shuffled shuffleList shuffle_list mix scramble".split(), "shuffle", "random.shuffle(list) shuffles in place (and returns None)")
py_mod("math", "power pwr".split(), "pow", "It's math.pow(x, y) — or x ** y")
py_mod("math", "square_root squareRoot squareroot sqr sqroot".split(), "sqrt", "Square roots are math.sqrt(x)")
py_mod("math", "root".split(), "sqrt", "Square roots are math.sqrt(x)", auto=False)
py_mod("math", "ceiling roundUp round_up roundup".split(), "ceil", "Rounding up is math.ceil(x)")
py_mod("math", "roundDown round_down rounddown".split(), "floor", "Rounding down is math.floor(x)")
R("python", "math.builtin", r"(?<![\w.])math\.(abs|round|max|min|sum)(?=\s*\()", "$1", "$1() is built in — no math. needed", auto=True, module="math")
R("python", "math.pi", r"(?<![\w.])math\.(?:PI|Pi)(?![\w(])", "math.pi", "It's lowercase: math.pi", auto=True, module="math")
R("python", "math.e", r"(?<![\w.])math\.E(?![\w(])", "math.e", "It's lowercase: math.e", auto=True, module="math")
R("python", "math.inf", r"(?<![\w.])math\.(?:Infinity|infinity|INF|Inf|INFINITY|infinite)(?![\w(])", "math.inf", "Infinity is math.inf", auto=True, module="math")
R("python", "math.nan", r"(?<![\w.])math\.(?:NaN|NAN|Nan)(?![\w(])", "math.nan", "It's lowercase: math.nan", auto=True, module="math")
py_mod("math", "ln natural_log naturalLog".split(), "log", "math.log(x) is the natural log")
py_mod("math", "toRadians to_radians deg2rad deg_to_rad degreesToRadians".split(), "radians", "math.radians(degrees) converts to radians")
py_mod("math", "toDegrees to_degrees rad2deg rad_to_deg radiansToDegrees".split(), "degrees", "math.degrees(radians) converts to degrees")
py_mod("math", "cubeRoot cube_root cuberoot".split(), "cbrt", "Cube roots are math.cbrt(x) (Python 3.11+)")
py_mod("math", "arctan arcTan".split(), "atan", "Python spells it math.atan")
py_mod("math", "arcsin arcSin".split(), "asin", "Python spells it math.asin")
py_mod("math", "arccos arcCos".split(), "acos", "Python spells it math.acos")
py_mod("math", "sine".split(), "sin", "It's math.sin")
py_mod("math", "cosine".split(), "cos", "It's math.cos")
py_mod("math", "tangent".split(), "tan", "It's math.tan")
py_mod("math", "is_nan isNaN".split(), "isnan", "It's math.isnan(x)")
py_mod("math", "is_inf isInf isinfinite".split(), "isinf", "It's math.isinf(x)")
R("python", "math.random", r"(?<![\w.])math\.random(?=\s*\()", "random.random", "Random numbers come from the random module", module="math")
R("python", "math.mean", r"(?<![\w.])math\.(?:average|mean|avg)(?=\s*\()", "statistics.mean", "Averages are statistics.mean()", module="math")
py_mod("re", "find search_for searchFor locate test exec check contains has includes".split(), "search", "re.search(pattern, text) finds a match anywhere")
py_mod("re", "findAll find_all matchAll match_all getAll get_all".split(), "findall", "re.findall(pattern, text) returns every match")
py_mod("re", "replace replaceAll replace_all gsub substitute sub_all subAll".split(), "sub", "re.sub(pattern, replacement, text) replaces")
py_mod("re", "matches fullMatch full_match matchFull exactMatch".split(), "fullmatch", "re.fullmatch() matches the whole text")
py_mod("re", "regex pattern new RegExp create make".split(), "compile", "re.compile(pattern) builds a reusable pattern", auto=False)
R("python", "datetime.module", r"(?<![\w.])datetime\.(now|today|utcnow|strptime|fromtimestamp|fromisoformat|combine|utcfromtimestamp)(?=\s*\()",
  "datetime.datetime.$1", "With import datetime, the class is datetime.datetime", auto=True,
  when=r"(?m)^\s*import\s+datetime\s*(?:#.*)?$", unless=r"\bfrom\s+datetime\s+import\b")
R("python", "datetime.class", r"(?<![\w.])datetime\.datetime\.(\w+)", "datetime.$1",
  "You imported the datetime class itself, so it's datetime.$1", auto=True,
  when=r"\bfrom\s+datetime\s+import\s+[^#\n]*\bdatetime\b", unless=r"(?m)^\s*import\s+datetime\b")
R("python", "date.now", r"(?<![\w.])(datetime\.date|date)\.now(?=\s*\()", "$1.today", "Dates use .today(); datetime has .now()", auto=True)
R("python", "string.py2", r"(?<![\w.])string\.(uppercase|lowercase|letters)(?![\w(])", "string.ascii_$1", "Python 3 renamed it string.ascii_$1", auto=True, module="string")
py_mod("collections", "default_dict defaultDictionary".split(), "defaultdict", "It's collections.defaultdict")
py_mod("collections", "OrderedDictionary ordered_dict".split(), "OrderedDict", "It's collections.OrderedDict")
py_mod("collections", "named_tuple".split(), "namedtuple", "It's collections.namedtuple")
py_mod("collections", "Count count_dict Counts".split(), "Counter", "It's collections.Counter")
py_mod("collections", "dequeue Dequeue double_ended_queue".split(), "deque", "It's collections.deque (no 'ue')")
py_mod("itertools", "permutation permutate permute all_permutations".split(), "permutations", "It's itertools.permutations")
py_mod("itertools", "combination combine combos all_combinations".split(), "combinations", "It's itertools.combinations")
py_mod("itertools", "cartesian cartesian_product cartesianProduct cross".split(), "product", "The cartesian product is itertools.product")
R("python", "itertools.flatten", r"(?<![\w.])itertools\.(?:flatten|flat|concat)(?=\s*\()", "itertools.chain.from_iterable", "Flattening is itertools.chain.from_iterable", module="itertools")
py_mod("statistics", "average avg mean_value arithmetic_mean".split(), "mean", "Averages are statistics.mean()")
py_mod("statistics", "med middle".split(), "median", "It's statistics.median()")
py_mod("statistics", "std stddev standard_deviation sd std_dev".split(), "stdev", "Standard deviation is statistics.stdev()")
py_mod("statistics", "var".split(), "variance", "It's statistics.variance()")
py_mod("subprocess", "execute exec shell system run_command runCommand cmd command".split(), "run", "subprocess.run([...]) runs a command")
py_mod("subprocess", "spawn".split(), "Popen", "subprocess.Popen starts a process without waiting", auto=False)
py_mod("subprocess", "check_out checkOutput output get_output getOutput capture".split(), "check_output", "subprocess.check_output() returns a command's output")
py_mod("shutil", "copyDir copy_dir copyfolder copy_folder copy_tree copyFolder copyDirectory".split(), "copytree", "Copying a folder is shutil.copytree")
py_mod("shutil", "mv rename".split(), "move", "It's shutil.move")
py_mod("shutil", "cp copy_file".split(), "copy", "It's shutil.copy")
py_mod("shutil", "rmdir rm_tree removetree delete_tree rmrf rm_rf remove delete deltree remove_dir removeDir".split(), "rmtree",
       "Deleting a folder tree is shutil.rmtree — careful, it deletes everything inside", auto=False)
py_mod("turtle", "forwards fw go_forward goForward moveForward move_forward".split(), "forward", "It's turtle.forward(distance)")
py_mod("turtle", "move step walk go".split(), "forward", "turtle moves with forward(distance)", auto=False)
py_mod("turtle", "backwards bw go_back goBack moveBack move_back".split(), "backward", "It's turtle.backward(distance)")
py_mod("turtle", "turn_left turnLeft rotate_left rotateLeft left_turn".split(), "left", "Turning is turtle.left(angle)")
py_mod("turtle", "turn_right turnRight rotate_right rotateRight right_turn".split(), "right", "Turning is turtle.right(angle)")
py_mod("turtle", "colour setColor set_color".split(), "color", "It's turtle.color()")
py_mod("turtle", "pen_up liftPen lift_pen pen_lift up_pen".split(), "penup", "It's turtle.penup()")
py_mod("turtle", "pen_down lowerPen lower_pen putPenDown".split(), "pendown", "It's turtle.pendown()")
py_mod("turtle", "go_to moveTo move_to gotoxy goto_xy".split(), "goto", "It's turtle.goto(x, y)")
py_mod("turtle", "background bg background_color backgroundColor bg_color setBackground".split(), "bgcolor", "The background is turtle.bgcolor()")
py_mod("turtle", "hide hide_turtle".split(), "hideturtle", "It's turtle.hideturtle()")
py_mod("turtle", "show show_turtle".split(), "showturtle", "It's turtle.showturtle()")
py_mod("turtle", "exit_on_click close_on_click".split(), "exitonclick", "It's turtle.exitonclick()")
py_mod("turtle", "fill_color set_fill".split(), "fillcolor", "It's turtle.fillcolor()")
py_mod("turtle", "pen_size line_width lineWidth thickness".split(), "pensize", "Line thickness is turtle.pensize()")
py_mod("turtle", "draw_circle drawCircle make_circle".split(), "circle", "It's turtle.circle(radius)")
py_mod("turtle", "start_fill beginFill fill_begin".split(), "begin_fill", "It's turtle.begin_fill()")
py_mod("turtle", "stop_fill endFill fill_end".split(), "end_fill", "It's turtle.end_fill()")
py_mod("turtle", "set_speed velocity".split(), "speed", "It's turtle.speed()")
py_mod("turtle", "set_heading face turn_to turnTo".split(), "setheading", "It's turtle.setheading(angle)")
R("python", "turtle.wait", r"(?<![\w.])turtle\.(?:wait|sleep|pause)(?=\s*\()", "time.sleep", "turtle can't wait; time.sleep(seconds) does", module="turtle")
R("python", "threading.sleep", r"(?<![\w.])threading\.(?:sleep|wait|delay|pause)(?=\s*\()", "time.sleep", "Sleeping is time.sleep(seconds)", module="threading")
py_mod("threading", "newThread create_thread start_thread".split(), "Thread", "It's threading.Thread(target=…)")
py_mod("threading", "mutex".split(), "Lock", "A mutex is threading.Lock()")
py_mod("asyncio", "delay pause sleepFor".split(), "sleep", "It's await asyncio.sleep(seconds)")
py_mod("asyncio", "gatherAll gather_all waitAll wait_all".split(), "gather", "Running tasks together is asyncio.gather()")
py_mod("asyncio", "start execute runAsync run_async".split(), "run", "asyncio.run(main()) starts the event loop", auto=False)
py_mod("logging", "warn".split(), "warning", "logging.warn is deprecated; use logging.warning", auto=False)
py_mod("logging", "err".split(), "error", "It's logging.error()")
py_mod("logging", "basic_config".split(), "basicConfig", "It's logging.basicConfig()")
R("python", "urllib.request", r"(?<![\w.])urllib\.(urlopen|urlretrieve|Request)(?=\s*\()", "urllib.request.$1", "In Python 3 it's urllib.request.$1", auto=True, module="urllib")
R("python", "urllib.parse", r"(?<![\w.])urllib\.(urlencode|quote|unquote|quote_plus|urlparse|urljoin)(?=\s*\()", "urllib.parse.$1", "In Python 3 it's urllib.parse.$1", auto=True, module="urllib")
R("python", "urllib2", r"(?<![\w.])urllib2\.urlopen(?=\s*\()", "urllib.request.urlopen", "urllib2 is Python 2; it's urllib.request.urlopen now", undefined=None)
py_mod("copy", "deep_copy deepCopy clone deep copy_deep deepClone".split(), "deepcopy", "It's copy.deepcopy()")
py_mod("copy", "shallow shallow_copy shallowCopy".split(), "copy", "It's copy.copy()")
py_mod("uuid", "uuid generate new random uuid_4 v4 create gen randomUUID random_uuid".split(), "uuid4", "A random UUID is uuid.uuid4()")
py_mod("base64", "b64_encode encode64 base64encode base64_encode btoa".split(), "b64encode", "It's base64.b64encode(bytes)")
py_mod("base64", "b64_decode decode64 base64decode base64_decode atob".split(), "b64decode", "It's base64.b64decode(data)")
py_mod("base64", "encode".split(), "b64encode", "base64.encode works on files; for bytes use b64encode", auto=False)
py_mod("base64", "decode".split(), "b64decode", "base64.decode works on files; for data use b64decode", auto=False)
py_mod("webbrowser", "openUrl open_url openURL open_link openLink browse launch visit navigate".split(), "open", "It's webbrowser.open(url)")
py_mod("getpass", "getPassword get_password password ask_password askPassword input prompt".split(), "getpass", "It's getpass.getpass()")
py_mod("heapq", "push heap_push add insert".split(), "heappush", "It's heapq.heappush(heap, item)")
py_mod("heapq", "pop heap_pop extract_min popmin pop_min".split(), "heappop", "It's heapq.heappop(heap)")
py_mod("heapq", "make_heap build_heap makeHeap".split(), "heapify", "It's heapq.heapify(list)")
py_mod("glob", "find search list files findall find_all".split(), "glob", "It's glob.glob(pattern)")
py_mod("pickle", "save write serialize store".split(), "dump", "pickle.dump(obj, file) saves to a file")
py_mod("pickle", "read deserialize restore unserialize".split(), "load", "pickle.load(file) reads from a file")
py_mod("sqlite3", "open connection conn opendb open_db connectDB connect_db".split(), "connect", "It's sqlite3.connect(path)")
py_mod("csv", "read Reader parse".split(), "reader", "Reading CSV is csv.reader(file)", auto=False)
py_mod("csv", "write Writer".split(), "writer", "Writing CSV is csv.writer(file)", auto=False)
py_mod("pathlib", "Paths".split(), "Path", "It's pathlib.Path")
py_mod("platform", "os osname os_name operating_system".split(), "system", "platform.system() names the OS", auto=False)
py_mod("calendar", "is_leap isLeap is_leap_year leap".split(), "isleap", "It's calendar.isleap(year)")

# Habits from JavaScript, Java, C and friends.
R("python", "console.log", r"(?<![\w.])(console)\.log(?=\s*\()", "print", "Python prints with print()", auto=True, undefined=1)
R("python", "System.out", r"(?<![\w.])(System)\.out\.print(?:ln)?(?=\s*\()", "print", "Python prints with print()", auto=True, undefined=1)
R("python", "fmt.Println", r"(?<![\w.])(fmt)\.Print(?:ln|f)?(?=\s*\()", "print", "Python prints with print()", auto=True, undefined=1)
R("python", "print-alias", r"(?<![\w.])(puts|echo|println|printLn|printline|print_line|printf|writeln|NSLog|say|Print|PRINT|prnt)(?=\s*\()", "print",
  "Python prints with print()", auto=True, undefined=1)
R("python", "alert", r"(?<![\w.])(alert)(?=\s*\()", "print", "Python has no alert(); print() shows text", undefined=1)
R("python", "raw_input", r"(?<![\w.])(raw_input)(?=\s*\()", "input", "Python 3 renamed raw_input() to input()", auto=True, undefined=1)
R("python", "input-alias", r"(?<![\w.])(scanf|readline|readLine|read_line|gets|getline|Readline|read_input|readInput)(?=\s*\()", "input",
  "Python reads a line with input()", auto=True, undefined=1)
R("python", "prompt", r"(?<![\w.])(prompt)(?=\s*\()", "input", "Python asks with input(\"question\")", undefined=1)
R("python", "len-alias", r"(?<![\w.])(length|lenght|len_of|lengthOf|length_of|strlen|sizeof|size_of|count_of|getLength|get_length|lengh|lenth)(?=\s*\()", "len",
  "Python's length function is len()", auto=True, undefined=1)
R("python", "len-maybe", r"(?<![\w.])(size|count|Length|Len|LEN)(?=\s*\(\s*[^)\s])", "len", "Python's length function is len()", undefined=1)
R("python", "xrange", r"(?<![\w.])(xrange)(?=\s*\()", "range", "Python 3 renamed xrange() to range()", auto=True, undefined=1)
R("python", "unicode", r"(?<![\w.])(unicode)(?=\s*\()", "str", "In Python 3 every str is unicode", auto=True, undefined=1)
R("python", "long", r"(?<![\w.])(long)(?=\s*\()", "int", "Python 3 ints have no size limit; it's int()", auto=True, undefined=1)
R("python", "basestring", r"(?<![\w.])(basestring)(?![\w(])", "str", "Python 3 has just str", auto=True, undefined=1)
R("python", "str-alias", r"(?<![\w.])(string|String|toString|to_string|stringify|toStr|to_str|tostring)(?=\s*\()", "str", "Python converts to text with str()", auto=True, undefined=1)
R("python", "int-alias", r"(?<![\w.])(integer|Integer|parseInt|parse_int|toInt|to_int|atoi|Int|INT|toInteger|to_integer|parseint)(?=\s*\()", "int",
  "Python converts to a whole number with int()", auto=True, undefined=1)
R("python", "float-alias", r"(?<![\w.])(parseFloat|parse_float|toFloat|to_float|double|Double|atof|Float|toDouble|to_double|parsefloat)(?=\s*\()", "float",
  "Python converts to a decimal number with float()", auto=True, undefined=1)
R("python", "bool-alias", r"(?<![\w.])(boolean|Boolean|Bool|toBool|to_bool|parseBool)(?=\s*\()", "bool", "Python's is bool()", auto=True, undefined=1)
R("python", "type-alias", r"(?<![\w.])(typeof|typeOf|type_of|gettype|getType|get_type)(?=\s*\()", "type", "Python's is type()", auto=True, undefined=1)
R("python", "list-alias", r"(?<![\w.])(array|Array|List|toList|to_list|ArrayList)(?=\s*\()", "list", "Python makes a list with list()", undefined=1)
R("python", "dict-alias", r"(?<![\w.])(Dict|Map|HashMap|dictionary|Dictionary)(?=\s*\()", "dict", "Python makes a dictionary with dict()", undefined=1)
R("python", "set-alias", r"(?<![\w.])(Set|HashSet|hashset)(?=\s*\()", "set", "Python's is set()", undefined=1)
R("python", "reversed", r"(?<![\w.])(reverse|Reverse)(?=\s*\()", "reversed", "Python's built-in is reversed()", undefined=1)
R("python", "sorted", r"(?<![\w.])(sort|Sort)(?=\s*\()", "sorted", "Python's built-in is sorted()", undefined=1)
R("python", "max-alias", r"(?<![\w.])(maximum|Max|MAX)(?=\s*\()", "max", "Python's is max()", auto=True, undefined=1)
R("python", "min-alias", r"(?<![\w.])(minimum|Min|MIN)(?=\s*\()", "min", "Python's is min()", auto=True, undefined=1)
R("python", "abs-alias", r"(?<![\w.])(absolute|Abs|ABS|fabs)(?=\s*\()", "abs", "Python's is abs()", auto=True, undefined=1)
R("python", "sum-alias", r"(?<![\w.])(Sum|SUM|summation)(?=\s*\()", "sum", "Python's is sum()", undefined=1)
R("python", "Math.builtin", r"(?<![\w.])(Math)\.(max|min|abs|round)(?=\s*\()", "$2", "Python's $2() is built in", auto=True, undefined=1)
R("python", "Math.module", r"(?<![\w.])(Math)\.(floor|ceil|sqrt|pow|sin|cos|tan|log|exp|atan2|hypot|trunc)(?=\s*\()", "math.$2", "Python's is math.$2 (import math)", undefined=1)
R("python", "Math.random", r"(?<![\w.])(Math)\.random\(\s*\)", "random.random()", "Python's is random.random() (import random)", undefined=1)
R("python", "Math.PI", r"(?<![\w.])(Math)\.PI(?!\w)", "math.pi", "Python's is math.pi (import math)", undefined=1)
R("python", "JSON.parse", r"(?<![\w.])(JSON)\.parse(?=\s*\()", "json.loads", "Python's is json.loads() (import json)", auto=True, undefined=1)
R("python", "JSON.stringify", r"(?<![\w.])(JSON)\.stringify(?=\s*\()", "json.dumps", "Python's is json.dumps() (import json)", auto=True, undefined=1)
R("python", "Object.keys", r"(?<![\w.])(Object)\.keys\(\s*([\w.]+)\s*\)", "$2.keys()", "Python dicts have .keys()", undefined=1)
R("python", "Object.values", r"(?<![\w.])(Object)\.values\(\s*([\w.]+)\s*\)", "$2.values()", "Python dicts have .values()", undefined=1)
R("python", "Object.entries", r"(?<![\w.])(Object)\.entries\(\s*([\w.]+)\s*\)", "$2.items()", "Python dicts have .items()", undefined=1)
R("python", "Array.isArray", r"(?<![\w.])(Array)\.isArray\(\s*([\w.]+)\s*\)", "isinstance($2, list)", "Python checks with isinstance(x, list)", undefined=1)

R("python", "true", r"(?<![\w.'\"])(true|TRUE)(?![\w'\"])", "True", "Python capitalizes True", auto=True, undefined=1)
R("python", "false", r"(?<![\w.'\"])(false|FALSE)(?![\w'\"])", "False", "Python capitalizes False", auto=True, undefined=1)
R("python", "none", r"(?<![\w.'\"])(null|nil|NULL|undefined|none|NONE|Null|Nil|nullptr)(?![\w'\"])", "None", "Python's “nothing” is None", auto=True, undefined=1)
R("python", "NaN", r"(?<![\w.])(NaN)(?!\w)", "float(\"nan\")", "Python writes NaN as float(\"nan\") or math.nan", undefined=1)
R("python", "Infinity", r"(?<![\w.])(Infinity)(?!\w)", "float(\"inf\")", "Python writes infinity as float(\"inf\") or math.inf", undefined=1)
R("python", "and", r"[ \t]*&&[ \t]*", " and ", "Python writes && as and", auto=True)
R("python", "or", r"[ \t]*\|\|[ \t]*", " or ", "Python writes || as or", auto=True)
R("python", "not", r"!(?!=)[ \t]*(?=[\w(\[])", "not ", "Python writes ! as not", auto=True)
R("python", "===", r"===", "==", "Python compares with ==", auto=True)
R("python", "!==", r"!==", "!=", "Python compares with !=", auto=True)
R("python", "++", r"(?m)^([ \t]*)([A-Za-z_][\w.]*(?:\[[^\]\n]*\])?)[ \t]*\+\+[ \t]*;?[ \t]*$", "$1$2 += 1", "Python has no ++; it's += 1", auto=True)
R("python", "--", r"(?m)^([ \t]*)([A-Za-z_][\w.]*(?:\[[^\]\n]*\])?)[ \t]*--[ \t]*;?[ \t]*$", "$1$2 -= 1", "Python has no --; it's -= 1", auto=True)
R("python", "pre++", r"(?m)^([ \t]*)\+\+[ \t]*([A-Za-z_][\w.]*)[ \t]*;?[ \t]*$", "$1$2 += 1", "Python has no ++; it's += 1", auto=True)
R("python", "else if", r"(?m)^([ \t]*)else[ \t]+if\b", "$1elif", "Python writes else if as elif", auto=True)
R("python", "elsif", r"(?m)^([ \t]*)(?:elseif|elsif|elseIf|else_if|elsef)\b", "$1elif", "Python writes it elif", auto=True)
R("python", "catch", r"(?m)^([ \t]*)catch\b", "$1except", "Python catches errors with except", auto=True)
R("python", "throw new Error", r"(?m)^([ \t]*)throw[ \t]+new[ \t]+Error\b", "$1raise Exception", "Python raises errors with raise", auto=True)
R("python", "throw new", r"(?m)^([ \t]*)throw[ \t]+new[ \t]+", "$1raise ", "Python raises errors with raise", auto=True)
R("python", "throw", r"(?m)^([ \t]*)throw\b", "$1raise", "Python raises errors with raise", auto=True)
R("python", "function", r"(?m)^([ \t]*)(?:async[ \t]+)?function[ \t]+(\w+)[ \t]*\(", "$1def $2(", "Python defines functions with def", auto=True)
R("python", "func", r"(?m)^([ \t]*)(?:func|fn|fun|define|sub|proc)[ \t]+(\w+)[ \t]*\(", "$1def $2(", "Python defines functions with def", auto=True)
R("python", "this.", r"(?<![\w.])(this)\.", "self.", "Python methods use self, not this", auto=True, undefined=1)
R("python", "var", r"(?m)^([ \t]*)(?:var|let|const|auto|my|local)[ \t]+(?=[A-Za-z_]\w*[ \t]*=(?!=))", "$1", "Python needs no declaration keyword", auto=True)
R("python", "int x =", r"(?m)^([ \t]*)int[ \t]+([A-Za-z_]\w*)[ \t]*=(?!=)", "$1$2: int =", "Python writes types after the name: x: int = …", auto=True)
R("python", "float x =", r"(?m)^([ \t]*)(?:float|double)[ \t]+([A-Za-z_]\w*)[ \t]*=(?!=)", "$1$2: float =", "Python writes types after the name: x: float = …", auto=True)
R("python", "str x =", r"(?m)^([ \t]*)(?:String|string|char)[ \t]+([A-Za-z_]\w*)[ \t]*=(?!=)", "$1$2: str =", "Python writes types after the name: x: str = …", auto=True)
R("python", "bool x =", r"(?m)^([ \t]*)(?:bool|boolean)[ \t]+([A-Za-z_]\w*)[ \t]*=(?!=)", "$1$2: bool =", "Python writes types after the name: x: bool = …", auto=True)
R("python", "// comment", r"(?m)^([ \t]*)//[ \t]?", "$1# ", "Python comments start with #", auto=True)
R("python", "print py2", r"(?m)^([ \t]*)print[ \t]+(?![\s(=,.\[])(.+?)[ \t]*$", "$1print($2)", "In Python 3, print is a function: print(…)", auto=True)
R("python", "except py2", r"(?m)^([ \t]*)except[ \t]+([\w.]+)[ \t]*,[ \t]*([A-Za-z_]\w*)[ \t]*:", "$1except $2 as $3:", "Python 3 writes except Error as name:", auto=True)
R("python", "has_key", r"(?<![\w.])([A-Za-z_][\w.]*)\.(?:has_key|containsKey|hasKey)\(\s*([^()\n]+?)\s*\)", "$2 in $1", "Python checks keys with: key in dict", auto=True)
R("python", "iteritems", r"\.(?:iteritems|iterItems)\(\)", ".items()", "Python 3 renamed it .items()", auto=True)
R("python", "itervalues", r"\.itervalues\(\)", ".values()", "Python 3 renamed it .values()", auto=True)
R("python", "iterkeys", r"\.iterkeys\(\)", ".keys()", "Python 3 renamed it .keys()", auto=True)
R("python", "if =", r"(?m)^([ \t]*(?:if|elif|while)[ \t]+[^=!<>()\n:]*?[^=!<>:+\-*/%&|^\s])[ \t]*=[ \t]*(?!=)", "$1 == ",
  "A comparison needs == (a single = assigns)", auto=True)
R("python", ".push", r"\.push\(", ".append(", "Python lists use .append()", auto=True, unless=r"\bdef\s+push\b")
R("python", ".push_back", r"\.(?:push_back|pushBack)\(", ".append(", "Python lists use .append()", auto=True, unless=r"\bdef\s+(?:push_back|pushBack)\b")
R("python", ".toUpperCase", r"\.(?:toUpperCase|toUpper|upperCase|to_upper|toupper|uppercase|upcase)\(\)", ".upper()", "Python strings use .upper()", auto=True,
  unless=r"\bdef\s+(?:toUpperCase|toUpper|upperCase|to_upper|toupper|uppercase|upcase)\b")
R("python", ".toLowerCase", r"\.(?:toLowerCase|toLower|lowerCase|to_lower|tolower|lowercase|downcase)\(\)", ".lower()", "Python strings use .lower()", auto=True,
  unless=r"\bdef\s+(?:toLowerCase|toLower|lowerCase|to_lower|tolower|lowercase|downcase)\b")
R("python", ".trim", r"\.trim\(\)", ".strip()", "Python strings use .strip()", auto=True, unless=r"\bdef\s+trim\b")
R("python", ".trimStart", r"\.(?:trimStart|trimLeft|ltrim)\(\)", ".lstrip()", "Python strings use .lstrip()", auto=True, unless=r"\bdef\s+(?:trimStart|trimLeft|ltrim)\b")
R("python", ".trimEnd", r"\.(?:trimEnd|trimRight|rtrim|chomp)\(\)", ".rstrip()", "Python strings use .rstrip()", auto=True, unless=r"\bdef\s+(?:trimEnd|trimRight|rtrim|chomp)\b")
R("python", ".startsWith", r"\.(?:startsWith|starts_with|beginsWith|begins_with|startWith)\(", ".startswith(", "Python spells it .startswith()", auto=True,
  unless=r"\bdef\s+(?:startsWith|starts_with|beginsWith|begins_with|startWith)\b")
R("python", ".endsWith", r"\.(?:endsWith|ends_with|endWith)\(", ".endswith(", "Python spells it .endswith()", auto=True, unless=r"\bdef\s+(?:endsWith|ends_with|endWith)\b")
for name in ["length", "len", "Length"]:
    R("python", f".{name}", rf"(?<![\w.])([A-Za-z_][\w.]*(?:\[[^\]\n]*\])?)\.{name}\b(?![\w(=]|\s*=[^=])", "len($1)", "Python gets a length with len(x)", auto=True,
      unless=rf"\.{name}\s*=[^=]|\bdef\s+{name}\b|\b{name}\s*=[^=]|@property")
R("python", ".size()", r"(?<![\w.])([A-Za-z_][\w.]*(?:\[[^\]\n]*\])?)\.(?:size|length|len|count|getLength|get_length|getSize|Size|Count|Length)\(\)", "len($1)",
  "Python gets a length with len(x)", auto=True, unless=r"\bdef\s+(?:size|length|len|count|getLength|get_length|getSize|Size|Count|Length)\b")
R("python", ".includes", r"(?<![\w.])([A-Za-z_][\w.]*(?:\[[^\]\n]*\])?)\.(?:includes|contains)\(\s*([^()\n]+?)\s*\)", "$2 in $1", "Python checks membership with: item in collection",
  auto=True, unless=r"\bdef\s+(?:includes|contains)\b")
R("python", ".indexOf", r"\.indexOf\(", ".index(", "Python lists and strings use .index() (strings also have .find())", unless=r"\bdef\s+indexOf\b")
R("python", ".lastIndexOf", r"\.lastIndexOf\(", ".rindex(", "Python strings use .rindex() or .rfind()", unless=r"\bdef\s+lastIndexOf\b")
R("python", ".toString", r"(?<![\w.])([A-Za-z_][\w.]*(?:\[[^\]\n]*\])?)\.(?:toString|to_string|toStr|ToString|tostring)\(\)", "str($1)", "Python converts to text with str(x)", auto=True,
  unless=r"\bdef\s+(?:toString|to_string|toStr|ToString|tostring)\b")
R("python", ".equals", r"(?<![\w.])([A-Za-z_][\w.]*)\.equals\(\s*([^()\n]+?)\s*\)", "$1 == $2", "Python compares with ==", auto=True, unless=r"\bdef\s+equals\b")
R("python", ".isEmpty", r"(?<![\w.])([A-Za-z_][\w.]*)\.(?:isEmpty|is_empty)\(\)", "not $1", "Empty collections are falsy: not x", auto=True, unless=r"\bdef\s+(?:isEmpty|is_empty)\b")
R("python", ".charAt", r"(?<![\w.])([A-Za-z_][\w.]*)\.charAt\(\s*([^()\n]+?)\s*\)", "$1[$2]", "Python indexes strings with s[i]", auto=True, unless=r"\bdef\s+charAt\b")
R("python", ".substring2", r"(?<![\w.])([A-Za-z_][\w.]*)\.(?:substring|substr|slice)\(\s*([^(),\n]+?)\s*,\s*([^()\n]+?)\s*\)", "$1[$2:$3]", "Python slices with s[start:end]", auto=True,
  unless=r"\bdef\s+(?:substring|substr|slice)\b")
R("python", ".substring1", r"(?<![\w.])([A-Za-z_][\w.]*)\.(?:substring|substr)\(\s*([^(),\n]+?)\s*\)", "$1[$2:]", "Python slices with s[start:]", auto=True,
  unless=r"\bdef\s+(?:substring|substr)\b")
R("python", ".replaceAll", r"\.replaceAll\(", ".replace(", "Python's .replace() already replaces every occurrence", auto=True, unless=r"\bdef\s+replaceAll\b")
R("python", ".join", r"(?<![\w.])([A-Za-z_][\w.]*)\.join\(\s*(\"[^\"\n]*\"|'[^'\n]*')\s*\)", "$2.join($1)", "In Python the separator comes first: \", \".join(items)", auto=True)
R("python", ".put", r"(?<![\w.])([A-Za-z_][\w.]*)\.put\(\s*([^,()\n]+?)\s*,\s*([^()\n]+?)\s*\)", "$1[$2] = $3", "Python dicts set values with d[key] = value", unless=r"\bdef\s+put\b|\bqueue\b|\bQueue\b")
R("python", "= .sort()", r"(?<![\w.])([A-Za-z_]\w*)[ \t]*=[ \t]*([A-Za-z_][\w.]*)\.sort\(\s*\)", "$1 = sorted($2)",
  "list.sort() sorts in place and returns None; sorted() returns a new list")
R("python", "= .reverse()", r"(?<![\w.])([A-Za-z_]\w*)[ \t]*=[ \t]*([A-Za-z_][\w.]*)\.reverse\(\s*\)", "$1 = list(reversed($2))",
  "list.reverse() works in place and returns None")
R("python", "x = x.append", r"(?<![\w.])([A-Za-z_]\w*)[ \t]*=[ \t]*\1\.append\(", "$1.append(", "append() changes the list and returns None — don't assign it", auto=True)
R("python", "^ power", r"([\w)\]]+)[ \t]*\^[ \t]*(\d+)\b", "$1 ** $2", "^ is XOR in Python; powers are **")

LANGS["python"]["imports"] = {
    **{n: "from time import " + n for n in ["sleep", "perf_counter", "monotonic"]},
    **{n: "from random import " + n for n in ["randint", "choice", "shuffle", "uniform", "sample", "randrange", "choices"]},
    **{n: "from math import " + n for n in ["sqrt", "floor", "ceil", "pi", "sin", "cos", "tan", "log", "exp", "radians", "degrees",
                                            "factorial", "gcd", "inf", "hypot", "atan2", "isclose", "comb", "perm"]},
    "Path": "from pathlib import Path",
    **{n: "from datetime import " + n for n in ["datetime", "timedelta", "date"]},
    **{n: "from collections import " + n for n in ["defaultdict", "Counter", "deque", "namedtuple", "OrderedDict"]},
    "dataclass": "from dataclasses import dataclass", "field": "from dataclasses import field",
    "Enum": "from enum import Enum",
    **{n: "from typing import " + n for n in ["List", "Dict", "Optional", "Tuple", "Union", "Any", "Callable", "Iterable", "Iterator", "Sequence"]},
    **{n: "from functools import " + n for n in ["partial", "reduce", "lru_cache", "wraps", "cache", "cmp_to_key"]},
    "pprint": "from pprint import pprint", "deepcopy": "from copy import deepcopy", "uuid4": "from uuid import uuid4",
    **{n: "from itertools import " + n for n in ["permutations", "combinations", "product", "chain", "groupby", "accumulate", "zip_longest"]},
    **{n: "from statistics import " + n for n in ["mean", "median", "stdev", "mode"]},
    "getpass": "from getpass import getpass", "argv": "from sys import argv",
    "ABC": "from abc import ABC", "abstractmethod": "from abc import abstractmethod",
    "ThreadPoolExecutor": "from concurrent.futures import ThreadPoolExecutor", "Thread": "from threading import Thread",
    "Fraction": "from fractions import Fraction", "Decimal": "from decimal import Decimal",
    **{n: "from heapq import " + n for n in ["heappush", "heappop", "heapify"]},
    **{n: "from bisect import " + n for n in ["bisect_left", "bisect_right", "insort"]},
    "dedent": "from textwrap import dedent", "contextmanager": "from contextlib import contextmanager",
    "StringIO": "from io import StringIO", "BytesIO": "from io import BytesIO", "ZipFile": "from zipfile import ZipFile",
}

# ---------------------------------------------------------------- JavaScript & TypeScript

def js_member(obj, wrong, right, why, auto=True, call=True):
    look = r"(?=\s*\()" if call else r"(?![\w$(])"
    R("javascript", f"{obj}.{right}.{wrong[0]}", rf"(?<![\w$.])({re.escape(obj)})\.(?:{alt(wrong)}){look}", f"{obj}.{right}", why, auto, undefined=1)

js_member("console", "print write println printLn out display show puts echo say writeLine WriteLine printf".split(), "log", "JavaScript prints with console.log()")
js_member("console", "err".split(), "error", "It's console.error()")
js_member("console", "warning".split(), "warn", "It's console.warn()")
js_member("JSON", "loads load decode deserialize fromString read toObject parseString".split(), "parse", "JSON.parse(text) reads JSON")
js_member("JSON", "dumps dump encode serialize toString stringfy stringyfy toJSON write".split(), "stringify", "JSON.stringify(value) writes JSON")
js_member("Math", "power pwr".split(), "pow", "It's Math.pow(x, y) — or x ** y")
js_member("Math", "squareRoot square_root squareroot sqr root".split(), "sqrt", "Square roots are Math.sqrt(x)")
js_member("Math", "ceiling roundUp".split(), "ceil", "Rounding up is Math.ceil(x)")
js_member("Math", "roundDown".split(), "floor", "Rounding down is Math.floor(x)")
js_member("Math", "rand rnd randomNumber".split(), "random", "Math.random() is a number from 0 to 1")
js_member("Math", "maximum".split(), "max", "It's Math.max()")
js_member("Math", "minimum".split(), "min", "It's Math.min()")
js_member("Math", "absolute".split(), "abs", "It's Math.abs()")
js_member("Math", "pi Pi".split(), "PI", "It's Math.PI (capitals)", call=False)
js_member("Math", "e".split(), "E", "It's Math.E (capital)", call=False)
R("javascript", "Math.randint2", r"(?<![\w$.])(Math)\.(?:randint|randInt|randomInt|random_int)\(\s*([^,()]+?)\s*,\s*([^,()]+?)\s*\)",
  "(Math.floor(Math.random() * ($3 - $2 + 1)) + $2)", "JavaScript has no randint; this picks a whole number from a to b", undefined=1)
R("javascript", "Math.randint1", r"(?<![\w$.])(Math)\.(?:randint|randInt|randomInt|random_int)\(\s*([^,()]+?)\s*\)",
  "Math.floor(Math.random() * $2)", "JavaScript has no randint; this picks 0 … n-1", undefined=1)
js_member("document", "getElementsById getElemById getElementId".split(), "getElementById", "It's document.getElementById (singular)")
js_member("document", "getElementByClassName getElementByClass getElementsByClass".split(), "getElementsByClassName", "It's document.getElementsByClassName (plural)")
js_member("document", "getElementByTagName getElementsByTag".split(), "getElementsByTagName", "It's document.getElementsByTagName (plural)")
js_member("document", "querySelectAll selectAll querySelectorALL".split(), "querySelectorAll", "It's document.querySelectorAll")
js_member("document", "querySelect".split(), "querySelector", "It's document.querySelector")
js_member("document", "createElem newElement makeElement".split(), "createElement", "It's document.createElement")
R("javascript", "getElementById #", r"getElementById\(\s*([\"'`])#([\w-]+)\1", "getElementById($1$2$1", "getElementById takes the id without #", auto=True)
R("javascript", "getElementsByClassName .", r"getElementsByClassName\(\s*([\"'`])\.([\w-]+)\1", "getElementsByClassName($1$2$1", "getElementsByClassName takes the class without the dot", auto=True)
R("javascript", "addEventListener on", r"addEventListener\(\s*([\"'`])on([a-z]+)\1", "addEventListener($1$2$1", "Event names have no “on”: \"click\", not \"onclick\"", auto=True)
R("javascript", "addEventListener call", r"addEventListener\(\s*([\"'`]\w+[\"'`])\s*,\s*([A-Za-z_$][\w$.]*)\(\)\s*\)", "addEventListener($1, $2)",
  "Pass the function itself; $2() runs it right away")
R("javascript", "setTimeout call", r"\b(setTimeout|setInterval)\(\s*([A-Za-z_$][\w$.]*)\(\)\s*,", "$1($2,", "Pass the function itself; $2() runs it right away")
for wrong, right in [("innerHtml", "innerHTML"), ("InnerHTML", "innerHTML"), ("outerHtml", "outerHTML"), ("textcontent", "textContent"),
                     ("TextContent", "textContent"), ("innertext", "innerText"), ("classname", "className"), ("classlist", "classList"),
                     ("addEventlistener", "addEventListener"), ("addeventlistener", "addEventListener"), ("removeEventlistener", "removeEventListener"),
                     ("appendchild", "appendChild"), ("AppendChild", "appendChild"), ("removechild", "removeChild"), ("parentnode", "parentNode"),
                     ("preventdefault", "preventDefault"), ("stoppropagation", "stopPropagation"), ("queryselector", "querySelector"),
                     ("setattribute", "setAttribute"), ("getattribute", "getAttribute")]:
    R("javascript", f".{wrong}", rf"\.{wrong}\b", f".{right}", f"DOM names are camelCase: .{right}", auto=True, unless=rf"\b{wrong}\s*[:=(]")
for prop in ["onClick", "onLoad", "onChange", "onSubmit", "onKeyDown", "onKeyUp", "onInput", "onMouseOver", "onMouseOut", "onFocus", "onBlur", "onScroll", "onResize"]:
    R("javascript", f".{prop}=", rf"\.{prop}(?=\s*=[^=])", f".{prop.lower()}", f"DOM event properties are lowercase: .{prop.lower()}", unless=rf"<\w[^>]*\b{prop}=")
R("javascript", ".lenght", r"\.(?:lenght|legnth|lengh|lentgh|lenth|lengt|lengthh|lneght|leng)\b", ".length", "It's .length", auto=True)
R("javascript", ".length()", r"\.length\(\)", ".length", ".length is a property — no ()", auto=True)
R("javascript", ".len", r"\.len\b(?:\(\))?", ".length", "It's .length", auto=True, unless=r"\blen\s*[:=(]")
R("javascript", ".size()", r"\.(?:size|count)\(\)", ".length", "Arrays and strings use .length (Maps and Sets use .size)", unless=r"\b(?:size|count)\s*\(\s*\)\s*\{")
R("javascript", ".push_back", r"\.(?:push_back|pushBack)\(", ".push(", "JavaScript arrays use .push()", auto=True)
R("javascript", ".append", r"\.append\(", ".push(", "Arrays use .push() (DOM elements do have .append())")
R("javascript", ".upper", r"\.(?:upper|toUpper|uppercase|to_upper)\(\)", ".toUpperCase()", "JavaScript strings use .toUpperCase()", auto=True)
R("javascript", ".lower", r"\.(?:lower|toLower|lowercase|to_lower)\(\)", ".toLowerCase()", "JavaScript strings use .toLowerCase()", auto=True)
R("javascript", ".strip", r"\.strip\(\)", ".trim()", "JavaScript strings use .trim()", auto=True)
R("javascript", ".lstrip", r"\.(?:lstrip|ltrim)\(\)", ".trimStart()", "JavaScript strings use .trimStart()", auto=True)
R("javascript", ".rstrip", r"\.(?:rstrip|rtrim)\(\)", ".trimEnd()", "JavaScript strings use .trimEnd()", auto=True)
R("javascript", ".startswith", r"\.(?:startswith|starts_with|beginsWith|startWith)\(", ".startsWith(", "It's .startsWith()", auto=True)
R("javascript", ".endswith", r"\.(?:endswith|ends_with|endWith)\(", ".endsWith(", "It's .endsWith()", auto=True)
R("javascript", ".contains", r"\.contains\(", ".includes(", "Strings and arrays use .includes() (classList and nodes have .contains())")
R("javascript", ".index", r"\.index\(", ".indexOf(", "Arrays and strings use .indexOf()", unless=r"\bindex\s*[:(]\s*")
R("javascript", ".forEach case", r"\.(?:foreach|ForEach|for_each)\(", ".forEach(", "It's .forEach()", auto=True)
R("javascript", ".toString case", r"\.(?:tostring|ToString|to_string|toStr)\(\)", ".toString()", "It's .toString()", auto=True)
R("javascript", "True", r"(?<![\w$.'\"])(True|TRUE)(?![\w$'\"])", "true", "JavaScript writes true in lowercase", auto=True, undefined=1)
R("javascript", "False", r"(?<![\w$.'\"])(False|FALSE)(?![\w$'\"])", "false", "JavaScript writes false in lowercase", auto=True, undefined=1)
R("javascript", "None", r"(?<![\w$.'\"])(None|nil|NULL|Null|nullptr)(?![\w$'\"])", "null", "JavaScript's “nothing” is null", auto=True, undefined=1)
R("javascript", "elif", r"(?m)^([ \t]*\}?[ \t]*)(?:elif|elsif|elseif|elseIf)\b", "$1else if", "JavaScript writes it else if", auto=True)
R("javascript", "def", r"(?m)^([ \t]*)(?:async[ \t]+)?def[ \t]+(\w+)[ \t]*\(", "$1function $2(", "JavaScript defines functions with function", auto=True)
R("javascript", "func", r"(?m)^([ \t]*)(?:func|fn|fun)[ \t]+(\w+)[ \t]*\(", "$1function $2(", "JavaScript defines functions with function", auto=True)
R("javascript", "print", r"(?<![\w$.])(print)\(\s*(?=[^)\s])", "console.log(", "print() prints the page; console.log() prints text", auto=True, undefined=1)
R("javascript", "print-alias", r"(?<![\w$.])(println|printf|echo|puts|printLn|writeln)(?=\s*\()", "console.log", "JavaScript prints with console.log()", auto=True, undefined=1)
R("javascript", "System.out", r"(?<![\w$.])(System)\.out\.print(?:ln)?(?=\s*\()", "console.log", "JavaScript prints with console.log()", auto=True, undefined=1)
R("javascript", "and", r"(?<=[\w$)\]'\"`])[ \t]+and[ \t]+(?=[\w$(!'\"`\[])", " && ", "JavaScript writes and as &&", auto=True, unless=r"\b(?:let|const|var)\s+and\b")
R("javascript", "or", r"(?<=[\w$)\]'\"`])[ \t]+or[ \t]+(?=[\w$(!'\"`\[])", " || ", "JavaScript writes or as ||", auto=True, unless=r"\b(?:let|const|var)\s+or\b")
R("javascript", "not", r"(?<![\w$.])not[ \t]+(?=[\w$(\[])", "!", "JavaScript writes not as !", auto=True, unless=r"\b(?:let|const|var|function)\s+not\b")
R("javascript", "self.", r"(?<![\w$.])(self)\.", "this.", "Methods use this, not self", undefined=1, unless=r"postMessage|importScripts|onmessage")
R("javascript", "module.export", r"(?<![\w$.])module\.export\b(?!s)", "module.exports", "It's module.exports (with an s)", auto=True)
R("javascript", "->", r"\)[ \t]*->[ \t]*(?=[{(\w])", ") => ", "Arrow functions use =>", auto=True)
R("javascript", "if =", r"\bif[ \t]*\([ \t]*([\w$.]+)[ \t]*=[ \t]*(?![=>])", "if ($1 === ", "A comparison needs === (a single = assigns)")
R("javascript", "len()", r"(?<![\w$.])(len)\(\s*([^()]+?)\s*\)", "$2.length", "JavaScript gets a length with x.length", auto=True, undefined=1)
R("javascript", "str()", r"(?<![\w$.])(str)\(", "String(", "JavaScript converts to text with String(x)", auto=True, undefined=1)
R("javascript", "int()", r"(?<![\w$.])(int)\(", "parseInt(", "JavaScript converts to a whole number with parseInt(x)", auto=True, undefined=1)
R("javascript", "float()", r"(?<![\w$.])(float)\(", "parseFloat(", "JavaScript converts to a number with parseFloat(x)", auto=True, undefined=1)
R("javascript", "type()", r"(?<![\w$.])(type)\(\s*([^()]+?)\s*\)", "typeof $2", "JavaScript checks types with typeof x", undefined=1)
R("javascript", "input()", r"(?<![\w$.])(input)\(", "prompt(", "Browsers ask with prompt()", undefined=1)
R("javascript", "for in", r"\bfor[ \t]*\([ \t]*(const|let|var)[ \t]+(\w+)[ \t]+in[ \t]+", "for ($1 $2 of ", "for…in gives keys/indexes; for…of gives the values")
R("javascript", "typeof array", r"\btypeof[ \t]+([\w$.]+)[ \t]*===?[ \t]*([\"'`])array\2", "Array.isArray($1)", "typeof never says \"array\"; use Array.isArray(x)", auto=True)
R("javascript", "typeof null", r"\btypeof[ \t]+([\w$.]+)[ \t]*===?[ \t]*([\"'`])null\2", "$1 === null", "typeof null is \"object\"; compare with === null", auto=True)
R("javascript", "== NaN", r"([\w$.]+)[ \t]*===?[ \t]*NaN\b", "Number.isNaN($1)", "Nothing equals NaN, not even NaN; use Number.isNaN(x)", auto=True)
R("javascript", "fetch.json", r"\bfetch\(([^()]*)\)\.json\(\)", "(await fetch($1)).json()", "fetch() returns a promise; await it before .json()")
R("javascript", "throw str", r"(?m)^([ \t]*)raise[ \t]+", "$1throw ", "JavaScript throws errors with throw", auto=True, unless=r"\braise\s*\(")
R("javascript", "^ power", r"([\w$)\]]+)[ \t]*\^[ \t]*(\d+)\b", "$1 ** $2", "^ is XOR in JavaScript; powers are **")
LANGS["javascript"]["builtins"] = ["require", "module", "exports", "process", "Buffer", "__dirname", "__filename", "global", "document", "window",
    "localStorage", "sessionStorage", "navigator", "location", "history", "console", "fetch", "alert", "confirm", "prompt", "setTimeout",
    "setInterval", "clearTimeout", "clearInterval", "requestAnimationFrame", "cancelAnimationFrame", "addEventListener", "event",
    "describe", "it", "test", "expect", "beforeEach", "afterEach", "beforeAll", "afterAll", "jest", "React", "useState", "useEffect",
    "useRef", "useMemo", "useCallback", "useContext", "useReducer", "Component", "jQuery", "$", "_", "performance", "crypto", "structuredClone",
    "queueMicrotask", "atob", "btoa", "Image", "Audio", "FormData", "URL", "URLSearchParams", "Blob", "File", "FileReader", "WebSocket",
    "Worker", "XMLHttpRequest", "AbortController", "TextEncoder", "TextDecoder", "Event", "CustomEvent", "HTMLElement", "Element", "Node",
    "MutationObserver", "IntersectionObserver", "ResizeObserver", "customElements", "getComputedStyle", "matchMedia", "innerWidth", "innerHeight"]
LANGS["javascript"]["methods"] = """innerHTML outerHTML textContent innerText className classList id style value checked disabled src href alt title
    appendChild removeChild insertBefore replaceChild cloneNode setAttribute getAttribute removeAttribute hasAttribute toggleAttribute
    addEventListener removeEventListener dispatchEvent querySelector querySelectorAll closest matches focus blur click remove append prepend
    before after replaceWith parentNode parentElement children childNodes firstChild lastChild nextSibling previousSibling
    nextElementSibling previousElementSibling firstElementChild lastElementChild dataset offsetWidth offsetHeight offsetTop offsetLeft
    clientWidth clientHeight scrollTop scrollLeft scrollHeight scrollWidth scrollIntoView getBoundingClientRect preventDefault
    stopPropagation target currentTarget key code keyCode which clientX clientY pageX pageY shiftKey ctrlKey metaKey altKey
    then catch finally json text blob status ok headers statusText getContext fillRect strokeRect fillStyle strokeStyle beginPath
    moveTo lineTo arc stroke fill fillText clearRect drawImage width height play pause currentTime volume duration""".split()
LANGS["javascript"]["keywords"] = """break case catch class const continue debugger default delete do else export extends finally for function
    if import in instanceof let new return super switch this throw try typeof var void while with yield async await of static get set
    true false null undefined""".split()

# ---------------------------------------------------------------- C and C++

C_HEADERS = "stdio stdlib string math time ctype stdbool stdint limits assert errno signal stdarg stddef float locale setjmp unistd pthread fcntl dirent".split()
R("c", "#include no .h", rf"(?m)^([ \t]*#[ \t]*include[ \t]*)<({alt(C_HEADERS)})>", "$1<$2.h>", "C headers end in .h: <$2.h>", auto=True)
R("c", "#include typo", r"(?m)^([ \t]*)#[ \t]*(?:incldue|inlcude|inculde|includ|incude|inclde|Include|INCLUDE|imclude|icnlude|incluce|inclue)\b", "$1#include", "It's #include", auto=True)
R("c", "#define typo", r"(?m)^([ \t]*)#[ \t]*(?:defien|defnie|definr|defin|Define|DEFINE|deifne)\b", "$1#define", "It's #define", auto=True)
R("c", "#define =", r"(?m)^([ \t]*#[ \t]*define[ \t]+\w+)[ \t]*=[ \t]*", "$1 ", "#define takes no =: #define NAME value", auto=True)
R("c", "#define ;", r"(?m)^([ \t]*#[ \t]*define[ \t]+\w+[ \t]+[^;\n]+?);[ \t]*$", "$1", "A ; in a #define ends up in every use")
R("c", "malloc.h", r"(?m)^([ \t]*#[ \t]*include[ \t]*)<malloc\.h>", "$1<stdlib.h>", "macOS has malloc in <stdlib.h>", auto=True)
R("c", "conio.h", r"(?m)^[ \t]*#[ \t]*include[ \t]*<conio\.h>[ \t]*\n?", "", "conio.h is Windows-only; macOS doesn't have it")
R("c", "print", r"(?<![\w.])(print|println|printLn|print_line|printline|Print|PRINT|prinf|writeln|echo)(?=\s*\()", "printf", "C prints with printf()", auto=True, undefined=1)
R("c", "console.log", r"(?<![\w.])(console)\.log(?=\s*\()", "printf", "C prints with printf()", auto=True, undefined=1)
R("c", "scanf &", r"\bscanf\(\s*(\"[^\"%]*%(?:d|i|u|f|lf|c|ld|lld|hd|x|o|e|g|zu)[^\"]*\")\s*,\s*([A-Za-z_]\w*)\s*\)", "scanf($1, &$2)",
  "scanf needs the variable's address: &$2")
R("c", "gets", r"(?<![\w.])gets\(\s*(\w+)\s*\)", "fgets($1, sizeof $1, stdin)", "gets() can overflow the buffer and was removed from C; fgets() is safe")
R("c", "strlen alias", r"(?<![\w.])(strlength|string_length|len|length|strlenght|str_len|strLen|lenght)(?=\s*\()", "strlen", "C measures strings with strlen()", auto=True, undefined=1)
R("c", "strcmp alias", r"(?<![\w.])(strcompare|string_compare|strequals|str_equals|strEquals|strcmpi)(?=\s*\()", "strcmp", "C compares strings with strcmp()", auto=True, undefined=1)
R("c", "strcpy alias", r"(?<![\w.])(strcopy|string_copy|str_copy)(?=\s*\()", "strcpy", "C copies strings with strcpy()", auto=True, undefined=1)
R("c", "strcat alias", r"(?<![\w.])(strconcat|strappend|str_concat|string_concat)(?=\s*\()", "strcat", "C joins strings with strcat()", auto=True, undefined=1)
R("c", "Sleep", r"(?<![\w.])(Sleep)\(\s*(\d+)\s*\)", "usleep($2 * 1000)", "Sleep(ms) is Windows; usleep() takes microseconds (<unistd.h>)", undefined=1)
R("c", "pause", r"\bsystem\(\s*\"pause\"\s*\)", "getchar()", "system(\"pause\") is Windows; getchar() waits for Enter")
R("c", "cls", r"\bsystem\(\s*\"cls\"\s*\)", "system(\"clear\")", "cls is Windows; macOS clears with clear", auto=True)
R("c", "getch", r"(?<![\w.])(getch|getche)\(\s*\)", "getchar()", "getch() is from Windows' conio.h; getchar() reads a key", undefined=1)
R("c", "void main", r"\bvoid[ \t]+main[ \t]*\(", "int main(", "main must return int", auto=True)
R("c", "main()", r"(?m)^main[ \t]*\(", "int main(", "main must return int", auto=True)
R("c", "mian", r"(?<![\w.])mian(?=[ \t]*\()", "main", "Did you mean main?", auto=True, unless=r"\bmain\s*\(")
R("c", "exit()", r"(?<![\w.])exit\(\s*\)", "exit(0)", "exit() needs a status: exit(0)", auto=True)
R("c", "True", r"(?<![\w.'\"])(True|TRUE)(?![\w'\"])", "true", "C writes true in lowercase (<stdbool.h>)", auto=True, undefined=1)
R("c", "False", r"(?<![\w.'\"])(False|FALSE)(?![\w'\"])", "false", "C writes false in lowercase (<stdbool.h>)", auto=True, undefined=1)
R("c", "NULL", r"(?<![\w.'\"])(null|Null|nil|None|nullptr|NUll|Nul)(?![\w'\"])", "NULL", "C's null pointer is NULL", auto=True, undefined=1)
R("c", "elif", r"(?m)^([ \t]*\}?[ \t]*)(?:elif|elsif|elseif|elseIf)\b", "$1else if", "C writes it else if", auto=True)
R("c", "and", r"(?<=[\w)\]'\"])[ \t]+and[ \t]+(?=[\w(!'\"])", " && ", "C writes and as &&", auto=True, unless=r"iso646")
R("c", "or", r"(?<=[\w)\]'\"])[ \t]+or[ \t]+(?=[\w(!'\"])", " || ", "C writes or as ||", auto=True, unless=r"iso646")
R("c", "not", r"(?<![\w.])not[ \t]+(?=[\w(])", "!", "C writes not as !", auto=True, unless=r"iso646")
R("c", "string type", r"(?<![\w.])string[ \t]+(\w+)", "char *$1", "C has no string type; text is char * (or char name[size])", unless=r"\btypedef\b[^;]*\bstring\s*;")
R("c", "char =\"", r"\bchar[ \t]+(\w+)[ \t]*=[ \t]*\"", "char $1[] = \"", "Text needs a char array: char $1[] = \"…\"", auto=True)
R("c", "array []", r"(=[ \t]*)\[([^\]\n]*)\][ \t]*;", "$1{$2};", "C writes array values in braces: { … }", auto=True)
R("c", "if =", r"\bif[ \t]*\([ \t]*([\w.\[\]>-]+)[ \t]*=[ \t]*(?!=)([^)=\n]+)\)", "if ($1 == $2)", "A comparison needs == (a single = assigns)")
R("c", "loop ;", r"(?m)^([ \t]*(?:for|while)[ \t]*\(.*\))[ \t]*;[ \t]*$", "$1", "This ; ends the loop right here, so its body runs only once")
R("c", "^ power", r"([\w)\]]+)[ \t]*\^[ \t]*2\b", "$1 * $1", "^ is XOR in C; to square, multiply (or pow(x, 2))")

CPP_HEADERS = {"stdio": "cstdio", "stdlib": "cstdlib", "math": "cmath", "time": "ctime", "ctype": "cctype", "stdint": "cstdint", "limits": "climits",
               "assert": "cassert", "errno": "cerrno", "stddef": "cstddef", "float": "cfloat", "stdarg": "cstdarg"}
for c, cpp in CPP_HEADERS.items():
    R("cpp", f"#include <{c}>", rf"(?m)^([ \t]*#[ \t]*include[ \t]*)<{c}>", f"$1<{cpp}>", f"In C++ it's <{cpp}> (or <{c}.h>)", auto=True)
R("cpp", "#include typo", r"(?m)^([ \t]*)#[ \t]*(?:incldue|inlcude|inculde|includ|incude|inclde|Include|INCLUDE|imclude|icnlude|incluce|inclue)\b", "$1#include", "It's #include", auto=True)
R("cpp", "iostream.h", r"(?m)^([ \t]*#[ \t]*include[ \t]*)<iostream\.h>", "$1<iostream>", "Modern C++ headers have no .h: <iostream>", auto=True)
R("cpp", "bits/stdc++", r"(?m)^[ \t]*#[ \t]*include[ \t]*<bits/stdc\+\+\.h>",
  "#include <iostream>\n#include <vector>\n#include <string>\n#include <algorithm>\n#include <map>\n#include <set>\n#include <cmath>",
  "macOS's compiler has no <bits/stdc++.h>; these are the headers it stands for", auto=True)
R("cpp", "malloc.h", r"(?m)^([ \t]*#[ \t]*include[ \t]*)<malloc\.h>", "$1<cstdlib>", "macOS has malloc in <cstdlib>", auto=True)
R("cpp", "cout >>", r"\b((?:std::)?cout)[ \t]*>>", "$1 <<", "Output goes into cout with <<", auto=True)
R("cpp", "cin <<", r"\b((?:std::)?cin)[ \t]*<<", "$1 >>", "Input comes out of cin with >>", auto=True)
R("cpp", "std::", r"(?<![\w:.])(cout|cin|cerr|endl|getline)\b", "std::$1", "$1 lives in std:: (or add using namespace std;)", unless=r"using\s+namespace\s+std|using\s+std::")
R("cpp", "nullptr", r"(?<![\w.'\"])(null|Null|nil|None)(?![\w'\"])", "nullptr", "C++'s null pointer is nullptr", auto=True, undefined=1)
R("cpp", "True", r"(?<![\w.'\"])(True|TRUE)(?![\w'\"])", "true", "C++ writes true in lowercase", auto=True, undefined=1)
R("cpp", "False", r"(?<![\w.'\"])(False|FALSE)(?![\w'\"])", "false", "C++ writes false in lowercase", auto=True, undefined=1)
R("cpp", "elif", r"(?m)^([ \t]*\}?[ \t]*)(?:elif|elsif|elseif|elseIf)\b", "$1else if", "C++ writes it else if", auto=True)
R("cpp", "void main", r"\bvoid[ \t]+main[ \t]*\(", "int main(", "main must return int", auto=True)
R("cpp", "mian", r"(?<![\w.])mian(?=[ \t]*\()", "main", "Did you mean main?", auto=True, unless=r"\bmain\s*\(")
R("cpp", ".push", r"\.push\(", ".push_back(", "Vectors add with .push_back() (stacks and queues use .push())", unless=r"\b(?:stack|queue|priority_queue)\s*<")
R("cpp", ".length", r"\.length\b(?![\w(])", ".length()", "In C++ length() is a function", unless=r"\blength\s*[;=]")
R("cpp", "print", r"(?<![\w.:])(print|println)(?=\s*\()", "printf", "C++ prints with std::cout << … or printf()", undefined=1)
R("cpp", "array []", r"(=[ \t]*)\[([^\]\n]*)\][ \t]*;", "$1{$2};", "C++ writes values in braces: { … }", auto=True)
R("cpp", "string.h", r"(?m)^([ \t]*#[ \t]*include[ \t]*)<string\.h>", "$1<string>", "std::string is in <string> (<string.h> is C's)", when=r"std::string|\bstring\s+\w")
R("cpp", "if =", r"\bif[ \t]*\([ \t]*([\w.\[\]>-]+)[ \t]*=[ \t]*(?!=)([^)=\n]+)\)", "if ($1 == $2)", "A comparison needs == (a single = assigns)")
R("cpp", "^ power", r"([\w)\]]+)[ \t]*\^[ \t]*2\b", "$1 * $1", "^ is XOR in C++; to square, multiply (or pow(x, 2))")

C_INCLUDES = {
    "stdio.h": "printf scanf fprintf fscanf sprintf snprintf sscanf puts fputs fgets putchar getchar fopen fclose fread fwrite fseek ftell rewind perror fflush getline FILE EOF stdin stdout stderr",
    "stdlib.h": "malloc calloc realloc free exit abort atexit atoi atof atol strtol strtod strtoul rand srand qsort bsearch system getenv abs labs EXIT_SUCCESS EXIT_FAILURE RAND_MAX",
    "string.h": "strlen strcpy strncpy strcat strncat strcmp strncmp strchr strrchr strstr strtok memcpy memmove memset memcmp strdup strndup strerror strspn strcspn",
    "math.h": "sqrt pow sin cos tan asin acos atan atan2 exp log log10 log2 fabs floor ceil round trunc fmod hypot cbrt M_PI INFINITY NAN isnan isinf fmin fmax",
    "ctype.h": "isalpha isdigit isalnum isspace isupper islower toupper tolower ispunct isxdigit isprint",
    "time.h": "time clock difftime localtime gmtime strftime mktime CLOCKS_PER_SEC clock_gettime nanosleep",
    "unistd.h": "sleep usleep getpid fork execvp pipe access getcwd chdir isatty",
    "stdbool.h": "bool true false",
    "stdint.h": "int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t intptr_t uintptr_t",
    "limits.h": "INT_MAX INT_MIN UINT_MAX LONG_MAX LONG_MIN CHAR_MAX CHAR_MIN",
    "assert.h": "assert", "errno.h": "errno", "signal.h": "signal raise SIGINT",
}
LANGS["c"]["imports"] = {name: f"#include <{h}>" for h, names in C_INCLUDES.items() for name in names.split()}
CPP_INCLUDES = {"iostream": "cout cin cerr endl", "vector": "vector", "string": "string getline to_string stoi stod",
                "map": "map", "set": "set", "unordered_map": "unordered_map", "algorithm": "sort reverse max_element min_element find count",
                "cmath": "sqrt pow fabs floor ceil", "cstdio": "printf scanf"}
LANGS["cpp"]["imports"] = {name: f"#include <{h}>" for h, names in CPP_INCLUDES.items() for name in names.split()}
C_COMMON = sorted({n for names in C_INCLUDES.values() for n in names.split()} | set("main argc argv sizeof NULL size_t".split()))
LANGS["c"]["builtins"] = C_COMMON
LANGS["cpp"]["builtins"] = C_COMMON + "std cout cin cerr endl string vector map set pair make_pair unordered_map sort find begin end size push_back emplace_back nullptr unique_ptr shared_ptr make_unique make_shared to_string stoi getline".split()
C_KEYWORDS = "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while".split()
LANGS["c"]["keywords"] = C_KEYWORDS
LANGS["cpp"]["keywords"] = C_KEYWORDS + "class namespace template typename public private protected virtual override new delete this throw try catch using operator friend explicit constexpr noexcept bool true false".split()
LANGS["cpp"]["methods"] = "push_back emplace_back pop_back size length empty clear insert erase find at front back begin end substr c_str first second count reserve resize".split()

# ---------------------------------------------------------------- Java

R("java", "System case", r"(?<![\w.])(?:system|SYSTEM)\.(in|out|err)\b", "System.$1", "It's System with a capital S", auto=True, undefined=None)
R("java", "System.Out", r"\bSystem\.(?:Out|OUT)\.", "System.out.", "It's System.out", auto=True)
R("java", "println alias", r"\bSystem\.out\.(?:printLn|PrintLn|Println|printline|print_line|prinln|printn|pritnln|println_|writeLine|WriteLine|log|write|printLine|prinltn|pirntln)(?=\s*\()",
  "System.out.println", "It's System.out.println()", auto=True)
R("java", "console.log", r"(?<![\w.])(console)\.log(?=\s*\()", "System.out.println", "Java prints with System.out.println()", auto=True, undefined=1)
R("java", "print bare", r"(?<![\w.])(print|println)(?=\s*\()", "System.out.println", "Java prints with System.out.println()", auto=True, undefined=1)
R("java", "printf bare", r"(?<![\w.])(printf)(?=\s*\()", "System.out.printf", "Java's printf is System.out.printf()", auto=True, undefined=1)
R("java", "string type", r"(?<![\w.])string(?=[ \t]+\w|[ \t]*\[|[ \t]*>|[ \t]*\.\.\.)", "String", "Java's text type is String (capital S)", auto=True, unless=r"\bclass\s+string\b")
R("java", "bool type", r"(?<![\w.])bool(?=[ \t]+\w)", "boolean", "Java's true/false type is boolean", auto=True, unless=r"\bclass\s+bool\b")
R("java", "Int type", r"(?<![\w.])(?:Int|integer)(?=[ \t]+[a-z]\w*[ \t]*[=;,)])", "int", "Java's whole-number type is int", auto=True, unless=r"\bclass\s+(?:Int|integer)\b")
R("java", "Integer.parse", r"\bInteger\.(?:parse|parseInteger|fromString|toInt|parseint|ParseInt)(?=\s*\()", "Integer.parseInt", "It's Integer.parseInt(text)", auto=True)
R("java", "Double.parse", r"\bDouble\.(?:parse|parsedouble|ParseDouble|toDouble)(?=\s*\()", "Double.parseDouble", "It's Double.parseDouble(text)", auto=True)
R("java", "Thread.wait", r"\bThread\.(?:wait|delay|pause)(?=\s*\()", "Thread.sleep", "It's Thread.sleep(milliseconds)", auto=True)
R("java", "string ==", r"(?<![\w.])([A-Za-z_][\w.]*(?:\(\))?)[ \t]*==[ \t]*(\"(?:[^\"\\\n]|\\.)*\")", "$1.equals($2)", "== compares objects, not text; use .equals()")
R("java", "string !=", r"(?<![\w.])([A-Za-z_][\w.]*(?:\(\))?)[ \t]*!=[ \t]*(\"(?:[^\"\\\n]|\\.)*\")", "!$1.equals($2)", "!= compares objects, not text; use !….equals()")
R("java", "True", r"(?<![\w.'\"])(True|TRUE)(?![\w'\"])", "true", "Java writes true in lowercase", auto=True, undefined=1)
R("java", "False", r"(?<![\w.'\"])(False|FALSE)(?![\w'\"])", "false", "Java writes false in lowercase", auto=True, undefined=1)
R("java", "null", r"(?<![\w.'\"])(None|nil|NULL|Null|nullptr|undefined)(?![\w'\"])", "null", "Java's “nothing” is null", auto=True, undefined=1)
R("java", "elif", r"(?m)^([ \t]*\}?[ \t]*)(?:elif|elsif|elseif|elseIf)\b", "$1else if", "Java writes it else if", auto=True)
R("java", "and", r"(?<=[\w)\]'\"])[ \t]+and[ \t]+(?=[\w(!'\"])", " && ", "Java writes and as &&", auto=True)
R("java", "or", r"(?<=[\w)\]'\"])[ \t]+or[ \t]+(?=[\w(!'\"])", " || ", "Java writes or as ||", auto=True)
R("java", "not", r"(?<![\w.])not[ \t]+(?=[\w(])", "!", "Java writes not as !", auto=True)
R("java", "mian", r"\bstatic[ \t]+void[ \t]+mian(?=[ \t]*\()", "static void main", "Did you mean main?", auto=True)
R("java", "^ power", r"([\w)\]]+)[ \t]*\^[ \t]*(\d+)\b", "Math.pow($1, $2)", "^ is XOR in Java; powers are Math.pow(x, y)")
LANGS["java"]["imports"] = {
    **{n: f"import java.util.{n};" for n in "Scanner ArrayList List HashMap Map HashSet Set Random Arrays Collections LinkedList Queue Deque ArrayDeque Iterator Optional Stack TreeMap TreeSet PriorityQueue Objects".split()},
    **{n: f"import java.io.{n};" for n in "File FileReader BufferedReader InputStreamReader IOException FileWriter PrintWriter".split()},
    **{n: f"import java.time.{n};" for n in "LocalDate LocalDateTime Duration".split()},
    "Collectors": "import java.util.stream.Collectors;",
}
LANGS["java"]["members"] = {
    "Math": "abs max min pow sqrt cbrt round floor ceil random sin cos tan asin acos atan atan2 log log10 exp hypot signum toRadians toDegrees floorDiv floorMod PI E rint log1p expm1 sinh cosh tanh ulp addExact multiplyExact".split(),
    "System": "out err in currentTimeMillis nanoTime exit arraycopy getProperty getenv lineSeparator identityHashCode gc".split(),
    "Integer": "parseInt valueOf MAX_VALUE MIN_VALUE toString toBinaryString toHexString toOctalString compare sum max min bitCount reverse signum".split(),
    "Double": "parseDouble valueOf MAX_VALUE MIN_VALUE isNaN isInfinite compare toString POSITIVE_INFINITY NEGATIVE_INFINITY NaN sum max min".split(),
    "String": "valueOf format join copyValueOf".split(),
    "Arrays": "sort toString asList fill copyOf copyOfRange stream equals binarySearch deepToString hashCode setAll parallelSort".split(),
    "Collections": "sort reverse shuffle max min unmodifiableList unmodifiableMap emptyList emptyMap singletonList frequency swap addAll nCopies reverseOrder".split(),
    "Thread": "sleep currentThread onSpinWait yield".split(),
    "Character": "isDigit isLetter isLetterOrDigit isUpperCase isLowerCase toUpperCase toLowerCase isWhitespace getNumericValue isAlphabetic".split(),
    "Boolean": "parseBoolean valueOf TRUE FALSE toString".split(),
    "Long": "parseLong valueOf MAX_VALUE MIN_VALUE toString".split(),
    "Objects": "equals hash requireNonNull isNull nonNull toString hashCode".split(),
}
LANGS["java"]["builtins"] = "System String Math Integer Double Boolean Long Character List ArrayList Map HashMap Set HashSet Scanner Arrays Collections Exception RuntimeException Object Override main args this super null true false Optional Thread StringBuilder".split()
LANGS["java"]["keywords"] = "abstract assert boolean break byte case catch char class continue default do double else enum extends final finally float for if implements import instanceof int interface long new package private protected public return short static super switch synchronized this throw throws try void volatile while var record".split()
LANGS["java"]["methods"] = "println print printf equals equalsIgnoreCase length charAt substring indexOf lastIndexOf toUpperCase toLowerCase trim split contains startsWith endsWith replace isEmpty size add get set remove put containsKey getOrDefault keySet values entrySet getKey getValue toString hashCode compareTo nextInt nextLine nextDouble next hasNext hasNextInt hasNextLine close stream forEach map filter collect sort".split()

# ---------------------------------------------------------------- Swift

R("swift", "println", r"(?<![\w.])(println)(?=\s*\()", "print", "Swift prints with print()", auto=True, undefined=1)
R("swift", "console.log", r"(?<![\w.])(console)\.log(?=\s*\()", "print", "Swift prints with print()", auto=True, undefined=1)
R("swift", "System.out", r"(?<![\w.])(System)\.out\.print(?:ln)?(?=\s*\()", "print", "Swift prints with print()", auto=True, undefined=1)
R("swift", ".count()", r"\.count\(\)", ".count", ".count is a property — no ()", auto=True)
R("swift", ".length", r"\.(?:length|size|len)\b(?:\(\))?", ".count", "Swift collections and strings use .count", auto=True, unless=r"\b(?:var|let)\s+(?:length|size|len)\b|\bfunc\s+(?:length|size|len)\b")
R("swift", ".push", r"\.(?:push|push_back|pushBack)\(", ".append(", "Swift arrays use .append()", auto=True, unless=r"\bfunc\s+(?:push|push_back|pushBack)\b")
R("swift", ".add", r"\.add\(", ".append(", "Arrays use .append() (Sets use .insert())", unless=r"\bfunc\s+add\b")
R("swift", ".toUpperCase", r"\.(?:toUpperCase|upper|toUpper|uppercase)\(\)", ".uppercased()", "Swift strings use .uppercased()", auto=True)
R("swift", ".toLowerCase", r"\.(?:toLowerCase|lower|toLower|lowercase)\(\)", ".lowercased()", "Swift strings use .lowercased()", auto=True)
R("swift", ".trim", r"\.(?:trim|strip)\(\)", ".trimmingCharacters(in: .whitespacesAndNewlines)", "Swift trims with .trimmingCharacters(in:)", auto=True)
R("swift", ".includes", r"\.includes\(", ".contains(", "Swift uses .contains()", auto=True)
R("swift", ".indexOf", r"\.indexOf\(", ".firstIndex(of: ", "Swift finds positions with .firstIndex(of:)", auto=True)
R("swift", ".startsWith", r"\.(?:startsWith|startswith)\(", ".hasPrefix(", "Swift strings use .hasPrefix()", auto=True)
R("swift", ".endsWith", r"\.(?:endsWith|endswith)\(", ".hasSuffix(", "Swift strings use .hasSuffix()", auto=True)
R("swift", "True", r"(?<![\w.'\"])(True|TRUE)(?![\w'\"])", "true", "Swift writes true in lowercase", auto=True, undefined=1)
R("swift", "False", r"(?<![\w.'\"])(False|FALSE)(?![\w'\"])", "false", "Swift writes false in lowercase", auto=True, undefined=1)
R("swift", "nil", r"(?<![\w.'\"])(None|null|NULL|Null|nullptr|undefined)(?![\w'\"])", "nil", "Swift's “nothing” is nil", auto=True, undefined=1)
R("swift", "elif", r"(?m)^([ \t]*\}?[ \t]*)(?:elif|elsif|elseif|elseIf)\b", "$1else if", "Swift writes it else if", auto=True)
R("swift", "def", r"(?m)^([ \t]*)(?:def|function|fun|fn)[ \t]+(\w+)[ \t]*\(", "$1func $2(", "Swift defines functions with func", auto=True)
R("swift", "const", r"(?m)^([ \t]*)const[ \t]+", "$1let ", "Swift constants use let", auto=True)
R("swift", "and", r"(?<=[\w)\]'\"])[ \t]+and[ \t]+(?=[\w(!'\"])", " && ", "Swift writes and as &&", auto=True)
R("swift", "or", r"(?<=[\w)\]'\"])[ \t]+or[ \t]+(?=[\w(!'\"])", " || ", "Swift writes or as ||", auto=True)
R("swift", "not", r"(?<![\w.])not[ \t]+(?=[\w(])", "!", "Swift writes not as !", auto=True)
R("swift", "Int(readLine())", r"\b(Int|Double)\(\s*readLine\(\)\s*\)", "$1(readLine() ?? \"\")", "readLine() can return nil; give it a fallback", auto=True)
R("swift", "sleep fraction", r"(?<![\w.])sleep\(\s*(\d+\.\d+)\s*\)", "Thread.sleep(forTimeInterval: $1)", "sleep() takes whole seconds; Thread.sleep(forTimeInterval:) takes fractions", auto=True)
LANGS["swift"]["keywords"] = "associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private protocol public rethrows static struct subscript typealias var break case continue default defer do else fallthrough for guard if in repeat return switch where while as catch is super throw throws try async await actor some any".split()
LANGS["swift"]["builtins"] = "print Int String Double Float Bool Array Dictionary Set Character Optional Result Error true false nil self Self min max abs zip stride readLine".split()
LANGS["swift"]["methods"] = "append count isEmpty contains first last map filter reduce sorted sort insert remove removeAll removeFirst removeLast joined split uppercased lowercased hasPrefix hasSuffix replacingOccurrences trimmingCharacters description keys values enumerated reversed firstIndex lastIndex compactMap flatMap forEach prefix suffix dropFirst dropLast".split()

# ---------------------------------------------------------------- Go

R("go", "time.wait", r"(?<![\w.])time\.(?:wait|delay|pause|sleep)(?=\s*\()", "time.Sleep", "Go pauses with time.Sleep(duration)", auto=True)
R("go", "time.Sleep n", r"(?<![\w.])time\.Sleep\(\s*(\d+)\s*\)", "time.Sleep($1 * time.Second)", "time.Sleep takes a Duration; a bare number is nanoseconds")
R("go", "nil", r"(?<![\w.'\"])(None|null|NULL|Null|nullptr|undefined)(?![\w'\"])", "nil", "Go's “nothing” is nil", auto=True, undefined=1)
R("go", "True", r"(?<![\w.'\"])(True|TRUE)(?![\w'\"])", "true", "Go writes true in lowercase", auto=True, undefined=1)
R("go", "False", r"(?<![\w.'\"])(False|FALSE)(?![\w'\"])", "false", "Go writes false in lowercase", auto=True, undefined=1)
R("go", "elif", r"(?m)^([ \t]*\}?[ \t]*)(?:elif|elsif|elseif|elseIf)\b", "$1else if", "Go writes it else if", auto=True)
R("go", "def", r"(?m)^([ \t]*)(?:def|function|fun|fn)[ \t]+(\w+)[ \t]*\(", "$1func $2(", "Go defines functions with func", auto=True)
R("go", "while", r"(?m)^([ \t]*)while\b[ \t]*", "$1for ", "Go has no while; for does it all", auto=True)
R("go", "and", r"(?<=[\w)\]'\"])[ \t]+and[ \t]+(?=[\w(!'\"])", " && ", "Go writes and as &&", auto=True)
R("go", "or", r"(?<=[\w)\]'\"])[ \t]+or[ \t]+(?=[\w(!'\"])", " || ", "Go writes or as ||", auto=True)
R("go", "not", r"(?<![\w.])not[ \t]+(?=[\w(])", "!", "Go writes not as !", auto=True)
R("go", "console.log", r"(?<![\w.])(console)\.log(?=\s*\()", "fmt.Println", "Go prints with fmt.Println()", auto=True, undefined=1)
R("go", "print", r"(?<![\w.])print(?:ln)?(?=\s*\()", "fmt.Println", "print() writes to stderr without formatting; fmt.Println() is the usual way")
R("go", ".length", r"(?<![\w.])([A-Za-z_][\w.]*)\.(?:length|len|size|count|Len)\b(?:\(\))?", "len($1)", "Go gets a length with len(x)", auto=True, unless=r"\bfunc\s*\([^)]*\)\s*(?:length|len|size|count|Len)\b")
R("go", ".append", r"(?<![\w.])([A-Za-z_][\w.]*)\.(?:append|push)\(([^()\n]*)\)", "$1 = append($1, $2)", "Go appends with x = append(x, item)", auto=True, unless=r"\bfunc\s*\([^)]*\)\s*(?:append|push)\b")
LANGS["go"]["members"] = {
    "fmt": "Println Printf Print Sprintf Sprint Sprintln Errorf Scan Scanln Scanf Fprintf Fprintln Fprint Sscanf Sscan Stringer".split(),
    "strings": "Split Join Contains ToUpper ToLower TrimSpace Trim TrimLeft TrimRight TrimPrefix TrimSuffix Replace ReplaceAll HasPrefix HasSuffix Index LastIndex Fields Repeat Count EqualFold Title Builder NewReader NewReplacer SplitN Map".split(),
    "strconv": "Itoa Atoi ParseInt ParseFloat ParseBool FormatInt FormatFloat Quote Unquote".split(),
    "os": "Exit Args Open Create ReadFile WriteFile Getenv Setenv Remove RemoveAll Mkdir MkdirAll Stdin Stdout Stderr Getwd Chdir Stat IsNotExist Environ Hostname".split(),
    "time": "Sleep Now Since Until Duration Second Millisecond Microsecond Nanosecond Minute Hour Tick NewTicker NewTimer After AfterFunc Parse Date Unix UnixMilli Time Month Weekday RFC3339 Kitchen".split(),
    "math": "Sqrt Pow Abs Max Min Floor Ceil Round Trunc Pi E Inf NaN IsNaN IsInf Log Log2 Log10 Exp Sin Cos Tan Hypot Mod MaxInt MinInt MaxInt64 MaxFloat64 Cbrt".split(),
    "sort": "Ints Strings Float64s Slice SliceStable Sort Search SearchInts".split(),
    "errors": "New Is As Unwrap Join".split(),
    "sync": "WaitGroup Mutex RWMutex Once Map Pool Cond".split(),
    "bufio": "NewReader NewWriter NewScanner ScanLines ScanWords Scanner Reader Writer".split(),
    "rand": "Intn Int Float64 Seed Shuffle Perm New NewSource Int63".split(),
    "json": "Marshal Unmarshal MarshalIndent NewEncoder NewDecoder".split(),
    "http": "Get Post HandleFunc ListenAndServe NewRequest Client Request Response ResponseWriter StatusOK StatusNotFound Handle FileServer Dir".split(),
    "filepath": "Join Base Dir Ext Abs Walk WalkDir Glob Rel Split Clean".split(),
}
LANGS["go"]["keywords"] = "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var".split()
LANGS["go"]["builtins"] = "append cap close complex copy delete imag len make new panic print println real recover string int int64 float64 bool byte rune error true false nil iota any".split()

# ---------------------------------------------------------------- Rust

R("rust", "macro !", r"(?<![\w.!])(println|print|eprintln|eprint|format|vec|panic|assert|assert_eq|assert_ne|write|writeln|todo|unimplemented|dbg)(?=\s*\()", "$1!",
  "$1 is a macro: $1!(…)", auto=True, unless=r"\bfn\s+(?:println|print|eprintln|format|vec|panic|assert|write|writeln|dbg)\b")
R("rust", "console.log", r"(?<![\w.])(console)\.log(?=\s*\()", "println!", "Rust prints with println!()", auto=True, undefined=1)
R("rust", "printf", r"(?<![\w.])(printf)(?=\s*\()", "println!", "Rust prints with println!()", auto=True, undefined=1)
R("rust", "True", r"(?<![\w.'\"])(True|TRUE)(?![\w'\"])", "true", "Rust writes true in lowercase", auto=True, undefined=1)
R("rust", "False", r"(?<![\w.'\"])(False|FALSE)(?![\w'\"])", "false", "Rust writes false in lowercase", auto=True, undefined=1)
R("rust", "None", r"(?<![\w.'\"])(null|nil|NULL|Null|nullptr|undefined)(?![\w'\"])", "None", "Rust has no null; an empty Option is None", auto=True, undefined=1)
R("rust", "elif", r"(?m)^([ \t]*\}?[ \t]*)(?:elif|elsif|elseif|elseIf)\b", "$1else if", "Rust writes it else if", auto=True)
R("rust", "def", r"(?m)^([ \t]*)(?:def|function|func|fun)[ \t]+(\w+)[ \t]*\(", "$1fn $2(", "Rust defines functions with fn", auto=True)
R("rust", "and", r"(?<=[\w)\]'\"])[ \t]+and[ \t]+(?=[\w(!'\"])", " && ", "Rust writes and as &&", auto=True)
R("rust", "or", r"(?<=[\w)\]'\"])[ \t]+or[ \t]+(?=[\w(!'\"])", " || ", "Rust writes or as ||", auto=True)
R("rust", "not", r"(?<![\w.])not[ \t]+(?=[\w(])", "!", "Rust writes not as !", auto=True)
R("rust", ".length", r"\.(?:length|size)\b(?:\(\))?", ".len()", "Rust uses .len()", auto=True, unless=r"\bfn\s+(?:length|size)\b")
R("rust", ".add", r"\.(?:add|push_back|pushBack)\(", ".push(", "Vec adds with .push()", auto=True, unless=r"\bfn\s+(?:add|push_back|pushBack)\b|\bimpl\s+Add\b|HashSet|BTreeSet")
R("rust", "String::new(\"", r"\bString::new\(\s*\"", "String::from(\"", "String::new() makes an empty string; String::from(\"…\") makes one with text", auto=True)
R("rust", ".toUpperCase", r"\.(?:toUpperCase|upper|toUpper)\(\)", ".to_uppercase()", "Rust uses .to_uppercase()", auto=True)
R("rust", ".toLowerCase", r"\.(?:toLowerCase|lower|toLower)\(\)", ".to_lowercase()", "Rust uses .to_lowercase()", auto=True)
R("rust", ".strip", r"\.strip\(\)", ".trim()", "Rust uses .trim()", auto=True)
R("rust", ".includes", r"\.includes\(", ".contains(", "Rust uses .contains()", auto=True)
R("rust", ".toString", r"\.(?:toString|ToString|tostring)\(\)", ".to_string()", "Rust uses .to_string()", auto=True)
LANGS["rust"]["keywords"] = "as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return static struct super trait type unsafe use where while".split()
LANGS["rust"]["builtins"] = "println print eprintln format vec panic assert assert_eq String Vec Option Result Some None Ok Err Box HashMap HashSet BTreeMap self Self true false".split()
LANGS["rust"]["methods"] = "len push pop iter iter_mut into_iter map collect unwrap expect clone to_string as_str is_empty contains insert remove get sort sort_by join split trim chars bytes enumerate filter rev sum count min max find any all fold zip lines parse to_uppercase to_lowercase starts_with ends_with replace".split()

PY_KEYWORDS_EXTRA = []
LANGS["python"]["builtins"] = ["self", "cls"]

if __name__ == "__main__":
    for lang in LANGS.values():
        for key in ("keywords", "builtins", "methods"):
            if key in lang: lang[key] = sorted(set(lang[key]))
    path = os.path.join(os.path.dirname(__file__), "..", "..", "Resources", "Fixes", "rules.json")
    with open(path, "w") as f:
        json.dump(LANGS, f, indent=1, ensure_ascii=False)
    total = sum(len(l["rules"]) for l in LANGS.values())
    print(f"wrote {os.path.normpath(path)}: {total} rules —", ", ".join(f"{k} {len(v['rules'])}" for k, v in LANGS.items()))
