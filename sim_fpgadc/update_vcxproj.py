"""
Rewrites ConsoleApplication1.vcxproj and .vcxproj.filters so that all
Vsimtop* ClCompile / ClInclude entries exactly match the Verilator manifest.
Run after every verilate.sh invocation (verilate.sh calls this automatically).

Usage:
    python update_vcxproj.py <manifest> <vcxproj> <filters>
"""
import sys, re, xml.etree.ElementTree as ET
from pathlib import PurePosixPath

manifest_path, vcxproj_path, filters_path = sys.argv[1], sys.argv[2], sys.argv[3]

# ---- Parse manifest for Vsimtop .cpp / .h targets ----
cpp_files, h_files = [], []
with open(manifest_path) as f:
    for line in f:
        m = re.match(r'^T\s+\S+\s+\S+.*?"(out/obj_dir/(Vsimtop[^"]+))"', line)
        if not m:
            continue
        base = PurePosixPath(m.group(2)).name
        if base.endswith('.cpp'):
            cpp_files.append(base)
        elif base.endswith('.h'):
            h_files.append(base)

cpp_files = sorted(set(cpp_files))
h_files   = sorted(set(h_files))

# Path prefix as MSVC sees it (relative to ConsoleApplication1/)
def win_path(base):
    return '..\\out\\obj_dir\\' + base

ET.register_namespace('', 'http://schemas.microsoft.com/developer/msbuild/2003')
NS  = 'http://schemas.microsoft.com/developer/msbuild/2003'

def ns(local):
    return '{' + NS + '}' + local

def fix_declaration(path):
    """ET writes standalone='no'; strip to plain version+encoding declaration."""
    with open(path, 'r', encoding='utf-8') as fh:
        text = fh.read()
    text = re.sub(r"<\?xml[^?]*\?>", '<?xml version="1.0" encoding="utf-8"?>', text)
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(text)

# ---- Rewrite .vcxproj ----
tree = ET.parse(vcxproj_path)
root = tree.getroot()

# Strip existing Vsimtop ClCompile / ClInclude items.
for ig in root.findall(ns('ItemGroup')):
    for child in list(ig):
        base = child.get('Include', '').replace('\\', '/').split('/')[-1]
        if base.startswith('Vsimtop') and child.tag in (ns('ClCompile'), ns('ClInclude')):
            ig.remove(child)

# Remove now-empty ItemGroups (keep labelled config/platform groups).
for ig in list(root.findall(ns('ItemGroup'))):
    if not ig.get('Label') and len(ig) == 0:
        root.remove(ig)

# Append fresh ItemGroups from manifest.
ig_cpp = ET.SubElement(root, ns('ItemGroup'))
for base in cpp_files:
    ET.SubElement(ig_cpp, ns('ClCompile')).set('Include', win_path(base))

ig_h = ET.SubElement(root, ns('ItemGroup'))
for base in h_files:
    ET.SubElement(ig_h, ns('ClInclude')).set('Include', win_path(base))

ET.indent(tree, space='  ')
tree.write(vcxproj_path, encoding='utf-8', xml_declaration=True)
fix_declaration(vcxproj_path)

# ---- Rewrite .vcxproj.filters ----
tree2 = ET.parse(filters_path)
root2 = tree2.getroot()

# Strip existing Vsimtop ClCompile / ClInclude items.
for ig in root2.findall(ns('ItemGroup')):
    for child in list(ig):
        base = child.get('Include', '').replace('\\', '/').split('/')[-1]
        if base.startswith('Vsimtop') and child.tag in (ns('ClCompile'), ns('ClInclude')):
            ig.remove(child)

# Remove empty ItemGroups (preserve Filter-definition groups).
for ig in list(root2.findall(ns('ItemGroup'))):
    if not any(c.tag == ns('Filter') for c in ig) and len(ig) == 0:
        root2.remove(ig)

VSIMTOP_FILTER = 'Source Files\\Vsimtop'

ig_cpp2 = ET.SubElement(root2, ns('ItemGroup'))
for base in cpp_files:
    el = ET.SubElement(ig_cpp2, ns('ClCompile'))
    el.set('Include', win_path(base))
    ET.SubElement(el, ns('Filter')).text = VSIMTOP_FILTER

ig_h2 = ET.SubElement(root2, ns('ItemGroup'))
for base in h_files:
    el = ET.SubElement(ig_h2, ns('ClInclude'))
    el.set('Include', win_path(base))
    ET.SubElement(el, ns('Filter')).text = VSIMTOP_FILTER

ET.indent(tree2, space='  ')
tree2.write(filters_path, encoding='utf-8', xml_declaration=True)
fix_declaration(filters_path)

print(f"vcxproj: {len(cpp_files)} .cpp + {len(h_files)} .h Vsimtop files")
print(f"filters: same set, all in 'Source Files\\Vsimtop'")
