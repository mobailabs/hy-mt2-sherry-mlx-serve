import re, sys

path, rel = sys.argv[1], sys.argv[2]
src = open(path).read()
out = re.sub(r'\.path = "[^"]*"', '.path = "%s"' % rel, src, count=1)
if out != src:
    open(path, "w").write(out)
