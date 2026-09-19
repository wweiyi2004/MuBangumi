"""Fail CI on dependency cycles, reversed feature layers or global auth services."""
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
ALLOWED_CORE_HOSTS={
    ('lib/core/widget/home_widget_sync_host.dart','lib/state/rss_controller.dart'),
    ('lib/core/widget/home_widget_sync_host.dart','lib/state/schedule_controller.dart'),
}

def cycles(graph):
    stack=[];active=set();visited=set();found=[]
    def visit(node):
        if node in active:
            found.append(stack[stack.index(node):]+[node]);return
        if node in visited:return
        visited.add(node);active.add(node);stack.append(node)
        for target in graph.get(node,[]):visit(target)
        stack.pop();active.remove(node)
    for node in graph:visit(node)
    return found

def audit(root):
    graph={};errors=[]
    for file in sorted((root/'lib').rglob('*.dart')):
        name=file.relative_to(root).as_posix();source=file.read_text(encoding='utf-8-sig');targets=[]
        if re.search(r'\b(?:CommunityService|PmService)\.shared\b',source):errors.append(f'{name}: process-wide authenticated service')
        for ref in re.findall(r"^\s*(?:import|export)\s+['\"]([^'\"]+)['\"]",source,re.M):
            if ref.startswith('package:mubangumi/'):target=root/'lib'/ref[len('package:mubangumi/'):]
            elif ':' not in ref:target=(file.parent/ref).resolve()
            else:continue
            if not target.is_file() or not target.is_relative_to(root/'lib'):continue
            dest=target.relative_to(root).as_posix();targets.append(dest)
            if '/application/' in name and dest.startswith(('lib/state/','lib/screens/','lib/widgets/','lib/navigation/')):errors.append(f'{name} -> {dest}: application depends on presentation/state')
            if name.startswith('lib/models/') and dest.startswith(('lib/core/storage/','lib/state/','lib/screens/','lib/widgets/')):errors.append(f'{name} -> {dest}: model depends on an implementation')
            if name.startswith('lib/core/') and dest.startswith(('lib/state/','lib/screens/','lib/widgets/')) and (name,dest) not in ALLOWED_CORE_HOSTS:errors.append(f'{name} -> {dest}: new reverse core dependency')
        graph[name]=targets
    errors.extend('Dependency cycle: '+' -> '.join(c) for c in cycles(graph))
    return graph,errors

if __name__=='__main__':
    if '--self-test' in sys.argv:
        assert cycles({'a':['b'],'b':['a']})
        assert not cycles({'a':['b'],'b':[]})
        assert cycles({'a':['a']})
        print('Architecture graph checks passed.')
    graph,errors=audit(ROOT)
    if errors:
        print('\n'.join(errors));raise SystemExit(1)
    print(f'Architecture boundaries passed: {len(graph)} Dart files; no import/export cycles or global auth services.')
