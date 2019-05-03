# $HOME/.gdbinit
# ┌─────────────────┐
# │┏━╸╺┳┓┏┓ ╻┏┓╻╻╺┳╸│
# │┃╺┓ ┃┃┣┻┓┃┃┗┫┃ ┃ │
# │┗━┛╺┻┛┗━┛╹╹ ╹╹ ╹ │
# └─────────────────┘
# skip STL source files
define skipcpp
python

def getsources():
    sources = []
    for line in gdb.execute('info sources', to_string=True).splitlines():
        if line.startswith("/"):
            sources += [source.strip() for source in line.split(",")]
    return sources

def skipdir(dir):
    sources = getsources()
    for src in sources:
        if src.startswith(dir):
            gdb.execute('skip file %s' % src, to_string=True)

if 'c++' in gdb.execute('show language', to_string=True):
    skipdir("/usr")
end
end

define hookpost-run
    skipcpp
end
