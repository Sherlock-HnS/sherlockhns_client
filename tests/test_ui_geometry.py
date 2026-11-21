from pathlib import Path
from validate_ui import run
source=Path('tests/ui_geometry_test.lua').read_text(encoding='utf-8-sig')
source=source.replace('-- PRODUCTION_SOURCE',Path('addon/lua/sherlockhns_client/cl_ui.lua').read_text(encoding='utf-8-sig'))
run('print = function() end' + '\n' + source,'UI geometry integration',True)
print('PASS: geometry invariants across 9 viewports, resize, wrapping, sidebar reflow and text bounds')
