import ctypes,os
from pathlib import Path
base=Path(r'C:\Program Files (x86)\Steam\steamapps\common\GarrysMod')
handles=[os.add_dll_directory(str(base/p)) for p in ['bin/win64','garrysmod/bin/win64','bin']]
lua=ctypes.CDLL(str(base/'garrysmod/bin/win64/lua_shared.dll'))
lua.luaL_newstate.restype=ctypes.c_void_p
lua.luaL_loadbuffer.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_size_t,ctypes.c_char_p]
lua.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lua.lua_tolstring.restype=ctypes.c_char_p
lua.lua_close.argtypes=[ctypes.c_void_p]
lua.luaL_openlibs.argtypes=[ctypes.c_void_p]
lua.lua_pcall.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int]
def run(source,name,execute=False):
 state=lua.luaL_newstate()
 try:
  data=source.encode('utf-8-sig').removeprefix(b'\xef\xbb\xbf')
  result=lua.luaL_loadbuffer(state,data,len(data),name.encode())
  if execute and not result:
   lua.luaL_openlibs(state);result=lua.lua_pcall(state,0,0,0)
  if result: raise AssertionError(name+': '+lua.lua_tolstring(state,-1,None).decode())
 finally: lua.lua_close(state)
if __name__=='__main__':
 files=list(Path('addon/lua').rglob('*.lua'))
 for p in files: run(p.read_text(encoding='utf-8-sig'),str(p))
 print(f'PASS: {len(files)} Lua files compile using installed Garry\'s Mod Lua runtime')
