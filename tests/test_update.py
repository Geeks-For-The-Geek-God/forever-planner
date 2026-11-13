import os, sys
from lupa.lua51 import LuaRuntime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness
S = os.path.dirname(os.path.abspath(__file__)); A = os.path.join(S, "..", "ForeverPlanner") + "/"
fails = []
def check(c, m):
    print(("PASS " if c else "FAIL ") + m)
    if not c: fails.append(m)

def session(saved_db, saved_char):
    lua = LuaRuntime(unpack_returned_tuples=True); G = lua.globals()
    def load(p):
        lua.eval("function(src,n) local f,e=loadstring(src,n); if not f then error(e) end; return f end")(open(p).read(), p)()
    load(os.path.join(S, "wowstub.lua"))
    lua.execute(saved_db); lua.execute(saved_char)
    for f in harness.toc_files(routes=False): load(A + f)
    lua.execute('FireEvent("ADDON_LOADED","ForeverPlanner"); FireEvent("PLAYER_LOGIN")')
    return [l for l in G.OUT.values()], G

ver = open(A + "ForeverPlanner.toc").read().split("## Version:")[1].split()[0]
out, G = session("ForeverPlannerDB = nil", "ForeverPlannerChar = nil")
check(not any("Updated" in l for l in out), "fresh install: no update notice")
check(G.ForeverPlannerDB.lastVersion == ver, "fresh install records the version")
out, G = session('ForeverPlannerDB = { titles = {}, lastVersion = "0.0.1" }', "ForeverPlannerChar = nil")
check(any(("Updated 0.0.1 -> %s" % ver) in l for l in out) and any("New:" in l for l in out), "update notice with news after an update")
out, G = session('ForeverPlannerDB = { titles = {} }', 'ForeverPlannerChar = { doneIds = { [1] = "X" } }')
check(any("Updated an earlier version" in l for l in out), "existing user from before version tracking gets the notice")
out, G = session('ForeverPlannerDB = { titles = {}, lastVersion = "%s" }' % ver, "ForeverPlannerChar = nil")
check(not any("Updated" in l for l in out), "same version: no notice")
print("FAILURES:", len(fails))
sys.exit(1 if fails else 0)
